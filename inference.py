"""Inference script for the Tajweed phoneme ASR model.

Transcribes a WAV file into Tajweed phoneme tokens and displays both
the phoneme sequence and an approximate Arabic rendering.

Usage:
    python inference.py recording.wav
    python inference.py recording.wav --model checkpoints/tajweed_run/final
"""
import argparse
import torch
import soundfile as sf
from transformers import Wav2Vec2Processor, Wav2Vec2ForCTC
from train_local import phonemes_to_arabic


def transcribe_audio(wav_path: str, model_dir: str = "checkpoints/tajweed_run/final"):
    print(f"Loading model from {model_dir} ...")

    # Load processor and model
    processor = Wav2Vec2Processor.from_pretrained(model_dir)
    model = Wav2Vec2ForCTC.from_pretrained(model_dir)

    # Move model to GPU if available
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model.to(device)
    model.eval()

    print(f"Loading audio file: {wav_path}")
    # Load audio using soundfile
    audio, sr = sf.read(wav_path, dtype="float32")

    # Convert to mono if stereo
    if len(audio.shape) > 1:
        audio = audio.mean(axis=1)

    # The model was trained on 16000 Hz audio.
    if sr != 16000:
        print(f"Warning: Audio sample rate is {sr}Hz. The model expects 16000Hz. Results may be inaccurate.")

    # Process the audio into the format the model expects
    inputs = processor(audio, sampling_rate=16000, return_tensors="pt").input_values
    inputs = inputs.to(device)

    print("Running inference...")
    # Get predictions
    with torch.no_grad():
        logits = model(inputs).logits

    # Decode the predictions into phoneme tokens
    pred_ids = torch.argmax(logits, dim=-1)
    pred_phonemes = processor.batch_decode(pred_ids)[0]

    # Convert phoneme tokens to approximate Arabic for display
    pred_arabic = phonemes_to_arabic(pred_phonemes)

    print("\n" + "=" * 70)
    print("  TRANSCRIPTION RESULTS")
    print("=" * 70)
    print(f"Phonemes : {pred_phonemes}")
    print(f"Arabic   : {pred_arabic}")
    print("=" * 70 + "\n")

    return pred_phonemes


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Transcribe a WAV file using the Tajweed ASR model.")
    parser.add_argument("wav_path", type=str, help="Path to the .wav audio file")
    parser.add_argument("--model", type=str, default="checkpoints/tajweed_run/final",
                        help="Path to the trained model directory")
    args = parser.parse_args()

    transcribe_audio(args.wav_path, args.model)
