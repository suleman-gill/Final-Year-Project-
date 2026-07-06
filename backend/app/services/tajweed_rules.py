"""Tajweed violation detection engine.

Ported from eval_recitation1.py — provides phoneme-level alignment via jiwer
and rule-based classification of Tajweed errors. Used by TajweedAnalysisService
to compare model predictions against G2P-generated reference phonemes.
"""
from __future__ import annotations

import logging
from typing import Dict, List, Optional

import jiwer

from .phoneme_constants import PHONEME_TO_LETTER

logger = logging.getLogger("uvicorn")

# =========================================================================
# TAJWEED RULE CLASSIFICATION
# =========================================================================
TAJWEED_RULES: Dict[str, str] = {
    # Original basic categories
    "_Q":       "Qalqalah (قلقلة)",
    "_T":       "Tafkheem (تفخيم)",
    "_IDGHAM":  "Idgham (إدغام)",
    "_IKHFA":   "Ikhfa (إخفاء)",
    "_IQLAB":   "Iqlab (إقلاب)",
    "_IDHAR":   "Idhar (إظهار)",
    "GHUNNA":   "Ghunna (غنة)",
    "MADD_2":   "Madd 2 counts (مد)",
    "MADD_4":   "Madd 4 counts (مد)",
    "MADD_6":   "Madd 6 counts (مد)",

    # 80-phoneme specific rules
    "RAA_TAFKHEEM":         "Tafkheem of Raa (تفخيم الراء)",
    "RAA_TARQEEQ":          "Tarqeeq of Raa (ترقيق الراء)",
    "LAM_ALLAH_TAFKHEEM":   "Tafkheem of Lam in Allah (تفخيم لام الجلالة)",
    "LAM_ALLAH_TARQEEQ":    "Tarqeeq of Lam in Allah (ترقيق لام الجلالة)",
    "TAFKHEEM_KHAH":        "Tafkheem of Khah (تفخيم الخاء)",
    "TAFKHEEM_SAD":         "Tafkheem of Sad (تفخيم الصاد)",
    "TAFKHEEM_DAD":         "Tafkheem of Dad (تفخيم الضاد)",
    "TAFKHEEM_GHAIN":       "Tafkheem of Ghain (تفخيم الغين)",
    "TAFKHEEM_ZAH":         "Tafkheem of Zah (تفخيم الظاء)",
    "LAM_SHAMSIYYAH":       "Lam Shamsiyyah (لام شمسية)",
    "LAM_QAMARIYYAH":       "Lam Qamariyyah (لام قمرية)",
    "LAM_SAAKIN_RULE":      "Lam Saakinah rule (حكم اللام الساكنة)",
    "IDGHAM_MUTAMATHILAYN": "Idgham Mutamathilayn (إدغام متماثلين)",
    "IDGHAM_MUTAJANISAYN":  "Idgham Mutajanisayn (إدغام متجانسين)",
    "IDGHAM_MUTAQARIBAYN":  "Idgham Mutaqaribayn (إدغام متقاربين)",
    "WAQF_MIM":             "Waqf Lazim - Mim (وقف لازم - م)",
    "WAQF_LA":              "Waqf - La (لا وقف)",
    "WAQF_JEEM":            "Waqf Jaiz - Jeem (وقف جائز - ج)",
    "WAQF_QALI":            "Waqf - Al-Waqfu Awla (الوقف أولى - قلي)",
    "WAQF_SALI":            "Waqf - Al-Waslu Awla (الوصل أولى - صلي)",
    "MADD_MUTTASIL":        "Madd Muttasil (مد متصل)",
    "MADD_MUNFASSIL":       "Madd Munfasil (مد منفصل)",
    "MADD_LAZIM":           "Madd Lazim (مد لازم)",
    "MADD_ARID":            "Madd Arid Lis-Sukoon (مد عارض للسكون)",
}

# User-facing tips for each rule category
TAJWEED_TIPS: Dict[str, str] = {
    "Qalqalah (قلقلة)": "Add a slight bounce/echo when stopping on ق ط ب ج د",
    "Tafkheem (تفخيم)": "Make the letter sound heavier/fuller",
    "Idgham (إدغام)": "Merge the noon/meem into the following letter smoothly",
    "Ikhfa (إخفاء)": "Nasalise the noon lightly before the following letter",
    "Iqlab (إقلاب)": "Change the noon sound to a meem before ب",
    "Idhar (إظهار)": "Pronounce the noon clearly without merging",
    "Ghunna (غنة)": "Hold the nasal sound for 2 counts",
    "Madd 2 counts (مد)": "Stretch the vowel for 2 counts",
    "Madd 4 counts (مد)": "Stretch the vowel for 4 counts",
    "Madd 6 counts (مد)": "Stretch the vowel for 6 counts",
    "Tafkheem of Raa (تفخيم الراء)": "Pronounce the Raa with a heavy/full sound",
    "Tarqeeq of Raa (ترقيق الراء)": "Pronounce the Raa with a light/thin sound",
    "Tafkheem of Lam in Allah (تفخيم لام الجلالة)": "Make the Lam in Allah heavy when preceded by fatha/damma",
    "Tarqeeq of Lam in Allah (ترقيق لام الجلالة)": "Make the Lam in Allah light when preceded by kasra",
    "Lam Shamsiyyah (لام شمسية)": "The Lam is silent — assimilate into the following letter",
    "Lam Qamariyyah (لام قمرية)": "Pronounce the Lam clearly before the Qamariyyah letter",
    "Madd Muttasil (مد متصل)": "Stretch the connected madd for 4-5 counts",
    "Madd Munfasil (مد منفصل)": "Stretch the separated madd for 4-5 counts",
    "Madd Lazim (مد لازم)": "Stretch the obligatory madd for 6 counts",
    "Madd Arid Lis-Sukoon (مد عارض للسكون)": "Stretch the vowel 2-6 counts when stopping",
    "Pronunciation error": "Focus on pronouncing each letter from its correct articulation point",
}


def get_tajweed_rule(phoneme: str) -> Optional[str]:
    """Identify which Tajweed rule a phoneme token represents."""
    # Match exact 80-vocab rules first
    if phoneme in TAJWEED_RULES:
        return TAJWEED_RULES[phoneme]

    # Fallback to suffix/prefix matching
    if phoneme == "GHUNNA":
        return "Ghunna (غنة)"
    if phoneme.startswith("MADD_"):
        parts = phoneme.split('_')
        if len(parts) > 1 and parts[1].isdigit():
            return f"Madd {parts[1]} counts (مد)"
    for suffix, rule_name in TAJWEED_RULES.items():
        if suffix.startswith("_") and phoneme.endswith(suffix):
            return rule_name
    return None


def get_base_phoneme(phoneme: str) -> str:
    """Strip Tajweed suffix to get the base phoneme."""
    # 80-vocab special base letter mappings
    if phoneme in ("RAA_TAFKHEEM", "RAA_TARQEEQ"):
        return "REH"
    if phoneme in ("LAM_ALLAH_TAFKHEEM", "LAM_ALLAH_TARQEEQ",
                    "LAM_SHAMSIYYAH", "LAM_QAMARIYYAH", "LAM_SAAKIN_RULE"):
        return "LAM"
    if phoneme == "TAFKHEEM_KHAH":
        return "KHAH"
    if phoneme == "TAFKHEEM_SAD":
        return "SAD"
    if phoneme == "TAFKHEEM_DAD":
        return "DAD"
    if phoneme == "TAFKHEEM_GHAIN":
        return "GHAIN"
    if phoneme == "TAFKHEEM_ZAH":
        return "ZAH"
    if phoneme.startswith("WAQF_"):
        return "SP"

    for suffix in ["_Q", "_T", "_IDGHAM", "_IKHFA", "_IQLAB", "_IDHAR"]:
        if phoneme.endswith(suffix):
            return phoneme[:-len(suffix)]
    if phoneme.startswith("NOON_") or phoneme.startswith("MEEM_"):
        return phoneme.split("_")[0]
    return phoneme


def classify_tajweed_violation(pred: str, ref: str) -> dict:
    """Classify a phoneme mismatch as a specific Tajweed violation."""
    base_pred = get_base_phoneme(pred)
    base_ref = get_base_phoneme(ref)

    # Same base letter, different Tajweed variant → hidden mistake
    severity = "hidden" if base_pred == base_ref else "clear"

    ref_rule = get_tajweed_rule(ref)
    pred_rule = get_tajweed_rule(pred)

    if ref_rule and not pred_rule:
        rule_name = ref_rule
        description = f"Missing {ref_rule}: expected {ref}, got plain {pred}"
    elif ref_rule and pred_rule and ref_rule != pred_rule:
        rule_name = f"{ref_rule} vs {pred_rule}"
        description = f"Wrong rule: expected {ref} ({ref_rule}), got {pred} ({pred_rule})"
    elif not ref_rule and pred_rule:
        rule_name = f"Extra {pred_rule}"
        description = f"Unnecessary {pred_rule}: got {pred} instead of {ref}"
    else:
        rule_name = "Pronunciation error"
        description = f"Wrong sound: expected {ref}, got {pred}"

    return {
        "rule": rule_name,
        "description": description,
        "severity": severity,
        "tip": TAJWEED_TIPS.get(rule_name, TAJWEED_TIPS.get("Pronunciation error", "")),
    }


def detect_tajweed_violations(pred_phonemes: str, ref_phonemes: str) -> List[dict]:
    """Compare predicted vs reference phoneme sequences and detect Tajweed violations.

    Uses jiwer word-level alignment treating each phoneme token as a word.

    Returns:
        List of violation dicts with position, rule, severity, description, tip.
    """
    pred_tokens = pred_phonemes.split()
    ref_tokens = ref_phonemes.split()

    out = jiwer.process_words(ref_phonemes, pred_phonemes)
    alignment = out.alignments[0]

    violations = []
    word_position = 0  # Track which Arabic word we're in (count SP tokens in ref)

    for chunk in alignment:
        if chunk.type == 'equal':
            for idx in range(chunk.ref_start_idx, chunk.ref_end_idx):
                if ref_tokens[idx] == "SP":
                    word_position += 1

        elif chunk.type == 'substitute':
            for i in range(chunk.ref_end_idx - chunk.ref_start_idx):
                ref_idx = chunk.ref_start_idx + i
                hyp_idx = chunk.hyp_start_idx + i if (chunk.hyp_start_idx + i) < len(pred_tokens) else None

                ref_tok = ref_tokens[ref_idx]
                pred_tok = pred_tokens[hyp_idx] if hyp_idx is not None else "?"

                if ref_tok == "SP":
                    word_position += 1
                    continue

                violation = classify_tajweed_violation(pred_tok, ref_tok)
                violation["position"] = word_position + 1
                violation["expected"] = ref_tok
                violation["got"] = pred_tok
                violations.append(violation)

        elif chunk.type == 'delete':
            for i in range(chunk.ref_end_idx - chunk.ref_start_idx):
                ref_idx = chunk.ref_start_idx + i
                ref_tok = ref_tokens[ref_idx]
                if ref_tok == "SP":
                    word_position += 1
                    continue

                ref_rule = get_tajweed_rule(ref_tok)
                violations.append({
                    "position": word_position + 1,
                    "rule": ref_rule or "Missing phoneme",
                    "description": f"Missing: {ref_tok} was not pronounced",
                    "severity": "clear" if not ref_rule else "hidden",
                    "expected": ref_tok,
                    "got": "---",
                    "tip": TAJWEED_TIPS.get(ref_rule, "") if ref_rule else "Ensure every letter is pronounced",
                })

        elif chunk.type == 'insert':
            for i in range(chunk.hyp_end_idx - chunk.hyp_start_idx):
                hyp_idx = chunk.hyp_start_idx + i
                pred_tok = pred_tokens[hyp_idx]
                if pred_tok == "SP":
                    continue

                violations.append({
                    "position": word_position + 1,
                    "rule": "Extra phoneme",
                    "description": f"Extra: {pred_tok} should not be here",
                    "severity": "clear",
                    "expected": "---",
                    "got": pred_tok,
                    "tip": "Avoid adding extra sounds between letters",
                })

    return violations


def split_phoneme_words(phonemes_str: str) -> List[str]:
    """Split a phoneme string into word-groups separated by SP tokens.

    Returns a list of underscore-joined phoneme words.
    Example: 'MEEM KASRA NOON SP SHEEN ...' -> ['MEEM_KASRA_NOON', 'SHEEN_...']
    """
    tokens = phonemes_str.split()
    words = []
    current = []
    for t in tokens:
        if t in ("SP", "|"):
            if current:
                words.append("_".join(current))
                current = []
        elif t not in ("<pad>", "<unk>"):
            current.append(t)
    if current:
        words.append("_".join(current))
    return words


def phonemes_to_arabic(phonemes_str: str) -> str:
    """Convert phoneme string back to approximate Arabic for display."""
    tokens = phonemes_str.split()
    chars = []
    for t in tokens:
        if t in ("SP", "|"):
            chars.append(" ")
            continue
        if t.startswith("WAQF_") or t == "GHUNNA" or t in ("<pad>", "<unk>"):
            continue
        base = get_base_phoneme(t)
        if base.startswith("MADD"):
            chars.append("ا")  # approximate
            continue
        ar = PHONEME_TO_LETTER.get(base)
        if ar:
            chars.append(ar)
    return "".join(chars)


__all__ = [
    "TAJWEED_RULES",
    "TAJWEED_TIPS",
    "get_tajweed_rule",
    "get_base_phoneme",
    "classify_tajweed_violation",
    "detect_tajweed_violations",
    "split_phoneme_words",
    "phonemes_to_arabic",
]
