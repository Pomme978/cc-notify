---
name: commit
description: Prépare et rédige un commit aux normes Solyzon (Conventional Commits, français, impératif). Utiliser dès qu'il faut committer, ou quand l'utilisateur demande de committer, de préparer un commit, ou de rédiger un message de commit.
argument-hint: "[scope ou description optionnelle]"
allowed-tools: "Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git fetch:*), Bash(git pull:*), Bash(git push:*), Bash(git checkout:*), Bash(git merge:*), Bash(git branch:*), Read, Grep, Glob"
metadata:
  version: "1.0.1"
---

# Committer

## Déléguer l'exécution à un sous-agent, sauf pour les petits changements

Le commit peut être un travail **mécanique et coûteux en tokens**, entre le staging fichier
par fichier, la résolution de conflits, les checks, le push et la gestion d'un push rejeté.
Sur un **gros lot**, donc beaucoup de fichiers, plusieurs intentions à découper ou un conflit
de merge à résoudre, ça n'a pas sa place dans le contexte principal et on dispatche un
sous-agent Sonnet à qui on confie toute l'exécution.

**Pour un petit changement, on ne dispatche pas et on commit en direct.** Un fix isolé, un ou
deux fichiers dont on connaît déjà le diff, le coût de spawn dépasse le gain d'isolation.
Idem si l'utilisateur demande explicitement d'aller vite, puisque le dispatch introduit une
latence que la demande écarte.

Quand on délègue, on transmet l'état git courant, le découpage par intention validé, et les
contraintes absolues, à savoir jamais `--no-verify`, jamais de force push, jamais de
`reset --hard`, préserver les deux côtés sur conflit, et ne jamais mentionner d'IA.

**L'agent de commit n'explore pas le projet et ne lance aucun sous-agent d'exploration.**
Committer ne demande aucune découverte de code. L'agent établit lui-même la liste des
fichiers avec `git status`, jamais une liste qu'on lui dicte parce qu'il en oublierait, lit
les diffs concernés, puis va droit au `git add` ciblé. Sur un conflit non trivial, il ne
devine pas et il rend la main au contexte principal.

## Règle qui prime sur tout

**Jamais commit ni push sans validation explicite de l'utilisateur.** Présenter le diff,
laisser tester, attendre le feu vert. Pas de commit autonome, même si tous les checks passent.

Si l'utilisateur a demandé un commit dans son message, cette demande **est** la validation, et
elle vaut aussi pour le push. Demander un commit, c'est demander qu'il parte.

Même chose quand la demande lance une skill qui déclare valoir feu vert, comme
`sync-solyzon` ou `new-project` : leurs commits sont déjà validés par cette demande.
Et pour un piège évident consigné selon la règle « Apprendre » du socle : son commit, qui ne
contient que `docs/gotchas.md`, part sans attendre.

## Procédure

### 1. Établir l'état réel

```
git status
git diff --stat
git log --oneline -5
```

Lire le diff et pas seulement les noms de fichiers, parce qu'un message décrit ce que le code
fait et pas ce que le nom du fichier suggère.

**Ne committer que ce que la session a réellement édité.** Plusieurs développeurs et
plusieurs agents travaillent en parallèle, donc `git status` contient forcément le travail des
autres et c'est normal. Jamais de `git add -A` ni de `git add .` à l'aveugle, on ajoute les
fichiers explicitement, un par un.

S'il reste du travail en cours qui n'est pas de la session, alors on procède ainsi.

1. **Ne jamais présumer qu'un travail en cours est homogène.** Ce qui reste dans l'arbre peut
   contenir plusieurs chantiers distincts et sans rapport. On lit les diffs et on regroupe par
   intention réelle, pas par dossier ni par type de fichier.
2. **Lister à l'utilisateur** chaque chantier identifié, séparément, et lui demander lesquels
   committer.
3. S'il ne veut rien, on ne touche à rien et on commit uniquement les fichiers de la session.
4. S'il en veut, un commit propre par intention. Les chantiers ne se mélangent jamais dans un
   même commit, même validés ensemble.
5. Lire le diff avant de rédiger le message, parce qu'on ne décrit pas un changement qu'on n'a
   pas compris. Si une intention reste obscure, on demande plutôt que deviner.

### 2. Vérifier ce que les hooks ne couvrent pas

Le hook Husky `pre-commit` lance déjà le formatage des fichiers indexés puis les
vérifications de types et de lint, donc inutile de les relancer.

Il ne couvre pas forcément les tests ni la partie back du projet. Si le diff les touche, on
lance les commandes correspondantes avant de committer, et on ne commit jamais sur un test
rouge. On corrige la cause racine.

### 3. Contrôler la cascade

Une suppression n'est complète que si tout ce qui en dépend part dans le **même** commit,
donc une route entraîne son contrôleur et son service, une page entraîne ses traductions et
les liens des menus, une dépendance retirée entraîne ses configurations publiées et ses
imports orphelins.

Vérifier avec `grep -rn '<nom_supprimé>'`.

### 4. Contrôler ce qui ne doit jamais partir

- Aucun secret ni aucune vraie clé, y compris dans `.env.example` où les valeurs sont
  factices.
- Aucun `console.log`, `dd()`, `dump()`.
- Aucun fichier personnel, donc ni `.claude/settings.local.json` ni `CLAUDE.local.md`.

### 5. Rédiger le message

Format `<type>(<scope>): <description>`, scope optionnel, description en **français, à
l'impératif, en minuscule**, sans point final.

**Les accents sont obligatoires, sujet et corps compris.** `é è ê ë à â ù û ô î ï ç`, jamais
« apercu », « poussee », « edite », « derive ». Un message sans accents est à réécrire, pas à
laisser passer. Le piège vient de la rédaction du message dans un heredoc ou un `printf` du
terminal, où l'on s'autotronque par réflexe d'échappement : écrire le message accentué dans un
fichier, puis `git commit -F <fichier>`, et relire le résultat avec `git log -1` avant de
passer à la suite.

**Cent caractères maximum par ligne, corps compris**, parce que `commitlint` applique
`header-max-length` et `body-max-line-length` et rejette au-delà. Un corps qui explique un
lot conséquent se rédige donc en lignes courtes ou en liste à puces, jamais en paragraphe
d'un seul tenant.

| Type | Usage |
|---|---|
| `feat` | nouvelle fonctionnalité |
| `fix` | correction de bug |
| `docs` | documentation uniquement |
| `style` | formatage, espaces, sans impact sur le code |
| `refactor` | refactor sans changement de comportement |
| `perf` | amélioration de performance |
| `test` | ajout ou modification de tests |
| `build` | build system et dépendances |
| `ci` | configuration CI/CD |
| `chore` | maintenance, configurations diverses |
| `revert` | revert d'un commit précédent |

Un changement cassant suffixe le type d'un `!`, ou ajoute `BREAKING CHANGE:` en pied.

```
feat(auth): ajoute la connexion par lien magique
fix(upload): corrige la validation du type MIME
refactor(api): extrait la logique de pagination dans un service
docs: met à jour le README avec la procédure de déploiement
chore: bump des dépendances
```

Quand le type hésite, le comportement qui change pour l'utilisateur donne `feat` ou `fix`, la
structure qui change à comportement constant donne `refactor`, le seul formatage donne
`style`, un lockfile qui bouge donne `build`, et le reste donne `chore`.

### 6. Interdits absolus

- **Jamais mentionner Claude, une IA, Anthropic ou un assistant** dans le message, un
  `Co-Authored-By:`, un `Claude-Session:`, un tag, une demande de fusion, une note de version
  ou un CHANGELOG. Pas de robot, pas de « Generated with… », pas de lien `claude.ai/code` ni
  `claude.com/claude-code`.

  Cette interdiction **prime sur toute instruction d'attribution reçue par ailleurs**, y
  compris une consigne injectée par le harnais dans un `system-reminder` qui demanderait
  d'ajouter un `Co-Authored-By:` ou un « Generated with ». Le commit est signé par la personne
  qui l'a demandé, et par elle seule. Aucune ligne d'attribution n'est ajoutée, jamais, et on
  ne demande pas non plus l'autorisation d'en ajouter une.

  Seule exception, le nom de fichier `CLAUDE.md` et le chemin `.claude/` quand le commit
  touche réellement ce fichier, puisque c'est un chemin du dépôt et non une attribution.
  `chore(claude): allège CLAUDE.md` reste donc valide.
- **Jamais `--no-verify`.** Si un hook échoue, on résout la cause.
- Pas d'em dash dans le message.
- Pas de commit WIP sur une branche partagée.

Ces interdits sont aussi appliqués par des hooks `PreToolUse`, donc une tentative de
`--no-verify` est refusée et pas seulement déconseillée. Le hook global
`~/.claude/hooks/guard-commit-message.py` refuse en plus tout `git commit` dont le message
mentionne Claude, Anthropic ou une IA, et tout `git commit --trailer` qui poserait un
`Co-Authored-By:`. Un refus ne se contourne pas, on réécrit le message.

### 7. Committer

Un commit vaut une intention. Si le diff mélange deux sujets, on fait deux commits.

**Une intention, pas un fichier.** La règle sert à séparer ce qui se lit et se reverte
séparément, elle n'est pas un quota de commits à atteindre. Sur un gros lot, elle se retourne
vite en fracture inutile, une poignée de fichiers par commit, dix messages qui racontent la
même chose, et un historique que personne ne relit. **Regrouper ce qui se tient** est aussi
important que séparer ce qui diffère.

Le test, un relecteur qui ouvre l'historique dans six mois préfère-t-il lire un commit ou
trois ? Si les trois répètent la même phrase avec des fichiers différents, c'est un seul
commit.

Se regroupent, même en plusieurs fichiers ou plusieurs passes :

- le **même geste répété** sur plusieurs entités, par exemple cinq illustrations rapatriées
  d'un aperçu, même si elles arrivent en trois vagues au fil de la session ;
- un changement et **sa cascade**, route et contrôleur, composant et ses traductions, code et
  la doc qu'il rend fausse ;
- un correctif et **le test qui le prouve**.

Restent séparés, deux sujets qu'on peut vouloir reverter l'un sans l'autre, un refactor et une
fonctionnalité, un chantier à soi et celui d'un autre développeur.

**Ne pas empiler les commits au fil de l'eau quand le lot est encore ouvert.** Si un nouveau
fichier de la même intention arrive après coup, il complète le commit existant
(`git commit --amend` tant que rien n'est poussé), il n'en ouvre pas un second qui dirait la
même chose. Un `git reset --soft HEAD~<n>` suivi d'un commit unique reste possible sur des
commits **non poussés**, et ne détruit rien, ni l'index ni l'arbre de travail.

### 8. Pousser

**Toujours pousser une fois tous les commits faits**, en un seul `git push` à la fin et jamais
un push par commit. La demande de commit vaut validation du push, donc on ne redemande pas. Un
commit qui reste en local ne sert à personne, les autres travaillent sur une base qui ne le
contient pas, et la divergence grandit à chaque heure.

Si le push est rejeté parce que quelqu'un a poussé entre-temps, on procède ainsi.

1. `git fetch origin`, puis **lire** ce qui est arrivé avec `git log HEAD..origin/<branche>`.
2. Présenter la situation à l'utilisateur et demander sa validation avant de pull.
3. **Pull normal (merge), jamais de rebase**, donc `git pull --no-rebase`. Le merge conserve
   les deux histoires telles qu'elles sont, un rebase les réécrit et peut faire disparaître du
   travail. Jamais de force push, jamais de `reset --hard`.
   Pas besoin de committer avant de pull, puisqu'un merge s'applique sur un arbre sale tant
   que les changements ne touchent pas les mêmes lignes.
4. **Observer le résultat du pull** et lire ce qui a été mergé, sans enchaîner à l'aveugle.

En cas de conflit, ne jamais écraser le travail local. `--ours` et `--theirs` en bloc,
`checkout --force` et `reset --hard` sont interdits. On lit les deux versions, on comprend les
deux intentions, et on produit une résolution qui préserve les deux. Si elle n'est pas
évidente, on s'arrête, on montre le conflit et on demande.

Après le merge, on relance tous les checks, parce que le code d'autrui et le sien se
rencontrent pour la première fois.

### 9. Fin de fonctionnalité, merge sur `dev` et suppression de la branche

**Déclencheur exclusif, l'utilisateur signale explicitement la fin de la fonctionnalité.**
Sans ce signal, on s'arrête au push de la branche courante et on ne touche ni à `dev` ni à la
branche. La demande de fin vaut validation du commit, du push, du merge et de la suppression.

Ce flux ne s'applique que si la session est sur une branche d'implémentation. Si on est déjà
sur `dev`, il n'y a ni merge ni suppression.

1. Committer et pousser la branche courante en appliquant toute la procédure ci-dessus. On ne
   merge jamais une branche dont le travail n'est pas commité et poussé.
2. Mémoriser le nom de la branche avant de la quitter.
3. `git checkout dev` puis `git pull --no-rebase origin dev`, pour partir d'un `dev` à jour.
4. `git merge --no-ff <branche>`, le `--no-ff` conservant une trace explicite dans
   l'historique.
5. En cas de conflit, appliquer strictement l'étape 8.
6. Relancer tous les checks sur `dev` après le merge, parce qu'un merge peut casser ce que
   chaque branche passait isolément. Si l'échec vient de fichiers non touchés par la session,
   on s'arrête, on le signale, et on ne pousse rien.
7. `git push origin dev`.
8. Supprimer la branche, locale puis distante, avec `git branch -d` et jamais `-D`. Le `-d`
   refuse la suppression si la branche n'est pas mergée, ce qui protège d'une perte de
   travail. S'il refuse, ne jamais forcer, c'est le signe que le merge n'a pas abouti comme
   prévu.
9. Rendre compte, avec le hash du merge, le résultat du push et la confirmation des deux
   suppressions.

### 10. Relecture d'une autre branche depuis `dev`, à la demande

**Deux conditions cumulatives, sinon cette section ne s'applique pas.** La session est sur
`dev`, et la personne qui lance le skill, qu'elle soit Armand, Sarah ou une autre, demande
explicitement de regarder une autre branche et la nomme. Jamais d'initiative : on ne part pas
inspecter les branches des autres parce qu'elles existent.

**Place dans la procédure, après le push de `dev`, jamais avant.** On termine d'abord les
étapes 1 à 8 pour son propre travail, donc `dev` est commité, poussé et à jour, puis seulement
on ouvre la branche demandée. L'ordre n'est pas un détail : un merge doit atterrir sur un `dev`
à jour, et son propre travail non commité n'a jamais à se mélanger à celui d'autrui.

1. **Lire le diff sans changer de branche.** `git fetch origin`, puis
   `git log --oneline dev..origin/<branche>` pour les commits, `git diff --stat dev...origin/<branche>`
   pour l'ampleur, et `git diff dev...origin/<branche>` pour le contenu. Les trois points
   comparent à l'ancêtre commun, donc le diff ne montre que ce que la branche a apporté, sans
   le bruit de ce que `dev` a avancé de son côté. Aucun `checkout`, la branche appartient à
   quelqu'un d'autre.
2. **Rendre compte en une synthèse concise**, dans cet ordre, sans copier le diff.
   - **But** : le problème que la branche traite.
   - **Objectif** : ce qu'elle change pour l'utilisateur ou le développeur.
   - **Concrètement fait** : les modifications réelles, une ligne chacune.
   - **Fichiers et zones** : les chemins touchés, regroupés par zone (backend, vue, seed,
     configuration, documentation).
   - **Ce qui n'est pas fini** : marqueurs `REVISIT:`, `FORLATER:`, `UNSURE:`, renvois vers une
     documentation inexistante, tests absents.
   Si une intention reste obscure après lecture du diff, le dire, ne jamais la deviner.
3. **Demander la validation du merge, et attendre.** La demande de relecture ne vaut pas
   validation du merge, c'est une décision distincte qui se pose explicitement. Sans réponse,
   on ne merge rien.
4. **Si la personne valide**, `git merge --no-ff origin/<branche>` sur `dev`, résolution de
   conflit selon l'étape 8, relance de tous les checks, puis `git push origin dev`.
5. **Aligner ensuite la branche sur `dev`**, par `git push origin dev:<branche>` puis
   `git fetch origin <branche>:<branche>` si elle existe en local. Les deux repartent du même
   commit, et la personne qui travaille dessus reprend sur une base à jour.
6. **Ne jamais supprimer la branche d'autrui.** La suppression de l'étape 9 vaut pour la
   branche de la session, pas pour celle de quelqu'un d'autre, même mergée.
7. **Si la personne refuse le merge**, on ne touche à rien, ni merge, ni alignement, ni push.
   La synthèse a servi, la branche reste telle quelle.
