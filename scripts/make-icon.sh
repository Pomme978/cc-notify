#!/bin/bash
# Génère assets/cc-notify-icon.png et assets/cc-notify.icns à partir du glyphe
# officiel Claude Code (assets/claude-code.svg).
#
# Deux retouches :
#   * les yeux du glyphe sont des trous (fill-rule evenodd) ; on glisse deux
#     rectangles noirs derrière pour qu'ils se voient sur fond clair comme sur
#     fond sombre. Leurs coordonnées sont celles des trous dans le tracé.
#   * le glyphe occupe x 0→24 et y 5→20 : large et bas. On le recentre dans un
#     carré de côté 30 pour lui donner la marge qu'attend une icône macOS.
#
# Nécessite rsvg-convert (brew install librsvg) et iconutil (système).
set -eu
cd "$(dirname "$0")/.."

TAILLE=512
COTE=30
X0=-3      # centre du glyphe (12, 12.5) moins COTE/2
Y0=-2.5
OEIL="#1F1300"

# Sur une seule ligne : sed BSD refuse les sauts de ligne dans un remplacement.
YEUX="<rect x=\"6\" y=\"8.102\" width=\"1.488\" height=\"2.847\" fill=\"$OEIL\"/><rect x=\"16.51\" y=\"8.102\" width=\"1.49\" height=\"2.847\" fill=\"$OEIL\"/>"

sed -e "s|viewBox=\"0 0 24 24\"|viewBox=\"$X0 $Y0 $COTE $COTE\"|" \
    -e "s|<title>Claude Code</title>|<title>Claude Code</title>$YEUX|" \
    assets/claude-code.svg > .icon-tmp.svg

rsvg-convert -w "$TAILLE" -h "$TAILLE" -b none .icon-tmp.svg -o assets/cc-notify-icon.png

# Jeu d'icônes pour le bundle .app.
rm -rf .build-icon.iconset && mkdir .build-icon.iconset
for t in 16 32 128 256 512; do
  rsvg-convert -w "$t"          -h "$t"          -b none .icon-tmp.svg -o ".build-icon.iconset/icon_${t}x${t}.png"
  rsvg-convert -w "$((t * 2))"  -h "$((t * 2))"  -b none .icon-tmp.svg -o ".build-icon.iconset/icon_${t}x${t}@2x.png"
done
iconutil -c icns .build-icon.iconset -o assets/cc-notify.icns
rm -rf .build-icon.iconset .icon-tmp.svg

echo "assets/cc-notify-icon.png ($(sips -g pixelWidth assets/cc-notify-icon.png | tail -1 | tr -d ' ')) et assets/cc-notify.icns générés"
