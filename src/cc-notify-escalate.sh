#!/bin/bash
# Escalade vers le téléphone. Lancé détaché à chaque notification, attend
# ESCALATE_AFTER secondes, puis pousse un message via ntfy.sh si — et seulement
# si — le marqueur d'attente est toujours là.
#
# Le marqueur est effacé dès que vous réagissez : réponse dans la bannière, clic
# dessus, ou nouveau message tapé dans la session. L'escalade ne se déclenche
# donc que si vous êtes vraiment parti.
#
# Arguments : session_id titre état
# --dry-run en premier argument imprime le push au lieu de l'envoyer.
set -u

DRY=0
[ "${1:-}" = "--dry-run" ] && { DRY=1; shift; }

NTFY_TOPIC=""
NTFY_SERVER="https://ntfy.sh"
NTFY_TAGS=""
NTFY_ICON=""
ESCALATE_AFTER=300

CONF="${CONF_OVERRIDE:-$HOME/.claude/hooks/cc-notify.conf}"
[ -r "$CONF" ] && . "$CONF"
# Réglages personnels, non versionnés : sujet ntfy, serveur privé, etc.
[ -r "${CONF%.conf}.local.conf" ] && . "${CONF%.conf}.local.conf"

STATE_DIR="${CC_NOTIFY_STATE_DIR:-$HOME/.claude/state/cc-notify}"

SID="$1"; TITRE="$2"; ETAT="$3"
PENDING="$STATE_DIR/pending-$SID"

[ -z "$NTFY_TOPIC" ] && exit 0

sleep "$ESCALATE_AFTER"

# Toujours en attente ? Sinon vous avez réagi, il n'y a rien à escalader.
[ -f "$PENDING" ] || exit 0
rm -f "$PENDING" 2>/dev/null

if [ "$DRY" = "1" ]; then
  printf 'PUSH %s | %s\n' "$TITRE" "$ETAT"
  exit 0
fi

set -- -H "Title: $ETAT" -H "Priority: high"
# Les tags deviennent des emojis collés au titre. Vides par défaut : sur iOS
# c'est le seul repère visuel possible, mais tout le monde n'en veut pas.
[ -n "$NTFY_TAGS" ] && set -- "$@" -H "Tags: $NTFY_TAGS"
# Icône personnalisée : Android uniquement, et seulement en JPEG ou PNG.
[ -n "$NTFY_ICON" ] && set -- "$@" -H "Icon: $NTFY_ICON"

curl -fsS "$@" -d "$TITRE" "$NTFY_SERVER/$NTFY_TOPIC" >/dev/null 2>&1

exit 0
