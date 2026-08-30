#!/bin/bash
# Harnais de test de cc-notify. Aucun effet de bord hors de son dossier temporaire.
cd "$(dirname "$0")/.." || exit 1

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
  OUT=$(printf '%s' "$1" | ./src/cc-notify.sh --dry-run 2>&1)
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
# turn_start nb_agents_vivants bg wakeup_until iterm_session notified_prompt
# Les agents sont horodatés à maintenant, donc considérés vivants.
write_state() {
  mkdir -p "$CC_NOTIFY_STATE_DIR"
  ws_agents='{}'
  ws_i=0
  while [ "$ws_i" -lt "$2" ]; do
    ws_agents=$(printf '%s' "$ws_agents" | jq -c --arg k "a$ws_i" --argjson t "$NOW" '.[$k]=$t')
    ws_i=$((ws_i + 1))
  done
  cat > "$CC_NOTIFY_STATE_DIR/$SID.json" <<EOF
{"turn_start":$1,"agents":$ws_agents,"bg":$3,"wakeup_until":$4,
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

# Nombre d'agents enregistrés dans l'état.
nb_agents() { jq -r '(.agents // {}) | length' "$CC_NOTIFY_STATE_DIR/$SID.json" 2>/dev/null; }

assert_agents() {
  got=$(nb_agents)
  if [ "$got" = "$1" ]; then
    PASS=$((PASS + 1)); printf '  ok   %s\n' "$2"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s\n       attendu: [%s]\n       obtenu : [%s]\n' "$2" "$1" "$got"
  fi
}

reset_state
run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"test-session","prompt_id":"p1","cwd":"/tmp/MonProjet"}'
assert_agents 0               "UserPromptSubmit initialise agents à vide"
assert_key bg 0               "UserPromptSubmit initialise bg à 0"
assert_key wakeup_until 0     "UserPromptSubmit initialise wakeup_until à 0"
assert_key cwd /tmp/MonProjet "UserPromptSubmit enregistre le cwd"

run_hook '{"hook_event_name":"SubagentStart","session_id":"test-session","agent_id":"a1"}'
run_hook '{"hook_event_name":"SubagentStart","session_id":"test-session","agent_id":"a2"}'
assert_agents 2 "deux SubagentStart enregistrent deux agents"

run_hook '{"hook_event_name":"SubagentStart","session_id":"test-session","agent_id":"a1"}'
assert_agents 2 "un même agent_id ne compte qu'une fois"

run_hook '{"hook_event_name":"SubagentStop","session_id":"test-session","agent_id":"a1"}'
assert_agents 1 "SubagentStop retire l'agent nommé"

run_hook '{"hook_event_name":"SubagentStop","session_id":"test-session","agent_id":"a2"}'
run_hook '{"hook_event_name":"SubagentStop","session_id":"test-session","agent_id":"jamais-vu"}'
assert_agents 0 "retirer un agent inconnu est sans effet"

# Le cœur du correctif : un agent qui n'émet jamais SubagentStart est quand
# même détecté, parce que ses appels d'outils portent son agent_id.
run_hook '{"hook_event_name":"PostToolUse","session_id":"test-session","agent_id":"fantome","agent_type":"teammate","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
assert_agents 1 "un outil appelé par un agent inconnu l'enregistre"
run_hook '{"hook_event_name":"SubagentStop","session_id":"test-session","agent_id":"fantome"}'
assert_agents 0 "et son SubagentStop le retire"

run_hook '{"hook_event_name":"PostToolUse","session_id":"test-session","tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'
assert_agents 0 "un outil de l'agent principal n'enregistre rien"

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

run_hook '{"hook_event_name":"SubagentStart","session_id":"test-session","agent_id":"survivant"}'
run_hook '{"hook_event_name":"UserPromptSubmit","session_id":"test-session","prompt_id":"p2","cwd":"/tmp/MonProjet"}'
assert_agents 0           "UserPromptSubmit vide les agents"
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

# Par défaut on simule un utilisateur absent, pour que le filtre d'inactivité
# ne se déclenche pas et n'interfère pas avec les autres cas.
export CC_NOTIFY_STUB_IDLE=9999

# 1 — tour trop court ET utilisateur devant sa machine
write_state "$RECENT" 0 0 0 "UUID-A" ""
CC_NOTIFY_STUB_IDLE=2 run_hook "$STOP"
assert_out "SKIP utilisateur-present" "tour de 5 s, machine active : silence"

# 1 bis — tour trop court MAIS utilisateur absent : on notifie quand même
write_state "$RECENT" 0 0 0 "UUID-A" ""
CC_NOTIFY_STUB_IDLE=600 run_hook "$STOP"
assert_out "NOTIFY done" "tour de 5 s mais absent depuis 10 min : notification"

# 1 ter — tour long et utilisateur devant : on notifie, il peut être ailleurs
write_state "$VIEUX" 0 0 0 "UUID-A" ""
CC_NOTIFY_STUB_IDLE=2 run_hook "$STOP"
assert_out "NOTIFY done" "tour de 5 min, machine active : notification"

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

# 15 — un agent périmé ne bloque plus : garde-fou contre un SubagentStop perdu
mkdir -p "$CC_NOTIFY_STATE_DIR"
cat > "$CC_NOTIFY_STATE_DIR/$SID.json" <<EOF
{"turn_start":$VIEUX,"agents":{"zombie":$((NOW - 7200))},"bg":0,"wakeup_until":0,
 "iterm_session":"UUID-A","notified_prompt":"","cwd":"/tmp/MonProjet"}
EOF
run_hook "$STOP"; assert_out "NOTIFY done" "agent vu il y a 2 h : considéré mort"

cat > "$CC_NOTIFY_STATE_DIR/$SID.json" <<EOF
{"turn_start":$VIEUX,"agents":{"vivant":$((NOW - 10))},"bg":0,"wakeup_until":0,
 "iterm_session":"UUID-A","notified_prompt":"","cwd":"/tmp/MonProjet"}
EOF
run_hook "$STOP"; assert_out "SKIP sous-agent-actif" "agent vu il y a 10 s : bien vivant"

echo
echo "== Titre de la bannière =="

assert_titre() {
  got=$(./src/cc-notify.sh --titre "$1" "$2" 2>&1)
  if [ "$got" = "$3" ]; then
    PASS=$((PASS + 1)); printf '  ok   %s\n' "$4"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s\n       attendu: [%s]\n       obtenu : [%s]\n' "$4" "$3" "$got"
  fi
}

TREPO="$CC_NOTIFY_STATE_DIR/mon-depot"
mkdir -p "$TREPO/sous/dossier"
( cd "$TREPO" && git init -q 2>/dev/null )
assert_titre "$TREPO" "" "mon-depot" "un dépôt git donne son nom"
assert_titre "$TREPO/sous/dossier" "" "mon-depot" "depuis un sous-dossier aussi"

THORS="$CC_NOTIFY_STATE_DIR/sans git"
mkdir -p "$THORS"
assert_titre "$THORS" "UUID-INEXISTANT" "sans git" "hors dépôt et sans session : le nom du dossier"

assert_titre "/chemin/qui/nexiste/pas" "" "pas" "un chemin inexistant ne fait pas échouer"

echo
echo "== Escalade vers le téléphone =="

ESC_CONF="$CC_NOTIFY_STATE_DIR/esc.conf"
printf 'NTFY_TOPIC=sujet-de-test\nESCALATE_AFTER=1\n' > "$ESC_CONF"
PENDING="$CC_NOTIFY_STATE_DIR/pending-$SID"

# Personne ne réagit : le marqueur survit, le push part.
: > "$PENDING"
OUT=$(CONF_OVERRIDE="$ESC_CONF" ./src/cc-notify-escalate.sh --dry-run "$SID" "Mon projet" "Terminé" 2>&1)
assert_out "PUSH Mon projet | Terminé" "sans réaction : le push part"

if [ -f "$PENDING" ]; then
  FAIL=$((FAIL + 1)); echo "  FAIL le marqueur doit être consommé après le push"
else
  PASS=$((PASS + 1)); echo "  ok   le marqueur est consommé après le push"
fi

# Vous avez réagi entre-temps : le marqueur a disparu, rien ne part.
: > "$PENDING"
( sleep 0.3; rm -f "$PENDING" ) &
OUT=$(CONF_OVERRIDE="$ESC_CONF" ./src/cc-notify-escalate.sh --dry-run "$SID" "Mon projet" "Terminé" 2>&1)
assert_out "" "réaction avant le délai : rien ne part"
wait

# Sans sujet configuré, l'escalade est inerte.
printf 'NTFY_TOPIC=\nESCALATE_AFTER=1\n' > "$ESC_CONF"
: > "$PENDING"
OUT=$(CONF_OVERRIDE="$ESC_CONF" ./src/cc-notify-escalate.sh --dry-run "$SID" "Mon projet" "Terminé" 2>&1)
assert_out "" "sans NTFY_TOPIC : rien ne part"
rm -f "$PENDING"

echo
printf 'Résultat : %d réussis, %d échoués\n' "$PASS" "$FAIL"
rm -rf "$CC_NOTIFY_STATE_DIR"
[ "$FAIL" -eq 0 ]
