"""
Tilawah AI — Auth Router.

Endpoints: register, login, me, forgot-password, verify-otp, reset-password.
Rate-limited via slowapi (applied in main.py middleware).
"""

import uuid
import secrets
import logging
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.core.database import get_db
from app.core.config import settings
from app.models.user import User
from app.schemas.auth import (
    UserCreate,
    UserLogin,
    Token,
    UserResponse,
    ForgotPasswordRequest,
    VerifyOtpRequest,
    ResetPasswordRequest,
    MessageResponse,
)
from app.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    get_current_user,
)

logger = logging.getLogger("uvicorn")
router = APIRouter(prefix="/api/auth", tags=["auth"])

# ── OTP Configuration ─────────────────────────────────────────────────
OTP_EXPIRY_MINUTES = 10
OTP_LENGTH = 6


def _generate_otp() -> str:
    """Generate a cryptographically secure 6-digit OTP."""
    return "".join([str(secrets.randbelow(10)) for _ in range(OTP_LENGTH)])


# ══════════════════════════════════════════════════════════════════════
# REGISTER
# ══════════════════════════════════════════════════════════════════════

@router.post("/register", response_model=Token, status_code=status.HTTP_201_CREATED)
def register(user: UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.email == user.email).first()
    if db_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    hashed_password = get_password_hash(user.password)
    user_id = str(uuid.uuid4())

    new_user = User(
        id=user_id,
        name=user.name,
        email=user.email,
        hashed_password=hashed_password,
        avatar_url=f"https://api.dicebear.com/7.x/bottts/svg?seed={user.name}",
        streak_days=1,
        longest_streak=1,
        last_active_date=datetime.now(timezone.utc),
        total_xp=50,
        level=1,
    )

    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    access_token = create_access_token(data={"sub": new_user.id})
    return {"access_token": access_token, "token_type": "bearer", "user": new_user}


# ══════════════════════════════════════════════════════════════════════
# LOGIN
# ══════════════════════════════════════════════════════════════════════

@router.post("/login", response_model=Token)
def login(user: UserLogin, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.email == user.email).first()
    if not db_user or not verify_password(user.password, db_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )

    # Update streak
    today = datetime.now(timezone.utc).date()
    if db_user.last_active_date:
        last_active = db_user.last_active_date.date()
        diff = (today - last_active).days
        if diff == 1:
            db_user.streak_days += 1
            if db_user.streak_days > db_user.longest_streak:
                db_user.longest_streak = db_user.streak_days
        elif diff > 1:
            db_user.streak_days = 1

    db_user.last_active_date = datetime.now(timezone.utc)
    db.commit()
    db.refresh(db_user)

    access_token = create_access_token(data={"sub": db_user.id})
    return {"access_token": access_token, "token_type": "bearer", "user": db_user}


# ══════════════════════════════════════════════════════════════════════
# GET CURRENT USER
# ══════════════════════════════════════════════════════════════════════

@router.get("/me", response_model=UserResponse)
def get_me(current_user: User = Depends(get_current_user)):
    return current_user


# ══════════════════════════════════════════════════════════════════════
# FORGOT PASSWORD — Generate & Log OTP
# ══════════════════════════════════════════════════════════════════════

@router.post("/forgot-password", response_model=MessageResponse)
def forgot_password(req: ForgotPasswordRequest, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.email == req.email).first()
    if not db_user:
        # Don't reveal whether email exists (security best practice)
        # But still return success to prevent email enumeration
        return {"message": "If the email exists, a verification code has been sent."}

    otp = _generate_otp()
    hashed_otp = get_password_hash(otp)

    db_user.otp_code = hashed_otp
    db_user.otp_expires_at = datetime.now(timezone.utc) + timedelta(minutes=OTP_EXPIRY_MINUTES)
    db_user.otp_attempts = 0
    db.commit()

    # ── DEV MODE: Log OTP to console ──────────────────────────────────
    logger.info(
        f"\n{'='*50}\n"
        f"  [DEV] PASSWORD RESET OTP for {req.email}\n"
        f"  OTP Code: {otp}\n"
        f"  Expires in: {OTP_EXPIRY_MINUTES} minutes\n"
        f"{'='*50}\n"
    )

    if settings.RESEND_API_KEY:
        try:
            from app.core.email import send_otp_email
            send_otp_email(to_email=req.email, otp=otp, expires_minutes=OTP_EXPIRY_MINUTES)
        except Exception as e:
            logger.error(f"Failed to send OTP email: {e}")

    return {"message": "If the email exists, a verification code has been sent."}


# ══════════════════════════════════════════════════════════════════════
# VERIFY OTP
# ══════════════════════════════════════════════════════════════════════

@router.post("/verify-otp", response_model=MessageResponse)
def verify_otp(req: VerifyOtpRequest, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.email == req.email).first()
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code",
        )

    if getattr(db_user, 'otp_attempts', 0) >= 5:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many attempts. Please request a new code.",
        )

    if not db_user.otp_code or not db_user.otp_expires_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code",
        )

    if datetime.now(timezone.utc) > db_user.otp_expires_at:
        db_user.otp_code = None
        db_user.otp_expires_at = None
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code",
        )

    if not verify_password(req.otp, db_user.otp_code):
        if hasattr(db_user, 'otp_attempts'):
            db_user.otp_attempts += 1
            db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code",
        )

    return {"message": "OTP verified successfully. You may now reset your password."}


# ══════════════════════════════════════════════════════════════════════
# RESET PASSWORD
# ══════════════════════════════════════════════════════════════════════

@router.post("/reset-password", response_model=MessageResponse)
def reset_password(req: ResetPasswordRequest, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.email == req.email).first()
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code",
        )

    if getattr(db_user, 'otp_attempts', 0) >= 5:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many attempts. Please request a new code.",
        )

    if not db_user.otp_code or not db_user.otp_expires_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code",
        )

    if datetime.now(timezone.utc) > db_user.otp_expires_at:
        db_user.otp_code = None
        db_user.otp_expires_at = None
        db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code",
        )

    if not verify_password(req.otp, db_user.otp_code):
        if hasattr(db_user, 'otp_attempts'):
            db_user.otp_attempts += 1
            db.commit()
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired OTP code",
        )

    # Update password and clear OTP
    db_user.hashed_password = get_password_hash(req.new_password)
    db_user.otp_code = None
    db_user.otp_expires_at = None
    if hasattr(db_user, 'otp_attempts'):
        db_user.otp_attempts = 0
    db.commit()

    logger.info(f"[AUTH] Password reset successful for {req.email}")
    return {"message": "Password has been reset successfully. You may now log in."}

