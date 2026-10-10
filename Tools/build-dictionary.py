#!/usr/bin/env python3
"""Builds jmdict.sqlite, the JMdict database word details show meanings from.

The data is JMdict from the Electronic Dictionary Research and Development
Group (https://www.edrdg.org/jmdict/j_jmdict.html), licensed CC BY-SA 4.0, in
the JSON form published by jmdict-simplified
(https://github.com/scriptin/jmdict-simplified).

Usage (from the repository root):
  curl -L -o /tmp/jmdict.tgz <jmdict-eng-*.json.tgz URL from the latest release>
  tar xzf /tmp/jmdict.tgz -C /tmp
  python3 Tools/build-dictionary.py /tmp/jmdict-eng-*.json jmdict.sqlite

Options:
  --common-only   Only words marked common: about 23,000 entries and 4 MB
                  instead of 219,000 entries and 35 MB, but literary words
                  such as 吾輩 are missing.
  --senses N      Senses kept per entry (default 3).
  --glosses N     English glosses kept per sense (default 3).
"""
import argparse
import json
import os
import sqlite3

parser = argparse.ArgumentParser()
parser.add_argument("source")
parser.add_argument("output")
parser.add_argument("--common-only", action="store_true")
parser.add_argument("--senses", type=int, default=3)
parser.add_argument("--glosses", type=int, default=3)
args = parser.parse_args()

source = json.load(open(args.source, encoding="utf-8"))
if os.path.exists(args.output):
    os.remove(args.output)
db = sqlite3.connect(args.output)
db.executescript("""
CREATE TABLE entries(id INTEGER PRIMARY KEY, common INTEGER NOT NULL, usually_kana INTEGER NOT NULL, kanji TEXT NOT NULL, kana TEXT NOT NULL, senses TEXT NOT NULL);
CREATE TABLE forms(text TEXT NOT NULL, entry INTEGER NOT NULL, common INTEGER NOT NULL, PRIMARY KEY(text, entry)) WITHOUT ROWID;
CREATE TABLE tags(code TEXT PRIMARY KEY, description TEXT NOT NULL) WITHOUT ROWID;
CREATE TABLE info(key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID;
""")

# Irregular, outdated, rare, and search-only spellings stay searchable but
# aren't shown.
hidden_kanji = {"sK", "iK", "oK", "rK"}
hidden_kana = {"sk", "ik", "ok", "rk"}
used_tags = set()
count = 0
for word in source["words"]:
    forms = word["kanji"] + word["kana"]
    common = int(any(form["common"] for form in forms))
    if args.common_only and not common:
        continue
    kanji = [k for k in word["kanji"] if not hidden_kanji & set(k["tags"])] or word["kanji"]
    kana = [k for k in word["kana"] if not hidden_kana & set(k["tags"])] or word["kana"]
    senses = []
    for sense in word["sense"][: args.senses]:
        glosses = [g["text"] for g in sense["gloss"] if g["lang"] == "eng"][: args.glosses]
        if glosses:
            used_tags.update(sense["partOfSpeech"])
            senses.append([sense["partOfSpeech"], glosses])
    if not senses:
        continue
    # How many senses are usually written in kana (all of 居る's, as いる,
    # but one of 要る's), to prefer such words when looking up kana.
    usually_kana = sum("uk" in sense["misc"] for sense in word["sense"][: args.senses])
    count += 1
    db.execute(
        "INSERT INTO entries VALUES (?, ?, ?, ?, ?, ?)",
        (
            int(word["id"]),
            common,
            usually_kana,
            "、".join(k["text"] for k in kanji[:3]),
            "、".join(k["text"] for k in kana[:3]),
            json.dumps(senses, ensure_ascii=False, separators=(",", ":")),
        ),
    )
    for form in forms:
        db.execute("INSERT OR IGNORE INTO forms VALUES (?, ?, ?)", (form["text"], int(word["id"]), int(form["common"])))

for code, description in source["tags"].items():
    if code in used_tags:
        db.execute("INSERT INTO tags VALUES (?, ?)", (code, description))
db.execute("INSERT INTO info VALUES ('version', ?)", (source["version"],))
db.execute("INSERT INTO info VALUES ('date', ?)", (source["dictDate"],))
db.commit()
db.execute("VACUUM")
db.close()
print(f"Wrote {count} entries to {args.output} ({os.path.getsize(args.output) / 1e6:.1f} MB)")
