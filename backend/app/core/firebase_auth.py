"""
Firebase Admin SDK — Token Verification.
Replaces the custom JWT auth used previously.
"""

import os
import json
import logging
import firebase_admin
from firebase_admin import credentials, auth
from functools import lru_cache

logger = logging.getLogger("uvicorn")

@lru_cache(maxsize=1)
def _get_app():
    """Initialize Firebase Admin SDK once. Cached — safe to call repeatedly."""
    try:
        # Production: FIREBASE_CREDENTIALS env var contains the full JSON
        cred_json = os.getenv("FIREBASE_CREDENTIALS")
        if cred_json:
            cred_dict = json.loads(cred_json)
            cred = credentials.Certificate(cred_dict)
        else:
            # Local development: use the service account JSON file
            cred = credentials.Certificate("firebase_service_account.json")
        
        return firebase_admin.initialize_app(cred)
    except ValueError:
        # App already initialized (happens if called multiple times)
        return firebase_admin.get_app()

def verify_firebase_token(id_token: str) -> dict | None:
    """
    Verify a Firebase ID token.
    Returns the decoded token claims dict if valid, None if invalid/expired.
    
    Key fields in the returned dict:
        uid   — Firebase user ID (use this as user_id everywhere)
        email — user's email address
        name  — display name (if set)
    """
    try:
        _get_app()
        decoded = auth.verify_id_token(id_token)
        return decoded
    except auth.ExpiredIdTokenError:
        logger.warning("[Firebase] Token expired")
        return None
    except auth.InvalidIdTokenError as e:
        logger.warning(f"[Firebase] Invalid token: {e}")
        return None
    except Exception as e:
        logger.warning(f"[Firebase] Token verification failed: {e}")
        return None
