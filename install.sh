#!/bin/bash
# Installe cc-notify : liens symboliques + bloc hooks dans settings.json.
# Idempotent. `--uninstall` fait le chemin inverse.
set -u

PROJET="$(cd "$(dirname "$0")" && pwd)"
HOOKS="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$HOOKS/cc-notify.sh" "$HOOKS/cc-notify.conf" \
        "$HOOKS/cc-notify-focus.scpt" "$HOOKS/cc-notify-icon.png" \
        "$HOOKS/cc-notify-app" "$HOOKS/cc-notify-alerter" \
        "$HOOKS/cc-notify-send.sh" "$HOOKS/cc-notify-inject.scpt" \
        "$HOOKS/cc-notify-escalate.sh"
  tmp=$(mktemp)
  jq 'del(.hooks.UserPromptSubmit, .hooks.SubagentStart, .hooks.SubagentStop,
          .hooks.PostToolUse, .hooks.Stop, .hooks.StopFailure, .hooks.Notification)
      | if (.hooks | length) == 0 then del(.hooks) else . end' \
     "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "cc-notify désinstallé. Les fichiers du projet sont intacts."
  exit 0
fi

command -v terminal-notifier >/dev/null 2>&1 || {
  echo "terminal-notifier manquant. Lancer : brew install terminal-notifier"
  exit 1
}

mkdir -p "$HOOKS"
chmod +x "$PROJET/cc-notify.sh"
[ -f "$PROJET/cc-notify-icon.png" ] || "$PROJET/make-icon.sh"
[ -d "$PROJET/vendor/cc-notify.app" ] || "$PROJET/make-app.sh"
# alerter est facultatif : sans lui, on retombe sur terminal-notifier, mais on
# perd le champ de réponse dans la bannière.
[ -x "$PROJET/vendor/alerter" ] || "$PROJET/get-alerter.sh" || \
  echo "avertissement : alerter absent, pas de champ de réponse dans les bannières"
chmod +x "$PROJET/cc-notify-send.sh" "$PROJET/cc-notify-escalate.sh"

ln -sf "$PROJET/cc-notify.sh"           "$HOOKS/cc-notify.sh"
ln -sf "$PROJET/cc-notify.conf"         "$HOOKS/cc-notify.conf"
ln -sf "$PROJET/cc-notify-focus.scpt"   "$HOOKS/cc-notify-focus.scpt"
ln -sf "$PROJET/cc-notify-inject.scpt"  "$HOOKS/cc-notify-inject.scpt"
ln -sf "$PROJET/cc-notify-send.sh"      "$HOOKS/cc-notify-send.sh"
ln -sf "$PROJET/cc-notify-escalate.sh"  "$HOOKS/cc-notify-escalate.sh"
ln -sf "$PROJET/cc-notify-icon.png"     "$HOOKS/cc-notify-icon.png"
ln -sf "$PROJET/vendor/cc-notify.app"   "$HOOKS/cc-notify-app"
[ -x "$PROJET/vendor/alerter" ] && ln -sf "$PROJET/vendor/alerter" "$HOOKS/cc-notify-alerter"

CMD="$HOOKS/cc-notify.sh"

# PostToolUse est branché sur tous les outils, sans matcher : un appel
# d outil est le seul signe de vie de certains types de sous-agents, ceux
# qui n emettent pas SubagentStart.
tmp=$(mktemp)
jq --arg cmd "$CMD" '
  def entry: [{matcher: "", hooks: [{type: "command", command: $cmd, timeout: 10}]}];
  .hooks = (.hooks // {})
  | .hooks.UserPromptSubmit = entry
  | .hooks.SubagentStart    = entry
  | .hooks.SubagentStop     = entry
  | .hooks.Stop             = entry
  | .hooks.StopFailure      = entry
  | .hooks.PostToolUse      = entry
  | .hooks.Notification     = [{matcher: "permission_prompt|agent_needs_input",
                                hooks: [{type: "command", command: $cmd, timeout: 10}]}]
' "$SETTINGS" > "$tmp" || { echo "échec de la fusion jq"; rm -f "$tmp"; exit 1; }
mv "$tmp" "$SETTINGS"

echo "cc-notify installé."
echo "Redémarrer Claude Code, puis vérifier avec /hooks."
