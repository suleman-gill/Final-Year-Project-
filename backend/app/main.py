"""
Tilawah AI — FastAPI Application Entry Point.

Features:
  • Rate limiting via slowapi
  • CORS with configurable origins
  • Lifespan events for ML engine init/shutdown
  • Quran data preloading
"""

import logging
import sys
import sentry_sdk
from contextlib import asynccontextmanager
from pythonjsonlogger import jsonlogger

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from app.core.config import settings
from app.core.database import Base, engine
from sqlalchemy import text
from app.core import quran_data_loader
from app.models import User, RecitationSession, WordResult
from app.routers import auth, users, audio
from app.websocket import recitation_ws
from app.core.redis import session_store

logger = logging.getLogger("uvicorn")

def configure_logging():
    if settings.ENVIRONMENT == "production":
        logHandler = logging.StreamHandler(sys.stdout)
        formatter = jsonlogger.JsonFormatter(
            '%(asctime)s %(levelname)s %(name)s %(message)s'
        )
        logHandler.setFormatter(formatter)
        logger.handlers.clear()
        logger.addHandler(logHandler)
        logger.setLevel(logging.INFO)

configure_logging()

if settings.SENTRY_DSN:
    sentry_sdk.init(
        dsn=settings.SENTRY_DSN,
        traces_sample_rate=1.0,
        environment=settings.ENVIRONMENT,
    )

# ── Rate Limiter ──────────────────────────────────────────────────────
limiter = Limiter(key_func=get_remote_address, default_limits=[settings.RATE_LIMIT_AUTH])


# ── Lifespan Events ──────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown lifecycle manager."""
    # STARTUP
    logger.info("=" * 60)
    logger.info("  Tilawah AI Backend — Starting Up")
    logger.info(f"  Environment: {settings.ENVIRONMENT}")
    logger.info(f"  Database:    {settings.DATABASE_URL[:40]}...")
    logger.info(f"  ML Model:    {settings.MODEL_PATH or 'FALLBACK ENGINE (no MODEL_PATH set)'}")
    logger.info("=" * 60)

    # Database migrations should be handled by Alembic in production

    # Preload Quran ground-truth data
    quran_data_loader.initialize()

    # Initialize Firebase Auth
    from app.core.firebase_auth import _get_app as init_firebase
    try:
        init_firebase()
        logger.info("[Firebase] Admin SDK initialized successfully")
    except Exception as e:
        logger.error(f"[Firebase] Failed to initialize: {e}")
        logger.warning("[Firebase] Authentication will not work until firebase_service_account.json is configured")

    # Initialize ML inference engine
    await recitation_ws.get_engine()

    # Initialize session store (Redis)
    await session_store.initialize()

    yield

    # SHUTDOWN
    logger.info("[Shutdown] Disposing ML inference engine...")
    await recitation_ws.shutdown_engine()
    logger.info("[Shutdown] Tilawah AI Backend stopped.")


# ── Application ───────────────────────────────────────────────────────
app = FastAPI(
    title="Tilawah Backend API",
    description="FastAPI Backend for Tilawah Quran App — Real-time Recitation & Tajweed AI",
    version="1.0.0",
    lifespan=lifespan,
)

# Attach rate limiter
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS middleware
origins = list(settings.ALLOWED_ORIGINS)
allow_origin_regex = None
if settings.ENVIRONMENT == "development":
    allow_origin_regex = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
    if "*" in origins:
        origins.remove("*")

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_regex=allow_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Include Routers ───────────────────────────────────────────────────
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(audio.router)

app.include_router(recitation_ws.router)


# ── Health Check ──────────────────────────────────────────────────────
@app.get("/api/health")
async def health_check():
    db_status = "OK"
    redis_status = "OK"
    
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as e:
        logger.error(f"Healthcheck DB Error: {e}")
        db_status = "ERROR"

    if session_store._use_redis and session_store._redis:
        try:
            await session_store._redis.ping()
        except Exception as e:
            logger.error(f"Healthcheck Redis Error: {e}")
            redis_status = "ERROR"

    status = "OK" if db_status == "OK" and redis_status == "OK" else "ERROR"

    # Check if actual model engine is loaded (not just config flag)
    model_engine = recitation_ws._inference_engine
    model_loaded = (
        model_engine is not None
        and isinstance(model_engine, recitation_ws.TilawahModelEngine)
        and model_engine._model is not None
    )
    engine_type = type(model_engine).__name__ if model_engine else "None"

    return {
        "status": status,
        "db_status": db_status,
        "redis_status": redis_status,
        "app": "Tilawah FastAPI",
        "version": "1.0.0",
        "environment": settings.ENVIRONMENT,
        "model_loaded": model_loaded,
        "engine_type": engine_type,
    }


