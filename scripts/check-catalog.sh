#!/bin/bash
#
# check-catalog.sh — check every Discover catalog entry against Homebrew's live
# API. Flags tokens that were renamed, removed, deprecated or disabled, or that
# are listed with the wrong type. Entries with a `tap:` are skipped (not in core).
# Run before a release:  make check-catalog
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL https://formulae.brew.sh/api/cask.json    -o "$TMP/cask.json"
curl -fsSL https://formulae.brew.sh/api/formula.json -o "$TMP/formula.json"
grep -E '^\s*\.init\("' "$REPO/BrewDock/DiscoverPackage.swift" | grep -v 'tap:' \
  | sed -E 's/^[[:space:]]*\.init\("([^"]+)".*\.(cask|formula)[,)].*/\2 \1/' > "$TMP/catalog.txt"

python3 -I - "$TMP" <<'EOF'
import json, sys
d = sys.argv[1]
casks = {c["token"]: c for c in json.load(open(f"{d}/cask.json"))}
formulae = {f["name"]: f for f in json.load(open(f"{d}/formula.json"))}
cask_renames = {o: c["token"] for c in casks.values() for o in c.get("old_tokens", [])}
formula_alias = {a: f["name"] for f in formulae.values() for a in f.get("aliases", []) + f.get("oldnames", [])}
problems = 0
for line in open(f"{d}/catalog.txt"):
    kind, name = line.split()
    entry = (casks if kind == "cask" else formulae).get(name)
    note = None
    if kind == "formula" and entry is None and name in formula_alias:
        continue  # alias (e.g. python -> python@3.x): installs fine, matched by prefix
    if entry is None:
        other = formulae if kind == "cask" else casks
        note = ("renamed to " + cask_renames[name]) if name in cask_renames else \
               ("is a " + ("formula" if kind == "cask" else "cask")) if name in other else "not found"
    elif entry.get("disabled"):
        note = "disabled: " + str(entry.get("disable_reason"))
    elif entry.get("deprecated"):
        note = "deprecated: " + str(entry.get("deprecation_reason"))
    if note:
        problems += 1
        print(f"{kind:7} {name:24} {note}")
print(f"{problems} problem(s)")
sys.exit(1 if problems else 0)
EOF
