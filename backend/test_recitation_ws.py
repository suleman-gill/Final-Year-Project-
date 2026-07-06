import asyncio
import websockets
import json
import base64
import httpx

API_URL = "http://localhost:8000"
WS_URL = "ws://localhost:8000/ws/recitation"
EMAIL = "221980068@gift.edu.pk"
PASSWORD = "falconhere2.0"
AUDIO_PATH = "/home/badshah/Documents/DeepSpeech-Quran/checkpoints/corrections/correct_recitation.wav"

async def test_recitation():
    print("1. Authenticating via REST API...")
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{API_URL}/api/auth/login",
            json={"email": EMAIL, "password": PASSWORD}
        )
        if response.status_code != 200:
            print("Authentication failed:", response.text)
            return
        
        data = response.json()
        token = data["access_token"]
        print("Logged in successfully. Token acquired.")

    print("\n2. Connecting to WebSocket...")
    async with websockets.connect(WS_URL) as ws:
        # Send Auth
        print("Sending auth message...")
        await ws.send(json.dumps({"type": "auth", "token": token}))
        
        # Start session
        print("Starting recitation session...")
        words = [
            {"index": 0, "arabic": "بِسْمِ", "phonetic": "bism"},
            {"index": 1, "arabic": "اللَّهِ", "phonetic": "allāh"},
            {"index": 2, "arabic": "الرَّحْمَٰنِ", "phonetic": "arraḥmān"},
            {"index": 3, "arabic": "الرَّحِيمِ", "phonetic": "arraḥīm"}
        ]
        await ws.send(json.dumps({
            "type": "start_session",
            "surahNum": 1,
            "ayahNum": 1,
            "words": words
        }))

        # Wait for session_ready
        res = await ws.recv()
        session_ready = json.loads(res)
        print("Received:", session_ready)
        if session_ready.get("type") != "session_ready":
            print("Failed to initialize session.")
            return
        
        session_id = session_ready["sessionId"]
        print(f"Session established with ID: {session_id}")

        # Read audio file and encode to base64
        print(f"\n3. Loading audio file from {AUDIO_PATH}...")
        with open(AUDIO_PATH, "rb") as f:
            audio_bytes = f.read()
        audio_base64 = base64.b64encode(audio_bytes).decode("utf-8")
        print(f"Audio loaded ({len(audio_bytes)} bytes, base64 length: {len(audio_base64)})")

        # Send verse_audio
        print("\n4. Sending verse_audio message for processing...")
        await ws.send(json.dumps({
            "type": "verse_audio",
            "sessionId": session_id,
            "verseIndex": 1,
            "expectedWords": ["بِسْمِ", "اللَّهِ", "الرَّحْمَٰنِ", "الرَّحِيمِ"],
            "audioBase64": audio_base64
        }))

        # Wait for verse_result
        print("Waiting for recitation feedback from the engine...")
        res = await ws.recv()
        result = json.loads(res)
        print("\n--- RECITATION RESULTS ---")
        print(json.dumps(result, indent=2, ensure_ascii=False))

        # End session
        print("\n5. Ending session...")
        await ws.send(json.dumps({
            "type": "end_session",
            "sessionId": session_id
        }))
        res = await ws.recv()
        print("End Session response:", json.loads(res))

if __name__ == "__main__":
    asyncio.run(test_recitation())
