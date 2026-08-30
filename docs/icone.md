# L'icône et le bundle

`./make-icon.sh` produit `cc-notify-icon.png` et `cc-notify.icns` à partir du glyphe officiel
Claude Code, qui vit dans `assets/claude-code.svg`. Deux retouches sont nécessaires. Les yeux
du glyphe sont des trous dans le tracé, donc on glisse deux rectangles noirs derrière pour
qu'ils restent visibles sur n'importe quel fond. Et le glyphe, large et bas, est recentré dans
un carré avec la marge qu'attend une icône macOS.

`./make-app.sh` construit ensuite `vendor/cc-notify.app`, une copie de `terminal-notifier.app`
qui porte cette icône et le nom « Claude Code ». Ce détour est indispensable, parce que macOS
ignore l'option `-appIcon`, qui reposait sur une API privée retirée depuis. L'icône affichée à
gauche d'une bannière vient toujours du bundle de l'application émettrice, il faut donc émettre
depuis le nôtre.

Après avoir modifié le SVG, il suffit de rejouer les deux scripts.

```bash
./make-icon.sh && ./make-app.sh
```

## Provenance

Le glyphe appartient à Anthropic et n'est repris ici que pour identifier Claude Code. Une
première version de l'icône était découpée dans la mascotte animée de Claude, rétro-conçue par
Codrops, qui n'est plus utilisée ni redistribuée dans ce dépôt. La provenance de cette mascotte
reste notée dans [`../assets/SOURCE.md`](../assets/SOURCE.md).
