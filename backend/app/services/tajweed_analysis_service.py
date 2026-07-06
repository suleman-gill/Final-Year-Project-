"""Production Tajweed analysis service.

Orchestrates the full pipeline:
  1. G2P: Arabic reference text → expected phoneme sequence
  2. Alignment: jiwer word-level alignment of predicted vs expected phonemes
  3. Classification: per-word correctness + Tajweed rule violation detection
  4. Feedback: structured JSON suitable for the Flutter frontend
"""
from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

import jiwer

from .tajweed_g2p import text_to_phonemes, phonemes_to_string
from .tajweed_rules import (
    detect_tajweed_violations,
    split_phoneme_words,
    phonemes_to_arabic,
    get_tajweed_rule,
    TAJWEED_TIPS,
)

logger = logging.getLogger("uvicorn")


class TajweedAnalysisService:
    """Compares model-predicted phonemes against G2P reference and
    produces structured word-level and rule-level analysis."""

    @staticmethod
    def analyze_verse(
        predicted_phonemes: str,
        expected_arabic: str,
    ) -> Dict[str, Any]:
        """Full verse-level analysis.

        Args:
            predicted_phonemes: Space-separated phoneme string from the model.
            expected_arabic: Diacritised Arabic text of the expected verse.

        Returns:
            Dict with keys:
                word_results: list of per-word result dicts
                tajweed_violations: list of violation dicts
                overall_score: float 0-100
                phoneme_accuracy: float 0-100
                word_accuracy: float 0-100
                ref_phonemes: the reference phoneme string (for debugging)
        """
        # 1. Generate reference phonemes from Arabic text
        ref_phonemes_list = text_to_phonemes(expected_arabic)
        ref_phonemes = phonemes_to_string(ref_phonemes_list)
        logger.info(f"[TajweedAnalysis] ref phonemes: {ref_phonemes[:120]}...")

        # 2. Assign each phoneme in the reference list to its word index
        ref_phonemes_flat = []
        phoneme_to_word_idx = []
        w_idx = 0
        for p in ref_phonemes_list:
            if p == "SP":
                w_idx += 1
            else:
                ref_phonemes_flat.append(p)
                phoneme_to_word_idx.append(w_idx)

        # Clean prediction phonemes (remove SP, pad, unk, |)
        pred_tokens = predicted_phonemes.split()
        pred_phonemes_flat = [p for p in pred_tokens if p not in ("SP", "|", "<pad>", "<unk>")]

        ref_arabic_words = expected_arabic.strip().split()

        logger.info(f"[TajweedAnalysis] ref flat={len(ref_phonemes_flat)}, "
                    f"pred flat={len(pred_phonemes_flat)}, "
                    f"arabic words={len(ref_arabic_words)}")

        # 3. jiwer phoneme-level sequence alignment
        ref_joined = " ".join(ref_phonemes_flat)
        pred_joined = " ".join(pred_phonemes_flat)

        word_out = jiwer.process_words(ref_joined, pred_joined)
        alignment = word_out.alignments[0]

        # 4. Build per-word results
        # Collect aligned predicted phonemes for each reference phoneme index.
        aligned_pred_tokens = [[] for _ in range(len(ref_phonemes_flat))]

        for chunk in alignment:
            if chunk.type == 'equal':
                for i in range(chunk.ref_start_idx, chunk.ref_end_idx):
                    hyp_idx = chunk.hyp_start_idx + (i - chunk.ref_start_idx)
                    if hyp_idx < len(pred_phonemes_flat):
                        aligned_pred_tokens[i].append(pred_phonemes_flat[hyp_idx])
            elif chunk.type == 'substitute':
                ref_len = chunk.ref_end_idx - chunk.ref_start_idx
                hyp_len = chunk.hyp_end_idx - chunk.hyp_start_idx
                for offset in range(max(ref_len, hyp_len)):
                    ref_i = chunk.ref_start_idx + offset
                    hyp_i = chunk.hyp_start_idx + offset
                    if ref_i < chunk.ref_end_idx:
                        if hyp_i < chunk.hyp_end_idx:
                            aligned_pred_tokens[ref_i].append(pred_phonemes_flat[hyp_i])

        word_results: List[Dict[str, Any]] = []
        for w_idx in range(len(ref_arabic_words)):
            arabic_word = ref_arabic_words[w_idx]
            ph_indices = [i for i, x in enumerate(phoneme_to_word_idx) if x == w_idx]
            
            # Extract Tajweed rules present in this word
            word_rules = []
            for idx in ph_indices:
                p = ref_phonemes_flat[idx]
                rule = get_tajweed_rule(p)
                if rule:
                    word_rules.append(rule)
            unique_rules = list(set(word_rules))

            if not ph_indices:
                word_results.append({
                    "word": arabic_word,
                    "recited_word": "[Not Recited]",
                    "status": "correct",
                    "similarity": 1.0,
                    "error_type": None,
                    "tip": None,
                    "rules": unique_rules,
                })
                continue

            ref_w_phons = [ref_phonemes_flat[idx] for idx in ph_indices]
            ref_w = "/".join(ref_w_phons)

            pred_w_phons = []
            for idx in ph_indices:
                pred_w_phons.extend(aligned_pred_tokens[idx])
            
            if not pred_w_phons:
                word_results.append({
                    "word": arabic_word,
                    "recited_word": "[Not Recited]",
                    "status": "missing",
                    "similarity": 0.0,
                    "error_type": "Skipped Word",
                    "tip": "This word was not recited — try again",
                    "rules": unique_rules,
                })
            else:
                pred_w = "/".join(pred_w_phons)
                similarity = _word_phoneme_similarity(ref_w, pred_w)
                error_type, tip = _classify_word_error(ref_w, pred_w)

                if similarity >= 0.85:
                    status = "correct"
                    error_type = None
                    tip = None
                else:
                    status = "incorrect"

                recited_word = phonemes_to_arabic(" ".join(pred_w_phons)).strip()
                if not recited_word:
                    recited_word = "..."  # representation of unrecognized speech

                word_results.append({
                    "word": arabic_word,
                    "recited_word": recited_word,
                    "status": status,
                    "similarity": similarity,
                    "error_type": error_type,
                    "tip": tip,
                    "rules": unique_rules,
                })

        # 5. Phoneme-token level accuracy (flat sequence without SP tokens)
        phon_out = jiwer.process_words(ref_joined, pred_joined)
        phon_hits = sum(
            c.ref_end_idx - c.ref_start_idx
            for c in phon_out.alignments[0]
            if c.type == 'equal'
        )
        phon_total = len(ref_phonemes_flat)
        phoneme_accuracy = (phon_hits / phon_total * 100) if phon_total > 0 else 0.0

        # 6. Word accuracy
        correct_words = sum(1 for w in word_results if w["status"] == "correct")
        total_words = sum(1 for w in word_results if w["status"] in ("correct", "incorrect", "missing"))
        word_accuracy = (correct_words / total_words * 100) if total_words > 0 else 0.0

        # 7. Tajweed violations
        tajweed_violations = detect_tajweed_violations(predicted_phonemes, ref_phonemes)

        # Extract all unique Tajweed rules evaluated on this verse
        rules_set = set()
        for p in ref_phonemes_list:
            rule = get_tajweed_rule(p)
            if rule:
                rules_set.add(rule)
        rules_in_ayah = sorted(list(rules_set))

        # 8. Overall score (weighted: 60% word accuracy + 30% phoneme accuracy + 10% tajweed)
        tajweed_penalty = min(len(tajweed_violations) * 2, 30)
        overall_score = max(0.0, 0.6 * word_accuracy + 0.3 * phoneme_accuracy + 10 - tajweed_penalty)
        overall_score = min(100.0, overall_score)

        return {
            "word_results": word_results,
            "tajweed_violations": tajweed_violations,
            "overall_score": round(overall_score, 1),
            "phoneme_accuracy": round(phoneme_accuracy, 1),
            "word_accuracy": round(word_accuracy, 1),
            "ref_phonemes": ref_phonemes,
            "rules_in_ayah": rules_in_ayah,
        }

    @staticmethod
    def analyze_word(
        predicted_phonemes: str,
        expected_arabic: str,
    ) -> Dict[str, Any]:
        """Single-word analysis.

        Args:
            predicted_phonemes: Space-separated phoneme string for one word.
            expected_arabic: Diacritised Arabic text of the expected word.

        Returns:
            Dict with status, similarity, error_type, tip.
        """
        ref_phonemes_list = text_to_phonemes(expected_arabic)
        ref_phonemes = phonemes_to_string(ref_phonemes_list)

        ref_w = "/".join(ref_phonemes.split())
        pred_w = "/".join(predicted_phonemes.split())

        similarity = _word_phoneme_similarity(ref_w, pred_w)
        error_type, tip = _classify_word_error(ref_w, pred_w)

        if similarity >= 0.85:
            status = "correct"
            error_type = None
            tip = None
        else:
            status = "incorrect"

        return {
            "word": expected_arabic,
            "status": status,
            "similarity": similarity,
            "error_type": error_type,
            "tip": tip,
        }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _word_phoneme_similarity(ref_word: str, pred_word: str) -> float:
    """Compute phoneme-level similarity between two slash-joined phoneme words."""
    ref_tokens = ref_word.split("/")
    pred_tokens = pred_word.split("/")

    if not ref_tokens:
        return 0.0

    ref_str = " ".join(ref_tokens)
    pred_str = " ".join(pred_tokens)

    out = jiwer.process_words(ref_str, pred_str)
    hits = sum(
        c.ref_end_idx - c.ref_start_idx
        for c in out.alignments[0]
        if c.type == 'equal'
    )
    return hits / len(ref_tokens) if ref_tokens else 0.0


def _classify_word_error(ref_word: str, pred_word: str) -> tuple:
    """Determine the primary error type for a mismatched word.

    Returns: (error_type: str, tip: str)
    """
    ref_tokens = ref_word.split("/")
    pred_tokens = pred_word.split("/")

    ref_str = " ".join(ref_tokens)
    pred_str = " ".join(pred_tokens)

    out = jiwer.process_words(ref_str, pred_str)

    tajweed_errors = 0
    pronunciation_errors = 0
    rule_mismatches = []

    for chunk in out.alignments[0]:
        if chunk.type == 'substitute':
            for i in range(chunk.ref_end_idx - chunk.ref_start_idx):
                ref_idx = chunk.ref_start_idx + i
                hyp_idx = chunk.hyp_start_idx + i
                if ref_idx < len(ref_tokens) and hyp_idx < len(pred_tokens):
                    ref_rule = get_tajweed_rule(ref_tokens[ref_idx])
                    if ref_rule:
                        tajweed_errors += 1
                        rule_mismatches.append(ref_rule)
                    else:
                        pronunciation_errors += 1
        elif chunk.type in ('delete', 'insert'):
            pronunciation_errors += (chunk.ref_end_idx - chunk.ref_start_idx) if chunk.type == 'delete' else (chunk.hyp_end_idx - chunk.hyp_start_idx)

    if tajweed_errors > pronunciation_errors and tajweed_errors > 0:
        if rule_mismatches:
            specific_rule = rule_mismatches[0]
            tip = TAJWEED_TIPS.get(specific_rule, f"Review the rule: {specific_rule}")
            return f"Tajweed Error: {specific_rule}", tip
        return "Tajweed Error", "Review the Tajweed rules for this word"
    elif pronunciation_errors > 0:
        return "Pronunciation Error", "Focus on pronouncing each letter clearly"
    else:
        return "Minor Difference", "Very close — keep practicing"
