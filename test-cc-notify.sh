#!/bin/bash
# Harnais de test de cc-notify. Aucun effet de bord hors de son dossier temporaire.
cd "$(dirname "$0")" || exit 1

export CC_NOTIFY_STATE_DIR
CC_NOTIFY_STATE_DIR=$(mktemp -d /tmp/cc-notify-test.XXXXXX)
export CC_NOTIFY_STUB_FRONT=no
export CC_NOTIFY_FOCUS_SCPT=/nonexistent

PASS=0
FAIL=0
OUT=""
SID="test-session"

# Lance le script avec le JSON passé en argument, capture stdout dans $OUT.
run_hook() {
  OUT=$(printf '%s' "$1" | ./cc-notify.sh --dry-run 2>&1)
}

# Compare $OUT à l'attendu.
assert_out() {
  if [ "$OUT" = "$1" ]; then
    PASS=$((PASS + 1))
    printf '  ok   %s\n' "$2"
  else
    FAIL=$((FAIL + 1))
    printf '  FAIL %s\n       attendu: [%s]\n       obtenu : [%s]\n' "$2" "$1" "$OUT"
  fi
}

# Écrit un fichier d'état complet. Arguments positionnels :
# turn_start subagents bg wakeup_until iterm_session notified_prompt
write_state() {
  mkdir -p "$CC_NOTIFY_STATE_DIR"
  cat > "$CC_NOTIFY_STATE_DIR/$SID.json" <<EOF
{"turn_start":$1,"subagents":$2,"bg":$3,"wakeup_until":$4,
 "iterm_session":"$5","notified_prompt":"$6","cwd":"/tmp/MonProjet"}
EOF
}

reset_state() { rm -f "$CC_NOTIFY_STATE_DIR/$SID.json"; }

NOW=$(date +%s)

echo "== Task 1 : dispatch =="

run_hook '{"hook_event_name":"Stop","session_id":"test-session","prompt_id":"p1"}'
assert_out "NOTIFY done" "Stop produit une décision done"

run_hook '{"hook_event_name":"EvenementInconnu","session_id":"test-session"}'
assert_out "" "un événement inconnu ne produit rien"

run_hook '{"hook_event_name":"Stop","session_id":"test-session","prompt_id":"p1"}'
[ $? -eq 0 ] && { PASS=$((PASS + 1)); echo "  ok   code de sortie 0"; } \
             || { FAIL=$((FAIL + 1)); echo "  FAIL code de sortie non nul"; }

echo
printf 'Résultat : %d réussis, %d échoués\n' "$PASS" "$FAIL"
rm -rf "$CC_NOTIFY_STATE_DIR"
[ "$FAIL" -eq 0 ]
