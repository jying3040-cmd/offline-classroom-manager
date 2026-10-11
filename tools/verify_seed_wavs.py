import os
import wave
from collections import Counter

root = os.path.join(os.path.dirname(__file__), '..', 'assets', 'tts_seed')
total = 0
sizes = []
per = {}
for g in sorted(os.listdir(root)):
    d = os.path.join(root, g)
    n = len([f for f in os.listdir(d) if f.endswith('.wav')])
    per[g] = n
    for f in os.listdir(d):
        p = os.path.join(d, f)
        total += 1
        sizes.append(os.path.getsize(p))

print('files:', total)
print('per-group:', per)
w = wave.open(os.path.join(root, 'g01', 'w01.wav'))
print('g01/w01: %d Hz, %d ch, %d bit, %.2fs' % (
    w.getframerate(), w.getnchannels(), w.getsampwidth() * 8,
    w.getnframes() / w.getframerate()))
w.close()
dup = Counter(sizes).most_common(3)
print('total MB: %.1f, duplicated sizes (top3):' % (sum(sizes) / 1048576), dup)
