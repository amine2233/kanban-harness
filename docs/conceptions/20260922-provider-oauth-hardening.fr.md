# Durcissement OAuth des fournisseurs

_Traduction française de [`provider-oauth-hardening.md`](20260922-provider-oauth-hardening.md), qui reste
la version de référence._

OAuth dans ce projet signifie **Hugging Face** : un flux authorization-code avec PKCE, un jeton
d'accès qui expire et un jeton de rafraîchissement. Les fournisseurs qui s'authentifient par clé
d'API sortent du cadre — ils n'ont ni callback, ni expiration, ni rafraîchissement, donc aucune des
décisions ci-dessous ne les concerne.

Le flux est livré et fonctionne. Trois des hypothèses sur lesquelles il a été conçu n'ont pas
survécu au contact du code : le callback n'est plus garanti d'être en loopback, le mécanisme de
rafraîchissement par requête sur lequel il s'appuyait n'a jamais été construit, et rien ne consigne
que la déconnexion est purement locale. Cette note tranche ces corrections (T-37, T-39, T-40) ainsi
que la course de stockage qu'exposent les connexions parallèles (T-42), et consigne pourquoi T-41
reste différée.

[`provider-sign-in.md`](20260921-provider-sign-in.md) décide le flux lui-même — PKCE, `state`, TTL de
session, le magasin d'identifiants — et en reste la référence.

## Pourquoi maintenant

`provider-sign-in.md` affirme que le callback est `http://127.0.0.1:5175/api/auth/callback` et que
« le serveur écoute en loopback, ce qui est ce qu'attendent les fournisseurs pour une application
locale ». L'implémentation construit en réalité l'URI de redirection à partir de l'en-tête `Host`
de la requête (`AIConfigController.beginSignIn`), et la prémisse du loopback ne tient plus :
`dashboard serve --hostname 0.0.0.0` est pris en charge et deux tâches `mise` s'appuient dessus
(`serve:lan`, `dev:lan`), tandis que `Configure.swift` n'installe que les middlewares CORS et
d'erreur — l'API n'a aucune authentification.

C'est un problème de **robustesse, pas une vulnérabilité**. Hugging Face valide `redirect_uri`
contre l'application OAuth enregistrée, donc un `Host` falsifié produit une URL que le fournisseur
rejette. Cela vaut tout de même la peine d'être corrigé : le schéma `http://` est codé en dur, ce
qui est faux derrière TLS, et le confinement repose entièrement sur une vérification côté
fournisseur plutôt que sur quoi que ce soit que fasse ce code. Un futur fournisseur qui accepterait
un callback libre rendrait le même code exploitable sans aucun changement de notre côté.

Vérifié par la lecture de `AIConfigController.swift`, `Configure.swift` et `ServeCommand.swift` ;
non reproduit contre un fournisseur réel.

## Décisions

### T-37 — l'URL de callback est de la configuration, pas un en-tête de requête

**Décision.** Ajouter `publicURL: URL?` à `ServerConfig`, à côté de `corsOrigins` — le même genre de
réglage de niveau transport, détenu par le même type, défini par un drapeau
`dashboard serve --public-url` et `MVP_DASHBOARD_PUBLIC_URL`. `beginSignIn` construit le callback à
partir de là. Quand il n'est pas défini, l'en-tête `Host` n'est accepté que si son hôte est en
loopback (`127.0.0.1`, `localhost`, `::1`) ; tout le reste est un `400`. Cela supprime aussi le
schéma `http://` codé en dur.

**Rejeté.** Sonder si quelque chose écoute sur le port web et l'utiliser comme callback : « une
socket est ouverte sur 5173 » ne signifie pas « mon serveur de dev Vite avec son proxy `/api` est
là », la réponse peut changer entre `begin` et le callback, et en production un tel port n'existe
tout simplement pas. Cela dériverait une URL critique pour la sécurité d'un signal ambiant et
falsifiable — la même classe d'erreur que faire confiance à `Host`, ce que cette décision existe
précisément pour supprimer. La valeur est connue d'avance dans tous les modes : c'est donc de la
configuration, pas un problème de découverte.

Également rejeté : valider `Host` contre une liste blanche — sous `--hostname 0.0.0.0` l'hôte
légitime est l'adresse LAN de la machine, qui n'est pas connue au moment où la configuration est
écrite, donc la liste blanche ne peut pas être remplie. Également rejeté : exiger `--public-url`
sans condition, ce qui casserait le flux loopback par défaut qui fonctionne aujourd'hui sans rien
apporter.

**Comment il est défini dans chaque mode.** Le callback doit être l'origine à laquelle le
navigateur a réellement l'application. Chaque mode connaît déjà cette valeur sans avoir à la
découvrir :

| Mode                           | Origine du callback         | Comment elle est connue                                                               |
| ------------------------------ | --------------------------- | ------------------------------------------------------------------------------------- |
| `mise run dev` (Vite)          | `http://127.0.0.1:5173`     | `scripts/dev.sh` détient `WEB_PORT` au lancement du backend ; il passe `--public-url` |
| `dashboard serve --static-dir` | l'origine du serveur        | chemin par défaut — le serveur sert l'application, donc le `Host` loopback est le bon |
| CLI, serveur démarré           | l'origine du serveur        | la route décide, comme aujourd'hui                                                    |
| CLI, sans serveur              | `http://127.0.0.1:<random>` | le serveur temporaire fournit son propre callback, inchangé                           |

Vite relaie `/api` vers `127.0.0.1:5175` (`web/vite.config`), donc un callback sur `5173` atteint le
serveur via le proxy et la redirection relative retombe sur `5173`, là où se trouve l'application.
C'est aussi ce qui corrige la bannière de confirmation manquante en dev.

**Où c'est résolu, et pourquoi cela compte.** Il y a deux producteurs de callback, et seul le
premier porte le bug :

| Producteur                                                                | Comment il obtient un callback                                                                   | Concerné |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | -------- |
| `AIConfigController.beginSignIn` (web, et le CLI quand un serveur tourne) | depuis l'en-tête `Host` de la requête                                                            | oui      |
| `AILoginCommand.viaTemporaryServer` (CLI, sans serveur)                   | construit `http://127.0.0.1:<random>/api/auth/callback` et appelle `SignInCommands.begin` direct | non      |

Le CLI n'a pas de serveur à lui. Avec un serveur démarré il passe par la route, et
`RemoteSignInCommands.begin` envoie `body: Empty?.none` — l'argument `callback` qu'il accepte est
**ignoré**, donc la dérivation du serveur est la seule qui compte. Sans serveur, il démarre Vapor
sur le port `0` et fournit son propre callback loopback, contournant entièrement le contrôleur.

La résolution doit donc se faire **à la frontière HTTP, dans le contrôleur**.
`ProviderSignInService.begin` continue de prendre un `callback` explicite et ne doit jamais le
remplacer — mettre la logique `publicURL` dans le service remplacerait le callback à port aléatoire
du serveur temporaire par une URL configurée sur laquelle rien n'écoute, cassant la connexion
précisément pour l'utilisateur qui n'a pas de serveur. C'est le piège que cette décision existe pour
éviter.

**Ce que cela implique pour la connexion web.** Le flux navigateur existe déjà et est testé
(`AIProvidersCard.tsx`, `AIProvidersCard.test.tsx`) : la carte des réglages ouvre l'URL
d'autorisation avec `window.open(url, '_blank')`, et après l'échange `completeSignIn` répond
`req.redirect(to: "/settings?signed_in=<id>")`. Cette redirection est **relative**, donc elle se
résout contre l'origine qui a servi le callback, et `signInLanding()` n'affiche la confirmation que
parce qu'il lit `signed_in` depuis `window.location.search` dans l'onglet qui a atterri là.

`publicURL` décide donc où l'utilisateur se retrouve après la connexion, et pas seulement où le
fournisseur rappelle. Cela précise la définition plutôt que de la compliquer : `publicURL` est
**l'origine à laquelle un navigateur atteint ce tableau de bord**, c'est-à-dire exactement l'origine
contre laquelle la redirection post-connexion doit se résoudre. Un `publicURL` pointant vers un
endroit où le navigateur ne peut pas charger l'application laisserait l'utilisateur sur une page
blanche avec un identifiant correctement stocké — la panne est cosmétique mais déroutante, donc elle
relève de la documentation du drapeau.

**Touche.** `DashboardServer` (`ServerConfig`, `AIConfigController`), `DashboardCLI`
(`ServeCommand`), `scripts/dev.sh` (un drapeau sur la ligne `serve`). Ni `DashboardOAuth` ni
`DashboardAI` : le flux est inchangé, seule l'URL qu'on lui passe change, et `SignInCommands.begin`
garde sa signature.

**Vérifié par.** Tests de route : un `Host` non-loopback sans `publicURL` renvoie `400` ; un `Host`
loopback produit toujours un callback ; `publicURL` l'emporte quand les deux sont présents ; et
`completeSignIn` redirige sous `publicURL` quand il y en a un. Plus le cas que le tableau rend
porteur : avec `publicURL` défini, le serveur temporaire d'`AILoginCommand` se connecte toujours
contre son propre callback loopback à port aléatoire. `mise run backend:test`.

### T-42 — des connexions parallèles ne doivent pas perdre un identifiant

Le côté écouteur loopback est déjà correct et ne demande aucun changement : `viaTemporaryServer`
écoute sur `127.0.0.1` port `0`, donc l'OS choisit un port libre et deux exécutions concurrentes ne
peuvent pas entrer en collision, et il appelle `asyncShutdown()` sur le chemin de succès comme sur
celui d'erreur. À l'intérieur d'un processus, `SignInSessions` est un acteur indexé par `state`,
donc autant de flux qu'on veut peuvent être en vol simultanément.

Le stockage en dessous, lui, ne l'est pas. `FileCredentialStore.set` lit `credentials.json`, mute le
dictionnaire et le réécrit, sans le moindre verrou dans `Sources/`. Deux connexions qui se terminent
dans des processus différents — deux connexions CLI, ou une connexion CLI à côté du serveur qui
tourne — s'entrelacent en lecture/lecture/écriture/écriture et un identifiant est silencieusement
perdu. `AtomicFile.write` aggrave le tout en utilisant un chemin temporaire fixe (`path + ".tmp"`)
que les deux écrivains partagent, et `Data.write(to:)` sans `.atomic` peut s'entrelacer à
l'intérieur.

**Décision.** Deux changements, tous deux dans la couche de stockage, aucun ne touchant au flux :

1. `AtomicFile.write` écrit vers un chemin temporaire unique (pid plus un suffixe aléatoire) avant
   le `rename`, pour que des écrivains concurrents ne partagent jamais un fichier d'attente.
2. `FileCredentialStore` prend un `flock` consultatif sur le fichier d'identifiants pour toute la
   séquence lecture-modification-écriture, afin que le dernier écrivain fusionne au lieu d'écraser.

**Rejeté.** Faire de `FileCredentialStore` un acteur : cela sérialise un seul processus, et le cas
qui perd réellement des données concerne deux processus. Également rejeté : un fichier par
fournisseur, qui supprime la fusion mais change le format sur disque que `provider-sign-in.md` a
fixé et que les utilisateurs ont déjà.

**Touche.** `DashboardPersistence` (`AtomicFile`), `DashboardPersistenceConfig`
(`FileCredentialStore`). Aucun changement dans `DashboardOAuth`, `DashboardAI` ou le CLI.

**Vérifié par.** Un test où deux écrivains concurrents stockant des identifiants de fournisseurs
différents survivent tous les deux, et où le fichier temporaire a disparu ensuite.
`mise run backend:test` plus `mise run backend:test:linux` — le comportement de `flock` est
typiquement le genre de chose qui diffère entre Darwin et Linux.

### T-39 — l'expiration appartient à la valeur du domaine, le renouvellement à la couche AI

Hugging Face est le seul type dont l'identifiant expire, donc cette décision n'a qu'un fournisseur à
satisfaire. Deux placements, tous deux plausibles ; c'est le coût qui tranche.

**(a) Rafraîchir dans le chemin de lecture de l'identifiant** (`ConfigFileAIConfigStore.load`).
Chaque consommateur devient correct sans aucune discipline requise. Mais
`DashboardPersistenceConfig` ne doit pas détenir de secrets ([`ARCHITECTURE.md`](../ARCHITECTURE.md)),
et renouveler exige le registre des fournisseurs et un appel HTTP sortant : un type de persistance
acquerrait donc une dépendance vers la couche AI et des E/S réseau. **Rejeté sur la règle de
couches**, pas par goût.

**(b) Exposer `expiresAt` sur `AIProviderConfig`** (domaine, pur, sans E/S) et garder le
renouvellement dans `ProviderSignInService.refreshed`. Un consommateur qui détient une configuration
peut voir que le secret est périmé, donc sauter le rafraîchissement devient visible sur le site
d'appel au lieu de produire silencieusement un 401. **Choisi.**

`provider-sign-in.md` avait conçu une troisième option — un rafraîchissement par requête via une clé
`@autoclosure` sur `OpenAILanguageModel`. Cette autoclosure n'existe pas dans ce code (aucune
occurrence d'`autoclosure` sous `Sources/`), ce qui explique pourquoi `refreshed()` est appelée à la
main depuis `AssistantService`, aujourd'hui le seul chemin de rédaction. Cette note remplace ce
mécanisme.

**Touche.** `DashboardDomain` (`AIProviderConfig`), `DashboardPersistenceConfig` (remplir
`expiresAt` depuis l'identifiant pendant la résolution de la clé), `DashboardAI`
(`ProviderSignInService`).

**Vérifié par.** Une configuration résolue depuis un identifiant expirant porte `expiresAt` ; une
configuration résolue depuis une variable d'environnement ou une clé collée n'en porte aucune ;
`AIConfigDTO` n'émet toujours ni le secret ni l'expiration. `mise run backend:test`.

### T-40 — `signOut` est local par conception, et devrait le dire

**Décision.** Un commentaire sur `ProviderSignInService.signOut` consignant qu'il supprime
l'identifiant stocké et ne révoque rien chez le fournisseur, avec la conséquence (le jeton d'accès
Hugging Face reste valide jusqu'à son expiration) et la raison (une révocation distante en échec ne
doit pas bloquer une déconnexion locale).

**Rejeté.** Appeler le point de terminaison de révocation de Hugging Face : cela ajoute un mode de
panne réseau à une suppression locale, pour un seul fournisseur, sans aucun moyen de réussir hors
ligne.

**Touche.** `DashboardAI` uniquement. Commentaire, aucun changement de comportement.

**Vérifié par.** Rien. C'est délibérément un patch de commentaire seul, sans contrôle ; son contenu
est une affirmation sur ce que le code ne fait _pas_, qu'aucun test ne peut asserter.

## Ordre des travaux

1. **T-42** — une correction de justesse dans le stockage, indépendante de tout le reste, et la
   seule qui puisse perdre des données utilisateur. Elle rend aussi T-39 testable sans course dans
   la fixture.
2. **T-37** — change un contrat visible de l'extérieur (l'URI de redirection), donc il faut le
   stabiliser avant que quoi que ce soit s'appuie dessus.
3. **T-39** — changement de comportement, touche au domaine.
4. **T-40** — un commentaire ; il peut accompagner n'importe lequel des précédents.

Aucun appariement refactor-avant-comportement ne s'applique ici : aucun des quatre ne déplace du
code sans le changer.

## Différé

**T-41 — descripteur `OAuthVendor`.** Un enregistrement déclaratif de fournisseur (URL
d'autorisation et de jeton, scopes, nécessité d'enregistrer une application) pour qu'un nouveau
fournisseur soit une constante plutôt qu'un module. Pas maintenant : Hugging Face est le seul
fournisseur avec une connexion, donc le descripteur aurait exactement une instance. Une abstraction
à une seule implémentation ne cache aucune variation, elle ne fait que la deviner.

**Déclencheur.** Le deuxième fournisseur avec un vrai flux OAuth (Groq, Mistral, Together, GitHub
Models). À une instance la forme est une supposition ; à deux les différences sont des preuves.

## Hors de cette note

- **Le flux de connexion lui-même** — `provider-sign-in.md` reste la référence pour PKCE, `state`,
  le TTL de session et le magasin d'identifiants.
- **T-38, la déduplication de `registerOpenAICompatible`** — cela concerne l'enregistrement dupliqué
  de fournisseurs, pas OAuth, et touche des fournisseurs qui ne se connectent jamais. Il lui faut sa
  propre note, ou bien elle peut passer directement en série depuis son entrée dans la note qui la détient.
- **Les fournisseurs à clé d'API** — pas de callback, pas d'expiration, pas de rafraîchissement ;
  rien ici ne les concerne.
- **`KeychainCredentialStore`** — T-26, déjà cadré dans `provider-sign-in.md` §1.
- **Les changements côté client web** — la connexion depuis les réglages existe déjà et ne demande
  aucun changement de code : elle lit `signed_in` depuis l'URL sur laquelle elle atterrit, quelle que
  soit cette origine. Seul le serveur décide de cette origine. Si l'onglet d'atterrissage devait
  reparler à l'onglet ouvreur, c'est du travail client et cela relève de `web/docs/TASKS.md`.
- **L'interaction entre CORS et `--public-url`** — `--cors-origin` gouverne les XHR ; le callback est
  une navigation de premier niveau et n'y est pas soumis.
- **`RemoteSignInCommands.begin` acceptant un `callback` qu'il ignore** — une signature trompeuse,
  pas un défaut : le serveur détient le callback par conception.

## Questions ouvertes

- **Un `publicURL` non-loopback doit-il être en HTTPS ?** Hugging Face enregistre une URI de
  redirection sur l'application OAuth et plusieurs fournisseurs refusent une redirection non-loopback
  en clair. Si c'est le cas, T-37 devrait rejeter un `publicURL` en `http://` dont l'hôte n'est pas
  loopback plutôt que d'accepter une URL que le fournisseur refusera ensuite. À vérifier contre les
  réglages d'application de Hugging Face avant de découper T-37 en patches ; cela change une branche
  de validation, pas la conception.
- **En dev Vite la bannière de confirmation n'apparaît jamais.** L'application est servie sur `5173`
  tandis que l'API et le callback sont sur `5175`, donc le nouvel onglet atterrit sur
  `5175/settings`, qui ne sert aucun frontend à moins que `--static-dir` soit défini. Préexistant,
  indépendant de T-37, et sans doute la première chose sur laquelle `publicURL` devrait pointer dans
  une configuration de dev. À confirmer avant de décider si cela mérite sa propre tâche.
- **`dashboard ai providers login <id>` signale un succès sans avoir connecté quand un identifiant
  existe déjà.** Les deux conditions de sondage demandent si un identifiant est présent, pas si
  _cette_ connexion s'est terminée — `waitUntil { …hasAPIKey == true }` (`AILoginCommand:43`) et
  `waitUntil { credentials.get(id) != nil }` (`:62`). Se réauthentifier avec un jeton Hugging Face
  expiré est exactement le moment où cette commande est lancée. C'est un défaut du flux existant
  plutôt qu'une partie du durcissement, donc il lui faut sa propre carte avant
  d'être conçu ici.

## Tâches

La liste des tâches vit dans la version de référence —
[`20260922-provider-oauth-hardening.md`](20260922-provider-oauth-hardening.md) § _Tasks_ — pour
qu'elle n'existe qu'une fois, et parce que `scripts/next-tasks.sh` la lit là.
