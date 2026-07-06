from app.models.session import RecitationSession
from datetime import datetime, timezone
import uuid


def test_update_profile(client, auth_headers):
    response = client.put(
        "/api/users/profile",
        json={
            "name": "Updated Name",
            "bio": "New bio"
        },
        headers=auth_headers
    )
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Updated Name"
    assert data["bio"] == "New bio"


def test_get_user_stats(client, auth_headers, db_session, test_user):
    # Add a mock session
    session_id = str(uuid.uuid4())
    recitation = RecitationSession(
        id=session_id,
        user_id=test_user.id,
        surah_num=1,
        ayah_num=1,
        correct=8,
        wrong=2,
        total=10,
        accuracy=80.0,
        duration_ms=5000,
        created_at=datetime.now(timezone.utc)
    )
    db_session.add(recitation)
    db_session.commit()

    response = client.get("/api/users/stats", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()
    assert data["total_sessions"] == 1
    assert data["total_words_recited"] == 10
    assert data["total_correct"] == 8
    assert data["average_accuracy"] == 80.0
