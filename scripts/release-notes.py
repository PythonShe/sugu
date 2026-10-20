"""Turns a release's notes into one Markdown file per language, plus all of
them in one page for the release workflow's summary.

    python3 -I scripts/release-notes.py split <model-output> <notes-dir>
    python3 -I scripts/release-notes.py fallback <notes-dir>

`split` takes the notes the release workflow asked a model for: each
language under its own `<!-- lang -->` marker line, starting with its
overview heading. It exits 1, writing nothing, when the output is not in
that shape. `fallback` writes the notes for a release with nothing to say.
Both write en.md, ja.md, zh-Hans.md and zh-Hant.md (scripts/appcast.py,
scripts/publish-release.sh), and body.md.
"""

import re
import sys
from pathlib import Path

OVERVIEW = {"en": "### Overview", "ja": "### 概要", "zh-Hans": "### 概述", "zh-Hant": "### 概述"}
NAMES = {"ja": "日本語", "zh-Hans": "简体中文", "zh-Hant": "繁體中文"}
FALLBACK = {
    "en": ("This release contains minor improvements and stability fixes.", "### Bug Fixes", "Minor improvements and stability fixes"),
    "ja": ("このリリースには細かな改善と安定性の向上が含まれます。", "### 不具合の修正", "細かな改善と安定性の向上"),
    "zh-Hans": ("此版本包含细节改进与稳定性修复。", "### 问题修复", "细节改进与稳定性修复"),
    "zh-Hant": ("此版本包含細節改進與穩定性修正。", "### 問題修正", "細節改進與穩定性修正"),
}
MARKER = re.compile(r"^<!--\s*([A-Za-z-]+)\s*-->\s*$")


def split(text):
    notes, language = {}, None
    for line in text.strip().splitlines():
        match = MARKER.match(line)
        if match:
            language = match.group(1)
            if language not in OVERVIEW or language in notes:
                return None
            notes[language] = []
        elif language:
            notes[language].append(line)
        elif line.strip():
            return None
    notes = {language: "\n".join(lines).strip() for language, lines in notes.items()}
    if list(notes) != list(OVERVIEW):
        return None
    for language, text in notes.items():
        lines = text.splitlines()
        if not lines or lines[0].strip() != OVERVIEW[language] or len(lines) < 2:
            return None
    return notes


def fallback():
    return {
        language: f"{OVERVIEW[language]}\n{overview}\n\n{heading}\n- {bullet}"
        for language, (overview, heading, bullet) in FALLBACK.items()
    }


def write(notes, directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    for language, text in notes.items():
        (directory / f"{language}.md").write_text(text + "\n")
    body = [notes["en"]]
    for language, name in NAMES.items():
        body.append(f"<details>\n<summary>{name}</summary>\n\n{notes[language]}\n\n</details>")
    (directory / "body.md").write_text("\n\n".join(body) + "\n")


def main(arguments):
    if arguments[:1] == ["split"] and len(arguments) == 3:
        notes = split(Path(arguments[1]).read_text())
        if notes is None:
            sys.exit(1)
        write(notes, arguments[2])
    elif arguments[:1] == ["fallback"] and len(arguments) == 2:
        write(fallback(), arguments[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
