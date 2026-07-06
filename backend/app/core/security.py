import bcrypt
from jose import JWTError, jwt
from datetime import datetime, timedelta, timezone
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.orm import Session
from app.core import config
from app.core.database import get_db
from app.models.user import User

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/auth/login", auto_error=False)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except ValueError:
        return False

def get_password_hash(password: str) -> str:
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password.encode('utf-8'), salt).decode('utf-8')

def create_access_token(data: dict, expires_delta: timedelta = None) -> str:
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=config.ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, config.JWT_SECRET_KEY, algorithm=config.JWT_ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, config.JWT_SECRET_KEY, algorithms=[config.JWT_ALGORITHM])
        return payload
    except JWTError:
        return None

from app.core.firebase_auth import verify_firebase_token

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    if not token:
        raise credentials_exception
        
    payload = verify_firebase_token(token)
    if payload is None:
        # Fall back to decoding custom JWT for compatibility/testing
        payload = decode_access_token(token)
        if payload is None:
            raise credentials_exception
        user_id = payload.get("sub")
    else:
        user_id = payload.get("uid")
        
    if user_id is None:
        raise credentials_exception
        
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        # Auto-create user record for new Firebase users
        email = payload.get("email") or f"{user_id}@firebase.app"
        name = payload.get("name") or email.split("@")[0] or "Firebase User"
        avatar_url = payload.get("picture") or f"https://api.dicebear.com/7.x/bottts/svg?seed={name}"
        
        user = User(
            id=user_id,
            name=name,
            email=email,
            hashed_password="firebase_managed", # satisfies nullable=False
            avatar_url=avatar_url,
            streak_days=1,
            longest_streak=1,
            last_active_date=datetime.now(timezone.utc),
            total_xp=50,
            level=1,
        )
        db.add(user)
        db.commit()
        db.refresh(user)
        
    return user
