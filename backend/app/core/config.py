"""
Tilawah AI — Centralized Configuration with pydantic-settings.

All environment variables are validated at startup.
Missing critical values in production will raise a terminal error.
"""

import os
import secrets
from typing import List, Optional
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import field_validator


class Settings(BaseSettings):
    """Application settings validated from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── Server ────────────────────────────────────────────────────────
    PORT: int = 8000
    HOST: str = "0.0.0.0"
    ENVIRONMENT: str = "development"  # "development" | "production"

    # ── Database ──────────────────────────────────────────────────────
    DATABASE_URL: str = "sqlite:///./tilawah.db"
    REDIS_URL: str = "redis://localhost:6379"

    # ── Security / JWT ────────────────────────────────────────────────
    JWT_SECRET_KEY: str = "tilawah_super_secret_dev_key_change_me_in_prod"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 43200  # 30 days

    # ── CORS ──────────────────────────────────────────────────────────
    ALLOWED_ORIGINS: List[str] = ["http://localhost:3000"]

    # ── ML / Wav2Vec2 ─────────────────────────────────────────────────
    MODEL_PATH: Optional[str] = None  # Path to fine-tuned Wav2Vec2 weights
    MAX_AUDIO_FRAME_BYTES: int = 1_048_576  # 1 MB

    # ── Rate Limiting ─────────────────────────────────────────────────
    RATE_LIMIT_AUTH: str = "5/minute"

    # ── Email / Resend ────────────────────────────────────────────────
    RESEND_API_KEY: str = ""
    FROM_EMAIL: str = "noreply@tilawah.app"

    # ── Storage ───────────────────────────────────────────────────────
    AUDIO_CACHE_MAX_GB: float = 5.0

    # ── Telemetry ─────────────────────────────────────────────────────
    SENTRY_DSN: Optional[str] = None

    # ── Validators ────────────────────────────────────────────────────
    @field_validator("JWT_SECRET_KEY")
    @classmethod
    def secret_key_must_not_be_default_in_prod(cls, v: str, info) -> str:
        """Raise a terminal error if the secret key is the default, short, or placeholder in production."""
        env = info.data.get("ENVIRONMENT", "development")
        invalid_keys = {
            "tilawah_super_secret_dev_key_change_me_in_prod",
            "change_this_in_production",
            "change_this",
            "change_me",
        }
        if env == "production":
            if v in invalid_keys or len(v) < 32:
                raise ValueError(
                    "FATAL: JWT_SECRET_KEY must be changed to a secure, unique key at least 32 characters long "
                    "in production. Generate one with: python -c \"import secrets; print(secrets.token_urlsafe(64))\""
                )
        return v

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.lower() == "production"

    @property
    def is_development(self) -> bool:
        return not self.is_production


# ── Singleton instance ────────────────────────────────────────────────
settings = Settings()

# ── Backward-compatible module-level exports ──────────────────────────
# These allow existing code (e.g., security.py, database.py) to import
# `from app.core.config import DATABASE_URL` without breaking.
PORT = settings.PORT
HOST = settings.HOST
DATABASE_URL = settings.DATABASE_URL
JWT_SECRET_KEY = settings.JWT_SECRET_KEY
JWT_ALGORITHM = settings.JWT_ALGORITHM
ACCESS_TOKEN_EXPIRE_MINUTES = settings.ACCESS_TOKEN_EXPIRE_MINUTES
MODEL_PATH = settings.MODEL_PATH
MAX_AUDIO_FRAME_BYTES = settings.MAX_AUDIO_FRAME_BYTES
