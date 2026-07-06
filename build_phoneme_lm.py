"""Build a phoneme-level KenLM language model from training transcripts.

This script:
  1. Extracts all phoneme transcripts from the training CSV
  2. Writes them to a corpus text file
  3. Builds a 5-gram KenLM ARPA model
  4. Converts it to binary for fast loading

Usage:
    python build_phoneme_lm.py
    python build_phoneme_lm.py --order 5 --output data/lms/phoneme_5gram.arpa
"""
import argparse
import csv
import os
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Build phoneme LM from training data")
    parser.add_argument("--train-csv",
                        default="data/everyayah_full/everyayah_train_tajweed.csv",
                        help="Training CSV with phoneme transcripts")
    parser.add_argument("--order", type=int, default=5,
                        help="N-gram order (default: 5)")
    parser.add_argument("--output-dir", default="data/lms",
                        help="Output directory for LM files")
    args = parser.parse_args()

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    corpus_path = out_dir / "phoneme_corpus.txt"
    arpa_path = out_dir / f"phoneme_{args.order}gram.arpa"
    bin_path = out_dir / f"phoneme_{args.order}gram.bin"

    # ── Step 1: Extract phoneme transcripts ──────────────────────────
    print(f"[Step 1] Extracting phoneme transcripts from {args.train_csv}...")
    n_lines = 0
    with open(args.train_csv, "r", encoding="utf-8") as f_in, \
         open(corpus_path, "w", encoding="utf-8") as f_out:
        reader = csv.DictReader(f_in)
        for row in reader:
            transcript = row.get("transcript", "").strip()
            if transcript:
                f_out.write(transcript + "\n")
                n_lines += 1
    print(f"  Wrote {n_lines} lines to {corpus_path}")

    # ── Step 2: Check if KenLM is available ──────────────────────────
    lmplz = None
    build_binary = None

    # Check common locations
    for search_path in [
        os.environ.get("KENLM_BIN", ""),
        "/usr/local/bin",
        "/usr/bin",
        str(Path.home() / "kenlm" / "build" / "bin"),
        str(Path.cwd() / "kenlm" / "build" / "bin"),
    ]:
        if search_path and os.path.isfile(os.path.join(search_path, "lmplz")):
            lmplz = os.path.join(search_path, "lmplz")
            build_binary = os.path.join(search_path, "build_binary")
            break

    if not lmplz:
        print("\n⚠️  KenLM binaries (lmplz, build_binary) not found!")
        print("To install KenLM:")
        print("  sudo apt install build-essential cmake libboost-all-dev")
        print("  git clone https://github.com/kpu/kenlm")
        print("  cd kenlm && mkdir -p build && cd build && cmake .. && make -j4")
        print(f"\nCorpus file is ready at: {corpus_path}")
        print("Once KenLM is installed, run:")
        print(f"  lmplz -o {args.order} --discount_fallback < {corpus_path} > {arpa_path}")
        print(f"  build_binary {arpa_path} {bin_path}")
        return

    # ── Step 3: Build ARPA model ─────────────────────────────────────
    print(f"\n[Step 2] Building {args.order}-gram ARPA model...")
    with open(corpus_path, "r") as f_in, open(arpa_path, "w") as f_out:
        proc = subprocess.run(
            [lmplz, "-o", str(args.order), "--discount_fallback"],
            stdin=f_in, stdout=f_out, stderr=subprocess.PIPE
        )
    if proc.returncode != 0:
        print(f"  Error: {proc.stderr.decode()}")
        return
    print(f"  Wrote {arpa_path}")

    # ── Step 4: Convert to binary ────────────────────────────────────
    print(f"\n[Step 3] Converting to binary format...")
    proc = subprocess.run(
        [build_binary, str(arpa_path), str(bin_path)],
        stderr=subprocess.PIPE
    )
    if proc.returncode != 0:
        print(f"  Error: {proc.stderr.decode()}")
        return
    print(f"  Wrote {bin_path}")

    # ── Summary ──────────────────────────────────────────────────────
    arpa_size = arpa_path.stat().st_size / (1024 * 1024)
    bin_size = bin_path.stat().st_size / (1024 * 1024)
    print(f"\n✅ Language model built successfully!")
    print(f"  Corpus lines  : {n_lines}")
    print(f"  N-gram order  : {args.order}")
    print(f"  ARPA file     : {arpa_path} ({arpa_size:.1f} MB)")
    print(f"  Binary file   : {bin_path} ({bin_size:.1f} MB)")
    print(f"\nTo use with pyctcdecode, install it:")
    print(f"  pip install pyctcdecode")
    print(f"Then use: decoder = build_ctcdecoder(labels, kenlm_model_path='{bin_path}')")


if __name__ == "__main__":
    main()
