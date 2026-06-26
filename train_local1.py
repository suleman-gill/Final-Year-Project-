"""
Local training script for Quranic Phoneme ASR on RTX 4080.

Reads Tajweed phoneme CSVs + WAV files, trains Wav2Vec2 XLS-R 300M CTC
on 53 Tajweed phoneme tokens, and reports PER/WER results.

Usage:
    python train_local.py --epochs 15 --max-train 120000
    python train_local.py --epochs 1 --max-train 5000    # smoke test
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import random
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

import numpy as np
import torch
import soundfile as sf
from torch.utils.data import Dataset as TorchDataset
from transformers import (
    Trainer,
    TrainingArguments,
    Wav2Vec2FeatureExtractor,
    Wav2Vec2ForCTC,
    Wav2Vec2Processor,
    set_seed,
)

# Phoneme tokenizer — handles multi-character, space-separated tokens
# (e.g., "BEH KASRA SEEN MEEM_IDGHAM SP")
try:
    from transformers import Wav2Vec2PhonemeCTCTokenizer
except ImportError:
    # Older transformers versions might not have this; fall back
    from transformers import Wav2Vec2CTCTokenizer as Wav2Vec2PhonemeCTCTokenizer

import jiwer

# =============================================================================
# 1. DATA LOADING
# =============================================================================
DATA_DIR = Path(__file__).parent / "data" / "everyayah_full"

# Phoneme-to-Arabic mapping for display purposes
# Maps phoneme tokens back to approximate Arabic representation
PHONEME_TO_ARABIC = {
    "HAMZA": "ء", "BEH": "ب", "TEH": "ت", "THEH": "ث", "JEEM": "ج",
    "HAH": "ح", "KHAH": "خ", "DAL": "د", "THAL": "ذ", "REH": "ر",
    "ZAIN": "ز", "SEEN": "س", "SHEEN": "ش", "SAD": "ص", "DAD": "ض",
    "TAH": "ط", "ZAH": "ظ", "AIN": "ع", "GHAIN": "غ", "FEH": "ف",
    "QAF": "ق", "KAF": "ك", "LAM": "ل", "MEEM": "م", "NOON": "ن",
    "HEH": "ه", "WAW": "و", "YEH": "ي",
    "FATHA": "َ", "KASRA": "ِ", "DAMMA": "ُ",
    "ALIF_M": "ا", "YEH_M": "ي", "WAW_M": "و",
    # Qalqalah variants → same letter with marker
    "QAF_Q": "ق⁺", "TAH_Q": "ط⁺", "BEH_Q": "ب⁺", "JEEM_Q": "ج⁺", "DAL_Q": "د⁺",
    # Tafkheem variants
    "REH_T": "رˤ", "LAM_T": "لˤ",
    # Noon rules
    "NOON_IDGHAM": "نᵈ", "NOON_IKHFA": "نᵡ", "NOON_IQLAB": "نᵐ", "NOON_IDHAR": "نᶻ",
    # Meem rules
    "MEEM_IDGHAM": "مᵈ", "MEEM_IKHFA": "مᵡ", "MEEM_IDHAR": "مᶻ",
    # Ghunna
    "GHUNNA": "ﻏ̃",
    # Madd counts
    "MADD_2": "~2", "MADD_4": "~4", "MADD_6": "~6",
    # Space
    "SP": " ",
}


def phonemes_to_arabic(phoneme_str: str) -> str:
    """Convert a space-separated phoneme string to approximate Arabic display."""
    tokens = phoneme_str.split()
    result = []
    for tok in tokens:
        if tok in PHONEME_TO_ARABIC:
            result.append(PHONEME_TO_ARABIC[tok])
        elif tok == "|":
            result.append(" ")
        else:
            result.append(f"[{tok}]")
    return "".join(result)


def load_csv(path: Path) -> List[Dict[str, str]]:
    """Load a phoneme CSV file."""
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            cleaned = {k.strip(): v.strip() for k, v in row.items()}
            # Make wav_filename absolute if relative
            if "wav_filename" in cleaned:
                wav_path = cleaned["wav_filename"]
                if not os.path.isabs(wav_path):
                    cleaned["wav_filename"] = str(DATA_DIR / wav_path)
            rows.append(cleaned)
    return rows


# =============================================================================
# 2. PYTORCH DATASET (loads WAV directly with soundfile)
# =============================================================================
class QuranASRDataset(TorchDataset):
    """Lazy-loading dataset that reads WAV files on the fly."""

    def __init__(self, rows: List[Dict[str, str]], processor: Wav2Vec2Processor,
                 max_seconds: float = 15.0, target_sr: int = 16000):
        self.rows = rows
        self.processor = processor
        self.max_seconds = max_seconds
        self.target_sr = target_sr

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, idx):
        row = self.rows[idx]
        wav_path = row["wav_filename"]
        transcript = row["transcript"]   # Now contains phoneme tokens like "BEH KASRA SEEN ..."

        # Load audio
        audio, sr = sf.read(wav_path, dtype="float32")
        if len(audio.shape) > 1:
            audio = audio.mean(axis=1)  # mono
        if sr != self.target_sr:
            import librosa
            audio = librosa.resample(audio, orig_sr=sr, target_sr=self.target_sr)

        # Feature extraction
        inputs = self.processor(
            audio, sampling_rate=self.target_sr
        )
        input_values = inputs.input_values[0]

        # Tokenize phoneme transcript
        # The PhonemeCTCTokenizer splits on spaces and maps each phoneme token to an ID
        labels = self.processor.tokenizer(transcript).input_ids

        return {
            "input_values": input_values,
            "labels": labels,
            "input_length": len(input_values),
        }


# =============================================================================
# 3. CTC DATA COLLATOR
# =============================================================================
@dataclass
class DataCollatorCTCWithPadding:
    processor: Wav2Vec2Processor
    padding: Union[bool, str] = True

    def __call__(self, features: List[Dict]) -> Dict[str, torch.Tensor]:
        input_features = [{"input_values": f["input_values"]} for f in features]

        batch = self.processor.pad(
            input_features, padding=self.padding, return_tensors="pt"
        )

        # Pad labels manually
        label_sequences = [f["labels"] for f in features]
        max_label_len = max(len(l) for l in label_sequences)
        padded_labels = []
        for l in label_sequences:
            pad_len = max_label_len - len(l)
            padded = l + [-100] * pad_len
            padded_labels.append(padded)
        batch["labels"] = torch.tensor(padded_labels, dtype=torch.long)
        return batch


# =============================================================================
# 4. METRICS
# =============================================================================
def per(hyps, refs):
    """Phoneme Error Rate — each whitespace-separated token is a 'word' for jiwer."""
    return float(jiwer.wer(list(refs), list(hyps))) * 100.0


def wer_no_del(hyps, refs):
    """WER without deletions (paper Eq. 2)."""
    out = jiwer.process_words(list(refs), list(hyps))
    S, I, C = out.substitutions, out.insertions, out.hits
    if S + C == 0:
        return 0.0
    return ((S + I) / (S + C)) * 100.0


# =============================================================================
# 5. MAIN
# =============================================================================
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-train", type=int, default=120000,
                        help="Max training samples (default: 120000 = full dataset)")
    parser.add_argument("--max-eval", type=int, default=5000,
                        help="Max evaluation samples")
    parser.add_argument("--epochs", type=int, default=15,
                        help="Training epochs (paper uses 15)")
    parser.add_argument("--batch-size", type=int, default=8,
                        help="Per-device batch size")
    parser.add_argument("--grad-accum", type=int, default=2,
                        help="Gradient accumulation steps")
    parser.add_argument("--lr", type=float, default=1e-4,
                        help="Learning rate (paper uses 1e-4)")
    parser.add_argument("--max-seconds", type=float, default=15.0,
                        help="Max audio duration in seconds")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--output-dir", default="./checkpoints/tajweed_run",
                        help="Output directory for checkpoints")
    parser.add_argument("--pretrained", default="facebook/wav2vec2-xls-r-300m",
                        help="Pretrained model ID")
    args = parser.parse_args()

    set_seed(args.seed)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------ data
    print("=" * 70)
    print(" Quranic Tajweed Phoneme-CTC ASR — Local RTX 4080 Trainer")
    print("=" * 70)

    # Load the NEW Tajweed phoneme CSVs (not the old Buckwalter ones)
    train_rows = load_csv(DATA_DIR / "everyayah_train_tajweed.csv")
    dev_rows = load_csv(DATA_DIR / "everyayah_dev_tajweed.csv")
    test_rows = load_csv(DATA_DIR / "everyayah_test_tajweed.csv")
    print(f"[data] loaded: train={len(train_rows)}, dev={len(dev_rows)}, test={len(test_rows)}")

    # Filter by duration (estimated from file size: 16kHz 16-bit mono ≈ 32000 bytes/sec)
    def filter_by_duration(rows, max_sec):
        filtered = []
        for r in rows:
            fsize = int(r.get("wav_filesize", 0))
            if fsize > 0:
                est_sec = fsize / 32000.0
                if est_sec > max_sec or est_sec < 0.5:
                    continue
            wav_path = r["wav_filename"]
            if not os.path.exists(wav_path):
                continue
            filtered.append(r)
        return filtered

    train_rows = filter_by_duration(train_rows, args.max_seconds)
    dev_rows = filter_by_duration(dev_rows, args.max_seconds)
    test_rows = filter_by_duration(test_rows, args.max_seconds)
    print(f"[data] after duration filter: train={len(train_rows)}, dev={len(dev_rows)}, test={len(test_rows)}")

    # Shuffle and subsample
    random.seed(args.seed)
    random.shuffle(train_rows)
    train_rows = train_rows[: args.max_train]
    dev_rows = dev_rows[: args.max_eval]
    test_rows = test_rows[: args.max_eval]
    print(f"[data] subsampled: train={len(train_rows)}, dev={len(dev_rows)}, test={len(test_rows)}")

    # ------------------------------------------------------------ processor
    # Use the canonical 53-phoneme vocab generated by relabel_with_phonemes.py
    vocab_path = DATA_DIR / "vocab_phoneme.json"
    if not vocab_path.exists():
        raise FileNotFoundError(
            f"Phoneme vocab not found at {vocab_path}.\n"
            "Run: python relabel_with_phonemes.py"
        )

    # Copy vocab to output dir for checkpoint portability
    import shutil
    out_vocab = out_dir / "vocab_phoneme.json"
    shutil.copy2(str(vocab_path), str(out_vocab))

    tokenizer = Wav2Vec2PhonemeCTCTokenizer(
        str(vocab_path),
        unk_token="<unk>",
        pad_token="<pad>",
        word_delimiter_token="|",
        phone_delimiter_token=" ",   # phonemes are space-separated
        do_phonemize=False,          # we already phonemised via tajweed_g2p
    )
    feature_extractor = Wav2Vec2FeatureExtractor(
        feature_size=1,
        sampling_rate=16000,
        padding_value=0.0,
        do_normalize=True,
        return_attention_mask=True,
    )
    processor = Wav2Vec2Processor(
        feature_extractor=feature_extractor, tokenizer=tokenizer
    )

    print(f"[tokenizer] vocab size: {len(tokenizer)} tokens")
    print(f"[tokenizer] sample encode: 'BEH KASRA' → {tokenizer('BEH KASRA').input_ids}")

    # ------------------------------------------------- PyTorch datasets
    train_ds = QuranASRDataset(train_rows, processor, max_seconds=args.max_seconds)
    val_ds = QuranASRDataset(dev_rows, processor, max_seconds=args.max_seconds)
    test_ds = QuranASRDataset(test_rows, processor, max_seconds=args.max_seconds)

    # --------------------------------------------------------------- model
    print(f"[model] loading {args.pretrained} ...")
    model = Wav2Vec2ForCTC.from_pretrained(
        args.pretrained,
        attention_dropout=0.1,
        hidden_dropout=0.1,
        feat_proj_dropout=0.0,
        mask_time_prob=0.05,
        layerdrop=0.05,
        ctc_loss_reduction="mean",
        ctc_zero_infinity=True,
        vocab_size=len(tokenizer),
        pad_token_id=tokenizer.pad_token_id,
        ignore_mismatched_sizes=True,
    )
    # Freeze feature encoder (paper §V-C: transfer learning from pretrained)
    model.freeze_feature_encoder()

    # ----------------------------------------------------------- metrics
    def compute_metrics(pred):
        pred_ids = np.argmax(pred.predictions, axis=-1)
        pred.label_ids[pred.label_ids == -100] = tokenizer.pad_token_id
        pred_str = processor.batch_decode(pred_ids)
        label_str = processor.batch_decode(pred.label_ids, group_tokens=False)
        return {"per": per(pred_str, label_str)}

    # -------------------------------------------------------- training args
    n_gpu = max(torch.cuda.device_count(), 1)
    eff_batch = args.batch_size * args.grad_accum * n_gpu
    steps_per_epoch = max(len(train_ds) // eff_batch, 1)
    total_steps = steps_per_epoch * args.epochs

    print(f"\n{'=' * 70}")
    print(f"  GPU              : {torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'}")
    if torch.cuda.is_available():
        print(f"  VRAM             : {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
    print(f"  Train samples    : {len(train_ds)}")
    print(f"  Val samples      : {len(val_ds)}")
    print(f"  Test samples     : {len(test_ds)}")
    print(f"  Epochs           : {args.epochs}")
    print(f"  Batch (device)   : {args.batch_size}")
    print(f"  Grad accum       : {args.grad_accum}")
    print(f"  Effective batch  : {eff_batch}")
    print(f"  Steps/epoch      : {steps_per_epoch}")
    print(f"  Total steps      : {total_steps}")
    print(f"  FP16             : {torch.cuda.is_available()}")
    print(f"  Learning rate    : {args.lr}")
    print(f"  Vocab tokens     : {len(tokenizer)} (53 phonemes + 3 special)")
    print(f"{'=' * 70}\n")

    eval_steps = max(steps_per_epoch // 2, 50)

    training_args = TrainingArguments(
        output_dir=str(out_dir),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        per_device_eval_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        learning_rate=args.lr,
        warmup_steps=max(int(total_steps * 0.1), 1),
        weight_decay=0.0,
        fp16=torch.cuda.is_available(),
        eval_strategy="steps",
        eval_steps=eval_steps,
        save_strategy="steps",
        save_steps=eval_steps,
        logging_steps=25,
        load_best_model_at_end=True,
        metric_for_best_model="per",
        greater_is_better=False,
        dataloader_num_workers=2,
        save_total_limit=2,
        seed=args.seed,
        report_to=["none"],
        push_to_hub=False,
        remove_unused_columns=False,
    )

    collator = DataCollatorCTCWithPadding(processor=processor, padding=True)

    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_ds,
        eval_dataset=val_ds,
        data_collator=collator,
        processing_class=processor.feature_extractor,
        compute_metrics=compute_metrics,
    )

    # ------------------------------------------------------------ train
    t0 = time.time()
    print("[train] starting training ...")
    trainer.train()
    train_time = time.time() - t0
    print(f"\n[train] finished in {train_time / 60:.1f} minutes")

    # Save final model
    final_dir = out_dir / "final"
    trainer.save_model(str(final_dir))
    processor.save_pretrained(str(final_dir))
    print(f"[train] saved model to {final_dir}")

    # ------------------------------------------------------------ evaluate
    print("\n[eval] running final evaluation on test split ...")
    raw = trainer.predict(test_ds)
    pred_ids = np.argmax(raw.predictions, axis=-1)
    label_ids = raw.label_ids.copy()
    label_ids[label_ids == -100] = tokenizer.pad_token_id

    pred_str = processor.batch_decode(pred_ids)
    label_str = processor.batch_decode(label_ids, group_tokens=False)

    test_per = per(pred_str, label_str)
    test_wer = float(jiwer.wer(list(label_str), list(pred_str))) * 100.0
    test_wer_nd = wer_no_del(pred_str, label_str)

    print("\n" + "=" * 70)
    print("  FINAL TEST RESULTS (greedy decode, no LM)")
    print("=" * 70)
    print(f"  PER  (Phoneme Error Rate)        : {test_per:6.2f} %")
    print(f"  WER  (Word Error Rate)           : {test_wer:6.2f} %")
    print(f"  WER without deletions            : {test_wer_nd:6.2f} %")
    print(f"  Training time                    : {train_time / 60:.1f} min")
    print(f"  Vocab                            : {len(tokenizer)} phoneme tokens")
    print("=" * 70)

    # Show some sample predictions
    print("\n--- Sample Predictions (first 10) ---")
    for i in range(min(10, len(pred_str))):
        ref_arabic = phonemes_to_arabic(label_str[i])
        pred_arabic = phonemes_to_arabic(pred_str[i])
        print(f"\n  [REF  Phonemes] {label_str[i][:100]}")
        print(f"  [REF  Arabic  ] {ref_arabic[:80]}")
        print(f"  [PRED Phonemes] {pred_str[i][:100]}")
        print(f"  [PRED Arabic  ] {pred_arabic[:80]}")

    # Save results
    results = {
        "PER": round(test_per, 2),
        "WER": round(test_wer, 2),
        "WER_without_deletions": round(test_wer_nd, 2),
        "train_samples": len(train_ds),
        "val_samples": len(val_ds),
        "test_samples": len(test_ds),
        "epochs": args.epochs,
        "effective_batch_size": eff_batch,
        "training_time_min": round(train_time / 60, 1),
        "vocab_size": len(tokenizer),
    }
    results_path = out_dir / "test_results.json"
    with open(results_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\n[eval] results saved to {results_path}")


if __name__ == "__main__":
    main()
