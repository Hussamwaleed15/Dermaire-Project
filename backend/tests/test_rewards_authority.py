import pytest
from tests.test_account_deletion import deletion_context
from app.models import User, RewardRedemption


@pytest.mark.parametrize("balance", [0, 6, 100])
def test_legacy_rewards_never_confirm_or_spend(deletion_context, balance):
    client, db, auth = deletion_context
    user = db.get(User, "delete-patient")
    user.tokens_balance = balance
    db.commit()
    count = db.query(RewardRedemption).count()
    assert client.get("/api/v1/rewards/balance").status_code == 401
    assert client.post("/api/v1/rewards/redeem", json={"reward_id": "travel_serum"}).status_code == 401
    for _ in range(2):
        response = client.get("/api/v1/rewards/balance", headers=auth)
        assert response.status_code == 503
        assert response.json()["errorCode"] == "REWARDS_UNAVAILABLE"
        assert "tokens_balance" not in response.json()
        for reward in ["travel_serum", "dermatologist_review", "advanced_analytics", "unknown"]:
            response = client.post("/api/v1/rewards/redeem", headers=auth, json={"reward_id": reward})
            assert response.status_code == 503
            assert response.json()["errorCode"] == "REWARDS_UNAVAILABLE"
        db.expire_all()
        assert db.get(User, user.id).tokens_balance == balance
        assert db.query(RewardRedemption).count() == count


def test_core_writes_do_not_award_deferred_tokens(deletion_context):
    client, db, auth = deletion_context
    assert db.get(User, "delete-patient").tokens_balance == 0
    response = client.post("/api/v1/products", headers=auth, json={"name": "Real product"})
    assert response.status_code == 201
    response = client.post("/api/v1/checkins", headers=auth, data={
        "hydration_score": 80, "texture_score": 70, "redness_score": 20})
    assert response.status_code == 201
    assert response.json()["tokens_earned"] == 0
    assert all(row["tokens_earned"] == 0 for row in client.get("/api/v1/checkins", headers=auth).json())
    db.expire_all()
    assert db.get(User, "delete-patient").tokens_balance == 0
    assert client.get("/api/v1/home", headers=auth).status_code == 200
