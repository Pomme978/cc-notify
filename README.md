# cc-notify

Notifications macOS pour Claude Code, qui se taisent quand Claude va repartir tout seul.

## Ce que ça fait

Une bannière macOS quand une session Claude Code dans iTerm réclame vraiment votre
attention : le tour est fini, une permission est demandée, ou le tour a échoué.
Le titre porte le nom du dossier, ce qui identifie la session parmi les autres.
Le clic active la fenêtre iTerm concernée et sélectionne sa session.

Rien ne s'affiche si :

- vous regardez déjà cet onglet ;
- un sous-agent ou une tâche de fond tourne encore ;
- un réveil est programmé (`/loop`, `ScheduleWakeup`, `CronCreate`) ;
- le tour a duré moins de 30 secondes.

Une erreur de tour (`StopFailure`) contourne tous ces filtres sauf le premier :
si la session est morte, elle ne repartira pas toute seule.

## Installation

    brew install terminal-notifier
    ./install.sh

**Redémarrer Claude Code**, puis vérifier avec `/hooks` que les sept événements
apparaissent. Les hooks ne sont pris en compte que par les sessions démarrées
après l'installation — c'est la cause la plus fréquente de « ça ne filtre pas ».

À la première notification, macOS crée une entrée `terminal-notifier` dans
Réglages Système → Notifications. Y autoriser les bannières et le son.

## Réglages

Tout est dans `cc-notify.conf`. `ENABLED=0` coupe tout sans désinstaller.

| Clé | Défaut | Effet |
|---|---|---|
| `ENABLED` | `1` | interrupteur général |
| `MIN_DURATION` | `30` | en dessous, pas de notification de fin de tour |
| `BODY_LEN` | `120` | troncature du corps du message |
| `SOUND_DONE` | `Ping` | fin de tour |
| `SOUND_QUESTION` | `Glass` | question ou permission |
| `SOUND_ERROR` | `Basso` | erreur |
| `DEBUG` | `0` | `1` journalise chaque événement et chaque décision |

## Icône

`cc-notify-icon.png` est produit par `./make-icon.sh` à partir du glyphe officiel
Claude Code (`assets/claude-code.svg`), recentré dans un carré avec la marge
qu'attend une icône macOS. Régénérer après toute modification du SVG.

`assets/CaludeMascot_opt.gif` est conservé comme trace : c'est la mascotte animée
dont provenait une première version de l'icône. Voir `assets/SOURCE.md`.

## Dépannage

Activer `DEBUG=1` dans `cc-notify.conf`, puis lire `~/.claude/state/cc-notify/log`.
Deux types de lignes y apparaissent :

    EVENT SubagentStart sid=… agent_type=Explore agent_id=…
    SKIP sous-agent-actif type=done sid=…

Les lignes `EVENT` tracent tout ce que Claude Code envoie. Les lignes `NOTIFY` et
`SKIP` donnent la décision et son motif : `onglet-actif`, `sous-agent-actif`,
`tache-de-fond`, `reveil-programme`, `tour-court`, `doublon`, `desactive`.

**Une notification part alors qu'un sous-agent tourne.** Chercher un
`EVENT SubagentStart` juste avant dans le journal. S'il est absent, Claude Code
n'émet pas cet événement pour ce type de tâche — relever la valeur d'`EVENT` qui
apparaît à la place et l'ajouter au dispatch. S'il est présent mais que le
`sid=` diffère de celui du `Stop`, le compteur est écrit dans le mauvais fichier
d'état.

**Aucune ligne n'apparaît.** Les hooks ne sont pas branchés : vérifier `/hooks`,
et redémarrer Claude Code si la session est antérieure à l'installation.

**Des lignes `NOTIFY` mais aucune bannière.** L'autorisation macOS manque.

## Tests

    ./test-cc-notify.sh

36 cas, sans effet de bord : le mode `--dry-run` imprime la décision au lieu de
notifier, et l'état est écrit dans un dossier temporaire.

## Désinstallation

    ./install.sh --uninstall

Retire les liens symboliques et le bloc `hooks` de `settings.json`. Les fichiers
du projet et l'état restent en place.

## Documentation

- `docs/superpowers/specs/2026-08-12-cc-notify-design.md` — la conception et ses
  arbitrages (pourquoi `bg` n'est jamais décrémenté, pourquoi l'échec est ouvert)
- `docs/superpowers/plans/2026-08-12-cc-notify.md` — le plan d'implémentation
