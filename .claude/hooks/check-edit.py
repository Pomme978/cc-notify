#!/usr/bin/env python3
"""Hook PostToolUse (Edit/Write) : refuse une écriture qui introduit une violation de convention.

Moteur seul, aucune règle en dur. La liste vit dans rules.json, section `edit`.
Détail et raisonnement : docs/hooks.md
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

payload = json.load(sys.stdin)
path = payload.get("tool_input", {}).get("file_path", "")

if not path or not Path(path).is_file():
    sys.exit(0)


def project_slug():
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    return re.sub(r"[^a-z0-9]+", "-", Path(root).name.lower()).strip("-") or "projet"


session = payload.get("session_id", "")
if session:
    ledger = Path(tempfile.gettempdir()) / f"{project_slug()}-touched-{session}"
    with ledger.open("a", encoding="utf-8") as fh:
        fh.write(path + "\n")

try:
    root = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, timeout=5,
        cwd=Path(path).parent,
    ).stdout.strip()
    rel = str(Path(path).relative_to(root))
except (subprocess.SubprocessError, ValueError, OSError):
    sys.exit(0)

try:
    rules = json.loads(
        (Path(root) / ".claude" / "hooks" / "rules.json").read_text(encoding="utf-8")
    ).get("edit", [])
except (OSError, ValueError):
    sys.exit(0)

if not rules:
    sys.exit(0)

suffix = Path(path).suffix
try:
    source = Path(path).read_text(encoding="utf-8")
except (OSError, UnicodeDecodeError):
    sys.exit(0)

committed = subprocess.run(
    ["git", "show", f"HEAD:{rel}"],
    capture_output=True, text=True, timeout=10, cwd=root,
)
is_new = committed.returncode != 0
previous = set() if is_new else set(committed.stdout.split("\n"))

lines = source.split("\n")
# Cliquet : une ligne n'est jugée que si elle n'existait pas dans la version committée.
judged = [(i, ln) for i, ln in enumerate(lines, 1) if ln.strip() and ln not in previous]

violations = []

for rule in rules:
    extensions = rule.get("extensions")
    if extensions and suffix not in extensions:
        continue
    paths = rule.get("paths")
    if paths and not any(p in rel for p in paths):
        continue
    if any(s in rel for s in rule.get("skip", [])):
        continue
    if rule.get("onlyNewFiles") and not is_new:
        continue

    prefix = rule.get("requirePrefix")
    if prefix:
        # Les directives `'use client';` précèdent légitimement l'en-tête.
        head = re.sub(r"^(?:\s*['\"]use [a-z]+['\"];)*\s*", "", source)
        if not head.startswith(prefix):
            violations.append(f"{rel}:1 : {rule['message']}")
        continue

    try:
        pattern = re.compile(rule["pattern"])
    except (KeyError, re.error):
        continue

    for number, line in judged:
        hit = pattern.search(line)
        if hit:
            violations.append(
                f"{rel}:{number} : {rule['message']} (trouvé : `{hit.group(0)[:60]}`)"
            )
            break

if violations:
    print(json.dumps({
        "decision": "block",
        "reason": "Écriture refusée, elle introduit des violations des conventions du projet :\n"
                  + "\n".join(f"  - {v}" for v in violations)
                  + "\n\nCorriger puis réécrire. Détail : `CLAUDE.md` et `.claude/rules/`.",
    }))

sys.exit(0)
