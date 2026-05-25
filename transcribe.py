import whisper
import json
import warnings
warnings.filterwarnings("ignore")

model = whisper.load_model("base")
result = model.transcribe("/Users/jackwallner/baseball/video_audio.mp3")

with open("/Users/jackwallner/baseball/transcript.json", "w") as f:
    json.dump(result["segments"], f, indent=2)

print("Transcription complete.")
