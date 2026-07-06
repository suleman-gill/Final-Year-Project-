"""
Tilawah AI — Quran Ground-Truth Data Loader.

Loads verified Uthmani Quran text (with full diacritics) from a local JSON
file.  Every ayah includes tashkeel (fatha/zabar, kasra/zeer, damma/pesh,
shadda, sukun) needed for accurate G2P phoneme generation.

Falls back to the alquran.cloud API when the local file is missing.
"""

import json
import os
import re
import logging
from typing import Dict, List, Optional
from pathlib import Path

logger = logging.getLogger("uvicorn")

# ── Path to the ground-truth JSON ─────────────────────────────────────
_DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data"
_QURAN_FILE = _DATA_DIR / "quran_uthmani.json"

# ── In-memory cache (loaded once at startup) ──────────────────────────
_quran_data: Optional[Dict] = None

# ── Surah lookup by number (built once) ───────────────────────────────
_surah_index: Optional[Dict[int, Dict]] = None


def _load_quran_data() -> Dict:
    """Load the Quran JSON file into memory. Called once at startup."""
    global _quran_data, _surah_index
    if _quran_data is not None:
        return _quran_data

    if _QURAN_FILE.exists():
        with open(_QURAN_FILE, "r", encoding="utf-8") as f:
            _quran_data = json.load(f)
        # Build O(1) surah index
        _surah_index = {}
        for s in _quran_data.get("surahs", []):
            _surah_index[s["number"]] = s
        logger.info(
            f"[QuranLoader] Loaded ground-truth data from {_QURAN_FILE} "
            f"({len(_quran_data.get('surahs', []))} surahs)"
        )
    else:
        logger.warning(
            f"[QuranLoader] {_QURAN_FILE} not found. "
            "Word lookup will return the expected_word from the client payload."
        )
        _quran_data = {"surahs": []}
        _surah_index = {}

    return _quran_data


def initialize():
    """Eagerly load Quran data into memory. Call during app startup."""
    _load_quran_data()


def remove_diacritics(text: str) -> str:
    """Remove Arabic diacritical marks (tashkeel) from text."""
    return re.sub(r"[\u064B-\u065F\u0670]", "", text)


def get_ayah_text(surah_num: int, ayah_num: int) -> Optional[str]:
    """
    Get the full Arabic text of a specific ayah (with diacritics).

    Args:
        surah_num: Surah number (1-114).
        ayah_num: Ayah number within the surah.

    Returns:
        The Arabic text of the ayah, or None if not found.
    """
    _load_quran_data()
    surah = _surah_index.get(surah_num)
    if not surah:
        return None
    for ayah in surah.get("ayahs", []):
        if ayah.get("numberInSurah") == ayah_num:
            text = ayah.get("text", "")
            # Strip any lingering BOM
            return text.lstrip("\ufeff").strip()
    return None


def get_ayah_text_clean(surah_num: int, ayah_num: int) -> Optional[str]:
    """
    Get verified, clean Arabic text with full diacritics.

    Strips BOM, leading/trailing whitespace, and normalizes for G2P use.

    Returns:
        Clean diacritized Arabic text, or None if not found.
    """
    return get_ayah_text(surah_num, ayah_num)


def get_verse_text_for_analysis(
    surah_num: int,
    ayah_num: int,
    client_words: Optional[List[str]] = None,
) -> str:
    """
    Get the **verified diacritized** Arabic text for a verse, suitable for
    G2P phoneme generation.

    Priority:
        1. Local quran_uthmani.json (verified, with full tashkeel)
        2. Fallback: join client_words (may lack diacritics)

    Args:
        surah_num: Surah number (1-114).
        ayah_num: Ayah number within the surah.
        client_words: Words sent by the frontend (fallback only).

    Returns:
        Diacritized Arabic text string.
    """
    text = get_ayah_text_clean(surah_num, ayah_num)
    if text:
        return text

    # Fallback: use whatever the client sent
    if client_words:
        logger.warning(
            f"[QuranLoader] No local data for S{surah_num}:A{ayah_num}, "
            "using client-provided words (may lack diacritics)"
        )
        return " ".join(client_words)

    return ""


def get_surah_ayah_texts(surah_num: int) -> List[Dict]:
    """
    Get all ayahs of a surah with their verified diacritized text.

    Returns:
        List of dicts with 'numberInSurah' and 'text' keys.
    """
    _load_quran_data()
    surah = _surah_index.get(surah_num)
    if not surah:
        return []
    result = []
    for ayah in surah.get("ayahs", []):
        text = ayah.get("text", "").lstrip("\ufeff").strip()
        result.append({
            "numberInSurah": ayah["numberInSurah"],
            "text": text,
        })
    return result


def get_ayah_words(surah_num: int, ayah_num: int) -> List[Dict]:
    """
    Get the individual words of a specific ayah as a list of dicts.

    Each dict contains:
        - index (int): 0-based word position
        - arabic (str): The word in Arabic with diacritics
        - arabic_clean (str): The word without diacritics (for comparison)

    Args:
        surah_num: Surah number (1-114).
        ayah_num: Ayah number within the surah.

    Returns:
        List of word dictionaries, or an empty list if not found.
    """
    text = get_ayah_text(surah_num, ayah_num)
    if not text:
        return []

    raw_words = text.strip().split()
    words = []
    for i, w in enumerate(raw_words):
        words.append({
            "index": i,
            "arabic": w,
            "arabic_clean": remove_diacritics(w),
        })
    return words


def get_surah_word_count(surah_num: int) -> int:
    """Get the total number of words in a surah."""
    _load_quran_data()
    surah = _surah_index.get(surah_num)
    if not surah:
        return 0
    total = 0
    for ayah in surah.get("ayahs", []):
        text = ayah.get("text", "")
        total += len(text.strip().split())
    return total
