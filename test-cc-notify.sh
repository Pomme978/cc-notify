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
echo "== Task 2 : accumulation de l'état =="

# Lit une clé du fichier d'état de test.
state_key() { jq -r ".$1" "$CC_NOTIFY_STATE_DIR/$SID.json" 2>/dev/null; }

assert_key() {
  got=$(state_key "$1")
  if [ "$got" = "$2" ]; then
    PASS=$((PASS + 1)); printf '  ok   %s\n' "$3"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s\n       attendu: [%s]\n       obtenu : [%s]\n' "$3" "$2" "$got"
  fi
}

reset_state
run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"test-session","prompt_id":"p1","cwd":"/tmp/MonProjet"}'
assert_key subagents 0        "UserPromptSubmit initialise subagents à 0"
assert_key bg 0               "UserPromptSubmit initialise bg à 0"
assert_key wakeup_until 0     "UserPromptSubmit initialise wakeup_until à 0"
assert_key cwd /tmp/MonProjet "UserPromptSubmit enregistre le cwd"

run_hook '{"hook_event_name":"SubagentStart","session_id":"test-session","agent_id":"a1"}'
run_hook '{"hook_event_name":"SubagentStart","session_id":"test-session","agent_id":"a2"}'
assert_key subagents 2 "deux SubagentStart incrémentent à 2"

run_hook '{"hook_event_name":"SubagentStop","session_id":"test-session","agent_id":"a1"}'
assert_key subagents 1 "SubagentStop décrémente à 1"

run_hook '{"hook_event_name":"SubagentStop","session_id":"test-session","agent_id":"a2"}'
run_hook '{"hook_event_name":"SubagentStop","session_id":"test-session","agent_id":"a3"}'
assert_key subagents 0 "SubagentStop ne descend pas sous 0"

run_hook '{"hook_event_name":"PostToolUse","session_id":"test-session","tool_name":"Bash","tool_input":{"command":"npm test","run_in_background":true}}'
assert_key bg 1 "Bash en arrière-plan incrémente bg"

run_hook '{"hook_event_name":"PostToolUse","session_id":"test-session","tool_name":"Bash","tool_input":{"command":"ls","run_in_background":false}}'
assert_key bg 1 "Bash au premier plan laisse bg inchangé"

run_hook '{"hook_event_name":"PostToolUse","session_id":"test-session","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
assert_key bg 1 "un autre outil laisse bg inchangé"

run_hook '{"hook_event_name":"PostToolUse","session_id":"test-session","tool_name":"ScheduleWakeup","tool_input":{"delaySeconds":600,"noop":true}}'
got=$(state_key wakeup_until)
if [ "$got" -gt "$NOW" ] 2>/dev/null && [ "$got" -le $((NOW + 700)) ] 2>/dev/null; then
  PASS=$((PASS + 1)); echo "  ok   ScheduleWakeup pose wakeup_until dans le futur"
else
  FAIL=$((FAIL + 1)); echo "  FAIL ScheduleWakeup : wakeup_until = [$got], attendu ~$((NOW + 600))"
fi

run_hook '{"hook_event_name":"PostToolUse","session_id":"test-session","tool_name":"ScheduleWakeup","tool_input":{"stop":true}}'
assert_key wakeup_until 0 "ScheduleWakeup avec stop:true remet wakeup_until à 0"

run_hook '{"hook_event_name":"PostToolUse","session_id":"test-session","tool_name":"ScheduleWakeup","tool_input":{"delaySeconds":1200.0}}'
got=$(state_key wakeup_until)
if [ "$got" -gt "$NOW" ] 2>/dev/null; then
  PASS=$((PASS + 1)); echo "  ok   delaySeconds décimal est accepté"
else
  FAIL=$((FAIL + 1)); echo "  FAIL delaySeconds décimal : wakeup_until = [$got]"
fi

run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"test-session","prompt_id":"p2","cwd":"/tmp/MonProjet"}'
assert_key subagents 0    "UserPromptSubmit remet subagents à 0"
assert_key bg 0           "UserPromptSubmit remet bg à 0"
assert_key wakeup_until 0 "UserPromptSubmit remet wakeup_until à 0"

echo
printf 'Résultat : %d réussis, %d échoués\n' "$PASS" "$FAIL"
rm -rf "$CC_NOTIFY_STATE_DIR"
[ "$FAIL" -eq 0 ]
