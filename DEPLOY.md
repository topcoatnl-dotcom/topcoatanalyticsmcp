# Deployment guide

End-to-end guide to deploy this worker on Cloudflare and connect it to Claude Desktop or your Anthropic organization.

## Prerequisites

- A Cloudflare account with Workers and KV enabled.
- A Google Cloud project where you control the OAuth Consent Screen and OAuth clients.
- `node` 22+, `npm`, and `git` installed locally.
- `wrangler` available via `npx` (no global install needed).

## 1. Google Cloud setup

### 1.1 Create the project (or reuse an existing one)

Go to https://console.cloud.google.com/projectcreate and create a new project, or pick an existing one.

### 1.2 Enable the required APIs

In the project, enable :

- Google Analytics Admin API
- Google Analytics Data API
- Google Search Console API

URL : https://console.cloud.google.com/apis/library

### 1.3 Configure the OAuth Consent Screen

In the project, go to OAuth Consent Screen :

- User Type : External (unless your organization is a Google Workspace and you want to restrict).
- App name : your choice (this is what users see in the Google OAuth dialog).
- Support email : an admin email.
- Scopes : you do not need to declare scopes here, they are passed in the OAuth flow.
- Test users (while in Testing mode) : add every Google account that will use the worker (up to 100). Without this, the OAuth flow returns access_denied.

### 1.4 Create the OAuth Client

In the project, go to Credentials → Create credentials → OAuth client ID :

- Application type : Web application
- Name : your choice
- Authorized redirect URI : `https://<your-worker>.workers.dev/callback`
- (Optional, local dev) add `http://localhost:8788/callback`

Click Create. A dialog shows the Client ID and Client Secret. **Save both somewhere secure** (password manager). You will paste them in the next section.

## 2. Cloudflare setup

### 2.1 Create the KV namespace

```bash
npx wrangler kv:namespace create OAUTH_KV
```

This prints a namespace ID. Open `wrangler.jsonc` and update the `id` field under `kv_namespaces` with the new ID.

### 2.2 Set the worker name

In `wrangler.jsonc`, change the `name` field to whatever you want your worker to be called. The deployed URL will be `https://<name>.<your-cloudflare-subdomain>.workers.dev`.

## 3. Deploy

### Option A : use the helper script

```bash
./deploy.sh
```

The script :

- Logs you into Cloudflare if needed.
- Prompts you for the Google Client ID and Client Secret.
- Generates a random `COOKIE_ENCRYPTION_KEY`.
- Prompts for the optional `ALLOWED_EMAILS`, `ALLOWED_DOMAINS`, and `ALIAS_PATHS` secrets.
- Deploys the worker.

### Option B : manual

```bash
# Login if needed
npx wrangler login

# Required secrets
npx wrangler secret put GOOGLE_CLIENT_ID
npx wrangler secret put GOOGLE_CLIENT_SECRET
npx wrangler secret put COOKIE_ENCRYPTION_KEY
# (use openssl rand -hex 32 to generate a value)
npx wrangler secret put HOSTED_DOMAIN
# (leave empty unless restricting to a single Google Workspace domain)

# Optional secrets
npx wrangler secret put ALLOWED_EMAILS
# Comma-separated list of authorized emails, e.g. alice@x.com,bob@y.com
npx wrangler secret put ALLOWED_DOMAINS
# Comma-separated list of authorized domains, e.g. example.com,other.com
npx wrangler secret put ALIAS_PATHS
# Comma-separated list of alias paths for multi-account, e.g. /sse-secondary
# Leave empty for single-account mode

# Deploy
npx wrangler deploy
```

At least one of `ALLOWED_EMAILS` or `ALLOWED_DOMAINS` must be set. Without these, the worker rejects all sign-ins by design (security gate).

The worker is now live at `https://<your-worker>.workers.dev`.

## 4. Test with MCP Inspector

```bash
npx @modelcontextprotocol/inspector
```

Open the URL shown in the terminal. Set Transport Type to `SSE`, URL to `https://<your-worker>.workers.dev/sse`, click Connect. A Google OAuth flow opens, approve the scopes. Then try `gsc_list_sites` to confirm it works.

## 5. Connect to Claude Desktop

### Manual config

Edit `~/Library/Application Support/Claude/claude_desktop_config.json` :

```json
{
  "mcpServers": {
    "ga4-gsc": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://<your-worker>.workers.dev/sse"]
    }
  }
}
```

Restart Claude Desktop. The first time you call a tool, an OAuth flow opens in your browser.

### Helper script

```bash
WORKER_URL="https://<your-worker>.workers.dev/sse" KEY="ga4-gsc" ./install_in_claude_desktop.sh
```

The script preserves your existing MCPs.

## 6. Connect at organization level (Anthropic Teams/Enterprise)

If you have an Anthropic organization, add the worker URL as a custom connector at the organization level. Every team member gets access in Cowork, Claude Desktop, and claude.ai web without local config. The allowlist enforces who can actually authenticate.

## 7. Multi-account setup

If you need to connect multiple Google accounts to the same worker, see [`MULTI-ACCOUNT.md`](./MULTI-ACCOUNT.md).

In short : set `ALIAS_PATHS=/sse-secondary` as a secret, redeploy, and add a second connector in Claude with URL `https://<your-worker>.workers.dev/sse-secondary`. Each alias has its own OAuth and tokens.

## 8. Troubleshooting

### `wrangler deploy` fails with `workerd-* missing`

The platform-specific Workerd binary (macOS arm64, Linux x64, etc.) was not installed because npm skipped `optionalDependencies` on a previous install. Force a clean install :

```bash
rm -rf node_modules
npm install --include=optional --legacy-peer-deps
npx wrangler deploy
```

Do NOT install the binary directly as a `dependency` (e.g. `npm install @cloudflare/workerd-darwin-arm64`) because it would break the build on other platforms (Cloudflare's build runner is Linux x64).

### Google OAuth returns 403 access_denied

The Google account is not in the Test users list of the OAuth Consent Screen. Add it at https://console.cloud.google.com/auth/audience

### Worker shows the Access Denied page after Google OAuth

The Google account is not in `ALLOWED_EMAILS` (or its domain not in `ALLOWED_DOMAINS`). Update the secret :

```bash
npx wrangler secret put ALLOWED_EMAILS
```

### Live logs

```bash
npx wrangler tail <your-worker-name> --format pretty
```
