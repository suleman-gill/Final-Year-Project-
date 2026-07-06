"""
Tilawah AI — User Model.

Stores user credentials, gamification data (XP, level, streaks),
and password-recovery OTP fields.
"""

from sqlalchemy import Column, String, Integer, DateTime, Text
from datetime import datetime, timezone
from app.core.database import Base


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, index=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=False)

    # ── Profile ────────────────────────────────────────────────────
    avatar_url = Column(String, nullable=True)
    bio = Column(Text, nullable=True)

    # ── Gamification ───────────────────────────────────────────────
    streak_days = Column(Integer, default=0)
    longest_streak = Column(Integer, default=0)
    last_active_date = Column(DateTime, default=lambda: datetime.now(timezone.utc), nullable=True)
    total_xp = Column(Integer, default=0)
    level = Column(Integer, default=1)

    # ── Password Recovery (OTP) ────────────────────────────────────
    otp_code = Column(String, nullable=True)       # Hashed 6-digit OTP
    otp_expires_at = Column(DateTime, nullable=True)
    otp_attempts = Column(Integer, default=0)

    # ── Timestamps ─────────────────────────────────────────────────
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
