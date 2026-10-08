import json
import logging
from app.core.logging_safety import PrivacyFilter


def test_server_exception_and_sdk_message_redaction():
    record = logging.LogRecord("uvicorn.error", logging.ERROR, "server.py", 1,
                              "token=%s user=private", ("secret",),
                              (ValueError, ValueError("private body"), None))
    record.stack_info = "raw stack"
    assert PrivacyFilter().filter(record)
    output = logging.Formatter("%(message)s").format(record)
    assert json.loads(output) == {"event": "server_log", "level": "ERROR"}
    assert record.exc_info is None and record.stack_info is None


def test_structured_operations_retained():
    value = '{"event":"dependency_state","component":"deletion_journal","state":"unavailable"}'
    record = logging.LogRecord("dermaire.operations", logging.INFO, "ops.py", 1, value, (), None)
    assert PrivacyFilter().filter(record) and record.getMessage() == value
