"""Additive patient projection; no AI, source mutation, or raw private snapshots."""
from datetime import datetime, timedelta
from statistics import mean
from app.models import (Product, RoutineEntry, RoutineAdherence, Experiment, ExperimentEvaluation,
                        Capture, Measurement, ClinicalNote, DoctorReviewAction, DoctorPatientAccess)
from app.schemas.personal_skin_model import Finding, Evidence, IntegratedSources
from app.services.personal_skin_model import utc, report_of, evidence
from app.services.product_intelligence import routine_intelligence
from app.services.measurement import response, compare
from app.services.baseline import baseline_snapshot
from app.services.safety import evaluate_safety, RANK


def enrich(db, user, model, now, reports, contexts):
    def fresh(when):
        when = utc(when) if when else None
        return {'latest_at': when, 'age_days': (now.date()-when.date()).days if when else None,
                'state': 'missing' if when is None else 'stale' if now-when > timedelta(days=14) else 'fresh'}

    def rows(cls, timestamp, owner='user_id'):
        return db.query(cls).filter(getattr(cls, owner) == user.id, timestamp <= now).order_by(timestamp, cls.id).all()

    products = {p.id: p for p in rows(Product, Product.created_at)}
    entries = rows(RoutineEntry, RoutineEntry.created_at)
    current = [e for e in entries if e.active and e.start_date <= now.date()
               and e.product_id in products and products[e.product_id].status == 'active']
    logs = [l for l in rows(RoutineAdherence, RoutineAdherence.created_at)
            if l.date <= now.date() and l.routine_entry_id in {e.id for e in entries}]
    recent = [l for l in logs if now.date()-timedelta(days=14) <= l.date < now.date()]
    expected = sum((2 if e.schedule == 'BOTH' else 1)*max(0, (now.date()-max(
        now.date()-timedelta(days=14), e.start_date, utc(e.updated_at).date()+timedelta(days=1))).days) for e in current)
    matching = [l for l in recent for e in current if l.routine_entry_id == e.id
                and l.date > utc(e.updated_at).date() and l.date >= e.start_date
                and l.slot in (('AM', 'PM') if e.schedule == 'BOTH' else (e.schedule,))
                and all(l.configuration_snapshot.get(k) == getattr(e, k) for k in ('product_id', 'schedule', 'frequency', 'active'))]
    completed = sum(l.status == 'completed' for l in matching)
    consistency = {'window_days': 14, 'expected_known_slots': expected, 'reported_slots': len(matching),
        'completed_slots': completed, 'unknown_slots': max(0, expected-len(matching)),
        'completed_fraction': completed/expected if expected else None,
        'category': 'deterministic_derived', 'source': 'user_reported',
        'freshness': fresh(max((l.created_at for l in logs), default=None)),
        'caveats': ['Self-reported application is not verified exposure.',
                    'Before latest configuration edit, expectations are unknown; current day excluded.']}
    routine = {'category': 'patient_reported', 'configured': [
        {'id': e.id, 'product_id': e.product_id, 'schedule': e.schedule, 'frequency': e.frequency,
         'start_date': e.start_date, 'freshness': fresh(e.updated_at)} for e in current], 'adherence': consistency,
        'historical_snapshots': [{'category': 'patient_reported', 'id': l.id, 'entry_id': l.routine_entry_id, 'date': l.date, 'slot': l.slot,
            'status': l.status, 'configuration': {k: l.configuration_snapshot.get(k) for k in
            ('id', 'product_id', 'schedule', 'frequency', 'active', 'start_date', 'end_date')},
            'recorded_at': l.created_at} for l in logs]}
    pi = routine_intelligence(db, user)
    for product in pi['products']:
        product['freshness'] = fresh(datetime.fromisoformat(product['updated_at']) if product['updated_at'] else None)
        for ingredient in product['ingredients']:
            ingredient['category'] = ('patient_reported' if ingredient['evidence']['type'] == 'user_reported' else 'system_observed')
        product['category'] = 'deterministic_derived'
    pi['category'] = 'deterministic_derived'
    evaluations = rows(ExperimentEvaluation, ExperimentEvaluation.created_at)
    experiments = []
    for e in rows(Experiment, Experiment.created_at):
        if e.engine_version != 2:
            continue
        ev = next((v for v in reversed(evaluations) if v.experiment_id == e.id
                   and (v.result or {}).get('engine_version') == 2), None)
        result = ev.result if ev else {}
        comp = result.get('comparison', {})
        counts = [comp.get(k) for k in ('baseline_days', 'experiment_days')]
        evidence_count = sum(counts) if all(type(c) is int and c >= 0 for c in counts) else None
        evaluation = None if not ev else {'id': ev.id, 'category': 'deterministic_derived',
            'label': result.get('label'), 'strength': result.get('evidence_strength'), 'confidence': result.get('evidence_strength'),
            'comparison': {k: comp.get(k) for k in ('start', 'end_exclusive', 'strategy', 'baseline_days', 'experiment_days', 'measurement_source')},
            'adherence': {k: result.get('adherence', {}).get(k) for k in
                ('expected_status', 'expected_slots', 'reported_slots', 'followed_slots', 'coverage', 'followed_fraction')},
            'confounders': {k: result.get('confounders', {}).get(k) for k in
                ('unusual_days', 'baseline_unusual_conditions', 'routine_changed_after_activation', 'product_changed_after_activation',
                 'baseline_inconsistent_routine_reports', 'inconsistent_routine_reports')},
            'evaluation_window': {'start': e.start_date, 'elapsed_days': result.get('coverage', {}).get('elapsed_days')},
            'evidence_count': evidence_count,
            'freshness': fresh(ev.created_at), 'statement': 'Experiment outcome is an association, not evidence of cause.',
            'caveats': ['Frozen evaluation; subsequent source edits do not reevaluate it.', 'Unreported confounding remains unknown.']}
        experiments.append({'id': e.id, 'category': 'patient_reported', 'status': e.status,
            'change_type': (e.intervention or {}).get('type'), 'product_id': e.product_id,
            'start_date': e.start_date, 'target_days': e.target_days, 'stopped_at': e.stopped_at,
            'baseline_window': {k: (e.definition_snapshot or {}).get('baseline', {}).get(k) for k in ('start', 'end_exclusive')},
            'evaluation': evaluation})
    captures = {c.id: c for c in rows(Capture, Capture.received_at) if c.state == 'accepted'}
    measured = [m for m in rows(Measurement, Measurement.measured_at) if m.capture_id in captures]
    measured.sort(key=lambda m: (utc(captures[m.capture_id].received_at), m.capture_id, m.id))
    latest = measured[-1] if measured else None
    measurement = {'category': 'deterministic_derived', 'latest': response(latest) if latest else None,
                   'freshness': fresh(captures[latest.capture_id].received_at if latest else None), 'trend_status': 'unknown'}
    if latest:
        previous = next((m for m in reversed(measured[:-1]) if m.status == 'measured'
                         and m.algorithm_version == latest.algorithm_version), None)
        comparison = compare(latest, previous)
        measurement['latest']['comparison'] = comparison
        measurement['trend_status'] = comparison['state'] if measurement['freshness']['state'] == 'fresh' else 'stale'
    latest_measured = next((m for m in reversed(measured) if m.status == 'measured'), None)
    measurement['latest_measured'] = ({'id': latest_measured.id, 'capture_id': latest_measured.capture_id,
        'algorithm_version': latest_measured.algorithm_version, 'metrics': latest_measured.results,
        'quality_reference': latest_measured.quality_reference, 'received_at': captures[latest_measured.capture_id].received_at,
        'measured_at': latest_measured.measured_at, 'freshness': fresh(captures[latest_measured.capture_id].received_at)}
        if latest_measured else None)
    eligible_proxy = [m for m in measured if m.status == 'measured']
    model.sufficiency.proxy_measurement_days = len({utc(captures[m.capture_id].received_at).date() for m in eligible_proxy})
    model.sufficiency.latest_proxy_measurement_at = utc(latest_measured.measured_at) if latest_measured else None
    if latest_measured and model.status in ('no_data', 'stale'):
        proxy_freshness = fresh(captures[latest_measured.capture_id].received_at)
        if proxy_freshness['state'] == 'fresh':
            model.status = 'insufficient_data'
            model.statement = 'Measured image proxies are available; insufficient evidence for an overall skin trajectory. Continue tracking.'
        elif model.status == 'no_data':
            model.status = 'stale'
            model.statement = 'Historical image proxies are stale; current skin trajectory is unknown.'
    safety = evaluate_safety(db, user, now)
    model.safety = safety
    reviews = rows(DoctorReviewAction, DoctorReviewAction.created_at, 'patient_id')
    reviews.sort(key=lambda r: r.sequence)
    def decision(r):
        return {'id': r.id, 'category': 'clinician_authored', 'state': r.state,
            'recommendation': r.recommendation, 'rationale': r.rationale, 'recorded_at': r.created_at,
            'freshness': fresh(r.created_at), 'diverges_from_current_safety': bool(r.recommendation and r.recommendation != safety.status),
            'lower_than_current_safety': bool(r.recommendation and RANK[r.recommendation] < RANK[safety.status])}
    last = reviews[-1] if reviews else None
    grants = rows(DoctorPatientAccess, DoctorPatientAccess.created_at, 'patient_id')
    doctor = {'category': 'clinician_authored', 'state': last.state if last else 'pending' if any(
        g.status in ('active', 'pending') and utc(g.expires_at) > now for g in grants) else 'not_requested',
        'freshness': fresh(last.created_at if last else None),
        'current_decision': decision(last) if last and last.patient_visible else None,
        'history': [decision(r) for r in reviews if r.patient_visible],
        'notes': [{'id': n.id, 'category': 'clinician_authored', 'content': n.content, 'priority': n.priority,
            'follow_up': n.follow_up, 'recorded_at': n.created_at, 'freshness': fresh(n.created_at)}
            for n in rows(ClinicalNote, ClinicalNote.created_at, 'patient_id') if n.patient_visible],
        'safety_precedence': 'Safety Engine is preserved independently of clinician recommendations.'}
    groups = {True: [], False: []}
    for r in reports:
        if utc(r.created_at) < now-timedelta(days=14):
            continue
        day_logs = [l for l in recent if l.date == utc(r.created_at).date() and l.configuration_snapshot.get('active') is True]
        statuses = {l.status for l in day_logs}
        if len(statuses) == 1:
            groups['completed' in statuses].append((r, day_logs))
    if all(len(g) >= 3 for g in groups.values()):
        rates = {k: mean(report_of(r).overall_change == 'worse' for r, _ in g) for k, g in groups.items()}
        if abs(rates[True]-rates[False]) >= 2/3:
            refs = [evidence(r, ['observation.user_reported.overall_change']) for g in groups.values() for r, _ in g]
            refs += [Evidence(source='adherence', id=l.id, fields=['status', 'configuration_snapshot'],
                recorded_at=utc(l.created_at), kind='user_reported') for g in groups.values() for _, ls in g for l in ls]
            model.associations.append(Finding(code='adherence_association', subject='reported_adherence', direction='associated',
                statement='Worse self-reports differed between days with reported completed and skipped slots. This association does not establish cause.',
                strength='limited', rule='adherence-paired-3-days-each_worse-rate-gap-2of3', evidence=refs,
                caveats=['Incomplete application reporting and unreported confounding remain unknown.', 'Product effects are not inferred.']))
    for f in model.changing + model.stable + model.associations:
        f.evidence_count = len({(v.source, v.id) for v in f.evidence})
        f.latest_evidence_at = max((v.recorded_at for v in f.evidence), default=None)
        f.confidence = f.strength
        f.caveats += ['Observational tracking only; no diagnosis or causal conclusion.']
    model.sources = {'profile': {'category': 'patient_reported', 'skin_type': user.skin_type,
        'skin_concerns': user.skin_concerns, 'freshness': fresh(user.updated_at)},
        'history': {'category': 'patient_reported', 'freshness': fresh(model.sufficiency.latest_evidence_at),
            'recent_reports': [{'id': r.id, 'recorded_at': r.created_at, 'report': {k: report_of(r).model_dump(mode='json').get(k)
                              for k in ('overall_change', 'symptoms', 'routine_status')}, 'freshness': fresh(r.created_at)} for r in reports]},
        'baseline': {'category': 'deterministic_derived', 'snapshot': baseline_snapshot(db, user.id, before=now),
                     'caveats': ['Personal historical reference, never clinical clearance.']},
        'daily_context': {'category': 'patient_reported', 'days': [{'id': c.id, 'date': c.date,
            'unusual_conditions': c.unusual_conditions, 'freshness': fresh(c.updated_at)} for c in contexts.values() if utc(c.updated_at) <= now],
            'caveats': ['Mutable current snapshots; sensitive cycle context excluded.']},
        'routine': routine, 'experiments': experiments, 'measurements': measurement,
        'product_intelligence': pi, 'safety': {**safety.model_dump(mode='json'), 'category': 'deterministic_derived'}, 'doctor': doctor}
    model.unknowns = list(model.sufficiency.reasons) + ['Actual exposure and causation are unknown.', 'Unreported sensitive disclosures remain omitted.']
    if not latest or measurement['trend_status'] != 'comparable':
        model.unknowns.append('Measurement trend is unknown or non-comparable; missing capture dimensions prohibit deltas.')
    if pi['data_completeness'] != 'complete':
        model.unknowns.append('Incomplete ingredients and unknown concentrations do not establish safety.')
    for product in pi['products']:
        if any(i['concentration_state'] == 'unknown' for i in product['ingredients']):
            model.unknowns.append('Product '+product['product_id']+': ingredient concentration is unknown.')
    for source, state in (('profile', fresh(user.updated_at)), ('routine', consistency['freshness']),
                          ('measurement', measurement['freshness']), ('doctor', doctor['freshness'])):
        if state['state'] == 'stale':
            model.unknowns.append(source+': stale input does not establish current condition.')
    model.summaries = {'current_skin_state': model.statement, 'recent_changes': [f.statement for f in model.changing],
        'routine_consistency': consistency, 'relevant_factors': {'products': [{'id': p['product_id'], 'data_completeness': p['data_completeness'], 'unknowns': p['unknowns']} for p in pi['products']], 'warnings': pi['warnings']},
        'experiment_learnings': [e['evaluation'] for e in experiments if e['evaluation'] and e['evaluation']['freshness']['state'] == 'fresh'],
        'measurement_trend_status': measurement['trend_status'], 'safety_status': safety.status,
        'safety_guidance': safety.guidance, 'doctor_review_status': doctor['state'], 'remaining_unknowns': model.unknowns}
    def timestamps(value):
        if isinstance(value, datetime):
            return utc(value)
        if isinstance(value, dict):
            return {k: timestamps(v) for k, v in value.items()}
        if isinstance(value, list):
            return [timestamps(v) for v in value]
        return value
    model.sources = IntegratedSources.model_validate(timestamps(model.sources))
    model.summaries = timestamps(model.summaries)
    return model
