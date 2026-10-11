import re
import os

ROOT = os.path.join(os.path.dirname(__file__), '..')
SRC = os.path.join(ROOT, 'lib', 'data', 'textbook_words.dart')
OUT = os.path.join(ROOT, 'tools', 'tts_seed_words.txt')

src = open(SRC, encoding='utf-8').read()
groups = re.findall(r"TextbookGroup\('([^']+)', '([^']+)', \[(.*?)\]\)", src, re.S)
lines = []
words_total = 0
for title, dir_, body in groups:
    words = re.findall(r"'([^']+)'", body)
    words_total += len(words)
    for i, w in enumerate(words):
        lines.append(f"{dir_}|w{i + 1:02d}|{w}")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, 'w', encoding='utf-8', newline='\r\n') as f:
    f.write('\n'.join(lines))
print(f'{len(groups)} groups, {words_total} words -> {OUT}')
