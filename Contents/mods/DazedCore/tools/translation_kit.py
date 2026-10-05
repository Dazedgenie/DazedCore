#!/usr/bin/env python3
"""Translation kit for the Dazed Utilities mods.

    python3 translation_kit.py start <mod folder> <LANG>   # copy every missing EN key into Translate/<LANG>/
    python3 translation_kit.py check <mod folder> [LANG]   # report missing, extra and broken keys

A started language keeps any line already translated and adds the missing ones in English, so a translator
only ever edits the JSON files. "check" also catches placeholders (%1, {1}, %%) that went missing.
"""
import json, re, sys
from pathlib import Path

PLACEHOLDER = re.compile(r"%\d+|\{\d+\}|%%|<[A-Z]+>")


def tr_root(mod):
    return Path(mod) / "common/media/lua/shared/Translate"


def load(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}


def placeholders(text):
    return sorted(PLACEHOLDER.findall(text or ""))


def start(mod, lang):
    root = tr_root(mod)
    added = 0
    for en_file in sorted((root / "EN").glob("*.json")):
        en = load(en_file)
        out_file = root / lang / en_file.name
        cur = load(out_file)
        merged = {k: cur.get(k, v) for k, v in en.items()}
        added += sum(1 for k in en if k not in cur)
        out_file.parent.mkdir(parents=True, exist_ok=True)
        out_file.write_text(json.dumps(merged, indent=4, ensure_ascii=False) + "\n", encoding="utf-8")
    print("%s/%s: %d keys added in English for translating" % (Path(mod).name, lang, added))


def check(mod, only=None):
    root = tr_root(mod)
    langs = [only] if only else sorted(p.name for p in root.iterdir() if p.is_dir() and p.name != "EN")
    bad = 0
    for lang in langs:
        missing = extra = broken = same = 0
        for en_file in sorted((root / "EN").glob("*.json")):
            en, cur = load(en_file), load(root / lang / en_file.name)
            for k, v in en.items():
                if k not in cur:
                    missing += 1
                    continue
                if placeholders(v) != placeholders(cur[k]):
                    broken += 1
                    print("  %s %s: placeholders differ: %r" % (lang, k, cur[k][:80]))
                if cur[k] == v:
                    same += 1
            extra += sum(1 for k in cur if k not in en)
        print("%s/%s: %d missing, %d extra, %d broken placeholders, %d still in English" % (
            Path(mod).name, lang, missing, extra, broken, same))
        bad += broken
    return bad


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("start", "check"):
        print(__doc__)
        sys.exit(2)
    if sys.argv[1] == "start":
        start(sys.argv[2], sys.argv[3])
    else:
        sys.exit(1 if check(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None) else 0)
