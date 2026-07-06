<p align="center">
  <img src="docs/assets/banner.png" alt="Tilawah AI Banner" width="100%" />
</p>

<h1 align="center">🕌 Tilawah AI</h1>

<p align="center">
  <strong>AI-Powered Quran Recitation Correction with Tajweed Analysis</strong>
</p>

<p align="center">
  <a href="#features"><img src="https://img.shields.io/badge/Features-✨_See_Below-2ea44f?style=for-the-badge" alt="Features"></a>
  <a href="#quick-start"><img src="https://img.shields.io/badge/Quick_Start-🚀_Get_Running-blue?style=for-the-badge" alt="Quick Start"></a>
  <a href="#api-reference"><img src="https://img.shields.io/badge/API-📡_Reference-orange?style=for-the-badge" alt="API Reference"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/python-3.11+-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python 3.11+">
  <img src="https://img.shields.io/badge/flutter-3.2+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.2+">
  <img src="https://img.shields.io/badge/fastapi-0.109+-009688?style=flat-square&logo=fastapi&logoColor=white" alt="FastAPI">
  <img src="https://img.shields.io/badge/pytorch-2.4+-EE4C2C?style=flat-square&logo=pytorch&logoColor=white" alt="PyTorch 2.4+">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square" alt="PRs Welcome">
</p>

<p align="center">
  <em>Recite. Correct. Perfect. — A full-stack AI system that listens to your Quran recitation and provides real-time, word-level Tajweed feedback powered by a fine-tuned Wav2Vec2 (XLS-R 300M) model.</em>
</p>

---

## 📖 Overview

**Tilawah AI** is an end-to-end Quran recitation correction platform that combines deep learning speech recognition with Tajweed rule analysis to help users improve their recitation. The system fine-tunes [XLS-R 300M](https://huggingface.co/facebook/wav2vec2-xls-r-300m) on ~120k Quranic audio samples labeled with **53+ custom Tajweed phoneme tokens** — covering rules like Ghunna, Idgham, Ikhfa, Madd, Qalqalah, and more.

### How It Works

```
┌─────────────┐    WebSocket     ┌──────────────────┐    CTC Decode    ┌──────────────────┐
│  Flutter App │ ──── audio ───► │  FastAPI Backend  │ ──────────────► │  Wav2Vec2 Model  │
│  (Mobile)    │ ◄── results ─── │  + G2P Pipeline   │ ◄── phonemes ── │  (XLS-R 300M)    │
└─────────────┘                  └──────────────────┘                  └──────────────────┘
                                         │
                                   ┌─────┴─────┐
                                   │  jiwer     │
                                   │  Alignment │
                                   └─────┬─────┘
                                         │
                                   Per-word Tajweed
                                   feedback + scores
```

1. **Pick a Surah** → Full 114-surah Quran text (Tanzil Uthmani script with diacritics)
2. **Recite verse-by-verse** → Audio streams to the backend over WebSocket in real-time
3. **AI processes your recitation** → Wav2Vec2 decodes audio into Tajweed phoneme tokens, aligns against expected sequence via `jiwer`
4. **Get instant feedback** → Each word is marked ✅ correct or ❌ incorrect with specific Tajweed error types and improvement tips

---

## ✨ Features

<table>
<tr>
<td width="50%">

### 🎙️ AI Recitation Correction
- Real-time speech recognition via WebSocket
- Word-level accuracy scoring
- Tajweed rule violation detection (Ghunna, Idgham, Ikhfa, Madd, Qalqalah, etc.)
- Phoneme-level alignment and error analysis
- On-demand correction without ending session

</td>
<td width="50%">

### 📖 Quran Reader
- Complete 114-surah Quran text (offline)
- Tajweed color-coded rendering
- Uthmani script with full diacritics
- Scheherazade New Arabic typography
- Surah-by-surah navigation

</td>
</tr>
<tr>
<td width="50%">

### 🕐 Islamic Tools
- Prayer times based on device GPS
- Qibla compass direction finder
- Location-aware calculations

</td>
<td width="50%">

### 📊 Progress Tracking
- Daily streak & XP gamification system
- Session history with detailed results
- Personal recitation statistics
- Dark & light theme support

</td>
</tr>
</table>

---

## 🏗️ Architecture

```mermaid
graph TB
    subgraph Client["📱 Flutter Mobile App"]
        UI[Screens & Widgets]
        RE[Recitation Engine<br/>WebSocket Client]
        QD[Quran Data Service<br/>Offline JSON]
        HV[Hive Local Storage]
    end

    subgraph Server["⚡ FastAPI Backend"]
        WS[WebSocket Endpoint]
        TA[Tajweed Analysis Service]
        G2P[G2P Pipeline]
        AUTH[JWT + Firebase Auth]
        DB[(SQLAlchemy<br/>SQLite / PostgreSQL)]
        RD[(Redis<br/>Session Store)]
    end

    subgraph ML["🧠 ML Pipeline"]
        W2V[Wav2Vec2-XLS-R-300M<br/>Fine-tuned CTC]
        VOC[53+ Tajweed Phoneme Vocab]
        JW[jiwer Alignment]
    end

    RE -->|Audio Base64| WS
    WS --> TA
    TA --> G2P
    TA --> JW
    G2P --> W2V
    W2V --> JW
    WS -->|Per-word Results| RE
    AUTH --> DB
    WS --> RD
```

---

## 🛠️ Tech Stack

<details>
<summary><strong>Backend</strong> — Python / FastAPI</summary>

| Layer | Technology |
|:---|:---|
| **Framework** | FastAPI 0.109+ with Uvicorn |
| **ML Model** | Wav2Vec2ForCTC (XLS-R 300M), PyTorch 2.4+, Transformers 4.40+ |
| **Real-time** | WebSocket via `websockets` 12+ |
| **Database** | SQLAlchemy 2.0 + Alembic (SQLite dev / PostgreSQL prod) |
| **Auth** | JWT (`python-jose`), bcrypt (`passlib`), Firebase Admin SDK |
| **Session Store** | Redis (with in-memory fallback) |
| **Audio** | soundfile, pydub, imageio-ffmpeg, librosa (16kHz resampling) |
| **Tajweed** | Custom G2P pipeline, jiwer phoneme alignment, pyarabic |
| **Rate Limiting** | slowapi |
| **Monitoring** | Sentry SDK (optional) |

</details>

<details>
<summary><strong>Frontend</strong> — Flutter / Dart</summary>

| Layer | Technology |
|:---|:---|
| **Framework** | Flutter 3.2+ (Dart) |
| **State** | Riverpod |
| **Navigation** | go_router |
| **HTTP** | Dio with JWT interceptor |
| **WebSocket** | web_socket_channel |
| **Audio** | record (mic capture), just_audio (playback) |
| **Storage** | Hive, flutter_secure_storage |
| **Auth** | Firebase Auth + Firebase Core |
| **UI** | Google Fonts (Scheherazade), Lottie, Shimmer, flutter_animate |
| **Quran Text** | Offline JSON — Tanzil Uthmani (`quran_complete.json`) |

</details>

<details>
<summary><strong>Training Pipeline</strong> — HuggingFace / PyTorch</summary>

| Component | Details |
|:---|:---|
| **Base Model** | `facebook/wav2vec2-xls-r-300m` |
| **Training** | HuggingFace Trainer, CTC loss |
| **Dataset** | ~120k WAV samples (EveryAyah, abdulsamad reciter) |
| **Phoneme Vocab** | 53+ custom Tajweed tokens (Qalqalah, Madd variants, Noon/Meem rules) |
| **Evaluation** | PER (Phoneme Error Rate), WER, jiwer |

</details>

<details>
<summary><strong>Infrastructure</strong></summary>

- Docker + docker-compose (PostgreSQL 15, Redis 7)
- GitHub Actions CI (`pytest` on push/PR)
- Production & development Dockerfiles

</details>

---

## 📁 Project Structure

```
tilawah-ai/
├── backend/
│   ├── app/
│   │   ├── main.py                  # FastAPI entry point, lifespan events
│   │   ├── core/                    # Config, DB, security, audio utils, Redis
│   │   ├── models/                  # SQLAlchemy ORM models (User, Session)
│   │   ├── routers/                 # REST endpoints (auth, users, audio)
│   │   ├── schemas/                 # Pydantic request/response schemas
│   │   ├── services/                # Tajweed analysis, G2P, rule detection
│   │   └── websocket/               # Real-time recitation WebSocket handler
│   ├── data/                        # Quran text JSON, audio cache
│   ├── models/tajweed_model/        # Fine-tuned Wav2Vec2 weights (gitignored)
│   ├── tests/                       # pytest suite
│   ├── alembic/                     # DB migrations
│   ├── requirements.txt
│   ├── Dockerfile / Dockerfile.prod
│   └── .env.example
│
├── frontend/
│   ├── lib/
│   │   ├── main.dart                # App entry, Firebase & Hive init
│   │   ├── config/                  # Routes, themes, providers
│   │   ├── core/                    # API client, local storage
│   │   ├── features/                # Auth & recitation state management
│   │   ├── screens/                 # All app screens (auth, quran, recitation, etc.)
│   │   ├── services/                # Quran data, prayer time services
│   │   └── widgets/                 # Reusable UI components
│   ├── assets/                      # Quran JSON, fonts, images
│   └── pubspec.yaml
│
├── docker-compose.yml               # Production stack (Backend + PostgreSQL + Redis)
├── .github/workflows/               # CI pipeline
└── train_local.py                   # Model training script
```

---

## 🚀 Quick Start

### Prerequisites

| Requirement | Version | Notes |
|:---|:---|:---|
| Python | 3.11+ | Backend runtime |
| Flutter SDK | 3.2+ | Mobile/web frontend |
| ffmpeg | Latest | Audio format conversion |
| GPU (NVIDIA) | Optional | Recommended for training; inference works on CPU |

### 1. Clone the Repository

```bash
git clone https://github.com/Faisal-Riaz-1/DeepSpeech-Quran.git
cd DeepSpeech-Quran
```

### 2. Backend Setup

```bash
cd backend

# Create virtual environment
python -m venv .venv
source .venv/bin/activate        # Linux/macOS
# .venv\Scripts\activate         # Windows

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env — set DATABASE_URL and JWT_SECRET_KEY at minimum

# Run database migrations (PostgreSQL)
alembic upgrade head

# Start the server
python run.py
# ✅ Server running at http://0.0.0.0:8000
```

### 3. Frontend Setup

```bash
cd frontend

# Install dependencies
flutter pub get

# Verify setup
flutter doctor

# Run on connected device/emulator
flutter run
```

### 4. Model Weights

The trained Wav2Vec2 checkpoint goes in `backend/models/tajweed_model/`. This directory is gitignored.

**Option A:** Train the model yourself (see [Training](#-training-the-model))

**Option B:** Copy an existing checkpoint into the directory

Then set in your `.env`:
```env
MODEL_PATH=models/tajweed_model/final
```

> [!NOTE]
> Without a model checkpoint, the backend falls back to `FallbackCalculatedEngine` — a deterministic audio-energy heuristic useful only for UI testing, not real speech recognition.

### 5. Docker (Production)

```bash
# From repo root — spins up Backend + PostgreSQL + Redis
docker-compose up --build

# Backend → :8000  |  PostgreSQL → :5432  |  Redis → :6379
```

---

## ⚙️ Configuration

### Backend Environment Variables

Create `backend/.env` from `.env.example`:

| Variable | Required | Default | Description |
|:---|:---:|:---|:---|
| `DATABASE_URL` | ✅ | `sqlite:///./tilawah.db` | SQLAlchemy connection string |
| `JWT_SECRET_KEY` | ✅ | — | JWT signing secret (≥32 chars in production) |
| `MODEL_PATH` | — | — | Path to fine-tuned Wav2Vec2 checkpoint |
| `REDIS_URL` | — | `redis://localhost:6379` | Redis connection URL |
| `ENVIRONMENT` | — | `development` | `development` or `production` |
| `RESEND_API_KEY` | — | — | For sending OTP emails |
| `GOOGLE_CLIENT_ID` | — | — | Google OAuth client ID |
| `SENTRY_DSN` | — | — | Sentry error tracking DSN |

### Frontend Build-Time Variables

Passed via `--dart-define` at build time:

| Variable | Default | Description |
|:---|:---|:---|
| `API_BASE_URL` | localtunnel fallback | Backend server URL |

```bash
# Example: custom backend URL
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000
```

---

## 📡 API Reference

### REST Endpoints

| Method | Endpoint | Auth | Description |
|:---:|:---|:---:|:---|
| `POST` | `/api/auth/register` | ❌ | Create a new account |
| `POST` | `/api/auth/login` | ❌ | Login, returns JWT |
| `GET` | `/api/auth/me` | ✅ | Get current user profile |
| `POST` | `/api/auth/forgot-password` | ❌ | Request password reset OTP |
| `POST` | `/api/auth/verify-otp` | ❌ | Verify OTP code |
| `POST` | `/api/auth/reset-password` | ❌ | Reset password with OTP |
| `GET` | `/api/audio/word/{surah}/{ayah}/{word_index}` | ✅ | Word-by-word Alafasy audio (cached CDN proxy) |
| `GET` | `/api/audio/demo/audio?surah=1&ayah=1` | ❌ | Demo recitation audio |
| `GET` | `/api/health` | ❌ | Health check (DB, Redis, model status) |

### WebSocket Protocol

**Endpoint:** `ws://localhost:8000/ws/recitation`

```
1. AUTH        →  { "type": "auth", "token": "<JWT>" }
               ←  Auth confirmation

2. START       →  { "type": "start_session", "surahNum": 1, "ayahNum": 1, "words": [...] }
               ←  { "type": "session_ready", "sessionId": "..." }

3. RECITE      →  { "type": "verse_audio", "sessionId": "...", "verseIndex": 1,
                     "expectedWords": [...], "audioBase64": "..." }
               ←  { "type": "verse_result", "words": [
                       { "word": "بِسْمِ", "correct": true, "score": 0.95,
                         "tajweedRules": ["KASRA"], "feedback": null },
                       { "word": "ٱللَّهِ", "correct": false, "score": 0.62,
                         "tajweedRules": ["MADD"], "feedback": "Focus on Madd elongation" }
                     ] }

4. END         →  { "type": "end_session", "sessionId": "..." }
               ←  Session summary with overall stats
```

---

## 🧠 Training the Model

The training script fine-tunes XLS-R 300M on the EveryAyah dataset with custom Tajweed phoneme labels.

```bash
# Full training run (~120k samples, 15 epochs)
python train_local.py --epochs 15 --max-train 120000

# Quick smoke test
python train_local.py --epochs 1 --max-train 5000

# Custom configuration
python train_local.py --output-dir ./checkpoints/my_run --lr 1e-4
```

### Training Requirements

| Requirement | Details |
|:---|:---|
| **Dataset** | `data/everyayah_full/` — WAV files + train/dev/test CSVs |
| **Vocab** | `data/everyayah_full/vocab_phoneme.json` — 53+ Tajweed tokens |
| **GPU** | ≥12 GB VRAM recommended (tested on RTX 4080) |
| **Output** | `<output-dir>/final/` — model weights + `test_results.json` (PER, WER) |

### Tajweed Phoneme Vocabulary

The model uses a custom vocabulary of 53+ tokens that encode both standard Arabic phonemes and Tajweed rule markers:

```
Standard:  ALEF  BEH  TEH  THEH  JEEM  HAH  KHAH  DAL  ...
Diacritics: FATHA  KASRA  DAMMA  SUKUN  SHADDA  TANWIN_FATHA  ...
Tajweed:   GHUNNA  IDGHAM  IKHFA  MADD  QALQALAH  MEEM_IDGHAM  ...
```

---

## 🧪 Testing

### Backend

```bash
cd backend

# Full test suite
pytest -v

# Quick integrity checks (imports, password hashing)
python run_tests.py
```

### Frontend

```bash
cd frontend

# All tests
flutter test

# Specific test
flutter test test/streak_test.dart

# Static analysis
flutter analyze
```

### CI/CD

Backend tests run automatically on every push and pull request to `main` via GitHub Actions (`.github/workflows/backend-ci.yml`).

---

## 🤝 Contributing

Contributions are welcome! Here's how to get started:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### Development Guidelines

- Backend code follows PEP 8 conventions
- Frontend follows Dart/Flutter style guidelines (`flutter analyze` must pass)
- All new backend features should include pytest coverage
- WebSocket protocol changes must be backward-compatible

---

## ⚠️ Known Limitations

| Area | Limitation |
|:---|:---|
| **Fallback Engine** | `FallbackCalculatedEngine` (no model loaded) uses audio energy heuristics — no real ASR |
| **Audio Cache** | Basic LRU pruning at 200 MB; no background cleanup |
| **Demo Endpoint** | `/api/audio/demo/audio` uses hardcoded paths; won't work in containers without volume mounts |
| **Web Platform** | Prayer times & Qibla require HTTPS + device sensors (GPS, compass) |
| **Single Reciter** | Model trained on abdulsamad reciter only; multi-reciter generalization not evaluated |

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [**EveryAyah.com**](https://everyayah.com/) — Quranic audio dataset
- [**Tanzil.net**](https://tanzil.net/) — Verified Uthmani Quran text
- [**HuggingFace**](https://huggingface.co/) — Transformers library and XLS-R model
- [**Facebook AI**](https://ai.meta.com/) — XLS-R 300M base model
- [**jiwer**](https://github.com/jitsi/jiwer) — Word/phoneme error rate alignment

---

<p align="center">
  <strong>Built with ❤️ as a Final Year Project</strong>
  <br />
  <sub>If this project helped you, please consider giving it a ⭐</sub>
</p>
