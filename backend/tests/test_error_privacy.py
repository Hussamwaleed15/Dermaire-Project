import json
import pytest
from starlette.requests import Request
from app.core.exceptions import unhandled_exception_handler


@pytest.mark.asyncio
async def test_unhandled_errors_never_expose_credentials_or_health_data():
    request = Request({'type': 'http', 'path': '/api/v1/checkins', 'headers': []})
    secret = 'postgresql://user:private-password@host/db; patient symptoms'
    response = await unhandled_exception_handler(request, RuntimeError(secret))
    body = json.loads(response.body)
    assert response.status_code == 500
    assert body['errorCode'] == 'INTERNAL_SERVER_ERROR'
    assert body['details'] == []
    assert secret not in response.body.decode()
    assert 'notified' not in body['message']
