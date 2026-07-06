"""Compare greedy CTC decoding vs LM-boosted beam search decoding.

Shows the PER improvement gained by adding the KenLM phoneme language model
to constrain the CTC output to valid Quranic phoneme sequences.

Usage:
    python eval_with_lm.py
    python eval_with_lm.py --model checkpoints/tajweed_run/final --max-samples 200
"""
import argparse
import csv
import json
import sys
import torch
import soundfile as sf
import jiwer
import numpy as np
from pathlib import Path
from transformers import Wav2Vec2Processor, Wav2Vec2ForCTC
from pyctcdecode import build_ctcdecoder


def main():
    parser = argparse.ArgumentParser(description="Compare greedy vs LM beam search")
    parser.add_argument("--model", default="checkpoints/tajweed_run/final")
    parser.add_argument("--lm-path", default="data/lms/phoneme_5gram.bin",
                        help="Path to KenLM binary model")
    parser.add_argument("--test-csv",
                        default="data/everyayah_full/everyayah_test_tajweed.csv")
    parser.add_argument("--max-samples", type=int, default=200)
    parser.add_argument("--max-seconds", type=float, default=15.0)
    parser.add_argument("--beam-width", type=int, default=100,
                        help="Beam width for beam search")
    parser.add_argument("--lm-weight", type=float, default=1.5,
                        help="LM weight (alpha)")
    args = parser.parse_args()

    # ── Load model ───────────────────────────────────────────────────
    print(f"Loading model from {args.model}...")
    processor = Wav2Vec2Processor.from_pretrained(args.model)
    model = Wav2Vec2ForCTC.from_pretrained(args.model)
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model.to(device).eval()

    # ── Build decoder with LM ────────────────────────────────────────
    print(f"Building beam search decoder with LM: {args.lm_path}...")

    # Get vocab in order from the tokenizer (includes all 58 tokens)
    vocab = processor.tokenizer.get_vocab()
    labels = [k for k, v in sorted(vocab.items(), key=lambda x: x[1])]

    # Extract unigrams from ARPA file for better decoding
    arpa_path = args.lm_path.replace(".bin", ".arpa")
    unigrams = []
    if Path(arpa_path).exists():
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
        kenlm_model_path=args.lm_path,
        alpha=args.lm_weight,
        beta=0.5,
        unigrams=unigrams if unigrams else None,
    )
    print(f"Decoder ready (beam_width={args.beam_width}, alpha={args.lm_weight})")

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
    print(f"\nEvaluating {len(samples)} samples...\n")

    # ── Evaluate ─────────────────────────────────────────────────────
    greedy_refs, greedy_preds = [], []
    lm_refs, lm_preds = [], []
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

        # ── Greedy decoding (current method) ─────────────────────────
        pred_ids = torch.argmax(logits, dim=-1)
        greedy_text = processor.batch_decode(pred_ids)[0]

        # ── LM beam search decoding ─────────────────────────────────
        logits_np = logits[0].cpu().numpy()
        lm_text = decoder.decode(logits_np, beam_width=args.beam_width)

        greedy_refs.append(ref_phonemes)
        greedy_preds.append(greedy_text)
        lm_refs.append(ref_phonemes)
        lm_preds.append(lm_text)

    # ── Compute PER ──────────────────────────────────────────────────
    n_evaluated = len(greedy_refs)

    if n_evaluated == 0:
        print("No samples were evaluated!")
        return

    greedy_out = jiwer.process_words(
        " ||| ".join(greedy_refs), " ||| ".join(greedy_preds)
    )
    greedy_per = greedy_out.wer * 100

    lm_out = jiwer.process_words(
        " ||| ".join(lm_refs), " ||| ".join(lm_preds)
    )
    lm_per = lm_out.wer * 100

    improvement = greedy_per - lm_per
    improvement_pct = (improvement / greedy_per * 100) if greedy_per > 0 else 0

    # ── Print results ────────────────────────────────────────────────
    print("\n" + "=" * 70)
    print(" 📊 GREEDY vs LM BEAM SEARCH COMPARISON")
    print("=" * 70)
    print(f"\n  Samples evaluated : {n_evaluated} (skipped: {skipped})")
    print(f"  Beam width        : {args.beam_width}")
    print(f"  LM weight (alpha) : {args.lm_weight}")
    print(f"\n{'─' * 70}")
    print(f"  {'Method':<30} {'PER':>10}")
    print(f"{'─' * 70}")
    print(f"  Greedy (no LM)               {greedy_per:>9.2f}%")
    print(f"  Beam Search + KenLM 5-gram   {lm_per:>9.2f}%")
    print(f"{'─' * 70}")

    if improvement > 0:
        print(f"\n  ✅ LM improved PER by {improvement:.2f}% ({improvement_pct:.1f}% relative)")
    elif improvement < 0:
        print(f"\n  ⚠️ LM slightly worsened PER by {-improvement:.2f}% (try adjusting --lm-weight)")
    else:
        print(f"\n  ➡️ No difference (model is already very accurate)")

    # ── Show a few examples ──────────────────────────────────────────
    print(f"\n{'=' * 70}")
    print(" 🔍 SAMPLE COMPARISONS (first 3)")
    print(f"{'=' * 70}")
    for i in range(min(3, n_evaluated)):
        print(f"\n  [{i+1}] Reference : {greedy_refs[i][:80]}...")
        print(f"      Greedy   : {greedy_preds[i][:80]}...")
        print(f"      LM Beam  : {lm_preds[i][:80]}...")

    print(f"\n{'=' * 70}\n")


if __name__ == "__main__":
    main()
