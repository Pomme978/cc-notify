# cc-notify

Notifications macOS pour Claude Code, qui se taisent quand Claude va repartir tout seul.

## Ce que ça fait

Une bannière macOS quand une session Claude Code dans iTerm réclame vraiment votre
attention : le tour est fini, une permission est demandée, ou le tour a échoué.
Le clic active la fenêtre iTerm concernée et sélectionne sa session.

La bannière porte l'icône Claude Code et se lit en trois lignes :

| Ligne | Contenu |
|---|---|
| Titre | le nom du dépôt git |
| Sous-titre | `Terminé`, `Attend ta réponse` ou `Erreur` |
| Corps | le dernier message de Claude, tronqué |

Le titre identifie le projet, ce qui dit laquelle de vos sessions vous appelle.
Le dépôt git est préféré au sujet de la conversation parce qu'il reste stable
quand la discussion dérive. Hors dépôt, le titre retombe sur le nom de l'onglet
iTerm — que Claude Code tient à jour avec le sujet — puis sur le nom du dossier.

Pour voir ce que donnerait un dossier donné :

    ./cc-notify.sh --titre /chemin/du/projet

Sur une fin de tour, la bannière porte un **champ de réponse** : ce que vous y
tapez est envoyé directement dans la session iTerm, sans quitter ce que vous
faisiez. Les demandes de permission n'en ont pas — elles attendent une touche
dans un sélecteur, pas du texte libre.

Rien ne s'affiche si :

- vous regardez déjà cet onglet ;
- un sous-agent ou une tâche de fond tourne encore ;
- un réveil est programmé (`/loop`, `ScheduleWakeup`, `CronCreate`) ;
- le tour a été court **et** vous venez de toucher la machine.

Ce dernier filtre demande les deux conditions à la fois. Prises séparément,
chacune se trompe : un tour court pendant votre absence mérite une notification,
et un tour long la mérite aussi même si vous tapez — vous tapiez ailleurs.
L'inactivité vient de `HIDIdleTime`, le compteur système de dernière frappe ou
dernier mouvement de souris.

Une erreur de tour contourne tous ces filtres sauf le premier : si la session est
morte, elle ne repartira pas toute seule.

## Installation

### Prérequis

macOS, iTerm2, et Homebrew. `jq` et `osascript` sont déjà là.

    brew install terminal-notifier librsvg

`terminal-notifier` sert de repli. `librsvg` fournit `rsvg-convert`, qui fabrique
l'icône à partir du SVG.

Le notifieur principal est **alerter**, seul à savoir afficher un champ de
réponse. Il n'est pas dans Homebrew : `get-alerter.sh` le récupère de sa release
GitHub et refuse de l'installer si l'empreinte SHA-256 épinglée ou la signature
Developer ID ne correspondent pas. `install.sh` l'appelle tout seul. Sans lui
tout fonctionne, mais les bannières perdent leur champ de réponse.

### Poser le système

    cd cc-notify
    ./install.sh

Le script est rejouable sans dommage. Il :

1. fabrique l'icône et le bundle `vendor/cc-notify.app` s'ils manquent ;
2. crée quatre liens symboliques dans `~/.claude/hooks/` — le code reste ici,
   seuls les liens vivent dans `~/.claude/` ;
3. fusionne sept entrées `hooks` dans `~/.claude/settings.json`, en préservant
   tout le reste de votre configuration.

### Redémarrer Claude Code

**Indispensable.** Les hooks ne sont lus qu'au démarrage d'une session. Une
session déjà ouverte continuera de les ignorer — c'est la cause numéro un de
« ça ne filtre rien ».

Vérifier ensuite avec `/hooks` que les sept événements apparaissent :
`UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `PostToolUse`, `Stop`,
`StopFailure`, `Notification`.

### Autoriser les notifications

macOS ne crée l'entrée qu'après la première tentative d'envoi. Déclencher une
notification de test :

    ./vendor/cc-notify.app/Contents/MacOS/terminal-notifier \
      -title "Test" -message "Bonjour" -sound Ping

Puis Réglages Système → Notifications → **Claude Code** → autoriser les
bannières et le son. Relancer la commande pour confirmer.

L'entrée s'appelle « Claude Code » et non « terminal-notifier » : les
notifications sont émises depuis notre propre bundle, seule façon d'afficher une
icône personnalisée (voir la section Icône).

### Vérifier de bout en bout

1. `DEBUG=1` dans `cc-notify.conf`
2. Lancer une requête longue, passer sur une autre application, attendre la fin →
   bannière. Le clic ramène sur le bon onglet.
3. Relancer une requête longue en restant sur l'onglet → pas de bannière, et
   `grep 'SKIP onglet-actif' ~/.claude/state/cc-notify/log` remonte une ligne.
4. Remettre `DEBUG=0`.

## Réglages

Tout est dans `cc-notify.conf`, relu à chaque notification — pas besoin de
redémarrer quoi que ce soit après l'avoir modifié.

| Clé | Défaut | Effet |
|---|---|---|
| `ENABLED` | `1` | `0` coupe tout sans désinstaller |
| `MIN_DURATION` | `30` | seuil de durée du tour, en secondes |
| `MIN_IDLE` | `30` | seuil d'inactivité de la machine, en secondes |
| `AGENT_TTL` | `600` | au-delà, un sous-agent muet est réputé mort |
| `BODY_LEN` | `120` | troncature du corps du message |
| `SOUND_DONE` | `Ping` | fin de tour |
| `SOUND_QUESTION` | `Glass` | question ou permission |
| `SOUND_ERROR` | `Basso` | erreur |
| `NTFY_TOPIC` | vide | sujet ntfy pour l'escalade ; vide = désactivé |
| `NTFY_SERVER` | `https://ntfy.sh` | serveur ntfy |
| `ESCALATE_AFTER` | `300` | délai avant escalade, en secondes |
| `DEBUG` | `0` | `1` journalise chaque événement et chaque décision |

Les sons disponibles sont les fichiers de `/System/Library/Sounds`.

## Escalade vers le téléphone

Désactivée par défaut. Une fois activée, si une bannière reste sans réaction
pendant `ESCALATE_AFTER` secondes, un push part sur votre téléphone. Toute
réaction l'annule : réponse dans la bannière, clic dessus, ou simple message
tapé dans la session. L'escalade ne se déclenche donc que si vous êtes
réellement parti — elle n'ajoute aucun bruit quand vous êtes là.

Ça marche à distance : ntfy passe par internet, pas par votre réseau local.

Pour l'activer :

1. Tirer un nom de sujet imprévisible : `openssl rand -hex 16`
2. Le mettre dans `NTFY_TOPIC` dans `cc-notify.conf`
3. Installer l'application ntfy sur le téléphone et s'abonner à ce sujet

**ntfy.sh est un service public sans authentification.** Quiconque connaît le nom
du sujet lit vos notifications, et le nom du dépôt y transite en clair. D'où le
nom aléatoire. Pour un usage sensible, héberger sa propre instance et pointer
`NTFY_SERVER` dessus.

### L'icône sur le téléphone

L'en-tête `Icon` de ntfy n'existe **que sur Android**, et seulement en PNG ou
JPEG. L'application ntfy iOS ne sait pas afficher d'icône personnalisée : le push
portera toujours l'icône de ntfy.

Aucun emoji n'est envoyé : `NTFY_TAGS` est vide par défaut. Le push porte
seulement l'état en titre et le nom du dépôt en corps. Si vous en vouliez un
malgré tout, `NTFY_TAGS` accepte les codes de <https://ntfy.sh/docs/emojis/>.

## Icône

`./make-icon.sh` produit `cc-notify-icon.png` et `cc-notify.icns` à partir du
glyphe officiel Claude Code (`assets/claude-code.svg`). Deux retouches : les yeux
du glyphe sont des trous dans le tracé, on glisse deux rectangles noirs derrière
pour qu'ils se voient sur tout fond ; et le glyphe, large et bas, est recentré
dans un carré avec la marge qu'attend une icône macOS.

`./make-app.sh` construit `vendor/cc-notify.app`, une copie de
`terminal-notifier.app` portant cette icône et le nom « Claude Code ». C'est
indispensable : macOS ignore l'option `-appIcon`, qui reposait sur une API privée
retirée depuis. L'icône affichée à gauche d'une bannière vient toujours du bundle
de l'application émettrice — il faut donc émettre depuis le nôtre.

Après avoir modifié le SVG : `./make-icon.sh && ./make-app.sh`.

`assets/CaludeMascot_opt.gif` est conservé comme trace : c'est la mascotte animée
dont provenait une première version de l'icône. Voir `assets/SOURCE.md`.

## Dépannage

Activer `DEBUG=1`, puis lire `~/.claude/state/cc-notify/log`. Deux types de
lignes y apparaissent :

    EVENT SubagentStart sid=… agent_type=Explore agent_id=…
    SKIP sous-agent-actif type=done sid=…

Les lignes `EVENT` tracent tout ce que Claude Code envoie. Les lignes `NOTIFY` et
`SKIP` donnent la décision et son motif : `onglet-actif`, `sous-agent-actif`,
`tache-de-fond`, `reveil-programme`, `tour-court`, `doublon`, `desactive`.

**Aucune ligne n'apparaît.** Les hooks ne sont pas branchés. Vérifier `/hooks`,
et redémarrer Claude Code si la session est antérieure à l'installation.

**Des lignes `NOTIFY` mais aucune bannière.** L'autorisation macOS manque, voir
plus haut.

**Une notification part alors qu'un sous-agent tourne.** Le suivi ne repose sur
aucun événement particulier : tout événement portant un `agent_id` enregistre
cet agent comme vivant, y compris un simple appel d'outil. Chercher dans le
journal une ligne `EVENT … agent_id=…` pendant que l'agent travaille. Si aucune
n'apparaît, Claude Code n'expose pas d'`agent_id` pour ce type de tâche. Si le
`sid=` de ces lignes diffère de celui du `Stop`, l'état est écrit dans le mauvais
fichier.

**La réponse tapée dans la bannière n'arrive pas.** Vérifier que
`~/.claude/hooks/cc-notify-alerter` existe et que la session iTerm visée est
toujours ouverte. `cc-notify-send.sh` tourne détaché : ses erreurs ne remontent
nulle part, le relancer à la main pour les voir.

**Trop de notifications.** Monter `MIN_DURATION`. Pour couper temporairement,
`ENABLED=0`.

## Tests

    ./test-cc-notify.sh

36 cas, sans effet de bord : le mode `--dry-run` imprime la décision au lieu de
notifier, et l'état est écrit dans un dossier temporaire.

## Désinstallation

    ./install.sh --uninstall

Retire les liens symboliques et le bloc `hooks` de `settings.json`. Les fichiers
du projet et l'état restent en place. L'entrée « Claude Code » subsiste dans les
Réglages Système ; elle disparaîtra d'elle-même.

## Documentation

- `docs/superpowers/specs/2026-08-12-cc-notify-design.md` — la conception et ses
  arbitrages : pourquoi le compteur de tâches de fond n'est jamais décrémenté,
  pourquoi le système échoue ouvert, pourquoi `Stop` plutôt que `idle_prompt`
- `docs/superpowers/plans/2026-08-12-cc-notify.md` — le plan d'implémentation
