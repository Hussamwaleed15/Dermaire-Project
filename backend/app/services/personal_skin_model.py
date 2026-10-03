"""Pure read-time rules; no LLM, population reference or persisted conclusions."""
from datetime import datetime, timezone, timedelta
from statistics import mean
from pydantic import ValidationError
from app.models import CheckIn, DailyContext, Product
from app.schemas import CheckInReport
from app.schemas.personal_skin_model import Evidence, Finding, PersonalSkinModel
from app.services.baseline import baseline_snapshot, confirmed_measurement


def utc(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def report_of(row):
    obs = row.observation or {}
    provenance = obs.get('provenance', {})
    if (obs.get('schema_version') != 1 or provenance.get('report') != 'user_reported'
            or provenance.get('created_at') != 'server_recorded'):
        return None
    try:
        return CheckInReport.model_validate(obs.get('user_reported'))
    except ValidationError:
        return None


def measurement_of(row):
    analysis = row.ai_vision_analysis or {}
    return confirmed_measurement(row) and not analysis.get('simulated') and analysis.get('azure_vision_status') not in ('SIMULATED', 'SIMULATED_SUCCESS', 'FALLBACK_SIMULATED')


def evidence(row, fields, kind='user_reported', source='checkin'):
    return Evidence(source=source, id=row.id, fields=fields,
                    recorded_at=utc(row.updated_at if source in ('daily_context', 'profile', 'product') else row.created_at), kind=kind)


def daily_first(rows):
    selected = {}
    for row in rows:
        selected.setdefault(utc(row.created_at).date(), row)
    return list(selected.values())


def personal_skin_model(db, user, now=None):
    now = utc(now or datetime.now(timezone.utc))
    rows = db.query(CheckIn).filter_by(user_id=user.id).order_by(CheckIn.created_at, CheckIn.id).all()
    # Future timestamps and simulated flags are never evidence, including reports.
    valid = [r for r in rows if utc(r.created_at) <= now and not (r.ai_vision_analysis or {}).get('simulated')
             and (r.ai_vision_analysis or {}).get('azure_vision_status') not in ('SIMULATED', 'SIMULATED_SUCCESS', 'FALLBACK_SIMULATED')
             and (r.ai_vision_analysis or {}).get('measurement_source') not in ('simulated', 'fake', 'mock')
             and (measurement_of(r) or report_of(r))]
    reports = daily_first([r for r in valid if report_of(r) and utc(r.created_at) >= now - timedelta(days=28)])
    measurements = daily_first([r for r in valid if measurement_of(r)])
    baseline = baseline_snapshot(db, user.id, before=now)
    changing, stable, associations, reasons = [], [], [], []
    reference = [r for r in measurements if r.id in baseline['checkin_ids']]
    if baseline['status'] == 'ready' and len(reference) == 5:
        sources = {(r.ai_vision_analysis or {}).get('measurement_source') for r in reference}
        if len(sources) == 1:
            source = next(iter(sources))
            recent = daily_first([r for r in valid if measurement_of(r)
                and utc(r.created_at).date() > utc(reference[-1].created_at).date()
                and utc(r.created_at) >= now - timedelta(days=14)
                and (r.ai_vision_analysis or {}).get('measurement_source') == source])[-5:]
            if len(recent) >= 3:
                for metric in ('hydration', 'texture', 'redness'):
                    ref = baseline['metrics'][metric]['mean']
                    threshold = max(10.0, 2 * baseline['metrics'][metric]['standard_deviation'])
                    value = mean(getattr(r, metric + '_score') for r in recent)
                    delta = value - ref
                    agreement = sum((getattr(r, metric + '_score') - ref) * delta > 0 for r in recent)
                    changed = abs(delta) >= threshold and agreement / len(recent) >= 2/3
                    # A large but inconsistent difference is uncertainty, not stability.
                    if abs(delta) >= threshold and not changed:
                        reasons.append(metric + ': inconsistent recent measurements')
                        continue
                    finding = Finding(code='measurement_change' if changed else 'measurement_stable', subject=metric,
                        direction=('increased' if delta > 0 else 'decreased') if changed else 'stable',
                        statement=f'{metric.capitalize()} tracking scores appear ' + (('higher' if delta > 0 else 'lower') + ' than your own baseline.' if changed else 'within the tracking change threshold of your own baseline.'),
                        strength='moderate', rule='same-source-baseline-5_recent-3_threshold-max-10-2sd_agreement-2of3',
                        evidence=[evidence(r, [metric + '_score'], 'image_proxy' if source == 'image_proxy' else 'user_reported') for r in reference + recent],
                        reference_value=round(ref, 2), recent_value=round(value, 2), threshold=round(threshold, 2))
                    (changing if changed else stable).append(finding)
            else:
                reasons.append('Need three recent distinct measurement days after the baseline, using the same measurement source.')
        else:
            reasons.append('Baseline mixes measurement sources; no comparable measurement conclusion.')
    else:
        reasons.append('Five eligible baseline days are required for measurement comparison.')
    if len(reports) >= 6 and utc(reports[-3].created_at) >= now - timedelta(days=14):
        early, recent = reports[:3], reports[-3:]
        for symptom in ('redness', 'dryness', 'itching', 'burning', 'breakouts', 'sensitivity', 'texture'):
            before = sum(symptom in report_of(r).symptoms for r in early)
            after = sum(symptom in report_of(r).symptoms for r in recent)
            if abs(after - before) >= 2:
                changing.append(Finding(code='symptom_frequency_change', subject=symptom,
                    direction='increased' if after > before else 'decreased',
                    statement=f'{symptom.capitalize()} was reported on {after} of the latest three report days versus {before} of the first three in the last 28 days.',
                    strength='limited', rule='report-6-days_frequency-difference-2of3',
                    evidence=[evidence(r, ['observation.user_reported.symptoms']) for r in early + recent], reference_value=before, recent_value=after, threshold=2))
        changes = [report_of(r).overall_change for r in recent]
        if len(set(changes)) == 1:
            direction = changes[0]
            finding = Finding(code='recent_self_report', subject='overall_change', direction=direction,
                statement=f'You reported {direction} skin on the latest three report days. This is a self-reported trend.',
                strength='limited', rule='report-6-days_latest-3-agree', evidence=[evidence(r, ['observation.user_reported.overall_change']) for r in recent])
            (stable if direction == 'same' else changing).append(finding)
    else:
        reasons.append('Need six distinct report days in 28 days, including three in 14 days, for a report trend.')
    contexts = {c.date: c for c in db.query(DailyContext).filter_by(user_id=user.id).all() if c.date <= now.date() and utc(c.updated_at) <= now}
    groups = {True: [], False: []}
    for row in reports:
        context = contexts.get(utc(row.created_at).date())
        if context and context.unusual_conditions in (True, False):
            groups[context.unusual_conditions].append((row, context))
    if all(len(g) >= 3 for g in groups.values()) and all(utc(r.created_at) >= now - timedelta(days=14) for g in groups.values() for r, _ in g):
        rates = {k: mean(report_of(r).overall_change == 'worse' for r, _ in g) for k, g in groups.items()}
        if rates[True] - rates[False] >= 2/3:
            pairs = groups[True] + groups[False]
            associations.append(Finding(code='context_association', subject='unusual_conditions', direction='associated',
                statement='Worse self-reports were more frequent on days with reported unusual conditions. This association does not establish cause.',
                strength='limited', rule='context-paired-3-days-each_worse-rate-gap-2of3',
                evidence=[item for r, c in pairs for item in (evidence(r, ['observation.user_reported.overall_change']), evidence(c, ['unusual_conditions', 'date'], source='daily_context'))],
                reference_value=round(rates[False], 3), recent_value=round(rates[True], 3), threshold=2/3))
    else:
        reasons.append('Context association requires three paired report days with and three without explicitly reported unusual conditions.')
    latest = max((utc(r.created_at) for r in valid), default=None)
    age = (now.date() - latest.date()).days if latest else None
    stale = age is not None and age > 14
    if stale:
        # Historical evidence remains discoverable through history; no stale conclusion presented as current.
        changing, stable, associations = [], [], []
        reasons.append('Latest confirmed skin evidence is older than 14 days; current trajectory is unknown.')
    state = 'no_data' if not valid else 'stale' if stale else 'meaningful_change' if changing else 'no_meaningful_change' if stable else 'insufficient_data'
    profile_context = user.profile_context or {}
    goals = profile_context.get('primary_goals') or []
    products = db.query(Product).filter_by(user_id=user.id).order_by(Product.id).all()
    model = PersonalSkinModel(generated_at=now, status=state,
        statement={'no_data': 'No authoritative skin observations yet; start tracking.', 'stale': 'Current trajectory is unknown; record a fresh check-in.', 'meaningful_change': 'Tracking evidence suggests change; review the structured findings.', 'no_meaningful_change': 'No meaningful change detected; continue tracking.', 'insufficient_data': 'Insufficient comparable evidence; continue tracking.'}[state],
        strength='moderate' if any(f.strength == 'moderate' for f in changing + stable) else 'limited' if changing or stable else 'none',
        changing=changing, stable=stable, associations=associations,
        sufficiency=dict(confirmed_days=len(daily_first(valid)), report_days=len(reports), measurement_days=len(measurements), excluded_checkins=len(rows)-len(valid), latest_evidence_at=latest, age_days=age,
            recency='missing' if latest is None else 'stale' if stale else 'fresh', baseline_ready=baseline['status']=='ready', reasons=reasons),
        profile=dict(available=user.profile_context is not None, primary_goals=goals,
            evidence=[evidence(user, ['profile_context.primary_goals'], source='profile')] if goals else []),
        products=[dict(id=p.id, status=p.status, evidence=evidence(p, ['status'], source='product')) for p in products],
        limitations=['Not diagnosis or medical certainty; tracking thresholds are engineering rules.',
            'Configured routine and self-reported adherence are distinct; neither verifies application.',
            'Products describe current inventory, not verified exposure or product effects.',
            'Profile goals supply orientation only; sensitive profile attributes and cycle day are excluded from derivation and output.',
            'Context is mutable user-reported state joined by owner and UTC date, not a historical snapshot.',
            'Image-property proxies are not clinical measurements; sources are never mixed for comparison.',
            'Report symptoms record presence, not severity; free text and photos are not interpreted.'])



    from app.services.personal_skin_model_v2 import enrich
    return enrich(db, user, model, now, reports, contexts)
