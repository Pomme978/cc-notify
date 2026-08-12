#!/bin/bash
# cc-notify — notifications macOS pour Claude Code.
# Reçoit un payload de hook sur stdin, décide s'il faut alerter, notifie.
# Sort TOUJOURS en 0 : un hook en échec ne doit jamais bloquer Claude.
# Pas de `set -e` — c'est délibéré.
set -u

# ------------------------------------------------------------- configuration --
ENABLED=1
MIN_DURATION=30
BODY_LEN=120
SOUND_DONE=Ping
SOUND_QUESTION=Glass
SOUND_ERROR=Basso
DEBUG=0

CONF="${CONF_OVERRIDE:-$HOME/.claude/hooks/cc-notify.conf}"
[ -r "$CONF" ] && . "$CONF"

STATE_DIR="${CC_NOTIFY_STATE_DIR:-$HOME/.claude/state/cc-notify}"
FOCUS_SCPT="${CC_NOTIFY_FOCUS_SCPT:-$HOME/.claude/hooks/cc-notify-focus.scpt}"
LOG="$STATE_DIR/log"

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# ------------------------------------------------------------------ entrée --
INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "inconnue"' 2>/dev/null)
[ -z "$SID" ] && SID=inconnue
STATE="$STATE_DIR/$SID.json"

log() {
  [ "$DEBUG" = "1" ] || return 0
  mkdir -p "$STATE_DIR" 2>/dev/null
  printf '%s %s\n' "$(date +%FT%T)" "$*" >> "$LOG" 2>/dev/null
  return 0
}

# Lit un champ du payload d'entrée.
in_get() { printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null; }

# ------------------------------------------------------------------- état --
# Verrou par répertoire : deux sous-agents peuvent démarrer simultanément et
# une écriture perdue laisserait le compteur bloqué au-dessus de zéro, ce qui
# supprimerait toutes les notifications du tour.
LOCKDIR=""
lock_state() {
  LOCKDIR="$STATE.lock"
  mkdir -p "$STATE_DIR" 2>/dev/null
  i=0
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 50 ]; then rm -rf "$LOCKDIR" 2>/dev/null; mkdir "$LOCKDIR" 2>/dev/null; break; fi
    sleep 0.02
  done
}
unlock_state() {
  [ -n "$LOCKDIR" ] && rmdir "$LOCKDIR" 2>/dev/null
  LOCKDIR=""
  return 0
}

state_read() {
  if [ -f "$STATE" ]; then cat "$STATE" 2>/dev/null; else printf '{}'; fi
}

state_get() { state_read | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null; }

# state_merge '<filtre jq>' [args jq…] — écriture atomique.
state_merge() {
  filter="$1"; shift
  mkdir -p "$STATE_DIR" 2>/dev/null
  tmp="$STATE.tmp.$$"
  if state_read | jq "$@" "$filter" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$STATE" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

h_user_prompt_submit() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  iterm="${ITERM_SESSION_ID:-}"
  iterm="${iterm##*:}"
  cwd=$(in_get '.cwd // ""')
  jq -n --argjson t "$(date +%s)" --arg i "$iterm" --arg c "$cwd" \
    '{turn_start:$t, subagents:0, bg:0, wakeup_until:0,
      iterm_session:$i, notified_prompt:"", cwd:$c}' > "$STATE" 2>/dev/null
  # Purge des états orphelins de plus de 7 jours.
  find "$STATE_DIR" -name '*.json' -mtime +7 -delete 2>/dev/null
  return 0
}

h_subagent_start() {
  lock_state
  state_merge '.subagents = ((.subagents // 0) + 1)'
  unlock_state
}

h_subagent_stop() {
  lock_state
  state_merge '.subagents = ([((.subagents // 0) - 1), 0] | max)'
  unlock_state
}

h_post_tool_use() {
  tool=$(in_get '.tool_name // ""')
  now=$(date +%s)
  case "$tool" in
    ScheduleWakeup)
      stop=$(in_get '.tool_input.stop // false')
      lock_state
      if [ "$stop" = "true" ]; then
        state_merge '.wakeup_until = 0'
      else
        delay=$(in_get '.tool_input.delaySeconds // 0')
        delay="${delay%%.*}"
        case "$delay" in ''|*[!0-9]*) delay=0 ;; esac
        state_merge '.wakeup_until = $u' --argjson u "$((now + delay))"
      fi
      unlock_state
      ;;
    CronCreate)
      # On ne parse pas l'expression cron : une borne forfaitaire d'une heure
      # suffit à couvrir « la session va repartir seule ».
      lock_state
      state_merge '.wakeup_until = $u' --argjson u "$((now + 3600))"
      unlock_state
      ;;
    Bash)
      if [ "$(in_get '.tool_input.run_in_background // false')" = "true" ]; then
        lock_state
        state_merge '.bg = ((.bg // 0) + 1)'
        unlock_state
      fi
      ;;
  esac
  return 0
}

# --------------------------------------------------------------- décision --
# Écrit sur stdout `NOTIFY <type>` ou `SKIP <motif>` en mode dry-run.
emit() {
  type="$1"
  reason=$(decide "$type")
  if [ $? -eq 0 ]; then
    if [ "$DRY_RUN" = "1" ]; then printf 'NOTIFY %s\n' "$type"; else notify "$type"; fi
    log "NOTIFY $type sid=$SID"
  else
    if [ "$DRY_RUN" = "1" ]; then printf 'SKIP %s\n' "$reason"; fi
    log "SKIP $reason type=$type sid=$SID"
  fi
}

# Renvoie 0 si iTerm est au premier plan ET affiche la session de cet état.
# Échoue ouvert : toute incertitude renvoie 1, donc la notification passe.
front_tab_is_mine() {
  case "${CC_NOTIFY_STUB_FRONT:-}" in
    yes) return 0 ;;
    no)  return 1 ;;
  esac
  mine=$(state_get iterm_session)
  [ -z "$mine" ] && return 1
  front=$(osascript \
    -e 'with timeout of 5 seconds' \
    -e 'tell application "System Events" to get name of first application process whose frontmost is true' \
    -e 'end timeout' 2>/dev/null)
  [ "$front" = "iTerm2" ] || return 1
  cur=$(osascript \
    -e 'with timeout of 5 seconds' \
    -e 'tell application "iTerm2" to get id of current session of current tab of current window' \
    -e 'end timeout' 2>/dev/null)
  [ "$cur" = "$mine" ]
}

# Renvoie 0 s'il faut notifier ; sinon 1 en écrivant le motif sur stdout.
decide() {
  d_type="$1"

  [ "$ENABLED" = "1" ] || { printf 'desactive'; return 1; }

  front_tab_is_mine && { printf 'onglet-actif'; return 1; }

  d_now=$(date +%s)

  # Une erreur contourne tous les filtres de « ça va repartir tout seul » :
  # justement, ça ne repartira pas.
  if [ "$d_type" != "error" ]; then
    d_sub=$(state_get subagents);     [ -z "$d_sub" ]  && d_sub=0
    d_bg=$(state_get bg);             [ -z "$d_bg" ]   && d_bg=0
    d_wake=$(state_get wakeup_until); [ -z "$d_wake" ] && d_wake=0
    [ "$d_sub"  -gt 0 ]        2>/dev/null && { printf 'sous-agent-actif'; return 1; }
    [ "$d_bg"   -gt 0 ]        2>/dev/null && { printf 'tache-de-fond'; return 1; }
    [ "$d_wake" -gt "$d_now" ] 2>/dev/null && { printf 'reveil-programme'; return 1; }
  fi

  # La durée minimale ne s'applique qu'à la fin de tour : une question et une
  # erreur méritent d'être signalées même après cinq secondes.
  if [ "$d_type" = "done" ]; then
    d_start=$(state_get turn_start)
    if [ -n "$d_start" ]; then
      if [ $((d_now - d_start)) -lt "$MIN_DURATION" ] 2>/dev/null; then
        printf 'tour-court'; return 1
      fi
    fi
  fi

  # Déduplication réservée aux événements porteurs d'un prompt_id.
  # `Notification` n'en reçoit pas : il ne lit ni n'écrit ce champ.
  if [ "$d_type" = "done" ] || [ "$d_type" = "error" ]; then
    d_pid=$(in_get '.prompt_id // ""')
    if [ -n "$d_pid" ]; then
      d_last=$(state_get notified_prompt)
      [ "$d_pid" = "$d_last" ] && { printf 'doublon'; return 1; }
      lock_state
      state_merge '.notified_prompt = $p' --arg p "$d_pid"
      unlock_state
    fi
  fi

  return 0
}

# Remplacée en Task 4.
notify() { return 0; }

# --------------------------------------------------------------- dispatch --
case "$EVENT" in
  UserPromptSubmit) h_user_prompt_submit ;;
  SubagentStart)    h_subagent_start ;;
  SubagentStop)     h_subagent_stop ;;
  PostToolUse)      h_post_tool_use ;;
  Stop)         emit done ;;
  StopFailure)  emit error ;;
  Notification) emit question ;;
esac

exit 0
