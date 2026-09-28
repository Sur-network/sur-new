# Logical parity of contracts/ (English) and contracts-fa/ (Persian): identical after stripping comments and whitespace.
import re, os, sys
def norm(s):
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S); s = re.sub(r'//[^\n]*', '', s); return re.sub(r'\s+', '', s)
bad = []; n = 0
for root, _, files in os.walk('contracts'):
    for f in files:
        if f.endswith('.sol'):
            en = os.path.join(root, f); fa = en.replace('contracts', 'contracts-fa', 1); n += 1
            if norm(open(en, encoding='utf-8').read()) != norm(open(fa, encoding='utf-8').read()): bad.append(en)
print(f'{n} pairs checked; logically different: {bad or "none"}'); sys.exit(1 if bad else 0)
