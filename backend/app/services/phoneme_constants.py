from __future__ import annotations
from typing import Dict, List, Tuple

# Base Arabic consonants (28)
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

# Short vowels (3)
SHORT_VOWELS: List[Tuple[str, str]] = [
    ("FATHA", "َ"),
    ("KASRA", "ِ"),
    ("DAMMA", "ُ"),
]

# Long vowels (3)
LONG_VOWELS: List[Tuple[str, str]] = [
    ("ALIF_M", "ا"),   # long /aː/
    ("YEH_M",  "ى"),   # long /iː/ (alif maqsura / yeh madd)
    ("WAW_M",  "وْ"),  # long /uː/ marker (paired with damma)
]

# Vocabulary from vocab.json
VOCAB = [
    "<pad>", "<unk>", "AIN", "ALIF_M", "BEH", "BEH_Q", "DAD", "DAL", "DAL_Q", "DAMMA",
    "FATHA", "FEH", "GHAIN", "GHUNNA", "HAH", "HAMZA", "HEH", "IDGHAM_MUTAJANISAYN",
    "IDGHAM_MUTAMATHILAYN", "IDGHAM_MUTAQARIBAYN", "JEEM", "JEEM_Q", "KAF", "KASRA",
    "KHAH", "LAM", "LAM_ALLAH_TAFKHEEM", "LAM_ALLAH_TARQEEQ", "LAM_QAMARIYYAH",
    "LAM_SAAKIN_RULE", "LAM_SHAMSIYYAH", "LAM_T", "MADD_2", "MADD_4", "MADD_6",
    "MADD_ARID", "MADD_LAZIM", "MADD_MUNFASSIL", "MADD_MUTTASIL", "MEEM", "MEEM_IDGHAM",
    "MEEM_IDHAR", "MEEM_IKHFA", "NOON", "NOON_IDGHAM", "NOON_IDHAR", "NOON_IKHFA",
    "NOON_IQLAB", "QAF", "QAF_Q", "RAA_TAFKHEEM", "RAA_TARQEEQ", "REH", "REH_T",
    "SAD", "SEEN", "SHEEN", "SP", "TAFKHEEM_DAD", "TAFKHEEM_GHAIN", "TAFKHEEM_KHAH",
    "TAFKHEEM_SAD", "TAFKHEEM_ZAH", "TAH", "TAH_Q", "TEH", "THAL", "THEH", "WAQF_JEEM",
    "WAQF_LA", "WAQF_MIM", "WAQF_QALI", "WAQF_SALI", "WAW", "WAW_M", "YEH", "YEH_M",
    "ZAH", "ZAIN", "|"
]

LETTER_TO_PHONEME: Dict[str, str] = {ar: name for name, ar in CONSONANTS}
LETTER_TO_PHONEME.update({ar: name for name, ar in SHORT_VOWELS})
LETTER_TO_PHONEME.update({ar: name for name, ar in LONG_VOWELS})

PHONEME_TO_LETTER: Dict[str, str] = {v: k for k, v in LETTER_TO_PHONEME.items()}

# Phonemes that are valid Qalqalah base letters
QALQALAH_BASE = {"QAF", "TAH", "BEH", "JEEM", "DAL"}
QALQALAH_MAP = {
    "QAF":  "QAF_Q",
    "TAH":  "TAH_Q",
    "BEH":  "BEH_Q",
    "JEEM": "JEEM_Q",
    "DAL":  "DAL_Q",
}

ALWAYS_HEAVY = {"KHAH", "GHAIN", "SAD", "DAD", "TAH", "ZAH", "QAF"}
SPACE = "SP"
