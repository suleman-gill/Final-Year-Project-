"""Quick evaluation — show sample predictions from the Tajweed phoneme model."""
import os
import torch
import soundfile as sf
import numpy as np
from transformers import Wav2Vec2Processor, Wav2Vec2ForCTC
from train_local import load_csv, phonemes_to_arabic, DATA_DIR


def main():
    model_dir = "checkpoints/tajweed_run/final"
    print(f"Loading model and processor from {model_dir} ...")
    processor = Wav2Vec2Processor.from_pretrained(model_dir)
    model = Wav2Vec2ForCTC.from_pretrained(model_dir)
    model.to("cuda" if torch.cuda.is_available() else "cpu")
    model.eval()

    print("Loading test data ...")
    test_rows = load_csv(DATA_DIR / "everyayah_test_tajweed.csv")

    print("\n--- Sample Predictions (first 10) ---")
    for i in range(min(10, len(test_rows))):
        row = test_rows[i]
        wav_path = row["wav_filename"]
        transcript = row["transcript"]  # Phoneme token sequence

        # Load audio
        audio, sr = sf.read(wav_path, dtype="float32")
        if len(audio.shape) > 1: audio = audio.mean(axis=1)

        # Process input
        inputs = processor(audio, sampling_rate=16000, return_tensors="pt").input_values
        inputs = inputs.to(model.device)

        # Inference
        with torch.no_grad():
            logits = model(inputs).logits

        # Decode
        pred_ids = torch.argmax(logits, dim=-1)
        pred_str = processor.batch_decode(pred_ids)[0]

        # Display both phoneme and Arabic
        ref_arabic = phonemes_to_arabic(transcript)
        pred_arabic = phonemes_to_arabic(pred_str)

        print(f"\n  [REF  Phonemes] {transcript[:100]}")
        print(f"  [REF  Arabic  ] {ref_arabic[:80]}")
        print(f"  [PRED Phonemes] {pred_str[:100]}")
        print(f"  [PRED Arabic  ] {pred_arabic[:80]}")

if __name__ == "__main__":
    main()
