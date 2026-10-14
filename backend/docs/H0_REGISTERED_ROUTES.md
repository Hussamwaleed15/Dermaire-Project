# Registered backend route inventory

Source inspection after H1-A, 2026-10-14. Registered modules resolved from app/api/v1/router.py; API prefix /api/v1. No live HTTP calls. DTO and dependency names are source expressions, not runtime/schema promises. See H0_BACKEND_MASTER_STATUS.md and H1_DOCTOR_CONTRACT_HANDOFF.md for authority and remaining gaps.

| Method | Path | Source / handler | Response contract |
|---|---|---|---|
| POST | `/api/v1/auth/register` | `app/api/v1/auth.py:65` / `register_user` | `TokenResponse` |
| POST | `/api/v1/auth/login` | `app/api/v1/auth.py:110` / `login_user` | `TokenResponse` |
| POST | `/api/v1/auth/google` | `app/api/v1/auth.py:129` / `google_login` | `TokenResponse` |
| POST | `/api/v1/auth/forgot-password` | `app/api/v1/auth.py:188` / `forgot_password` | `handler return (no response_model)` |
| POST | `/api/v1/auth/reset-password` | `app/api/v1/auth.py:222` / `reset_password` | `UserOut` |
| POST | `/api/v1/auth/logout` | `app/api/v1/auth.py:286` / `logout_session` | `handler return (no response_model)` |
| POST | `/api/v1/auth/accept-safety` | `app/api/v1/auth.py:295` / `accept_safety_terms` | `UserOut` |
| GET | `/api/v1/baseline` | `app/api/v1/baseline.py:12` / `get_baseline` | `handler return (no response_model)` |
| POST | `/api/v1/captures` | `app/api/v1/captures.py:32` / `create_capture` | `handler return (no response_model)` |
| GET | `/api/v1/captures` | `app/api/v1/captures.py:102` / `history` | `handler return (no response_model)` |
| GET | `/api/v1/captures/{capture_id}` | `app/api/v1/captures.py:113` / `get_capture` | `handler return (no response_model)` |
| GET | `/api/v1/captures/{capture_id}/image` | `app/api/v1/captures.py:121` / `get_image` | `handler return (no response_model)` |
| POST | `/api/v1/chat` | `app/api/v1/chat.py:14` / `chat_with_assistant` | `ChatMessageResponse` |
| GET | `/api/v1/checkins` | `app/api/v1/checkins.py:28` / `get_checkins_history` | `List[CheckInResponse]` |
| POST | `/api/v1/checkins` | `app/api/v1/checkins.py:63` / `submit_daily_checkin` | `CheckInResponse` |
| GET | `/api/v1/checkins/{checkin_id}/image` | `app/api/v1/checkins.py:228` / `get_image` | `handler return (no response_model)` |
| GET | `/api/v1/context/{day}` | `app/api/v1/context.py:32` / `read_context` | `ContextResponse` |
| PUT | `/api/v1/context/{day}` | `app/api/v1/context.py:36` / `save_context` | `ContextResponse` |
| POST | `/api/v1/assistance` | `app/api/v1/contextual_ai.py:12` / `contextual_assistance` | `AssistanceResponse` |
| POST | `/api/v1/doctor/generate-qr` | `app/api/v1/doctor.py:24` / `generate_doctor_qr_access` | `GenerateQrResponse` |
| POST | `/api/v1/doctor/claim` | `app/api/v1/doctor.py:75` / `claim_patient_access` | `handler return (no response_model)` |
| DELETE | `/api/v1/doctor/revoke/{patient_id}` | `app/api/v1/doctor.py:132` / `revoke_patient_access` | `handler return (no response_model)` |
| GET | `/api/v1/doctor/patients` | `app/api/v1/doctor.py:153` / `list_authorized_patients` | `List[DoctorPatientOut]` |
| POST | `/api/v1/doctor/patients/{patient_id}/notes` | `app/api/v1/doctor.py:203` / `add_clinical_note` | `ClinicalNoteOut` |
| GET | `/api/v1/doctor/access` | `app/api/v1/doctor.py:241` / `patient_access` | `handler return (no response_model)` |
| DELETE | `/api/v1/doctor/access/{access_id}` | `app/api/v1/doctor.py:246` / `revoke_one` | `handler return (no response_model)` |
| GET | `/api/v1/doctor/review-status` | `app/api/v1/doctor.py:259` / `patient_review_status` | `handler return (no response_model)` |
| GET | `/api/v1/doctor/patients/{patient_id}` | `app/api/v1/doctor.py:264` / `patient_detail` | `handler return (no response_model)` |
| GET | `/api/v1/doctor/patients/{patient_id}/timeline` | `app/api/v1/doctor.py:271` / `patient_timeline` | `handler return (no response_model)` |
| GET | `/api/v1/doctor/patients/{patient_id}/notes` | `app/api/v1/doctor.py:282` / `patient_notes` | `List[ClinicalNoteOut]` |
| GET | `/api/v1/doctor/patients/{patient_id}/reviews` | `app/api/v1/doctor.py:288` / `patient_reviews` | `handler return (no response_model)` |
| POST | `/api/v1/doctor/patients/{patient_id}/reviews` | `app/api/v1/doctor.py:294` / `add_review` | `handler return (no response_model)` |
| GET | `/api/v1/experiments/current` | `app/api/v1/experiments.py:35` / `current` | `ExperimentOut | None` |
| GET | `/api/v1/experiments` | `app/api/v1/experiments.py:40` / `listing` | `list[ExperimentOut]` |
| POST | `/api/v1/experiments` | `app/api/v1/experiments.py:45` / `create` | `ExperimentOut` |
| GET | `/api/v1/experiments/{identifier}` | `app/api/v1/experiments.py:58` / `read` | `ExperimentOut` |
| PATCH | `/api/v1/experiments/{identifier}` | `app/api/v1/experiments.py:62` / `edit` | `ExperimentOut` |
| POST | `/api/v1/experiments/{identifier}/activate` | `app/api/v1/experiments.py:79` / `activate` | `ExperimentOut` |
| POST | `/api/v1/experiments/{identifier}/finish` | `app/api/v1/experiments.py:91` / `finish` | `ExperimentOut` |
| DELETE | `/api/v1/experiments/{identifier}` | `app/api/v1/experiments.py:113` / `cancel` | `ExperimentOut` |
| POST | `/api/v1/experiments/{identifier}/evaluate` | `app/api/v1/experiments.py:119` / `evaluate` | `EvaluationOut` |
| GET | `/api/v1/experiments/{identifier}/results` | `app/api/v1/experiments.py:128` / `results` | `list[EvaluationOut]` |
| PATCH | `/api/v1/experiments/{identifier}/toggle-pause` | `app/api/v1/experiments.py:133` / `retired_pause` | `handler return (no response_model)` |
| GET | `/api/v1/home` | `app/api/v1/home.py:15` / `get_home` | `handler return (no response_model)` |
| GET | `/api/v1/measurements` | `app/api/v1/measurements.py:18` / `history` | `handler return (no response_model)` |
| GET | `/api/v1/measurements/{capture_id}` | `app/api/v1/measurements.py:28` / `read` | `handler return (no response_model)` |
| POST | `/api/v1/measurements/{capture_id}` | `app/api/v1/measurements.py:41` / `generate` | `handler return (no response_model)` |
| GET | `/api/v1/personal-skin-model` | `app/api/v1/personal_skin_model.py:12` / `get_personal_skin_model` | `PersonalSkinModel` |
| GET | `/api/v1/products/{product_id}/intelligence` | `app/api/v1/product_intelligence.py:14` / `read` | `handler return (no response_model)` |
| GET | `/api/v1/routine/intelligence` | `app/api/v1/product_intelligence.py:24` / `routine` | `handler return (no response_model)` |
| PUT | `/api/v1/admin/product-intelligence/{product_id}` | `app/api/v1/product_intelligence.py:29` / `ingest` | `handler return (no response_model)` |
| GET | `/api/v1/products` | `app/api/v1/products.py:19` / `list_products` | `List[ProductOut]` |
| POST | `/api/v1/products` | `app/api/v1/products.py:39` / `create_product` | `ProductOut` |
| GET | `/api/v1/products/{product_id}` | `app/api/v1/products.py:82` / `get_product` | `ProductOut` |
| PATCH | `/api/v1/products/{product_id}` | `app/api/v1/products.py:96` / `update_product` | `ProductOut` |
| DELETE | `/api/v1/products/{product_id}` | `app/api/v1/products.py:139` / `delete_product` | `handler return (no response_model)` |
| POST | `/api/v1/products/check-interactions` | `app/api/v1/products.py:182` / `check_interactions_endpoint` | `handler return (no response_model)` |
| GET | `/api/v1/rewards/balance` | `app/api/v1/rewards.py:20` / `get_rewards_balance` | `handler return (no response_model)` |
| POST | `/api/v1/rewards/redeem` | `app/api/v1/rewards.py:25` / `redeem_reward` | `handler return (no response_model)` |
| GET | `/api/v1/routine/entries` | `app/api/v1/routine.py:13` / `entries` | `list[RoutineOut]` |
| POST | `/api/v1/routine/entries` | `app/api/v1/routine.py:20` / `create` | `RoutineOut` |
| GET | `/api/v1/routine/entries/{entry_id}` | `app/api/v1/routine.py:39` / `read` | `RoutineOut` |
| PATCH | `/api/v1/routine/entries/{entry_id}` | `app/api/v1/routine.py:43` / `update` | `RoutineOut` |
| DELETE | `/api/v1/routine/entries/{entry_id}` | `app/api/v1/routine.py:62` / `remove` | `handler return (no response_model)` |
| GET | `/api/v1/routine/adherence` | `app/api/v1/routine.py:71` / `logs` | `list[AdherenceOut]` |
| POST | `/api/v1/routine/adherence` | `app/api/v1/routine.py:79` / `log` | `AdherenceOut` |
| GET | `/api/v1/safety` | `app/api/v1/safety.py:10` / `current_safety` | `SafetyEvaluation` |
| GET | `/api/v1/users/me` | `app/api/v1/users.py:13` / `get_current_user_profile` | `UserOut` |
| PATCH | `/api/v1/users/skin-profile` | `app/api/v1/users.py:20` / `update_skin_profile` | `UserOut` |
| DELETE | `/api/v1/users/me` | `app/api/v1/users.py:55` / `delete_current_account` | `handler return (no response_model)` |

Count: 70 registered API route operations. Main health and public static landing routes are outside this patient/clinician API inventory.
