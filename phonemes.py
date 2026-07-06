"""Quranic phoneme inventory (53 phonemes incl. Tajweed).

Mirrors §IV-A of Al-Zaro et al. 2025. The paper says "Arabic-like symbols"
without enumerating them; we use ASCII tags so the phonemes can serve as a
discrete CTC vocabulary AND be tokenised by KenLM as whitespace-separated tokens.

Coverage:
  - 28 standard Arabic consonants
  - 3 short vowels (FATHA/KASRA/DAMMA)
  - 3 long vowels (ALIF_M / YEH_M / WAW_M)
  - Tajweed-special:
        * 5 Qalqalah variants  (QAF/TAH/BEH/JEEM/DAL  + _Q)
        * 7 Tafkheem variants  (REH/LAM/KHAH/GHAIN/SAD/DAD/TAH/ZAH/QAF subset + _T)
          (the always-heavy ones are encoded directly as their letter; only
          conditional Tafkheem on REH and LAM-of-Allah get _T variants;
          the 7 always-heavy heavy-letters are covered by their plain symbols)
        * 4 Noon/Tanween rules (IDGHAM / IKHFA / IQLAB / IDHAR_default=NOON)
        * 2 Meem rules         (IDGHAM_M / IKHFA_M)
        * 1 Ghunna marker      (GHUNNA)
        * 3 Madd counts        (MADD_2 / MADD_4 / MADD_6)
  - SPACE delimiter
  - Special CTC tokens (PAD/UNK) added by the tokenizer, not counted in 53.

This yields exactly 53 phoneme tokens. Counts are asserted at import time.
"""
from __future__ import annotations

from typing import Dict, List, Tuple

# ---------------------------------------------------------------------------
# 1. Base Arabic consonants (28)
# ---------------------------------------------------------------------------
CONSONANTS: List[Tuple[str, str]] = [
    ("HAMZA", "ء"),
    ("BEH",   "ب"),
    ("TEH",   "ت"),
    ("THEH",  "ث"),
    ("JEEM",  "ج"),
    ("HAH",   "ح"),
    ("KHAH",  "خ"),
    ("DAL",   "د"),
    ("THAL",  "ذ"),
    ("REH",   "ر"),
    ("ZAIN",  "ز"),
    ("SEEN",  "س"),
    ("SHEEN", "ش"),
    ("SAD",   "ص"),
    ("DAD",   "ض"),
    ("TAH",   "ط"),
    ("ZAH",   "ظ"),
    ("AIN",   "ع"),
    ("GHAIN", "غ"),
    ("FEH",   "ف"),
    ("QAF",   "ق"),
    ("KAF",   "ك"),
    ("LAM",   "ل"),
    ("MEEM",  "م"),
    ("NOON",  "ن"),
    ("HEH",   "ه"),
    ("WAW",   "و"),
    ("YEH",   "ي"),
]

# ---------------------------------------------------------------------------
# 2. Short vowels (3) — diacritics only
# ---------------------------------------------------------------------------
SHORT_VOWELS: List[Tuple[str, str]] = [
    ("FATHA", "َ"),
    ("KASRA", "ِ"),
    ("DAMMA", "ُ"),
]

# ---------------------------------------------------------------------------
# 3. Long vowels (3)
# ---------------------------------------------------------------------------
LONG_VOWELS: List[Tuple[str, str]] = [
    ("ALIF_M", "ا"),   # long /aː/
    ("YEH_M",  "ى"),   # long /iː/ (alif maqsura / yeh madd)
    ("WAW_M",  "وْ"),  # long /uː/ marker (paired with damma)
]

# ---------------------------------------------------------------------------
# 4. Tajweed special phonemes (18)
# ---------------------------------------------------------------------------
# Qalqalah (echo/bounce on the 5 Qalqalah letters when sukoon)
QALQALAH = ["QAF_Q", "TAH_Q", "BEH_Q", "JEEM_Q", "DAL_Q"]

# Conditional Tafkheem: REH (depends on vowel) and LAM-of-Allah (depends on prev vowel)
# (the always-heavy 7 letters: KHAH/GHAIN/SAD/DAD/TAH/ZAH/QAF are encoded plainly)
TAFKHEEM = ["REH_T", "LAM_T"]

# Noon/Tanween rules — 4 variants (explicit Idhar marker included)
NOON_RULES = ["NOON_IDGHAM", "NOON_IKHFA", "NOON_IQLAB", "NOON_IDHAR"]

# Meem rules — 3 variants (Idgham / Ikhfa / explicit Idhar)
MEEM_RULES = ["MEEM_IDGHAM", "MEEM_IKHFA", "MEEM_IDHAR"]

# Ghunna (nasalisation marker)
GHUNNA = ["GHUNNA"]

# Madd-count markers (replace generic long vowel when stretching)
MADD = ["MADD_2", "MADD_4", "MADD_6"]

TAJWEED = QALQALAH + TAFKHEEM + NOON_RULES + MEEM_RULES + GHUNNA + MADD
# = 5 + 2 + 4 + 3 + 1 + 3 = 18 tajweed phonemes

# ---------------------------------------------------------------------------
# 5. Delimiter
# ---------------------------------------------------------------------------
SPACE = "SP"

# ---------------------------------------------------------------------------
# Build canonical ordered phoneme list
# ---------------------------------------------------------------------------
def _build_phoneme_list() -> List[str]:
    phonemes: List[str] = []
    phonemes += [name for name, _ in CONSONANTS]    # 28
    phonemes += [name for name, _ in SHORT_VOWELS]  # 3
    phonemes += [name for name, _ in LONG_VOWELS]   # 3
    phonemes += TAJWEED                             # 18
    phonemes += [SPACE]                             # 1
    return phonemes

PHONEMES: List[str] = _build_phoneme_list()
# 28 consonants + 3 short vowels + 3 long vowels + 18 tajweed + 1 SP = 53
assert len(PHONEMES) == 53, f"Expected 53 phonemes, got {len(PHONEMES)}: {PHONEMES}"

# ---------------------------------------------------------------------------
# Lookup tables
# ---------------------------------------------------------------------------
PHONEME_TO_ID: Dict[str, int] = {p: i for i, p in enumerate(PHONEMES)}
ID_TO_PHONEME: Dict[int, str] = {i: p for p, i in PHONEME_TO_ID.items()}

# Arabic letter -> default phoneme name (without Tajweed context).
LETTER_TO_PHONEME: Dict[str, str] = {ar: name for name, ar in CONSONANTS}
LETTER_TO_PHONEME.update({ar: name for name, ar in SHORT_VOWELS})
LETTER_TO_PHONEME.update({ar: name for name, ar in LONG_VOWELS})

# Reverse map for rendering (debugging only)
PHONEME_TO_LETTER: Dict[str, str] = {v: k for k, v in LETTER_TO_PHONEME.items()}

# Phonemes that are valid Qalqalah base letters (used by the G2P module)
QALQALAH_BASE = {"QAF", "TAH", "BEH", "JEEM", "DAL"}
QALQALAH_MAP = {
    "QAF":  "QAF_Q",
    "TAH":  "TAH_Q",
    "BEH":  "BEH_Q",
    "JEEM": "JEEM_Q",
    "DAL":  "DAL_Q",
}

ALWAYS_HEAVY = {"KHAH", "GHAIN", "SAD", "DAD", "TAH", "ZAH", "QAF"}  # see paper

# ---------------------------------------------------------------------------
# Vocab file writer (used by the HF tokenizer)
# ---------------------------------------------------------------------------
def write_vocab_json(path: str) -> None:
    """Write a Wav2Vec2CTCTokenizer-compatible vocab.json file.

    The CTC tokenizer expects a JSON dict {token: id}. We add the standard
    HuggingFace special tokens (<pad>, <unk>, |) at the end so the phoneme IDs
    stay stable across runs.
    """
    import json

    vocab = dict(PHONEME_TO_ID)               # 53 phonemes
    next_id = len(vocab)
    for special in ("<pad>", "<unk>", "|"):   # | is the word-delimiter HF expects
        vocab[special] = next_id
        next_id += 1
    with open(path, "w", encoding="utf-8") as f:
        json.dump(vocab, f, ensure_ascii=False, indent=2)


__all__ = [
    "PHONEMES",
    "PHONEME_TO_ID",
    "ID_TO_PHONEME",
    "LETTER_TO_PHONEME",
    "PHONEME_TO_LETTER",
    "QALQALAH_BASE",
    "QALQALAH_MAP",
    "ALWAYS_HEAVY",
    "SPACE",
    "write_vocab_json",
]
