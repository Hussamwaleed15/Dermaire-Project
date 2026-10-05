# Real AI / Vision integration

## Contracts and authority
- Vision previously had a no-op live branch. All tracking scores remain local Pillow RGB/variance proxies, never clinical measurements.
- Vision now optionally POSTs caller-supplied image bytes to Image Analysis 4.0, api-version 2024-02-01, features=tags. General tags are discarded, never promoted to diagnoses, skin scores or clinician evidence. Stored provider metadata reports disabled/available/degraded independently of local score success.
- Chat and contextual assistance use AzureContextualProvider, not legacy free-prose AzureOpenAIService. The provider selects eligible fact IDs and canonical next-step IDs in JSON. Backend validation rejects malformed, incomplete, stale, invented or safety-mismatching output and renders canonical prose. Safety Engine urgent/doctor_review paths and clinician decisions precede provider invocation.
- Content Safety is a supplementary adapter, not a medical triage engine. It is not used to override contextual assistance or clinician state. Its SDK categories_analysis contract is corrected; outages return explicit degraded metadata. Local red flags execute first.
- Legacy AzureOpenAIService is not the active chat route. It now has bounded timeout/no retries and rejects truncated or empty responses; do not reconnect it to clinical chat without authoritative safety/context guards.

## Configuration
Existing contracts: AZURE_VISION_ENDPOINT + AZURE_VISION_KEY; AZURE_OPENAI_ENDPOINT + AZURE_OPENAI_API_KEY + AZURE_OPENAI_DEPLOYMENT_NAME + AZURE_OPENAI_API_VERSION; AZURE_CONTENT_SAFETY_ENDPOINT + AZURE_CONTENT_SAFETY_KEY.
Endpoints must be HTTPS resource base URLs without paths, embedded credentials, queries or fragments. Partial pairs prevent startup. AZURE_VISION_ENABLED=false and CONTEXTUAL_AI_ENABLED=false are defaults. Enabled providers require complete configuration. AI_PROVIDER_TIMEOUT_SECONDS defaults to 20 (range 1..60). OpenAI and Vision do not automatically retry; Content Safety retry_total=0.
Health reports configuration, never verified live availability. Request metadata reports actual provider outcomes. Failures never include exception text, credentials, response bodies or image content in application responses.

## Production activation runbook
1. Identify existing Azure subscription, hosting app and resources through authenticated inventory before creating anything. Do not create duplicate services. Confirm permitted regions, billing and current service lifecycle/support.
2. Provision/reuse an Azure AI Vision resource supporting Image Analysis 4.0 and an Azure OpenAI resource with a deployed chat model supporting JSON object response format. Deployment name is an actual deployment identifier, not necessarily a model ID. Optionally configure Azure Content Safety separately; it is supplementary.
3. Set endpoint/key pairs and deployment/API version in the hosting app secret settings or approved vault references, never source control, logs or chat. Use the already supported API version only after verifying deployment compatibility. Keep production ENVIRONMENT, unique SECRET_KEY and existing private Blob configuration.
4. Review data processing region, retention and patient authorization before transmitting images or structured skin context. Vision callers must supply normalized bytes (no Blob public URL/SAS) or structured eligible context; contextual requests do not send raw user questions.
5. Deploy this backend to a staging slot with providers disabled; verify existing authenticated image/check-in routes, doctor loop and Safety Engine.
6. Enable AZURE_VISION_ENABLED and CONTEXTUAL_AI_ENABLED separately in staging. Run authenticated smoke checks with synthetic non-patient inputs: valid image => provider available plus image_proxy provenance; contextual supported task => grounded_ai with validated IDs; urgent/doctor_review => safety_guard without OpenAI call. Force timeout/invalid credentials in staging to verify degraded local behavior and no medical downgrade. Health alone is not proof of reachability.
7. Promote only after smoke checks and privacy approval. Roll back by disabling either feature flag and redeploying if needed. Retain deterministic safety and clinician authority.

## Limitations
No live Azure requests, resource provisioning or deployment were validated in this implementation run. This is general image-analysis integration, not a validated dermatology model. General Azure tags cannot supply calibrated hydration, texture or erythema measurements. No dependency changes are needed: httpx, Pillow, openai and azure-ai-contentsafety were already required. Requirements currently use broad minimum versions, so deployment should use a tested reproducible environment.

## Commit boundary and activation prerequisite
Land the caller-safety fix and its regression tests before this integration commit. The check-in route passes the same metadata-stripped PNG bytes used for private storage to Vision and offloads synchronous analysis to a worker thread. Regression tests cover JPEG EXIF, PNG EXIF/text metadata, matching storage bytes, worker-thread execution and event-loop responsiveness. Keep providers disabled until the staging configuration, privacy review and live success/failure smoke checks above are complete.
