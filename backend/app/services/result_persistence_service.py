import logging
from datetime import datetime, timezone
from sqlalchemy.orm import Session
from app.models.user import User
from app.models.session import RecitationSession, WordResult, TajweedError, PracticeHistory
from typing import Dict, List, Any

logger = logging.getLogger("uvicorn")

class ResultPersistenceService:
    """
    Handles saving completed recitation sessions, word-level analysis,
    XP gains, level progression, and logging Tajweed errors.
    """
    
    @staticmethod
    def save_session_results(
        db: Session,
        session_id: str,
        user_id: str,
        surah_num: int,
        ayah_num: int,
        results: List[Dict[str, Any]],
        correct_count: int,
        wrong_count: int,
        start_time: datetime
    ) -> Dict[str, Any]:
        """
        Commit recitation results and update user stats in a single transaction.
        """
        try:
            total = correct_count + wrong_count
            accuracy = round((correct_count / total) * 100) if total > 0 else 100
            duration = (datetime.now(timezone.utc) - start_time).total_seconds() * 1000

            # 1. Save session
            db_session = RecitationSession(
                id=session_id,
                user_id=user_id,
                surah_num=surah_num,
                ayah_num=ayah_num,
                correct=correct_count,
                wrong=wrong_count,
                total=total,
                accuracy=accuracy,
                duration_ms=int(duration),
            )
            db.add(db_session)

            # 2. Save each word result
            for r in results:
                db_word = WordResult(
                    session_id=session_id,
                    word_index=r["wordIndex"],
                    arabic=r.get("arabic", ""),
                    is_correct=r["is_correct"],
                    spoken_text=r.get("spoken_text", ""),
                    confidence=r.get("confidence", 0.0),
                    tajweed_error_type=r.get("error_type"),
                )
                db.add(db_word)
                
                # If there is a specific Tajweed error, log it
                if not r["is_correct"] and r.get("error_type"):
                    import uuid
                    db_err = TajweedError(
                        id=str(uuid.uuid4()),
                        session_id=session_id,
                        surah=surah_num,
                        ayah=ayah_num,
                        word_index=r["wordIndex"],
                        rule_type=r.get("error_type", "Pronunciation Error"),
                        severity="warning",
                        confidence=r.get("confidence", 0.0),
                        expected_text=r.get("arabic", ""),
                        detected_text=r.get("spoken_text", ""),
                        correction=r.get("tajweed_tip", "Focus on matching exact vowel sounds.")
                    )
                    db.add(db_err)

            # 3. Save Practice History
            db_history = PracticeHistory(
                user_id=user_id,
                surah=surah_num,
                ayah=ayah_num,
                accuracy=float(accuracy),
                duration_ms=int(duration)
            )
            db.add(db_history)

            # 4. Award XP & Level Up User
            user = db.query(User).filter(User.id == user_id).first()
            if user:
                xp_gained = correct_count * 10 + 5
                user.total_xp += xp_gained
                new_level = int((user.total_xp / 100) ** 0.5) + 1
                if new_level > user.level:
                    user.level = new_level

            db.commit()
            logger.info(f"[Persistence] Recitation session {session_id} saved successfully for user {user_id}.")
            return {
                "correct": correct_count,
                "wrong": wrong_count,
                "accuracy": accuracy,
                "durationMs": int(duration),
            }
        except Exception as e:
            db.rollback()
            logger.error(f"[Persistence] Failed to save session results: {e}")
            raise e
