"""Sanitize server/SDK logs, including ASGI exceptions after error responses."""
import json
import logging


class PrivacyFilter(logging.Filter):
    def filter(self, record):
        if record.name != "dermaire.operations":
            record.msg = json.dumps({"event": "server_log", "level": record.levelname})
            record.args = ()
        record.exc_info = None
        record.exc_text = None
        record.stack_info = None
        return True
