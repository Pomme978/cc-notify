#!/bin/bash
# Envoie une bannière avec alerter et traite la réaction de l'utilisateur.
#
# alerter BLOQUE jusqu'à ce que la bannière soit fermée, cliquée ou répondue.
# Ce script est donc lancé détaché par cc-notify.sh : un hook qui attendrait
# une interaction humaine bloquerait Claude Code.
#
# Arguments : type titre sous-titre message son groupe session_iterm
set -u

HOOKS="$HOME/.claude/hooks"
ALERTER="${CC_NOTIFY_ALERTER:-$HOOKS/cc-notify-alerter}"
INJECT="${CC_NOTIFY_INJECT:-$HOOKS/cc-notify-inject.scpt}"
SENDER="${CC_NOTIFY_SENDER:-fr.allaan.cc-notify}"
# Au-delà, la bannière se ferme et le processus rend la main. Sans cela, un
# processus par notification s'accumulerait indéfiniment.
TIMEOUT="${CC_NOTIFY_REPLY_TIMEOUT:-3600}"

TYPE="$1"; TITRE="$2"; SOUSTITRE="$3"; MESSAGE="$4"; SON="$5"; GROUPE="$6"; ITERM="${7:-}"

set -- --title "$TITRE" --subtitle "$SOUSTITRE" --message "$MESSAGE" \
       --sound "$SON" --group "$GROUPE" --sender "$SENDER" \
       --timeout "$TIMEOUT" --json

# Champ de réponse pour une fin de tour seulement. Une demande de permission
# attend une touche dans un sélecteur, pas du texte libre : y coller une phrase
# ferait n'importe quoi.
[ "$TYPE" = "done" ] && set -- "$@" --reply "Répondre à Claude…"

SORTIE=$("$ALERTER" "$@" 2>/dev/null)
ACTION=$(printf '%s' "$SORTIE" | jq -r '.activationType // ""' 2>/dev/null)

# Toute réaction de votre part annule l'escalade vers le téléphone.
STATE_DIR="${CC_NOTIFY_STATE_DIR:-$HOME/.claude/state/cc-notify}"
case "$ACTION" in
  replied|contentsClicked|actionClicked) rm -f "$STATE_DIR/pending-$GROUPE" 2>/dev/null ;;
esac

case "$ACTION" in
  replied)
    REPONSE=$(printf '%s' "$SORTIE" | jq -r '.activationValue // ""' 2>/dev/null)
    if [ -n "$REPONSE" ]; then
      /usr/bin/osascript "$INJECT" "$ITERM" "$REPONSE"
    else
      /usr/bin/osascript "$INJECT" "$ITERM"
    fi
    ;;
  contentsClicked|actionClicked)
    /usr/bin/osascript "$INJECT" "$ITERM"
    ;;
esac

exit 0
