# Escalade vers le téléphone

L'escalade est désactivée par défaut. Une fois activée, une bannière qui reste sans réaction
pendant `ESCALATE_AFTER` secondes déclenche un push sur votre téléphone. Toute réaction
l'annule, qu'il s'agisse d'une réponse tapée dans la bannière, d'un clic dessus ou d'un simple
message envoyé dans la session. L'escalade ne part donc que si vous êtes réellement parti, et
elle n'ajoute aucun bruit quand vous êtes là.

Ça marche à distance, puisque ntfy passe par internet et pas par votre réseau local.

## Activer

1. Tirer un nom de sujet imprévisible avec `openssl rand -hex 16`.
2. Le mettre dans `NTFY_TOPIC`, de préférence dans `config/cc-notify.local.conf` qui n'est pas suivi
   par git plutôt que dans `config/cc-notify.conf` qui l'est.
3. Installer l'application ntfy sur le téléphone et s'abonner à ce sujet.

## Ce que ça expose

**ntfy.sh est un service public sans authentification.** Quiconque connaît le nom du sujet lit
vos notifications, et le nom du dépôt y transite en clair. D'où le nom tiré au hasard, qui est
la seule protection réelle du dispositif. Pour un usage sensible, il vaut mieux héberger sa
propre instance et pointer `NTFY_SERVER` dessus.

## L'icône sur le téléphone

L'en-tête `Icon` de ntfy n'existe **que sur Android**, et seulement en PNG ou en JPEG.
L'application ntfy iOS ne sait pas afficher d'icône personnalisée, donc le push portera
toujours l'icône de ntfy.

Aucun emoji n'est envoyé, `NTFY_TAGS` étant vide par défaut. Le push porte seulement l'état en
titre et le nom du dépôt en corps. Pour en ajouter un malgré tout, `NTFY_TAGS` accepte les
codes de <https://ntfy.sh/docs/emojis/>.
