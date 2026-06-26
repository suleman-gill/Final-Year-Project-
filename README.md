# Tajweed-Aware Quranic Speech Recognition (80-Token ASR)

An end-to-end, speaker-independent automatic speech recognition (ASR) system designed to evaluate Quranic recitation and detect Tajweed pronunciation errors. The system is built by fine-tuning the **Wav2Vec2-XLS-R-300M** architecture using connectionist temporal classification (CTC) loss, mapping raw audio waveforms directly to an expanded phonetic vocabulary of **80 tokens** that represent standard Arabic phonemes and Tajweed rules.

---

## 📂 Project Directory Structure

```
FYP/
├── checkpoints/              # Model weights and tokenizer configurations
│   └── 
│       ├── final1/           # Default active model checkpoint (Wav2Vec2)
│       └── vocab_phoneme.json
├── data/                     # Dataset directories
│   └── Everyayah_full/
│       ├── vocab_tajweed.json # Expanded 80-token vocabulary definition
│       └── wav/              # Reference Quranic audio recordings for playback
├── eval_recitation1.py       # Core evaluation, microphone, and alignment engine                 
├── test_results1.json        # Test metrics (PER, WER, Batch size, Epochs)
└── README.md                 # Project documentation (this file)
```

---

## 🛠️ System Prerequisites & Installation

To run the evaluation script, you must configure the Python virtual environment and set up the required system-level libraries for handling audio files and live microphone recordings.

### 1. System Dependencies (Linux/Debian)
Install audio extraction and microphone recording development libraries:
```bash
sudo apt-get update
sudo apt-get install -y libsndfile1 portaudio19-dev python3-dev
```

### 2. Python Environment Setup
Create and activate your virtual environment:
```bash
# From the project root directory
python3 -m venv env
source env/bin/activate
cd FYP
```

### 3. Package Installation
Install the required libraries:
```bash
pip install torch transformers librosa sounddevice soundfile jiwer rapidfuzz pyaudio
```

---

## ⚙️ How the Evaluation Pipeline Works

The system evaluates recitations through a four-stage process:

```
[Voice Input] ➔ [Wav2Vec2 Inference] ➔ [Phoneme Alignment] ➔ [Tajweed Assessment]
```

1. **Acoustic Processing**: The raw audio waveform is resampled to **16,000 Hz Mono** and normalized. The frozen 7-layer CNN extracts features, and the 24 Transformer layers construct contextual representations.
2. **CTC Decoding**:
   * *Greedy Search*: Selects the highest-probability token per 20ms frame, collapsing repeating elements.
   * *KenLM Beam Search (`--use-lm`)*: Scores sequences using a 5-gram phonemic language model to reduce noise.
3. **Phoneme-Space Retrieval**: The predicted phoneme string is compared against all Quranic verse phonemes in the precomputed database using Levenshtein distance (`rapidfuzz`). If the user does not specify a reference verse, the system automatically detects the closest matching verse.
4. **Levenshtein Alignment**: The predicted sequence is aligned against the reference verse at the word/phoneme level using `jiwer.process_words`.
5. **Tajweed Error Classification**: 
   * **Clear Mistakes**: Core character changes (e.g., substituting `KAF` for `QAF`).
   * **Hidden Mistakes**: Missing Tajweed rules (e.g., omitting `GHUNNA` or skipping `QALQALAH`).
   * **Color-Coded Feedback**: Green indicates correct pronunciation, red indicates deletions/mistakes, and yellow highlights missing Tajweed rules.

---

## 🗂️ The 80-Token Tajweed Vocabulary

The model’s vocabulary (`vocab_tajweed.json`) features 80 distinct tokens:

* **Arabic Consonants**: `HAMZA`, `BEH`, `TEH`, `THEH`, `JEEM`, `HAH`, `KHAH`, `DAL`, `THAL`, `REH`, `ZAIN`, `SEEN`, `SHEEN`, `SAD`, `DAD`, `TAH`, `ZAH`, `AIN`, `GHAIN`, `FEH`, `QAF`, `KAF`, `LAM`, `MEEM`, `NOON`, `HEH`, `WAW`, `YEH`.
* **Short Vowels & Vowel Lengths**: `FATHA`, `KASRA`, `DAMMA`, `ALIF_M`, `YEH_M`, `WAW_M`.
* **Qalqalah (Echoing)**: `QAF_Q`, `TAH_Q`, `BEH_Q`, `JEEM_Q`, `DAL_Q`.
* **Tafkheem/Tarqeeq (Heavy/Light)**: `REH_T`, `LAM_T`.
* **Noon Sakinah & Tanween Rules**: `NOON_IDGHAM`, `NOON_IKHFA`, `NOON_IQLAB`, `NOON_IDHAR`.
* **Meem Sakinah Rules**: `MEEM_IDGHAM`, `MEEM_IKHFA`, `MEEM_IDHAR`.
* **Madd Lengths (Vowel extension beats)**: `MADD_2`, `MADD_4`, `MADD_6`.
* **Special Tokens**: `<pad>`, `<unk>`, `|` (word boundary), `SP` (space).

---

## 📊 Evaluation & Training Metrics

| Metric | Value |
| :--- | :--- |
| **Phoneme Error Rate (PER)** | **2.20%** |
| **Word Error Rate (WER)** | **2.20%** |
| **WER (Without Deletions)** | **2.16%** |
| **Training Samples** | 79,396 verses |
| **Validation / Test Samples** | 5,000 / 5,000 verses |
| **Training Epochs** | 15 |
| **Effective Batch Size** | 16 |
| **Total Training Time** | 716.5 minutes (~11.9 hours) |

---

## 💻 CLI Commands & Arguments Reference

The core entry point for evaluation is `eval_recitation1.py`.

### Command Line Arguments

```bash
python eval_recitation1.py [wav_path] [reference] [options]
```

* **`wav_path`** *(positional, optional)*: Path to the `.wav` audio file. If omitted, the script automatically enters interactive mode.
* **`reference`** *(positional, optional)*: The expected verse text in Arabic. If omitted, the system auto-detects the matching verse in phoneme space.
* **`--record`**: Records directly from the microphone instead of loading a file.
* **`--use-lm`**: Uses the KenLM 5-gram language model for beam search decoding.
* **`--model <path>`**: Path to the Wav2Vec2 model directory (default: `checkpoints/local_run/final1`).
* **`--no-play`**: Disables audio playback of the correct recitation.
* **`--cpu`**: Forces inference to run on CPU.
* **`--interactive` / `-i`**: Runs in interactive mode (loads the model once, then remains open for multiple evaluations).

---

## 💡 Usage Examples

### 1. Interactive Mode (Recommended)
Loads the model into RAM once, allowing you to run multiple recitations back-to-back:
```bash
python eval_recitation1.py -i
```
* **Mic Recording**: Type `r` and press Enter to record from your microphone. Press Enter again to stop recording.
* **Mic Recording with expected verse**: Type `r "إِنَّا أَعْطَيْنَاكَ الْكَوْثَرَ"` to record and align against that specific verse.
* **File Input**: Type the path to any WAV file (e.g., `test_audio.wav`) and press Enter to evaluate it.
* **Quit**: Type `q` and press Enter to exit interactive mode.

### 2. Single Run File Evaluation
Grades a pre-recorded file and exits:
```bash
python eval_recitation1.py path/to/recording.wav
```

### 3. Auto-Detect and Grade Live Microphone Input
Record from the microphone for a single evaluation run (the system automatically matches the verse):
```bash
python eval_recitation1.py --record
```

### 4. Grade File with Specific Expected Verse and Language Model
Run with KenLM beam search decoding, validating against a specific Arabic verse reference:
```bash
python eval_recitation1.py path/to/recording.wav "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ" --use-lm
```
