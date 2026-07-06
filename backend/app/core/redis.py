import json
import logging
from typing import Dict, Any, Optional
import redis.asyncio as redis
from app.core.config import settings

logger = logging.getLogger("uvicorn")

class SessionStore:
    def __init__(self):
        self._redis: Optional[redis.Redis] = None
        self._fallback: Dict[str, Dict[str, Any]] = {}
        self._user_conns: Dict[str, int] = {}
        self._use_redis = False

    async def initialize(self):
        if settings.REDIS_URL:
            try:
                self._redis = redis.from_url(settings.REDIS_URL, decode_responses=True)
                await self._redis.ping()
                self._use_redis = True
                logger.info("Successfully connected to Redis for session storage.")
            except Exception as e:
                logger.warning(f"Failed to connect to Redis ({e}). Falling back to in-memory dict.")
                self._use_redis = False
        else:
            logger.info("REDIS_URL not set. Using in-memory dict for session storage.")
            self._use_redis = False

    async def get_session(self, session_id: str) -> Optional[Dict[str, Any]]:
        if self._use_redis:
            try:
                data = await self._redis.get(f"session:{session_id}")
                if data:
                    # Parse JSON
                    sess = json.loads(data)
                    return sess
                return None
            except Exception as e:
                logger.error(f"Redis get error: {e}")
                # Fallback to local dict temporarily
                return self._fallback.get(session_id)
        else:
            return self._fallback.get(session_id)

    async def save_session(self, session_id: str, data: Dict[str, Any]):
        if self._use_redis:
            try:
                # Need to convert datetime to isoformat before serializing
                serialized = json.dumps(data, default=str)
                await self._redis.set(f"session:{session_id}", serialized, ex=86400) # 24 hr expiry
            except Exception as e:
                logger.error(f"Redis set error: {e}")
                self._fallback[session_id] = data
        else:
            self._fallback[session_id] = data

    async def delete_session(self, session_id: str):
        if self._use_redis:
            try:
                await self._redis.delete(f"session:{session_id}")
            except Exception as e:
                logger.error(f"Redis delete error: {e}")
        self._fallback.pop(session_id, None)

    async def get_active_connections(self, user_id: str) -> int:
        if self._use_redis:
            try:
                val = await self._redis.get(f"ws_conns:{user_id}")
                return int(val) if val else 0
            except Exception:
                return self._user_conns.get(user_id, 0)
        return self._user_conns.get(user_id, 0)
        
    async def increment_connection(self, user_id: str):
        if self._use_redis:
            try:
                await self._redis.incr(f"ws_conns:{user_id}")
                await self._redis.expire(f"ws_conns:{user_id}", 3600)
            except Exception:
                self._user_conns[user_id] = self._user_conns.get(user_id, 0) + 1
        else:
            self._user_conns[user_id] = self._user_conns.get(user_id, 0) + 1
            
    async def decrement_connection(self, user_id: str):
        if self._use_redis:
            try:
                val = await self._redis.decr(f"ws_conns:{user_id}")
                if val < 0:
                    await self._redis.set(f"ws_conns:{user_id}", 0)
            except Exception:
                self._user_conns[user_id] = max(0, self._user_conns.get(user_id, 0) - 1)
        else:
            self._user_conns[user_id] = max(0, self._user_conns.get(user_id, 0) - 1)

session_store = SessionStore()
