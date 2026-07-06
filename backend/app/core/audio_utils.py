"""
Tilawah AI — Audio Preprocessing Pipeline.

Converts base64-encoded PCM audio from the Flutter client into
16 kHz PyTorch tensors ready for Wav2Vec2 inference.
"""

import base64
import io
import struct
import logging
from typing import Optional, Tuple

import numpy as np
import soundfile as sf

logger = logging.getLogger("uvicorn")

# ── Constants ─────────────────────────────────────────────────────────
TARGET_SAMPLE_RATE = 16_000  # Wav2Vec2 requirement
PCM_DTYPE = np.int16         # 16-bit signed PCM from Flutter's AudioRecorder


def validate_audio_frame(base64_str: str, max_bytes: int) -> bool:
    """
    Check if the base64-encoded audio frame is within the allowed size.

    Args:
        base64_str: Raw base64 string from the WebSocket payload.
        max_bytes: Maximum allowed size in bytes (default 1 MB).

    Returns:
        True if the frame is within limits, False otherwise.
    """
    # Base64 encodes 3 bytes into 4 characters.
    # Estimated decoded size = len(base64_str) * 3 / 4
    estimated_bytes = len(base64_str) * 3 // 4
    return estimated_bytes <= max_bytes


def decode_audio_base64(
    base64_str: str,
    sample_rate: int = TARGET_SAMPLE_RATE,
    num_channels: int = 1,
) -> np.ndarray:
    """
    Decode a base64-encoded PCM16, WAV, or WebM/Opus audio chunk into a numpy float32 array.

    Supports:
      - WAV files (via soundfile)
      - WebM/Opus/OGG and other formats (via pydub + ffmpeg fallback)
      - Raw PCM16 bytes (final fallback)
    """
    raw_bytes = base64.b64decode(base64_str)

    if len(raw_bytes) < 2:
        logger.warning("[AudioUtils] Received audio frame with < 2 bytes, returning empty array.")
        return np.array([], dtype=np.float32)

    # ── Attempt 1: WAV file (starts with RIFF header) ───────────────
    if raw_bytes.startswith(b'RIFF'):
        try:
            data, sr = sf.read(io.BytesIO(raw_bytes))
            if len(data.shape) > 1:
                data = np.mean(data, axis=-1)
            if sr != TARGET_SAMPLE_RATE:
                data = resample_to_16khz(data, sr)
            logger.info(f"[AudioUtils] Decoded WAV: {len(data)} samples, sr={sr}")
            return data.astype(np.float32)
        except Exception as e:
            logger.error(f"[AudioUtils] Failed to decode WAV using soundfile: {e}")

    # ── Attempt 2: WebM/Opus/OGG/MP3 via pydub + ffmpeg ─────────────
    # WebM starts with 0x1A45DFA3 (EBML header)
    # OGG starts with 'OggS'
    is_webm = raw_bytes[:4] == b'\x1a\x45\xdf\xa3'
    is_ogg = raw_bytes[:4] == b'OggS'
    if is_webm or is_ogg or len(raw_bytes) > 44:
        try:
            audio_np = _decode_with_pydub(raw_bytes)
            if audio_np is not None and len(audio_np) > 0:
                return audio_np
        except Exception as e:
            logger.warning(f"[AudioUtils] pydub decoding failed: {e}")

    # ── Attempt 3: Raw PCM16 (final fallback) ────────────────────────
    logger.info(f"[AudioUtils] Interpreting {len(raw_bytes)} bytes as raw PCM16")
    num_samples = len(raw_bytes) // 2
    pcm_samples = np.frombuffer(raw_bytes[:num_samples * 2], dtype=np.int16)
    audio_float = pcm_samples.astype(np.float32) / 32768.0
    return audio_float


def _decode_with_pydub(raw_bytes: bytes) -> Optional[np.ndarray]:
    """
    Decode audio bytes in any format using pydub (backed by ffmpeg).

    Returns float32 numpy array at 16kHz mono, or None on failure.
    """
    try:
        # Try to find ffmpeg from imageio-ffmpeg (pip-installed binary)
        import imageio_ffmpeg
        ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

        import os
        # Set ffmpeg path for pydub
        os.environ["FFMPEG_BINARY"] = ffmpeg_exe

        from pydub import AudioSegment
        AudioSegment.converter = ffmpeg_exe

        # Detect format from magic bytes
        fmt = None
        if raw_bytes[:4] == b'\x1a\x45\xdf\xa3':
            fmt = "webm"
        elif raw_bytes[:4] == b'OggS':
            fmt = "ogg"
        elif raw_bytes[:3] == b'ID3' or raw_bytes[:2] == b'\xff\xfb':
            fmt = "mp3"
        elif raw_bytes[:4] == b'fLaC':
            fmt = "flac"

        # Load audio using pydub
        audio_buf = io.BytesIO(raw_bytes)
        if fmt:
            audio = AudioSegment.from_file(audio_buf, format=fmt)
        else:
            audio = AudioSegment.from_file(audio_buf)

        # Convert to 16kHz mono PCM
        audio = audio.set_channels(1).set_frame_rate(TARGET_SAMPLE_RATE).set_sample_width(2)

        # Extract raw PCM samples
        pcm_data = np.frombuffer(audio.raw_data, dtype=np.int16)
        audio_float = pcm_data.astype(np.float32) / 32768.0

        logger.info(
            f"[AudioUtils] Decoded {fmt or 'unknown'} via pydub: "
            f"{len(audio_float)} samples, duration={len(audio_float)/TARGET_SAMPLE_RATE:.2f}s"
        )
        return audio_float

    except ImportError as e:
        logger.warning(f"[AudioUtils] pydub/imageio-ffmpeg not available: {e}")
        return None
    except Exception as e:
        logger.error(f"[AudioUtils] pydub decoding error: {e}")
        return None


def resample_to_16khz(
    audio_array: np.ndarray,
    original_sr: int,
) -> np.ndarray:
    """
    Resample audio to 16 kHz. No-op if already at 16 kHz.
    Tries torchaudio first, falls back to scipy.
    """
    if original_sr == TARGET_SAMPLE_RATE:
        return audio_array

    # Primary: torchaudio
    try:
        import torchaudio
        import torch
        tensor = torch.from_numpy(audio_array.copy()).float().unsqueeze(0)
        resampler = torchaudio.transforms.Resample(
            orig_freq=original_sr,
            new_freq=TARGET_SAMPLE_RATE,
        )
        resampled = resampler(tensor)
        return resampled.squeeze(0).numpy().astype(np.float32)
    except Exception as e:
        logger.warning(f"[AudioUtils] torchaudio resampling failed ({e}), trying scipy...")

    # Fallback: scipy
    try:
        import math
        from scipy.signal import resample_poly
        gcd = math.gcd(TARGET_SAMPLE_RATE, original_sr)
        up = TARGET_SAMPLE_RATE // gcd
        down = original_sr // gcd
        resampled = resample_poly(audio_array, up, down)
        return resampled.astype(np.float32)
    except Exception as e:
        logger.error(f"[AudioUtils] scipy resampling also failed ({e}). Returning original audio.")
        return audio_array.astype(np.float32)


def audio_to_tensor(audio_array: np.ndarray):
    """
    Convert a numpy float32 audio array into a PyTorch tensor.

    Args:
        audio_array: Numpy float32 audio array normalized to [-1.0, 1.0].

    Returns:
        1-D PyTorch float32 tensor ready for Wav2Vec2 input.
    """
    import torch
    return torch.from_numpy(audio_array).float()


def compute_audio_energy(audio_array: np.ndarray) -> float:
    """
    Compute the Root Mean Square (RMS) energy of the audio signal.

    Used by the FallbackCalculatedEngine to determine whether the
    audio frame contains actual speech or is silence/noise.

    Args:
        audio_array: Numpy float32 audio array.

    Returns:
        RMS energy as a float. Silence typically < 0.01, speech > 0.02.
    """
    if len(audio_array) == 0:
        return 0.0
    return float(np.sqrt(np.mean(audio_array ** 2)))


def compute_audio_duration_ms(audio_array: np.ndarray, sample_rate: int = TARGET_SAMPLE_RATE) -> float:
    """
    Compute the duration of the audio in milliseconds.

    Args:
        audio_array: Numpy float32 audio array.
        sample_rate: The sample rate of the audio.

    Returns:
        Duration in milliseconds.
    """
    if len(audio_array) == 0:
        return 0.0
    return (len(audio_array) / sample_rate) * 1000.0


def is_speech_present(
    audio_array: np.ndarray,
    energy_threshold: float = 0.015,
    min_duration_ms: float = 100.0,
    sample_rate: int = TARGET_SAMPLE_RATE,
) -> bool:
    """
    Simple Voice Activity Detection (VAD) based on energy and duration.

    Determines whether the audio frame likely contains speech rather
    than silence or background noise.

    Args:
        audio_array: Numpy float32 audio array.
        energy_threshold: Minimum RMS energy to consider as speech.
        min_duration_ms: Minimum duration in ms to consider as a valid utterance.
        sample_rate: Sample rate of the audio.

    Returns:
        True if the audio likely contains speech.
    """
    energy = compute_audio_energy(audio_array)
    duration = compute_audio_duration_ms(audio_array, sample_rate)
    return energy >= energy_threshold and duration >= min_duration_ms
