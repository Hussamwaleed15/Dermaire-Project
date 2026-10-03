"""Read-only owner-scoped projections; no prose, legacy defaults or inferred traits."""
import json
import math
from datetime import datetime, timezone, timedelta
from app.models import (CheckIn, DailyContext, RoutineEntry, RoutineAdherence, Product,
                        Experiment, ExperimentEvaluation, Capture, Measurement)
from app.schemas.contextual_ai import ContextFact, SourceAvailability, SkinContext
from app.services.personal_skin_model import report_of, measurement_of, personal_skin_model, utc
from app.services.baseline import baseline_snapshot
from app.services.product_intelligence import routine_intelligence
from app.services.safety import evaluate_safety

LIMIT = 14
MAX_FACTS = 240
SOURCES = ('profile', 'checkin', 'baseline', 'daily_context', 'routine', 'adherence',
           'experiment', 'measurement', 'product_intelligence', 'personal_skin_model', 'safety')


def build_context(db, user, safety=None, now=None):
    now = utc(now or datetime.now(timezone.utc))
    facts, unknowns = [], []
    truncated = set()
    budget = 0

    def add(source, source_id, field, value, when=None, category='patient_reported',
            confidence=None, provenance=None, historical=False):
        nonlocal budget
        label = f'{source}.{field}'
        if value is None:
            unknowns.append(label)
            return
        timestamp = utc(when) if when else None
        if timestamp and timestamp > now:
            unknowns.append(label + ': future record excluded')
            return
        # Bound documents and provider payloads. Never replace truncation with a negative.
        size = len(json.dumps({'value':value,'provenance':provenance or {}},allow_nan=False))
        if len(facts) >= MAX_FACTS or size > 3000 or budget+size > 24000:
            truncated.add(source)
            unknowns.append(label + ': omitted by context budget')
            return
        budget += size
        freshness = ('historical_reference' if historical else 'unknown' if timestamp is None
                     else 'stale' if now-timestamp > timedelta(days=14) else 'fresh')
        if freshness == 'stale':
            unknowns.append(label + ': stale record does not establish current status')
        facts.append(ContextFact(id=f'f{len(facts):03d}', source=source, source_id=str(source_id),
            field=field, value=value, recorded_at=timestamp, category=category,
            freshness=freshness, confidence=confidence, provenance=provenance or {}))

    def recent(model, timestamp):
        rows = (db.query(model).filter(model.user_id == user.id, timestamp <= now)
                .order_by(timestamp.desc(), model.id.desc()).limit(LIMIT+1).all())
        if len(rows) > LIMIT:
            truncated.add({CheckIn:'checkin', RoutineEntry:'routine', RoutineAdherence:'adherence',
                Experiment:'experiment', ExperimentEvaluation:'experiment', Measurement:'measurement'}[model])
        return rows[:LIMIT]

    profile = user.profile_context or {}
    for field, value in [('skin_type', user.skin_type), ('primary_goals', profile.get('primary_goals'))]:
        add('profile', 'current', field, value, user.updated_at)
    # Sensitive disclosures are used by the existing safety/PI rules only. No demographics,
    # medications, hormonal fields, cycle day, identifiers, notes or images reach the model.
    unknowns.append('Sensitive traits and causes are not inferred; free text is not clinical evidence.')
    for row in recent(CheckIn, CheckIn.created_at):
        analysis = row.ai_vision_analysis or {}
        if (analysis.get('simulated') or analysis.get('measurement_source') in ('simulated','fake','mock')
                or analysis.get('azure_vision_status') in ('SIMULATED','SIMULATED_SUCCESS','FALLBACK_SIMULATED')):
            continue
        report = report_of(row)
        if report:
            values = report.model_dump(mode='json')
            for key in ('overall_change','symptoms','routine_status'):
                add('checkin', row.id, key, values[key] if key in report.model_fields_set else None, row.created_at,
                    provenance={'report':'user_reported', 'created_at':'server_recorded'})
            for key, value in (values.get('safety') or {}).items():
                add('checkin', row.id, 'safety.'+key, value, row.created_at)
            if report.safety is None:
                unknowns.append('checkin.safety: risk screen unknown')
        if measurement_of(row):
            for key in ('hydration','texture','redness'):
                source = analysis['measurement_source']
                add('checkin', row.id, key+'_tracking_score', getattr(row,key+'_score'), row.created_at,
                    category='patient_reported' if source == 'manual' else 'system_observed',
                    provenance={'measurement_source':source, 'clinical_measurement':False})

    baseline = baseline_snapshot(db,user.id, before=now)
    reference = db.query(CheckIn).filter(CheckIn.user_id == user.id,
        CheckIn.id.in_(baseline['checkin_ids'])).all()
    baseline_sources = sorted({(r.ai_vision_analysis or {}).get('measurement_source') for r in reference})
    for key in ('status','completed_days','required_days','checkin_ids','metrics'):
        if key == 'metrics' and len(baseline_sources)>1:
            unknowns.append('baseline.metrics: mixed measurement sources; comparable reference unknown')
            continue
        add('baseline','current',key,baseline[key],category='deterministic_derived',historical=True,
            provenance={'rule':'first_five_confirmed_distinct_days', 'clinical_clearance':False,
                        'measurement_sources':baseline_sources, 'checkin_ids':baseline['checkin_ids']})
    if baseline['status'] != 'ready':
        unknowns.append('baseline: insufficient confirmed days for comparison')

    contexts = (db.query(DailyContext).filter(DailyContext.user_id == user.id, DailyContext.date <= now.date())
                .order_by(DailyContext.date.desc(),DailyContext.id.desc()).limit(LIMIT+1).all())
    if len(contexts)>LIMIT:
        truncated.add('daily_context')
    for row in contexts[:LIMIT]:
        when = datetime.combine(row.date, datetime.min.time(),timezone.utc)
        if row.updated_at and utc(row.updated_at)>now:
            continue
        add('daily_context',row.id,'unusual_conditions',row.unusual_conditions,when,
            provenance={'date':row.date.isoformat(), 'mutable':True})

    products = {p.id:p for p in db.query(Product).filter_by(user_id=user.id).all()}
    entries = recent(RoutineEntry,RoutineEntry.updated_at)
    owned_entries = {e.id:e for e in db.query(RoutineEntry).filter_by(user_id=user.id).all()
                     if e.product_id in products}
    for row in entries:
        if row.id not in owned_entries or row.start_date>now.date():
            continue
        add('routine',row.id,'configuration',{'schedule':row.schedule, 'active':row.active,
            'product_status':products[row.product_id].status, 'start_date':row.start_date.isoformat(),
            'end_date':row.end_date.isoformat() if row.end_date else None}, row.updated_at,
            provenance={'source':row.source, 'actual_usage':'unknown'})
    for row in recent(RoutineAdherence,RoutineAdherence.created_at):
        if row.routine_entry_id in owned_entries and row.date<=now.date():
            add('adherence',row.id,'reported_use',{'date':row.date.isoformat(), 'slot':row.slot,
                'status':row.status,'routine_entry_id':row.routine_entry_id},
                datetime.combine(row.date,datetime.min.time(),timezone.utc),
                provenance={'source':row.source,'actual_usage':'unverified'})
    unknowns.append('adherence: missing slots are unknown; reported completion does not verify actual use.')

    experiments = {e.id:e for e in db.query(Experiment).filter_by(user_id=user.id,engine_version=2).all()
                   if e.product_id in products and e.routine_entry_id in owned_entries and utc(e.created_at)<=now}
    for row in recent(Experiment,Experiment.created_at):
        if row.id in experiments:
            add('experiment',row.id,'configuration',{'status':row.status,'target_days':row.target_days},
                row.created_at,provenance={'engine_version':2,'source':row.source})
    seen = set()
    for row in recent(ExperimentEvaluation,ExperimentEvaluation.created_at):
        outcome = row.result or {}
        if row.experiment_id in experiments and row.experiment_id not in seen and outcome.get('engine_version')==2:
            seen.add(row.experiment_id)
            label = outcome.get('label')
            if label in ('likely_associated_worsening','likely_associated_improvement','no_meaningful_change','insufficient_evidence','confounded_or_low_adherence'):
                add('experiment',row.id,'association_result',label,row.created_at,'deterministic_derived',
                    outcome.get('evidence_strength'), {'causality':'not_established','experiment_id':row.experiment_id})

    captures = {c.id:c for c in db.query(Capture).filter_by(user_id=user.id,state='accepted').all()
                if utc(c.received_at)<=now}
    for row in recent(Measurement,Measurement.measured_at):
        if row.capture_id not in captures:
            continue
        add('measurement',row.id,'availability',row.status,row.measured_at,'system_observed')
        if row.status != 'measured':
            unknowns.append('measurement.values: unavailable')
            continue
        for key in ('red_chromaticity_proxy','texture_contrast_proxy'):
            item = (row.results or {}).get(key,{})
            value = item.get('value')
            if (item.get('status')=='measured' and item.get('method_version')==row.algorithm_version
                    and item.get('source_capture_id')==row.capture_id and item.get('unit')=='fraction_0_to_1'
                    and type(value) in (int,float) and math.isfinite(value) and 0<=value<=1
                    and (row.quality_reference or {}).get('decision')=='accepted'):
                add('measurement',row.id,key,value,captures[row.capture_id].received_at,'system_observed',
                    'limited_image_proxy',{'algorithm':row.algorithm_version,'clinical_measurement':False})
            else:
                unknowns.append('measurement.'+key+': invalid or unavailable provenance')

    pi = routine_intelligence(db,user)
    for product in pi['products'][:LIMIT]:
        when = datetime.fromisoformat(product['updated_at']) if product['updated_at'] else None
        add('product_intelligence',product['product_id'],'completeness',product['data_completeness'],when,
            'deterministic_derived')
        for ingredient in product['ingredients'][:12]:
            evidence = ingredient['evidence']
            add('product_intelligence',product['product_id'],'reported_ingredient',ingredient['normalized_name'],when,
                'patient_reported' if evidence['type']=='user_reported' else 'system_observed',evidence['confidence'],
                {'source_type':evidence['type'],'verification':evidence['verification'],
                 'last_verified_at':evidence['last_verified_at'],'ingredient_ref':ingredient['ingredient_ref']})
        unknowns.extend('product_intelligence.'+u for u in product['unknowns'])
    if len(pi['products'])>LIMIT:
        truncated.add('product_intelligence')
    for warning in pi['warnings'][:12]:
        add('product_intelligence',warning['key'],'caution',warning['explanation'],category='deterministic_derived',
            confidence=warning['confidence'],provenance={'rule_source':warning['rule_source'],
                'medical_determination':False,'evidence':warning['evidence']})

    psm = personal_skin_model(db,user,now)
    add('personal_skin_model','current','status',psm.status,now,'deterministic_derived',psm.strength,
        {'version':psm.derivation_version,'sufficiency':psm.sufficiency.model_dump(mode='json')})
    for finding in (psm.changing+psm.stable+psm.associations)[:12]:
        latest = max((e.recorded_at for e in finding.evidence), default=None)
        add('personal_skin_model',finding.code+':'+finding.subject,'finding',finding.statement,latest,
            'deterministic_derived',finding.strength,{'rule':finding.rule,
                'evidence':[e.model_dump(mode='json') for e in finding.evidence], 'causality':'not_established'})
    unknowns.extend(psm.sufficiency.reasons)
    safety = safety or evaluate_safety(db,user,now)
    add('safety','current','status',safety.status,now,'deterministic_derived',
        provenance={'version':safety.engine_version,'risk_screen_complete':safety.evidence_status['risk_screen_complete']})
    for reason in safety.reasons[:12]:
        add('safety',reason.code,'reason',reason.summary,now,'deterministic_derived',
            provenance={'evidence':reason.evidence,'state':reason.state})
    availability = {}
    for source in SOURCES:
        included = sum(f.source==source for f in facts)
        partial = source in truncated or any(u.startswith(source+'.') or u.startswith(source+':') for u in unknowns)
        availability[source] = SourceAvailability(state='missing' if not included else 'partial' if partial else 'available',
            included=included,truncated=source in truncated)
        if not included:
            unknowns.append(source+': no eligible facts; absence is not negative evidence')
    unknowns.extend(['Tracking associations do not establish cause or diagnosis.',
                     'Freshness uses a 14-day engineering window, not clinical clearance.'])
    return SkinContext(built_at=now,facts=facts,sources=availability,
        unknowns=sorted(set(unknowns)),safety=safety)
