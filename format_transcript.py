import json

with open('/Users/jackwallner/baseball/transcript.json', 'r') as f:
    data = json.load(f)

with open('/Users/jackwallner/baseball/transcript.txt', 'w') as f:
    for segment in data:
        start_time = segment['start']
        end_time = segment['end']
        text = segment['text']
        f.write(f"[{start_time:.2f} - {end_time:.2f}] {text}\n")
