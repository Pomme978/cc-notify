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

CONF="$HOME/.claude/hooks/cc-notify.conf"
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

# Renvoie 0 s'il faut notifier, 1 sinon en écrivant le motif sur stdout.
# Remplacée en Task 3.
decide() { return 0; }

# Remplacée en Task 4.
notify() { return 0; }

# --------------------------------------------------------------- dispatch --
case "$EVENT" in
  Stop)         emit done ;;
  StopFailure)  emit error ;;
  Notification) emit question ;;
esac

exit 0
