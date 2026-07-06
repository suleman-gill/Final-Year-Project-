from fastapi.testclient import TestClient
import pytest
from app.main import app
from app.core.security import get_password_hash, verify_password

client = TestClient(app)

def test_password_security():
    password = "supersecretpassword123"
    hashed = get_password_hash(password)
    assert hashed != password
    assert verify_password(password, hashed) is True
    assert verify_password("wrongpassword", hashed) is False

def test_api_health():
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json()["status"] == "OK"

def test_user_authentication_flow():
    # Register a new user
    user_payload = {
        "name": "Test User",
        "email": "testuser@example.com",
        "password": "Securepassword123"
    }
    
    # Try registration
    response = client.post("/api/auth/register", json=user_payload)
    if response.status_code == 400:
        # User already exists from previous runs, this is fine
        assert "already registered" in response.json()["detail"]
    else:
        assert response.status_code == 201
        data = response.json()
        assert "access_token" in data
        assert data["user"]["email"] == user_payload["email"]

    # Login with the registered user
    login_payload = {
        "email": "testuser@example.com",
        "password": "Securepassword123"
    }
    response = client.post("/api/auth/login", json=login_payload)
    assert response.status_code == 200
    token_data = response.json()
    assert "access_token" in token_data
    token = token_data["access_token"]

    # Get current user profile
    headers = {"Authorization": f"Bearer {token}"}
    response = client.get("/api/auth/me", headers=headers)
    assert response.status_code == 200
    assert response.json()["email"] == "testuser@example.com"


