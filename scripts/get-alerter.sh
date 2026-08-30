#!/bin/bash
# Récupère alerter, le notifieur qui gère les champs de réponse. Absent de
# Homebrew, on le prend à sa release GitHub.
#
# Deux vérifications avant de rendre le binaire exécutable :
#   * l'empreinte SHA-256 de l'archive, épinglée ci-dessous ;
#   * la signature Developer ID, qui doit remonter à Apple Root CA.
# Si l'une échoue, on s'arrête sans rien installer.
set -eu
cd "$(dirname "$0")/.."

VERSION=26.5
URL="https://github.com/vjeantet/alerter/releases/download/v$VERSION/alerter-$VERSION.zip"
SHA=11f63cddc9bb3f8554ed9b762632a120cfa7bee05e3c09d65734823e09d24f10
EQUIPE=NQLLJK2GK3   # Valere JEANTET

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "téléchargement de alerter $VERSION…"
curl -fsSL "$URL" -o "$TMP/alerter.zip"

OBTENU=$(shasum -a 256 "$TMP/alerter.zip" | awk '{print $1}')
if [ "$OBTENU" != "$SHA" ]; then
  echo "EMPREINTE INATTENDUE — installation annulée."
  echo "  attendue : $SHA"
  echo "  obtenue  : $OBTENU"
  exit 1
fi

unzip -q "$TMP/alerter.zip" -d "$TMP/x"
BIN="$TMP/x/alerter"
[ -f "$BIN" ] || { echo "archive inattendue : pas de binaire alerter"; exit 1; }

if ! codesign -v "$BIN" 2>/dev/null; then
  echo "SIGNATURE INVALIDE — installation annulée."
  exit 1
fi
OBTENUE=$(codesign -dvvv "$BIN" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2}')
if [ "$OBTENUE" != "$EQUIPE" ]; then
  echo "SIGNATAIRE INATTENDU — installation annulée."
  echo "  attendu : $EQUIPE"
  echo "  obtenu  : $OBTENUE"
  exit 1
fi

mkdir -p vendor
cp "$BIN" vendor/alerter
chmod +x vendor/alerter
xattr -c vendor/alerter 2>/dev/null || true

echo "vendor/alerter installé — empreinte et signature Developer ID vérifiées"
