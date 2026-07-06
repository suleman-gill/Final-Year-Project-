from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from app.core.database import Base

class RecitationSession(Base):
    __tablename__ = "recitation_sessions"
    
    id = Column(String, primary_key=True, index=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), index=True)
    surah_num = Column(Integer, nullable=False)
    ayah_num = Column(Integer, nullable=False)
    correct = Column(Integer, default=0)
    wrong = Column(Integer, default=0)
    total = Column(Integer, default=0)
    accuracy = Column(Float, default=0.0)
    duration_ms = Column(Integer, default=0)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    
    # Relationship to user
    user = relationship("User", backref="sessions")
    # Relationship to word results
    word_results = relationship("WordResult", backref="session", cascade="all, delete-orphan")

class WordResult(Base):
    __tablename__ = "word_results"
    
    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    session_id = Column(String, ForeignKey("recitation_sessions.id", ondelete="CASCADE"), index=True)
    word_index = Column(Integer, nullable=False)
    arabic = Column(String, nullable=False)
    is_correct = Column(Boolean, nullable=False)
    spoken_text = Column(String, nullable=True)
    confidence = Column(Float, nullable=True)
    tajweed_error_type = Column(String, nullable=True) # e.g. "Minor Tajweed Error", "Major Tajweed Error"
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

class TajweedError(Base):
    __tablename__ = "tajweed_errors"

    id = Column(String, primary_key=True, index=True)
    session_id = Column(String, ForeignKey("recitation_sessions.id", ondelete="CASCADE"), index=True)
    surah = Column(Integer, nullable=False)
    ayah = Column(Integer, nullable=False)
    word_index = Column(Integer, nullable=False)
    rule_type = Column(String, nullable=False)
    severity = Column(String, default="warning")
    confidence = Column(Float, nullable=False)
    expected_text = Column(String, nullable=False)
    detected_text = Column(String, nullable=False)
    correction = Column(Text, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

class PracticeHistory(Base):
    __tablename__ = "practice_history"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), index=True)
    surah = Column(Integer, nullable=False)
    ayah = Column(Integer, nullable=False)
    accuracy = Column(Float, default=0.0)
    duration_ms = Column(Integer, default=0)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

class DailyGoal(Base):
    __tablename__ = "daily_goals"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), index=True)
    target_xp = Column(Integer, default=50)
    current_xp = Column(Integer, default=0)
    date = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    is_completed = Column(Boolean, default=False)

class UserProgress(Base):
    __tablename__ = "user_progress"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), index=True)
    surah_num = Column(Integer, nullable=False)
    ayah_num = Column(Integer, nullable=False)
    completed = Column(Boolean, default=False)
    last_practiced = Column(DateTime, default=lambda: datetime.now(timezone.utc))

class Bookmark(Base):
    __tablename__ = "bookmarks"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(String, ForeignKey("users.id", ondelete="CASCADE"), index=True)
    surah_num = Column(Integer, nullable=False)
    ayah_num = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))

