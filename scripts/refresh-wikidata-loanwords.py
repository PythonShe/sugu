#!/usr/bin/env python3
"""Regenerates scripts/data/wikidata-katakana.tsv.gz: foreign spellings and
their katakana from Wikidata labels (CC0).

Wikidata's dumps are over 100 GB and no public query endpoint can be pinned,
so the extract is tracked, and this script is run by hand when refreshing the
foreign-word data for a release. It reads labels through QLever's endpoint,
keeps them in <cache>, and needs nothing but Python's standard library.

usage: refresh-wikidata-loanwords.py [--cache <dir>] [--no-fetch]

Columns: spelling, katakana, the item's sitelinks, and how many labels agreed
when the pair was taken out of a longer name (0 for a whole label).
"""
import argparse
import collections
import gzip
import os
import re
import sys
import time
import unicodedata
import urllib.parse
import urllib.request

ENDPOINT = "https://qlever.dev/api/wikidata"
LANGUAGES = ["en", "mul", "de", "fr", "es", "it", "pt", "nl", "sv", "pl", "tr"]
KATAKANA_LABEL = (
    '?i rdfs:label ?ja . FILTER(LANG(?ja)="ja") '
    'FILTER(REGEX(STR(?ja),"^[ァ-ヺーヽヾ・=＝ ]+$")) __RESUME__ '
)
PREFIXES = """PREFIX wikibase: <http://wikiba.se/ontology#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
"""
# Whole labels below this many sitelinks are mostly obscure people, whose
# full names no one types as one word.
WHOLE_LABEL_SITELINKS = 50
# A pair seen this often in longer names is a reading, not a coincidence.
TOKEN_LABELS = 3
SOUNDS_ALIKE = 0.6


def fetch(path, body, select):
    """Pages through a query whose result streams sorted by ?i."""
    last, total = None, 0
    with open(path, "w", encoding="utf-8") as out:
        while True:
            resume = f"FILTER(?i > <{last}>)" if last else ""
            query = PREFIXES + f'SELECT {select} WHERE {{ {body.replace("__RESUME__", resume)} }}'
            url = ENDPOINT + "?" + urllib.parse.urlencode({"query": query})
            request = urllib.request.Request(url, headers={"Accept": "text/tab-separated-values", "User-Agent": "sugu-build"})
            data = ""
            for _ in range(5):
                try:
                    data = urllib.request.urlopen(request, timeout=120).read().decode("utf-8", "replace")
                    break
                except OSError as error:
                    print("retrying:", error, file=sys.stderr)
                    time.sleep(10)
            timed_out = "Operation timed out" in data[-200:]
            rows = [row for row in data.split("\n")[1:] if row.startswith("<http")]
            if timed_out and rows:
                rows = rows[:-1]
            if not rows:
                return total
            out.write("\n".join(rows) + "\n")
            out.flush()
            total += len(rows)
            last = rows[-1].split("\t")[0][1:-1]
            print(os.path.basename(path), total, flush=True)
            if not timed_out:
                return total
            time.sleep(3)


def fetch_all(cache):
    os.makedirs(cache, exist_ok=True)
    for language in LANGUAGES:
        body = KATAKANA_LABEL + f'?i rdfs:label ?x . FILTER(LANG(?x)="{language}")'
        fetch(os.path.join(cache, f"lab_{language}.tsv"), body, "?i ?ja ?x")
    fetch(os.path.join(cache, "sitelinks.tsv"), KATAKANA_LABEL + "?i wikibase:sitelinks ?s", "?i ?s")


SPECIAL = {"ß": "ss", "ẞ": "ss", "æ": "ae", "Æ": "ae", "œ": "oe", "Œ": "oe", "ø": "o", "Ø": "o", "ð": "d", "Ð": "d",
           "þ": "th", "Þ": "th", "ł": "l", "Ł": "l", "đ": "d", "Đ": "d", "ı": "i", "ħ": "h", "ŋ": "n"}
KANA_ROMAJI = dict(zip(
    "アイウエオカキクケコガギグゲゴサシスセソザジズゼゾタチツテトダヂヅデドナニヌネノハヒフヘホバビブベボパピプペポマミムメモヤユヨラリルレロワヲンヴァィゥェォャュョ",
    ("a i u e o ka ki ku ke ko ga gi gu ge go sa shi su se so za ji zu ze zo ta chi tsu te to da ji zu de do "
     "na ni nu ne no ha hi fu he ho ba bi bu be bo pa pi pu pe po ma mi mu me mo ya yu yo "
     "ra ri ru re ro wa o n vu a i u e o ya yu yo").split(),
))
CONSONANT_CLASSES = {"r": "R", "l": "R", "b": "B", "v": "B", "w": "B", "f": "H", "h": "H", "k": "K", "c": "K", "q": "K",
                     "g": "K", "x": "K", "s": "S", "z": "S", "j": "S", "t": "T", "d": "T", "m": "M", "n": "N", "p": "P"}
LATIN_LABEL = re.compile(r"^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .'’\-]*$")
LITERAL = re.compile(r'^"(.*)"@[\w-]+$')
PARTICLES = {"de", "van", "von", "der", "da", "di", "del", "du", "la", "le", "el", "al", "bin", "ibn", "of", "the"}


def fold(text):
    """As LoanwordSpelling.key in Swift, which applies again when building."""
    text = "".join(SPECIAL.get(c, c) for c in text)
    text = "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c)).lower()
    return re.sub(r"[\s\-'’ʻʼ.‐·・&_]", "", text)


def consonants(text):
    for old, new in (("ph", "f"), ("ck", "k"), ("qu", "k"), ("sch", "s"), ("sh", "s"), ("ch", "s"),
                     ("th", "s"), ("ts", "s"), ("tz", "s"), ("dg", "j")):
        text = text.replace(old, new)
    out = []
    for character in text:
        group = CONSONANT_CLASSES.get(character)
        if group and (not out or out[-1] != group):
            out.append(group)
    return out


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        current = [i]
        for j, y in enumerate(b, 1):
            current.append(min(row[j] + 1, current[j - 1] + 1, row[j - 1] + (x != y)))
        row = current
    return row[-1]


def sounds_alike(spelling, kana):
    """Keeps transliterations from translations, by coarse consonants."""
    a = consonants(fold(spelling))
    b = consonants("".join(KANA_ROMAJI.get(c, "") for c in kana))
    return 1.0 if not a and not b else 1 - distance(a, b) / max(len(a), len(b), 1)


def literal(text):
    match = LITERAL.match(text)
    return match.group(1).replace('\\"', '"').replace("\\\\", "\\") if match else None


def extract(cache):
    sitelinks = {}
    with open(os.path.join(cache, "sitelinks.tsv"), encoding="utf-8") as lines:
        for line in lines:
            columns = line.rstrip("\n").split("\t")
            number = re.search(r"\d+", columns[1]) if len(columns) == 2 else None
            if number:
                sitelinks[columns[0]] = int(number.group())
    whole = collections.defaultdict(int)
    tokens = collections.defaultdict(lambda: [0, 0])
    for language in LANGUAGES:
        with open(os.path.join(cache, f"lab_{language}.tsv"), encoding="utf-8") as lines:
            for line in lines:
                columns = line.rstrip("\n").split("\t")
                if len(columns) != 3 or not columns[0].rsplit("/", 1)[-1].startswith("Q"):
                    continue
                japanese, label = literal(columns[1]), literal(columns[2])
                if not japanese or not label or not LATIN_LABEL.match(label):
                    continue
                links = sitelinks.get(columns[0], 0)
                kana = re.sub(r"[・=＝ ]", "", japanese)
                key = fold(label)
                if sounds_alike(label, kana) >= SOUNDS_ALIKE:
                    whole[(key, kana)] = max(whole[(key, kana)], links)
                parts = [part for part in re.split(r"[・=＝ ]", japanese) if part]
                words = label.split()
                if len(words) != len(parts):
                    words = [word for word in words if word.lower() not in PARTICLES]
                if len(parts) >= 2 and len(words) == len(parts):
                    for word, part in zip(words, parts):
                        if len(word) >= 2 and sounds_alike(word, part) >= SOUNDS_ALIKE:
                            entry = tokens[(fold(word), part)]
                            entry[0] += 1
                            entry[1] = max(entry[1], links)
    rows = [(key, kana, links, 0) for (key, kana), links in whole.items() if links >= WHOLE_LABEL_SITELINKS]
    rows += [(key, kana, entry[1], entry[0]) for (key, kana), entry in tokens.items() if entry[0] >= TOKEN_LABELS]
    return sorted(rows)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", default=os.path.join(root, ".vendor", "wikidata-labels"))
    parser.add_argument("--no-fetch", action="store_true")
    arguments = parser.parse_args()
    if not arguments.no_fetch:
        fetch_all(arguments.cache)
    rows = extract(arguments.cache)
    text = "".join(f"{key}\t{kana}\t{links}\t{labels}\n" for key, kana, links, labels in rows)
    # No timestamp, so the same labels give the same bytes.
    with open(os.path.join(root, "scripts", "data", "wikidata-katakana.tsv.gz"), "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", compresslevel=9, fileobj=raw, mtime=0) as out:
            out.write(text.encode("utf-8"))
    print(len(rows), "pairs")


main()
