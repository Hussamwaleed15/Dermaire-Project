from fastapi import APIRouter
from app.api.v1.auth import router as auth_router
from app.api.v1.users import router as users_router
from app.api.v1.products import router as products_router
from app.api.v1.experiments import router as experiments_router
from app.api.v1.checkins import router as checkins_router
from app.api.v1.doctor import router as doctor_router
from app.api.v1.rewards import router as rewards_router
from app.api.v1.chat import router as chat_router

from app.api.v1.baseline import router as baseline_router

from app.api.v1.context import router as context_router

from app.api.v1.home import router as home_router

from app.api.v1.personal_skin_model import router as personal_skin_model_router

api_v1_router = APIRouter()
from app.api.v1.captures import router as captures_router
api_v1_router.include_router(captures_router)
api_v1_router.include_router(home_router)
api_v1_router.include_router(context_router)
api_v1_router.include_router(baseline_router)
api_v1_router.include_router(auth_router)
api_v1_router.include_router(users_router)
api_v1_router.include_router(products_router)
api_v1_router.include_router(experiments_router)
api_v1_router.include_router(checkins_router)
api_v1_router.include_router(doctor_router)
api_v1_router.include_router(rewards_router)
api_v1_router.include_router(chat_router)

api_v1_router.include_router(personal_skin_model_router)
from app.api.v1.routine import router as routine_router
api_v1_router.include_router(routine_router)

from app.api.v1.measurements import router as measurements_router
api_v1_router.include_router(measurements_router)
