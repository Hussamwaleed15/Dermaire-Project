import os
import secrets
import subprocess
import sys
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.core.config import Settings


@pytest.fixture(autouse=True)
def isolate_environment(monkeypatch):
    # Never read developer/deployment secrets from the process or .env file.
    for name in Settings.model_fields:
        monkeypatch.delenv(name, raising=False)


@pytest.mark.parametrize("environment", ["production", "prod", " PRODUCTION ", "staging"])
@pytest.mark.parametrize("secret", [None, "", "   ", "development", "padded_development"])
def test_production_rejects_missing_blank_and_development_secret(environment, secret):
    values = {"ENVIRONMENT": environment}
    if secret == "development":
        secret = Settings.model_fields["SECRET_KEY"].default
    elif secret == "padded_development":
        secret = " " + Settings.model_fields["SECRET_KEY"].default + " "
    if secret is not None:
        values["SECRET_KEY"] = secret
    with pytest.raises(ValidationError, match="SECRET_KEY must be explicitly configured") as error:
        Settings(_env_file=None, **values)
    assert "input_value" not in str(error.value)


@pytest.mark.parametrize("environment", ["development", "dev", "test", "testing"])
def test_explicit_local_environment_allows_development_fallback(environment):
    config = Settings(_env_file=None, ENVIRONMENT=environment)
    assert config.SECRET_KEY == Settings.model_fields["SECRET_KEY"].default


def test_default_environment_preserves_local_development():
    assert Settings(_env_file=None).ENVIRONMENT == "development"


def test_valid_production_secret_is_loaded_from_environment(monkeypatch):
    secret = secrets.token_hex(32)
    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("SECRET_KEY", secret)
    config = Settings(_env_file=None)
    assert config.SECRET_KEY == secret


def test_unknown_environment_does_not_silently_bypass_validation():
    with pytest.raises(ValidationError):
        Settings(_env_file=None, ENVIRONMENT="produciton")


def test_application_import_fails_before_startup_with_missing_secret(tmp_path):
    env = os.environ.copy()
    env["ENVIRONMENT"] = "production"
    env["PYTHONPATH"] = str(Path(__file__).resolve().parents[1])
    result = subprocess.run(
        [sys.executable, "-c", "import app.main"],
        cwd=tmp_path, env=env, capture_output=True, text=True,
    )
    assert result.returncode != 0
    assert "SECRET_KEY must be explicitly configured" in result.stderr
    assert "input_value" not in result.stderr


def test_dotenv_development_secret_cannot_bypass_production(monkeypatch, tmp_path):
    env_file = tmp_path / ".env"
    fallback = Settings.model_fields["SECRET_KEY"].default
    env_file.write_text(
        f"ENVIRONMENT=development\nSECRET_KEY={fallback}\n", encoding="utf-8"
    )
    monkeypatch.setenv("ENVIRONMENT", "production")
    with pytest.raises(ValidationError, match="SECRET_KEY must be explicitly configured"):
        Settings(_env_file=env_file)


def test_validation_error_does_not_expose_supplied_secret():
    secret = secrets.token_hex(32)
    with pytest.raises(ValidationError) as error:
        Settings(_env_file=None, ENVIRONMENT="unknown", SECRET_KEY=secret)
    assert secret not in str(error.value)
