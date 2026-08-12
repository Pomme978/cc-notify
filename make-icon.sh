#!/bin/bash
# Génère cc-notify-icon.png, l'icône affichée dans les notifications,
# à partir du glyphe officiel Claude Code (assets/claude-code.svg).
#
# Le glyphe occupe x 0→24 et y 5→20 dans son viewBox : il est large et bas.
# On le recentre dans un carré de côté 30 pour lui donner la marge qu'attend
# une icône macOS, sans le déformer.
#
# Nécessite rsvg-convert (brew install librsvg).
set -eu
cd "$(dirname "$0")"

TAILLE=512
COTE=30
# Centre du glyphe : (12, 12.5). Coin du carré : centre − côté/2.
X0=-3
Y0=-2.5

sed "s|viewBox=\"0 0 24 24\"|viewBox=\"$X0 $Y0 $COTE $COTE\"|" assets/claude-code.svg \
  > .icon-tmp.svg

rsvg-convert -w "$TAILLE" -h "$TAILLE" -b none .icon-tmp.svg -o cc-notify-icon.png
rm -f .icon-tmp.svg

echo "cc-notify-icon.png généré ($(sips -g pixelWidth -g pixelHeight cc-notify-icon.png | tail -2 | tr -d ' \n'))"
