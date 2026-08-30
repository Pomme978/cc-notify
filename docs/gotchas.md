# Pièges déjà rencontrés

La première chose à faire quand quelque chose cloche est de passer `DEBUG=1` dans
`cc-notify.conf`, puis de lire `~/.claude/state/cc-notify/log`. Deux types de lignes y
apparaissent.

```
EVENT SubagentStart sid=… agent_type=Explore agent_id=…
SKIP sous-agent-actif type=done sid=…
```

Les lignes `EVENT` tracent tout ce que Claude Code envoie. Les lignes `NOTIFY` et `SKIP`
donnent la décision et son motif, qui peut être `onglet-actif`, `sous-agent-actif`,
`tache-de-fond`, `reveil-programme`, `tour-court`, `doublon` ou `desactive`.

## Aucune ligne n'apparaît dans le journal

Les hooks ne sont pas branchés. Vérifier avec `/hooks`, et redémarrer Claude Code si la session
a été ouverte avant l'installation. C'est de loin le cas le plus fréquent, parce que les hooks
ne sont lus qu'au démarrage d'une session.

## Des lignes `NOTIFY`, mais aucune bannière

L'autorisation macOS manque. La marche à suivre est dans le README, à la section qui parle
d'autoriser les notifications.

## Une notification part alors qu'un sous-agent tourne

Le suivi des sous-agents ne repose sur aucun événement particulier. Tout événement portant un
`agent_id` enregistre cet agent comme vivant, y compris un simple appel d'outil. Il faut donc
chercher dans le journal une ligne `EVENT … agent_id=…` pendant que l'agent travaille. Si
aucune n'apparaît, Claude Code n'expose pas d'`agent_id` pour ce type de tâche. Et si le `sid=`
de ces lignes diffère de celui du `Stop`, l'état est écrit dans le mauvais fichier.

## La réponse tapée dans la bannière n'arrive pas

Vérifier que `~/.claude/hooks/cc-notify-alerter` existe et que la session iTerm visée est
toujours ouverte. `cc-notify-send.sh` tourne détaché, donc ses erreurs ne remontent nulle part,
et le relancer à la main est le seul moyen de les voir.

## Trop de notifications

Monter `MIN_DURATION`. Pour couper temporairement sans désinstaller, `ENABLED=0` suffit.

## Les liens symboliques cassent après un déplacement du dépôt

Les liens de `~/.claude/hooks/` pointent vers le dépôt par chemin absolu. Déplacer ou renommer
le dossier les casse, et un lien mort fait échouer le hook silencieusement sans bloquer Claude
Code. Rejouer `./install.sh` depuis le nouvel emplacement les recrée.
