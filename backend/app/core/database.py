from typing import Generator
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker, Session
from app.core.config import settings

def connection_options(url):
    if url.startswith("sqlite"):
        return {"check_same_thread": False}
    if url.startswith("postgresql"):
        # Existing naive timestamp columns carry server-UTC values. Pin the
        # connection's cast semantics instead of inheriting a host timezone.
        return {"connect_timeout": 5, "options": "-c statement_timeout=5000 -c timezone=UTC"}
    return {}


connect_args = connection_options(settings.DATABASE_URL)

engine = create_engine(
    settings.DATABASE_URL,
    connect_args=connect_args,
    pool_pre_ping=True,
    echo=settings.DEBUG and settings.ENVIRONMENT == "development" and not settings.DATABASE_URL.startswith("sqlite")
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def init_db() -> None:
    # Managed environments use reviewed migrations, never implicit startup DDL.
    if settings.ENVIRONMENT in {"development", "test"}:
        Base.metadata.create_all(bind=engine)
