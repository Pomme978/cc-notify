#!/usr/bin/env bash
# Hook Stop : interdit de conclure un tour sur du code cassé PAR CETTE SESSION.
# Juge sur le journal des fichiers édités par la session, jamais sur `git status`.
# Checks déclarés dans rules.json, section `verify`. Détail : docs/hooks.md
set -uo pipefail

payload=$(cat)
read -r session prompt <<<"$(printf '%s' "$payload" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("session_id", ""), d.get("prompt_id", "x"))
' 2>/dev/null)" || exit 0

root="${CLAUDE_PROJECT_DIR:-.}"
cd "$root" || exit 0

slug=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')
[ -n "$slug" ] || slug=projet

tmp="${TMPDIR:-/tmp}"
ledger="$tmp/$slug-touched-$session"
[ -s "$ledger" ] || exit 0

touched=$(sort -u "$ledger")

checks=$(python3 - <<'PY'
import json, pathlib, sys
try:
    data = json.loads(pathlib.Path(".claude/hooks/rules.json").read_text(encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(0)
for check in data.get("verify", []):
    print("\t".join([",".join(check.get("when", [])), check.get("run", "")]))
PY
)
[ -n "$checks" ] || exit 0

attempts="$tmp/$slug-verify-$prompt"
[ "$(cat "$attempts" 2>/dev/null || echo 0)" -ge 2 ] && exit 0

# Verrou : deux agents ne lancent pas les checks en même temps sur le même arbre.
lock="$tmp/$slug-verify.lock"
for _ in $(seq 1 30); do
    mkdir "$lock" 2>/dev/null && break
    sleep 1
done
trap 'rmdir "$lock" 2>/dev/null' EXIT
[ -d "$lock" ] || exit 0

report=""
run() {
    if ! out=$("$@" 2>&1); then
        report="$report
=== $* ===
$(printf '%s' "$out" | tail -25)"
    fi
}

ran=0
while IFS=$'\t' read -r when cmd; do
    [ -n "$cmd" ] || continue
    match=0
    IFS=',' read -ra exts <<<"$when"
    for ext in "${exts[@]}"; do
        [ -n "$ext" ] || continue
        printf '%s\n' "$touched" | grep -q -- "${ext//./\\.}\$" && match=1
    done
    if [ "$match" -eq 1 ]; then
        ran=1
        # shellcheck disable=SC2086
        run $cmd
    fi
done <<<"$checks"

[ "$ran" -eq 1 ] || exit 0
[ -z "$report" ] && exit 0

# Le rapport cite-t-il un fichier que CETTE session a touché ?
ours=$(REPORT="$report" TOUCHED="$touched" python3 <<'PY'
import os

report = os.environ["REPORT"]
touched = [l for l in os.environ["TOUCHED"].splitlines() if l.strip()]
print(1 if any(os.path.basename(f) in report for f in touched) else 0)
PY
)
[ "$ours" = "1" ] || ours=0

if [ "$ours" -eq 1 ]; then
    echo $(( $(cat "$attempts" 2>/dev/null || echo 0) + 1 )) > "$attempts"
    python3 - "$report" <<'PY'
import json, sys
print(json.dumps({
    "decision": "block",
    "reason": "Tour bloqué : les checks échouent sur des fichiers que TU as édités. "
              "CLAUDE.md interdit de déclarer une tâche terminée sans preuve d'exécution."
              + sys.argv[1]
              + "\n\nCorriger la cause racine (jamais de @ts-ignore ni de contournement), puis reprendre.",
}))
PY
else
    echo 2 > "$attempts"
    python3 - "$report" <<'PY'
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "Stop",
        "additionalContext": "Les checks du projet échouent, mais AUCUN des fichiers que tu as édités "
                             "n'est en cause : le dépôt était déjà cassé (travail en cours d'un autre agent "
                             "ou de l'utilisateur). Ne pas corriger ces fichiers d'autorité, ne rien reverter : "
                             "SIGNALER l'erreur à l'utilisateur."
                             + sys.argv[1],
    }
}))
PY
fi
