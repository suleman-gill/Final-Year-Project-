"""
Tilawah AI — Users Router.

Endpoints: profile update, user stats.
"""

import logging
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.core.database import get_db
from app.core.security import get_current_user
from app.models.user import User
from app.models.session import RecitationSession
from app.schemas.auth import UserResponse, ProfileUpdateRequest

logger = logging.getLogger("uvicorn")
router = APIRouter(prefix="/api/users", tags=["users"])


# ══════════════════════════════════════════════════════════════════════
# UPDATE PROFILE
# ══════════════════════════════════════════════════════════════════════

@router.put("/profile", response_model=UserResponse)
def update_profile(
    req: ProfileUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update the authenticated user's profile fields."""
    if req.name is not None:
        current_user.name = req.name
    if req.bio is not None:
        current_user.bio = req.bio
    if req.avatar_url is not None:
        current_user.avatar_url = req.avatar_url

    db.commit()
    db.refresh(current_user)
    logger.info(f"[Users] Profile updated for user {current_user.id}")
    return current_user


# ══════════════════════════════════════════════════════════════════════
# USER STATS
# ══════════════════════════════════════════════════════════════════════

@router.get("/stats")
def get_user_stats(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Return aggregated recitation statistics for the authenticated user."""
    stats = db.query(
        func.count(RecitationSession.id).label("total_sessions"),
        func.sum(RecitationSession.total).label("total_words"),
        func.sum(RecitationSession.correct).label("total_correct"),
        func.sum(RecitationSession.wrong).label("total_wrong"),
        func.avg(RecitationSession.accuracy).label("avg_accuracy"),
        func.sum(RecitationSession.duration_ms).label("total_duration_ms")
    ).filter(RecitationSession.user_id == current_user.id).first()

    total_sessions = stats.total_sessions or 0
    total_words = stats.total_words or 0
    total_correct = stats.total_correct or 0
    total_wrong = stats.total_wrong or 0
    avg_accuracy = round(stats.avg_accuracy, 1) if stats.avg_accuracy else 0.0
    total_duration_ms = stats.total_duration_ms or 0

    return {
        "user_id": current_user.id,
        "total_sessions": total_sessions,
        "total_words_recited": total_words,
        "total_correct": total_correct,
        "total_wrong": total_wrong,
        "average_accuracy": avg_accuracy,
        "total_duration_ms": total_duration_ms,
        "total_xp": current_user.total_xp,
        "level": current_user.level,
        "streak_days": current_user.streak_days,
        "longest_streak": current_user.longest_streak,
    }
