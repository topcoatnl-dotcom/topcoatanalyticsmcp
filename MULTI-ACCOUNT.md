# Multi-compte : guide pratique

Ce guide explique comment configurer le worker pour servir un, deux ou N comptes Google différents dans Claude Desktop, sans avoir à toucher au code MCP lui-même.

## Pourquoi plusieurs comptes ?

Claude Desktop déduplique les serveurs MCP par URL exacte. Si tu veux connecter deux comptes Google distincts au même service (par exemple parce que tu transitionnes d'un compte à un autre, ou parce que tu gères des portefeuilles séparés), il te faut **deux URLs différentes** qui pointent vers le même worker.

Le worker supporte ce cas via un système d'alias : tu déclares des chemins additionnels (`/sse-quelque-chose`), et le worker les réécrit en interne vers `/sse`. Côté Claude, chaque URL distincte déclenche son propre OAuth et stocke ses propres tokens.

## Configuration par défaut

```ts
// src/index.ts
const ALIAS_PATHS = [];
```

Une seule route : `/sse`. Comportement identique à une installation MCP vanilla. Aucun wrapper de rewrite ne s'active, performance inchangée.

## Scénarios

### Scénario 1 : un seul compte

C'est la configuration par défaut pour quiconque fork le repo sans avoir besoin du multi-compte.

`src/index.ts` :

```ts
const ALIAS_PATHS = [];
```

`wrangler.jsonc` :

```jsonc
"ALLOWED_EMAILS": "votre-compte@votre-domaine.com"
```

Une seule route : `https://<votre-worker>.workers.dev/sse`.

### Scénario 2 : deux comptes

Tu veux connecter deux comptes Google distincts (par exemple un compte principal et un compte secondaire).

`src/index.ts` :

```ts
const ALIAS_PATHS = ["/sse-secondary"];
```

`wrangler.jsonc` :

```jsonc
"ALLOWED_EMAILS": "compte-principal@domaine.com,compte-secondaire@domaine.com"
```

Routes actives :

- `https://<votre-worker>.workers.dev/sse` (compte principal)
- `https://<votre-worker>.workers.dev/sse-secondary` (compte secondaire)

### Scénario 3 : ajouter un compte supplémentaire

Tu veux passer de 2 à 3 comptes.

**Étape 1, code (2 lignes)**

`src/index.ts` :

```ts
const ALIAS_PATHS = ["/sse-secondary", "/sse-staging"];
```

`wrangler.jsonc` :

```jsonc
"ALLOWED_EMAILS": "compte-1@domaine.com,compte-2@domaine.com,compte-3@domaine.com"
```

**Étape 2, Google Cloud**

Ajouter le nouvel email dans les test users du projet OAuth :
https://console.cloud.google.com/auth/audience

**Étape 3, déploiement**

```bash
git add src/index.ts wrangler.jsonc
git commit -m "feat: add third account route"
git push
npx wrangler deploy
```

**Étape 4, Claude Desktop**

Ajouter un nouveau connecteur avec l'URL `https://<votre-worker>.workers.dev/sse-staging`. Faire l'OAuth Google avec le compte correspondant.

Total : 5 minutes.

### Scénario 4 : retirer un compte

Tu veux décommissionner un compte.

**Option A, retrait minimal (sans redeploy)**

Le plus rapide. Tu retires juste l'email de la liste autorisée via le dashboard.

Dashboard Cloudflare → Workers → ton worker → Settings → Variables and Secrets → `ALLOWED_EMAILS` → enlever l'email → Save and deploy.

L'URL reste techniquement vivante mais aucun compte ne peut plus s'authentifier dessus. Tu déconnectes manuellement le connecteur côté Claude Desktop sur chaque machine concernée.

**Option B, nettoyage du code**

Plus propre à long terme. Tu retires aussi la route.

Si tu veux supprimer une route alias et garder uniquement la route principale, modifie `src/index.ts` pour enlever l'entrée correspondante de `ALIAS_PATHS`, redeploie.

Si tu veux remplacer la route principale par une route alias (par exemple promouvoir `/sse-secondary` au rang de route principale), modifie `src/index.ts` :

```ts
const ALIAS_PATHS = [];
const mcpHandler = MyMCP.mount("/sse-secondary") as any;

// dans OAuthProvider :
apiRoute: ["/sse-secondary"],
```

Déploie. La route `/sse` retourne 404. Les utilisateurs du compte secondaire continuent de fonctionner sans rien changer côté Claude.

### Scénario 5 : fork du repo par une autre équipe

Quelqu'un fork le repo pour son propre projet. Il fait :

1. `git clone` du fork
2. Modifier `wrangler.jsonc` :
   - Renommer le worker (`name`)
   - Créer un nouveau KV namespace (`npx wrangler kv:namespace create OAUTH_KV`) et mettre son ID dans le fichier
   - Mettre son propre `ALLOWED_EMAILS`
3. Créer un projet Google Cloud + OAuth client (voir `DEPLOY.md` pour la procédure)
4. Setter ses secrets (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `COOKIE_ENCRYPTION_KEY`)
5. `npx wrangler deploy`

Aucun code MCP à modifier. Le multi-compte est désactivé par défaut (`ALIAS_PATHS = []`).

## Restreindre les chemins par utilisateur (optionnel)

Par défaut, n'importe quel email présent dans `ALLOWED_EMAILS` peut se connecter à n'importe quel chemin (`/sse`, `/sse-secondary`, etc.). Si tu veux qu'un chemin donné soit réservé à un email précis (par exemple pour éviter les mélanges accidentels dans une équipe, ou pour isoler un chemin de test), configure la variable `PATH_EMAIL_MAP`.

**Format** : JSON string, chaque clé est un chemin de base et la valeur est la liste des emails autorisés sur ce chemin.

**Setup dans le dashboard Cloudflare** (Settings -> Variables and Secrets -> Add -> Plaintext) :

- Name : `PATH_EMAIL_MAP`
- Value (exemple) : `{"/sse":["alice@example.com"],"/sse-secondary":["bob@example.com"],"/sse-test":["alice-test@example.com"]}`

**Comportement** :

- Si `PATH_EMAIL_MAP` n'est pas définie ou vide → aucun filtrage par chemin (comportement par défaut)
- Si un chemin est dans la map mais qu'un email non listé tente de l'utiliser → erreur 403
- Si un chemin n'est PAS dans la map → aucune restriction sur ce chemin (les emails de `ALLOWED_EMAILS` y ont accès)

**Quand l'utiliser** :

- Équipe nombreuse, risque de mélange d'accès clients
- Chemin de test isolé (que toi seul doit pouvoir utiliser)
- Audit / conformité (qui peut accéder à quoi)

**Quand ne PAS l'utiliser** :

- Petit setup où la discipline suffit
- Tu veux maximiser la flexibilité de connexion

Modifier `PATH_EMAIL_MAP` ne nécessite pas de redeploy : c'est lu au runtime à chaque requête. Édite la valeur dans le dashboard, Save and deploy (config-only deploy en quelques secondes), c'est en place.

## Comprendre le routing

Le `OAuthProvider` route les requêtes entrantes selon ce mécanisme :

```
URL reçue
  ├── pathname commence par une route déclarée dans apiRoute ?
  │     ├── OUI → vérifie le token OAuth → passe à apiHandler (le wrapper MCP)
  │     │            └── le wrapper rewrite l'URL si elle matche un alias, puis appelle le MCP handler
  │     └── NON → passe à defaultHandler (GoogleHandler) qui gère /authorize, /callback, etc.
```

Le matching de `apiRoute` est **par préfixe**. Si tu déclares `apiRoute: ["/sse"]`, toute URL commençant par `/sse` est considérée comme une requête API par OAuthProvider, mais le MCP handler interne fait du matching strict, donc seules les routes exactes `/sse` et `/sse/message` répondent vraiment.

Conséquence pratique : **tu ne peux pas balancer une URL random à Claude et espérer que ça marche**. Il faut que la route soit explicitement déclarée dans `ALIAS_PATHS` (ou que ce soit `/sse`).

## Limites

| Limite | Valeur | Source |
|---|---|---|
| Nombre max de routes alias | Aucune limite technique | Wrapper itère sur un array |
| Nombre max d'emails dans ALLOWED_EMAILS | Aucune limite technique | Parsé par split(',') |
| Nombre max de test users Google | 100 | Mode Testing de Google OAuth |
| Au-delà de 100 utilisateurs | Publier l'app OAuth | Vérification Google nécessaire (2 à 4 semaines) |

## Troubleshooting

### « A server with this URL already exists » dans Claude Desktop

Tu essaies d'ajouter deux fois la même URL. Vérifie que tu mets bien un chemin différent (`/sse-secondary` par exemple) pour le 2e connecteur, pas `/sse`.

### Erreur 403 access_denied de Google après l'OAuth

L'email du compte n'est pas dans les test users du projet Google Cloud. Aller sur https://console.cloud.google.com/auth/audience et ajouter l'email.

### Page « Accès refusé » du worker après l'OAuth Google

L'email du compte n'est pas dans `ALLOWED_EMAILS` (variable Cloudflare). Modifier la variable dans `wrangler.jsonc` puis `npx wrangler deploy`, ou directement dans le dashboard Cloudflare.

### Le connecteur se connecte mais « aucun outil disponible »

Vérifier les logs en temps réel :

```bash
npx wrangler tail <nom-du-worker> --format pretty
```

Rafraîchir les outils dans Claude Desktop. Si le SSE handshake n'aboutit pas, c'est souvent un problème de rewrite (chemin alias mal écrit dans `ALIAS_PATHS`).

### Refus de déploiement Wrangler avec « workerd-* missing »

Le binaire natif de Workerd correspondant à ta plateforme (macOS arm64, Linux x64, etc.) n'a pas été installé. Cela arrive quand npm a sauté les `optionalDependencies` lors d'une install passée.

Solution propre : régénérer les `node_modules` en forçant les optional deps.

```bash
rm -rf node_modules
npm install --include=optional --legacy-peer-deps
npx wrangler deploy
```

Ne PAS installer le binaire directement en `dependencies` (par exemple `npm install @cloudflare/workerd-darwin-arm64`), car cela casse le build sur les autres plateformes (le runner Cloudflare est Linux x64 et refuserait un binaire Darwin).
