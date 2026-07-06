"""Tajweed-aware grapheme-to-phoneme conversion for Quranic Uthmani text.

Ported from quranic_asr_phoneme/src/tajweed_g2p.py for use in the
tilawah-ai backend. Converts diacritised Arabic text into phoneme
sequences that match the model's 80-token vocabulary.

Pipeline:
    Uthmani Arabic text  ──►  base phoneme stream
                              + Tajweed rule overlays (Tafkheem, Qalqalah,
                                Madd-N, Ghunna, Noon/Tanween, Meem rules)
                          ──►  whitespace-separated phoneme sequence
"""
from __future__ import annotations

import re
import unicodedata
from typing import Dict, Iterable, List, Optional

import pyarabic.araby as araby

from .phoneme_constants import (
    ALWAYS_HEAVY,
    LETTER_TO_PHONEME,
    QALQALAH_MAP,
    SPACE,
)

# ---------------------------------------------------------------------------
# Arabic diacritic / letter constants
# ---------------------------------------------------------------------------
SHADDA = "\u0651"
SUKUN  = "\u0652"
FATHA  = "\u064E"
KASRA  = "\u0650"
DAMMA  = "\u064F"
FATHATAN = "\u064B"
KASRATAN = "\u064D"
DAMMATAN = "\u064C"
ALIF = "\u0627"
WAW  = "\u0648"
YEH  = "\u064A"
ALIF_MAQSURA = "\u0649"
HAMZA_ABOVE = "\u0654"
HAMZA_BELOW = "\u0655"
TATWEEL = "\u0640"
NOON = "\u0646"
MEEM = "\u0645"
LAM  = "\u0644"
REH  = "\u0631"
HEH_HAMZA_FORMS = {"\u0623", "\u0625", "\u0622", "\u0626", "\u0624"}

# Mapping from common composite Arabic letters to their canonical base letter
_LETTER_NORMALISE: Dict[str, str] = {
    "\u0623": "ا",  # alif w/ hamza above
    "\u0625": "ا",  # alif w/ hamza below
    "\u0622": "ا",  # alif madda
    "\u0671": "ا",  # alif wasla
    "\u0649": "ى",  # alif maqsura
    "\u0626": "ي",  # yeh w/ hamza above
    "\u0624": "و",  # waw w/ hamza above
    "\u0629": "ت",  # teh marbuta -> teh (only when pronounced; else dropped)
    "\u0670": "ا",  # superscript alif (treated as long /aː/)
}

TANWEEN = {FATHATAN, KASRATAN, DAMMATAN}
SHORT_VOWEL_DIAC = {FATHA, KASRA, DAMMA}
ALL_DIAC = SHORT_VOWEL_DIAC | TANWEEN | {SHADDA, SUKUN}

# Letters that trigger Idgham of NOON sakinah / tanween:        ي ر م ل و ن
NOON_IDGHAM_LETTERS = set("يرملون")
# Letters that trigger Iqlab:                                    ب
NOON_IQLAB_LETTERS  = set("ب")
# Letters that trigger Idhar (clear):                            ء ه ع ح غ خ
NOON_IDHAR_LETTERS  = set("ءهعحغخ")
# All other 15 letters trigger Ikhfa.

# Meem rules: Idgham if next letter is meem, Ikhfa if next is beh, else Idhar.
MEEM_IDGHAM_LETTERS = set("م")
MEEM_IKHFA_LETTERS  = set("ب")


# ---------------------------------------------------------------------------
# Core G2P
# ---------------------------------------------------------------------------
def _normalise_letter(ch: str) -> str:
    return _LETTER_NORMALISE.get(ch, ch)


def _strip_tatweel(text: str) -> str:
    return text.replace(TATWEEL, "")


def base_phonemise(uthmani_word: str) -> List[str]:
    """Convert one Uthmani word to its *base* phoneme sequence.

    No Tajweed overlays applied. Diacritics (FATHA/KASRA/DAMMA) are emitted as
    separate phonemes after the consonant they decorate. Long vowels are
    detected by ALIF / WAW / YEH following an appropriate short vowel.
    """
    text = unicodedata.normalize("NFC", uthmani_word)
    text = _strip_tatweel(text)

    out: List[str] = []
    i = 0
    chars = list(text)
    n = len(chars)
    while i < n:
        ch = chars[i]
        norm = _normalise_letter(ch)

        if norm in ALL_DIAC:
            i += 1
            continue  # diacritics handled when we look at the *previous* letter

        if norm == " ":
            out.append(SPACE)
            i += 1
            continue

        # Skip standalone hamza marks (already part of letter normalisation)
        if norm in {HAMZA_ABOVE, HAMZA_BELOW}:
            i += 1
            continue

        phoneme = LETTER_TO_PHONEME.get(norm)
        if phoneme is None:
            i += 1  # unknown char (e.g. punctuation) — drop silently
            continue

        # Look at the diacritics immediately following this letter
        j = i + 1
        diacs: List[str] = []
        while j < n and chars[j] in ALL_DIAC:
            diacs.append(chars[j])
            j += 1
        has_shadda = SHADDA in diacs
        has_sukun  = SUKUN  in diacs
        short = next((d for d in diacs if d in SHORT_VOWEL_DIAC), None)
        tanween = next((d for d in diacs if d in TANWEEN), None)

        # Geminate consonant if shadda
        if has_shadda:
            out.append(phoneme)
            out.append(phoneme)
        else:
            out.append(phoneme)

        # Vowel emission
        if short == FATHA:
            out.append("FATHA")
        elif short == KASRA:
            out.append("KASRA")
        elif short == DAMMA:
            out.append("DAMMA")
        elif tanween == FATHATAN:
            out.append("FATHA"); out.append("NOON")
        elif tanween == KASRATAN:
            out.append("KASRA"); out.append("NOON")
        elif tanween == DAMMATAN:
            out.append("DAMMA"); out.append("NOON")

        # Detect long vowel: short-vowel + matching long-vowel letter (next)
        next_letter = None
        if j < n:
            next_letter = _normalise_letter(chars[j])
        if short == FATHA and next_letter == ALIF:
            out.pop()                       # remove FATHA — folded into ALIF_M
            out.append("ALIF_M")
            j += 1                          # consume ALIF
        elif short == KASRA and next_letter == YEH:
            out.pop(); out.append("YEH_M"); j += 1
        elif short == DAMMA and next_letter == WAW:
            out.pop(); out.append("WAW_M"); j += 1

        i = j
    return out


# ---------------------------------------------------------------------------
# Tajweed overlay
# ---------------------------------------------------------------------------
def _apply_qalqalah(phonemes: List[str]) -> List[str]:
    """Promote Qalqalah letters to their _Q variant when in sukoon position."""
    vowel_set = {"FATHA", "KASRA", "DAMMA", "ALIF_M", "YEH_M", "WAW_M"}
    out = list(phonemes)
    for idx, p in enumerate(out):
        if p in QALQALAH_MAP:
            following = out[idx + 1] if idx + 1 < len(out) else None
            if following not in vowel_set and following != p:  # not vowel, not gemination
                out[idx] = QALQALAH_MAP[p]
    return out


def _apply_reh_tafkheem(phonemes: List[str]) -> List[str]:
    """Heuristic Tafkheem on REH:
       - Heavy when followed/preceded by FATHA, DAMMA, ALIF_M, WAW_M
       - Light when followed/preceded by KASRA, YEH_M
    """
    heavy_ctx = {"FATHA", "DAMMA", "ALIF_M", "WAW_M"}
    out = list(phonemes)
    for idx, p in enumerate(out):
        if p != "REH":
            continue
        prev_p = out[idx - 1] if idx > 0 else None
        next_p = out[idx + 1] if idx + 1 < len(out) else None
        if (next_p in heavy_ctx) or (prev_p in heavy_ctx):
            out[idx] = "REH_T"
    return out


def _apply_lam_of_allah(phonemes: List[str], ayah_text: str) -> List[str]:
    """Mark heavy LAM in the divine name 'Allah' when preceded by FATHA/DAMMA."""
    if "\u0671\u0644\u0644\u0651\u064e\u0647" not in ayah_text and "الله" not in ayah_text:
        return phonemes
    out = list(phonemes)
    heavy_ctx = {"FATHA", "DAMMA", "ALIF_M", "WAW_M"}
    for idx, p in enumerate(out):
        if p == "LAM" and idx + 1 < len(out) and out[idx + 1] == "LAM":
            prev_p = out[idx - 1] if idx > 0 else None
            if prev_p in heavy_ctx:
                out[idx]     = "LAM_T"
                out[idx + 1] = "LAM_T"
    return out


def _apply_noon_rules(phonemes: List[str]) -> List[str]:
    """Replace NOON-with-sukoon according to the next consonant."""
    vowels = {"FATHA", "KASRA", "DAMMA", "ALIF_M", "YEH_M", "WAW_M"}
    out = list(phonemes)
    for idx, p in enumerate(out):
        if p != "NOON":
            continue
        nxt = out[idx + 1] if idx + 1 < len(out) else None
        if nxt is None or nxt in vowels:
            continue  # vocalised NOON, no rule
        nxt_letter = _phoneme_to_arabic_letter(nxt)
        if nxt_letter is None:
            continue
        if nxt_letter in NOON_IDGHAM_LETTERS:
            out[idx] = "NOON_IDGHAM"
        elif nxt_letter in NOON_IQLAB_LETTERS:
            out[idx] = "NOON_IQLAB"
        elif nxt_letter in NOON_IDHAR_LETTERS:
            pass  # remains NOON
        else:
            out[idx] = "NOON_IKHFA"
    return out


def _apply_meem_rules(phonemes: List[str]) -> List[str]:
    vowels = {"FATHA", "KASRA", "DAMMA", "ALIF_M", "YEH_M", "WAW_M"}
    out = list(phonemes)
    for idx, p in enumerate(out):
        if p != "MEEM":
            continue
        nxt = out[idx + 1] if idx + 1 < len(out) else None
        if nxt is None or nxt in vowels:
            continue
        nxt_letter = _phoneme_to_arabic_letter(nxt)
        if nxt_letter in MEEM_IDGHAM_LETTERS:
            out[idx] = "MEEM_IDGHAM"
    return out


def _apply_ghunnah(phonemes: List[str]) -> List[str]:
    """Insert a GHUNNA marker after Idgham/Ikhfa/Iqlab NOON variants and
    after geminated NOON or MEEM (shadda)."""
    triggers = {"NOON_IDGHAM", "NOON_IKHFA", "NOON_IQLAB", "MEEM_IDGHAM"}
    out: List[str] = []
    i = 0
    while i < len(phonemes):
        p = phonemes[i]
        out.append(p)
        # Geminated noon/meem detection: same phoneme repeats
        if p in {"NOON", "MEEM"} and i + 1 < len(phonemes) and phonemes[i + 1] == p:
            out.append(phonemes[i + 1])
            out.append("GHUNNA")
            i += 2
            continue
        if p in triggers:
            out.append("GHUNNA")
        i += 1
    return out


# ---------------------------------------------------------------------------
# Helper: phoneme -> Arabic letter (best-effort, for rule lookups)
# ---------------------------------------------------------------------------
_PHONEME_TO_LETTER_LOOKUP: Dict[str, str] = {p: ar for ar, p in
                                             [(v, k) for k, v in LETTER_TO_PHONEME.items()]}

def _phoneme_to_arabic_letter(p: str) -> Optional[str]:
    base = re.sub(r"_(Q|T|IDGHAM|IKHFA|IQLAB)$", "", p)
    return _PHONEME_TO_LETTER_LOOKUP.get(base)


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------
def text_to_phonemes(uthmani_text: str) -> List[str]:
    """Full Uthmani -> phoneme pipeline with Tajweed overlay.

    Args:
        uthmani_text: Uthmani-script Arabic ayah (with diacritics).
    """
    # 1. Base phonemisation per word
    words = uthmani_text.strip().split()
    phs: List[str] = []
    for w_idx, w in enumerate(words):
        phs.extend(base_phonemise(w))
        if w_idx != len(words) - 1:
            phs.append(SPACE)

    # 2. Tajweed overlays (order matters)
    phs = _apply_reh_tafkheem(phs)
    phs = _apply_lam_of_allah(phs, uthmani_text)
    phs = _apply_qalqalah(phs)
    phs = _apply_noon_rules(phs)
    phs = _apply_meem_rules(phs)
    phs = _apply_ghunnah(phs)
    return phs


def phonemes_to_string(phs: Iterable[str]) -> str:
    """Render phoneme sequence as space-joined tokens (CTC label format)."""
    return " ".join(phs)


__all__ = [
    "base_phonemise",
    "text_to_phonemes",
    "phonemes_to_string",
]
