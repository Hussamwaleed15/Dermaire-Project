from typing import List, Literal
from urllib.parse import urlsplit
from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
        hide_input_in_errors=True
    )

    # App Identity
    PROJECT_NAME: str = "Dermaire Skin Lab API"
    VERSION: str = "1.0.0"
    API_V1_STR: str = "/api/v1"
    IMAGINE_COP_EDITION: str = "Microsoft Imagine Cup 2027"
    ENVIRONMENT: Literal["development", "test", "staging", "production"] = "development"
    DEBUG: bool = True

    # Security & Authentication
    SECRET_KEY: str = "dermaire-super-secret-azure-imagine-cup-key-2027-change-in-production"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24  # 24 hours
    REFRESH_TOKEN_EXPIRE_DAYS: int = 30

    # Google Sign-In (OAuth 2.0)
    # This must be the "Web application" client ID from Google Cloud Console —
    # it's the audience the Flutter app's google_sign_in requests via
    # serverClientId, and what we verify incoming ID tokens against here.
    GOOGLE_WEB_CLIENT_ID: str = "1042340572793-ss2cemhfub1bod1a8nakitgco1af2540.apps.googleusercontent.com"

    # Password reset — no email-sending provider is configured yet for this
    # project, so there's no way to deliver reset links to an inbox. While
    # that's true, this flag lets the forgot-password endpoint return the
    # raw token directly in its response so the flow can still be tested
    # end-to-end. Turn this OFF the moment a real email provider is wired
    # up, since leaving it on would let anyone reset any account's password
    # just by knowing their email.
    EXPOSE_PASSWORD_RESET_TOKEN: bool = False

    # Azure Communication Services Email
    AZURE_COMMUNICATION_CONNECTION_STRING: str = ""
    AZURE_EMAIL_SENDER: str = ""

    # CORS
    BACKEND_CORS_ORIGINS: List[str] = [
        "http://localhost",
        "http://localhost:3000",
        "http://localhost:8080",
        "http://127.0.0.1",
        "*"
    ]

    # Database (Defaults to SQLite for instant local zero-dependency run, can switch to Azure Postgres)
    DATABASE_URL: str = "sqlite:///./dermaire_dev.db"

    # Microsoft Azure Blob Storage (Skin photos & medical reports)
    AZURE_STORAGE_CONNECTION_STRING: str = ""
    AZURE_STORAGE_CONTAINER: str = "skin-records"

    # Microsoft Azure AI Vision (Image Analysis 4.0)
    AZURE_VISION_ENDPOINT: str = ""
    AZURE_VISION_KEY: str = ""
    AZURE_VISION_ENABLED: bool = False
    AI_PROVIDER_TIMEOUT_SECONDS: float = 20.0

    # Microsoft Azure OpenAI Service (GPT-4o Medical Assistant)
    AZURE_OPENAI_ENDPOINT: str = ""
    AZURE_OPENAI_API_KEY: str = ""
    AZURE_OPENAI_DEPLOYMENT_NAME: str = "gpt-4o"
    AZURE_OPENAI_API_VERSION: str = "2024-08-01-preview"
    # Azure credentials alone do not enable contextual generation.
    CONTEXTUAL_AI_ENABLED: bool = False

    # Microsoft Azure AI Content Safety (Emergency Red Flag Escalation)
    AZURE_CONTENT_SAFETY_ENDPOINT: str = ""
    AZURE_CONTENT_SAFETY_KEY: str = ""

    @model_validator(mode="after")
    def validate_ai_configuration(self):
        for endpoint_name, key_name in (
            ("AZURE_VISION_ENDPOINT", "AZURE_VISION_KEY"),
            ("AZURE_OPENAI_ENDPOINT", "AZURE_OPENAI_API_KEY"),
            ("AZURE_CONTENT_SAFETY_ENDPOINT", "AZURE_CONTENT_SAFETY_KEY"),
        ):
            endpoint = getattr(self, endpoint_name).strip()
            key = getattr(self, key_name).strip()
            if bool(endpoint) != bool(key):
                raise ValueError(f"{endpoint_name} and {key_name} must be configured together")
            if endpoint:
                url = urlsplit(endpoint)
                if (url.scheme != "https" or not url.hostname or url.username or url.password
                        or url.query or url.fragment or url.path not in ("", "/")):
                    raise ValueError(f"{endpoint_name} must be an HTTPS resource base URL")
                setattr(self, endpoint_name, endpoint.rstrip("/"))
                setattr(self, key_name, key)
        if not 1 <= self.AI_PROVIDER_TIMEOUT_SECONDS <= 60:
            raise ValueError("AI_PROVIDER_TIMEOUT_SECONDS must be between 1 and 60")
        if self.AZURE_VISION_ENABLED and not self.is_vision_live:
            raise ValueError("AZURE_VISION_ENABLED requires Vision credentials")
        if self.CONTEXTUAL_AI_ENABLED and (not self.is_openai_live
                or not self.AZURE_OPENAI_DEPLOYMENT_NAME.strip()
                or not self.AZURE_OPENAI_API_VERSION.strip()):
            raise ValueError("CONTEXTUAL_AI_ENABLED requires complete OpenAI configuration")
        return self

    @field_validator("ENVIRONMENT", mode="before")
    @classmethod
    def normalize_environment(cls, value):
        if isinstance(value, str):
            value = value.strip().lower()
            return {"dev": "development", "testing": "test", "prod": "production"}.get(value, value)
        return value

    @model_validator(mode="after")
    def validate_production_secret(self):
        if self.ENVIRONMENT in {"production", "staging"}:
            development_secret = type(self).model_fields["SECRET_KEY"].default
            if not self.SECRET_KEY.strip() or self.SECRET_KEY.strip() == development_secret:
                raise ValueError(
                    "SECRET_KEY must be explicitly configured with a non-empty, "
                    "non-development secret in production/staging"
                )
        return self

    # Configuration presence only; the service health probe checks reachability/privacy.
    @property
    def is_blob_live(self) -> bool:
        return bool(self.AZURE_STORAGE_CONNECTION_STRING.strip())

    @property
    def is_vision_live(self) -> bool:
        return bool(self.AZURE_VISION_ENDPOINT and self.AZURE_VISION_KEY)

    @property
    def is_openai_live(self) -> bool:
        return bool(self.AZURE_OPENAI_ENDPOINT and self.AZURE_OPENAI_API_KEY)

    @property
    def is_safety_live(self) -> bool:
        return bool(self.AZURE_CONTENT_SAFETY_ENDPOINT and self.AZURE_CONTENT_SAFETY_KEY)

settings = Settings()

