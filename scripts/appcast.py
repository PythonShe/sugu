"""Writes Sugu's appcast: one item, for the release in release.json.

    python3 -I scripts/appcast.py dist/release.json dist/appcast.xml [notes-dir]

notes-dir holds the release notes as Markdown, one file per language
(en.md, ja.md, zh-Hans.md, zh-Hant.md); each becomes a <description> that
Sparkle shows in the user's language. scripts/release.sh signs the result
(the app requires a signed feed), so it is never edited afterwards.
"""

import json
import sys
from email.utils import formatdate
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

LANGUAGES = ["en", "ja", "zh-Hans", "zh-Hant"]


def cdata(text):
    return "<![CDATA[" + text.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def main(release_path, output_path, notes_dir=None):
    release = json.loads(Path(release_path).read_text())
    descriptions = []
    if notes_dir:
        for language in LANGUAGES:
            notes = (Path(notes_dir) / f"{language}.md").read_text().strip()
            descriptions.append(
                f'      <description sparkle:format="markdown" xml:lang="{language}">{cdata(notes)}</description>'
            )
    version = escape(release["version"])
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">',
        "  <channel>",
        "    <title>Sugu</title>",
        "    <item>",
        f"      <title>{version}</title>",
        f"      <pubDate>{formatdate(usegmt=True)}</pubDate>",
        f"      <sparkle:version>{escape(release['build'])}</sparkle:version>",
        f"      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>",
        f"      <sparkle:minimumSystemVersion>{escape(release['minimumSystemVersion'])}</sparkle:minimumSystemVersion>",
        *descriptions,
        f"      <enclosure url={quoteattr(release['url'])} length=\"{int(release['length'])}\""
        f" type=\"application/octet-stream\" sparkle:edSignature={quoteattr(release['edSignature'])}/>",
        "    </item>",
        "  </channel>",
        "</rss>",
    ]
    Path(output_path).write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    main(*sys.argv[1:])
