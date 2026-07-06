"""
Tilawah AI — Audio Proxy & Caching Router.

Endpoint: GET /api/audio/word/{surah}/{ayah}/{word_index}

Acts as a reverse proxy to https://audio.qurancdn.com with local disk caching.
On first request, fetches the MP3 from QuranCDN, saves it locally under
backend/data/audio_cache/, and streams it to the client. Subsequent requests
are served directly from disk without hitting the CDN.
"""

import logging
from pathlib import Path

import httpx
from fastapi import APIRouter, HTTPException, Depends
from fastapi.responses import FileResponse

from app.core.security import get_current_user
from app.models.user import User

logger = logging.getLogger("uvicorn")
router = APIRouter(prefix="/api/audio", tags=["audio"])

# ── Cache directory ───────────────────────────────────────────────────
_CACHE_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "audio_cache"
_CACHE_DIR.mkdir(parents=True, exist_ok=True)

# ── Upstream CDN ──────────────────────────────────────────────────────
_CDN_BASE = "https://audio.qurancdn.com"


def _cache_path(surah: int, ayah: int, word_index: int) -> Path:
    """
    Compute the local cache file path for a word audio clip.

    Structure: data/audio_cache/{surah}/{ayah}/{word_index}.mp3
    """
    directory = _CACHE_DIR / str(surah) / str(ayah)
    directory.mkdir(parents=True, exist_ok=True)
    return directory / f"{word_index}.mp3"

MAX_CACHE_SIZE_MB = 200

def _enforce_cache_limit():
    """Ensure the local audio cache doesn't exceed the specified limit."""
    try:
        files = [f for f in _CACHE_DIR.rglob('*') if f.is_file()]
        total_size = sum(f.stat().st_size for f in files)
        if total_size > MAX_CACHE_SIZE_MB * 1024 * 1024:
            logger.info(f"[Audio] Cache size {total_size / 1024 / 1024:.2f}MB exceeds limit. Pruning oldest files.")
            # Sort by modification time, oldest first
            files.sort(key=lambda f: f.stat().st_mtime)
            # Delete oldest half
            for f in files[:len(files)//2]:
                f.unlink(missing_ok=True)
    except Exception as e:
        logger.error(f"[Audio] Failed to enforce cache limit: {e}")


@router.get("/word/{surah}/{ayah}/{word_index}")
async def get_word_audio(
    surah: int, 
    ayah: int, 
    word_index: int,
    current_user: User = Depends(get_current_user),
):
    """
    Stream the word-by-word recitation audio for a specific word.

    1. Checks if the audio file exists in the local cache.
    2. If cached → streams it immediately from disk.
    3. If not cached → fetches from QuranCDN, saves locally, then streams.

    The CDN URL pattern is:
        https://audio.qurancdn.com/wbw/{surah}/{ayah}/{word_index}/Alafasy.mp3

    Args:
        surah: Surah number (1-114).
        ayah: Ayah number within the surah.
        word_index: 0-based word position within the ayah.
    """
    # ── Input validation ──────────────────────────────────────────────
    if not (1 <= surah <= 114):
        raise HTTPException(status_code=400, detail="Surah number must be between 1 and 114")
    if ayah < 1:
        raise HTTPException(status_code=400, detail="Ayah number must be >= 1")
    if word_index < 0:
        raise HTTPException(status_code=400, detail="Word index must be >= 0")

    cached_file = _cache_path(surah, ayah, word_index)

    # ── Serve from cache ──────────────────────────────────────────────
    if cached_file.exists() and cached_file.stat().st_size > 0:
        logger.debug(f"[Audio] Cache HIT: {surah}/{ayah}/{word_index}")
        return FileResponse(
            path=str(cached_file),
            media_type="audio/mpeg",
            filename=f"{surah}_{ayah}_{word_index}.mp3",
        )

    # ── Fetch from CDN ────────────────────────────────────────────────
    cdn_url = f"{_CDN_BASE}/wbw/{surah}/{ayah}/{word_index}/Alafasy.mp3"
    logger.info(f"[Audio] Cache MISS — fetching from CDN: {cdn_url}")

    try:
        async with httpx.AsyncClient(timeout=15.0, follow_redirects=True) as client:
            response = await client.get(cdn_url)

            if response.status_code == 404:
                raise HTTPException(
                    status_code=404,
                    detail=f"Audio not found on CDN for surah={surah}, ayah={ayah}, word={word_index}",
                )

            response.raise_for_status()

            # ── Save to local cache ───────────────────────────────────
            cached_file.write_bytes(response.content)
            logger.info(
                f"[Audio] Cached {len(response.content)} bytes → {cached_file}"
            )
            # Enforce limit after adding new file
            _enforce_cache_limit()

    except httpx.HTTPStatusError as e:
        logger.error(f"[Audio] CDN HTTP error: {e.response.status_code} for {cdn_url}")
        raise HTTPException(
            status_code=502,
            detail=f"Upstream CDN returned {e.response.status_code}",
        )
    except httpx.RequestError as e:
        logger.error(f"[Audio] CDN connection error: {e}")
        raise HTTPException(
            status_code=502,
            detail="Failed to connect to audio CDN. Please try again later.",
        )

    # ── Stream the freshly cached file ────────────────────────────────
    return FileResponse(
        path=str(cached_file),
        media_type="audio/mpeg",
        filename=f"{surah}_{ayah}_{word_index}.mp3",
    )


# ── Quran verse count lookup ──────────────────────────────────────────
# Standard verse counts per surah (1-indexed). Surah 1 has 7 in standard,
# but the abdulsamad dataset skips verse 3 (الرحمن الرحيم), yielding 6.
_SURAH_VERSES_STD = [
    7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,
    112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,
    59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,14,
    11,52,52,28,28,20,56,40,31,50,40,46,42,29,15,21,15,19,8,14,14,43,12,50,
    25,11,14,17,19,17,75,50,11,11,22,44,103,44,31,15,28,52,46,24,15,21,11,22,
    9,108,9,29,15,13,14,11,3,5,4,7,3,6,6,4,3,4,3,5,6,7,3,3,4,8,5,3,7,5,8,7,
    5,3,3,6,3,5,3,4,4,3,6,
]

# WAV dataset directory for professional recitations
_RECITATION_WAV_DIR = (
    Path("/home/badshah/Documents/DeepSpeech-Quran/data/everyayah_full/wav")
)

# Pre-built sorted list of abdulsamad file suffixes (lazy-loaded once)
_ABDULSAMAD_SUFFIXES: list[int] | None = None

def _get_abdulsamad_suffixes() -> list[int]:
    """Return sorted list of available abdulsamad file suffixes (cached)."""
    global _ABDULSAMAD_SUFFIXES
    if _ABDULSAMAD_SUFFIXES is not None:
        return _ABDULSAMAD_SUFFIXES
    import re
    suffixes: list[int] = []
    if _RECITATION_WAV_DIR.exists():
        for f in _RECITATION_WAV_DIR.iterdir():
            m = re.match(r"abdulsamad_(\d+)\.wav$", f.name)
            if m:
                suffixes.append(int(m.group(1)))
    suffixes.sort()
    _ABDULSAMAD_SUFFIXES = suffixes
    return suffixes


def _dataset_row_index(surah: int, ayah: int) -> int:
    """
    Map a standard (surah, ayah) pair to a 0-based sequential row index in the
    abdulsamad portion of the dataset.

    The dataset uses 6 verses for Surah 1 (standard verse 3 'الرحمن الرحيم' is
    absent), so we apply a correction for Surah 1 and an offset of -1 for all
    subsequent surahs.
    """
    if surah == 1:
        if ayah <= 2:
            return ayah - 1        # A1→0, A2→1
        elif ayah == 3:
            return 2               # No recording; use nearest (مالك يوم الدين)
        else:
            return ayah - 2        # A4→2, A5→3, A6→4, A7→5
    # For Surah 2+: standard cumulative index, minus 1 to account for Surah 1 offset
    std_global = sum(_SURAH_VERSES_STD[:surah - 1]) + (ayah - 1)
    return std_global - 1


def _find_recitation_wav(surah: int, ayah: int) -> Path | None:
    """
    Find the best available WAV file for the given (surah, ayah).

    Strategy:
    1. Compute the sequential row index for abdulsamad.
    2. Index into the sorted suffix list (clamped to valid range).
    3. Return the corresponding WAV path.

    Falls back to None when the WAV directory is unavailable.
    """
    suffixes = _get_abdulsamad_suffixes()
    if not suffixes:
        return None
    row = _dataset_row_index(surah, ayah)
    row = max(0, min(row, len(suffixes) - 1))
    suffix = suffixes[row]
    candidate = _RECITATION_WAV_DIR / f"abdulsamad_{suffix:06d}.wav"
    return candidate if candidate.exists() else None


@router.get("/demo/audio")
async def get_demo_audio(surah: int = 1, ayah: int = 1):
    """
    Get the base64-encoded professional recitation WAV for the given surah/ayah.
    Allows testing the full recitation pipeline without a microphone.

    The audio comes from the abdulsamad reciter subset of the everyayah dataset.
    Falls back to the static correct_recitation.wav when the dataset is unavailable.
    """
    import base64

    if not (1 <= surah <= 114):
        raise HTTPException(status_code=400, detail="surah must be 1-114")
    if ayah < 1:
        raise HTTPException(status_code=400, detail="ayah must be >= 1")

    # ── Try dataset WAV first ─────────────────────────────────────────
    wav_path = _find_recitation_wav(surah, ayah)
    if wav_path is not None:
        logger.info(f"[Demo] Serving dataset WAV for S{surah}:A{ayah}: {wav_path.name}")
        content = wav_path.read_bytes()
        return {
            "audio_base64": base64.b64encode(content).decode("utf-8"),
            "source": wav_path.name,
            "surah": surah,
            "ayah": ayah,
        }

    # ── Static fallback ───────────────────────────────────────────────
    fallback = Path("/home/badshah/Documents/DeepSpeech-Quran/checkpoints/corrections/correct_recitation.wav")
    if not fallback.exists():
        raise HTTPException(status_code=404, detail="Demo audio file not found")
    logger.warning(f"[Demo] Dataset WAV not found for S{surah}:A{ayah}, using static fallback")
    content = fallback.read_bytes()
    return {
        "audio_base64": base64.b64encode(content).decode("utf-8"),
        "source": fallback.name,
        "surah": surah,
        "ayah": ayah,
    }
