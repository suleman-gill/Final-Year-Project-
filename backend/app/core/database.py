"""
Tilawah AI — Database Engine & Session Factory.

Dual-mode: PostgreSQL via DATABASE_URL in production,
automatic fallback to SQLite for local development.
"""

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from app.core.config import settings
import logging

logger = logging.getLogger("uvicorn")

DATABASE_URL = settings.DATABASE_URL
connect_args = {}

# ── Engine creation with PostgreSQL → SQLite fallback ─────────────────
if DATABASE_URL.startswith("postgresql"):
    try:
        temp_engine = create_engine(
            DATABASE_URL,
            pool_size=20,
            max_overflow=10,
            pool_timeout=30,
            pool_pre_ping=True
        )
        with temp_engine.connect() as conn:
            pass
        engine = temp_engine
        logger.info("Successfully connected to PostgreSQL database.")
    except Exception as e:
        logger.warning(
            f"PostgreSQL connection failed ({e}). "
            "Falling back to local SQLite database: tilawah.db"
        )
        DATABASE_URL = "sqlite:///./tilawah.db"
        connect_args["check_same_thread"] = False
        engine = create_engine(
            DATABASE_URL, connect_args=connect_args, pool_pre_ping=True
        )
else:
    if DATABASE_URL.startswith("sqlite"):
        connect_args["check_same_thread"] = False
    engine = create_engine(
        DATABASE_URL, connect_args=connect_args, pool_pre_ping=True
    )

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


# ── Dependency-injected database session provider ─────────────────────
def get_db():
    """FastAPI dependency that yields a database session and closes it after use."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
