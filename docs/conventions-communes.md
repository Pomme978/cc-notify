# Conventions communes à tous les projets Solyzon

Ces conventions valent sur n'importe quel projet Solyzon, indépendamment de la pile. Elles
voyagent avec le modèle plutôt que d'être redécrites projet par projet.

**Ce fichier ne s'enrichit pas depuis un projet.** Une convention propre à un projet va dans
`conventions.md`, qui est le fichier du projet. Si elle se révèle valable partout, elle
remonte dans le dépôt modèle et redescend ensuite dans tous les projets.

La référence d'implémentation vient de `zetelecom.fr`, premier projet à l'avoir posée.

---

## Repère d'environnement dans l'onglet du navigateur

**Objectif.** Distinguer d'un coup d'œil, dans un navigateur qui a beaucoup d'onglets
ouverts, l'environnement servi. En production, aucun repère. En développement local et sur un
aperçu, un repère visible.

Deux repères combinés, communs à **tous** les projets Solyzon, quel que soit le site :

| Repère | Local | Aperçu | Production |
|---|---|---|---|
| Préfixe du titre d'onglet | `(DEV) ...` | `(PREV) ...` | aucun |
| Favicon teinté | violet `#7C3AED` | orange `#F97316` | couleur de marque |

Un violet veut toujours dire local, un orange toujours aperçu, quel que soit le projet
ouvert dans l'onglet voisin.

### La source de vérité est l'environnement qui sert, jamais le mode de compilation

La valeur du repère se décide côté environnement qui **sert** l'application, jamais côté
mode de compilation du bundle. Une variable de build du type `DEV`/`PROD`, par exemple
`import.meta.env.DEV`, décrit comment le bundle a été compilé, pas l'environnement qui le
sert réellement. Dès qu'on sert un build de production alors que le serveur de
développement n'est pas lancé, un tel indicateur ment et le repère disparaît, même si la
page tourne encore en local. C'est le piège principal à éviter : ne jamais dériver le repère
d'un indicateur de compilation, toujours de la configuration de l'environnement qui sert la
page.

Un aperçu tourne généralement avec la même configuration d'environnement applicatif que la
production, donc cette configuration ne suffit pas non plus à distinguer un aperçu de la
production. D'où une variable dédiée à ce seul usage, aux seules valeurs `DEV`, `PREV`, ou
vide en production. Son nom exact dépend de l'outillage de build du projet, par exemple
`APP_ENV_LABEL`, `VITE_APP_ENV_LABEL` ou `PUBLIC_APP_ENV_LABEL`.

### Mécanique

- La couche serveur (contrôleur, layout, point d'entrée du rendu) expose cette variable à la
  configuration de l'application, avec un repli raisonnable qui la fait valoir `DEV` par
  défaut en développement local sans configuration explicite.
- Le layout HTML pose le préfixe dans le `<title>` du premier rendu. Un moyen courant de le
  rendre aussi lisible au JavaScript client, par exemple une balise meta dédiée ou une
  variable injectée dans la page, est une implémentation possible parmi d'autres.
- Pour une application dont la navigation se fait côté client sans rechargement complet de
  page (SPA), le titre doit être re-préfixé à **chaque** navigation. Sans cette étape, le
  titre posé par le routeur ou le framework front écrase le préfixe initial dès la première
  navigation, et le repère ne survit que quelques secondes.
- Un rendu effectué côté serveur sans accès au DOM (SSR) lit la variable d'environnement
  injectée au build plutôt qu'une balise du document.
- Les variables exposées au bundle client sont, dans la plupart des outils de build, figées
  à la compilation et non au démarrage. Sur une image conteneurisée, la variable se passe
  donc en argument de construction de l'image (`ARG` puis `ENV` d'un `Dockerfile`, `args`
  d'un service de build en Compose), jamais en simple variable d'environnement au lancement
  du conteneur.

### Favicons

- Les variantes vivent dans des sous-dossiers du dossier des favicons (`dev/`, `preview/`),
  à côté de la version de production.
- Elles se génèrent par substitution de la couleur de marque dans le SVG source, jamais en
  redessinant la forme.
- Quatre formats par variante : `favicon.svg`, `favicon-96x96.png`, `favicon.ico` (16, 32,
  48), `apple-touch-icon.png` (180).
- L'`apple-touch-icon` et les icônes de manifeste `maskable` restent à fond plein carré, sans
  coin arrondi : le système applique déjà son propre masque, un fond pré-arrondi double
  l'effet et rogne le dessin.
- Un favicon remplacé à URL fixe impose de bumper son paramètre `?v=` dans le même commit,
  sinon les visiteurs récurrents gardent l'ancien en cache.
- Conséquence assumée : les fichiers des variantes sont présents dans l'image de production,
  puisqu'ils sont committés, simplement jamais référencés par le HTML servi en production.

**Projet à marque multiple.** Le chemin se compose marque puis environnement,
`/favicons/<marque>/<environnement>/favicon.svg`, pour qu'une page thématisée garde sa
marque tout en montrant l'environnement qui la sert.
