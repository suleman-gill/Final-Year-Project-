"""
Tilawah AI — WebSocket Recitation Endpoint & ML Inference Pipeline.

Engines:
  • TilawahModelEngine  — Wav2Vec2 fine-tuned model (when MODEL_PATH is set)
  • FallbackCalculatedEngine — Deterministic audio-energy–based engine (dev/testing)

Both engines implement RecitationInferenceEngine and return a unified result dict.
"""

import json
import asyncio
import uuid
import re
import abc
import logging
from datetime import datetime, timezone
from typing import Dict, List, Optional, Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.database import SessionLocal
from app.core.audio_utils import (
    decode_audio_base64,
    resample_to_16khz,
    audio_to_tensor,
    validate_audio_frame,
    compute_audio_energy,
    compute_audio_duration_ms,
    is_speech_present,
)
from app.core import quran_data_loader
from app.models.user import User
from app.models.session import RecitationSession, WordResult
from app.core.firebase_auth import verify_firebase_token
from app.core.redis import session_store
from app.services.tajweed_analysis_service import TajweedAnalysisService
from app.services.tajweed_g2p import text_to_phonemes, phonemes_to_string
from app.services.tajweed_rules import (
    split_phoneme_words,
    phonemes_to_arabic,
    get_tajweed_rule,
    get_base_phoneme,
    TAJWEED_TIPS,
)

logger = logging.getLogger("uvicorn")
router = APIRouter()


# ═══════════════════════════════════════════════════════════════════════
# DIACRITICS HELPER
# ═══════════════════════════════════════════════════════════════════════

def remove_diacritics(text: str) -> str:
    """Remove Arabic diacritical marks (tashkeel) from text."""
    return re.sub(r"[\u064B-\u065F\u0670]", "", text)


# ═══════════════════════════════════════════════════════════════════════
# ABSTRACT BASE — INFERENCE ENGINE
# ═══════════════════════════════════════════════════════════════════════

class RecitationInferenceEngine(abc.ABC):
    """Abstract base class for recitation inference engines."""

    @abc.abstractmethod
    async def initialize(self) -> None:
        """Load model weights or prepare resources."""
        ...

    @abc.abstractmethod
    async def process_audio(
        self,
        audio_base64: str,
        expected_word: str,
        phonetic_data: str = "",
    ) -> Dict[str, Any]:
        """
        Process an audio frame and return inference results.

        Returns:
            dict with keys:
                - is_correct (bool)
                - spoken_text (str)
                - corrected_arabic (str)
                - confidence (float)
                - error_type (str | None)
        """
        ...

    @abc.abstractmethod
    async def process_verse_audio(
        self,
        audio_base64: str,
        expected_words: List[str],
        expected_arabic_text: str = "",
    ) -> Dict[str, Any]:
        """
        Process a full verse audio recording.

        Returns:
            dict with keys:
                - transcription (str)
                - word_results (list of dicts)
                - accuracy (float)
                - correct_count (int)
                - wrong_count (int)
        """
        ...

    @abc.abstractmethod
    async def dispose(self) -> None:
        """Release model resources."""
        ...


# ═══════════════════════════════════════════════════════════════════════
# ARABIC → TAJWEED TOKEN MAPPING
# ═══════════════════════════════════════════════════════════════════════

# Map Arabic base letters (diacritics stripped) to their Tajweed token name.
_ARABIC_TO_TOKEN = {
    "ء": "HAMZA", "ب": "BEH", "ت": "TEH", "ث": "THEH", "ج": "JEEM",
    "ح": "HAH", "خ": "KHAH", "د": "DAL", "ذ": "THAL", "ر": "REH",
    "ز": "ZAIN", "س": "SEEN", "ش": "SHEEN", "ص": "SAD", "ض": "DAD",
    "ط": "TAH", "ظ": "ZAH", "ع": "AIN", "غ": "GHAIN", "ف": "FEH",
    "ق": "QAF", "ك": "KAF", "ل": "LAM", "م": "MEEM", "ن": "NOON",
    "ه": "HEH", "و": "WAW", "ي": "YEH", "ا": "HAMZA", "أ": "HAMZA",
    "إ": "HAMZA", "آ": "HAMZA", "ى": "YEH", "ة": "HEH",
    "ئ": "HAMZA", "ؤ": "HAMZA",
}

# All known Tajweed rule tokens from the model vocabulary
_TAJWEED_RULES = {
    "GHUNNA", "NOON_IDGHAM", "NOON_IDHAR", "NOON_IKHFA", "NOON_IQLAB",
    "MEEM_IDGHAM", "MEEM_IDHAR", "MEEM_IKHFA",
    "MADD_2", "MADD_4", "MADD_6", "MADD_ARID", "MADD_LAZIM",
    "MADD_MUNFASSIL", "MADD_MUTTASIL",
    "LAM_ALLAH_TAFKHEEM", "LAM_ALLAH_TARQEEQ",
    "LAM_QAMARIYYAH", "LAM_SHAMSIYYAH", "LAM_SAAKIN_RULE",
    "RAA_TAFKHEEM", "RAA_TARQEEQ",
    "QAF_Q", "DAL_Q", "BEH_Q", "JEEM_Q", "TAH_Q",
    "TAFKHEEM_DAD", "TAFKHEEM_GHAIN", "TAFKHEEM_KHAH",
    "TAFKHEEM_SAD", "TAFKHEEM_ZAH",
    "IDGHAM_MUTAJANISAYN", "IDGHAM_MUTAMATHILAYN", "IDGHAM_MUTAQARIBAYN",
    "WAQF_JEEM", "WAQF_LA", "WAQF_MIM", "WAQF_QALI", "WAQF_SALI",
}

# Map Tajweed rule tokens to human-readable error descriptions
_TOKEN_TO_ERROR = {
    "GHUNNA": "Ghunna Error",
    "NOON_IDGHAM": "Idgham Error", "NOON_IDHAR": "Izhar Error",
    "NOON_IKHFA": "Ikhfa Error", "NOON_IQLAB": "Iqlab Error",
    "MEEM_IDGHAM": "Meem Idgham Error", "MEEM_IDHAR": "Meem Izhar Error",
    "MEEM_IKHFA": "Meem Ikhfa Error",
    "MADD_2": "Madd Error", "MADD_4": "Madd Error", "MADD_6": "Madd Error",
    "MADD_ARID": "Madd Error", "MADD_LAZIM": "Madd Error",
    "MADD_MUNFASSIL": "Madd Error", "MADD_MUTTASIL": "Madd Error",
    "QAF_Q": "Qalqala Error", "DAL_Q": "Qalqala Error",
    "BEH_Q": "Qalqala Error", "JEEM_Q": "Qalqala Error", "TAH_Q": "Qalqala Error",
}


def arabic_to_expected_tokens(word: str) -> List[str]:
    """
    Convert an Arabic word into the sequence of Tajweed base-letter tokens
    the model is expected to produce.
    """
    clean = remove_diacritics(word)
    tokens = []
    for ch in clean:
        tok = _ARABIC_TO_TOKEN.get(ch)
        if tok:
            tokens.append(tok)
    return tokens


# ═══════════════════════════════════════════════════════════════════════
# PRODUCTION ENGINE — Wav2Vec2 Fine-Tuned Tajweed Model
# ═══════════════════════════════════════════════════════════════════════

class TilawahModelEngine(RecitationInferenceEngine):
    """
    Production inference engine using a fine-tuned Wav2Vec2 Tajweed model.

    The model outputs sequences of Tajweed rule tokens (BEH, NOON_IKHFA,
    MADD_6, LAM_ALLAH_TAFKHEEM, etc.) via CTC decoding. We compare these
    against expected base-letter tokens derived from the Arabic text and
    use any detected Tajweed rule tokens to assess correctness and
    identify specific errors.
    """

    def __init__(self, model_path: str):
        self._model_path = model_path
        self._model = None
        self._processor = None
        self._device = None

    async def initialize(self) -> None:
        """Load Wav2Vec2 model and processor from disk."""
        import torch
        from transformers import Wav2Vec2ForCTC, Wav2Vec2Processor

        self._device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        logger.info(f"[TilawahModel] Loading model from {self._model_path} on {self._device}")

        self._processor = await run_in_threadpool(
            Wav2Vec2Processor.from_pretrained, self._model_path
        )
        self._model = await run_in_threadpool(
            Wav2Vec2ForCTC.from_pretrained, self._model_path
        )
        self._model = self._model.to(self._device)
        self._model.eval()
        logger.info("[TilawahModel] Model loaded and ready for inference.")

    # ── Internal: run the model on raw audio ─────────────────────────
    async def _run_inference(self, audio_np) -> str:
        """Run Wav2Vec2 inference and return the decoded token string."""
        import torch

        def _inference():
            inputs = self._processor(
                audio_np,
                sampling_rate=16000,
                return_tensors="pt",
                padding=True,
            )
            input_values = inputs.input_values.to(self._device)
            with torch.no_grad():
                logits = self._model(input_values).logits
            predicted_ids = torch.argmax(logits, dim=-1)
            transcription = self._processor.batch_decode(predicted_ids)[0]
            return transcription

        return await run_in_threadpool(_inference)

    # ── Word-level audio (kept for backward compat) ──────────────────
    async def process_audio(
        self,
        audio_base64: str,
        expected_word: str,
        phonetic_data: str = "",
    ) -> Dict[str, Any]:
        """Run inference on a single word audio chunk."""
        audio_np = decode_audio_base64(audio_base64)
        if len(audio_np) == 0:
            return self._empty_result(expected_word, "Empty audio frame")

        audio_np = resample_to_16khz(audio_np, 16000)

        if not is_speech_present(audio_np):
            return self._empty_result(expected_word, "No speech detected")

        decoded = await self._run_inference(audio_np)

        # Use G2P-based analysis for accurate comparison
        word_analysis = TajweedAnalysisService.analyze_word(
            decoded, expected_word
        )

        return {
            "is_correct": word_analysis["status"] == "correct",
            "spoken_text": decoded,
            "corrected_arabic": expected_word,
            "confidence": round(word_analysis["similarity"], 4),
            "error_type": word_analysis.get("error_type"),
        }

    # ── Verse-level audio (main flow) ────────────────────────────────
    async def process_verse_audio(
        self,
        audio_base64: str,
        expected_words: List[str],
        expected_arabic_text: str = "",
    ) -> Dict[str, Any]:
        """Run Wav2Vec2 inference on a full verse audio recording.

        Uses TajweedAnalysisService for G2P-based phoneme alignment
        instead of naive token matching.
        """
        audio_np = decode_audio_base64(audio_base64)
        if len(audio_np) == 0:
            return self._empty_verse_result(expected_words, "Empty audio")

        audio_np = resample_to_16khz(audio_np, 16000)

        if not is_speech_present(audio_np):
            return self._empty_verse_result(expected_words, "No speech detected")

        decoded = await self._run_inference(audio_np)
        logger.info(f"[TilawahModel] Verse decoded tokens: {decoded[:200]}")

        # Build the full diacritised Arabic text if not provided
        if not expected_arabic_text:
            expected_arabic_text = " ".join(expected_words)

        # Run full G2P-based analysis
        analysis = await run_in_threadpool(
            TajweedAnalysisService.analyze_verse,
            decoded, expected_arabic_text
        )

        # Map analysis word_results to the format expected by the frontend
        word_results = []
        analysis_words = analysis.get("word_results", [])
        for i, exp_word in enumerate(expected_words):
            if i < len(analysis_words):
                aw = analysis_words[i]
                word_results.append({
                    "wordIndex": i,
                    "arabic": exp_word,
                    "is_correct": aw["status"] == "correct",
                    "spoken_text": aw.get("recited_word", ""),
                    "confidence": round(aw.get("similarity", 0.0), 4),
                    "error_type": aw.get("error_type"),
                    "tajweed_tip": aw.get("tip"),
                    "rules": aw.get("rules", []),
                })
            else:
                # More expected words than analysis returned
                word_results.append({
                    "wordIndex": i,
                    "arabic": exp_word,
                    "is_correct": False,
                    "spoken_text": "[Not Recited]",
                    "confidence": 0.0,
                    "error_type": "Skipped Word",
                    "tajweed_tip": "This word was not recited",
                    "rules": [],
                })

        correct_count = sum(1 for w in word_results if w["is_correct"])
        total = len(expected_words)
        accuracy = analysis.get("word_accuracy", (correct_count / total * 100) if total > 0 else 0)

        return {
            "transcription": decoded,
            "word_results": word_results,
            "accuracy": round(accuracy, 1),
            "correct_count": correct_count,
            "wrong_count": total - correct_count,
            "phoneme_accuracy": analysis.get("phoneme_accuracy", 0.0),
            "overall_score": analysis.get("overall_score", 0.0),
            "tajweed_violations": analysis.get("tajweed_violations", []),
            "rules_in_ayah": analysis.get("rules_in_ayah", []),
        }

    def _align_token_groups(
        self,
        expected_words: List[str],
        expected_groups: List[List[str]],
        spoken_groups: List[List[str]],
    ) -> List[Dict[str, Any]]:
        """Align spoken token groups against expected words."""
        results = []
        spoken_idx = 0

        for i, (exp_word, exp_tokens) in enumerate(zip(expected_words, expected_groups)):
            best_score = 0.0
            best_group_tokens: List[str] = []
            best_j = spoken_idx

            # Search within a window of +3 spoken groups
            search_end = min(spoken_idx + 4, len(spoken_groups))
            for j in range(spoken_idx, search_end):
                score = self._token_sequence_similarity(
                    spoken_groups[j], exp_tokens
                )
                if score > best_score:
                    best_score = score
                    best_group_tokens = spoken_groups[j]
                    best_j = j

            if best_score >= 0.40:
                spoken_idx = best_j + 1

            is_correct = best_score >= 0.50
            error_type = None
            if not is_correct:
                error_type = self._detect_tajweed_error_from_tokens(
                    best_group_tokens, exp_tokens
                )

            results.append({
                "wordIndex": i,
                "arabic": exp_word,
                "is_correct": is_correct,
                "spoken_text": " ".join(best_group_tokens) if best_group_tokens else "",
                "confidence": round(best_score, 4),
                "error_type": error_type,
            })

        return results

    # ── Similarity helpers ────────────────────────────────────────────
    @staticmethod
    def _token_sequence_similarity(
        spoken: List[str], expected: List[str]
    ) -> float:
        """
        Compare two token sequences.
        Base-letter tokens must match; Tajweed rule tokens are bonus.
        """
        if not expected:
            return 1.0 if not spoken else 0.5
        if not spoken:
            return 0.0

        # Filter to base-letter tokens only for core comparison
        spoken_base = [t for t in spoken if t not in _TAJWEED_RULES
                       and t not in ("SP", "|", "FATHA", "KASRA", "DAMMA",
                                     "ALIF_M", "WAW_M", "YEH_M",
                                     "LAM_T", "REH_T")]
        expected_base = [t for t in expected if t not in _TAJWEED_RULES]

        if not expected_base:
            return 0.8  # Edge case: word is all diacritics

        # Levenshtein-based similarity on base-letter tokens
        dist = TilawahModelEngine._levenshtein_tokens(spoken_base, expected_base)
        max_len = max(len(spoken_base), len(expected_base))
        similarity = 1.0 - (dist / max_len) if max_len > 0 else 1.0

        return max(0.0, min(1.0, similarity))

    @staticmethod
    def _levenshtein_tokens(s1: List[str], s2: List[str]) -> int:
        """Levenshtein distance on token lists."""
        if len(s1) < len(s2):
            return TilawahModelEngine._levenshtein_tokens(s2, s1)
        if len(s2) == 0:
            return len(s1)
        prev_row = list(range(len(s2) + 1))
        for i, t1 in enumerate(s1):
            curr_row = [i + 1]
            for j, t2 in enumerate(s2):
                insertions = prev_row[j + 1] + 1
                deletions = curr_row[j] + 1
                substitutions = prev_row[j] + (0 if t1 == t2 else 1)
                curr_row.append(min(insertions, deletions, substitutions))
            prev_row = curr_row
        return prev_row[-1]

    @staticmethod
    def _detect_tajweed_error_from_tokens(
        spoken: List[str], expected: List[str]
    ) -> str:
        """Classify Tajweed error based on token differences."""
        spoken_set = set(spoken)
        expected_set = set(expected)

        # Check for specific Tajweed rule tokens in the spoken output
        # that shouldn't be there, or expected ones that are missing
        spoken_rules = spoken_set & _TAJWEED_RULES

        # Missing expected base letters
        expected_base = {t for t in expected if t not in _TAJWEED_RULES}
        spoken_base = {t for t in spoken if t not in _TAJWEED_RULES}
        missing_base = expected_base - spoken_base

        if any("MADD" in r for r in spoken_rules) or any("MADD" in t for t in missing_base):
            return "Madd Error"
        if any("GHUNNA" in r for r in spoken_rules):
            return "Ghunna Error"
        if any("NOON_IKHFA" in r or "MEEM_IKHFA" in r for r in spoken_rules):
            return "Ikhfa Error"
        if any("IDGHAM" in r for r in spoken_rules):
            return "Idgham Error"
        if any("_Q" in r for r in spoken_rules):
            return "Qalqala Error"
        if any(t in missing_base for t in ("NOON", "MEEM")):
            return "Ghunna Error"
        if any(t in missing_base for t in ("QAF", "DAL", "BEH", "JEEM", "TAH")):
            return "Qalqala Error"

        return "Pronunciation Error"

    @staticmethod
    def _normalized_similarity(a: str, b: str) -> float:
        """Compute normalized Levenshtein similarity between two strings."""
        if not a and not b:
            return 1.0
        if not a or not b:
            return 0.0
        max_len = max(len(a), len(b))
        distance = TilawahModelEngine._levenshtein(a, b)
        return 1.0 - (distance / max_len)

    @staticmethod
    def _levenshtein(s1: str, s2: str) -> int:
        if len(s1) < len(s2):
            return TilawahModelEngine._levenshtein(s2, s1)
        if len(s2) == 0:
            return len(s1)
        prev_row = list(range(len(s2) + 1))
        for i, c1 in enumerate(s1):
            curr_row = [i + 1]
            for j, c2 in enumerate(s2):
                insertions = prev_row[j + 1] + 1
                deletions = curr_row[j] + 1
                substitutions = prev_row[j] + (c1 != c2)
                curr_row.append(min(insertions, deletions, substitutions))
            prev_row = curr_row
        return prev_row[-1]

    @staticmethod
    def _classify_error(expected: str, spoken: str) -> str:
        madd_chars = set("اوي")
        expected_set = set(expected)
        spoken_set = set(spoken)
        missing = expected_set - spoken_set
        if missing & madd_chars:
            return "Madd Error"
        if "ن" in missing or "م" in missing:
            return "Ghunna Error"
        if any(c in missing for c in "قطبجد"):
            return "Qalqala Error"
        if len(spoken) < len(expected) * 0.5:
            return "Idgham Error"
        return "Pronunciation Error"

    async def dispose(self) -> None:
        self._model = None
        self._processor = None
        import torch
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        logger.info("[TilawahModel] Model resources released.")

    @staticmethod
    def _empty_result(expected_word: str, reason: str) -> Dict[str, Any]:
        return {
            "is_correct": False,
            "spoken_text": "",
            "corrected_arabic": expected_word,
            "confidence": 0.0,
            "error_type": reason,
        }

    @staticmethod
    def _empty_verse_result(
        expected_words: List[str], reason: str
    ) -> Dict[str, Any]:
        return {
            "transcription": "",
            "word_results": [
                {
                    "wordIndex": i,
                    "arabic": w,
                    "is_correct": False,
                    "spoken_text": "[Not Recited]",
                    "confidence": 0.0,
                    "error_type": reason,
                }
                for i, w in enumerate(expected_words)
            ],
            "accuracy": 0.0,
            "correct_count": 0,
            "wrong_count": len(expected_words),
            "rules_in_ayah": [],
        }


# ═══════════════════════════════════════════════════════════════════════
# FALLBACK ENGINE — Deterministic Audio-Energy Analysis
# ═══════════════════════════════════════════════════════════════════════

class FallbackCalculatedEngine(RecitationInferenceEngine):
    """
    Deterministic fallback engine for development/testing.

    Uses audio signal analysis (energy, duration) and phonetic rule
    parsing to produce repeatable, non-random results.

    NO random.random() is used anywhere in this class.
    """

    # Phonetic complexity scores for common Arabic phonemes
    _PHONEME_DIFFICULTY = {
        "ع": 0.9, "غ": 0.85, "ح": 0.8, "خ": 0.8, "ص": 0.75,
        "ض": 0.85, "ط": 0.75, "ظ": 0.85, "ق": 0.7, "ث": 0.65,
        "ذ": 0.65, "ش": 0.5, "ر": 0.5, "ه": 0.5, "ن": 0.3,
        "م": 0.3, "ل": 0.3, "ب": 0.2, "ت": 0.2, "س": 0.2,
    }

    async def initialize(self) -> None:
        logger.info("[FallbackEngine] Deterministic fallback engine initialized.")

    async def process_audio(
        self,
        audio_base64: str,
        expected_word: str,
        phonetic_data: str = "",
    ) -> Dict[str, Any]:
        """
        Deterministic inference using audio energy and phonetic analysis.

        Logic:
        1. Decode audio and compute energy + duration
        2. If no speech detected → incorrect
        3. Compute a deterministic 'difficulty score' from the expected word's characters
        4. Combine audio energy with difficulty score to compute confidence
        5. Apply phonetic rules to detect specific Tajweed errors
        """
        audio_np = decode_audio_base64(audio_base64)
        if len(audio_np) == 0:
            return {
                "is_correct": False,
                "spoken_text": "",
                "corrected_arabic": expected_word,
                "confidence": 0.0,
                "error_type": "Empty audio frame",
            }

        energy = compute_audio_energy(audio_np)
        duration_ms = compute_audio_duration_ms(audio_np)
        speech_detected = is_speech_present(audio_np)

        if not speech_detected:
            return {
                "is_correct": False,
                "spoken_text": "",
                "corrected_arabic": expected_word,
                "confidence": 0.0,
                "error_type": "No speech detected — please recite clearly",
            }

        # ── Deterministic confidence calculation ──────────────────────
        word_clean = remove_diacritics(expected_word)
        char_count = max(len(word_clean), 1)

        # Difficulty factor: average phoneme difficulty of the word
        difficulty_scores = [
            self._PHONEME_DIFFICULTY.get(c, 0.15) for c in word_clean
        ]
        avg_difficulty = sum(difficulty_scores) / len(difficulty_scores) if difficulty_scores else 0.15

        # Energy factor: normalize energy (typical speech ~0.03-0.15)
        energy_factor = min(energy / 0.08, 1.0)  # Saturates at 0.08 RMS

        # Duration factor: expected duration ~200ms per Arabic character
        expected_duration_ms = char_count * 200.0
        duration_ratio = min(duration_ms / expected_duration_ms, 1.5)
        duration_factor = min(duration_ratio, 1.0) if duration_ratio >= 0.3 else duration_ratio

        # Final confidence: weighted combination (no randomness)
        confidence = (
            0.40 * energy_factor
            + 0.30 * duration_factor
            + 0.30 * (1.0 - avg_difficulty)
        )
        confidence = max(0.0, min(1.0, confidence))

        # ── Correctness threshold ─────────────────────────────────────
        is_correct = confidence >= 0.55

        # ── Tajweed error classification ──────────────────────────────
        error_type = None
        if not is_correct:
            error_type = self._detect_tajweed_error(
                expected_word, word_clean, phonetic_data, energy, duration_ms
            )

        return {
            "is_correct": is_correct,
            "spoken_text": expected_word if is_correct else f"[low confidence: {confidence:.2f}]",
            "corrected_arabic": expected_word,
            "confidence": round(confidence, 4),
            "error_type": error_type,
        }

    async def dispose(self) -> None:
        logger.info("[FallbackEngine] Fallback engine disposed.")

    async def process_verse_audio(
        self,
        audio_base64: str,
        expected_words: List[str],
        expected_arabic_text: str = "",
    ) -> Dict[str, Any]:
        """Deterministic verse-level analysis using audio energy."""
        audio_np = decode_audio_base64(audio_base64)
        if len(audio_np) == 0:
            return {
                "transcription": "",
                "word_results": [
                    {"wordIndex": i, "arabic": w, "is_correct": False,
                     "spoken_text": "", "confidence": 0.0,
                     "error_type": "Empty audio", "rules": []}
                    for i, w in enumerate(expected_words)
                ],
                "accuracy": 0.0, "correct_count": 0,
                "wrong_count": len(expected_words),
            }

        energy = compute_audio_energy(audio_np)
        duration_ms = compute_audio_duration_ms(audio_np)
        speech_detected = is_speech_present(audio_np)

        word_results = []
        correct_count = 0

        for i, exp_word in enumerate(expected_words):
            if not speech_detected:
                word_results.append({
                    "wordIndex": i, "arabic": exp_word, "is_correct": False,
                    "spoken_text": "", "confidence": 0.0,
                    "error_type": "No speech detected", "rules": []
                })
                continue

            word_clean = remove_diacritics(exp_word)
            char_count = max(len(word_clean), 1)
            difficulty_scores = [
                self._PHONEME_DIFFICULTY.get(c, 0.15) for c in word_clean
            ]
            avg_difficulty = (
                sum(difficulty_scores) / len(difficulty_scores)
                if difficulty_scores else 0.15
            )
            energy_factor = min(energy / 0.08, 1.0)
            per_word_dur = duration_ms / max(len(expected_words), 1)
            expected_dur = char_count * 200.0
            duration_factor = min(per_word_dur / expected_dur, 1.0)

            confidence = (
                0.40 * energy_factor
                + 0.30 * duration_factor
                + 0.30 * (1.0 - avg_difficulty)
            )
            confidence = max(0.0, min(1.0, confidence))
            is_correct = confidence >= 0.55

            error_type = None
            if not is_correct:
                error_type = self._detect_tajweed_error(
                    exp_word, word_clean, "", energy, per_word_dur
                )

            if is_correct:
                correct_count += 1

            word_results.append({
                "wordIndex": i,
                "arabic": exp_word,
                "is_correct": is_correct,
                "spoken_text": exp_word if is_correct else f"[low: {confidence:.2f}]",
                "confidence": round(confidence, 4),
                "error_type": error_type,
                "rules": [],
            })

        total = len(expected_words)
        accuracy = (correct_count / total * 100) if total > 0 else 0

        return {
            "transcription": " ".join(w["spoken_text"] for w in word_results),
            "word_results": word_results,
            "accuracy": round(accuracy, 1),
            "correct_count": correct_count,
            "wrong_count": total - correct_count,
            "rules_in_ayah": [],
        }

    def _detect_tajweed_error(
        self,
        original_word: str,
        clean_word: str,
        phonetic: str,
        energy: float,
        duration_ms: float,
    ) -> str:
        """Deterministic Tajweed error classification based on the word's characters."""
        has_madd = any(c in original_word for c in "آ") or "ـٰ" in original_word
        if has_madd and duration_ms < 300:
            return "Madd Error"

        has_ghunna = any(c in clean_word for c in "نم")
        has_shaddah = "ّ" in original_word
        if has_ghunna and has_shaddah and energy < 0.03:
            return "Ghunna Error"

        qalqala_letters = set("قطبجد")
        if any(c in qalqala_letters for c in clean_word) and energy < 0.025:
            return "Qalqala Error"

        if has_ghunna and duration_ms < 150:
            return "Idgham Error"

        return "Pronunciation Error"


# ═══════════════════════════════════════════════════════════════════════
# ENGINE FACTORY — Selects engine based on MODEL_PATH
# ═══════════════════════════════════════════════════════════════════════

_inference_engine: Optional[RecitationInferenceEngine] = None


async def get_engine() -> RecitationInferenceEngine:
    """Get or create the singleton inference engine."""
    global _inference_engine
    if _inference_engine is None:
        if settings.MODEL_PATH:
            _inference_engine = TilawahModelEngine(settings.MODEL_PATH)
        else:
            _inference_engine = FallbackCalculatedEngine()
        await _inference_engine.initialize()
    return _inference_engine


async def shutdown_engine() -> None:
    """Dispose the inference engine. Called during app shutdown."""
    global _inference_engine
    if _inference_engine is not None:
        await _inference_engine.dispose()
        _inference_engine = None


# ═══════════════════════════════════════════════════════════════════════
# ACTIVE SESSIONS REPOSITORY
# ═══════════════════════════════════════════════════════════════════════

# ACTIVE SESSIONS REPOSITORY is now handled by app.core.redis.session_store


# ═══════════════════════════════════════════════════════════════════════
# DATABASE WRITE HELPER
# ═══════════════════════════════════════════════════════════════════════

def db_save_session(session_data: dict, results: list) -> dict:
    """
    Persist completed recitation session data using the ResultPersistenceService.
    """
    from app.services.result_persistence_service import ResultPersistenceService
    db: Session = SessionLocal()
    try:
        return ResultPersistenceService.save_session_results(
            db=db,
            session_id=session_data["id"],
            user_id=session_data["user_id"],
            surah_num=session_data["surah_num"],
            ayah_num=session_data["ayah_num"],
            results=results,
            correct_count=session_data["correct_count"],
            wrong_count=session_data["wrong_count"],
            start_time=session_data["start_time"]
        )
    finally:
        db.close()


# ═══════════════════════════════════════════════════════════════════════
# TAJWEED FEEDBACK DICTIONARY
# ═══════════════════════════════════════════════════════════════════════

TAJWEED_FEEDBACK = {
    "bismi": "Ensure the 'ba' has a light, quick kasra without elongation.",
    "allahi": "Lam of Jalalah should be pronounced with light thickness (Tarqeeq) due to preceding kasra.",
    "arrahmaani": "Pronounce 'Ra' heavily (Tafkheem). Lengthen the 'ma' for exactly two counts.",
    "arrahiim": "Perform natural lengthening (Madd Asli) on the 'hee' sound.",
    "ghunna error": "Hold the Ghunna (nasal sound) for 2 counts on the letters Nun or Mim.",
    "qalqala error": "Make sure to bounce the sound on the Qalqala letter (Qaf, Ta, Ba, Jim, Dal).",
    "madd error": "Ensure you stretch the vowel for the correct number of counts.",
    "idgham error": "Merge the letters completely without pronouncing the first one.",
    "ikhfa error": "Hide the Nun sound and prepare the mouth for the next letter, holding for 2 counts.",
    "izhar error": "Pronounce the letter clearly without any extra nasal sound (Ghunna).",
    "throat letter error": "Ensure the letter originates from the correct part of the throat.",
    "pronunciation error": "Focus on matching the exact vowel sounds and letter articulation points.",
    "tajweed error": "Review the Tajweed rules for this word — check Ghunna, Madd, and Idgham.",
    "skipped word": "This word was not recited — try again.",
    "no speech detected — please recite clearly": "Make sure your microphone is close and recite clearly.",
    "empty audio frame": "No audio was received. Please check your microphone permissions.",
}
# Merge in detailed tips from tajweed_rules.py
for _rule, _tip in TAJWEED_TIPS.items():
    _key = _rule.lower().strip()
    if _key not in TAJWEED_FEEDBACK:
        TAJWEED_FEEDBACK[_key] = _tip


def get_tajweed_feedback(phonetic: str, error_type: str = None) -> str:
    """Return a Tajweed tip based on the phonetic or error type."""
    if phonetic:
        cleaned = phonetic.lower().replace("'", "").strip()
        if cleaned in TAJWEED_FEEDBACK:
            return TAJWEED_FEEDBACK[cleaned]
    if error_type:
        key = error_type.lower().strip()
        if key in TAJWEED_FEEDBACK:
            return TAJWEED_FEEDBACK[key]
    return f"Focus on matching the exact vowel sounds. Type: {error_type or 'Pronunciation Check'}"


# ═══════════════════════════════════════════════════════════════════════
# WEBSOCKET ENDPOINT
# ═══════════════════════════════════════════════════════════════════════

@router.websocket("/ws/recitation")
async def recitation_endpoint(websocket: WebSocket):
    """
    Real-time recitation WebSocket endpoint.

    Protocol:
        → Client connects
        → Client sends: {"type": "auth", "token": "..."}
        → Client sends: {"type": "start_session", "surahNum": 1, "ayahNum": 1, "words": [...]}
        ...
    """
    await websocket.accept()

    try:
        # Wait for auth message first
        auth_data = await websocket.receive_text()
        msg = json.loads(auth_data)
        if msg.get("type") != "auth":
            await websocket.close(code=4001, reason="First message must be auth")
            return
            
        token = msg.get("token")
        
        # In development environment, allow a guest fallback if token is missing or invalid
        if settings.ENVIRONMENT == "development" and (not token or token == "" or token == "guest"):
            user_id = "dev_guest_user"
            payload = {
                "uid": "dev_guest_user",
                "email": "guest@dev.local",
                "name": "Dev Guest User",
            }
        else:
            if not token:
                await websocket.close(code=4001, reason="Authentication token missing")
                return

            payload = verify_firebase_token(token)
            if not payload:
                from app.core.security import decode_access_token
                payload = decode_access_token(token)
                if not payload:
                    if settings.ENVIRONMENT == "development":
                        user_id = "dev_guest_user"
                        payload = {
                            "uid": "dev_guest_user",
                            "email": "guest@dev.local",
                            "name": "Dev Guest User",
                        }
                    else:
                        await websocket.close(code=4001, reason="Invalid or expired token")
                        return
                else:
                    user_id = payload.get("sub")
            else:
                user_id = payload.get("uid")  # Firebase uses "uid" not "sub"

        # Enforce that user exists in SQL DB (auto-create if missing)
        db = SessionLocal()
        try:
            db_user = db.query(User).filter(User.id == user_id).first()
            if not db_user:
                email = payload.get("email") or f"{user_id}@firebase.app"
                name = payload.get("name") or email.split("@")[0] or "Firebase User"
                avatar_url = payload.get("picture") or f"https://api.dicebear.com/7.x/bottts/svg?seed={name}"
                db_user = User(
                    id=user_id,
                    name=name,
                    email=email,
                    hashed_password="firebase_managed",
                    avatar_url=avatar_url,
                    streak_days=1,
                    longest_streak=1,
                    last_active_date=datetime.now(timezone.utc),
                    total_xp=50,
                    level=1,
                )
                db.add(db_user)
                db.commit()
                db.refresh(db_user)
        finally:
            db.close()

        logger.info(f"[WS] User {user_id} connected successfully")
        
        # Enforce per-user WS connection limit
        conns = await session_store.get_active_connections(user_id)
        if conns >= 2:
            logger.warning(f"[WS] User {user_id} exceeded connection limit")
            await websocket.close(code=4001, reason="Too many active connections")
            return
            
        await session_store.increment_connection(user_id)
        
    except json.JSONDecodeError:
        await websocket.close(code=4001, reason="Invalid auth format")
        return
    except WebSocketDisconnect:
        return

    engine = await get_engine()
    session_id = None

    try:
        while True:
            data = await websocket.receive_text()

            try:
                msg = json.loads(data)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "message": "Invalid JSON format"})
                continue

            msg_type = msg.get("type")

            # ── START SESSION ─────────────────────────────────────────
            if msg_type == "start_session":
                session_id = str(uuid.uuid4())
                session_data = {
                    "id": session_id,
                    "user_id": user_id,
                    "surah_num": msg.get("surahNum", 1),
                    "ayah_num": msg.get("ayahNum", 1),
                    "words": msg.get("words", []),
                    "results": [],
                    "start_time": datetime.now(timezone.utc),
                    "correct_count": 0,
                    "wrong_count": 0,
                }
                await session_store.save_session(session_id, session_data)
                
                await websocket.send_json({
                    "type": "session_ready",
                    "sessionId": session_id,
                    "message": "Session established. Streaming enabled.",
                })
                logger.info(
                    f"[WS] Session {session_id} started for User {user_id} — "
                    f"Surah {msg.get('surahNum')}, Ayah {msg.get('ayahNum')}"
                )

            # ── AUDIO CHUNK ───────────────────────────────────────────
            elif msg_type == "audio_chunk":
                sid = msg.get("sessionId")
                session = await session_store.get_session(sid)
                if not session:
                    await websocket.send_json({"type": "error", "message": "Active session context not found"})
                    continue
                word_index = msg.get("wordIndex")
                audio_base64 = msg.get("audioBase64", "")

                # Guard: reject oversized audio frames
                if not validate_audio_frame(audio_base64, settings.MAX_AUDIO_FRAME_BYTES):
                    await websocket.send_json({
                        "type": "error",
                        "message": f"Audio frame exceeds {settings.MAX_AUDIO_FRAME_BYTES} byte limit",
                    })
                    continue

                # Fetch target word details
                word = next(
                    (w for w in session["words"] if w.get("index") == word_index),
                    None,
                )
                if not word:
                    await websocket.send_json({
                        "type": "error",
                        "message": f"Word index {word_index} not in word list",
                    })
                    continue

                # Call inference engine
                try:
                    result = await engine.process_audio(
                        audio_base64,
                        word.get("arabic", ""),
                        word.get("phonetic", ""),
                    )
                except Exception as e:
                    logger.error(f"[WS] Inference error: {e}")
                    await websocket.send_json({
                        "type": "error",
                        "message": "Inference engine error — please retry",
                    })
                    continue

                # Guard: Wait for actual speech if silence is detected
                if result.get("error_type") == "No speech detected — please recite clearly":
                    continue

                if result["is_correct"]:
                    session["correct_count"] += 1
                else:
                    session["wrong_count"] += 1

                # Format Tajweed feedback
                tajweed_tip = None
                if not result["is_correct"]:
                    tajweed_tip = get_tajweed_feedback(
                        word.get("phonetic", ""), result["error_type"]
                    )

                session["results"].append({
                    "wordIndex": word_index,
                    "arabic": word.get("arabic", ""),
                    "is_correct": result["is_correct"],
                    "spoken_text": result["spoken_text"],
                    "confidence": result["confidence"],
                    "error_type": result["error_type"],
                    "tajweed_tip": tajweed_tip,
                })

                await websocket.send_json({
                    "type": "word_result",
                    "sessionId": sid,
                    "wordIndex": word_index,
                    "arabic": word.get("arabic"),
                    "correctedArabic": result.get("corrected_arabic", word.get("arabic")),
                    "isCorrect": result["is_correct"],
                    "spokenText": result["spoken_text"],
                    "confidence": result["confidence"],
                    "errorType": result["error_type"],
                    "tajweedTip": tajweed_tip,
                })
                
                # Save session back to store
                await session_store.save_session(sid, session)

            # ── VERSE AUDIO (full verse recording) ────────────────────
            elif msg_type == "verse_audio":
                sid = msg.get("sessionId")
                session = await session_store.get_session(sid)
                if not session:
                    await websocket.send_json({
                        "type": "error",
                        "message": "No active session",
                    })
                    continue

                verse_index = msg.get("verseIndex", 0)
                audio_base64 = msg.get("audioBase64", "")
                expected_words = msg.get("expectedWords", [])

                logger.info(
                    f"[WS] verse_audio received: verseIdx={verse_index}, "
                    f"words={len(expected_words)}, base64Len={len(audio_base64)}"
                )

                if not expected_words:
                    await websocket.send_json({
                        "type": "error",
                        "message": "No expected words provided",
                    })
                    continue

                # ── Look up verified diacritized text from local Quran ──
                surah_num = session.get("surah_num", 1)
                ayah_num = session.get("ayah_num", 1) + verse_index
                verified_text = quran_data_loader.get_verse_text_for_analysis(
                    surah_num, ayah_num, client_words=expected_words,
                )
                if verified_text:
                    verified_words = verified_text.strip().split()
                    logger.info(
                        f"[WS] Using verified text for S{surah_num}:A{ayah_num}: "
                        f"{verified_text[:80]}..."
                    )
                else:
                    verified_words = expected_words
                    verified_text = " ".join(expected_words)

                try:
                    result = await engine.process_verse_audio(
                        audio_base64,
                        verified_words,
                        expected_arabic_text=verified_text,
                    )
                except Exception as e:
                    logger.error(f"[WS] Verse inference error: {e}")
                    await websocket.send_json({
                        "type": "error",
                        "message": "Inference engine error — please retry",
                    })
                    continue

                # Update session counters
                session["correct_count"] += result["correct_count"]
                session["wrong_count"] += result["wrong_count"]

                for wr in result["word_results"]:
                    # Use the tip from analysis if available, else fall back
                    tajweed_tip = wr.get("tajweed_tip")
                    if not tajweed_tip and not wr["is_correct"]:
                        tajweed_tip = get_tajweed_feedback(
                            "", wr.get("error_type")
                        )
                    session["results"].append({
                        "wordIndex": wr["wordIndex"],
                        "arabic": wr["arabic"],
                        "is_correct": wr["is_correct"],
                        "spoken_text": wr.get("spoken_text", ""),
                        "confidence": wr.get("confidence", 0.0),
                        "error_type": wr.get("error_type"),
                        "tajweed_tip": tajweed_tip,
                    })

                await session_store.save_session(sid, session)

                # Build response with tajweed tips
                verse_word_results = []
                for wr in result["word_results"]:
                    # Use the tip from analysis if available, else fall back
                    tajweed_tip = wr.get("tajweed_tip")
                    if not tajweed_tip and not wr["is_correct"]:
                        tajweed_tip = get_tajweed_feedback(
                            "", wr.get("error_type")
                        )
                    verse_word_results.append({
                        "wordIndex": wr["wordIndex"],
                        "arabic": wr["arabic"],
                        "isCorrect": wr["is_correct"],
                        "spokenText": wr.get("spoken_text", ""),
                        "confidence": wr.get("confidence", 0.0),
                        "errorType": wr.get("error_type"),
                        "tajweedTip": tajweed_tip,
                        "rules": wr.get("rules", []),
                    })

                # Include tajweed violations in the response
                tajweed_violations = result.get("tajweed_violations", [])

                await websocket.send_json({
                    "type": "verse_result",
                    "sessionId": sid,
                    "verseIndex": verse_index,
                    "transcription": result.get("transcription", ""),
                    "accuracy": result.get("accuracy", 0),
                    "wordResults": verse_word_results,
                    "tajweedViolations": tajweed_violations,
                    "rulesInAyah": result.get("rules_in_ayah", []),
                })
                logger.info(
                    f"[WS] Verse {verse_index} processed — "
                    f"accuracy: {result.get('accuracy', 0)}%, "
                    f"tajweed violations: {len(tajweed_violations)}"
                )

            # ── END SESSION ───────────────────────────────────────────
            elif msg_type == "end_session":
                sid = msg.get("sessionId")
                session = await session_store.get_session(sid)
                if session:
                    await session_store.delete_session(sid)
                    try:
                        if isinstance(session["start_time"], str):
                            session["start_time"] = datetime.fromisoformat(session["start_time"])
                        summary = await run_in_threadpool(
                            db_save_session, session, session["results"]
                        )
                    except Exception as e:
                        logger.error(f"[WS] Failed to save session: {e}")
                        summary = {
                            "correct": session["correct_count"],
                            "wrong": session["wrong_count"],
                            "accuracy": 0,
                            "durationMs": 0,
                        }

                    await websocket.send_json({
                        "type": "session_complete",
                        "sessionId": sid,
                        "summary": summary,
                    })
                    logger.info(f"[WS] Session {sid} finished. Summary: {summary}")

            else:
                await websocket.send_json({
                    "type": "error",
                    "message": f"Unsupported action: {msg_type}",
                })

    except WebSocketDisconnect:
        logger.info(f"[WS] Connection terminated by client for User {user_id}")
        if session_id:
            await session_store.delete_session(session_id)
        await session_store.decrement_connection(user_id)
    except Exception as e:
        logger.error(f"[WS ERROR] {e}")
        try:
            await websocket.send_json({"type": "error", "message": "Internal WebSocket Error"})
        except Exception:
            pass
        if session_id:
            await session_store.delete_session(session_id)
        await session_store.decrement_connection(user_id)
