"""Grade a Quranic recitation with Tajweed violation detection.

Evaluates pronunciation at three levels:
  1. Character-level alignment (colored diff)
  2. Word-level corrections
  3. Tajweed rule violations (Qalqalah, Tafkheem, Ghunna, Noon/Meem rules, Madd)

Usage:
    python eval_recitation.py recording.wav
    python eval_recitation.py recording.wav "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ"
    python eval_recitation.py recording.wav --no-play
"""
import argparse
import torch
import soundfile as sf
import jiwer
import csv
import os
import subprocess
import shutil
import sys
import json
import numpy as np
import sounddevice as sd
import queue
from pathlib import Path
from rapidfuzz import process, fuzz
from transformers import Wav2Vec2Processor, Wav2Vec2ForCTC

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(1, "/home/badshah/Desktop")  # Path to quranic_asr_phoneme
sys.path.insert(2, "/home/badshah/Documents/FYP")  # Fallback path
from train_local import DATA_DIR

def phonemes_to_arabic(phonemes_str: str) -> str:
    from quranic_asr_phoneme.src.phonemes import PHONEME_TO_LETTER
    import re
    tokens = phonemes_str.split()
    chars = []
    for t in tokens:
        if t == "SP" or t == "|":
            chars.append(" ")
            continue
        if t.startswith("MADD"):
            chars.append("ا")  # approximate
            continue
        if t == "GHUNNA" or t == "<pad>" or t == "<unk>":
            continue
        # Strip Tajweed suffixes to get the base phoneme
        base = re.sub(r"_(Q|T|IDGHAM|IKHFA|IQLAB|IDHAR)$", "", t)
        ar = PHONEME_TO_LETTER.get(base)
        if ar:
            chars.append(ar)
    return "".join(chars)


def split_phoneme_words(phonemes_str):
    """Split a phoneme string into word-groups separated by SP tokens.

    Returns a list of underscore-joined phoneme words, each suitable
    for use as a single 'word' token in jiwer comparison.
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


from quranic_asr_phoneme.src.tajweed_g2p import text_to_phonemes, phonemes_to_string

# ANSI Color Codes for terminal highlighting
class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    CYAN = '\033[96m'
    MAGENTA = '\033[95m'
    BOLD = '\033[1m'
    RESET = '\033[0m'

# Preferred Qaris in order of priority (best quality first)
PREFERRED_QARIS = [
    "husary", "minshawi", "alafasy", "abdul_basit",
    "abdulsamad", "maher_al_muaiqly", "menshawi", "ghamadi",
]

# =========================================================================
# TAJWEED RULE CLASSIFICATION
# =========================================================================
# Map suffixes to rule names
TAJWEED_RULES = {
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
}


def get_tajweed_rule(phoneme: str) -> str:
    """Identify which Tajweed rule a phoneme token represents."""
    if phoneme == "GHUNNA":
        return "Ghunna (غنة)"
    if phoneme.startswith("MADD_"):
        return f"Madd {phoneme.split('_')[1]} counts (مد)"
    for suffix, rule_name in TAJWEED_RULES.items():
        if phoneme.endswith(suffix) and suffix != "GHUNNA":
            return rule_name
    return None


def extract_verse_tajweed_rules(ref_phonemes: str, ref_arabic_words: list) -> dict:
    """Scan reference phonemes and return all Tajweed rules present in the verse.

    Returns:
        dict mapping rule_name -> list of (word_position, phoneme_token) tuples
    """
    tokens = ref_phonemes.split()
    rules_found = {}  # rule_name -> [(word_pos, token), ...]
    word_pos = 1  # 1-indexed word position

    for tok in tokens:
        if tok in ("SP", "|"):
            word_pos += 1
            continue
        if tok in ("<pad>", "<unk>"):
            continue
        rule = get_tajweed_rule(tok)
        if rule:
            if rule not in rules_found:
                rules_found[rule] = []
            rules_found[rule].append((word_pos, tok))

    return rules_found


def get_base_phoneme(phoneme: str) -> str:
    """Strip Tajweed suffix to get the base phoneme."""
    for suffix in ["_Q", "_T", "_IDGHAM", "_IKHFA", "_IQLAB", "_IDHAR"]:
        if phoneme.endswith(suffix):
            return phoneme[:-len(suffix)]
    if phoneme.startswith("NOON_") or phoneme.startswith("MEEM_"):
        return phoneme.split("_")[0]
    return phoneme


def classify_tajweed_violation(pred: str, ref: str) -> dict:
    """Classify a phoneme mismatch as a specific Tajweed violation.

    Returns:
        dict with keys: rule, description, severity
    """
    base_pred = get_base_phoneme(pred)
    base_ref = get_base_phoneme(ref)

    # Same base letter, different Tajweed variant → hidden mistake
    if base_pred == base_ref:
        severity = "hidden"
    else:
        severity = "clear"

    ref_rule = get_tajweed_rule(ref)
    pred_rule = get_tajweed_rule(pred)

    if ref_rule and not pred_rule:
        # Expected a Tajweed rule, got plain phoneme
        return {
            "rule": ref_rule,
            "description": f"Missing {ref_rule}: expected {ref}, got plain {pred}",
            "severity": severity,
        }
    elif ref_rule and pred_rule and ref_rule != pred_rule:
        # Wrong Tajweed rule applied
        return {
            "rule": f"{ref_rule} vs {pred_rule}",
            "description": f"Wrong rule: expected {ref} ({ref_rule}), got {pred} ({pred_rule})",
            "severity": severity,
        }
    elif not ref_rule and pred_rule:
        # Added a Tajweed rule where none expected
        return {
            "rule": f"Extra {pred_rule}",
            "description": f"Unnecessary {pred_rule}: got {pred} instead of {ref}",
            "severity": severity,
        }
    else:
        # Pure phoneme substitution
        return {
            "rule": "Pronunciation error",
            "description": f"Wrong sound: expected {ref}, got {pred}",
            "severity": severity,
        }


def detect_tajweed_violations(pred_phonemes: str, ref_phonemes: str) -> list:
    """Compare predicted vs reference phoneme sequences and detect Tajweed violations.

    Returns:
        List of violation dicts with position, rule, severity, etc.
    """
    pred_tokens = pred_phonemes.split()
    ref_tokens = ref_phonemes.split()

    # Use jiwer's word-level alignment (treating each phoneme as a word)
    out = jiwer.process_words(ref_phonemes, pred_phonemes)
    alignment = out.alignments[0]

    violations = []
    word_position = 0  # Track which word we're in (by counting SP tokens in ref)

    for chunk in alignment:
        if chunk.type == 'equal':
            # Count SP tokens to track word position
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
                })

    return violations


# =============================================================================
# PHONEME-SPACE MATCHING DATABASE
# =============================================================================
_PHONEME_DB_CACHE = None

def load_phoneme_database(quran_verses):
    """Build a phoneme-space lookup for verse matching.

    Instead of matching lossy Arabic→Arabic text, we pre-compute the
    Tajweed phoneme string for every unique verse and match the model's
    raw phoneme output directly against this database.

    Returns:
        phoneme_to_verse: dict mapping phoneme_string → Arabic verse text
        phoneme_list: list of phoneme strings (for rapidfuzz extractOne)
    """
    global _PHONEME_DB_CACHE
    if _PHONEME_DB_CACHE is not None:
        return _PHONEME_DB_CACHE

    cache_path = DATA_DIR / "_phoneme_db_cache.json"

    # Try loading from disk cache
    if cache_path.exists():
        try:
            with open(cache_path, "r", encoding="utf-8") as f:
                phoneme_to_verse = json.load(f)
            phoneme_list = list(phoneme_to_verse.keys())
            _PHONEME_DB_CACHE = (phoneme_to_verse, phoneme_list)
            return _PHONEME_DB_CACHE
        except (json.JSONDecodeError, OSError):
            pass  # rebuild

    print("  Building phoneme database (first run only, will be cached)...")
    phoneme_to_verse = {}
    for verse in quran_verses:
        try:
            phs = text_to_phonemes(verse)
            ph_str = phonemes_to_string(phs)
            phoneme_to_verse[ph_str] = verse
        except Exception:
            continue  # skip problematic verses

    # Save to disk cache
    try:
        with open(cache_path, "w", encoding="utf-8") as f:
            json.dump(phoneme_to_verse, f, ensure_ascii=False)
    except OSError:
        pass

    phoneme_list = list(phoneme_to_verse.keys())
    _PHONEME_DB_CACHE = (phoneme_to_verse, phoneme_list)
    return _PHONEME_DB_CACHE


# =============================================================================
# LM BEAM SEARCH DECODER
# =============================================================================
# All known phoneme tokens, sorted longest-first for greedy match
_PHONEME_TOKENS = sorted([
    'ALIF_M', 'YEH_M', 'WAW_M',
    'QAF_Q', 'TAH_Q', 'BEH_Q', 'JEEM_Q', 'DAL_Q',
    'REH_T', 'LAM_T',
    'NOON_IDGHAM', 'NOON_IKHFA', 'NOON_IQLAB', 'NOON_IDHAR',
    'MEEM_IDGHAM', 'MEEM_IKHFA', 'MEEM_IDHAR',
    'GHUNNA', 'MADD_2', 'MADD_4', 'MADD_6',
    'HAMZA', 'BEH', 'TEH', 'THEH', 'JEEM', 'HAH', 'KHAH',
    'DAL', 'THAL', 'REH', 'ZAIN', 'SEEN', 'SHEEN', 'SAD',
    'DAD', 'TAH', 'ZAH', 'AIN', 'GHAIN', 'FEH', 'QAF',
    'KAF', 'LAM', 'MEEM', 'NOON', 'HEH', 'WAW', 'YEH',
    'FATHA', 'KASRA', 'DAMMA',
], key=len, reverse=True)


def _reconstruct_phonemes_from_lm(lm_output):
    """Reconstruct space-separated phonemes from pyctcdecode's concatenated output."""
    word_chunks = lm_output.strip().split()
    result_words = []
    for chunk in word_chunks:
        tokens = []
        i = 0
        while i < len(chunk):
            matched = False
            for tok in _PHONEME_TOKENS:
                if chunk[i:i+len(tok)] == tok:
                    tokens.append(tok)
                    i += len(tok)
                    matched = True
                    break
            if not matched:
                i += 1  # skip unknown character
        if tokens:
            result_words.append(" ".join(tokens))
    return " SP ".join(result_words)


def build_lm_decoder(processor, lm_path="data/lms/phoneme_5gram.bin"):
    """Build a pyctcdecode beam search decoder with KenLM."""
    try:
        from pyctcdecode import build_ctcdecoder
    except ImportError:
        print(f"{Colors.YELLOW}pyctcdecode not installed. Run: pip install pyctcdecode{Colors.RESET}")
        return None

    if not os.path.exists(lm_path):
        print(f"{Colors.YELLOW}KenLM model not found at {lm_path}. Using greedy decoding.{Colors.RESET}")
        return None

    vocab = processor.tokenizer.get_vocab()
    labels = [k for k, v in sorted(vocab.items(), key=lambda x: x[1])]

    # Replace SP with actual space so pyctcdecode produces word boundaries
    labels = [' ' if l == 'SP' else l for l in labels]

    # Extract unigrams from ARPA file if available
    arpa_path = lm_path.replace(".bin", ".arpa")
    unigrams = []
    if os.path.exists(arpa_path):
        in_unigrams = False
        with open(arpa_path, "r") as f:
            for line in f:
                line = line.strip()
                if line == "\\1-grams:":
                    in_unigrams = True
                    continue
                if line.startswith("\\") and in_unigrams:
                    break
                if in_unigrams and line:
                    parts = line.split("\t")
                    if len(parts) >= 2:
                        unigrams.append(parts[1])

    decoder = build_ctcdecoder(
        labels=labels,
        kenlm_model_path=lm_path,
        alpha=1.5,
        beta=0.5,
        unigrams=unigrams if unigrams else None,
    )
    return decoder


# =============================================================================
# MICROPHONE RECORDING Helper
# =============================================================================
def record_audio(filename="temp_recitation.wav", samplerate=16000):
    """Records audio from the microphone until the user presses Enter."""
    print(f"\n🎤 {Colors.CYAN}Ready to record. Press Enter to start...{Colors.RESET}")
    input()
    print(f"🔴 {Colors.RED}Recording... Press Enter again to stop.{Colors.RESET}")
    
    q = queue.Queue()
    
    def callback(indata, frames, time, status):
        if status:
            print(status, file=sys.stderr)
        q.put(indata.copy())
        
    # Record in 16kHz mono to match model requirements
    stream = sd.InputStream(samplerate=samplerate, channels=1, callback=callback)
    with stream:
        input()  # wait for Enter to stop
    
    print(f"✅ {Colors.GREEN}Recording stopped. Saving...{Colors.RESET}")
    data = []
    while not q.empty():
        data.append(q.get())
    
    audio_data = np.concatenate(data, axis=0)
    sf.write(filename, audio_data, samplerate)
    return filename


# =============================================================================
# QURAN DATABASE (Verse Text → Audio File Lookup)
# =============================================================================
def load_quran_database():
    """Loads all unique Arabic verses from the dataset.
    Returns:
        verses: list of unique verse strings
        verse_to_audio: dict mapping verse text → list of (qari_name, audio_path) tuples
    """
    csv_path = DATA_DIR / "everyayah_train.csv"

    if not os.path.exists(csv_path):
        print(f"{Colors.RED}Error: Cannot find Quran database at {csv_path}{Colors.RESET}")
        return [], {}

    verse_to_audio = {}
    unique_verses = set()

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            transcript = row.get("transcript", "").strip()
            wav_filename = row.get("wav_filename", "").strip()
            if transcript and wav_filename:
                unique_verses.add(transcript)
                # Make path absolute if it's relative
                if not os.path.isabs(wav_filename):
                    wav_filename = str(DATA_DIR / wav_filename)
                # Extract qari name from filename
                basename = os.path.basename(wav_filename)
                qari_name = basename.rsplit('_', 1)[0] if '_' in basename else "unknown"
                if transcript not in verse_to_audio:
                    verse_to_audio[transcript] = []
                verse_to_audio[transcript].append((qari_name, wav_filename))

    return list(unique_verses), verse_to_audio


def pick_best_audio(audio_entries):
    """Pick the best audio based on PREFERRED_QARIS priority order."""
    for preferred in PREFERRED_QARIS:
        for qari_name, path in audio_entries:
            if qari_name == preferred and os.path.exists(path):
                return qari_name, path
    for qari_name, path in audio_entries:
        if os.path.exists(path):
            return qari_name, path
    return None, None


# =============================================================================
# AUDIO PLAYBACK
# =============================================================================
def play_audio(wav_path: str):
    """Play a WAV file using the system audio player."""
    if not os.path.exists(wav_path):
        print(f"{Colors.RED}  Audio file not found: {wav_path}{Colors.RESET}")
        return False

    if shutil.which("aplay"):
        try:
            subprocess.run(["aplay", "-q", wav_path], check=True, timeout=30)
            return True
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            pass

    if shutil.which("paplay"):
        try:
            subprocess.run(["paplay", wav_path], check=True, timeout=30)
            return True
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            pass

    print(f"{Colors.YELLOW}  Could not play audio automatically. File saved at: {wav_path}{Colors.RESET}")
    return False


# =============================================================================
# CHARACTER-LEVEL ALIGNMENT & COLORING
# =============================================================================
def colorize_alignment(alignment, ref_chars, hyp_chars):
    """Parses jiwer character alignments and prints the result with colors."""
    colored_output = []
    hits, subs, dels, ins = 0, 0, 0, 0

    for chunk in alignment:
        if chunk.type == 'equal':
            colored_output.append(Colors.GREEN + ref_chars[chunk.ref_start_idx:chunk.ref_end_idx] + Colors.RESET)
            hits += (chunk.ref_end_idx - chunk.ref_start_idx)
        elif chunk.type == 'substitute':
            wrong_chars = hyp_chars[chunk.hyp_start_idx:chunk.hyp_end_idx]
            colored_output.append(Colors.RED + wrong_chars + Colors.RESET)
            subs += (chunk.hyp_end_idx - chunk.hyp_start_idx)
        elif chunk.type == 'delete':
            missing_chars = ref_chars[chunk.ref_start_idx:chunk.ref_end_idx]
            colored_output.append(Colors.RED + f"[{missing_chars}]" + Colors.RESET)
            dels += (chunk.ref_end_idx - chunk.ref_start_idx)
        elif chunk.type == 'insert':
            extra_chars = hyp_chars[chunk.hyp_start_idx:chunk.hyp_end_idx]
            colored_output.append(Colors.YELLOW + f"({extra_chars})" + Colors.RESET)
            ins += (chunk.hyp_end_idx - chunk.hyp_start_idx)

    formatted_string = "".join(colored_output)
    total_expected = hits + subs + dels
    accuracy = (hits / total_expected) * 100 if total_expected > 0 else 0
    return formatted_string, hits, subs, dels, ins, accuracy


# =============================================================================
# WORD-LEVEL CORRECTIONS (phoneme-level comparison, Arabic display)
# =============================================================================
def get_word_corrections(ref_phon_words, pred_phon_words, ref_arabic_words):
    """Performs word-level alignment using phoneme-word sequences.

    Args:
        ref_phon_words:   list of underscore-joined phoneme words (reference)
        pred_phon_words:  list of underscore-joined phoneme words (prediction)
        ref_arabic_words: list of Arabic words for display (from CSV)
    """
    ref_phon_str = " ".join(ref_phon_words)
    pred_phon_str = " ".join(pred_phon_words)

    out = jiwer.process_words(ref_phon_str, pred_phon_str)
    alignment = out.alignments[0]

    corrections = []
    word_num = 0

    for chunk in alignment:
        if chunk.type == 'equal':
            count = chunk.ref_end_idx - chunk.ref_start_idx
            word_num += count

        elif chunk.type == 'substitute':
            for i in range(chunk.ref_end_idx - chunk.ref_start_idx):
                word_num += 1
                ref_idx = chunk.ref_start_idx + i
                hyp_idx = chunk.hyp_start_idx + i if (chunk.hyp_start_idx + i) < len(pred_phon_words) else None
                # Display Arabic for reference, reconstruct Arabic for prediction
                correct_word = ref_arabic_words[ref_idx] if ref_idx < len(ref_arabic_words) else ref_phon_words[ref_idx]
                if hyp_idx is not None:
                    wrong_word = phonemes_to_arabic(pred_phon_words[hyp_idx].replace("_", " "))
                    if not wrong_word.strip():
                        wrong_word = pred_phon_words[hyp_idx]  # fallback to phoneme
                else:
                    wrong_word = "?"
                corrections.append({
                    "type": "wrong", "position": word_num,
                    "you_said": wrong_word, "correct": correct_word,
                })

        elif chunk.type == 'delete':
            for i in range(chunk.ref_end_idx - chunk.ref_start_idx):
                word_num += 1
                ref_idx = chunk.ref_start_idx + i
                correct_word = ref_arabic_words[ref_idx] if ref_idx < len(ref_arabic_words) else ref_phon_words[ref_idx]
                corrections.append({
                    "type": "skipped", "position": word_num,
                    "you_said": "---", "correct": correct_word,
                })

        elif chunk.type == 'insert':
            for i in range(chunk.hyp_end_idx - chunk.hyp_start_idx):
                hyp_idx = chunk.hyp_start_idx + i
                extra_word = phonemes_to_arabic(pred_phon_words[hyp_idx].replace("_", " "))
                if not extra_word.strip():
                    extra_word = pred_phon_words[hyp_idx]
                corrections.append({
                    "type": "extra", "position": word_num,
                    "you_said": extra_word, "correct": "(should not be here)",
                })

    correct_word_count = sum(c.ref_end_idx - c.ref_start_idx for c in alignment if c.type == 'equal')
    total_ref_words = len(ref_phon_words)
    word_accuracy = (correct_word_count / total_ref_words) * 100 if total_ref_words > 0 else 0

    return corrections, correct_word_count, total_ref_words, word_accuracy


# =============================================================================
# MODEL & DATABASE LOADING (done once)
# =============================================================================
def load_model_and_database(model_dir: str, force_cpu: bool = False):
    """Load the acoustic model and Quran database once.

    Returns:
        processor, model, device, quran_verses, verse_to_audio
    """
    print(f"Loading Acoustic Model...")
    processor = Wav2Vec2Processor.from_pretrained(model_dir)
    model = Wav2Vec2ForCTC.from_pretrained(model_dir)
    device = "cpu" if force_cpu else ("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)
    model.eval()

    print("Loading Quran Database...")
    quran_verses, verse_to_audio = load_quran_database()

    print(f"{Colors.GREEN}✅ Model and database loaded successfully! Ready to grade.{Colors.RESET}\n")
    return processor, model, device, quran_verses, verse_to_audio


# =============================================================================
# MAIN GRADING FUNCTION
# =============================================================================
def grade_recitation(wav_path: str, reference_text: str = None,
                     model_dir: str = "checkpoints/tajweed_run/final",
                     play_correction: bool = True,
                     processor=None, model=None, device=None,
                     quran_verses=None, verse_to_audio=None,
                     use_lm: bool = False, lm_decoder=None):
    # 1. Load model if not provided (backward compatible)
    if processor is None or model is None:
        processor, model, device, quran_verses, verse_to_audio = load_model_and_database(
            model_dir, force_cpu=getattr(args, "cpu", False)
        )

    # 2. Process Audio
    audio, sr = sf.read(wav_path, dtype="float32")
    if len(audio.shape) > 1: audio = audio.mean(axis=1)
    
    # Automatically resample to 16kHz if the input audio is different
    if sr != 16000:
        import librosa
        # print(f"{Colors.YELLOW}  (Resampling audio from {sr}Hz to 16000Hz){Colors.RESET}")
        audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)

    inputs = processor(audio, sampling_rate=16000, return_tensors="pt").input_values
    inputs = inputs.to(device)

    # 4. Acoustic Inference → Phoneme tokens
    print("Listening to audio...")
    with torch.no_grad():
        logits = model(inputs).logits

    if use_lm and lm_decoder:
        # Beam search with KenLM language model
        logits_np = logits[0].cpu().numpy()
        lm_raw = lm_decoder.decode(logits_np, beam_width=100)
        pred_phonemes = _reconstruct_phonemes_from_lm(lm_raw)
    else:
        # Greedy decoding (original method)
        pred_ids = torch.argmax(logits, dim=-1)
        pred_phonemes = processor.batch_decode(pred_ids)[0]

    pred_arabic = phonemes_to_arabic(pred_phonemes)

    # 5. Verse Retrieval — PHONEME-SPACE MATCHING
    is_auto_matched = False
    match_confidence = 0.0
    matched_verse_key = None

    if reference_text:
        ref_arabic = reference_text
        best = process.extractOne(ref_arabic, quran_verses, scorer=fuzz.ratio)
        if best and best[1] > 80:
            matched_verse_key = best[0]
    else:
        print("Searching for matching verse (phoneme-space matching)...")
        if not quran_verses:
            print(f"{Colors.RED}Error: No verse database loaded{Colors.RESET}")
            return

        # Build/load phoneme-space database
        phoneme_to_verse, phoneme_list = load_phoneme_database(quran_verses)

        # Match in phoneme space (much more accurate than Arabic-space)
        results = process.extract(
            pred_phonemes, phoneme_list,
            scorer=fuzz.ratio, limit=3
        )

        if results:
            best_ph, match_confidence, _ = results[0]
            ref_arabic = phoneme_to_verse[best_ph]
            matched_verse_key = ref_arabic
            is_auto_matched = True

            # Show top-3 if confidence is ambiguous (top-1 and top-2 within 5%)
            if len(results) >= 2 and (results[0][1] - results[1][1]) < 5:
                print(f"\n{Colors.YELLOW}  Top matches (close confidence — verify correct verse):{Colors.RESET}")
                for rank, (ph_str, conf, _) in enumerate(results, 1):
                    v = phoneme_to_verse[ph_str]
                    marker = " ← selected" if rank == 1 else ""
                    print(f"    #{rank}: {conf:.1f}% — {v[:60]}{marker}")
                print()
        else:
            print(f"{Colors.RED}Error: No matching verse found{Colors.RESET}")
            return

    # 6. Generate reference phonemes from Arabic text
    ref_phonemes_list = text_to_phonemes(ref_arabic)
    ref_phonemes = phonemes_to_string(ref_phonemes_list)

    # 6b. Extract expected Tajweed rules from the verse
    ref_arabic_words_early = ref_arabic.split()
    verse_tajweed_rules = extract_verse_tajweed_rules(ref_phonemes, ref_arabic_words_early)

    # 7. Phoneme-word level comparison (accurate scoring)
    ref_phon_words = split_phoneme_words(ref_phonemes)
    pred_phon_words = split_phoneme_words(pred_phonemes)
    ref_arabic_words = ref_arabic.split()

    # 8. Build colored Arabic display from phoneme-word alignment
    phon_word_out = jiwer.process_words(" ".join(ref_phon_words), " ".join(pred_phon_words))
    colored_parts = []
    for chunk in phon_word_out.alignments[0]:
        if chunk.type == 'equal':
            for idx in range(chunk.ref_start_idx, chunk.ref_end_idx):
                ar = ref_arabic_words[idx] if idx < len(ref_arabic_words) else phonemes_to_arabic(ref_phon_words[idx].replace("_", " "))
                colored_parts.append(Colors.GREEN + ar + Colors.RESET)
        elif chunk.type == 'substitute':
            for i in range(chunk.hyp_start_idx, chunk.hyp_end_idx):
                ar = phonemes_to_arabic(pred_phon_words[i].replace("_", " "))
                if not ar.strip():
                    ar = pred_phon_words[i]
                colored_parts.append(Colors.RED + ar + Colors.RESET)
        elif chunk.type == 'delete':
            for idx in range(chunk.ref_start_idx, chunk.ref_end_idx):
                ar = ref_arabic_words[idx] if idx < len(ref_arabic_words) else ref_phon_words[idx]
                colored_parts.append(Colors.RED + f"[{ar}]" + Colors.RESET)
        elif chunk.type == 'insert':
            for i in range(chunk.hyp_start_idx, chunk.hyp_end_idx):
                ar = phonemes_to_arabic(pred_phon_words[i].replace("_", " "))
                if not ar.strip():
                    ar = pred_phon_words[i]
                colored_parts.append(Colors.YELLOW + f"({ar})" + Colors.RESET)
    colored_str = " ".join(colored_parts)

    # 9. Phoneme-token level accuracy (replaces character-level Arabic accuracy)
    phon_token_out = jiwer.process_words(ref_phonemes, pred_phonemes)
    phon_hits = sum(c.ref_end_idx - c.ref_start_idx for c in phon_token_out.alignments[0] if c.type == 'equal')
    phon_total = len(ref_phonemes.split())
    char_accuracy = (phon_hits / phon_total) * 100 if phon_total > 0 else 0

    # 10. Word-Level Corrections (phoneme comparison, Arabic display)
    corrections, correct_words, total_words, word_accuracy = get_word_corrections(
        ref_phon_words, pred_phon_words, ref_arabic_words
    )

    # 11. Tajweed Violation Detection (Phoneme-level)
    tajweed_violations = detect_tajweed_violations(pred_phonemes, ref_phonemes)

    # 10. Print Report
    print("\n" + "=" * 70)
    print(" 📖 RECITATION GRADING REPORT 📖")
    print("=" * 70)

    if is_auto_matched:
        print(f"{Colors.CYAN}[Auto-Detected Verse] (Confidence: {match_confidence:.1f}%){Colors.RESET}")
        if match_confidence < 60:
            print(f"{Colors.YELLOW}Warning: Confidence is low. The audio might be unclear.{Colors.RESET}")

    print(f"\n{Colors.GREEN}Expected Verse:{Colors.RESET}  {ref_arabic}")
    print(f"What you said :  {colored_str}\n")

    print("--- Legend ---")
    print(f"{Colors.GREEN}Green{Colors.RESET}  = Correctly Pronounced")
    print(f"{Colors.RED}Red{Colors.RESET}    = Mispronounced or Missed [in brackets]")
    print(f"{Colors.YELLOW}Yellow{Colors.RESET} = Added extra sounds (in parentheses)")

    # -- Tajweed Rules Present in This Verse --
    print(f"\n{'=' * 70}")
    print(f" 📜 TAJWEED RULES PRESENT IN THIS VERSE")
    print(f"{'=' * 70}")
    if verse_tajweed_rules:
        for rule_name, occurrences in verse_tajweed_rules.items():
            word_positions = sorted(set(pos for pos, _ in occurrences))
            pos_str = ", ".join(f"#{p}" for p in word_positions)
            print(f"\n  {Colors.CYAN}📌 {rule_name}{Colors.RESET}  — {len(occurrences)} occurrence{'s' if len(occurrences) > 1 else ''}")
            print(f"     At word{'s' if len(word_positions) > 1 else ''}: {pos_str}")
            for pos, tok in occurrences[:5]:
                ar_letter = phonemes_to_arabic(tok.split('_')[0]) if '_' in tok else phonemes_to_arabic(tok)
                print(f"       • Word #{pos}: {tok}" + (f"  ({ar_letter})" if ar_letter.strip() else ""))
            if len(occurrences) > 5:
                print(f"       ... and {len(occurrences) - 5} more")
    else:
        print(f"  {Colors.YELLOW}No special Tajweed rules detected in this verse.{Colors.RESET}")

    # -- Word-by-word corrections --
    if corrections:
        print(f"\n{'=' * 70}")
        print(f" ✏️  WORD-BY-WORD CORRECTIONS")
        print(f"{'=' * 70}")

        for c in corrections:
            if c["type"] == "wrong":
                print(f"\n  {Colors.RED}❌ Mistake at word #{c['position']}:{Colors.RESET}")
                print(f"     You said    : {Colors.RED}{c['you_said']}{Colors.RESET}")
                print(f"     Correct word: {Colors.GREEN}{c['correct']}{Colors.RESET}")
            elif c["type"] == "skipped":
                print(f"\n  {Colors.RED}⏭️  You skipped word #{c['position']}:{Colors.RESET}")
                print(f"     Missing word: {Colors.GREEN}{c['correct']}{Colors.RESET}")
            elif c["type"] == "extra":
                print(f"\n  {Colors.YELLOW}➕ Extra word after position #{c['position']}:{Colors.RESET}")
                print(f"     You added   : {Colors.YELLOW}{c['you_said']}{Colors.RESET}")
                print(f"     {c['correct']}")
    else:
        print(f"\n{Colors.GREEN}{'=' * 70}")
        print(f" ✅ PERFECT RECITATION! No word-level mistakes found!")
        print(f"{'=' * 70}{Colors.RESET}")

    # -- Tajweed Violations (NEW!) --
    hidden_violations = [v for v in tajweed_violations if v["severity"] == "hidden"]
    clear_violations = [v for v in tajweed_violations if v["severity"] == "clear"]

    if tajweed_violations:
        print(f"\n{'=' * 70}")
        print(f" 🕌 TAJWEED RULE VIOLATIONS")
        print(f"{'=' * 70}")

        if clear_violations:
            print(f"\n  {Colors.RED}{Colors.BOLD}Clear Mistakes (affect meaning):{Colors.RESET}")
            for v in clear_violations[:10]:
                print(f"    {Colors.RED}❌ Word #{v['position']}: {v['description']}{Colors.RESET}")

        if hidden_violations:
            print(f"\n  {Colors.YELLOW}{Colors.BOLD}Hidden Mistakes (Tajweed only — experts detect):{Colors.RESET}")
            # Group by rule type
            rules_seen = {}
            for v in hidden_violations:
                rule = v["rule"]
                if rule not in rules_seen:
                    rules_seen[rule] = []
                rules_seen[rule].append(v)

            for rule, vlist in rules_seen.items():
                print(f"\n    {Colors.MAGENTA}📌 {rule} ({len(vlist)} occurrence{'s' if len(vlist) > 1 else ''}):{Colors.RESET}")
                for v in vlist[:5]:  # Show max 5 per rule
                    print(f"       Word #{v['position']}: {v['expected']} → {v['got']}")
                if len(vlist) > 5:
                    print(f"       ... and {len(vlist) - 5} more")

        print(f"\n  Summary: {len(clear_violations)} clear + {len(hidden_violations)} hidden violations")
    else:
        print(f"\n{Colors.GREEN}{'=' * 70}")
        print(f" ✅ PERFECT TAJWEED! No rule violations detected!")
        print(f"{'=' * 70}{Colors.RESET}")

    # -- Final Score --
    print(f"\n{'=' * 70}")
    print(f" 📊 FINAL SCORE")
    print(f"{'=' * 70}")
    print(f"  Words Correct  : {correct_words} / {total_words}")
    print(f"  Word Accuracy  : {word_accuracy:.1f}%")
    print(f"  Letter Accuracy: {char_accuracy:.1f}%")
    print(f"  Tajweed Errors : {len(tajweed_violations)} ({len(clear_violations)} clear, {len(hidden_violations)} hidden)")

    if word_accuracy == 100 and len(tajweed_violations) == 0:
        print(f"\n  {Colors.GREEN}{Colors.BOLD}ما شاء الله! Perfect recitation with perfect Tajweed!{Colors.RESET}")
    elif word_accuracy == 100:
        print(f"\n  {Colors.GREEN}All words correct! But review the Tajweed violations above.{Colors.RESET}")
    elif word_accuracy >= 80:
        print(f"\n  {Colors.GREEN}Very good! Just a few small mistakes.{Colors.RESET}")
    elif word_accuracy >= 50:
        print(f"\n  {Colors.YELLOW}Good effort. Review the corrections above and try again.{Colors.RESET}")
    else:
        print(f"\n  {Colors.RED}Needs more practice. Focus on the corrections above.{Colors.RESET}")
    print("=" * 70)

    # =========================================================================
    # 11. AUDIO CORRECTION — Play the correct recitation
    # =========================================================================
    if corrections and matched_verse_key and matched_verse_key in verse_to_audio:
        audio_entries = verse_to_audio[matched_verse_key]
        qari_name, best_audio_path = pick_best_audio(audio_entries)

        if best_audio_path:
            correction_dir = Path("checkpoints/corrections")
            correction_dir.mkdir(parents=True, exist_ok=True)
            correction_path = correction_dir / "correct_recitation.wav"
            shutil.copy2(best_audio_path, str(correction_path))

            qari_display = qari_name.replace('_', ' ').title()

            print(f"\n{'=' * 70}")
            print(f" 🔊 LISTEN TO THE CORRECT RECITATION")
            print(f"{'=' * 70}")
            print(f"  Qari          : {Colors.CYAN}{qari_display}{Colors.RESET}")
            print(f"  Audio saved to: {Colors.CYAN}{correction_path}{Colors.RESET}")

            if play_correction:
                while True:
                    user_input = input(f"\n  Press {Colors.GREEN}Enter{Colors.RESET} to hear the correct recitation, or '{Colors.RED}q{Colors.RESET}' to stop: ")
                    if user_input.strip().lower() == 'q':
                        break
                    print(f"  🔊 Playing ({qari_display})...")
                    play_audio(str(correction_path))
                    print(f"  ✅ Done! Press Enter to replay or 'q' to stop.")

            print("=" * 70 + "\n")
    elif corrections:
        print(f"\n  {Colors.YELLOW}(No matching audio found in database for playback){Colors.RESET}\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Grade a Quranic recitation audio file.")
    parser.add_argument("wav_path", type=str, nargs="?", default=None,
                        help="Path to the .wav audio file (omit to enter interactive mode)")
    parser.add_argument("reference", type=str, nargs="?", default=None,
                        help="(Optional) The expected verse text in Arabic. If omitted, auto-detects.")
    parser.add_argument("--record", action="store_true",
                        help="Record audio directly from the microphone instead of providing a file")
    parser.add_argument("--use-lm", action="store_true",
                        help="Use KenLM beam search instead of greedy decoding")
    parser.add_argument("--model", type=str, default="checkpoints/local_run/final1",
                        help="Path to the trained model directory")
    parser.add_argument("--no-play", action="store_true",
                        help="Skip audio playback of the correct recitation")
    parser.add_argument("--cpu", action="store_true",
                        help="Force execution on CPU (useful if GPU is busy training)")
    parser.add_argument("--interactive", "-i", action="store_true",
                        help="Interactive mode: load model once, then keep grading audio files")
    args = parser.parse_args()

    # Load model and database once
    processor, model, device, quran_verses, verse_to_audio = load_model_and_database(
        args.model, force_cpu=args.cpu
    )

    # Build LM decoder if requested
    lm_decoder = None
    if args.use_lm:
        print("Loading KenLM beam search decoder...")
        lm_decoder = build_lm_decoder(processor)
        if lm_decoder:
            print(f"{Colors.GREEN}  LM decoder ready (beam search mode){Colors.RESET}")
        else:
            print(f"{Colors.YELLOW}  Falling back to greedy decoding{Colors.RESET}")

    # Determine if we run in interactive or single-file mode
    run_interactive = args.interactive or (args.wav_path is None and not args.record)

    if run_interactive:
        # ===== INTERACTIVE MODE =====
        print("=" * 70)
        print(f" 🎙️  {Colors.CYAN}{Colors.BOLD}INTERACTIVE RECITATION GRADING MODE{Colors.RESET}")
        print("=" * 70)
        print(f"  Model loaded and ready! You can now grade multiple files.")
        print(f"  Type the path to a .wav file, or type '{Colors.GREEN}r{Colors.RESET}' to record from your mic.")
        print(f"  Type '{Colors.RED}q{Colors.RESET}' or '{Colors.RED}quit{Colors.RESET}' to exit.\n")

        while True:
            try:
                user_input = input(f"{Colors.CYAN}Enter wav path (or 'r' to record, 'q' to quit): {Colors.RESET}").strip()
            except (EOFError, KeyboardInterrupt):
                print(f"\n{Colors.GREEN}Goodbye!{Colors.RESET}")
                break

            if user_input.lower() in ('q', 'quit', 'exit'):
                print(f"{Colors.GREEN}Goodbye!{Colors.RESET}")
                break

            if not user_input:
                continue

            ref_text = None
            wav_file = None

            # Check if user typed record command (e.g. 'r' or 'record')
            parts = user_input.split('"')
            cmd_part = parts[0].strip().lower()

            if cmd_part in ('r', 'record'):
                # Microphone recording mode
                # If they typed: r "بِسْمِ اللَّهِ"
                if len(parts) >= 3:
                    ref_text = parts[1].strip()
                wav_file = record_audio()
            else:
                # File input mode
                if len(parts) >= 3:
                    wav_file = parts[0].strip()
                    ref_text = parts[1].strip()
                else:
                    wav_file = user_input
                
                if not os.path.exists(wav_file):
                    print(f"{Colors.RED}  File not found: {wav_file}{Colors.RESET}\n")
                    continue

            grade_recitation(
                wav_file, ref_text, model_dir=args.model,
                play_correction=not args.no_play,
                processor=processor, model=model, device=device,
                quran_verses=quran_verses, verse_to_audio=verse_to_audio,
                use_lm=args.use_lm, lm_decoder=lm_decoder
            )
            print()  # blank line between runs
    else:
        # ===== SINGLE FILE MODE =====
        if args.record:
            wav_path = record_audio()
        else:
            if not args.wav_path:
                print(f"{Colors.RED}Error: You must provide a wav_path or use the --record flag.{Colors.RESET}")
                sys.exit(1)
            wav_path = args.wav_path

        if not os.path.exists(wav_path):
            print(f"{Colors.RED}Error: File not found: {wav_path}{Colors.RESET}")
            sys.exit(1)

        grade_recitation(
            wav_path, args.reference, model_dir=args.model,
            play_correction=not args.no_play,
            processor=processor, model=model, device=device,
            quran_verses=quran_verses, verse_to_audio=verse_to_audio,
            use_lm=args.use_lm, lm_decoder=lm_decoder
        )
