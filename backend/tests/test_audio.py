from unittest.mock import patch


def test_get_word_audio_unauthorized(client):
    response = client.get("/api/audio/word/1/1/1")
    assert response.status_code == 401


@patch("app.routers.audio.httpx.AsyncClient.get")
def test_get_word_audio_authorized(mock_get, client, auth_headers):
    # Mock the CDN response
    class MockResponse:
        status_code = 200
        content = b"fake audio content"
        def raise_for_status(self): pass

    mock_get.return_value = MockResponse()

    response = client.get("/api/audio/word/1/1/1", headers=auth_headers)
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/mpeg"


def test_audio_resampling_pipeline():
    import numpy as np
    from app.core.audio_utils import resample_to_16khz
    import pytest
    
    try:
        import torchaudio
        import torch
    except ImportError:
        pytest.skip("torchaudio or torch not installed, skipping resampling test.")
    
    # Create a 1-second mock audio wave at 8000 Hz sample rate
    original_sr = 8000
    t = np.linspace(0, 1.0, original_sr, dtype=np.float32)
    mock_audio = np.sin(2 * np.pi * 440 * t)
    
    # Resample to the target Wav2Vec2 sample rate (16000 Hz)
    resampled = resample_to_16khz(mock_audio, original_sr)
    
    assert resampled is not None
    assert resampled.dtype == np.float32
    # Verify that the signal duration matches target sample rate (8000Hz -> 16000Hz doubles length)
    assert len(resampled) == 16000
