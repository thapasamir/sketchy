#!/usr/bin/env python3
"""Validate Sketchy word files.

usage: validate_words.py --category "Animals" --expect 120 --mix 80,32,8 file1.json [file2.json ...]
Exit code 0 = clean, 1 = problems (printed). Several files are checked together (for duplicates).
"""
import argparse, json, re, sys, collections

p = argparse.ArgumentParser()
p.add_argument("--category", required=True)
p.add_argument("--expect", type=int, required=True)
p.add_argument("--mix", default=None, help="easy,medium,hard targets; each must be within +-4")
p.add_argument("--skip", action="append", default=[], help="file whose words must NOT appear (repeatable)")
p.add_argument("files", nargs="+")
a = p.parse_args()

errors, entries = [], []
TOKEN = re.compile(r"[a-z]+")
OK_TEXT = re.compile(r"^[A-Za-z][A-Za-z '\-]*$")

for f in a.files:
    try:
        data = json.load(open(f))
    except Exception as e:
        errors.append(f"{f}: not valid JSON ({e})"); continue
    if not isinstance(data, list):
        errors.append(f"{f}: top level must be an array"); continue
    for i, e in enumerate(data):
        entries.append((f, i, e))

seen = {}
for f, i, e in entries:
    where = f"{f.split('/')[-1]}[{i}]"
    if not isinstance(e, dict) or set(e) != {"category", "word", "difficulty", "hints"}:
        errors.append(f"{where}: keys must be exactly category, word, difficulty, hints"); continue
    w, hints = e["word"], e["hints"]
    if e["category"] != a.category:
        errors.append(f"{where}: category {e['category']!r} != {a.category!r}")
    if not isinstance(w, str) or not OK_TEXT.match(w) or len(w) > 24:
        errors.append(f"{where}: bad word {w!r}"); continue
    parts = w.split()
    if not 1 <= len(parts) <= 2:
        errors.append(f"{where}: word {w!r} must be 1-2 words")
    if any(not t[0].isupper() for t in parts):
        errors.append(f"{where}: word {w!r} must be Title Case")
    if e["difficulty"] not in ("easy", "medium", "hard"):
        errors.append(f"{where}: bad difficulty {e['difficulty']!r}")
    key = w.lower()
    if key in seen:
        errors.append(f"{where}: duplicate word {w!r} (also {seen[key]})")
    seen[key] = where
    if not isinstance(hints, list) or len(hints) != 3 or not all(isinstance(h, str) for h in hints):
        errors.append(f"{where} {w}: hints must be exactly 3 strings"); continue
    if len({h.lower() for h in hints}) != 3:
        errors.append(f"{where} {w}: hints must be 3 different hints")
    wtoks = [t for t in TOKEN.findall(key) if len(t) >= 3]
    for h in hints:
        if h != h.lower():
            errors.append(f"{where} {w}: hint {h!r} must be lowercase")
        if not OK_TEXT.match(h) or not 1 <= len(h.split()) <= 3 or len(h) > 24:
            errors.append(f"{where} {w}: bad hint {h!r} (1-3 words, letters only)")
        hl = h.lower()
        htoks = TOKEN.findall(hl)
        if re.search(r'\b' + re.escape(key) + r'\b', hl):
            errors.append(f"{where} {w}: hint {h!r} contains the word")
        for t in wtoks:
            if any(ht.startswith(t) for ht in htoks):
                errors.append(f"{where} {w}: hint {h!r} contains/echoes {t!r}")
        for ht in htoks:
            if len(ht) >= 4 and ht in key:
                errors.append(f"{where} {w}: hint {h!r} is part of the word")

for sf in a.skip:
    try:
        prev = {x["word"].lower() for x in json.load(open(sf))}
    except Exception as ex:
        errors.append(f"{sf}: cannot read ({ex})"); continue
    for w, where in seen.items():
        if w in prev:
            errors.append(f"{where}: {w!r} already used in {sf.split('/')[-1]}")

if len(entries) != a.expect:
    errors.append(f"expected {a.expect} entries, found {len(entries)}")
if a.mix:
    want = dict(zip(("easy", "medium", "hard"), map(int, a.mix.split(","))))
    got = collections.Counter(e["difficulty"] for _, _, e in entries if isinstance(e, dict))
    for k, v in want.items():
        if abs(got[k] - v) > 4:
            errors.append(f"difficulty mix: {k} is {got[k]}, target {v} (+-4)")

if errors:
    print(f"{len(errors)} PROBLEM(S):")
    for e in errors: print(" -", e)
    sys.exit(1)
print(f"OK: {len(entries)} entries, no problems")
