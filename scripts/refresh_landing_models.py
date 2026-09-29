#!/usr/bin/env python3
"""Refresh the static model IDs in docs/index.html from OpenRouter's public list.

The landing page's model picker mock fetches the same list in the browser;
this script keeps the no-JS fallback text current. Same rule as the page
script: newest three text models per provider family (claude-, gpt-,
gemini-), skipping small or special variants, treating "-pro" as the same
release as its base model.

Run by .github/workflows/refresh-landing-models.yml once a week, or by hand:

    python3 scripts/refresh_landing_models.py          # rewrite docs/index.html
    python3 scripts/refresh_landing_models.py --check  # exit 1 if it would change

Exit code 0 when the file is current or was updated, 1 on --check with drift,
2 when the list could not be fetched (the file is left untouched).
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

PAGE = Path(__file__).resolve().parent.parent / "docs" / "index.html"
API = "https://openrouter.ai/api/v1/models"
# Whole segments only ("gpt-5-mini" yes, "gemini-3.8-flash" no).
SKIP = re.compile(r"(^|[-._])(haiku|mini|nano|lite|guard|image|audio|tts|realtime|embed|embedding|search|transcribe|moderation|codex|thinking|small|oss)([-._]|$)")
SLOT = re.compile(r'(<div class="mviz-sub" data-model-ids="([a-z0-9-]+/[a-z0-9-]+)">)(.*?)(</div>)')


def newest(models, prefix, limit=3):
    """prefix is provider plus family, e.g. "google/gemini-"."""
    picks = []
    for m in models:
        mid = m.get("id", "")
        if not mid.startswith(prefix) or ":" in mid:
            continue
        out = (m.get("architecture") or {}).get("output_modalities") or ["text"]
        if "text" not in out:
            continue
        slug = mid.split("/", 1)[1]
        if SKIP.search(slug):
            continue
        picks.append((slug, int(m.get("created") or 0)))
    have = {slug for slug, _ in picks}
    picks = [p for p in picks if not (p[0].endswith("-pro") and p[0][:-4] in have)]
    picks.sort(key=lambda p: (-p[1], p[0]))
    return " · ".join(slug for slug, _ in picks[:limit])


def main():
    check = "--check" in sys.argv
    try:
        with urllib.request.urlopen(API, timeout=30) as resp:
            models = json.load(resp).get("data", [])
    except Exception as exc:  # network or schema trouble: leave the page alone
        print(f"could not fetch {API}: {exc}", file=sys.stderr)
        return 2
    if not models:
        print("empty model list, leaving the page alone", file=sys.stderr)
        return 2

    html = PAGE.read_text(encoding="utf-8")
    changes = []

    def swap(match):
        prefix, current = match.group(2), match.group(3)
        fresh = newest(models, prefix)
        if not fresh:
            print(f"warning: no {prefix} models matched, keeping the current text", file=sys.stderr)
            fresh = current
        if fresh != current:
            changes.append(f"{prefix}: {current} -> {fresh}")
        return match.group(1) + fresh + match.group(4)

    updated = SLOT.sub(swap, html)
    if not changes:
        print("model IDs are current")
        return 0
    for line in changes:
        print(line)
    if check:
        return 1
    PAGE.write_text(updated, encoding="utf-8")
    print(f"updated {PAGE.relative_to(PAGE.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
