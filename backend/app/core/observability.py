"""Privacy-safe request telemetry: no bodies, query strings or exception text."""
import json
import logging
import time
import uuid
from contextvars import ContextVar
from functools import wraps

logger = logging.getLogger("dermaire.operations")
logger.setLevel(logging.INFO)
if not logger.handlers:
    # Uvicorn configures its own loggers, not the application's root logger.
    logger.addHandler(logging.StreamHandler())
correlation_id = ContextVar("request_id", default=None)
boot_id = str(uuid.uuid4())
process_started = time.monotonic()


def operation_event(component, state):
    logger.info(json.dumps({"event": "dependency_state", "component": component,
                           "state": state, "request_id": correlation_id.get()}))


def observed_dependency(component):
    def decorate(function):
        @wraps(function)
        def observed(*args, **kwargs):
            try:
                result = function(*args, **kwargs)
            except Exception:
                operation_event(component, "degraded")
                raise
            operation_event(component, "available")
            return result
        return observed
    return decorate


class RequestTelemetry:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        request_id = str(uuid.uuid4())
        context_token = correlation_id.set(request_id)
        scope.setdefault("state", {})["request_id"] = request_id
        started = time.monotonic()
        status = 500

        async def traced_send(message):
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
                message.setdefault("headers", []).append((b"x-request-id", request_id.encode()))
            await send(message)

        try:
            await self.app(scope, receive, traced_send)
        finally:
            route = scope.get("route")
            logger.info(json.dumps({
                "event": "http_request", "request_id": request_id,
                "method": scope["method"], "route": getattr(route, "path", "unmatched"),
                "status": status, "duration_ms": round((time.monotonic() - started) * 1000, 2),
            }))
            correlation_id.reset(context_token)
