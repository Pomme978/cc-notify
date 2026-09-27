#!/usr/bin/env bash
# Hook SessionStart : synchronise avec origin en fast-forward seul, jamais de rebase ni de forçage.
# Détail et raisonnement : docs/hooks.md
set -uo pipefail

emit() {
    python3 - "$1" <<'PY'
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": sys.argv[1],
    }
}))
PY
    exit 0
}

# `timeout` n'existe pas sur macOS, on borne la durée à la main.
with_timeout() {
    local limit=$1
    shift
    "$@" &
    local pid=$! elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$limit" ]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wait "$pid"
}

git rev-parse --git-dir >/dev/null 2>&1 || exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null) || exit 0

slug=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')
[ -n "$slug" ] || slug=projet

with_timeout 15 git fetch --quiet 2>/dev/null

behind=$(git rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)
ahead=$(git rev-list --count "$upstream..HEAD" 2>/dev/null || echo 0)
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

state="Dépôt : branche \`$branch\`, suit \`$upstream\`."

if [ "$behind" -eq 0 ]; then
    state="$state À jour avec origin."
elif [ "$ahead" -gt 0 ]; then
    state="$state EN RETARD DE $behind COMMIT(S) SUR origin, avec $ahead commit(s) local(aux) en avance : le fast-forward est impossible, il faut un vrai merge. Prévenir l'utilisateur et lui demander avant de pull. Jamais de rebase, jamais de force push. Ne pas coder sur une base périmée."
else
    # Verrou : deux sessions qui démarrent ensemble ne doivent pas merger en concurrence.
    lock="${TMPDIR:-/tmp}/$slug-pull.lock"
    if ! mkdir "$lock" 2>/dev/null; then
        emit "$state EN RETARD DE $behind COMMIT(S) : un autre agent est en train de synchroniser le dépôt. Attendre, puis revérifier avec \`git status\` avant de coder."
    fi
    trap 'rmdir "$lock" 2>/dev/null' EXIT

    if with_timeout 30 git merge --ff-only "$upstream" --quiet 2>/dev/null; then
        state="$state Était en retard de $behind commit(s) : PULL FAST-FORWARD DÉJÀ EFFECTUÉ automatiquement. La base de code est à jour, inutile de pull à la main."
    else
        state="$state EN RETARD DE $behind COMMIT(S) : git a refusé le fast-forward, probablement parce qu'un commit distant touche un fichier modifié non commité (git protège le travail en cours, rien n'a été écrasé). Prévenir l'utilisateur, lui montrer le conflit potentiel, et lui laisser la main. Ne rien forcer, ne rien stasher. Ne pas coder sur une base périmée."
    fi
fi

[ "$ahead" -gt 0 ] && state="$state $ahead commit(s) local(aux) non poussé(s)."
[ "$dirty" -gt 0 ] && state="$state $dirty fichier(s) modifié(s) non commité(s) : travail en cours de l'utilisateur, ne jamais le reverter ni le nettoyer."

emit "$state"
