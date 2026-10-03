"""Safety first, evidence selection second, canonical backend rendering last."""
import json
from app.core.config import settings
from app.schemas.contextual_ai import AssistanceResponse, ProviderMetadata, ProviderSelection, InferredPoint
from app.services.context_builder import build_context
from app.services.contextual_provider import get_contextual_provider
from app.services.safety import evaluate_safety
from app.services.azure_safety import RED_FLAG_KEYWORDS

STEPS = {
    'record_checkin':'Record a fresh structured check-in including symptoms and the safety screen; unanswered fields remain unknown.',
    'record_adherence':'Record completed or skipped routine slots; missing entries do not mean skipped use.',
    'review_product_evidence':'Review documented ingredient sources and cautions; incomplete facts cannot establish product safety.',
    'ask_doctor':'Ask your doctor which reported changes need assessment and what information to keep tracking.',
    'seek_guidance':'If symptoms concern you or worsen, seek medical guidance. Tracking cannot rule out a health risk.',
}
INTRO = {
    'changes':'Here is the available tracking evidence. Reports and image proxies describe observations; they do not establish a diagnosis.',
    'worsening':'The available records cannot establish why your skin might be worse. Associations do not establish cause.',
    'tracking':'Keep tracking structured symptoms, reported routine use and relevant daily context. Missing information remains unknown.',
    'routine':'Routine configuration and self-reported adherence are separate. These records cannot verify actual use or establish consistency for unrecorded slots.',
    'doctor_questions':'Ask your doctor which documented observations need assessment; this assistant cannot diagnose or prescribe.',
    'unsupported':'I can help review recorded changes, routine logs, tracking gaps or questions for your doctor. I cannot diagnose, prescribe, infer sensitive traits or answer unsupported medical questions.',
}
SOURCE_TASKS = {
    'changes':{'checkin','baseline','measurement','personal_skin_model','experiment'},
    'worsening':{'checkin','daily_context','personal_skin_model','experiment','product_intelligence'},
    'tracking':{'checkin','baseline','routine','adherence','personal_skin_model'},
    'routine':{'routine','adherence'},
    'doctor_questions':{'checkin','personal_skin_model','product_intelligence'},
    'unsupported':set(),
}

def resolve_task(payload):
    # Questions are requests, never clinical evidence. Explicit tasks narrow prose to
    # supported operations. Raw questions never reach the provider.
    if payload.task:
        return payload.task
    question=payload.message.casefold()
    if any(t in question for t in ('diagnos','prescri','dose','pregnan','gender','cancer',
            'breathing','swelling','emergency','تشخيص','جرعة','حامل','سرطان','تنفس','تورم')):
        return 'unsupported'
    groups=[('doctor_questions',('ask my doctor','ask the doctor','أسأل الدكتور','اسأل الدكتور','طبيب')),
            ('routine',('routine consistent','my routine','روتيني','الروتين')),
            ('worsening',('why might','why is','worse','أسوأ','اسوء','ساءت')),
            ('changes',('what changed','changes','إيه اتغير','ايه اتغير','تغير')),
            ('tracking',('keep tracking','what should i track','أتابع','اتابع','tracking'))]
    return next((task for task,tokens in groups if any(t in question for t in tokens)),'unsupported')

def provider_metadata():
    configured=settings.is_openai_live and bool(settings.AZURE_OPENAI_DEPLOYMENT_NAME.strip())
    enabled=settings.CONTEXTUAL_AI_ENABLED
    return ProviderMetadata(provider='azure_openai' if configured else None,
        model=settings.AZURE_OPENAI_DEPLOYMENT_NAME if configured else None,configured=configured,invoked=False,
        availability='not_invoked' if configured and enabled else 'disabled' if not enabled else 'unconfigured',
        mode='degraded',reason='disabled' if not enabled else 'provider_unconfigured' if not configured else None)

def validate_selection(raw,context,task,eligible,inference_ids):
    if not isinstance(raw,str) or len(raw)>8000:
        raise ValueError('Invalid provider envelope')
    def unique_object(pairs):
        result={}
        for key,value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key]=value
        return result
    def invalid_constant(_):
        raise ValueError('Nonfinite JSON')
    plan=ProviderSelection.model_validate(json.loads(raw,object_pairs_hook=unique_object,parse_constant=invalid_constant))
    if plan.task!=task or plan.escalation!=context.safety.status:
        raise ValueError('Task or safety mismatch')
    if len(plan.fact_ids)!=len(set(plan.fact_ids)) or not set(plan.fact_ids)<=set(eligible):
        raise ValueError('Unknown, stale or ineligible citation')
    if len(plan.next_steps)!=len(set(plan.next_steps)):
        raise ValueError('Repeated steps')
    for inference in plan.inferred_points:
        if (not inference_ids or not set(inference.evidence_ids)<=set(inference_ids)
                or not set(inference.evidence_ids)<=set(plan.fact_ids)):
            raise ValueError('Unsupported inference')
    return plan

def assist(db,user,payload,provider=None,now=None):
    safety=evaluate_safety(db,user,now)
    task=resolve_task(payload)
    metadata=provider_metadata()
    if safety.status in ('urgent','doctor_review'):
        metadata.mode='safety_guard'
        metadata.reason='safety_precedence'
        return AssistanceResponse(task=task,message=safety.guidance,grounded_facts_used=[],
            inferred_points=[],uncertainties=safety.limitations,next_steps=[safety.guidance],
            escalation=safety.status,authoritative_safety=safety,metadata=metadata)
    if any(flag in payload.message.casefold() for flag in RED_FLAG_KEYWORDS):
        # Request-level precaution only, never promote prose to structured symptoms
        # or mutate the canonical engine state. Retains the legacy chat safety warning.
        metadata.mode='narrowed'
        metadata.reason='question_safety_caution'
        message=('If you are experiencing breathing difficulty, severe swelling, severe pain '
                 'or a rapidly spreading reaction, contact emergency services now. '
                 'إذا كنت تعاني من صعوبة تنفس أو تورم حاد، توجه للطوارئ فوراً. '
                 'Your question has not been converted into clinical facts. Record a structured '
                 'safety check-in when safe; the stored assessment cannot rule out current risk.')
        return AssistanceResponse(task='unsupported',message=message,grounded_facts_used=[],
            inferred_points=[],uncertainties=['Symptoms mentioned in prose are not confirmed structured evidence.'],
            next_steps=[message],escalation=safety.status,authoritative_safety=safety,metadata=metadata)
    context=build_context(db,user,safety,now)
    eligible=[f.id for f in context.facts if f.source in SOURCE_TASKS[task]
              and f.freshness in ('fresh','historical_reference')]
    inference_ids=[f.id for f in context.facts if f.id in eligible and f.source=='routine'
                   and f.value.get('active') and f.value.get('product_status')=='active']
    if context.sources['adherence'].state!='missing' or task not in ('routine','tracking'):
        inference_ids=[]
    selected_ids=eligible[:8]
    next_steps=['record_adherence','record_checkin','seek_guidance'] if task=='routine' else ['record_checkin','ask_doctor','seek_guidance']
    inferences=[]
    if task=='unsupported':
        metadata.mode='narrowed'
        metadata.reason='unsupported_question'
    elif metadata.configured and settings.CONTEXTUAL_AI_ENABLED:
        metadata.invoked=True
        try:
            raw=(provider or get_contextual_provider()).generate(context,task,eligible,inference_ids)
            plan=validate_selection(raw,context,task,eligible,inference_ids)
            selected_ids=plan.fact_ids
            next_steps=plan.next_steps
            inferences=[InferredPoint(statement='The available routine configuration may be useful for checking tracking gaps; without eligible adherence records, consistency and actual use remain unknown.',
                evidence_ids=i.evidence_ids) for i in plan.inferred_points]
            metadata.mode='grounded_ai'
            metadata.availability='available'
            metadata.reason=None
        except Exception:
            metadata.availability='failed'
            metadata.reason='provider_failure_or_invalid_output'
    facts=[next(f for f in context.facts if f.id==key) for key in selected_ids]
    sentences=[INTRO[task]]
    if metadata.mode=='degraded':
        sentences.append('AI generation is unavailable; this is a deterministic summary of recorded evidence.')
    for fact in facts:
        sentences.append(f'{fact.category} | {fact.source}.{fact.field} ({fact.freshness}): '
                         +json.dumps(fact.value,ensure_ascii=False,allow_nan=False)+'.')
    if not facts and task!='unsupported':
        sentences.append('No eligible current facts for this question; your current situation remains unknown.')
    sentences.append(safety.guidance)
    steps=[STEPS[key] for key in next_steps]
    if STEPS['seek_guidance'] not in steps:
        steps.append(STEPS['seek_guidance'])
    return AssistanceResponse(task=task,message='\n'.join(sentences),grounded_facts_used=facts,
        inferred_points=inferences,uncertainties=context.unknowns,next_steps=steps,
        escalation=safety.status,authoritative_safety=safety,metadata=metadata)
