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
echo "== Task 3 : filtres de décision =="

FUTUR=$((NOW + 600))
PASSE=$((NOW - 600))
VIEUX=$((NOW - 300))   # tour démarré il y a 5 min
RECENT=$((NOW - 5))    # tour démarré il y a 5 s

STOP='{"hook_event_name":"Stop","session_id":"test-session","prompt_id":"pX","last_assistant_message":"fini"}'
QUEST='{"hook_event_name":"Notification","session_id":"test-session","notification_type":"permission_prompt"}'
ERR='{"hook_event_name":"StopFailure","session_id":"test-session","prompt_id":"pE","error_type":"rate_limit"}'

# 1 — tour trop court
write_state "$RECENT" 0 0 0 "UUID-A" ""
run_hook "$STOP"; assert_out "SKIP tour-court" "tour de 5 s : silence"

# 2 — état propre, tour long
write_state "$VIEUX" 0 0 0 "UUID-A" ""
run_hook "$STOP"; assert_out "NOTIFY done" "tour de 5 min, état propre : notification"

# 3 — sous-agent actif
write_state "$VIEUX" 1 0 0 "UUID-A" ""
run_hook "$STOP"; assert_out "SKIP sous-agent-actif" "sous-agent en cours : silence"

# 4 — tâche de fond
write_state "$VIEUX" 0 1 0 "UUID-A" ""
run_hook "$STOP"; assert_out "SKIP tache-de-fond" "tâche de fond en cours : silence"

# 5 — réveil programmé non échu
write_state "$VIEUX" 0 0 "$FUTUR" "UUID-A" ""
run_hook "$STOP"; assert_out "SKIP reveil-programme" "réveil à venir : silence"

# 6 — réveil échu
write_state "$VIEUX" 0 0 "$PASSE" "UUID-A" ""
run_hook "$STOP"; assert_out "NOTIFY done" "réveil échu : notification"

# 7 — question, tour court : la durée ne s'applique pas
write_state "$RECENT" 0 0 0 "UUID-A" ""
run_hook "$QUEST"; assert_out "NOTIFY question" "question après 5 s : notification"

# 8 — erreur : seul l'onglet filtre
write_state "$RECENT" 1 1 "$FUTUR" "UUID-A" ""
run_hook "$ERR"; assert_out "NOTIFY error" "erreur : ignore sous-agent, fond, réveil et durée"

# 9 — doublon
write_state "$VIEUX" 0 0 0 "UUID-A" ""
run_hook "$STOP"; assert_out "NOTIFY done" "première notification du tour"
run_hook "$STOP"; assert_out "SKIP doublon" "seconde notification du même prompt_id : silence"

# 10 — la question ne consomme pas le prompt_id, et n'est pas bloquée par lui
write_state "$VIEUX" 0 0 0 "UUID-A" "pX"
run_hook "$QUEST"; assert_out "NOTIFY question" "une question n'est jamais dédupliquée"
run_hook "$STOP";  assert_out "SKIP doublon" "la question n'a pas consommé le prompt_id"

# 11 — fichier d'état absent : échec ouvert
reset_state
run_hook "$STOP"; assert_out "NOTIFY done" "état absent : on notifie quand même"

# 12 — état corrompu : échec ouvert
mkdir -p "$CC_NOTIFY_STATE_DIR"
printf 'ceci nest pas du json' > "$CC_NOTIFY_STATE_DIR/$SID.json"
run_hook "$STOP"; assert_out "NOTIFY done" "état corrompu : on notifie quand même"

# 13 — onglet au premier plan
write_state "$VIEUX" 0 0 0 "UUID-A" ""
CC_NOTIFY_STUB_FRONT=yes run_hook "$STOP"
assert_out "SKIP onglet-actif" "onglet déjà regardé : silence"

CC_NOTIFY_STUB_FRONT=yes run_hook "$ERR"
assert_out "SKIP onglet-actif" "onglet déjà regardé : même les erreurs se taisent"

# 14 — interrupteur général
write_state "$VIEUX" 0 0 0 "UUID-A" ""
printf 'ENABLED=0\n' > "$CC_NOTIFY_STATE_DIR/conf"
CONF_OVERRIDE="$CC_NOTIFY_STATE_DIR/conf" run_hook "$STOP"
assert_out "SKIP desactive" "ENABLED=0 : silence total"

echo
printf 'Résultat : %d réussis, %d échoués\n' "$PASS" "$FAIL"
rm -rf "$CC_NOTIFY_STATE_DIR"
[ "$FAIL" -eq 0 ]
