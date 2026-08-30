#!/bin/bash
# Construit vendor/cc-notify.app : une copie de terminal-notifier.app portant
# notre icône et notre identité.
#
# Pourquoi une copie plutôt que l'option -appIcon : macOS moderne ignore
# -appIcon (il reposait sur une API privée retirée). L'icône affichée à gauche
# d'une notification vient toujours du bundle de l'application émettrice. Seule
# façon d'y mettre la nôtre : émettre depuis notre propre bundle.
#
# Effet secondaire assumé : une entrée distincte « Claude Code » apparaît dans
# Réglages Système → Notifications, à autoriser une fois.
set -eu
cd "$(dirname "$0")/.."

SRC="$(brew --prefix terminal-notifier)/terminal-notifier.app"
DST="vendor/cc-notify.app"
ID="fr.allaan.cc-notify"
NOM="Claude Code"

[ -d "$SRC" ] || { echo "terminal-notifier introuvable. brew install terminal-notifier"; exit 1; }
[ -f assets/cc-notify.icns ] || ./scripts/make-icon.sh

rm -rf "$DST"
mkdir -p vendor
cp -R "$SRC" "$DST"

rm -f "$DST/Contents/Resources/Terminal.icns"
cp assets/cc-notify.icns "$DST/Contents/Resources/cc-notify.icns"

P="$DST/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$ID"  "$P"
plutil -replace CFBundleName       -string "$NOM" "$P"
plutil -replace CFBundleIconFile   -string "cc-notify" "$P"

# La copie invalide la signature d'origine : on re-signe en ad-hoc, sans quoi
# macOS refuse de lancer le binaire.
codesign --force --deep --sign - "$DST" 2>/dev/null

# Fait connaître le bundle à LaunchServices pour que son icône et son nom
# remontent dans le centre de notifications.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f "$(pwd)/$DST"

echo "$DST construit (identité $ID, nom « $NOM »)"
