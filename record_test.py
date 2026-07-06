import sounddevice as sd
from scipy.io.wavfile import write
import time

fs = 16000  # 16kHz to match your model
seconds = 6 # Record for 6 seconds

print("🎤 Get ready to recite...")
time.sleep(1)
print("🔴 RECORDING NOW (Speak into your microphone) - 6 Seconds!")

# Record audio
myrecording = sd.rec(int(seconds * fs), samplerate=fs, channels=1, dtype='float32')
sd.wait()  # Wait until recording is finished

# Save as WAV file
write('test_mistake.wav', fs, myrecording)
print("✅ Saved to 'test_mistake.wav'")
print("\nNow run this to test your recording:")
print("python eval_recitation.py test_mistake.wav --model checkpoints/tajweed_run/final")
