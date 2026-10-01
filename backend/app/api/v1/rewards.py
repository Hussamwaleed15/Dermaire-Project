from fastapi import APIRouter, Depends, status
from app.api.deps import get_current_user
from app.core.exceptions import DermaireException
from app.models import User
from app.schemas import RewardRedeemRequest

router = APIRouter(prefix="/rewards", tags=["Rewards & Gamification"])


def unavailable():
    # Legacy balances have no award provenance or fulfillment guarantee.
    raise DermaireException(
        "Rewards are not available. No tokens were spent or reward requested.",
        error_code="REWARDS_UNAVAILABLE",
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
    )


@router.get("/balance")
def get_rewards_balance(current_user: User = Depends(get_current_user)):
    return unavailable()


@router.post("/redeem")
def redeem_reward(
    payload: RewardRedeemRequest,
    current_user: User = Depends(get_current_user),
):
    return unavailable()
