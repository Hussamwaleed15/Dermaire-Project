import os
from contextlib import asynccontextmanager
from fastapi import FastAPI, status, Depends
from sqlalchemy.orm import Session
from sqlalchemy.exc import OperationalError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.config import settings
from app.core.database import init_db, get_db
from app.core.observability import RequestTelemetry, operation_event, boot_id, process_started
from app.core.exceptions import (
    DermaireException,
    dermaire_exception_handler,
    validation_exception_handler,
    starlette_http_exception_handler,
    unhandled_exception_handler,
    database_unavailable_handler
)
from app.api.v1.router import api_v1_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Initialize database tables
    init_db()
    # Ensure local upload directory exists
    os.makedirs(os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "uploads")), exist_ok=True)
    operation_event("startup", "complete")
    yield

app = FastAPI(
    title="Dermaire Personal Skin Lab API",
    version="1.0.0",
    description="""
## Dermaire Skin Lab Backend — Microsoft Imagine Cup 2027
Advanced Evidence-Based Clinical Skin Tracker & AI Assistant powered by:
- **Microsoft Azure Blob Storage** (Private photos served through authenticated backend reads)
- **Microsoft Azure AI Vision 4.0** (Erythema/Redness, texture smoothness, and lesion analysis)
- **Microsoft Azure OpenAI Service (GPT-4o)** (Responsible medical skin assistant)
- **Microsoft Azure AI Content Safety** (Real-time clinical emergency red-flag escalation)
- **PostgreSQL & Append-Only Clinical Audit Trails** (Doctor portal, consent, and tamper-evident logs)
    """,
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json"
)

# CORS Middleware configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(RequestTelemetry)

# Exception Handlers Registration
app.add_exception_handler(DermaireException, dermaire_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(StarletteHTTPException, starlette_http_exception_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)
app.add_exception_handler(OperationalError, database_unavailable_handler)

from fastapi.responses import FileResponse

# Public static files contain only the landing page; images have no static route.
uploads_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "uploads"))
static_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "static"))
os.makedirs(uploads_dir, exist_ok=True)
os.makedirs(static_dir, exist_ok=True)

app.mount("/static", StaticFiles(directory=static_dir), name="static")

@app.get("/", tags=["NeoVague Team Showcase"])
def serve_landing_page():
    index_path = os.path.join(static_dir, "index.html")
    if os.path.exists(index_path):
        return FileResponse(index_path)
    return {"message": "NeoVague Team API is running. Visit /docs for Swagger UI."}

@app.get("/dermaire", tags=["Dermaire Product Details"])
def serve_dermaire_page():
    dermaire_path = os.path.join(static_dir, "dermaire.html")
    if os.path.exists(dermaire_path):
        return FileResponse(dermaire_path)
    return FileResponse(os.path.join(static_dir, "index.html"))

# Include API v1 Router
app.include_router(api_v1_router, prefix=settings.API_V1_STR)

@app.get("/health/live", tags=["System Health"])
def liveness():
    import time
    return {"status": "alive", "boot_id": boot_id,
            "uptime_seconds": round(time.monotonic() - process_started, 2)}

@app.get("/health/ready", tags=["System Health"])
def readiness(db: Session = Depends(get_db)):
    from sqlalchemy import text
    from fastapi.responses import JSONResponse
    from app.services.azure_blob import azure_blob_service
    from app.services.deletion_journal import deletion_journal
    try:
        db.execute(text("SELECT 1"))
        if settings.ENVIRONMENT in {"staging", "production"}:
            revision = db.execute(text("SELECT version_num FROM alembic_version")).scalars().all()
            if revision != ["20261008_01"]:
                raise RuntimeError("Schema revision unavailable")
        database = "available"
    except Exception:
        database = "unavailable"
    storage = azure_blob_service.health()["state"]
    operation_event("database", database)
    operation_event("blob", storage)
    journal = deletion_journal.health()
    operation_event("deletion_journal", journal)
    ready = database == "available" and (storage == "available" or
        (storage == "unconfigured" and settings.ENVIRONMENT in {"development", "test"})) and (
        journal == "available" or settings.ENVIRONMENT in {"development", "test"})
    return JSONResponse(status_code=200 if ready else 503, content={
        "status": "ready" if ready else "unavailable", "database": database,
        "storage": storage, "deletion_journal": journal})

@app.get("/health", tags=["System Health"])
def health_check():
    from app.services.azure_blob import azure_blob_service
    blob = azure_blob_service.health()
    return {
        "status": "degraded" if blob["state"] == "degraded" or (blob["state"] == "unconfigured" and settings.ENVIRONMENT in {"production", "staging"}) else "healthy",
        "project": settings.PROJECT_NAME,
        "edition": settings.IMAGINE_COP_EDITION,
        "azure_services": {
            "blob_storage": blob,
            "ai_vision": "Configured; reachability unverified" if settings.AZURE_VISION_ENABLED else "Disabled; local image proxies",
            "openai_gpt4o": "Configured; reachability unverified" if settings.CONTEXTUAL_AI_ENABLED else "Disabled; deterministic assistance",
            "content_safety": "Configured; reachability unverified" if settings.is_safety_live else "Local Rules"
        }
    }
