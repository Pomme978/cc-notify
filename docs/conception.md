# cc-notify — Notifications macOS pour Claude Code

Date : 2026-08-12
Statut : design validé, prêt pour le plan d'implémentation

## Problème

Plusieurs sessions Claude Code tournent en parallèle dans iTerm. Rien ne signale
qu'une session a rendu la main, pose une question, ou a planté. Il faut surveiller
les onglets à la main.

Le piège d'un système naïf est le bruit. Une notification à chaque fin de tour est
inutile : Claude repart souvent tout seul, parce qu'un sous-agent tourne encore,
parce qu'une tâche de fond va le réveiller, ou parce qu'un `/loop` est programmé.
Un système qui notifie dans ces cas-là finit désactivé.

## Objectif

Notifier uniquement quand l'attention humaine est réellement requise :

- Claude a fini son tour et attend un nouveau message, **et rien ne va le relancer**
- Claude pose une question ou demande une permission — il est bloqué
- Le tour s'est terminé sur une erreur — la session est morte

Canal unique : le centre de notifications macOS. Pas de push mobile.

## Non-objectifs

- Pas de push iPhone / Apple Watch (Remote Control natif couvre déjà ce besoin
  si l'envie vient plus tard)
- Pas d'indicateur permanent en barre de menus
- Pas de notification à la fin d'un sous-agent : Claude enchaîne tout seul après,
  l'information n'est pas actionnable
- Pas de support d'un terminal autre qu'iTerm2

## Architecture

Un script, aucun service résident.

Le code **vit dans le Workdir**, pas dans `~/.claude/`, pour ne pas être perdu lors
d'une réinstallation de Claude Code ou d'un nettoyage du dossier de config. Seuls
des liens symboliques pointent depuis l'emplacement attendu par Claude Code.

```
Dépôt du projet
  src/cc-notify.sh          exécutable unique, dispatché par hook_event_name
  src/cc-notify-focus.scpt  AppleScript de focus, prend un UUID de session en argument
  config/cc-notify.conf     seuils, sons, interrupteur général
  tests/test-cc-notify.sh   harnais de test
  install.sh                liens symboliques + fusion dans settings.json
  README.md                 installation, dépannage, désinstallation
  docs/conception.md        cette spec

Liens symboliques créés par install.sh :
  ~/.claude/hooks/cc-notify.sh          ->  <projet>/src/cc-notify.sh
  ~/.claude/hooks/cc-notify.conf        ->  <projet>/config/cc-notify.conf
  ~/.claude/hooks/cc-notify-focus.scpt  ->  <projet>/src/cc-notify-focus.scpt

État volatil (jetable, jamais sauvegardé) :
  ~/.claude/state/cc-notify/<sid>.json
  ~/.claude/state/cc-notify/log
```

Le script reste un fichier unique plutôt que découpé en bibliothèques : un hook est
lancé plusieurs fois par tour, le coût de démarrage compte, et résoudre le chemin
d'un fichier voisin depuis un script atteint par lien symbolique est une source
d'erreurs. Le fichier est structuré en sections commentées : état, filtres, rendu.

L'AppleScript de focus est en revanche un fichier séparé, parce que l'imbriquer dans
la chaîne `-execute` de `terminal-notifier` demanderait trois niveaux
d'échappement de guillemets.

Les liens symboliques plutôt qu'un chemin direct dans `settings.json` : le chemin du
Workdir contient une espace et des parenthèses, sources classiques de bugs de
quoting dans les commandes de hook. Le lien maintient un chemin propre côté
configuration tout en gardant le code sous la main.

Le script est branché sur six événements dans `~/.claude/settings.json`. Il lit le
JSON du hook sur stdin, extrait `hook_event_name`, et route vers la sous-fonction
correspondante. Deux rôles distincts : les événements qui **accumulent du contexte**
et ceux qui **décident**.

Dépendances : `terminal-notifier` (Homebrew), `jq` (déjà présent en `/usr/bin/jq`),
`osascript` (système).

## Composant 1 — Accumulation d'état

### Format du fichier d'état

```json
{
  "turn_start": 1754990400,
  "subagents": 0,
  "bg": 0,
  "wakeup_until": 0,
  "iterm_session": "B3688F78-556B-419D-8398-0FDCB229E5C8",
  "notified_prompt": "",
  "cwd": "~/Workdir"
}
```

### Écritures

| Hook | Matcher | Effet |
|---|---|---|
| `UserPromptSubmit` | — | réinitialise tout le fichier ; `turn_start` = maintenant ; capture `$ITERM_SESSION_ID` et `cwd` |
| `SubagentStart` | — | `subagents += 1` |
| `SubagentStop` | — | `subagents -= 1`, plancher à 0 |
| `PostToolUse` | `ScheduleWakeup` | si `tool_input.stop` est vrai → `wakeup_until = 0` ; sinon `wakeup_until = maintenant + tool_input.delaySeconds` |
| `PostToolUse` | `CronCreate` | `wakeup_until = maintenant + 3600` (borne forfaitaire, on ne parse pas le cron) |
| `PostToolUse` | `Bash` | si `tool_input.run_in_background` est vrai → `bg += 1` |

La réinitialisation complète sur `UserPromptSubmit` est délibérée : un nouveau
message humain prouve qu'aucun sous-agent ni aucune tâche de fond n'est en cours.
C'est le mécanisme d'auto-réparation des compteurs après un crash ou un `Ctrl-C`.
Aucune autre resynchronisation n'est nécessaire.

`bg` n'est jamais décrémenté. Une tâche de fond marque le tour entier comme
« Claude va probablement repartir ». Ce choix évite de dépendre des hooks de
complétion de tâche, dont la couverture est incertaine. Coût accepté : une
notification manquée si l'utilisateur lance une tâche de fond très longue puis
attend au même tour. Ce cas est rare et le tour suivant repart proprement.

`iterm_session` est capturé dans le fichier d'état plutôt que relu à chaque appel,
car rien ne garantit que `$ITERM_SESSION_ID` reste exposé à tous les processus de
hook. Sa valeur a la forme `w1t1p0:UUID` ; seul l'UUID après le `:` est conservé,
c'est lui qui correspond à l'`id` AppleScript d'une session iTerm2.

## Composant 2 — Décision

### Déclencheurs

| Hook | Matcher | Type de notification | Filtres appliqués |
|---|---|---|---|
| `Stop` | — | `done` | les cinq |
| `Notification` | `permission_prompt`, `agent_needs_input` | `question` | tous sauf la durée minimale |
| `StopFailure` | — | `error` | uniquement l'onglet au premier plan |

`Stop` est choisi plutôt que `Notification`/`idle_prompt` pour la fin de tour parce
qu'il est garanti à chaque fin de tour et qu'il porte `last_assistant_message` et
`stop_reason`, nécessaires au corps de la notification.

### Les cinq filtres

Évalués dans cet ordre, le premier qui matche impose le silence :

1. **Onglet actif** — l'application au premier plan est iTerm2 **et** l'`id` de la
   session courante égale `iterm_session`. L'utilisateur voit déjà l'écran.
2. **Travail en cours** — `subagents > 0` ou `bg > 0`. Claude va reprendre seul.
3. **Réveil programmé** — `maintenant < wakeup_until`. La session va redémarrer seule.
4. **Tour trop court** — `maintenant - turn_start < MIN_DURATION` (30 s par défaut).
   L'utilisateur était devant l'écran. Non appliqué aux types `question` et `error`.
5. **Doublon** — `prompt_id` du hook égal à `notified_prompt`. Empêche deux
   notifications pour le même tour si `Stop` et `StopFailure` se succèdent.

En cas de succès, `notified_prompt` est mis à jour avec le `prompt_id` courant.

Ce filtre ne s'applique qu'à `Stop` et `StopFailure` : l'événement `Notification`
ne reçoit pas de `prompt_id`, il ne lit ni n'écrit `notified_prompt`. C'est le
comportement voulu. Une demande de permission au milieu d'un tour, puis la fin de
ce tour, sont deux moments distincts où l'attention est requise — l'utilisateur a
répondu à la permission puis s'est éloigné de nouveau. Les deux notifications sont
légitimes.

### Politique en cas d'échec

Le système échoue **ouvert** : fichier d'état absent, JSON illisible, `jq` en erreur,
AppleScript en timeout — la notification part quand même. Une notification en trop
coûte moins qu'une notification manquée. Le filtre « onglet actif » en particulier
laisse passer si AppleScript ne répond pas dans les 5 secondes.

Le script sort **toujours** en code 0. Un hook `Stop` qui sort en code 2 bloque
Claude et l'oblige à continuer ; c'est un mode de défaillance inacceptable pour un
outil de notification.

## Composant 3 — Rendu de la notification

Appel `terminal-notifier` :

| Champ | Valeur |
|---|---|
| `-title` | `basename` du `cwd` — identifie la session parmi les autres |
| `-subtitle` | `Terminé` / `Attend ta réponse` / `Erreur` |
| `-message` | `last_assistant_message` tronqué à 120 caractères, sauts de ligne remplacés par des espaces |
| `-sound` | `Ping` / `Glass` / `Basso` selon le type |
| `-group` | le `session_id` — une notification remplace la précédente de la même session |
| `-execute` | commande de focus (ci-dessous) |

Commande de focus, exécutée au clic :

```applescript
tell application "iTerm2"
  activate
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if (id of s) is "<UUID>" then
          select w
          select t
          select s
          return
        end if
      end repeat
    end repeat
  end repeat
end tell
```

Si la session n'existe plus, iTerm est simplement activé sans sélection. Pas d'erreur.

## Configuration

`~/.claude/hooks/cc-notify.conf`, format `clé=valeur` sourcé par le script :

```sh
ENABLED=1          # interrupteur général
MIN_DURATION=30    # secondes ; en dessous, pas de notification de fin de tour
BODY_LEN=120       # troncature du corps
SOUND_DONE=Ping
SOUND_QUESTION=Glass
SOUND_ERROR=Basso
DEBUG=0            # 1 pour journaliser chaque décision
```

Absence du fichier : les valeurs par défaut ci-dessus s'appliquent.

## Tests

Le script accepte un drapeau `--dry-run` qui imprime sur stdout la décision et le
motif (`NOTIFY done` / `SKIP filtre=onglet-actif`) au lieu d'appeler
`terminal-notifier`. Cela rend chaque filtre vérifiable en injectant du JSON de hook
factice et un fichier d'état préfabriqué.

Cas de test minimaux :

1. `Stop` après un tour de 5 s → SKIP (durée)
2. `Stop` après 60 s, état propre → NOTIFY
3. `Stop` après 60 s avec `subagents=1` → SKIP
4. `Stop` après 60 s avec `bg=1` → SKIP
5. `Stop` après 60 s avec `wakeup_until` dans le futur → SKIP
6. `Stop` après 60 s avec `wakeup_until` échu → NOTIFY
7. `Notification`/`permission_prompt` après 5 s → NOTIFY (la durée ne s'applique pas)
8. `StopFailure` après 5 s avec `subagents=1` → NOTIFY (seul l'onglet filtre)
9. Deux décisions successives, même `prompt_id` → la seconde SKIP
10. Fichier d'état absent → NOTIFY
11. `UserPromptSubmit` remet `subagents` et `bg` à 0

Le filtre « onglet actif » est testé en injectant l'`iterm_session` de la session
réellement au premier plan, puis une valeur bidon.

## Installation

1. `brew install terminal-notifier`
2. Écrire les fichiers dans le dépôt, `chmod +x` sur le script
3. Créer les liens symboliques vers `~/.claude/hooks/`
4. Fusionner le bloc `hooks` dans `~/.claude/settings.json`, en préservant
   les clés existantes (`env`, `permissions`, `model`, `statusLine`,
   `enabledPlugins`)
5. Déclencher une notification une fois pour que macOS crée l'entrée
   `terminal-notifier` dans Réglages → Notifications, puis y autoriser les
   bannières et le son
6. Vérifier avec `/hooks` que les six événements apparaissent

## Risques connus

| Risque | Traitement |
|---|---|
| `PostToolUse` n'expose pas `tool_input` sous la forme attendue | à vérifier en premier pendant l'implémentation, avant d'écrire la logique ; repli : journaliser le payload brut et adapter |
| `SubagentStart` indisponible dans la version installée (2.1.228) | vérifier via `/hooks` ; repli : ne compter que les `SubagentStop` en sens inverse depuis un compteur `PostToolUse` sur `Agent` |
| macOS bloque silencieusement les notifications tant que l'autorisation n'est pas accordée | étape d'installation explicite ; `--dry-run` permet de distinguer « le script décide de se taire » de « macOS avale la notification » |
| Fichiers d'état qui s'accumulent | purge des fichiers de plus de 7 jours au passage sur `UserPromptSubmit` |
| Le Workdir est déplacé ou renommé, les liens symboliques cassent | un lien mort fait échouer le hook silencieusement, sans bloquer Claude ; le README documente la recréation des liens |
