# Pièges communs à tous les projets Solyzon

Ces pièges ont déjà été payés une fois, sur un projet ou sur un autre, et leur cause racine
ne dépend pas du projet. Ils voyagent donc avec le modèle plutôt que d'être redécouverts à
chaque dépôt.

**Ce fichier ne s'enrichit pas depuis un projet.** Une leçon nouvelle va dans `gotchas.md`,
qui est le fichier du projet. Si elle se révèle valable partout, elle remonte dans le dépôt
modèle et redescend ensuite dans tous les projets. C'est ce qui évite que quinze copies
divergent.

La plupart viennent de `zetelecom.fr`, qui est le projet le plus instrumenté et donc celui
qui a rencontré le plus de choses.

---

## Git et travail à plusieurs

### Ne jamais `git add` un dossier entier

Plusieurs développeurs et agents travaillent en parallèle, donc l'arbre de travail contient
toujours du travail qui n'est pas le sien.

Un `git add docs/superpowers/` a ainsi embarqué la spec d'un autre chantier dans un commit de
documentation. Le fichier n'avait rien à y faire, et son auteur en aurait perdu la paternité.

**Correctif.** Ajouter les fichiers explicitement, un par un. Jamais `git add -A`, jamais
`git add .`, jamais un dossier. Vérifier l'index avec `git diff --cached --name-only`
**avant** de committer et pas après. Se méfier aussi des renommages déjà indexés par
quelqu'un d'autre, qui remontent sans avoir été ajoutés par soi.

Le hook `PreToolUse` refuse maintenant `git add -A` et `git add .`, mais il ne peut pas
deviner qu'un chemin donné est un dossier, donc la vigilance reste nécessaire.

### Un travail en cours n'est presque jamais homogène

Ce qui reste dans l'arbre contient souvent plusieurs chantiers sans rapport, par exemple un
nettoyage, une optimisation et un helper de tests. On regroupe par intention réelle après
lecture des diffs, jamais par dossier ni par type de fichier.

### Un `git commit` annonce « aucune modification », et le dernier commit d'un autre agent porte nos fichiers

**Cause racine.** L'index git est partagé par tous les agents qui travaillent dans l'arbre, et
`git commit` sans chemin committe tout l'index, quel qu'en soit l'auteur. Le hook `pre-commit`
réindexe en plus chaque fichier indexé en entier après Prettier : un indexage partiel, bloc par
bloc, ne survit pas au hook. Un jeu de données indexé pendant qu'une suite de tests tournait est
ainsi parti dans le commit de feuille de route d'un autre agent.

**Correctif.** Toujours `git commit -m "…" -- <fichiers>` : seuls les chemins nommés partent,
quel que soit l'index. Un fichier nouveau se déclare par `git add -N <nouveau>` (intention
d'ajout), jamais par `git add` : un fichier pleinement indexé part dans le commit du premier
agent qui committe pendant que nos hooks tournent, une minute durant, alors qu'une intention
d'ajout n'apparaît pas dans `git diff --cached` et n'entre que dans le commit qui la nomme. Un
fichier qui porte deux changements se committe entier, ou attend que le second soit prêt.

### Le dernier commit ne compilait pas, donc aucune comparaison n'était possible

Pour savoir si six tests échouaient déjà avant le travail en cours, un worktree sur le commit
précédent a suffi à trancher : il ne compilait pas du tout, un fichier nouveau étant resté hors
de l'index. Le commit annonçait donc un état qui n'a jamais tourné.

**Correctif.** Avant de commiter, vérifier que les fichiers NOUVEAUX sont indexés :
`git status` les montre en `??`, et un `git add` sur les seuls fichiers modifiés laisse un
commit qui ne compile pas sans qu'aucun outil ne s'en plaigne. Et devant un test qui échoue,
mesurer sur le commit précédent avant de conclure qu'un changement l'a cassé.

### Le journal de l'app se perdait dès qu'un autre agent la relançait

Tout le diagnostic d'une app peut passer par son journal. Mais il ne se lisait qu'en lançant
le binaire depuis un terminal qui le redirige, et il mourait avec ce processus. Trois sessions
travaillaient sur le même dépôt : la capture a été perdue trois fois de suite, chaque fois au
milieu d'un diagnostic, parce qu'une autre session coupait l'app pour reconstruire.

**Ce qui est en place.** En DEBUG, quand la sortie n'est ni un terminal ni un fichier déjà
choisi par celui qui lance, l'app double `stdout` et `stderr` dans
`~/Library/Logs/<App>/journal.txt`. Lancée par `open`, par le Finder ou par n'importe quel
agent, elle laisse donc une trace lisible par tous ; lancée depuis un terminal, elle garde son
comportement d'avant.

**Le piège du premier essai.** `isatty` seul ne suffit pas : un agent qui redirige LUI-MÊME la
sortie vers son fichier voyait l'app la rediriger une seconde fois, son fichier restait vide,
et le journal commun était tronqué. Une sortie déjà posée sur un fichier RÉGULIER (`fstat`,
`S_IFREG`) est donc laissée telle quelle.

**Les deux sorties vont dans le MÊME fichier** : c'est leur entrelacement dans le temps qui
date les défauts. Les séparer reviendrait à perdre ce qui fait leur valeur.

**À retenir.** Quand plusieurs agents travaillent sur le même dépôt, un diagnostic qui vit
dans le processus d'un seul d'entre eux est perdu d'avance. La trace doit appartenir à l'app,
pas à celui qui l'a lancée.

---

## Branches, CI et renommages

### Pointer un workflow sur une branche qui n'existe pas encore éteint la CI en silence

**Symptôme.** Après avoir changé le déclencheur d'un workflow, plus rien ne tourne. Aucune
erreur, aucun avertissement, aucune croix rouge, simplement plus aucune exécution dans
l'onglet Actions. C'est bien pire qu'un échec, puisqu'un échec se voit.

**Cause racine.** GitHub n'a aucun moyen de savoir que `branches: [prod]` désigne une branche
qui n'existe pas, donc il se contente de ne jamais déclencher. Le cas se produit exactement
quand on aligne un dépôt sur une nouvelle convention de nommage avant d'avoir renommé la
branche, ce qui est l'ordre naturel des choses puisque le renommage demande souvent une action
manuelle.

**Correctif.** Renommer la branche **avant** de changer les déclencheurs, ou accepter la
fenêtre en sachant qu'elle existe et la refermer vite. Après tout changement de déclencheur,
pousser un commit de vérification et regarder qu'une exécution démarre vraiment.

Un second piège se cache dans le même bloc. Sur `pull_request`, la clé `branches` filtre la
branche **cible** de la demande de fusion et jamais la branche source, ce qui se lit à
l'envers la première fois. Filtrer par `types` plutôt que par `branches` évite la question et
fait tourner la CI sur toute demande de fusion, ce qui est le comportement qu'on veut.

### Renommer une branche par git ferme les demandes de fusion ouvertes

**Symptôme.** Après un renommage propre en apparence, les demandes de fusion qui visaient
l'ancienne branche ont disparu, et la branche par défaut du dépôt a changé toute seule.

**Cause racine.** Renommer en local puis pousser la nouvelle branche et supprimer l'ancienne
est, du point de vue du serveur, une création suivie d'une suppression. GitHub ferme alors
toute demande de fusion dont la base vient d'être supprimée, et il ne fait aucun lien entre
les deux branches.

**Correctif.** Passer par la fonction de renommage de l'interface GitHub, qui rebranche les
demandes de fusion ouvertes, conserve la branche par défaut et met en place les redirections.
Le local se répercute ensuite, et pas l'inverse.

```bash
git fetch origin
git branch -m <ancienne> <nouvelle>
git branch -u origin/<nouvelle> <nouvelle>
git remote set-head origin -a
```

### Un `AGENTS.md` recopié depuis `CLAUDE.md` diverge sans que rien ne le signale

**Symptôme.** Deux agents se comportent différemment sur le même dépôt, l'un applique une
règle que l'autre ignore, et personne ne comprend pourquoi puisque « les règles sont
écrites ».

**Cause racine.** Les deux fichiers portent le même contenu à quelques lignes près, et rien ne
vérifie qu'ils restent alignés. Une session édite celui qu'elle a chargé, l'autre reste en
arrière, et l'écart grandit à chaque passage. Sur le dépôt où c'est arrivé, trois blocs
avaient divergé sans que ce soit voulu pour deux d'entre eux.

**Correctif.** Faire d'`AGENTS.md` un simple **pointeur** vers `CLAUDE.md`, ce que fait le
dépôt modèle. Si un projet tient absolument au doublon, alors toute modification s'applique aux
deux dans le même geste, et un `diff CLAUDE.md AGENTS.md` avant commit dit si l'écart est bien
celui qu'on connaît.

### Un renommage global dans la documentation touche parfois du contractuel

**Symptôme.** Aucun, sur le moment, et c'est bien le problème. Le mot est remplacé partout, la
relecture ne voit rien, et l'écart avec ce qui a été signé ne se découvre qu'au litige.

**Cause racine.** Une partie de la documentation d'un projet client reprend des termes qui
viennent du devis ou des conditions générales. En remplaçant un vocabulaire technique dans
tout un dossier `docs/`, on réécrit sans le vouloir la description d'un engagement. Le cas
rencontré portait sur une recette de vingt-et-un jours livrée sur un environnement nommé dans
les conditions générales.

**Correctif.** Avant un renommage de vocabulaire, isoler les documents qui parlent du devis,
du contrat ou de la recette, et les laisser tels quels. Si le terme contractuel ne correspond
plus à ce qu'on livre, ce n'est pas une correction de documentation, c'est une question à
poser au client.

Un corollaire du même chantier. Avant de porter une phrase de documentation qui décrit un
comportement par environnement, **vérifier dans le code que cet environnement existe**. Une
doc annonçait une règle propre à deux environnements alors que le code n'en testait qu'un
seul, donc la phrase décrivait depuis des mois un environnement qui n'a jamais existé.

### `gitleaks-action` exige une licence payante dès que le dépôt appartient à une organisation

**Symptôme.** Le job d'audit échoue sur `missing gitleaks license. Go grab one at gitleaks.io`,
alors que rien n'a changé dans le dépôt et qu'aucun secret n'a fuité. Le message parle d'une
licence, ce qui laisse croire à un secret manquant ou à une erreur de configuration.

**Cause racine.** Depuis la version 2, **l'action** `gitleaks/gitleaks-action` est gratuite sur
un compte personnel et payante sur une organisation, et elle réclame un secret
`GITLEAKS_LICENSE`. Le **binaire** `gitleaks`, lui, reste libre et sans restriction. La
distinction ne se voit nulle part au moment où on écrit le workflow, et tout dépôt Solyzon
tombe dedans par construction puisqu'ils vivent tous sous une organisation.

**Correctif.** Appeler le binaire par son image Docker plutôt que l'action. Le scan porte sur
le même historique et ne demande aucune licence.

```yaml
- uses: actions/checkout@v6
  with:
    fetch-depth: 0

- run: docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:latest git /repo --redact
```

Le `fetch-depth: 0` n'est pas décoratif, sans lui gitleaks ne voit qu'un seul commit et un
secret introduit puis retiré passe inaperçu.

### Un `pnpm audit` enchaîné à la recherche de secrets la désarme sans le dire

**Symptôme.** Le job d'audit est rouge depuis des semaines à cause d'avis de sécurité sur des
dépendances transitives, et on découvre que la recherche de secrets n'a plus tourné une seule
fois depuis.

**Cause racine.** `pnpm audit` et `gitleaks` étaient deux **étapes du même job**. Une étape qui
échoue arrête le job, donc le premier avis venu, même mineur et même sans correctif
disponible, coupe la seule protection qui compte vraiment ici. Le job étant déjà rouge, plus
personne ne regarde pourquoi.

Le cas est d'autant plus vicieux que `pnpm audit` remonte l'arbre **transitif** complet. Un
framework en retard d'une version majeure suffit à produire une dizaine d'avis qu'aucune
montée de version mineure ne corrigera, donc l'échec est structurel et pas passager.

**Correctif.** Deux jobs distincts, `audit` et `secrets`, qui ne se conditionnent pas l'un
l'autre. La recherche de secrets doit tourner même quand l'audit de dépendances est au rouge,
puisque les deux ne protègent pas de la même chose. Le modèle est découpé ainsi.

Corollaire, un audit rouge se traite en cause racine, donc en montant la dépendance fautive,
et jamais en retirant le job ni en enchaînant un `|| true`. Si la montée demande un changement
de version majeure, ça devient une décision à poser à l'utilisateur, pas une case à cocher.

---

## Environnement et outillage

### `timeout` n'existe pas sur macOS

Le hook `SessionStart` bornait ses commandes réseau avec `timeout 15 git fetch`. Or `timeout`
est un utilitaire GNU, absent de macOS, donc la commande échouait **silencieusement**. Le hook
n'a jamais fetché ni pull, tout en annonçant « à jour avec origin » alors que le distant avait
de l'avance.

**Symptôme.** Un script qui semble ne rien faire, sans erreur visible, alors qu'il devrait
marcher.

**Correctif.** Ne jamais supposer qu'un utilitaire GNU existe sur macOS, ce qui vaut aussi
pour `sed -i` sans argument, `date -d` et `readlink -f`. Le hook du modèle réimplémente donc
son propre `with_timeout` en bash.

### Le nom d'un service Docker ne résout pas depuis l'hôte

**Symptôme.** Les tests qui touchent la base ou le cache échouent sur la machine avec un
`getaddrinfo for redis failed`, alors qu'ils passent dans le conteneur.

**Cause racine.** `redis` et `db` sont des noms de services, résolus par le DNS interne du
réseau Docker. Depuis l'hôte, il faut `127.0.0.1` et le port publié.

**Correctif.** Lancer la suite complète dans le conteneur. Sur l'hôte, ne garder que les
vérifications qui ne touchent à rien, donc les types, le lint et le format. Un `.env.local`
qui pointe sur `127.0.0.1` règle le cas où on veut vraiment tourner depuis l'hôte.

### Ne jamais installer une dépendance Node sur l'hôte quand `node_modules` est un volume

**Symptôme.** Un `pnpm add` sur la machine échoue, ou pire réussit et casse le conteneur au
démarrage suivant.

**Cause racine.** Le `compose.yaml` du modèle monte `dev_node_modules` par-dessus le source,
donc les modules sont installés **par et pour le conteneur**, souvent sur une autre
architecture. Le store de l'hôte et celui du conteneur ne sont pas le même.

**Correctif.** `docker compose exec app pnpm add <paquet>`. Si ça échoue sur un décalage de
store, ne pas contourner en installant sur l'hôte. On laisse la modification de
`package.json` et du lockfile, on prévient, et un redémarrage réconcilie.

### L'onglet du navigateur d'automatisation est occulté, ce qui fausse tout timing

Une seule cause racine, deux symptômes très différents, et les deux font perdre des heures.

**Cause racine.** L'onglet piloté par `claude-in-chrome` s'ouvre en arrière-plan, avec
`document.visibilityState` à `hidden`, et n'est jamais mis au premier plan. Chrome throttle
alors `requestAnimationFrame` jusqu'à l'arrêt complet, puis ralentit les timers.

**Premier symptôme, les animations se téléportent.** Un ticker basé sur rAF, ce qui est le cas
de GSAP, reste bloqué à la frame zéro, donc une transition de 300 ms se lit comme un saut avec
une seule écriture de style au lieu d'une par frame. Une boucle `requestAnimationFrame`
lancée à la main part en timeout sans jamais tourner.

**Second symptôme, l'HMR semble cassé.** Le client Vite rate son heartbeat, la connexion
WebSocket tombe toutes les 60 à 90 secondes, et la console enchaîne
`[vite] server connection lost` et de faux `Failed to fetch dynamically imported module`. Or
aucune requête n'échoue vraiment, le Resource Timing ne montre que des 200, et le terminal
Vite ne journalise rien.

**Correctif.** Ne jamais diagnostiquer une animation, un WebSocket ou l'HMR depuis cet
onglet. Les captures d'écran restent fiables puisque le paint fonctionne, c'est le timing qui
ne l'est pas. Pour l'animation, on pompe le ticker à la main avec `setTimeout`. Pour l'HMR, on
vérifie côté serveur ou avec un client hors navigateur. La validation finale se fait dans le
vrai navigateur.

### Deux serveurs de développement réécrivent le même cache

**Symptôme.** `Failed to fetch dynamically imported module` au chargement, interface figée,
alors que le fichier visé répond bien en 200.

**Cause racine.** Vite essaie le port suivant quand le sien est occupé, donc un second
démarrage part silencieusement à côté et réécrit le même `node_modules/.vite`. Le graphe que
détient le navigateur pointe alors vers des dépendances incohérentes, et l'échec d'un import
transitif remonte sur le module dynamique racine, ce qui désigne le mauvais coupable.

**Correctif.** Passer toujours par le script du projet, jamais par le binaire directement, et
garder `server.strictPort` activé comme seconde protection. Pour récupérer, arrêter l'unique
processus actif, vérifier que le port ne répond plus, **et seulement alors** supprimer
`node_modules/.vite`.

Un piège de diagnostic va avec. Si le module, tout son graphe et le CORS répondent en 200 mais
que seul le profil Chrome habituel échoue, il faut valider dans un profil vierge. Un
rechargement forcé ne vide pas toujours le cache de code persistant du profil.

### Une tâche longue s'arrête faute de place alors que rien d'autre n'écrit dans le dépôt

**Symptôme.** Une tâche lancée avec 14 Go libres s'arrête au milieu de son travail, faute de
place, sans que ses propres fichiers expliquent la chute.

**Cause racine.** Un `docker build` lancé en parallèle. Le disque de la machine virtuelle
Docker est un fichier du Mac (`~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`)
qui grossit pendant la construction et ne rend pas la place tout de suite, même après la
suppression d'une image. Supprimer des images dans Docker ne libère pas le disque du Mac.

Autre cause, la mémoire d'échange : un entraînement qui prend jusqu'à 60 % de la mémoire
unifiée, pendant qu'une pile Docker à 13 Go de mémoire tourne, dépasse les 26 Go du Mac, et
macOS écrit jusqu'à 11 Go d'échange dans `/System/Volumes/VM`, qui partage l'espace libre du
disque (`sysctl vm.swapusage`).

**Correctif.** Jamais de construction d'image ni de pile Docker chargée pendant une tâche
longue, un entraînement ou une évaluation par exemple. Lire `df -h` et la taille de
`Docker.raw` avant de lancer l'un ou l'autre.

### `sops exec-env` échoue sur un `.env.<environnement>.enc` avec « invalid character looking for beginning of value »

**Cause racine.** SOPS déduit le format d'un fichier de son extension, et `.enc` ne lui dit
rien : il tente du JSON. `sops -d` accepte `--input-type dotenv`, mais `sops exec-env` et
`exec-file` n'ont pas cette option, ils échouent donc sur tout `.env.<environnement>.enc`, quel
que soit leur contenu.

**Correctif.** Déchiffrer par `sops -d --input-type dotenv`, avec `--output-type json` pour un
programme ou `--extract '["NOM"]'` pour une seule valeur, qui rend aussi les valeurs
multilignes, comme une clé cosign, avec leurs vrais sauts de ligne.

### `grep -r` ne trouve rien dans des fichiers binaires alors que la chaîne y est

**Cause racine.** `grep` traite un fichier comme binaire dès qu'il y voit un octet nul, et sur
macOS il l'**ignore silencieusement**, y compris avec `-l`. Une recherche sans `-a` dans des
fichiers binaires renvoie donc zéro résultat et un code de retour 1, exactement comme si la
chaîne était absente, ce qui se lit à tort comme une preuve d'absence.

Mesure qui le montre : `grep -rl "Blink" <dossier>` ne renvoie rien, alors que
`LC_ALL=C grep -ac "Blink" <fichier>` compte onze occurrences dans un seul de ses fichiers.
C'est ce qui a produit la conclusion fausse « ces fichiers ne contiennent aucune chaîne », qui
a fermé une piste de diagnostic.

**Correctif.** Toujours `LC_ALL=C grep -a` sur des binaires, jamais `grep` nu. `LC_ALL=C` en
plus de `-a` parce qu'une locale UTF-8 fait échouer la mise en correspondance sur les octets
qui ne forment pas une séquence valide. Et devant un résultat vide sur un binaire,
**vérifier l'outil avant de conclure à l'absence** : chercher une chaîne dont on sait qu'elle
est présente sert de témoin.

### `pgrep -f` ne trouve pas un processus lancé par un chemin relatif

**Symptôme.** Un script cherchait une instance de l'app pour avertir avant de réassembler son
bundle, et l'avertissement n'est pas apparu alors que l'app tournait. Il sortait pourtant en
test, quand l'app venait d'être lancée depuis le Finder.

**Cause racine.** Le script cherchait l'instance par `pgrep -f "$BUNDLE/Contents/MacOS/<App>"`,
donc par son **chemin absolu**. Une app lancée depuis un terminal ouvert à la racine du dépôt
porte un chemin **relatif** dans sa ligne de commande, et `pgrep -f` compare la ligne de
commande telle quelle : aucune correspondance. L'avertissement manquait précisément dans le
cas qui l'a fait écrire, celui d'un lancement depuis le terminal pendant qu'on travaille.

**Correctif.** Chercher le **suffixe** `<App>.app/Contents/MacOS/<App>`, qui attrape les deux
formes. Un `pgrep -f` se teste sur un processus lancé comme on le lance vraiment, pas sur celui
qu'on vient d'ouvrir depuis le Finder pour l'occasion.

### Une fonction shell appelée dans `$( )` perd tout ce qu'elle écrit dans une variable

**Symptôme.** Une fonction copiait bien des centaines de fichiers dans le bundle, et pourtant
l'élagage de fin de construction les supprimait juste après, comme s'ils n'avaient jamais été
demandés.

**Cause racine.** La fonction rendait son compte sur la sortie standard, donc les appelants
l'écrivaient `note "copiés : $(copie ...)"`. Un `$( )` ouvre un **sous-shell** : les copies,
qui touchent le disque, survivaient ; les `ATTENDU+=(...)`, qui touchent une variable,
mouraient avec le sous-shell. La liste des ressources attendues arrivait donc incomplète dans
le shell principal, et l'élagage faisait exactement ce qu'on lui demande, sur une liste fausse.

**Correctif.** Le compte passe par une variable globale et la fonction s'appelle directement,
jamais dans une substitution. En shell, une fonction qui a un effet de bord sur une variable ne
peut pas, en plus, rendre une valeur par sa sortie standard. Les deux usages s'excluent, et
rien ne le signale : le code marche à moitié, du côté qu'on regarde le moins.

### `head -1` dans un script en `pipefail` : sortie 141, silencieuse

Un script s'arrêtait sans rien produire, en rendant 141 (128 + SIGPIPE).
`ls -t <dossier>/*.js | head -1` : `head` ferme le tuyau dès la première ligne lue, `ls` reçoit
SIGPIPE en écrivant la suite, et `set -o pipefail` fait sortir le script. Il suffit que la
liste dépasse le tampon du tuyau pour que cela arrive à chaque fois, là où une liste courte
tient dans le tampon et passe.

**Correctif.** `sed -n 1p`, qui lit tout le flux et ne referme rien.

### `zstd -d --rm` ignore les fichiers à suffixe inconnu sans rien décompresser, et sort en code 0

**Cause racine.** Le binaire `zstd` ne reconnaît que `.zst`, `.tzst`, `.gz`, `.tgz`, `.lzma`,
`.xz`, `.txz`, `.lz4` et `.tlz4` pour dériver le nom de sortie. Devant un autre suffixe, `.zs`
par exemple, il écrit `unknown suffix ... Ignoring` sur la sortie d'erreur, passe au fichier
suivant et **termine avec un code de retour 0**. Une boucle qui ne lit que le code de retour
croit donc avoir tout décompressé alors qu'elle n'a rien fait.

**Correctif.** Toujours donner le nom de sortie explicitement, un fichier à la fois :
`zstd -dq -f "$f" -o "${f%.zs}"`. Et vérifier le résultat en comptant les fichiers compressés
restants, jamais en se fiant au seul code de retour.

---

### `EACCES: permission denied` sur `public/storage` en production

Un téléversement ou une copie de fichier échoue en prod sur
`EACCES: permission denied, mkdir '/app/public/storage/<categorie>'`, alors que le même code
passe en local et que le dossier existe bien sur l'hôte.

**Cause racine.** Le stockage est un montage lié, `./public/storage` de l'hôte dans le
conteneur, et son arborescence appartenait à `root`. L'image du modèle tourne
sous l'utilisateur `node` (uid 1000), qui ne peut donc ni créer un sous-dossier ni écrire dans
ceux qui existent. Aucune erreur ne remonte tant que personne ne téléverse.

**Correctif.** Sur l'hôte, donner l'arborescence à l'uid du conteneur,
`chown -R 1000:1000 <chemin du volume>`. Un nouveau volume lié doit
naître avec ce propriétaire, sans quoi le premier écrit échoue.

---

### La policy ImageMagick d'une image Docker interdit de lire un PDF

**Symptôme.** `Imagick::readImage('fichier.pdf')` lève `not authorized`, alors que
l'extension est chargée et que Ghostscript est installé dans le conteneur.

**Cause racine.** `/etc/ImageMagick-6/policy.xml`, durcissement anti-ImageTragick hérité de
l'image de base, bannit tous les delegates et tous les coders avant de rouvrir une liste
étroite (`GIF`, `JPEG`, `PNG`, `WEBP`). Le delegate Ghostscript est donc coupé.

**Correctif.** Ne pas affaiblir la policy. Rastériser le PDF en appelant Ghostscript
directement en ligne de commande, arguments en tableau, puis traiter l'image obtenue.

---

## Base de données

### PostgreSQL n'indexe pas les clés étrangères

Contrairement à MySQL, PostgreSQL ne crée **aucun** index automatique sur une clé étrangère.
Un audit qui affirme qu'un index de clé étrangère est redondant a donc tort sur PostgreSQL, et
il faut vérifier avant de le suivre.

### Une violation SQL attendue invalide la transaction du test

**Symptôme.** Un test vérifie correctement une contrainte en attendant une exception, puis son
nettoyage ou la requête suivante échoue avec
`SQLSTATE[25P02]: current transaction is aborted`. Le même test passe sur SQLite ou MySQL.

**Cause racine.** Le test est enveloppé dans une transaction, et PostgreSQL invalide toute la
transaction après une erreur SQL, même si le framework de test attrape l'exception.

**Correctif.** Encapsuler la requête volontairement invalide dans sa propre transaction, ce
qui crée un point de sauvegarde dont le retour arrière restaure la transaction externe avant
que l'exception soit vérifiée.

### JSONB ne conserve pas l'ordre des clés d'un objet

**Symptôme.** Un test strict échoue sous PostgreSQL alors que les données attendues et reçues
sont identiques, seul l'ordre des clés diffère.

**Cause racine.** PostgreSQL normalise les objets `jsonb`, et l'ordre des clés d'un objet JSON
n'est de toute façon pas sémantique.

**Correctif.** Comparer en égalité profonde, jamais en identité stricte. L'ordre des
**tableaux** JSON, lui, reste significatif.

### Tester sur un autre moteur que la production finit toujours par coûter cher

**Symptôme.** Toute une suite de tests échoue sur une erreur de syntaxe SQL, avant même
d'exécuter la moindre ligne de test, alors que la migration passe très bien sur le serveur.

**Cause racine.** Les tests tournaient sur SQLite en mémoire pour aller vite, et SQLite ne
supporte ni `ALTER TABLE ADD CONSTRAINT`, ni `NULLS NOT DISTINCT`, ni la moitié de ce qu'on
écrit pour PostgreSQL. Une migration valide en production casse donc chaque test.

**Correctif.** Faire tourner les tests sur **le même moteur que la production**, ce que le
`compose.yaml` du modèle permet sans effort. Si un moteur plus léger est vraiment nécessaire,
il faut garder le DDL spécifique derrière un test de driver et porter l'invariant au niveau
applicatif, ce qui fait deux endroits à maintenir au lieu d'un.

### Ne jamais mettre un objet d'ORM en cache

**Symptôme.** Le code marche une fois puis casse au **second** passage, avec un objet vide ou
une erreur de type. Jamais au premier appel, ce qui rend le diagnostic déroutant.

**Cause racine.** Le premier appel retourne l'objet frais qui est en mémoire, donc tout va
bien, et le sérialise dans le cache au passage. Les appels suivants le désérialisent, et la
reconstruction d'un objet d'ORM depuis sa forme sérialisée est fragile.

**Correctif.** Ne mettre en cache que des **tableaux de scalaires** déjà projetés, et
reconstruire à la lecture. L'invalidation se branche sur les événements du modèle.

### Une exception dans un seeder arrête tous les seeders suivants

**Symptôme.** Une table à moitié remplie et plusieurs autres vides, ce qui pousse à chercher
un bug dans chacune.

**Cause racine.** Une exception non attrapée dans un seeder interrompt toute la chaîne. Le
symptôme trompe parce qu'il désigne les tables vides plutôt que celle qui a planté.

**Correctif.** Vérifier d'abord si un seeder antérieur dans la liste a échoué, avant de
chercher ailleurs.

---

### Index de texte incohérents ou tris inattendus après un changement d'image PostgreSQL

**Symptôme.** Après avoir changé l'image du service PostgreSQL (par exemple
`postgres:18-alpine` vers `pgvector/pgvector:pg18`), des requêtes triées ou filtrées sur une
colonne textuelle renvoient un ordre ou des résultats différents de ceux d'avant, sans erreur.

**Cause racine.** L'image Alpine est basée sur musl, l'image pgvector (comme la plupart des
images Debian) sur glibc. Les deux bibliothèques implémentent les collations différemment. Les
index construits sur des colonnes textuelles restent physiquement valides mais deviennent
incohérents avec le nouvel ordre de collation du serveur.

**Correctif.** Recréer la base et rejouer migrations et seed en développement, dump et
restore en production.

---

### La distance cosinus d'un vecteur nul vaut `NaN`, et une comparaison avec `NaN` est toujours fausse

**Symptôme.** Deux implémentations d'une même recherche vectorielle (une en SQL pgvector, une en
code applicatif) divergent sur un passage dont l'embedding est un vecteur nul : l'une l'exclut
en silence, l'autre le rend avec un score de `0.0`.

**Cause racine.** La similarité cosinus d'un vecteur nul est indéfinie. `1 - (embedding <=>
?::vector)` rend `NaN` sous pgvector, et `NaN >= minScore` est toujours faux, donc le passage
est exclu. Une implémentation qui protège la division par zéro en rendant `0.0` l'inclut au
contraire dès que `minScore <= 0`.

**Correctif.** Harmoniser sur l'exclusion : rendre `NaN` quand une norme est nulle, le filtre
`score >= minScore` l'exclut alors comme pgvector. Ne jamais neutraliser le `NaN` côté SQL
(`COALESCE`) pour inclure un passage dont la pertinence est indéfinie.

---

### Une recherche insensible à la casse compile alors que le provider Prisma est MySQL

**Cause racine.** `mode: 'insensitive'` sur un filtre `contains` ou `startsWith` n'existe que
pour PostgreSQL, SQL Server et MongoDB dans le client Prisma généré ; MySQL ne l'implémente
pas, et l'option ne figure même pas dans le typage du client pour ce provider. Le code
semblait pourtant fonctionner en local, parce que la collation par défaut de MySQL
(`utf8mb4_*_ci`, case insensitive) rend déjà les comparaisons insensibles à la casse sans le
moindre `mode`.

**Correctif.** Ne jamais écrire `mode: 'insensitive'` avec MySQL, une comparaison texte
standard suffit.

---

### Le nombre de connexions ouvertes vers MySQL double en production sans qu'aucune charge supplémentaire ne l'explique

**Cause racine.** Deux fichiers instanciaient chacun un `PrismaClient`, en partageant la même
clé sur `globalThis` pour éviter la recréation à chaud. Le motif classique ne peuple ce global
**que hors production**, pour éviter de garder une instance entre deux invocations
serverless. En développement les deux fichiers finissaient par converger vers la même
instance globale, mais en production chacun créait silencieusement son propre pool de
connexions, jamais partagé.

**Correctif.** Un seul module instancie `PrismaClient`, importé partout. Aucun autre fichier
n'en crée.

---

### Un nouveau modèle Prisma reste `undefined` dans le serveur de développement

Après l'ajout d'un modèle au schéma et l'application de sa migration, la page qui l'interroge
casse sur `Cannot read properties of undefined (reading 'findUnique')`. La migration est bien
appliquée, `prisma migrate status` est propre, le client a été régénéré.

**Cause racine.** Le serveur de développement charge `@prisma/client` une seule fois, au
démarrage. Régénérer le client réécrit `node_modules` mais le processus Next continue de
servir l'ancien module en mémoire, où le modèle n'existe pas. Le rechargement à chaud ne
recharge que le code applicatif, jamais une dépendance.

**Correctif.** Redémarrer le conteneur applicatif après `prisma generate`.

---

### `prisma migrate dev` échoue sur `UPDATE command denied` dans une base fantôme

`prisma migrate dev`, même avec `--create-only`, s'arrête sur
`UPDATE command denied to user '<app>' for table prisma_migrate_shadow_db_...`, en
pointant une migration ancienne qui n'a rien à voir avec le changement en cours.

**Cause racine.** Pour calculer le diff, Prisma rejoue toutes les migrations dans une base
fantôme qu'il crée à la volée. L'utilisateur MySQL du projet a le droit de créer cette base
mais ses privilèges de lecture-écriture sont accordés sur la seule base applicative, donc la
première migration qui contient une écriture de données y est refusée.

**Correctif.** Produire le SQL depuis la base vivante,
`prisma migrate diff --from-url "$DATABASE_URL" --to-schema-datamodel prisma/schema.prisma --script`,
le poser dans un dossier `prisma/migrations/<horodatage>_<nom>/migration.sql`, y ajouter le
rétro-remplissage éventuel, puis l'appliquer avec `prisma migrate deploy`, qui ne passe pas
par la base fantôme. Le `db push` documenté dans `conventions.md` reste le repli quand aucun
fichier de migration n'est attendu.

---

### Deux insertions concurrentes passent malgré une vérification préalable dans une transaction

**Symptôme.** Le service vérifie qu'une place est libre avant d'insérer, la vérification est
dans une transaction, et deux acceptations simultanées la remplissent quand même
au-delà de son quota.

**Cause racine.** MySQL est en `REPEATABLE READ`. Un `SELECT` ordinaire y lit un **instantané**
pris à l'ouverture de la transaction et ne pose aucun verrou, donc deux transactions lisent
le même état d'avant et décident toutes les deux que la place est libre. Le schéma classique
lire puis écrire n'est pas sérialisé par le seul fait d'être dans une transaction.

**Correctif.** Verrouiller la ligne parente en tête de transaction avec
`SELECT ... FOR UPDATE`. Toute décision concurrente sur une même
ressource passe par ce verrou.

---

### `pnpm db:migrate` vise la production alors que la configuration dit autre chose

**Cause racine.** `drizzle-kit` charge `.env` **lui-même, avant** d'évaluer
`drizzle.config.ts`. Or dotenv n'écrase jamais une variable déjà présente. Toute la logique de
priorité écrite dans le fichier de configuration est donc sans effet, les valeurs de `.env`
ayant déjà gagné.

Le symptôme est trompeur, dotenv affiche `injecting env (0)`, ce qui se lit comme « rien à
faire » alors que ça signifie « tout était déjà défini ». La commande part ensuite sur l'hôte
de production, et selon le réseau elle expire ou, bien pire, elle réussit.

**Correctif.** `config({ path: '.env', override: true })` dans `drizzle.config.ts`. Et avant
toute migration, vérifier la cible plutôt que la supposer :

```bash
node -e "require('dotenv').config({path:'.env'});console.log(process.env.DB_HOST+':'+process.env.DB_PORT)"
```

---

### Le journal drizzle référence un fichier SQL absent

**Cause racine.** `drizzle/` était dans `.gitignore`, donc les fichiers `.sql` n'ont jamais
été versionnés alors que `meta/_journal.json` l'était. Le journal annonce une migration dont
le fichier n'existe nulle part, et `drizzle-kit migrate` s'arrête sur
`No file ./drizzle/XXXX.sql found`.

**Correctif.** Réaligner le journal sur les fichiers réellement présents. Le dossier `drizzle/`
est désormais versionné, migrations comprises.

---

### Une écriture ou suppression de masse ne déclenche aucun événement du modèle

**Symptôme.** Un cache invalidé par un observer du modèle (sur `saved`, `deleted`) sert une
valeur périmée après une action qui a pourtant modifié la base. Aucune erreur.

**Cause racine.** Une mise à jour ou suppression appelée sur une requête (`update()`,
`delete()` du query builder) exécute du SQL direct sans hydrater de modèle : aucun événement,
aucun observer. Les changements de liaisons many-to-many (`sync()`, `attach()`, `detach()`)
n'émettent rien non plus sur le modèle parent.

**Correctif.** Passer par une instance, ou purger le cache explicitement après l'écriture de
masse ou le `sync()`. Pour un lot, désactiver les événements pendant la boucle et purger une
seule fois à la fin.

---

### Deux questions de sujets différents concaténées pour la recherche font dériver le vecteur vers rien

**Symptôme.** Une question claire retrouve des passages sans rapport, alors que la même
question posée seule retrouve les bons.

**Cause racine.** La recherche vectorisait les deux dernières questions concaténées, pour
donner du contexte à un enchaînement elliptique. Quand elles portent sur des sujets
différents, la requête combinée dérive vers un point qui ne correspond à aucune des deux,
quel que soit le modèle d'embedding.

**Correctif.** Chercher d'abord sur la seule question courante, et ne compléter avec la
fenêtre à deux questions que s'il reste des places. Les scores des deux recherches ne se
comparent ni ne se trient ensemble.

---

### Une recherche de complément limitée aux places restantes se prive elle-même du fragment qu'elle cherchait

**Symptôme.** Un enchaînement elliptique légitime répond hors sujet malgré une recherche de
complément.

**Cause racine.** La recherche de complément ne demandait que le nombre de places libres,
souvent une ou deux, donc avec une surcapture réduite d'autant. Son meilleur résultat est
souvent un fragment déjà retenu, qui occupe à lui seul la place, et le vrai complément,
deuxième de la liste, n'atteint jamais la déduplication.

**Correctif.** Interroger avec la même limite que la recherche principale, et ne borner au
nombre de places restantes que les fragments retenus après déduplication.

---

## Front, rendu et bundle

### Une étape d'assets qui ne copie pas les gabarits produit un CSS Tailwind presque vide

**Symptôme.** Le site répond, la feuille de style se charge en 200 avec le bon type MIME, et
pourtant plus aucune mise en forme n'est appliquée. La feuille est syntaxiquement correcte,
simplement beaucoup plus légère qu'avant.

**Cause racine.** Tailwind 4 découvre les classes en parcourant son répertoire de travail, sans
liste de sources à déclarer. Une étape de construction multi-niveaux qui ne recopie que le dossier
des feuilles, du genre `COPY src/assets ./src/assets`, ne lui donne aucun gabarit à lire. Il émet
alors les quelques classes qu'il trouve et rien d'autre, sans le moindre avertissement.

**Correctif.** Copier tout ce qui porte des classes dans l'étape d'assets, donc `COPY src ./src`,
ou déclarer explicitement les sources par `@source` dans le fichier d'entrée.

**Comment le voir.** Compter les classes du HTML servi qui n'ont aucune règle dans la feuille. Un
écart de plusieurs centaines ne laisse aucun doute, là où l'œil hésite encore.

### Un cache de CDN rend un déploiement invisible, et une URL de contournement le masque

**Symptôme.** Le serveur livre bien le fichier corrigé, tout le monde le vérifie et le confirme,
et le visiteur voit toujours l'ancienne version. Le site reste cassé alors que la chaîne de
déploiement est verte de bout en bout.

**Cause racine.** Cloudflare garde les fichiers statiques selon le `max-age` de l'origine, cinq
jours dans notre configuration par défaut. Le HTML, lui, n'est pas mis en cache, donc la page est
neuve et ses feuilles sont vieilles.

**Le piège de vérification, qui est le vrai coût.** Contrôler avec une URL du genre
`style.css?v=123` interroge une entrée de cache différente et renvoie systématiquement le fichier
neuf. La vérification passe, le site reste cassé, et on cherche la cause ailleurs pendant des
heures. **Toujours vérifier sur l'URL nue, et regarder `cf-cache-status` et `age`.**

**Correctif durable.** Verser une empreinte du fichier dans l'URL émise par le gabarit, et ne poser
un cache long que sur les URL qui la portent. Une URL nue retombe sur un cache court, ce qui couvre
les modules importés depuis le JavaScript et les images. Vider le cache à la main règle le cas du
jour et laisse le piège en place pour le déploiement suivant.

### Une transition sur `translate`, `scale` ou `rotate` ne s'anime pas en Tailwind v4

**Symptôme.** Un `hover:-translate-y-*` ou un `group-hover:scale-*` saute instantanément,
sans courbe, alors que la transition est bien posée et que la bordure ou l'ombre s'animent
normalement.

**Cause racine.** Tailwind v4 applique `translate-*`, `scale-*` et `rotate-*` par les
**propriétés CSS natives** `translate`, `scale` et `rotate`, et non plus par `transform`. Une
`transition-transform` ne couvre donc pas ces changements, puisque la propriété transitionnée
n'est pas celle qui change.

**Correctif.** Lister la vraie propriété, donc `transition-[translate,box-shadow]` pour un
soulèvement et `transition-[scale]` pour un zoom. Ça ne se voit pas au `getComputedStyle`,
puisque la transition est bien appliquée, elle ne porte simplement pas sur la bonne propriété.

### Un import statique dans le tronc commun fait fuiter tout son arbre dans chaque page

**Symptôme.** Le bundle principal est anormalement gros et il est chargé sur **chaque** page.
Mesuré une fois à 931 Ko bruts, ramenés à 313 Ko après correction, donc 97 Ko compressés au
lieu de 290.

**Cause racine.** Un module du tronc commun importait statiquement un layout de back-office,
ce qui y faisait basculer tout son arbre de dépendances, donc le centre de notifications, le
tiroir, les toasts et le client WebSocket. Chaque visiteur de la vitrine téléchargeait le
back-office.

Le découpage par page ne protège **pas** de ça, puisqu'il ne découpe que les pages et pas
leurs layouts.

**Correctif.** Charger chaque layout en import dynamique selon le préfixe du nom de page. Ça
se vérifie en une commande, en cherchant le nom d'une dépendance lourde dans le bundle
principal, qui doit renvoyer zéro.

### Une boucle de rendu infinie blanchie par un `setTimeout` ne déclenche aucun garde-fou

**Symptôme.** L'onglet crashe après quelques minutes sur n'importe quelle page, la mémoire
monte en continu, le ventilateur s'emballe, et il n'y a **aucune erreur**, ni serveur, ni
navigateur, ni le « Maximum update depth exceeded » qu'on attendrait.

**Cause racine.** Un hook renvoyait une fonction recréée à chaque rendu, un effet en
dépendait, l'effet programmait un `setTimeout` qui appelait un `setState`, ce qui relançait le
rendu, recréait la fonction et relançait l'effet. Comme le `setState` part d'un timer et non
du corps du rendu, React ne voit aucune chaîne synchrone et son garde-fou ne se déclenche
jamais. Un composant global propage le problème sur toutes les pages.

**Diagnostic.** Instrumenter `window.setTimeout` sur une page inactive et compter les appels
par seconde, ici environ quatre mille. Capturer `new Error().stack` dans l'enveloppe désigne
la ligne coupable.

**Correctif.** Mémoïser **à la source**, jamais en pansement sur chaque consommateur. La règle
générale qui en découle vaut d'être retenue, **toute valeur non primitive renvoyée par un hook
et destinée à figurer dans les dépendances d'un effet doit être stable entre les rendus**.

### Un composant qui capture ses nœuds une seule fois casse quand sa liste change

**Symptôme.** Un carrousel ou une roue animée disparaît, souvent avec les éléments empilés au
centre, après un rechargement partiel ou un changement de la liste qu'il affiche. Il
réapparaît au rechargement complet.

**Cause racine.** Le composant interroge le DOM une seule fois dans un effet dont les
dépendances n'incluent pas la liste, puis pilote ces nœuds impérativement. Quand la liste
change, React démonte et remonte les nœuds, mais l'effet ne se relance pas, donc l'animation
continue de positionner les **anciens** nœuds détachés pendant que les nouveaux n'obtiennent
jamais de transformation.

**Correctif.** Donner au composant une `key` React dérivée de l'identité de la liste, **au
point d'appel**, pour forcer un remontage propre. Ne pas mettre la liste dans les dépendances
de l'effet interne, un nouveau tableau à chaque rendu relancerait l'effet en boucle.

### Un HTML invalide fait abandonner l'hydratation

**Symptôme.** Du contenu qui apparaît après l'hydratation, ou qui se téléporte.

**Cause racine.** Le navigateur **répare** le markup rendu par le serveur avant que React le
lise, par exemple un `<p>` imbriqué dans un autre `<p>`. React trouve alors un DOM différent
de ce qu'il attendait, abandonne l'hydratation et régénère tout l'arbre côté client.

**Correctif.** Garder une imbrication HTML valide et vérifier l'absence de `Hydration failed`
dans un navigateur au profil neuf.

### Le rendu serveur ne supprime pas les chargements en navigation interne

**Symptôme.** « On est en rendu serveur, pourquoi cette page affiche-t-elle un squelette de
chargement ? »

**Cause racine.** Aucune, et c'est justement le piège. Le rendu serveur ne concerne que le
**premier** chargement d'une URL, donc un accès direct ou un rafraîchissement. Après
hydratation, l'application est une application monopage, et chaque clic est une requête qui ne
sollicite plus jamais le serveur de rendu.

**Test discriminant.** Le squelette n'apparaît **que** sur navigation interne. S'il apparaît
aussi au rafraîchissement, alors le rendu serveur est réellement en cause.

### Le réglage « réduire les animations » ne coupe pas une animation précise

**Symptôme.** Le réglage d'accessibilité coupe la plupart des animations mais en laisse une
tourner, souvent une animation continue.

**Cause racine.** Le variant `motion-reduce:` et les blocs `@media (prefers-reduced-motion)`
ne réagissent qu'à la **préférence système**, jamais à l'attribut posé par le panneau
d'accessibilité de l'application. Une coupure qui ne passe que par eux ignore donc le choix de
l'utilisateur.

**Correctif.** Vérifier la préférence en JavaScript par un hook qui combine la media query
système **et** l'attribut, ou dupliquer la règle CSS sous le sélecteur d'attribut.

### Rastériser un asset d'une autre origine teinte le canvas et fait échouer la lecture

**Symptôme.** Une détection qui lit les pixels d'un canvas meurt en silence en développement,
et seulement en développement.

**Cause racine.** L'asset est servi par le serveur de développement, donc sur une origine
différente de la page. Le dessiner dans un canvas le teinte, et `getImageData` lève alors une
exception.

**Correctif.** Poser `crossOrigin="anonymous"` sur l'image, le serveur de développement
renvoyant les en-têtes nécessaires. En production sur un CDN, c'est au CDN de les renvoyer.

### Pièce miroir en three.js : jamais de BackSide, le moteur inverse déjà l'enroulement

**Cause racine.** Une pièce miroir (enveloppe d'échelle x = -1) était rendue creuse et à moitié
transparente. Sa matière avait été passée en `THREE.BackSide` en raisonnant « l'échelle
négative inverse les faces, il faut dessiner l'autre côté ». Mais three.js corrige DÉJÀ tout
seul le sens d'enroulement des objets dont la matrice monde a un déterminant négatif :
`frontFaceCW = matrixWorld.determinantAffine() < 0` dans `renderBufferDirect`, qui bascule
`flipSided` dans `setMaterial`. BackSide par-dessus = double inversion : seules les faces
intérieures se dessinaient, d'où une pièce vue de l'intérieur, trouée selon l'angle.

**Correctif.** Une pièce sous enveloppe miroir garde sa matière normale, la même instance que
la pièce d'origine. Preuve : les deux meshes en scène, `side: 0` (FrontSide) des deux côtés,
même uuid de matière, déterminant négatif seulement du côté miroir, rendu plein sous tous les
angles.

### Une démarcation droite entre deux teintes d'un même aplat : le wrap du sampler de normales

**Symptôme.** En gros plan, une ligne droite sépare deux zones d'un même aplat de teintes
légèrement différentes : une plaque plus pâle couvre une moitié du modèle.

**Cause racine.** L'aplat étant uniforme, la différence de teinte ne pouvait venir que de
l'éclairage, donc de la carte de normales. Mesure décisive : la marche nette du canal rouge
(214 vers 207 sur un pixel) disparaît quand on retire la carte de normales, et disparaît aussi
quand on passe son wrap en répétition. Les UV du modèle couraient en u de 0,019 à 1,981
(miroir autour de u = 1), et le sampler source déclarait la répétition. Or
`new THREE.Texture()` reste sur le défaut de three.js, ClampToEdge : toute la moitié dont u
dépasse 1 lisait la colonne de bord de la texture, normales figées, d'où la plaque pâle à
frontière droite exactement sur l'axe u = 1.

**Correctif.** Lire les modes d'adressage U et V du sampler source et les appliquer aux cartes
de normales (`RepeatWrapping` ici). Un matériau ne se résume pas à ses noms de texture : le
sampler porte des réglages (adressage, filtrage) qui font partie de la donnée. Quand deux
zones d'un même aplat n'ont pas la même teinte, chercher les normales, pas la couleur.

---

### Une variable d'environnement du bundle client est figée au build, pas au démarrage du conteneur

**Symptôme.** La variable est bien définie au lancement du conteneur, et le code exécuté par le
navigateur garde la valeur de la construction, ou rien.

**Cause racine.** Next.js inline les variables `NEXT_PUBLIC_*` dans le bundle JavaScript au
moment du `next build`, pas au démarrage du serveur. Une variable passée en `environment` ou
`env_file` à un conteneur déjà construit arrive bien dans `process.env` côté serveur, mais
jamais dans le code du navigateur, figé une fois pour toutes à la construction de l'image.

**Correctif.** La valeur se passe en `ARG` du Dockerfile, réexportée en `ENV` avant le build,
et en `args` du service dans le Compose de production. Rebuild obligatoire si la valeur change,
un redémarrage du conteneur ne suffit pas.

---

### Un `gsap.from` tué au démontage rejoue une animation invisible, StrictMode fait apparaître l'élément d'un coup

**Symptôme.** Une animation d'entrée `gsap.from` ne se voit pas en développement. L'élément
reste à sa valeur de départ (opacité 0, échelle réduite) pendant toute la durée annoncée, puis
apparaît brutalement à la fin. Le tween progresse pourtant, `tween.progress()` avance de 0 à 1.

**Cause racine.** StrictMode monte chaque composant deux fois en développement. Le premier
effet crée le `from`, qui pose immédiatement sa valeur de départ ; le nettoyage appelle
`tween.kill()`, qui laisse l'élément à cette valeur de départ. Le second effet crée alors un
`from` dont la destination est la valeur courante, c'est-à-dire la valeur de départ : il anime
de 0 vers 0, et le `clearProps` de fin rend l'élément d'un coup.

**Correctif.** `tween.revert()` au nettoyage, jamais `kill()`, pour un `from` ou une timeline
qui en contient. `revert()` restaure l'état d'avant le tween.

---

### Un dialog contrôlé n'exécute jamais les effets de bord posés dans `onOpenChange`

**Symptôme.** Dans un dialog ouvert par un état du parent (`<Dialog open={open}>`), un effet de
bord branché sur `onOpenChange` (mise en pause du défilement doux, par exemple) ne se produit
pas, alors que le même dialog ouvert par son `DialogTrigger` se comporte correctement.

**Cause racine.** Radix n'appelle `onOpenChange` que lorsque le dialog lui-même demande un
changement d'état (déclencheur, Échap, clic extérieur). Quand le parent passe `open` à `true`,
le callback ne part jamais.

**Correctif.** Piloter l'effet de bord depuis un effet sur la valeur `open`, et libérer dans le
nettoyage, qui couvre aussi le démontage d'un dialog encore ouvert.

---

### Une container query ne style jamais l'élément qui la porte

**Symptôme.** Un élément porte `@container/nom` et des utilities `@min-[Xpx]/nom:*`. Les classes
sont dans le DOM, la règle est dans le CSS servi, et rien ne s'applique à cet élément, alors que
ses descendants réagissent.

**Cause racine.** `container-type` définit un contexte de requête pour les descendants. Un
élément ne peut pas se requêter lui-même, sa propre taille étant ce qui est mesuré.

**Correctif.** Les styles conditionnés vont sur un enfant, et ce qui doit valoir pour le
container s'écrit sans variante.

---

### `offsetLeft` d'une carte de carrousel n'est pas relatif au conteneur scrollable

**Symptôme.** Un carrousel à défilement snap ne centre pas sa carte active, et le décalage
semble s'accumuler à chaque swipe.

**Cause racine.** `offsetLeft` est mesuré depuis l'`offsetParent`, le premier ancêtre
positionné. Un scroller en `overflow-x: auto` sans `position: relative` n'en est pas un : la
mesure part d'un ancêtre qui n'a ni les mêmes bords ni le même padding. Un padding en
pourcentage aggrave l'écart, il se calcule sur la largeur du parent.

**Correctif.** Ne pas mélanger les référentiels : mesurer l'écart à l'écran et l'ajouter au
scroll courant.

```ts
const offset = card.getBoundingClientRect().left + card.getBoundingClientRect().width / 2
    - (el.getBoundingClientRect().left + el.clientWidth / 2);
el.scrollTo({ left: el.scrollLeft + offset });
```

---

### Deux slides jointives laissent une bande fantôme de l'image précédente

**Symptôme.** Pendant la transition d'un carrousel plein cadre, une fine bande grisâtre de
l'image précédente reste visible au bord et paraît figée un instant.

**Cause racine.** Les slides sont des calques `absolute inset-0` translatés de multiples exacts
de la largeur, leurs bords se touchent pile et la position animée est fractionnaire. Le pixel de
la jointure reçoit une couverture partagée entre les deux slides, peintes l'une après l'autre
sur le fond : une part du fond transparaît et dessine une colonne fantôme, que la fin lente
d'un ease-out laisse collée au bord.

**Correctif.** Arrondir la translation à la grille de pixels
(`Math.round(x * devicePixelRatio) / devicePixelRatio`), élargir chaque slide d'un pixel pour
que les calques se recouvrent, et empiler au-dessus la slide la plus proche du centre.

---

### Un composant qui décide son balisage à la mesure change de contenu visiblement à l'hydratation

**Symptôme.** Un bandeau ou une liste affiche une structure au premier rendu, puis bascule
visiblement sur une autre juste après (rendu statique centré puis piste dupliquée en boucle, ou
l'inverse).

**Cause racine.** Le composant décidait son balisage (nombre de nœuds, structure des enfants)
dans un effet qui mesurait le DOM (`ResizeObserver`, `getBoundingClientRect`) ou lisait une
media query (`useReducedMotion`, `useMediaQuery`). Le serveur ne connaît ni la largeur du
viewport ni l'état système : il produit un balisage par défaut, le premier rendu client le
reproduit pour que l'hydratation matche, puis l'effet corrige l'état et change le DOM après coup.

**Correctif.** Le balisage ne dépend que des props et données connues au rendu, identiques sur
serveur et client (le nombre d'éléments plutôt qu'une largeur mesurée). Le mouvement peut
rester en CSS ou dans une boucle qui met à jour un `transform`, tant qu'il n'ajoute ni ne
retire aucun nœud. Lire une media query pour décider si un effet s'attache ne pose aucun
problème.

---

### Une couleur lue par `getComputedStyle` n'est pas en `rgb()`

**Symptôme.** Un code qui lit une couleur calculée (`getComputedStyle(el).backgroundColor`) et
la parse avec une regex `rgba?(...)` ne trouve rien sur certains fonds, sans erreur.

**Cause racine.** Depuis CSS Color 4, une couleur calculée garde l'espace de sa déclaration. Des
tokens en `oklch` ressortent en `oklch(0.445 0.1202 249.9)`, jamais en `rgb()`. Seules les
couleurs déclarées en hex ou `rgb()` ressortent en `rgb()`.

**Correctif.** Ne jamais parser une couleur CSS à la main ; la faire convertir par le
navigateur, en la peignant dans un canvas 1×1 et en relisant le pixel, ce qui couvre `oklch`,
`oklab`, `color()` et l'alpha.

---

### Un `mask-image: url(...)` posé en style inline ne s'applique pas

**Symptôme.** Un fond découpé par un SVG importé (`maskImage: \`url(${shape})\``) s'affiche en
rectangle plein, sans erreur console, et `getComputedStyle(el).maskImage` renvoie `none`.

**Cause racine.** Sous la limite `assetsInlineLimit`, Vite livre le SVG en
`data:image/svg+xml,…` avec des apostrophes dans le contenu. Un `url()` CSS sans guillemets ne
tolère pas d'apostrophe : la déclaration entière est invalide et ignorée. Le même code marchait
tant que le fichier était servi par son chemin.

**Correctif.** Toujours écrire `url("${shape}")`, guillemets doubles compris (Vite encode les
guillemets doubles du SVG, jamais les apostrophes).

---

### Un panneau à fermeture « clic extérieur » se referme dans le clic qui l'ouvre, ou n'ouvre pas son voisin

**Symptôme.** Un widget flottant se ferme au clic hors de lui via un listener sur `document`.
Avec `pointerdown`, cliquer la pastille d'un voisin ferme le panneau ouvert mais n'ouvre pas le
voisin ; avec `click`, la pastille ne s'ouvre plus du tout.

**Cause racine.** Les widgets vivent dans une pile flex, la géométrie change dès qu'un panneau
se rétracte. Avec `pointerdown`, la fermeture démarre à l'appui, la pastille voisine glisse sous
le curseur et le `click` au relâchement ne tombe plus sur elle. Avec `click`, React applique le
`setState` d'un événement discret avant que l'événement n'atteigne `document` : la pastille est
démontée, `container.contains(event.target)` renvoie faux, et le panneau qui vient de s'ouvrir
se referme.

**Correctif.** Écouter `click`, et tester l'appartenance avec
`event.composedPath().includes(container)`, jamais `contains(event.target)`. Le chemin est figé
au dispatch et contient encore le conteneur même si la cible a été démontée.

---

### Un glissement de carrousel échoue une fois sur quatre au doigt, jamais à la souris

**Symptôme.** Au doigt, un carrousel refuse de glisser de façon intermittente, une tentative sur
trois ou quatre. Rien en console, parfait à la souris et impossible à reproduire au simulateur
tactile des outils de développement, qui trace des lignes droites.

**Cause racine.** L'axe du geste était arrêté sur le premier `pointermove` franchissant le
seuil, en comparant `|dx|` à `|dy|`. La pulpe du doigt roule en se posant, et un balayage
horizontal démarre souvent par quelques pixels verticaux : l'axe se verrouille sur `y` et le
glissement est abandonné. Un seuil testé en `Math.max(|dx|, |dy|)` aggrave le biais.

**Correctif.** Ne trancher que lorsqu'une direction franchit le seuil et domine l'autre d'un
facteur net, en laissant l'axe indécis sinon, dans une fonction partagée par tous les composants
à glissement. Un `setPointerCapture` sur un conteneur scrollable reçoit un `pointercancel`
d'iOS : ne capturer qu'à la souris. Un bug « une fois sur N » au doigt désigne une décision
prise sur un seul échantillon d'un flux bruité.

---

### Une logique placée dans `requestAnimationFrame` ne s'exécute plus en arrière-plan

**Symptôme.** Des compteurs ne s'incrémentent pas quand l'onglet est masqué, et l'état est
désynchronisé au retour au premier plan.

**Cause racine.** `requestAnimationFrame` est totalement suspendu quand l'onglet est masqué.

**Correctif.** La logique métier se rattache à un événement qui continue en arrière-plan, comme
`timeupdate` d'un élément audio, émis à cadence réduite. `requestAnimationFrame` est réservé à
l'animation d'interface, et arrêté dès que `document.hidden` est vrai.

---

### `hls.js` ne fonctionne pas sur iPhone avant iOS 17.1

**Symptôme.** Rien ne se lit sur un iPhone ancien, alors que tout va bien sur ordinateur.

**Cause racine.** `hls.js` s'appuie sur les Media Source Extensions, absentes de Safari iOS
avant la 17.1.

**Correctif.** Deux chemins de lecture sur le même élément : `hls.js` là où les MSE existent,
HLS natif (`audio.src = '…/playlist.m3u8'`) sur iOS. Le lecteur natif iOS ne permet pas
d'ajouter d'en-tête HTTP à sa requête de clé de déchiffrement : le jeton voyage dans l'URI de
la clé au sein de la playlist, jamais dans un en-tête.

---

### Une requête `fetch` lancée pendant `pagehide` n'arrive pas

**Symptôme.** Les remontées envoyées à la fermeture de l'onglet se perdent.

**Cause racine.** Le navigateur abandonne les requêtes en vol quand la page se décharge.

**Correctif.** `navigator.sendBeacon()` pour toute remontée sur `visibilitychange` vers
`hidden` et sur `pagehide`, seul mécanisme dont la livraison est garantie.

---

### Un token `@theme` marche en classe Tailwind mais reste vide en `var()` depuis un SCSS

**Symptôme.** Un token ajouté au bloc `@theme`, puis consommé par `var(--color-mon-token)` dans
une feuille SCSS, ne peint rien. Aucune erreur, l'inspecteur montre une déclaration sans valeur.
La même valeur en classe utilitaire fonctionne.

**Cause racine.** Tailwind 4 n'émet que les variables du bloc `@theme` dont il détecte un usage
dans les sources qu'il scanne. Les feuilles SCSS importées par un composant n'en font pas
partie, donc le token est éliminé et la variable jamais déclarée.

**Correctif.** Consommer le token par sa classe utilitaire sur l'élément plutôt que par
`var()`. Devant une couleur qui ne s'applique pas, chercher la variable dans la feuille
réellement servie avant de suspecter la cascade.

---

### Un menu déroulant ne s'ouvre pas dans une boîte de dialogue

**Cause racine.** Radix portalise le panneau d'un `Select` dans `body`, où il devient un
frère de la boîte de dialogue et non son descendant. Les deux couches se comparent donc par
`z-index` seul. Le voile et le contenu du dialogue étaient posés à `110`, alors que le
panneau retombait à `100` par la règle `[data-radix-popper-content-wrapper]` de la
feuille globale, ou à `50` par sa classe utilitaire quand le `Select` est en position
`item-aligned`. Le panneau s'ouvrait bel et bien, mais derrière le voile, invisible et non
cliquable, et le clic suivant le refermait. Rien ne le distingue à l'écran d'un menu qui
refuse de s'ouvrir, ce qui envoie chercher la cause du côté du gestionnaire de clic.

**Correctif.** Une échelle d'empilement en tokens dans la feuille globale, `--z-modal: 110`,
`--z-popover: 120`, `--z-progress: 200`, où les couches flottantes passent toujours devant
les couches modales. Devant un menu, une infobulle ou un sélecteur de date qui « ne s'ouvre
pas » dans un dialogue, comparer les `z-index` des deux portails avant de soupçonner le
gestionnaire d'événement.

**Piège dans le piège.** Radix pose `z-index: auto` en style en ligne sur
`[data-radix-popper-content-wrapper]`. Aucune classe utilitaire ne l'atteint, seul un
`!important` en CSS le surcharge.

---

### Une page perd tout son rendu serveur à cause d'une seule image

**Symptôme.** Une page rendue par le serveur n'expose aucune balise `<img>` dans son HTML,
alors que son texte y est bien présent. Rien n'échoue visiblement, la page finit par
s'afficher correctement dans le navigateur, et seul le journal du serveur porte un
`Invalid src prop (...) hostname "..." is not configured under images in your
next.config.js`.

**Cause racine.** `next/image` **lève** quand l'hôte d'une URL distante n'est pas déclaré
dans `remotePatterns`. L'exception se produit pendant le rendu serveur de l'arbre client, et
Next se rabat alors sur un rendu navigateur pour la page entière. Une seule image
saisie par un administrateur suffit donc à annuler le rendu serveur de toute la page, y
compris son image LCP.

Allowlister les hôtes un par un ne règle rien : les URL d'images viennent en partie de la
saisie d'un administrateur. Et
un `hostname: '**'` ferait de l'optimiseur un proxy ouvert.

**Correctif.** Une fonction `bypassesImageOptimizer` répond à la seule
question « l'optimiseur accepterait-il cette URL ? », en relisant la liste
`remoteImagePatterns` que `next.config.ts` consomme aussi. Toute image dont la source vient
de la base se rend avec `unoptimized={bypassesImageOptimizer(src)}` : l'hôte inconnu est
servi tel quel au lieu de faire planter la page.

---

### Un écart d'hydratation sur un `transform` que le serveur et le client calculent pourtant pareil

**Symptôme.** React signale `A tree hydrated but some attributes of the server rendered HTML
didn't match the client properties`, et le diff ne montre qu'une différence de précision :
`rotate(-49.0253deg)` côté serveur contre `rotate(-49.02530962309245deg)` côté client. La
valeur vient d'un générateur pseudo-aléatoire à graine fixe, donc les deux côtés calculent
bien le même nombre.

**Cause racine.** Chrome tronque la précision des angles en relisant l'attribut `style`. Le
serveur écrit le flottant complet dans le HTML, le navigateur le reparse et le ressert
arrondi, et React compare sa propre chaîne à celle relue du DOM. La graine n'y est pour rien,
c'est la sérialisation CSS qui diffère. Le piège vaut pour toute valeur à forte précision
posée dans un style en ligne, pas seulement une rotation.

**Correctif.** Arrondir à la source, avant que la valeur n'entre dans le style. Dans
`ChristmasGarland.tsx`, l'angle est stocké en `Number(rotation.toFixed(2))` au moment où le
point d'attache est construit. Deux décimales se relisent à l'identique, et l'écart disparaît.

---

### `next/image` avertit sur `images.localPatterns`, et le déclarer casse les autres images

**Symptôme.** La console de développement répète
`Image with src "/api/storage/avatars?id=..." is using a query string which is not configured
in images.localPatterns. This config will be required starting in Next.js 16.`

**Cause racine.** Next avertit dès qu'une source locale porte une chaîne de requête tant que
`images.localPatterns` n'est pas déclaré. Le piège est dans le correctif : la liste est
facultative, mais une fois déclarée elle devient contraignante, et tout chemin local qu'elle
ne couvre pas fait lever `next/image` au lieu de simplement échouer. Le champ `search` d'un
pattern se compare à l'identique, donc il ne se déclare pas pour une requête dont la valeur
varie, `?id=<uuid>` par exemple, et s'omet pour toutes les accepter.

**Correctif.** Une liste `localImagePatterns` dans un module de configuration, que `next.config.ts`
consomme comme il consomme déjà `remoteImagePatterns`. `bypassesImageOptimizer` suit la même
liste pour les chemins servis par l'application, de sorte qu'un chemin local absent de la
liste se rende tel quel au lieu de faire tomber la page.

---

### Trois images par seconde après l'ajout d'un halo en `drop-shadow`

**Symptôme.** La page devient injouable, l'inspecteur montre des repaints permanents, alors
que le seul ajout est un `filter` décoratif sur une quinzaine d'images.

**Cause racine.** Un empilement de `drop-shadow` dont le plus large monte à 293 pixels de
flou force le compositeur à recalculer une surface énorme autour de chaque élément. Posé sur
des éléments qui portent en plus une animation, le filtre est réévalué à chaque image.

**Correctif.** Le halo se calcule dans le shader, où il ne coûte qu'une passe rendue une
seule fois. Le `filter` CSS reste acceptable sur un élément isolé et immobile.

---

### Un glisser au pointeur ne reçoit que deux `pointermove`, puis plus rien

Un geste de traction maison, `pointerdown` puis suivi des `pointermove` sur `window`,
s'arrête net après un ou deux événements, sans erreur. Un compteur posé en phase de capture
sur `window` confirme que les événements n'arrivent plus, alors que le même geste sur le
fond de page en reçoit un flot continu. Le glisser de framer-motion présente le même
symptôme, et `setPointerCapture` sur l'élément saisi n'y change rien.

**Cause racine.** L'élément saisi est un lien ou contient une image, et les deux sont
nativement déplaçables. Dès le premier mouvement, le navigateur ouvre un glisser-déposer
natif, qui prend la main sur le pointeur et cesse d'émettre les `pointermove`. Un
`draggable={false}` sur le lien ne suffit pas si une image vit à l'intérieur.

**Correctif.** Annuler `dragstart` pendant le geste, avec un écouteur sur `window` qui fait
`preventDefault` tant qu'une prise est en cours.

---

### Un `position: sticky` qui ne colle jamais, alors que la propriété est bien appliquée

Une colonne latérale en `lg:sticky` avec un `top` calculé défile avec la page et disparaît en
haut. L'inspection ne montre rien d'anormal, `position` vaut bien `sticky` et le `top` est
correct, mais le rectangle de l'élément suit le flux comme s'il était en `static`.

**Cause racine.** `body` portait `overflow-x: hidden !important`. Fixer un axe fait passer
l'autre à `auto`, ce qui transforme `body` en conteneur de défilement. Un descendant en
`sticky` se cale alors sur `body` et non sur la fenêtre, et comme le défilement réel se passe
sur `html`, l'élément ne se décolle jamais de sa position dans le flux.

**Correctif.** Le débordement horizontal se coupe sur `html` uniquement, où il n'empêche pas
le `sticky`. La protection contre le défilement
horizontal reste entière.

---

### Le middleware ne s'exécute jamais, sans la moindre erreur

Les gardes d'authentification laissaient passer tout le monde, une page protégée répondait 200 à
un visiteur sans session au lieu de rediriger vers la connexion. Aucune réponse ne portait
d'en-tête `Set-Cookie`, donc le cookie de locale n'était jamais posé et le layout racine
servait `<html lang="fr">` sur toutes les pages anglaises. Rien dans les journaux, ni au
démarrage ni à la requête.

**Cause racine.** Le fichier vivait à la racine du dépôt. Next ne lit le middleware qu'à un
seul endroit, à côté du dossier `app`, donc dans `src/` dès lors que le projet a un dossier
`src`. Un `middleware.ts` posé ailleurs est un fichier mort que rien ne signale, ni le build,
ni le lint, ni les types.

**Correctif.**
`git mv middleware.ts src/middleware.ts`. Le symptôme qui identifie le
problème en une commande, `curl -sD- -o /dev/null http://localhost:3000/fr` ne renvoie aucun
`Set-Cookie` alors que le middleware en pose un.

**À surveiller après l'avoir réactivé.** Un middleware dormant laisse passer des
incohérences qui se réveillent d'un coup. Par exemple une route protégée que le plan de site proposait à
l'indexation, et qui se met à rediriger les robots vers la connexion.

---

### Un carrousel enchaîne vingt diapositives d'un coup au retour sur l'onglet

En quittant le navigateur puis en y revenant, tous les carrousels de la page défilaient à
toute allure pendant quelques secondes avant de retrouver leur rythme.

**Cause racine.** Un `setInterval` laissé tourner pendant que l'onglet dort. Le navigateur
mobile gèle la page, retient les battements, puis les délivre en rafale au réveil. Chaque
battement relance une transition du carrousel, d'où la course. Même mécanique pour toute
boucle d'animation qui calcule son temps depuis une origine fixe, l'écart accumulé se
rattrape en un seul pas.

**Correctif.** Deux réflexes qui valent pour toute animation autonome. Couper la minuterie
sur `visibilitychange` quand `document.hidden` est vrai, et la relancer au retour. Plafonner
le pas de temps d'une boucle `requestAnimationFrame` plutôt que de dériver les secondes d'une
origine posée au démarrage.

---

### Une page publique télécharge deux mégaoctets de polices

**Symptôme.** Une page tire des dizaines de fichiers de police pour plus de 2 Mo, alors
qu'elle n'affiche que deux familles.

**Cause racine.** Deux choses se cumulaient. Les polices locales étaient déclarées en `.ttf`,
un format non compressé, là où `woff2` divise par trois pour les mêmes glyphes. Et
`next/font` précharge par défaut **toutes** les graisses déclarées d'une famille dès que le
module est importé dans le layout, qu'elles servent ou non sur la page.

**Correctif.** Tout convertir en `woff2`, et poser `preload: false` sur les familles
décoratives, celles qui ne servent qu'à un bloc de marque. Le `@font-face` reste déclaré,
le navigateur ne télécharge que le fichier réellement rendu. Les deux familles du texte
courant gardent leur préchargement.

---

### Safari iOS rend le texte d'un élément `zoom` à sa taille pleine

**Symptôme.** Une barre mise à l'échelle par `zoom: 0.55` s'affiche correctement sur toutes
ses formes, mais son texte sort environ 1,8 fois trop gros sur iPhone, soit exactement
`1 / 0.55`. Les libellés débordent de leur cadre et passent à la ligne. Aucun navigateur de
bureau ne reproduit le défaut, WebKit de bureau compris.

**Cause racine.** WebKit agrandit automatiquement le texte des blocs plus larges que la
fenêtre. Un `zoom` inférieur à 1 rend la mise en page interne `1 / zoom` fois plus large que
l'écran, donc WebKit applique ce même facteur au texte et annule le zoom, mais sur lui seul.
`-webkit-text-size-adjust` n'y change rien, ni à la racine ni sur l'élément zoomé, quelle que
soit sa valeur.

**Correctif.** Ne pas passer par `zoom` là où le défaut se manifeste. Les cotes de la maquette
se multiplient par une variable, `calc(196 * var(--nav-unit))`, ce qui fait tenir la mise en
page dans la largeur réelle et donne au texte une taille calculée honnête. Trois conséquences à ne pas oublier, un SVG dont
les coordonnées viennent de la maquette a besoin d'un `viewBox` pour suivre l'échelle, une
translation animée doit être multipliée par la réduction, et les utilitaires en `rem` des
sous-composants cessent d'être réduits, ce qui oblige à garder `zoom` là où ils vivent.

---

### Un `<label>` englobant n'étiquette pas un `Switch`

**Symptôme.** L'audit d'accessibilité signale un contrôle sans nom accessible, alors que le
`Switch` est bien entouré d'un `<label>` qui porte son texte.

**Cause racine.** Le `Switch` de Radix rend un `<button role="switch">`, pas un `<input>`. Un
`<label>` n'étiquette que les éléments de formulaire natifs, un bouton n'en fait pas partie,
donc l'association est ignorée.

**Correctif.** Un `<div>` à la place du `<label>`, un `id` sur le `Switch`, et un `<label
htmlFor>` qui le vise. Vaut pour tout composant Radix rendu en bouton.

---

### Une transition de `border-radius` saute instantanément au lieu de s'animer

**Cause racine.** Tailwind 4 résout `rounded-full` en `calc(infinity * 1px)`, valeur que le
navigateur ne sait pas interpoler. La transition passe donc d'un état à l'autre sans
animation, sans erreur ni warning.

**Correctif.** Une valeur fixe en pixels, `rounded-[Npx]`, aux deux extrémités de la
transition. Pour un cercle parfait sur un élément carré, N est la moitié du côté.

---

### Une classe `hidden` posée sur un composant UI ne cache rien

**Symptôme.** `<Button className="hidden min-[850px]:inline-flex">` reste visible sous
850px. Le même motif sur un `<div>` (`hidden … min-[850px]:flex`) fonctionne, ce qui rend le
diagnostic contre-intuitif.

**Cause racine.** Tailwind 4.3 émet les utilitaires de `display` par ordre alphabétique de
nom de classe, donc `.inline-flex` sort après `.hidden` dans la feuille. À spécificité
égale, la dernière règle gagne : un composant dont la base contient `inline-flex`
(`Button`, `UnderlineLink`) ne peut pas être caché par un `hidden` passé en `className`.
`.flex` sort avant `.hidden`, d'où l'asymétrie. Les variantes à media query
(`min-[850px]:hidden`) ne sont pas concernées, elles sont émises après les utilitaires nus.

**Correctif.** Porter le `hidden` sur un conteneur qui n'a pas de `display` de base, jamais
sur le composant lui-même. Même piège pour toute classe alphabétiquement postérieure à
`hidden` (`inline-block`, `table-cell`).

---

### Sur iOS, un carrousel ne glisse pas en douceur et le geste s'interrompt

**Cause racine.** Safari iOS ignore `behavior: 'smooth'` sur un conteneur scrollable, le
défilement saute donc d'un cran à l'autre. Et `setPointerCapture` appelé sur ce même
conteneur y déclenche un `pointercancel` immédiat, ce qui coupe le glissement au doigt.

**Correctif.** Animer le `scrollLeft` par GSAP plutôt que par `scrollTo({ behavior })`, et
ne capturer le pointeur que pour un pointeur de type souris.

---

### Un canvas se vide et clignote à chaque redimensionnement

**Cause racine.** `ResizeObserver` se déclenche aussi à dimensions inchangées, et
réassigner `canvas.width`, même à la valeur qu'il porte déjà, efface tout le contenu du
canvas et remet à zéro l'état de l'animation.

**Correctif.** Comparer les dimensions avant de réassigner, et ne reconstruire l'état que
sur un changement réel.

---

### Une section à hauteur réservée grandit sans fin sous `ResizeObserver`

**Cause racine.** Mesurer `offsetHeight` du conteneur pour en déduire le `minHeight` qu'on
vient de lui poser rend la mesure circulaire. L'observateur voit la nouvelle hauteur, la
réinjecte, et la section croît à chaque passe.

**Correctif.** Reconstruire la hauteur depuis les enfants, jamais depuis le conteneur qui
porte la contrainte.

---

### Un bouton reste sans effet quand un `pointerdown` sur `document` replie un bloc au-dessus

**Symptôme.** Dans un accordéon dont chaque bande est un îlot indépendant, cliquer une bande
referme bien celle qui était ouverte mais n'ouvre pas celle qu'on a cliquée. Le premier clic
après un chargement fonctionne, les suivants non, ce qui égare le diagnostic vers l'état React.

**Cause racine.** Un `click` n'est émis que si le `pointerdown` et le `pointerup` visent le
même élément, sinon le navigateur le livre à leur ancêtre commun. Refermer le bloc voisin dès
le `pointerdown` réagence la page pendant que le doigt est encore appuyé, le bouton visé
glisse hors du curseur, et son gestionnaire n'est jamais appelé. Rien n'échoue et aucune
erreur n'est émise.

**Correctif.** Écouter `click` et non `pointerdown` pour toute fermeture qui déplace la mise
en page. La règle vaut pour les menus et les popovers autant que pour les accordéons.

---

### Un défilement vers un bloc qu'on vient d'ouvrir atterrit trop bas

**Symptôme.** Le bloc voisin se replie bien, mais le défilement s'arrête comme s'il était
resté ouvert. L'écart vaut à peu près la hauteur du bloc replié.

**Cause racine.** Deux temps distincts qu'on confond facilement. Une mise à jour d'état
déclenchée depuis un écouteur `document` natif est traitée par React en priorité par défaut,
donc elle est validée une ou plusieurs frames après celle du composant cliqué, qui passe elle
par un événement discret. Les transitions des blocs voisins démarrent donc en retard sur la
nôtre. Un minuteur calé sur la durée du token, armé au moment du clic, expire alors que le
voisin se replie encore, et sa hauteur résiduelle entre dans la position mesurée.

**Correctif.** Faire partir toutes les transitions du même rendu, en repliant les voisins par
un `CustomEvent` émis pendant le gestionnaire de clic plutôt qu'en s'appuyant sur un écouteur
différé, puis mesurer sur le `transitionend` du panneau et non sur un minuteur. L'écart à
respecter en haut se relit sur l'élément par `getComputedStyle(...).scrollMarginTop`, ce qui
évite de dupliquer en JavaScript la valeur de son `scroll-mt-*`. Le mouvement réduit supprime
la transition, donc `transitionend` ne vient jamais, et ce cas se traite à part sur une frame.

---

### La page glisse toute seule jusqu'au bas quand on clique dans le vide

**Symptôme.** En bas de page, un clic qui ne vise rien fait descendre la page jusqu'au
footer, en glissant sur quelques centaines de millisecondes. Le symptôme n'apparaît qu'après
un chargement, ne se reproduit pas au clic suivant, et manque à ceux qui ont déjà touché aux
sections repliables.

**Cause racine.** Un bloc replié par un écouteur posé sur `document` retire sa hauteur au
document, alors qu'il se trouve **au-dessus** du viewport. La position de défilement, elle,
n'est pas compensée, donc le contenu remonte sous les yeux d'autant. Près du bas de page,
`scrollY` dépasse le nouveau maximum et le navigateur ramène la vue à la fin du document.
La transition du repli étale l'effet, ce qui le fait passer pour un défilement volontaire et
égare le diagnostic vers le composant cliqué, qui n'y est pour rien.

**Correctif.** Ne jamais retirer de hauteur au-dessus du viewport sans contrepartie. Soit
la hauteur reste constante, comme la FAQ qui réserve celle de sa réponse la plus longue, soit
le repli s'accompagne du défilement qui le compense, comme l'ouverture d'une bande d'offre
qui se recale sur elle-même. Un écouteur de fermeture branché sur `document` porte donc à
conséquence dans toute la page, pas seulement autour du bloc qu'il ferme.

---

### Un tracé SVG animé par `stroke-dashoffset` ne montre que quelques pixels

**Symptôme.** Une traînée censée occuper une fraction d'un chemin SVG normalisé par
`pathLength="1"` s'affiche comme un point de quelques pixels, et le glissement du
`stroke-dashoffset` semble ne rien déplacer.

**Cause racine.** `vector-effect: non-scaling-stroke` sur le même tracé. Chrome calcule alors
le contour dans l'espace écran, où `pathLength` ne s'applique plus : un `stroke-dasharray` de
`0.08 1`, prévu pour 8 % de la longueur du chemin, redevient 0,08 pixel. Les deux
fonctionnalités ne se combinent pas, et rien ne le signale, ni erreur ni avertissement.

**Correctif.** Choisir l'une des deux. Avec `pathLength` normalisé, on abandonne
`non-scaling-stroke` et on accepte que l'épaisseur du trait suive la mise à l'échelle du
`viewBox`, quitte à la compenser dans les valeurs de `stroke-width`. Avec
`non-scaling-stroke`, on exprime les longueurs de tirets dans les unités réelles du chemin,
mesurées par `getTotalLength()`.

---

### Un tween GSAP sur `stroke-dashoffset` saute d'un coup au lieu de glisser

**Symptôme.** GSAP anime `stroke-dashoffset` sur un chemin normalisé par `pathLength="1"`,
et le trait reste immobile à `0px` pendant la moitié de la durée, puis saute directement à
`-1px`. Visuellement, un segment statique qui apparaît puis disparaît, sans mouvement.

**Cause racine.** GSAP arrondit les valeurs en `px` au pixel entier pendant le tween. Avec
un chemin normalisé à 1, toute la course tient entre 0 et environ -1,2 px : l'arrondi ne
laisse que deux états possibles, 0 et -1. Rien ne le signale, le tween tourne normalement.

**Correctif.** Normaliser large, `pathLength="1000"` et toutes les valeurs de tirets à
l'échelle, pour que l'arrondi au pixel devienne invisible.

---

### Un nouvel import d'asset périme le cache Vite et tue l'hydratation d'une seule île

**Symptôme.** Après ajout d'imports d'assets en cours de session, les commandes d'une île
cessent de répondre alors que le reste de la page fonctionne. La console montre
`504 (Outdated Optimize Dep)` sur une dépendance sans rapport, puis
`[astro-island] Error hydrating <composant>.tsx: Failed to fetch dynamically imported module`.
Le rechargement ne suffit pas, y compris après plusieurs tentatives.

**Cause racine.** Un import nouveau déclenche une réoptimisation des dépendances par Vite,
qui change le hash `?v=` des chunks pré-bundlés. Le serveur de développement continue de
servir un graphe de modules qui référence l'ancien hash, donc l'import dynamique de l'île
échoue. L'erreur désigne la dépendance transitive et non l'île, ce qui envoie chercher le
bug dans le mauvais composant. Distinct du cas « deux serveurs réécrivent le même cache » de
`gotchas-communs.md` : ici un seul serveur tourne, à vérifier avec `pgrep -fl astro` avant de
conclure.

**Correctif.** Redémarrer le serveur de développement, ce qui reconstruit le graphe. La
production n'est pas concernée, le build ne consomme pas le cache d'optimisation. Avant de
suspecter le code, vérifier que `pnpm types:check` passe : si les types sont bons et que
l'erreur ne vise qu'une seule île, le cache est le coupable.

---

### Une image s'affiche en dev et disparaît après le build de production

**Cause racine.** Un chemin en dur qui pointe vers `src/assets/`, écrit dans le `src` d'une
balise `<img>` ou dans un fichier de `src/data/`, désigne un fichier que le serveur de dev
sert directement depuis le disque. Le build de production, lui, ne sert rien depuis `src/`.
Vite y traite les assets, les hache et les émet ailleurs, donc le chemin littéral ne
correspond plus à aucun fichier et l'image tombe en 404 sans que le build échoue.

Le silence du build est ce qui rend le piège coûteux, puisque le problème n'apparaît qu'en
production.

**Correctif.** Deux voies selon le cas.

Pour une image utilisée par un composant, on importe le fichier et on lit son `src`, ce qui
laisse Vite réécrire le chemin.

```ts
import img from '@assets/image.png';
// puis img.src
```

Pour des images nombreuses adressées par données, comme des logos, on les place
dans `public/` et on les adresse par chemin absolu, par exemple `/logos/nom.webp`. `public/`
est servi tel quel, sans traitement Vite, donc le chemin littéral reste valable.

---

### Le son se coupe quand le téléphone passe en arrière-plan

**Symptôme.** La lecture s'arrête quand l'écran se verrouille, surtout au changement de morceau. En voiture, les commandes au volant ne répondent plus.

**Cause racine.** Un élément `<audio>` créé pendant que la page est en arrière-plan n'a pas le droit de démarrer de lui-même : seule la continuation d'une session média déjà établie est autorisée. Détruire l'élément qui porte la session pour en créer un autre fait perdre l'autorisation de lecture.

**Règle qui en découle.** Un seul élément audio pour toute la session, jamais détruit ni remplacé, dont on ne change que la source. `hls.loadSource()` et l'affectation de `audio.src` conservent tous deux l'élément.

---

### Le son se coupe en veille et ne revient pas au déverrouillage

**Symptôme.** La lecture continue plusieurs minutes écran verrouillé, puis le son disparaît alors que la progression avance toujours. Le déverrouillage ne le ramène pas, seule une pause suivie d'une lecture le rétablit.

**Cause racine.** L'analyse spectrale du shader route l'élément audio dans un `AudioContext` par `createMediaElementSource()`. À partir de ce moment, le son ne sort plus par l'élément mais par le graphe. Le système suspend ce contexte en veille, et un `AudioContext` suspendu ne se remet jamais en marche tout seul.

**Règle qui en découle.** Tout `AudioContext` qui porte le son du lecteur écoute son `statechange` et se reprend par `resume()`, et le retour au premier plan en retente un. Le routage ne se fait jamais vers un contexte qui n'est pas `running`.

---

### Une route d'API dynamique rend systématiquement 500 sans qu'aucun message n'indique la vraie cause

**Cause racine.** Sous Next.js 15, `params` d'un handler de route dynamique est une
`Promise`, pas un objet direct. Le déstructurer sans l'attendre (`const { id } = params`)
donne un champ `undefined`, qui part tel quel dans une requête Prisma. Prisma lève alors une
erreur de validation sur l'argument manquant, loin du point réel du problème, ce qui masque
le vrai symptôme (`params` non résolu) derrière un message qui parle d'un tout autre champ.

**Correctif.** Toujours `await` le second argument du handler,
`const { id } = await params;`, avec le type `{ params: Promise<{ id: string }> }`.

---

### `pnpm build` échoue sur une route alors que `pnpm types:check` ne signale rien

**Symptôme.** `next build` s'arrête sur
`"broadcastFeedUpdate" is not a valid Route export field`, ou sur un `OmitWithTag` illisible
pointant `.next/types/app/.../route.ts`. `tsc --noEmit` passe pourtant à zéro.

**Cause racine.** Un fichier `route.ts` n'accepte en export que les verbes HTTP, `dynamic`,
`revalidate` et quelques options. Toute autre fonction exportée est refusée. La contrainte
n'existe que dans les types générés par Next pendant le build, donc `tsc` seul ne la voit
jamais.

**Correctif.** Sortir la fonction dans un module de bibliothèque. Le corollaire est que
`ignoreDuringBuilds` cache cette famille entière de défauts, en plus du lint.

---

### Une page qui charge indéfiniment alors que le serveur répond en 200 ms

**Symptôme.** Un onglet reste sur « chargement » pendant plusieurs minutes, changer de page
devient interminable, et pourtant `curl http://localhost:3000/fr` répond en moins d'une
seconde. Le serveur ne journalise aucune requête pendant tout ce temps, et l'onglet ne répond
plus à l'inspection.

**Cause racine.** Chrome plafonne à six connexions TCP simultanées par origine en HTTP/1.1,
et le serveur de développement sert justement en HTTP/1.1. Chaque onglet connecte deux flux
`text/event-stream` permanents, auxquels
s'ajoute la connexion de rechargement à chaud de Next. Trois connexions immobilisées par
onglet, donc deux onglets ouverts sur le site suffisent à consommer le quota, et la moindre
requête suivante attend qu'une connexion se libère, ce qui n'arrive jamais puisque les flux
sont maintenus par un battement de coeur.

**Constat.** `lsof -nP -iTCP:3000 -sTCP:ESTABLISHED | grep Google` liste les sockets, et deux
relevés espacés montrent les mêmes ports source, preuve que rien ne se libère.

**Correctif.** Ne garder qu'un onglet ouvert sur le site en développement. Le nombre de flux
par onglet est le vrai sujet, un flux multiplexe ou partage entre onglets supprimerait le
plafond.

---

### Le flou d'un shader coupé net au bord du canvas

**Symptôme.** Le halo d'un bloom s'arrête sur une ligne droite au bord de la surface, alors
que le shader est correct.

**Cause racine.** Le canvas fait exactement la taille de son contenu, donc le flou n'a aucune
place pour déborder et l'échantillonnage `clamp-to-edge` étale la dernière colonne de texels.

**Correctif.** Élargir la surface d'une marge et dessiner le contenu en retrait, la marge
étant reprise par un `padding` compensé d'une `margin` négative pour ne pas déplacer la mise
en page.

---

### Un canvas positionné en absolu qui garde sa taille en pixels

**Symptôme.** Un `<canvas>` en `position: absolute` déborde de son parent et s'affiche au
double de sa taille attendue, bien que ses quatre décalages soient renseignés.

**Cause racine.** Les décalages se résolvent contre le premier ancêtre positionné, pas contre
le parent visuel. Si ce parent n'est pas positionné, le canvas retombe sur sa taille
intrinsèque, celle de ses attributs `width` et `height`, exprimée en pixels CSS, donc doublée
sur un écran à deux pixels par point.

**Correctif.** Positionner explicitement la boîte parente, et couvrir avec `inset-0` plutôt
qu'avec des décalages négatifs dont l'ancrage est difficile à garantir.

---

### Un onglet des paramètres plante en production seulement, `Cannot access 'X' before initialization`

**Symptôme.** Un onglet de paramètres lève `ReferenceError: Cannot access 'X' before
initialization` dans un `useMemo`, accompagné de l'erreur React #418 (hydratation). En
développement, la page passe.

**Cause racine.** Deux pièges superposés. Un `useMemo` appelait une fonction déclarée en
`const` plus bas dans le corps du composant, donc encore dans sa zone morte temporelle au
premier rendu. Le crash ne se voit qu'avec une donnée qui déclenche la branche, ce qui explique un développement qui passe et une production
qui casse, le nom minifié `X` masquant l'identité de la variable. Par ailleurs l'onglet
initial était lu dans `window.location` depuis l'initialiseur d'un `useState`, donc le
serveur rendait un onglet et le client un autre, d'où le #418.

**Correctif.** Une fonction pure appelée par un hook se déclare au niveau du module, jamais
après le hook dans le corps du composant. L'état initial qui dépend de l'URL vient des
`searchParams` de la page serveur et descend en prop, jamais de `window` au premier rendu.

---

### Un carrousel affiche des cases vides sur mobile, puis se rattrape

Les premières photos d'un carrousel arrivaient vides sur téléphone, l'image ne se chargeait
qu'une fois la diapositive amenée devant l'œil.

**Cause racine.** Le chargement différé natif, `loading="lazy"`, ne regarde que la fenêtre.
Une diapositive sortie de l'écran sur l'axe **horizontal**, à l'intérieur d'un conteneur en
`overflow: hidden` que le carrousel translate, n'est jamais considérée comme approchant, donc
son image ne part qu'au moment où le glissement l'amène. Sur une connexion mobile, la case
reste vide le temps du téléchargement.

**Correctif.** La photo n'est posée dans le DOM qu'une fois sa diapositive à l'image ou
juste après, d'après `slidesInView()` d'Embla, les autres gardent un bloc de même format qui
ne demande rien au réseau. Un `IntersectionObserver` sur la racine amorce la série un peu
avant que le bloc n'atteigne l'écran.

**Ce qui ne suffit pas.** Laisser les images en place et se contenter de basculer
`loading="lazy"` en `eager` rend la main au navigateur, qui choisit seul sa distance
d'avance et télécharge volontiers la série entière au chargement de la page.

---

### Un carrousel déborde de sa colonne et croit que toutes ses diapositives sont visibles

Un carrousel posé dans une grille mesurait 7266 px de large pour une colonne de 326 px. Les
flèches ne servaient à rien, `slidesInView()` renvoyait les vingt-sept diapositives, et le
chargement à la demande téléchargeait donc tout d'un coup.

**Cause racine.** La largeur intrinsèque d'un rail de carrousel est la somme de ses
diapositives. Une colonne de grille en largeur automatique se dimensionne sur le
`max-content` de son contenu, donc sur ce rail, et le conteneur déborde. L'`overflow: hidden`
de la fenêtre du carrousel masque le débordement à l'écran mais ne retire rien au calcul,
un contenu caché compte toujours dans la largeur intrinsèque.

**Correctif.** `contain: inline-size` sur la fenêtre du carrousel. L'élément cesse d'annoncer la largeur de son contenu, la
colonne se dimensionne sur le conteneur, et le carrousel retrouve une fenêtre juste.

---

### Une image passée à un shader se télécharge deux fois

Une image arrivait deux fois, la version optimisée pour la balise `<img>` et
l'original de 2480 px pour la texture WebGPU, soit 683 ko pour un rendu de 320 px.

**Cause racine.** `next/image` sert une version redimensionnée, mais le shader partait de
`src.src`, qui pointe le fichier importé tel quel. Deux URL différentes, donc deux
téléchargements, et le plus gros des deux servait à dessiner le plus petit.

**Correctif.** Le shader attend que la balise ait chargé et repart de son `currentSrc`, déjà
en cache. Le rendu attend tant que l'URL n'est pas
connue.

---

### Un carrousel se téléporte quand ses photos remplacent leurs cases d'attente

**Symptôme.** La bande défile normalement, puis saute d'un coup de plusieurs dizaines de
pixels, surtout pendant un glissé. Le défaut apparaît après avoir rendu les photos
cliquables, jamais avant.

**Cause racine.** La base du composant `Button` porte `border-2 border-transparent`, donc
envelopper une photo dedans élargit sa diapositive de quatre pixels et la rehausse d'autant.
Le carrousel garde en revanche des cases d'attente aux cotes de la photo nue tant que le
chargement différé n'a pas posé l'image. Chaque diapositive change donc de largeur au moment
où elle se remplit, embla a mesuré les positions avec les anciennes cotes, et il se recale
d'un bloc dès que l'écart s'accumule.

**Correctif.** Poser `border-0` sur le bouton qui enveloppe l'image, l'anneau de
`focus-visible` suffisant à signaler le focus clavier. Plus généralement, tout ce qui entoure
une diapositive doit rendre exactement les mêmes cotes que sa case d'attente. La mesure se
vérifie en comparant `getBoundingClientRect().width` des diapositives avant et après
chargement.

---

### Les visuels du catalogue manquent au site publié, alors que le build est vert

**Cause racine.** Le rendu des pages et les intégrations ne partagent pas la même instance
d'un module. Un registre tenu en mémoire de processus, rempli pendant le rendu, est donc vu
vide par le hook `astro:build:done`, qui sort sans rien écrire. Le HTML garde les chemins
locaux qu'il a fabriqués, les fichiers n'existent pas, et rien n'échoue.

**Correctif.** Faire transiter le registre par le disque, seul canal que les deux côtés
partagent. Un dossier tampon écrit au rendu, lu puis retiré par le hook.

---

### L'indicateur d'un sommaire saute des entrées pendant un défilement déclenché au clic

**Cause racine.** Un `IntersectionObserver` ne notifie que les **changements** d'état
d'intersection, constatés au plus une fois par frame. Un `rootMargin` qui ne laisse qu'une
bande étroite, ici 10 % de la hauteur du viewport, se traverse entièrement entre deux
constats dès que le défilement dépasse la centaine de pixels par frame, ce que fait un
`lenis.scrollTo` sur une longue distance. Le titre est vu hors bande avant et hors bande
après, aucune entrée n'est émise, et les sections intermédiaires n'existent jamais pour
l'observateur.

**Correctif.** Espionner la **position** plutôt que les événements, en relisant à chaque frame
de défilement quel titre a franchi une ligne de référence. Le résultat est déterministe,
insensible à la vitesse, et l'indicateur suit le défilement section par section.

---

### Un build interrompu laisse le code serveur, et ce qu'il inline, dans `dist/.prerender/`

**Symptôme.** Après un build qui échoue, par exemple sur un export du parent injoignable,
`dist/` contient un dossier `.prerender/chunks/` de modules `.mjs`. Toute valeur que le code
lit par `import.meta.env` au rendu y figure en clair, jeton du parent compris, et un
déploiement qui publierait `dist/` tel quel la servirait.

**Cause racine.** Astro construit les pages dans `dist/.prerender/` puis ne le supprime qu'à la
fin d'une génération réussie (`core/build/static-build.js`). Une variable non publique lue par
`import.meta.env` est inlinée par Vite dans ces modules au moment du build.

**Correctif.** Lire tout secret par `astro:env/server` (`access: 'secret'`, `context: 'server'`),
qu'Astro relit dans l'environnement du processus au lieu de l'inliner. Ne jamais publier un
`dist/` issu d'un build en échec, et supprimer un `dist/` local périmé plutôt que de le garder.

---

### Une couleur composée par son opacité puis écrite dans un PNG à alpha droit sort presque noire

**Symptôme.** Des aplats semi-transparents se dessinent en taches sombres au lieu de leur
teinte, et les bords antialiasés ont un liseré sombre. Le défaut disparaît là où l'opacité
atteint 255.

**Cause racine.** Le code composait `couleur = teinte × opacité` et rangeait cette même
opacité dans le canal A. Un PNG est à alpha droit : le consommateur remultiplie par l'alpha,
et la teinte arrive au carré de son opacité.

**Correctif.** Une seule fonction de composition « source par-dessus » en alpha droit :

```
a = a0 + m (1 - a0)
c = (c0 a0 (1 - m) + teinte m) / a
```

Ne jamais multiplier une couleur par l'opacité écrite à côté d'elle, sauf dans un tampon
prémultiplié.

---

### Un liseré sombre cerne les bords d'une texture transparente : du noir sous les texels invisibles

**Symptôme.** Un contour sombre cerne une zone claire d'une texture posée en 3D, alors que la
texture ouverte à plat n'a aucun pixel sombre à cet endroit.

**Cause racine.** Le compositeur laisse `RGB = (0,0,0)` là où l'opacité est nulle. Tout
échantillonnage filtré, mipmaps comprises, mélange les canaux de couleur indépendamment de
l'opacité : un pixel à cheval sur le bord moyenne sa couleur avec le noir voisin. Le halo ne
se voit que sur les zones claires.

**Correctif.** En dernière passe, étendre la couleur des texels visibles sous les texels
transparents sur quelques pixels, sans jamais toucher à l'opacité. Un texel invisible dont
aucun voisin visible n'est coloré peut rester noir.

---

### Un effet qui lit un `useSyncExternalStore` écrit une valeur périmée au premier commit

**Symptôme.** Un élément dont la taille ou l'état est déjà correct au premier paint (posé par
un script inline) saute ou s'anime juste après l'hydratation.

**Cause racine.** Pendant l'hydratation, `useSyncExternalStore` rend la valeur de
`getServerSnapshot`, pas celle du client, pour que le HTML corresponde. Le re-rendu avec la
vraie valeur n'arrive qu'après, et les effets du premier commit tournent avant : leur closure
capture la valeur serveur. Un effet qui applique cette valeur au DOM écrase l'état correct par
l'état par défaut, puis le corrige au commit suivant. Vaut aussi pour `useMediaQuery`, bâti sur
le même hook.

**Correctif.** Un effet qui applique un état de ce genre lit la source vivante
(`window.matchMedia(...)`, le getter du store) plutôt que la valeur reçue en closure, en
gardant les valeurs du hook en dépendances.

---

### Écart d'hydratation sur `aria-describedby="DndDescribedBy-N"` (dnd-kit)

**Symptôme.** Au chargement d'une page portant une liste triable, React signale « A tree
hydrated but some attributes of the server rendered HTML didn't match », sur le seul
`aria-describedby`.

**Cause racine.** dnd-kit numérote ses `DndContext` avec un compteur de module global. Le
rendu serveur et le rendu client ne partent pas du même compteur.

**Correctif.** Un `id` explicite et stable sur chaque `<DndContext id="...">`, dès la
création d'une liste triable.

---

## Files d'attente, tâches planifiées et emails

### Un worker exécute le code chargé à son démarrage

**Symptôme.** On corrige un service, les tests passent, un appel direct passe, et
l'application continue de produire **exactement** l'ancienne erreur.

**Cause racine.** Le traitement tourne dans un worker, et un worker garde en mémoire le code
chargé à son démarrage. Tant qu'il n'a pas été relancé, il exécute l'ancienne version.

**Correctif.** Toute correction dans du code appelé depuis une tâche de fond doit être suivie
d'un redémarrage des workers. Ça vaut pour tous les systèmes de files, quel que soit le
langage.

### Un email mis en file est rendu hors contexte HTTP

**Symptôme.** Le logo d'un email reçu pointe vers `localhost`, ou une URL absolue est fausse.

**Cause racine.** Le worker rend l'email en dehors de toute requête, donc les helpers qui
construisent une URL absolue se rabattent sur la variable d'environnement de base, qui doit
être correcte **dans l'environnement du worker** et pas seulement dans celui du serveur web.

### Un filtre par fenêtre temporelle n'est pas idempotent

**Symptôme.** Un digest envoyé deux fois, ou des notifications jamais rappelées après un
déploiement.

**Cause racine.** Une commande planifiée peut sauter une exécution, par exemple pendant un
redéploiement, ou être rejouée. Un filtre du type « créé depuis moins de vingt-quatre heures »
ne tolère ni l'un ni l'autre.

**Correctif.** Poser un **tampon en base**, et le poser **avant** la mise en file de l'envoi.
Un crash entre les deux perd au pire un envoi, jamais n'en produit deux. Une fenêtre de
tolérance de quelques minutes rattrape une exécution manquée.

### `oklch` et les variables CSS sont inutilisables en email

**Symptôme.** Couleurs absentes ou noires dans un email rendu par Outlook ou Gmail.

**Cause racine.** Les clients de messagerie ne supportent ni les couleurs OKLCH ni les
propriétés personnalisées CSS. Or les tokens modernes d'une feuille Tailwind sont justement en
`oklch()`.

**Correctif.** Convertir en hexadécimal sRGB au moment du rendu, par une couche dédiée que
toute couleur d'email traverse. Jamais un hexadécimal en dur, jamais une classe Tailwind.

### Un email en largeur fixe ne se redimensionne pas sur mobile

**Symptôme.** Sur téléphone, la carte déborde de l'écran et le texte est coupé à droite.

**Cause racine.** Le conteneur était en largeur fixe. Un `max-width: 100%` ne suffit pas,
parce que le client de messagerie rend le document à sa largeur intrinsèque.

**Correctif.** Le motif fluide-hybride, donc un conteneur en `width: 100%` avec un
`max-width` et une marge automatique, jamais de largeur fixe, plus une table fantôme sous
condition `mso` pour épingler Outlook qui ignore `max-width`.

---

### Des abonnés se désinscrivent de la newsletter sans avoir rien cliqué

**Cause racine.** Le lien de désabonnement d'un courriel pointait sur un `GET` qui
désabonnait directement. Un `GET` ne doit jamais muter d'état, parce que des agents
automatiques (antivirus, filtres anti-hameçonnage, préchargeurs de client mail) suivent les
liens d'un courriel sans intervention humaine. Chacun de ces suivis automatiques désabonnait
silencieusement l'utilisateur à son insu.

**Correctif.** Le `GET` ne fait plus que
consulter l'état d'abonnement, sans effet de bord. La désinscription réelle passe par un
`POST`, déclenché depuis la page de confirmation.

---

## API externes et assets

### Une clé de payload d'API externe ne se devine pas

**Symptôme.** Une exception du type « réponse sans identifiant » alors que l'appel HTTP répond
bien en 200 et que le reste fonctionne.

**Cause racine.** Les noms de clés avaient été **supposés** au moment d'écrire le client, sans
jamais appeler l'API réelle. Sur le cas qui a servi de leçon, l'identifiant attendu sous `id`
vivait en réalité dans `responses.0`, et l'état sous `wfs` plutôt que sous `status`.

**Correctif.** Tant qu'un appel réel n'a pas été fait, la structure est **inconnue** et pas
« probablement `id` ». Poser un `// REVISIT:` ne suffit pas, il faut appeler l'API.

Corollaire du même incident, une réponse vide n'est pas toujours une panne. Un test
d'éligibilité qui aboutit sans aucune offre est un résultat valide, pas un échec.

### Un export Figma rend un carré blanc au lieu de l'asset

**Symptôme.** Un SVG ou un PNG exporté depuis Figma s'affiche comme un carré plein, blanc ou
bleu clair, et l'asset est invisible.

**Cause racine.** L'export embarque des rectangles hérités du canvas et du groupe parent,
peints **par-dessus** l'asset, donc un rectangle à la couleur de fond du canvas et parfois le
cadre plein du groupe entier.

**Correctif.** Retirer ces rectangles de fond après export, ou pour un PNG exporter le nœud
isolé et recadrer sur la vraie boîte englobante en gardant l'alpha. Toujours vérifier le rendu
sur fond sombre avant intégration, et vérifier d'abord que l'asset n'existe pas déjà dans le
dépôt.

### Le texte des exports Meta est en double-encodage UTF-8

**Symptôme.** Un quart des légendes d'un export JSON de Meta contiennent des suites illisibles
au lieu des emojis et des accents.

**Cause racine.** Meta sérialise le texte en UTF-8 puis le relit en Latin-1 avant de l'écrire
dans le JSON. L'emoji dont les octets sont `F0 9F A5 B0` ressort en quatre caractères
Latin-1 distincts.

**Correctif.** Ré-encoder la chaîne en Latin-1 et la relire en UTF-8.

Un texte français correct comme `café` contient `é`, soit l'octet Latin-1 `E9` isolé, qui
n'est pas une séquence UTF-8 valide. Le décodage échoue donc et la chaîne ressort intacte.

### La réparation du mojibake casse la typographie française

**Symptôme.** `CAFÉ !` écrit avec une espace insécable ressort en `CAFɠ!`. `CRÉ : 2026`
ressort en `CRɠ: 2026`.

**Cause racine.** Le raisonnement de l'entrée précédente est vrai pour un accent isolé, mais il
ne suffit pas. Les majuscules accentuées `Â` à `Ë` occupent en Latin-1 les octets `C2` à `CB`,
qui sont des **octets d'amorce UTF-8 valides**. La typographie française place une espace
insécable (`U+00A0`, soit l'octet `A0`, un **octet de continuation valide**) devant `!`, `?`,
`:` et `;`. La paire forme donc une séquence UTF-8 parfaitement valide, que le décodage
transforme en une lettre de l'alphabet phonétique.

Le piège est que le décodage réussit. Il ne peut donc pas servir seul de test de validité.

**Correctif.** Contrôler la plausibilité du résultat après décodage, et refuser la
réparation si le texte obtenu contient un scalaire dans `U+0080...U+009F` (contrôles C1) ou
`U+0250...U+02AF` (extension de l'alphabet phonétique).

Ces deux plages suffisent, et il faut résister à la tentation de les élargir. `É` (`C9`) et
`Ê` (`CA`) suivis d'une insécable (`A0`) ou d'un degré (`B0`) décodent vers `U+0260`,
`U+02A0` et `U+0270`, tous dans la plage phonétique. Exclure en plus les lettres
modificatives (`U+02B0...U+02FF`) ne protège donc rien de neuf, et rejette à tort les
légendes décoratives, fréquentes sur Threads. Mesuré sur 838 légendes réelles : retirer
cette exclusion ne fait basculer qu'une seule légende, et dans le bon sens.

Un mojibake réel décode vers des emojis, des lettres latines accentuées, de la ponctuation ou
des idéogrammes. Il ne décode jamais vers l'alphabet phonétique, alors que `É` et `Ê`, les deux
seuls cas réels en français, y atterrissent.

Le latin étendu B (`U+0180...U+024F`) est lui aussi délibérément hors de la liste, car le
vietnamien l'utilise (`ơ`, `ư`).

**Limite connue.** Le contrôle protège les cas réels, pas tous les cas concevables. Une
lettre accentuée suivie sans espace d'un ou deux symboles Latin-1 de la zone de continuation
(`U+00A0` à `U+00BF`) peut encore décoder vers une plage autorisée, par exemple `à§¶` qui
donnerait un caractère bengali. Ces suites n'apparaissent dans aucune des 838 légendes
mesurées et ne correspondent à aucune typographie réelle, mais la garantie n'est pas
absolue : elle est statistique, calibrée sur le corpus.

---

### La détection MIME serveur ne distingue jamais un `.md` d'un `.txt`

**Symptôme.** Une validation `text/markdown` ne se déclenche jamais sur un vrai `.md`, accepté
quand même comme `text/plain`, et une extension régénérée depuis le MIME ressort en `.txt`.

**Cause racine.** La détection (`finfo`, `libmagic`) identifie un fichier par la signature de
son contenu, pas par son extension. Un `.md` est du texte brut au même titre qu'un `.txt`.

**Correctif.** Ne jamais se fier au MIME détecté pour distinguer texte brut et markdown. Seule
l'extension du nom d'origine porte cette distinction, à valider séparément.

---

## Vérifications statiques

### Une clé de traduction passée par une variable est invisible au vérificateur

Un vérificateur d'i18n scanne le code **statiquement**, donc une clé passée par une variable
ou par un paramètre lui échappe et ressort comme orpheline, ce qui casse le check sans qu'il y
ait de vrai problème.

**Correctif.** Toujours un littéral au point d'appel.

---

### Le cliquet de dette bloque tous les commits à cause d'un navigateur téléchargé

**Symptôme.** Le cliquet de lint annonce des centaines d'erreurs contre zéro en référence,
toutes sur une seule ligne d'un fichier jamais écrit dans le projet. Aucun commit ne passe,
quel que soit son contenu.

**Cause racine.** Un outil de test télécharge son navigateur dans le dépôt, sous
`.puppeteer/`. Ce dossier n'était ni ignoré par git ni exclu d'ESLint, qui lintait donc les
scripts minifiés de Chrome.

**Correctif.** Le dossier figure dans `.gitignore` et dans les `ignores` de
`eslint.config.mjs`. Un nouvel outil qui dépose ses binaires dans le dépôt demande les deux
entrées, sans quoi il bloque le dépôt entier.

---

### `set-state-in-effect` ne se corrige pas en déplaçant le `setState`

**Symptôme.** ESLint signale `Calling setState synchronously within an effect` sur un effet,
parfois en pointant un simple appel de fonction plutôt qu'un `setState` visible.

**Cause racine.** La règle remonte la chaîne d'appels. Un effet qui appelle une fonction
`async` est signalé si cette fonction écrit un état **avant son premier `await`**, et
l'écriture reste rattachée au chemin synchrone de l'appelant même quand elle est placée
après un `await`. Seule une écriture dans un rappel (`.then()`, `.finally()`, un écouteur,
un minuteur) sort du chemin synchrone. Les 111 occurrences du projet relevaient de six cas,
et dans presque tous l'écriture signalée était **redondante** : `loading` vaut déjà `true` à
l'initialisation, et il n'y a pas d'erreur à effacer au premier chargement.

**Correctif, selon le cas.**

1. **Amorcer au rendu** ce qui est lisible sans effet, par une initialisation paresseuse de
   `useState`, puis réamorcer dans le corps du rendu quand la clé change. Vaut pour un cache
   déjà rempli ou une API déjà initialisée (`useSWR`, `useApiCache`, `carousel`).
2. **Chaîner les rappels** plutôt qu'`async`/`await` quand un effet déclenche du réseau. Le
   `setState` vit dans `.then()`, `.catch()`, `.finally()`.
3. **S'abonner** par `useSyncExternalStore` quand la donnée vient du navigateur et non de
   React, donc une media query, `document.referrer`, ou un drapeau « on est côté client ».
   Un abonnement vide (`() => () => {}`) est la forme correcte pour une valeur qui ne change
   jamais.
4. **Dériver des props** au rendu au lieu de les recopier dans un état.
5. **Ajuster pendant le rendu** quand un état doit se réinitialiser au changement d'une prop,
   en gardant la valeur précédente dans un état témoin.
6. **`useSearchParams()`** au lieu de lire `window.location.search` dans un effet.

**Ce que l'écriture d'ouverture devient.** `setLoading(true)` et `setError(null)` ne
disparaissent pas, ils rejoignent le `refetch` déclenché par une action de l'utilisateur, où
ils servent vraiment et où l'écriture est légitime puisqu'elle ne vient pas d'un effet.

**Un drapeau `isClient` posé par un effet est presque toujours un pansement.** Il masque un
écart d'hydratation créé ailleurs, le plus souvent par un `Math.random()` appelé pendant le
rendu. On corrige la source, `useId()` pour un identifiant, une valeur dérivée d'un index ou
d'une graine fixe pour une valeur décorative.

---

### Une erreur `immutability` en cache souvent une autre en dessous

**Symptôme.** On corrige `X is accessed before it is declared` en remontant la fonction
au-dessus de l'effet, et le compteur ne bouge pas : `set-state-in-effect` apparaît à la place.

**Cause racine.** Tant que la fonction est déclarée après l'effet, la règle s'arrête à
l'erreur d'ordre et n'analyse pas le corps. L'ordre corrigé, elle voit le `setLoading(true)`
synchrone qui s'y trouvait depuis le début. Les deux ne sont qu'un seul défaut.

**Correctif.** Traiter les deux d'un coup, donc convertir la fonction en chaîne de promesses
**et** la déclarer avant l'effet. Compter une correction par fichier, pas par erreur.

---

### Un indicateur de chargement disparaît après une correction de `set-state-in-effect`

**Symptôme.** Plus aucun spinner sur un écran qui en avait un. Ni le lint ni le type-check ne
signalent quoi que ce soit, et l'écran finit par afficher ses données.

**Cause racine.** Retirer le `setLoading(true)` d'une fonction de chargement suppose qu'un
gestionnaire d'événement le repose ailleurs. Quand la fonction n'est appelée que par un effet,
ce gestionnaire n'existe pas et le drapeau ne repasse jamais à vrai.

**Correctif.** Lister les appelants (`grep -n "nomDeLaFonction()"`) **avant** de retirer
l'écriture. S'il n'y a que l'effet, le drapeau se repose soit à l'initialisation de l'état
quand la condition est lisible au rendu, soit dans l'ajustement au rendu qui constate le
changement de clé. Le piège s'est présenté trois fois, sur la page badges, sur
`AddUserModal` et sur le fil clubfeed, où la fonction était appelée par un effet **et** par
deux gestionnaires.

---

### Une variable `error` inutilisée signalée par le lint n'est pas un résidu

**Symptôme.** ESLint remonte `'error' is defined but never used` sur un `catch (error)` d'une
route API. Le réflexe est de renommer la variable en `_error` ou de la retirer de la
signature du `catch`.

**Cause racine.** Le signalement dit que la route capture son erreur et la jette. La route
renvoie donc un 500 générique sans laisser la moindre trace serveur, et un incident de
production devient impossible à diagnostiquer, on sait seulement qu'une requête a échoué.

**Correctif.** Écrire le `console.error()` dans le `catch` de toute route API, en nommant la méthode et le chemin. Le lint retombe par
effet de bord, ce n'est pas le but. Ne jamais faire taire le signalement en préfixant la
variable d'un underscore, c'est le symptôme qu'on éteint, pas la cause.

---

## Python

### Le dépôt de travail entier disparaît pendant une suite de tests, il ne reste que `.pytest_cache`

**Cause racine.** Un test faisait `shutil.rmtree(Path(result.stdout.strip()))` sur la sortie
d'une commande. Quand la commande échoue, stdout est vide, `Path("")` vaut `.`, et `rmtree`
efface le répertoire courant, c'est-à-dire le dépôt entier. Deux suites pytest lancées en
parallèle dans le même arbre ont provoqué l'échec de la commande dans l'une d'elles, et l'arbre
a été effacé.

**Correctif.** Un test ne supprime jamais un chemin dérivé d'une sortie sans l'avoir vérifié :
code de sortie à zéro, chemin résolu, situé sous `tmp_path`, et existant. Une seule suite
pytest à la fois dans un dépôt. Ce qui ne se régénère pas a une copie hors du dépôt avant tout
run lourd.

### Une deuxième copie par `shutil.copytree` échoue en `PermissionError: [Errno 13] Permission denied`

**Cause racine.** Les fichiers source venaient du cache Hugging Face, déposés en mode `0444`
(lecture seule). `shutil.copytree(..., dirs_exist_ok=True)` a pour fonction de copie par
défaut `shutil.copy2`, qui reproduit les métadonnées du fichier source, mode d'accès compris :
la première copie écrit donc un fichier déjà `0444` à destination. Une deuxième copie au même
endroit tente d'écraser ce fichier désormais en lecture seule et échoue, `dirs_exist_ok=True`
ne rendant le dossier réutilisable qu'en apparence.

**Correctif.** Passer `copy_function=shutil.copyfile` à `copytree`, qui copie le contenu sans
reproduire les métadonnées : le fichier écrit hérite du mode par défaut du processus, pas de
celui de la source, et une copie suivante peut l'écraser normalement.

### Python échoue en `CERTIFICATE_VERIFY_FAILED` sur certains hôtes, alors que `curl` réussit sur le même hôte

**Cause racine.** Certains serveurs ne servent que leur certificat feuille pendant la poignée
de main TLS, sans le certificat intermédiaire qui le relie à une racine connue. `curl` sur
macOS complète cette chaîne via le magasin de confiance du système, qui a mis ce certificat
intermédiaire en cache. Le module `ssl` de Python, lui, ne fait aucune reconstruction de
chaîne : il vérifie seulement ce que le serveur envoie contre le magasin fourni au contexte, et
rejette la connexion s'il manque un maillon. Fournir le magasin `certifi` au contexte ne change
rien, puisque `certifi` ne contient que des racines, pas les intermédiaires manquants publiés
par les serveurs eux-mêmes.

**Correctif.** Utiliser `truststore.SSLContext`, qui délègue la vérification au magasin natif
du système d'exploitation (le même que `curl`), capable de compléter la chaîne là où
`ssl.create_default_context(cafile=certifi.where())` échoue.

---

## Apps macOS en Swift

### Les Command Line Tools ne suffisent pas, il faut Xcode.app

**Symptôme.** `swift test` échoue sur `no such module 'XCTest'`. Un type marqué `@Model` échoue
à la compilation avec
`external macro implementation type 'SwiftDataMacros.PersistentModelMacro' could not be found`.

**Cause racine.** Les Command Line Tools livrent le compilateur Swift et le SDK, mais ni
XCTest, ni les plugins de macro compilés dont SwiftData a besoin. Ces derniers vivent dans
`Xcode.app`.

**Correctif.** Installer Xcode depuis l'App Store, puis
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. Vérifier avec
`xcodebuild -version`, qui échoue explicitement tant que seuls les CLT sont actifs.

### `swift test` échoue avec « no such module 'Testing' », alors que le framework est là

**Symptôme.** Toute la suite Swift refuse de compiler, sur *tous* les fichiers de test, avec
`error: no such module 'Testing'`. Le réflexe est de croire que swift-testing n'est pas
disponible sans Xcode complet, et d'aller réécrire les tests en XCTest.

**Cause racine.** C'est faux. Le framework est installé avec les seules Command Line Tools :

```
/Library/Developer/CommandLineTools/Library/Developer/Frameworks/Testing.framework
/Library/Developer/CommandLineTools/Library/Developer/usr/lib/lib_TestingInterop.dylib
```

SwiftPM ne les cherche simplement pas là, faute d'Xcode pour poser les chemins. Il manque un
chemin de recherche à la compilation, et **deux** chemins d'exécution à l'édition de liens,
dans deux dossiers différents : le framework et sa dylib d'interop ne vivent pas au même
endroit. N'en donner qu'un fait passer la compilation puis échouer le chargement du bundle de
test, ce qui ressemble à un tout autre problème.

```
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
swift test -Xswiftc -F -Xswiftc $F \
  -Xlinker -F -Xlinker $F \
  -Xlinker -rpath -Xlinker $F \
  -Xlinker -rpath -Xlinker $L
```

**Correctif.** Devant un module introuvable, chercher le framework sur le disque avant de
conclure qu'il manque. `find /Library/Developer/CommandLineTools -iname "*<Module>*"` tranche
en une commande. Et quand un chargement dynamique échoue après une compilation réussie, lire
la liste des chemins essayés que dyld imprime : elle dit exactement quel rpath manque.

### Une cible SPM vide dans un produit est une erreur, pas un avertissement

**Symptôme.** `error: target '<cible>' referenced in product '<cible>' is empty`, alors qu'une
autre cible tout aussi vide ne produit qu'un avertissement.

**Cause racine.** SPM tolère une cible sans fichier source tant qu'elle n'est référencée nulle
part, et il se contente d'avertir. Dès que cette cible apparaît dans un `products:`, elle doit
produire une bibliothèque, et une cible vide ne le peut pas.

Le piège est que la vérification faite sur un paquet sans `products:` passe, ce qui donne une
fausse assurance.

**Correctif.** Déclarer une cible et son produit au moment où elle reçoit son premier
fichier, jamais avant. Créer un fichier bouche-trou pour faire taire l'erreur est un
contournement interdit par la règle 4.

### `@Attribute(.unique)` fait un upsert silencieux

**Symptôme.** On attend une erreur en insérant deux fois la même clé unique, et rien ne se
produit. Une seule ligne subsiste, la seconde insertion a écrasé la première.

**Cause racine.** SwiftData traite une contrainte d'unicité comme un upsert, pas comme une
violation. Aucune erreur n'est levée.

**Correctif.** Ne jamais compter sur la contrainte pour détecter un doublon. La
déduplication se fait explicitement, en cherchant la clé avant d'insérer.

Corollaire pour la déduplication au sein d'un même lot, il faut sauver le contexte après
chaque insertion, sinon les recherches suivantes du lot ne voient pas ce qui vient d'être
inséré.

### Renommer le dossier d'un paquet SwiftPM empoisonne son cache de modules

**Symptôme.** Après un `git mv` du dossier du paquet, `swift build` échoue en série sur
`precompiled file ... was compiled with module cache path <ancien chemin>, but the path is
currently <nouveau chemin>` puis `missing required module 'SwiftShims'`. Aucun fichier source
n'est en cause, et le message ne nomme jamais le renommage.

**Cause racine.** `.build/` suit le dossier pendant le `mv`. Les `.pcm` du `ModuleCache`
contiennent leur chemin absolu de compilation, qui ne correspond plus au nouvel emplacement.
Clang refuse alors chaque module précompilé.

**Correctif.** `swift package --package-path <paquet> clean` avant la première compilation
qui suit un renommage. Le cache est un artefact dérivé, le supprimer ne coûte qu'une
recompilation complète.

### Un build incrémental périmé fait échouer des tests qu'on n'a pas touchés

**Symptôme.** Après un changement de signature d'un initialiseur traversant plusieurs
modules, `swift build --build-tests` échoue d'abord sur `Undefined symbols` nommant
l'ancienne signature, sans la moindre erreur de compilation. Une fois les appelants corrigés,
`swift test` rapporte des échecs d'assertion sur des champs qu'aucune modification
n'approche. Les mêmes tests passent sur un `git worktree` de `HEAD`.

**Cause racine.** Le même `.build` que dans l'entrée précédente, encore désaligné par le
renommage du dossier. Les objets des modules non recompilés gardent l'ancienne disposition
mémoire de la structure élargie, donc les champs se lisent décalés à l'exécution. L'échec
d'assertion est un symptôme de l'édition de liens, pas du code testé.

**Correctif.** `swift package --package-path <paquet> clean` avant de suspecter le code.
Avant d'accuser une assertion, comparer avec un `git worktree` de `HEAD` : si le test y passe
et que le diff ne touche pas ce chemin, le cache est en cause.

### Le bundle de ressources SwiftPM ne survit pas à l'assemblage du `.app`

**Symptôme.** L'application assemblée ne se lance pas, ni au double-clic ni par `open`. Lancé
à la main, le binaire meurt aussitôt sur `Fatal error: could not load resource bundle: from
<...>/<App>.app/<App>_<Cible>.bundle or <...>/.build/.../<App>_<Cible>.bundle`.

**Cause racine.** Deux causes empilées. Le script d'assemblage ne copiait aucun bundle de
ressources dans l'application, et `Bundle.module` ne tenait que par son chemin de repli
absolu vers `.build`, cassé au premier renommage du dossier de travail. Le chemin principal,
lui, ne pouvait pas fonctionner : l'accesseur généré par SwiftPM cherche sous
`Bundle.main.bundleURL`, donc à la racine du `.app`, où `codesign` refuse tout contenu
(« unsealed contents present in the bundle root ») et laisse le bundle sans ressources
scellées.

**Correctif.** Le script copie `<paquet>/.build/<config>/*.bundle` dans `Contents/Resources`,
seul emplacement que `codesign` scelle, et un accesseur du projet l'y cherche sous
`Bundle.main.resourceURL` avant de retomber sur `Bundle.module` pour les exécutables lancés
hors application. C'est la disposition que produit Xcode ; SwiftPM seul ne la produit pas.

### Une `NSWindow` retenue en Swift se libère deux fois à la fermeture

**Symptôme.** L'application meurt en `SIGSEGV` peu après la fermeture d'une fenêtre, jamais
pendant. Le rapport pointe `objc_release` sous `-[_NSWindowTransformAnimation dealloc]`, dans
le vidage du pool d'autorelease d'un commit CoreAnimation. Aucune ligne de code du projet
n'apparaît dans la pile.

**Cause racine.** `NSWindow.isReleasedWhenClosed` vaut `true` par défaut pour une fenêtre
construite par `init(contentRect:styleMask:backing:defer:)`. La classe qui l'ouvrait en
gardait aussi une référence forte : la fermeture libérait donc la fenêtre une fois de trop, et
l'animation de fermeture, qui survit au `windowWillClose`, lisait un objet déjà détruit.

**Correctif.** `isReleasedWhenClosed = false` dès la construction, dès lors qu'une propriété
Swift retient la fenêtre. La règle vaut pour toute `NSWindow` créée à la main.

### `ImageRenderer` rend une `ScrollView` vide

**Symptôme.** Une vue qui contient une `ScrollView` s'affiche sans aucun contenu dans les
images produites par `ImageRenderer` : seul le fond se voit, le texte et les composants à
l'intérieur disparaissent entièrement. Ni `swift build` ni les tests ne signalent quoi que ce
soit, la vue fonctionne normalement une fois l'application réellement lancée.

**Cause racine.** `ImageRenderer` rend hors écran, sans la machinerie AppKit de défilement
qu'une `ScrollView` réelle attend d'une fenêtre hôte. Le contenu qui dépend de cette
machinerie pour se dimensionner n'est jamais mesuré, donc jamais dessiné. Un `VStack` sans
`ScrollView`, à la même place, rend correctement.

**Correctif.** Aucun, côté application : la `ScrollView` reste la bonne solution pour un
contenu qui peut dépasser la hauteur disponible. Pour vérifier visuellement une vue de ce
genre par `ImageRenderer`, retirer temporairement la `ScrollView` (garder juste son contenu)
le temps du rendu, puis la remettre : ne jamais conclure d'une planche vide que la vue est
cassée sans avoir écarté ce piège en premier.

### `ImageRenderer` casse aussi `NSVisualEffectView`

**Symptôme.** Une vue enveloppant `NSVisualEffectView` (translucidité native) ne rend pas un
flou mais un aplat jaune vif barré d'un cercle rouge d'interdiction, quel que soit le
`material` ou le `blendingMode` (`.behindWindow` comme `.withinWindow`).

**Cause racine.** Même famille de piège que la `ScrollView` juste au-dessus : `ImageRenderer`
rend hors écran, sans fenêtre système. `NSVisualEffectView` a besoin de cette fenêtre pour
composer son flou et affiche le glyphe d'erreur standard d'AppKit quand elle en est privée.
Le matériau natif SwiftUI (`.ultraThinMaterial` et apparentés, `ShapeStyle` pur, aucune vue
AppKit) n'a pas ce besoin et rend correctement, flou et transparence compris.

**Correctif.** Pour un fond translucide qu'il faut pouvoir vérifier à l'image, préférer un
`SwiftUI.Material` à `NSVisualEffectView`. Si `NSVisualEffectView` reste nécessaire ailleurs
pour une raison qui le justifie, vérifier son rendu directement dans l'application lancée,
jamais par `ImageRenderer`, qui affichera toujours le glyphe d'erreur pour ce composant.

### Un cache calculé dans l'`init` d'une vue SwiftUI se refait à chaque passe

**Symptôme.** Un filtrage coûteux posé dans l'`init` d'une vue, avec `State(initialValue:)`,
pour ne le faire qu'une fois, reste sans effet : la vue perd autant d'images qu'avant.

**Cause racine.** SwiftUI reconstruit la vue à chaque passe, donc l'`init` s'exécute à chaque
image, même si sa valeur est ignorée. Un cache doit vivre dans un objet que `@State` garde en
vie, jamais dans une valeur calculée à la construction.

**Correctif.** Un cache tenu dans un `@State` garde le dernier résultat tant que ses entrées
ne changent pas. Pour qu'une vue voisine d'un changement ne soit plus reconstruite du tout,
l'envelopper dans une vue `Equatable` posée derrière `.equatable()`, et SwiftUI saute son
corps entier. Deux points à ne pas rater. La conformance s'écrit
`: View, @MainActor Equatable`, sans quoi la concurrence stricte refuse une égalité
nonisolated sur un type isolé par `View`. Et l'égalité **ignore les fermetures et les
liaisons**, neuves à chaque passe donc jamais égales : ce qui change vraiment passe soit par
les valeurs comparées, soit par les propriétés observées que lit la vue, qui l'invalident sans
passer par cette égalité.

### La touche Retour arrière n'égale pas `KeyEquivalent.delete`

**Symptôme.** La touche Supprimer ne fait rien, alors que toute la chaîne est en place :
l'action existe, les deux accords sont dans la table, et le routage mène bien à la
suppression. Suppr avant, elle, fonctionne.

**Cause racine.** AppKit livre la touche Retour arrière comme `NSDeleteCharacter`, U+007F,
quand `KeyEquivalent.delete` vaut `NSBackspaceCharacter`, U+0008. Un `switch` qui compare la
touche reçue à `.delete` ne matche donc jamais, retombe dans son `default`, et produit un nom
d'accord fait d'un caractère de contrôle qui n'est dans aucune table. La touche est morte
sans qu'aucun maillon ne paraisse fautif. Suppr avant marche parce que `.deleteForward` vaut
`NSDeleteFunctionKey`, U+F728, que le clavier envoie bien.

**Vérification.** Ne pas déduire ces valeurs, les mesurer. `KeyEquivalent.delete.character`
et un `NSEvent.keyEvent` de code 51 les donnent en trois lignes de Swift.

**Correctif.** Une fonction unique traduit les touches en noms d'accord, et reconnaît U+007F
comme U+0008. C'est la seule traduction du clavier vers la table, et elle est pure, donc
testée sans interface.

### Une poignée qui suit l'aperçu ne doit pas partir de sa position courante

**Symptôme.** L'extrémité d'une flèche tirée à la poignée fuit devant le curseur, de plus en
plus vite.

**Cause racine.** La poignée se redessine à la position de l'aperçu à chaque image, et la
translation d'un `DragGesture` est **cumulée depuis le début du geste**. L'appliquer à la
position courante ajoute donc la même course à un point qui l'a déjà parcourue.

**Correctif.** Figer la position de départ au premier cran, dans un `@State`, et n'appliquer
la translation qu'à elle.

### Un `swiftc` à liste de fichiers tenue à la main échoue sur un symbole qui n'a rien à voir

**Symptôme.** Un banc compilé par `swiftc` refuse de compiler avec « cannot find 'X' in scope »,
puis 'Y', puis 'Z', et ainsi de suite à chaque fichier ajouté au module depuis la dernière
fois.

**Cause racine.** La liste des fichiers à compiler vivait dans un **commentaire** du banc,
recopiée à la main dans un `swiftc`. Elle se périme à chaque fichier neuf, et l'erreur ne parle
jamais de la liste : elle parle du symbole manquant, ce qui envoie chercher le problème dans
le code.

**Correctif.** Un script **calcule** la liste. Il part du banc seul, compile, et chaque
« cannot find 'X' in scope » désigne un symbole dont il cherche la déclaration dans les
sources ; le fichier qui la porte entre dans la liste, avec ses extensions, et il recommence.
Huit tours suffisent, pour 41 fichiers.

**Deux pièges rencontrés en l'écrivant.** L'ordre alphabétique peut donner l'`extension` d'un
type avant sa déclaration : le script prenait l'extension, et le symbole restait introuvable
tour après tour. La déclaration est donc cherchée d'abord, ses extensions ensuite. Et
`mapfile` n'existe pas dans le bash 3.2 d'Apple, le seul installé sur macOS.

**Ce qu'il ne faut PAS essayer : compiler le module entier.** Hors SwiftPM, une expression peut
faire renoncer le vérificateur de types (« unable to type-check this expression in reasonable
time ») alors que `swift build` la compile sans broncher. Mesuré sans succès : `-O`, `-wmo`,
`-disable-batch-mode`, un lot par fichier, `-j 1`, et un seuil de solveur relevé à 120 s.
`-typecheck` seul passe, l'émission d'objets échoue. D'où la liste minimale.

### Un banc qui ne compile plus rejoue son ancien binaire et ment sans le dire

Des bancs se compilent à la main avec `swiftc`, en listant les fichiers de l'app dont ils
dépendent. Quand un de ces fichiers gagne une dépendance, la compilation échoue mais **le
binaire de la fois d'avant est toujours là**, et la commande qui suit dans la même ligne shell
le lance : le banc affiche un résultat complet, crédible, et vieux, qui allait être rapporté
comme s'il était frais.

**Correctif.** `rm -f` sur le binaire avant chaque compilation, et la ligne de compilation
tenue à jour dans l'en-tête de chaque banc. Un `grep error` sur la sortie de compilation ne
suffit pas si la commande suivante s'exécute quand même : chaîner avec `&&`, ou supprimer la
cible d'abord. Un résultat qui n'a pas été produit par le code qu'on vient d'écrire n'est pas
un résultat.

### La signature du bundle n'est pas celle qu'on croit, et Gatekeeper n'a pas trois portes

**Ce qu'on croit.** Qu'un bundle assemblé à la main est non signé, et qu'Apple Silicon le
refuse tant qu'on ne le signe pas. Les deux moitiés sont fausses, et croire la première fait
écrire un commentaire qui explique un problème qui n'existe pas.

**Mesure.** `codesign -dv .build/release/<App>` rend `flags=0x20002(adhoc,linker-signed)` : le
linker Swift signe déjà le binaire, en ad hoc, à la construction. L'app se lançait donc avant
qu'aucun `codesign` ne soit ajouté au script.

**Ce que la signature du bundle apporte vraiment.** La signature du linker ne couvre QUE le
binaire. L'Info.plist généré et les ressources copiées autour ne sont scellés que par un
`codesign` sur le bundle entier. C'est ce qui rend `codesign --verify --deep --strict` capable
de dire qu'un bundle transféré est arrivé intact, et c'est la seule raison de le faire.

**Gatekeeper, lui, est un autre sujet.** Une app sans Developer ID et sans notarisation est
bloquée au premier lancement quoi qu'on signe. Le chemin historique (clic droit puis Ouvrir) ne
débloque plus depuis macOS 15 : il reste les Réglages Système, ou
`xattr -dr com.apple.quarantine` sur l'app installée.

**Correctif.** Avant d'écrire dans un commentaire qu'une commande répare un problème, mesurer
l'état SANS elle. Ici, une ligne de `codesign -dv` séparait la vraie raison de la fausse.

### `SMAppService.agent` tue toute mise à jour d'une app signée ad hoc

**Symptôme.** L'agent launchd inscrit par `SMAppService.agent(plistName:)` lance bien l'app la
première fois. Après un réassemblage du bundle, launchd tue son instance à la naissance :
rapport `SIGKILL (Code Signature Invalid)`,
`termination: CODESIGNING, Launch Constraint Violation` ; `launchctl print` donne
`job state = spawn failed`, `last exit code = 78: EX_CONFIG`, `runs = 5`, et
`properties = ... needs LWCR update | has LWCR`. Puis BTM (`sfltool dumpbtm`) passe l'agent en
`disabled`.

**Cause racine.** L'inscription attache au job une contrainte de lancement (LWCR) dérivée de la
signature du bundle. Sans compte développeur, la signature est ad hoc et son CDHash change à
chaque `codesign` : le bundle suivant viole la contrainte. `unregister` puis `register`, ce
qu'Apple recommande quand l'exécutable change, n'a pas rafraîchi la contrainte : même une
inscription neuve (clé de premier lancement effacée) a été tuée pareil.

**Correctif.** Un agent classique dans `~/Library/LaunchAgents`, chargé par
`launchctl bootstrap gui/<uid>` : mesuré le même jour, il a démarré l'app, survécu à un
remplacement du binaire par un autre CDHash (`launchctl kickstart`), relancé après `SIGSEGV`
en une seconde, et laissé une sortie propre (code 0) tranquille.

Autres mesures, sur des jobs factices. `KeepAlive.SuccessfulExit = false` implique le
lancement au chargement. `bootout` tue le process du job. `XPC_SERVICE_NAME` vaut « 0 » pour un
job launchd ordinaire, il ne porte pas le label : pour savoir si on est l'instance de launchd,
on compare son `pid` à celui de `launchctl print gui/<uid>/<label>`.

### Un `Timer` qui a tiré ne se met pas à nil, et un garde `timer == nil` ne rouvre jamais

**Symptôme.** Un personnage animé restait planté une à deux minutes avant de repartir.

**Cause racine.** L'objet garde son minuteur dans `timer`, et `resume` s'ouvre sur
`guard timer == nil, ...`. Un `Timer` non répétitif devient invalide quand il tire, mais la
référence, elle, reste : `timer` n'était plus jamais nul après la première étape, et `resume`
sortait sans rien relancer. Il ne repartait que lorsqu'une autre minuterie déjà en route
replanifiait d'elle-même. Le chemin d'interruption, lui, marchait : il remettait la référence
à nil.

**Correctif.** Le minuteur s'oublie dans son propre rappel. `isValid` et « non nul » ne disent
pas la même chose : un garde qui teste la présence d'une minuterie doit être appuyé par une
remise à nil au moment du tir, sinon il se ferme pour toujours.

### Une échéance de 45 minutes qui ne tombe pas : `Timer.scheduledTimer` n'inscrit qu'en mode par défaut

**Symptôme.** Une échéance de 2 700 s tire après 2 799,2 s, mesurées sur l'horloge absolue du
journal (`CACurrentMediaTime`). Le minuteur n'était pas perdu, il était EN RETARD, et c'est
bien pire à diagnostiquer : rien ne manque au journal, la ligne finit par arriver. Sans la
mesure on conclut « le minuteur ne part pas » et on va chercher la panne ailleurs.

**Cause racine.** `Timer.scheduledTimer(withTimeInterval:repeats:)` inscrit le minuteur dans le
SEUL mode par défaut de la boucle. Ce mode est **suspendu** dès qu'une boucle de suivi prend la
main : un menu déroulé, un redimensionnement, un défilement. Une échéance qui court trois
quarts d'heure traverse forcément plusieurs de ces épisodes.

**Correctif.** Tout minuteur se construit à la main puis passe par
`RunLoop.main.add(t, forMode: .common)`. `Timer.scheduledTimer` est un piège, pas un raccourci.

---

### `INFocusStatusCenter.requestAuthorization` tue une app signée ad hoc, même avec la clé d'usage

**Symptôme.** La demande d'autorisation tue le processus, code 134, avec « This app has
crashed because it attempted to access privacy-sensitive data without a usage description ».

**Cause racine.** Sans `NSFocusStatusUsageDescription` dans le `Info.plist`, la demande meurt
sur SIGABRT. La clé posée, elle meurt encore avec le même message, qui désigne alors une clé
présente. L'entitlement `com.apple.developer.focus-status` ajouté à une signature ad hoc fait
tuer le binaire dès le lancement, SIGKILL, code 137 : c'est un entitlement restreint, qui
demande un profil de provisioning signé par Apple.

**Correctif.** Sans compte Apple Developer, l'API est inutilisable. Ne pas la contourner en
lisant `~/Library/DoNotDisturb/DB/`, fichier privé sans format documenté. Avec un compte,
`focusStatus.isFocused` à `false` sous `authorizationStatus == .notDetermined` ne prouve pas
l'absence de concentration.

---

### Une fenêtre transparente qui couvre l'écran avale tous les clics, même là où elle est vide

**Cause racine.** Une `NSWindow` sans bordure qui couvre l'écran reste, pour le gestionnaire
de fenêtres, une fenêtre pleine taille. Renvoyer `nil` depuis `hitTest(_:)` n'implémente pas
le clic traversant : AppKit ne trouve aucune vue, ignore l'événement et ne le retransmet pas à
la fenêtre en dessous. Tout le bureau devient inerte.

**Correctif.** Ne pas couvrir l'écran : la fenêtre fait la taille de son contenu, et un
glisser déplace la fenêtre elle-même. `ignoresMouseEvents = true` rend la fenêtre entière non
cliquable, contenu compris.

---

### Une app lancée depuis son dossier de build disparaît à la construction suivante

**Symptôme.** L'app tournait, personne ne l'a quittée, et elle n'est plus là. Aucun message,
aucun plantage ; on soupçonne un agent d'avoir tué le processus.

**Cause racine.** Le script de construction fait `rm -rf` sur le `.app` avant de le
réassembler. Le processus survit à la disparition de son exécutable, dont il garde l'inode,
mais pas à celle de ses ressources ouvertes à la demande : la première ressource lue après une
construction ne trouve plus son fichier.

**Correctif.** Le script prévient quand une instance tourne, avec son PID, sans la tuer.
Personne n'a envoyé de signal, inutile de chercher lequel.

---

### `CADisplayLink` ne tire jamais dans une app `.accessory` dont la fenêtre n'est jamais key

**Symptôme.** Une animation cadencée par le lien d'affichage ne part pas, puis tout se rejoue
d'un coup dès qu'on bouge la souris, ce qui se déguise en « délai ».

**Cause racine.** Les liens obtenus par `NSView.displayLink(target:selector:)` ne reçoivent
aucun rappel dans une fenêtre `.floating` d'une app `.accessory` jamais key : zéro tick en
quinze secondes, mesuré. `beginActivity` n'y change rien. Les événements souris réveillent la
fenêtre. Une `SCNView` s'anime pourtant en continu avec son propre lien interne, donc l'écran
bouge et fait croire que les rappels fonctionnent.

**Correctif.** Pas de `CADisplayLink` dans ce type d'app : des minuteries du runloop, dont on
a prouvé qu'elles tirent, avec le pas de temps mesuré à chaque tour. Un cadencement se prouve
par un tick reçu, jamais par « le lien est armé » ni par « l'écran bouge ». Une sonde de tick
s'écrit sur stderr, un `print` vers un fichier part par blocs et se perd si on tue le
processus.

---

### Une fenêtre `canJoinAllSpaces` ne s'occulte jamais, ni sur le plein écran ni sur l'écran de verrouillage

**Symptôme.** Un garde-fou qui coupe le rendu sur l'occultation ne se déclenche jamais :
l'app dessine soixante images par seconde par-dessus un film en plein écran, ou toute la nuit
derrière l'écran de verrouillage.

**Cause racine.** Une fenêtre `.floating` et `.canJoinAllSpaces` suit le bureau affiché, y
compris celui d'une app en plein écran ou de l'écran de verrouillage. Elle n'est jamais
recouverte, donc `NSWindow.occlusionState` ne perd jamais `.visible`. La dépense vient du seul
fait de soumettre des images (attente dans `CAMetalLayer.nextDrawable`), pas du calcul.

**Correctif.** Mesurer le plein écran soi-même et couper le rendu explicitement. Pour le
verrouillage, observer les notifications distribuées `com.apple.screenIsLocked` et
`com.apple.screenIsUnlocked`, et ne pas relancer au réveil des écrans, qui se rallument
encore verrouillés.

---

### Le cadre d'une fenêtre plein écran se mesure avec `CGWindowListCopyWindowInfo`, il ne se devine pas

**Symptôme.** Une détection de plein écran se croit en permanence devant un plein écran, ou
ne reconnaît jamais celui d'un écran secondaire.

**Cause racine.** Avec `.optionOnScreenOnly` et `.excludeDesktopElements`, les fenêtres
ordinaires sont couche 0 et commencent sous la barre des menus, donc une fenêtre agrandie ne
couvre pas l'écran. Le Dock (couche 20) et le Centre de notifications (couche 21) couvrent
l'écran entier en permanence. Le repère de `CGWindowList` a son origine en haut à gauche de
l'écran principal, celui d'AppKit en bas à gauche.

**Correctif.** Filtrer sur la couche 0 et retourner les coordonnées avant de comparer aux
cadres des `NSScreen`. Le nom du propriétaire se lit sans autorisation d'enregistrement de
l'écran ; seul le nom des fenêtres est protégé depuis macOS 10.15.

---

### La musique du Mac ne se voit pas dans les seules notifications de Musique.app

**Symptôme.** Une détection de lecture audio reste muette alors que de la musique passe.

**Cause racine.** Écouter `com.apple.Music.playerInfo` et `com.apple.iTunes.playerInfo` ne
couvre que Musique : Spotify publie `com.spotify.client.PlaybackStateChanged`, et une vidéo du
navigateur, Deezer ou VLC ne publient rien. Une lecture déjà en cours au lancement n'envoie
aucune notification. Et Musique publie `Playing` aussi pour un clip vidéo.

**Correctif.** Lire et suivre `kAudioDevicePropertyDeviceIsRunningSomewhere` du périphérique
de sortie par défaut (`CoreAudio/AudioHardware.h`) : publique, sans permission, sans accès au
contenu, elle vaut 1 dès qu'un processus joue du son. Des durées minimales séparent une
musique d'un son d'interface.

---

### Une fenêtre à origine absolue reste sur un écran disparu quand la configuration change

**Symptôme.** Après une veille avec un écran externe débranché, la fenêtre n'est plus visible
ni cliquable, et rien ne permet de la rappeler sans relancer l'app.

**Cause racine.** Rien n'écoutait `NSApplication.didChangeScreenParametersNotification`, seule
notification publiée quand un écran arrive, s'en va, ou change de résolution ou de Dock. Un
`NSScreen` retenu sans fin peut désigner un écran qui n'existe plus. Et un repli
`window.screen ?? NSScreen.screens.first` vise l'écran principal justement quand la fenêtre est
hors champ et que `window.screen` rend `nil`.

**Correctif.** Relire la géométrie à chaque changement et ramener la fenêtre dans une zone
visible, oublier l'écran retenu quand il disparaît, et ne jamais replier sur l'écran principal
pour une fenêtre hors champ.

---

### `decompressed(using: .zlib)` ne lit pas le zlib, il lit le deflate brut

**Symptôme.** Des données compressées par `zlib.deflateSync` de Node rendent toutes `nil` à la
lecture par Foundation, sans erreur.

**Cause racine.** `NSData.CompressionAlgorithm.zlib` désigne le deflate brut (RFC 1951), pas
le format zlib (RFC 1950) qui ajoute un en-tête de deux octets et une somme Adler-32 de quatre.
Les deux formes ne diffèrent que de ces six octets.

**Correctif.** Compresser en `deflateRawSync`, jamais en `deflateSync`, et vérifier
l'aller-retour sur le vrai fichier. Un chargeur qui rend `nil` en silence doit journaliser son
échec.

---

### Une détection bâtie sur l'échantillonnage d'un compteur est aveugle à la veille du Mac

**Symptôme.** Une longue absence écran rabattu n'est jamais détectée au retour, alors que la
même absence Mac allumé l'est.

**Cause racine.** Le retour se déduisait de la retombée du compteur d'inactivité de macOS,
lu par un `Timer`, arrêté avec la machine. Au réveil, l'utilisateur a déjà touché le clavier,
`secondsSinceLastEventType` est retombé à zéro avant que `NSWorkspace.didWakeNotification`
ne fasse regarder l'app, et le détecteur ne voit qu'une retombée depuis la dernière valeur
d'avant la veille.

**Correctif.** La veille se déclare au lieu de s'échantillonner : noter l'heure et
l'inactivité acquise sur `NSWorkspace.willSleepNotification`, puis ajouter la durée de la
veille au réveil. La veille, le `SIGSTOP` d'App Nap et une relance de l'app sont les trois
trous de tout échantillonnage.

---

### `NSScreen.visibleFrame` garde la bande du Dock sur un bureau en plein écran

**Symptôme.** Une fenêtre qui suit tous les bureaux se cale sur le Dock alors qu'il a
disparu en plein écran.

**Cause racine.** Une app en plein écran vit sur son propre `Space`, où le Dock est retiré.
`NSScreen.visibleFrame` et `CoreDockGetRect` décrivent le bureau ordinaire et gardent sa
bande. Rien ne le signale, les deux mesures répondent exactement ce qu'on leur demande.

**Correctif.** Croiser avec une mesure du plein écran et ignorer le Dock tant qu'il est
actif. Une mesure du système répond pour le bureau ordinaire, pas pour le bureau affiché.

---

### Une cadence de rendu ne se choisit pas, elle se divise

**Symptôme.** Une cadence réduite (45 images par seconde) saccade au lieu d'économiser.

**Cause racine.** Un écran ne tient que les cadences que sa granularité divise.
`NSScreen.displayUpdateGranularity` d'un écran 120 Hz vaut 1/240 s, donc 120, 80, 60, 48,
40, 30, 24 et rien entre ; un écran 60 Hz ne tient que 60, 30, 20, 15. Une cadence hors
palier fait tomber les images à un rythme irrégulier que SceneKit ne lisse pas.

**Correctif.** Choisir un palier commun à tous les écrans visés, 30 pour 60 et 120 Hz, et le
garder par un test. La dépense suit le nombre d'images soumises, donc moitié moins d'images
vaut à peu près moitié moins de dépense.

---

### Un rendu SceneKit hors écran dans une cible non sRGB sort les couleurs délavées

**Symptôme.** Une couleur rendue par SceneKit dans une image sort nettement plus orangée ou
plus sombre que sa valeur, par exemple (255, 211, 173) rendue en (255, 166, 107).

**Cause racine.** SceneKit calcule en linéaire. Dans une cible `.bgra8Unorm`, il écrit ces
valeurs linéaires telles quelles, et CoreGraphics les relit comme du sRGB.

**Correctif.** Une cible `.bgra8Unorm_srgb`, dont le GPU fait la conversion à l'écriture.

---

## JavaScript et Node

### `node --test test/` échoue avec `Cannot find module .../test` alors que le dossier existe

**Cause racine.** Les Node récents (constaté sur la v25) ne prennent plus un répertoire comme
argument de `--test`, l'argument est traité comme un point d'entrée de module. Les exemples en
ligne avec `node --test test/` datent des versions où c'était accepté.

**Correctif.** `node --test` sans argument : la découverte par défaut trouve récursivement les
`*.test.js`. Pour un seul fichier, le passer explicitement, `node --test test/png.test.js`.

### Un masque bit à bit en JavaScript rend un négatif, et la comparaison échoue toujours

**Symptôme.** Une recherche de références ARM64 en JavaScript tourne sans erreur et conclut
« aucune référence », même sur un cas certain, ce qui fait croire que la donnée cherchée n'est
référencée par aucun code.

**Cause racine.** Les opérateurs bit à bit de JavaScript travaillent sur des entiers **signés**
32 bits. `instruction & 0x9f000000` rend donc un nombre négatif dès que le bit 31 est mis, et
la comparaison `=== 0x90000000` (un littéral positif, 2 415 919 104) est toujours fausse. Or
le bit 31 est mis sur presque toutes les instructions ARM64 utiles, `ADRP` en tête.

**Correctif.** Toujours ramener le résultat d'un masque en non signé : `((w & m) >>> 0)`. Et
**valider la méthode sur un cas connu avant de conclure quoi que ce soit** : tant que la
recherche ne retrouve pas un couple dont on sait qu'il existe, elle est fausse, pas le binaire.

### Une comparaison qui ne tient qu'au choix entre `!=` et `!==`

**Symptôme.** Pour écarter des éléments alimentés par une autre source, on écrit
`found.source != null`. Le code est juste, tous les tests passent. Puis un relecteur ou un
linter resserre l'égalité en `!==`, de bonne foi, parce que le reste du dépôt est en égalité
stricte. Des dizaines d'éléments disparaissent alors en silence, et aucun test générique ne
bronche.

**Cause racine.** Les éléments concernés ne portaient pas de champ `source`, donc
`found.source` valait `undefined`. En égalité lâche, `undefined != null` est faux et l'élément
passait ; en égalité stricte il aurait été rejeté. Le comportement correct tenait à un
caractère, et rien dans le code ne le disait.

**Correctif.** Deux, et il faut les deux. Rendre `source: null` **explicite** sur ces éléments,
pour que les deux tables aient la même forme et que l'égalité stricte soit sûre. Et un test qui
verrouille le résultat plutôt que la forme, en comptant les éléments qui doivent survivre au
filtre.

---

### Un lockfile pnpm 10 est rejeté par pnpm 11

**Symptôme.** `pnpm install` refuse de tourner et signale que le lockfile contient des entrées
que les politiques actives rejettent.

**Cause racine.** pnpm 11 applique `minimumReleaseAge`, qui refuse tout paquet publié depuis
moins de 24 heures, protection contre la compromission d'un paquet en amont. Un lockfile résolu
la veille avec pnpm 10 contient forcément de telles entrées.

**Correctif.** `pnpm clean --lockfile` puis `pnpm install`, qui rebâtit la résolution en
respectant la politique. Ne jamais relâcher la politique pour faire passer l'installation.

---

### `pnpm install` échoue sur `ERR_PNPM_IGNORED_BUILDS` et ajouter `pnpm.onlyBuiltDependencies` n'y change rien

**Cause racine.** Deux choses se combinent, et la seconde annule la correction qu'on vient
d'écrire.

Le `.npmrc` du modèle pose `ignore-scripts=true`, ce qui est voulu : un paquet installé
n'exécute aucun script d'installation tant qu'on ne l'a pas autorisé nommément, ce qui empêche
une dépendance compromise de lancer du code au moment de l'installation. Certains paquets en
ont pourtant réellement besoin, comme `sharp` qui compile son binaire natif et `unrs-resolver`
que tire `eslint-config-next`.

Le réflexe est d'ajouter un champ `pnpm.onlyBuiltDependencies` dans `package.json`. pnpm 11 ne
lit plus ce champ, il l'ignore en le signalant par un avertissement noyé dans la sortie, et
l'erreur d'origine réapparaît à l'identique. Le réglage a déménagé dans `pnpm-workspace.yaml`
sous le nom `allowBuilds`, et c'est une table où chaque paquet porte un booléen.

**Correctif.**

```yaml
allowBuilds:
    sharp: true
    unrs-resolver: true
```

Un `husky` qui échoue en même temps sur `.git can't be found` n'a aucun rapport : `pnpm
install` a tourné avant `git init`. Initialiser le dépôt d'abord.

---

### ESLint échoue à trouver un plugin qu'un `eslint-config` déclare pourtant en dépendance

**Cause racine.** La couche de compatibilité `FlatCompat`, utilisée pour charger d'anciennes
configurations partagées comme `eslint-config-next`, résout les plugins depuis la racine du
projet. Sous npm, l'arborescence à plat hissait ces plugins jusqu'à la racine et ça
fonctionnait par accident. pnpm ne hisse rien par défaut, donc un plugin déclaré comme
dépendance d'un `eslint-config` reste invisible depuis la racine.

**Correctif.** Une configuration plate native, sans `FlatCompat` ni `eslint-config-next` :
chaque plugin (`eslint-plugin-react`, `eslint-plugin-jsx-a11y`, `@next/eslint-plugin-next`,
etc.) est importé et déclaré explicitement, en dépendance directe du projet.

---

### `pnpm test` échoue avec une erreur de configuration Jest qui ne mentionne aucun paquet manquant

**Cause racine.** Depuis Jest 28, `jest-environment-jsdom` n'est plus livré avec le paquet
`jest` et doit être installé explicitement dès qu'un test cible l'environnement `jsdom`
(composants React, DOM). Sans lui, Jest échoue à résoudre l'environnement déclaré et le
message d'erreur ne dit à aucun moment qu'il s'agit d'une dépendance absente.

**Correctif.** `jest-environment-jsdom` est une dépendance de développement explicite du
projet (`package.json`), jamais supposée transitive de `jest`.

---

### `pnpm types:check` signale `TS5097` sur des fichiers qu'on n'a pas touchés

**Cause racine.** Deux causes différentes produisent exactement le même message, et les distinguer
fait gagner beaucoup de temps.

La première est réelle. Le code tourne sous le **décapage de types natif de Node**, qui exige
que tout import relatif porte son extension `.ts` explicite. TypeScript refuse cette écriture par
défaut, donc `allowImportingTsExtensions` doit rester à `true` dans `tsconfig.json`. Le retirer casse
tout le code exécuté par Node.

La seconde est un fantôme. `incremental` étant actif, `tsc` garde son cache dans
`tsconfig.tsbuildinfo`. **Un changement de `tsconfig.json` ne l'invalide pas toujours**, donc le
cache continue de faire remonter des erreurs déjà corrigées, sur des fichiers que la session n'a pas
ouverts, ce qui envoie chercher un problème inexistant chez les autres.

**Correctif.** Vérifier d'abord qu'`allowImportingTsExtensions` est bien présent. Si l'erreur
persiste alors qu'elle ne devrait plus, supprimer `tsconfig.tsbuildinfo` et relancer. Ce fichier
n'est pas versionné, donc le supprimer ne coûte rien.

---

### Un processus Node gonfle en mémoire au fil des jours, sans fuite visible dans son état

**Cause racine.** Chaque attente d'une boucle de source posait un écouteur `abort` sur le
signal d'arrêt global sans jamais le retirer quand le minuteur se déclenchait normalement.
`{ once: true }` ne protège pas, il ne retire l'écouteur qu'après un `abort` qui n'arrive
qu'à l'extinction du processus. Vingt boucles y laissaient environ 250 000 closures par
jour, chacune retenant son minuteur et son `resolve`. Le symptôme visible arrive
tard, un `MaxListenersExceededWarning` puis une empreinte mémoire qui monte sans que l'état
diffusé grossisse.

**Correctif.** Retirer l'écouteur dans la fonction de terminaison elle-même, donc
`signal.removeEventListener('abort', done)` à côté du `clearTimeout`. Toute nouvelle boucle passe
par une attente partagée plutôt que de recopier le motif.

---

### Une visite toute fraîche ne lit rien, 403 sur la clé et le premier segment

**Symptôme.** Sur un navigateur sans cookie du site, le lecteur affiche le bon morceau mais la lecture ne démarre jamais. La playlist part en 200, la clé HLS et le premier segment repartent en 403. Un rechargement suffit à tout remettre d'aplomb, ce qui fait passer le bug pour un caprice de réseau. Reproduit deux fois sur cinq en local.

**Cause racine.** `sessionId()` crée la session à la demande, dans la requête qui en a besoin. Le lecteur demande deux playlists quasi simultanément, celle du morceau courant et celle du préchargé. Sans cookie `sid`, chacune en génère un et le pose dans sa réponse : le navigateur ne garde que le dernier, et les jetons signés par la playlist perdante deviennent invalides pour la session retenue. Les jetons sont bien liés à la session, c'est la session qui n'était pas encore posée.

**Règle qui en découle.** Une session à création paresseuse ne se laisse jamais créer par plusieurs requêtes concurrentes. Un middleware serveur la pose sur toute requête hors média, document compris, de sorte que toute requête média la trouve déjà là. Sans s'appuyer sur `sec-fetch-dest`, que Safari avant 16.4 n'envoie pas.

---

### Impossible d'écrire dans un éditeur TipTap : la frappe réécrit le texte déjà là

**Symptôme.** Taper dans un champ riche ne produit rien, le caret ne bouge pas, et la console
crache à chaque frappe `RangeError: Can not convert <"…"> to a Fragment (looks like multiple
versions of prosemirror-model were loaded)`.

**Cause racine.** Deux versions de `prosemirror-model` cohabitent dans `node_modules`, l'une
tirée par `@tiptap/pm`, l'autre par les paquets `prosemirror-*` transitifs. Le nœud reparsé
vient de l'autre copie du module, `Fragment.from` le refuse, et la vue restaure le DOM.

**Correctif.** `find node_modules -maxdepth 4 -type d -name "prosemirror-model"` : plus d'un
résultat, c'est ce piège. `pnpm dedupe`, puis redémarrer Vite, dont le cache
`node_modules/.vite/deps` garde le bundle d'avant jusqu'au démarrage suivant.

---

## Tests

### Un test qui lit l'heure de la machine échoue une nuit sur trois

Un test partait de `Date()` et attendait que le moteur résolve une action. Lancé à 00:13, il
tombait dans une plage horaire gérée par le code (23:30 à 07:30) : le moteur s'endormait, ne
résolvait rien, et le test échouait en accusant la résolution. Le même test passe la journée.

**Correctif.** Un test qui traverse une règle horaire fixe l'heure au lieu de lire celle de la
machine. Et devant un test qui échoue, vérifier l'heure avant de suspecter le code.

---

### Un test vert en local échoue par intermittence en CI sur un timestamp

**Symptôme.** Une assertion qui compare une date formatée à `now()` passe toujours en local et
échoue au hasard sur un runner de CI, à une seconde près.

**Cause racine.** `now()` est réévalué à l'assertion, après la création du modèle et la requête
HTTP. Sur une machine lente, la seconde a changé entre-temps. La CI le révèle, elle ne le crée
pas.

**Correctif.** Figer l'horloge en tête du test (`freezeSecond()` ou `freezeTime()` en Laravel),
jamais assouplir l'assertion.

---

### Playwright : un champ rempli juste après `goto` se retrouve vide à la soumission

**Symptôme.** Un test E2E remplit un formulaire dès `page.goto()` puis soumet ; le navigateur
bloque sur « Please fill out this field » ou le serveur refuse les identifiants. La capture
montre un champ vide, souvent le premier.

**Cause racine.** Le HTML rendu par le serveur est interactif pour Playwright avant que React
ait hydraté. La saisie tombe dans l'input natif, puis l'hydratation réaligne les champs
contrôlés sur l'état initial (`''`) et efface la valeur.

**Correctif.** Attendre un marqueur posé à l'hydratation (par exemple
`await expect(page.locator('html[data-hydrated]')).toBeAttached()`) avant la première
interaction.
