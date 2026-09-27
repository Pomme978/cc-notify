#!/usr/bin/env python3
"""Traduit un évènement de hook Codex vers le format attendu par les hooks de `.claude/hooks/`.

Les deux harnais partagent les noms de champs (`tool_name`, `tool_input`, `hook_event_name`) et la
forme du refus, mais pas la façon de désigner un fichier : l'outil `apply_patch` de Codex ne passe
aucun chemin, seulement le texte brut du patch sous `tool_input.command`. Les chemins s'en
extraient, et chacun est soumis au hook comme un `file_path`.

Usage : adapt.py <chemin du hook .claude à appeler>
"""

import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

COMMAND_KEYS = ("command", "cmd", "shell_command", "script")
PATH_KEYS = ("file_path", "path", "filename", "file")
PATCH_PATH = re.compile(
    r"^\*\*\*\s+(?:Add|Update|Delete)\s+File:\s*(.+?)\s*$",
    re.MULTILINE,
)
PATCH_MOVE = re.compile(r"^\*\*\*\s+Move\s+to:\s*(.+?)\s*$", re.MULTILINE)

payload = json.load(sys.stdin)
tool_input = payload.get("tool_input") or {}

if isinstance(tool_input, str):
    try:
        tool_input = json.loads(tool_input)
    except ValueError:
        tool_input = {"command": tool_input}

normalized = dict(tool_input)

for key in COMMAND_KEYS:
    value = tool_input.get(key)
    if isinstance(value, list):
        value = shlex.join(str(part) for part in value)
    if isinstance(value, str) and value.strip():
        normalized["command"] = value
        break

paths = []
for key in PATH_KEYS:
    value = tool_input.get(key)
    if isinstance(value, str) and value.strip():
        paths.append(value)

command = normalized.get("command", "")
if payload.get("tool_name") == "apply_patch" or "*** Begin Patch" in command:
    patch = normalized.pop("command", "")
    paths.extend(PATCH_PATH.findall(patch))
    paths.extend(PATCH_MOVE.findall(patch))

changes = tool_input.get("changes")
if isinstance(changes, dict):
    paths.extend(str(k) for k in changes)
elif isinstance(changes, list):
    for change in changes:
        if isinstance(change, dict):
            for key in PATH_KEYS:
                if isinstance(change.get(key), str):
                    paths.append(change[key])
                    break
        elif isinstance(change, str):
            paths.append(change)

target = Path(sys.argv[1])
if not target.is_file():
    sys.exit(0)


def run(inner: dict) -> tuple[int, str, str]:
    inner_payload = dict(payload)
    inner_payload["tool_input"] = inner
    done = subprocess.run(
        ["python3", str(target)],
        input=json.dumps(inner_payload),
        capture_output=True,
        text=True,
    )
    return done.returncode, done.stdout.strip(), done.stderr.strip()


def refuse(reason: str) -> None:
    event = payload.get("hook_event_name", "PreToolUse")
    if event == "PreToolUse":
        print(
            json.dumps(
                {
                    "hookSpecificOutput": {
                        "hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": reason,
                    }
                }
            )
        )
    else:
        print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(0)


root = Path(payload.get("cwd") or tool_input.get("workdir") or Path.cwd())

inputs = [normalized] if "command" in normalized else []
inputs += [
    {**normalized, "file_path": str(Path(p) if Path(p).is_absolute() else root / p)}
    for p in dict.fromkeys(paths)
]

if not inputs:
    sys.exit(0)

for candidate in inputs:
    code, out, err = run(candidate)

    if code == 2 and err:
        refuse(err)

    if out:
        try:
            decision = json.loads(out)
        except ValueError:
            continue

        specific = decision.get("hookSpecificOutput") or {}
        reason = (
            decision.get("reason")
            or specific.get("permissionDecisionReason")
            or decision.get("permissionDecisionReason")
        )
        blocked = decision.get("decision") in ("block", "deny") or specific.get(
            "permissionDecision"
        ) in ("deny", "ask")

        if blocked and reason:
            refuse(reason)

sys.exit(0)
