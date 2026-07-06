"""Per-Rule Tajweed Evaluation — Measures accuracy for each Tajweed rule separately.

Runs the trained model on the test set and reports:
  - Overall PER (Phoneme Error Rate)
  - Per-rule accuracy (Qalqalah, Tafkheem, Ghunna, Madd, etc.)
  - Confusion matrix for Tajweed-specific phonemes
  - Error breakdown by rule type

Usage:
    python eval_per_rule.py
    python eval_per_rule.py --model checkpoints/tajweed_run/final --max-samples 500
"""
import argparse
import csv
import sys
import torch
import soundfile as sf
import jiwer
from pathlib import Path
from collections import defaultdict, Counter
from transformers import Wav2Vec2Processor, Wav2Vec2ForCTC

# ── Tajweed rule definitions ─────────────────────────────────────────
TAJWEED_SUFFIXES = {
    "_Q":      "Qalqalah (قلقلة)",
    "_T":      "Tafkheem (تفخيم)",
    "_IDGHAM": "Idgham (إدغام)",
    "_IKHFA":  "Ikhfa (إخفاء)",
    "_IQLAB":  "Iqlab (إقلاب)",
    "_IDHAR":  "Idhar (إظهار)",
}

SPECIAL_RULES = {
    "GHUNNA":  "Ghunna (غنة)",
    "MADD_2":  "Madd 2 beats (مد)",
    "MADD_4":  "Madd 4 beats (مد)",
    "MADD_6":  "Madd 6 beats (مد)",
}


def get_rule(phoneme: str) -> str:
    """Return the Tajweed rule name for a phoneme, or 'Base' if none."""
    if phoneme in SPECIAL_RULES:
        return SPECIAL_RULES[phoneme]
    for suffix, rule in TAJWEED_SUFFIXES.items():
        if phoneme.endswith(suffix):
            return rule
    return "Base Phoneme"


def get_base(phoneme: str) -> str:
    """Strip Tajweed suffix."""
    for suffix in TAJWEED_SUFFIXES:
        if phoneme.endswith(suffix):
            return phoneme[:-len(suffix)]
    return phoneme


def main():
    parser = argparse.ArgumentParser(description="Per-rule Tajweed evaluation")
    parser.add_argument("--model", default="checkpoints/tajweed_run/final",
                        help="Path to the trained model")
    parser.add_argument("--test-csv",
                        default="data/everyayah_full/everyayah_test_tajweed.csv",
                        help="Test CSV with phoneme labels")
    parser.add_argument("--max-samples", type=int, default=500,
                        help="Max samples to evaluate (for speed)")
    parser.add_argument("--max-seconds", type=float, default=15.0,
                        help="Skip audio longer than this")
    args = parser.parse_args()

    # ── Load model ───────────────────────────────────────────────────
    print(f"Loading model from {args.model}...")
    processor = Wav2Vec2Processor.from_pretrained(args.model)
    model = Wav2Vec2ForCTC.from_pretrained(args.model)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model.to(device).eval()
    print(f"Model loaded on {device.upper()}")

    # ── Load test data ───────────────────────────────────────────────
    data_dir = Path(args.test_csv).parent
    samples = []
    with open(args.test_csv, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            wav = row.get("wav_filename", "").strip()
            transcript = row.get("transcript", "").strip()
            if wav and transcript:
                wav_path = Path(wav)
                if not wav_path.is_absolute():
                    wav_path = data_dir / wav
                samples.append((str(wav_path), transcript))

    samples = samples[:args.max_samples]
    print(f"Evaluating on {len(samples)} samples...\n")

    # ── Counters ─────────────────────────────────────────────────────
    # Per-rule: track (correct, total) for each rule category
    rule_correct = defaultdict(int)
    rule_total = defaultdict(int)

    # Confusion: (ref_phoneme, pred_phoneme) → count
    tajweed_confusions = Counter()

    # Overall
    all_refs = []
    all_preds = []
    skipped = 0

    for i, (wav_path, ref_phonemes) in enumerate(samples):
        if (i + 1) % 50 == 0:
            print(f"  [{i+1}/{len(samples)}]...")

        try:
            audio, sr = sf.read(wav_path, dtype="float32")
        except Exception:
            skipped += 1
            continue

        if len(audio.shape) > 1:
            audio = audio.mean(axis=1)
        if len(audio) / 16000 > args.max_seconds:
            skipped += 1
            continue

        inputs = processor(audio, sampling_rate=16000, return_tensors="pt").input_values.to(device)
        with torch.no_grad():
            logits = model(inputs).logits
        pred_ids = torch.argmax(logits, dim=-1)
        pred_phonemes = processor.batch_decode(pred_ids)[0]

        all_refs.append(ref_phonemes)
        all_preds.append(pred_phonemes)

        # ── Per-phoneme alignment ────────────────────────────────────
        ref_tokens = ref_phonemes.split()
        pred_tokens = pred_phonemes.split()

        try:
            out = jiwer.process_words(ref_phonemes, pred_phonemes)
            alignment = out.alignments[0]
        except Exception:
            continue

        for chunk in alignment:
            if chunk.type == "equal":
                for idx in range(chunk.ref_start_idx, chunk.ref_end_idx):
                    tok = ref_tokens[idx]
                    if tok in ("SP", "|", "<pad>", "<unk>"):
                        continue
                    rule = get_rule(tok)
                    rule_correct[rule] += 1
                    rule_total[rule] += 1

            elif chunk.type == "substitute":
                for i in range(chunk.ref_end_idx - chunk.ref_start_idx):
                    ref_idx = chunk.ref_start_idx + i
                    hyp_idx = chunk.hyp_start_idx + i
                    ref_tok = ref_tokens[ref_idx]
                    pred_tok = pred_tokens[hyp_idx] if hyp_idx < len(pred_tokens) else "?"

                    if ref_tok in ("SP", "|", "<pad>", "<unk>"):
                        continue

                    rule = get_rule(ref_tok)
                    rule_total[rule] += 1  # not correct

                    # Track confusions for Tajweed-specific tokens
                    if get_rule(ref_tok) != "Base Phoneme":
                        tajweed_confusions[(ref_tok, pred_tok)] += 1

            elif chunk.type == "delete":
                for idx in range(chunk.ref_start_idx, chunk.ref_end_idx):
                    ref_tok = ref_tokens[idx]
                    if ref_tok in ("SP", "|", "<pad>", "<unk>"):
                        continue
                    rule = get_rule(ref_tok)
                    rule_total[rule] += 1

                    if get_rule(ref_tok) != "Base Phoneme":
                        tajweed_confusions[(ref_tok, "DELETED")] += 1

    # ── Compute overall PER ──────────────────────────────────────────
    if all_refs:
        overall_out = jiwer.process_words(
            " ||| ".join(all_refs),
            " ||| ".join(all_preds),
        )
        overall_per = overall_out.wer * 100
    else:
        overall_per = 100.0

    # ── Print results ────────────────────────────────────────────────
    print("\n" + "=" * 70)
    print(" 📊 PER-RULE TAJWEED EVALUATION REPORT")
    print("=" * 70)

    print(f"\n  Overall Phoneme Error Rate (PER): {overall_per:.2f}%")
    print(f"  Samples evaluated: {len(all_refs)} (skipped: {skipped})")

    # Sort rules: Tajweed rules first, then base
    tajweed_rules = {r: (rule_correct[r], rule_total[r])
                     for r in rule_total if r != "Base Phoneme"}
    base_stats = (rule_correct.get("Base Phoneme", 0), rule_total.get("Base Phoneme", 0))

    print(f"\n{'─' * 70}")
    print(f"  {'Rule':<30} {'Correct':>8} {'Total':>8} {'Accuracy':>10}")
    print(f"{'─' * 70}")

    for rule in sorted(tajweed_rules.keys()):
        correct, total = tajweed_rules[rule]
        acc = (correct / total * 100) if total > 0 else 0
        bar = "█" * int(acc / 5) + "░" * (20 - int(acc / 5))
        emoji = "✅" if acc >= 90 else "⚠️" if acc >= 70 else "❌"
        print(f"  {emoji} {rule:<28} {correct:>8} {total:>8} {acc:>9.1f}%  {bar}")

    # Base phoneme stats
    if base_stats[1] > 0:
        acc = (base_stats[0] / base_stats[1] * 100)
        bar = "█" * int(acc / 5) + "░" * (20 - int(acc / 5))
        print(f"{'─' * 70}")
        print(f"  {'Base Phoneme':<30} {base_stats[0]:>8} {base_stats[1]:>8} {acc:>9.1f}%  {bar}")

    # ── Tajweed confusion matrix ─────────────────────────────────────
    if tajweed_confusions:
        print(f"\n{'=' * 70}")
        print(" 🔍 TOP TAJWEED CONFUSIONS (where the model gets it wrong)")
        print(f"{'=' * 70}")
        print(f"  {'Expected':<20} {'Predicted':<20} {'Count':>8}")
        print(f"{'─' * 70}")
        for (ref, pred), count in tajweed_confusions.most_common(20):
            print(f"  {ref:<20} {pred:<20} {count:>8}")

    print(f"\n{'=' * 70}\n")


if __name__ == "__main__":
    main()
