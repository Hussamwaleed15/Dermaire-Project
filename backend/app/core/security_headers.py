"""Conservative response headers suitable for the API and bundled documentation."""

from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.config import settings


class SecurityHeaders:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def send_with_headers(message):
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                existing = {name.lower() for name, _ in headers}
                additions = {
                    b"x-content-type-options": b"nosniff",
                    b"x-frame-options": b"SAMEORIGIN",
                    b"referrer-policy": b"no-referrer",
                    b"permissions-policy": b"camera=(), microphone=(), geolocation=()",
                }
                if settings.ENVIRONMENT in {"staging", "production"}:
                    additions[b"strict-transport-security"] = b"max-age=31536000"
                for name, value in additions.items():
                    if name not in existing:
                        headers.append((name, value))
                message["headers"] = headers
            await send(message)

        await self.app(scope, receive, send_with_headers)
