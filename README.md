# MCP server, Google Analytics 4 + Search Console

A remote Model Context Protocol (MCP) server, deployed on Cloudflare Workers, that exposes read-only Google Analytics 4 and Google Search Console data to MCP clients such as Claude Desktop, Cowork, Lovable Agent, and the MCP Inspector.

Built for the Rablab agency to power dashboards and content reporting workflows. Open for forks.

## Features

- 17 read-only tools across Google Analytics 4 and Search Console
- OAuth 2.0 user authentication via Google with `analytics.readonly` and `webmasters.readonly` scopes
- Automatic refresh token, no need to reconnect every hour
- Works with Dynamic Client Registration (DCR) for compatibility with MCP Inspector, Cowork, Lovable, etc.
- Email and domain allowlist via `ALLOWED_EMAILS` and `ALLOWED_DOMAINS` secrets, so only authorized accounts can mint an MCP token
- Branded access-denied page for users outside the allowlist (Rablab colors)
- Multi-user friendly, each authorized user authenticates with their own Google account
- Deployed once on Cloudflare Workers, available to a whole team

## Available tools

Google Analytics 4 (12 tools, all read-only):

- `ga4_list_account_summaries`, lists all accounts and properties accessible to the user
- `ga4_list_properties`, lists properties under a specific account
- `ga4_get_property_details`, returns timezone, currency, industry, etc.
- `ga4_list_data_streams`, lists web, iOS, Android streams
- `ga4_get_metadata`, lists all dimensions and metrics available on a property
- `ga4_check_compatibility`, validates dimension and metric combos
- `ga4_run_report`, runs a custom report (sessions, conversions, etc. by dimension and date)
- `ga4_run_realtime_report`, runs a realtime report (last 30 minutes)
- `ga4_run_pivot_report`, pivot tables
- `ga4_batch_run_reports`, up to 5 reports in one API call
- `ga4_list_key_events`, lists key events and conversions
- `ga4_list_conversion_events`, legacy conversion events
- `ga4_list_custom_dimensions`, `ga4_list_custom_metrics`
- `ga4_list_audiences`, `ga4_list_google_ads_links`, `ga4_list_firebase_links`

Google Search Console (5 tools, all read-only):

- `gsc_list_sites`, lists all GSC properties accessible to the user
- `gsc_query_search_analytics`, clicks, impressions, CTR, position by dimensions and date
- `gsc_list_sitemaps`, lists sitemaps submitted
- `gsc_get_sitemap`, details of a specific sitemap
- `gsc_inspect_url`, URL inspection (indexation status, last crawl, mobile usability)

No write actions are exposed. Worst case if credentials leak, the attacker can only read GA4 and GSC data they already have access to.

## Architecture

```
MCP client (Claude, Cowork, Lovable, Inspector)
│
│ MCP over SSE
▼
Cloudflare Worker (this repo)
├── @cloudflare/workers-oauth-provider
│    handles MCP OAuth + Dynamic Client Registration
├── google-handler.ts
│    handles Google OAuth flow + email allowlist + refresh token
└── 17 MCP tools
│
▼
Google APIs (analyticsdata, analyticsadmin, searchconsole, webmasters)
```

## Setup for your own deployment

If you fork this repo to deploy your own MCP server.

### 1. Google Cloud setup

In your Google Cloud project:

1. Enable the following APIs:
- Google Analytics Admin API
- Google Analytics Data API
- Google Search Console API
2. Configure the OAuth Consent Screen (Audience: External, mode Test, add yourself as a test user).
3. Create an OAuth 2.0 Client ID, type Web Application:
- Authorized JavaScript origin: `https://<your-worker-name>.<your-subdomain>.workers.dev`
- Authorized redirect URI: `https://<your-worker-name>.<your-subdomain>.workers.dev/callback`
4. Note the Client ID. Click `Add secret`, copy the Client Secret value (shown only once).

### 2. Cloudflare setup

1. Create a KV namespace, name it `OAUTH_KV`. Note its ID.
2. Edit `wrangler.jsonc`:
- `name`: your worker name (this controls the URL)
- `kv_namespaces[0].id`: replace with your KV namespace ID

### 3. Deploy

```bash
npm install --legacy-peer-deps

# Set the secrets (you'll be prompted to paste each value)
npx wrangler secret put GOOGLE_CLIENT_ID
npx wrangler secret put GOOGLE_CLIENT_SECRET
npx wrangler secret put COOKIE_ENCRYPTION_KEY # any random 32-char hex string, e.g. openssl rand -hex 32
npx wrangler secret put HOSTED_DOMAIN # press Enter for empty (accept any Google Workspace domain)
npx wrangler secret put ALLOWED_EMAILS # comma-separated emails, e.g. alice@example.com,bob@example.com
npx wrangler secret put ALLOWED_DOMAINS # optional, comma-separated domains, e.g. example.com

# Deploy
npx wrangler deploy
```

At least one of `ALLOWED_EMAILS` or `ALLOWED_DOMAINS` must be set, otherwise no one can sign in (see Access control below).

### 4. Access control: ALLOWED_EMAILS and ALLOWED_DOMAINS

After a user signs in with Google, the worker checks their email against two Cloudflare secrets before issuing an MCP token:

- `ALLOWED_EMAILS`: comma-separated list of full email addresses allowed to authenticate (case-insensitive). Example: `alice@example.com,bob@example.com`.
- `ALLOWED_DOMAINS`: comma-separated list of domains. Any email ending with `@domain` is allowed (case-insensitive). Example: `example.com,partner.com`.

The two lists are additive: an email is allowed if it matches either one.

If neither secret is set, the worker rejects every sign-in. This is intentional. Without an allowlist, any Google account could complete the OAuth flow and mint a token, burning the deployment.

Unauthorized users get a branded "Acces refuse" 403 page (Rablab colors) instead of a token. No error leaks to the MCP client.

To update the allowlist after deployment:

```bash
# Replace the value (you'll be prompted for the new full list)
npx wrangler secret put ALLOWED_EMAILS
```

The change takes effect on the next sign-in. Existing MCP tokens stay valid until they expire; to revoke immediately, purge the `OAUTH_KV` namespace.

### 5. Test with MCP Inspector

```bash
npx @modelcontextprotocol/inspector@latest
```

Open `http://localhost:6274`. Set Transport Type to `SSE`, URL to `https://<your-worker>.workers.dev/sse`, click Connect. A Google OAuth flow opens, approve the scopes. Then try `gsc_list_sites` to confirm it works.

If you sign in with an unlisted email, you should see the "Acces refuse" 403 page instead. Use this to validate the allowlist before sharing the worker URL with your team.

### 6. Connect to Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json`:

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

**Multiple Google accounts on the same machine.** Claude Desktop deduplicates MCP servers by URL, so you cannot add the same `/sse` endpoint twice. The worker supports multi-account via the `ALIAS_PATHS` env variable: each alias is a separate URL that Claude treats as a distinct connector (e.g. `/sse-secondary`). By default `ALIAS_PATHS` is unset so the worker behaves like a normal single-account MCP.

**Path-based access control (optional).** You can also restrict each path to specific authorized emails via the `PATH_EMAIL_MAP` env variable, a JSON map of `path -> [authorized emails]`. Useful when you want an alias path usable by one specific user only (e.g. a test path isolated from team usage, or strict separation between account holders in a transition setup). If `PATH_EMAIL_MAP` is unset, no path-level restriction applies and any email in `ALLOWED_EMAILS` can use any path.

See [`MULTI-ACCOUNT.md`](./MULTI-ACCOUNT.md) for step-by-step scenarios (add a route, remove a route, fork the repo, restrict paths to specific users, troubleshoot).

### 7. Connect at organization level (recommended)

If you have an Anthropic organization (Claude Team or Enterprise), add the worker URL as a custom connector at the organization level. Every team member gets access in Cowork, Claude Desktop, and claude.ai web without local config. The allowlist enforces who can actually authenticate.

## Local development

```bash
npm install --legacy-peer-deps
cp .dev.vars.example .dev.vars
# Fill in the values in .dev.vars (do not commit this file)
npx wrangler dev
```

For local dev, set `ALLOWED_EMAILS` (and optionally `ALLOWED_DOMAINS`) in `.dev.vars` too, otherwise the local worker rejects all sign-ins.

## CI/CD with Cloudflare Workers Builds

This repo is set up to auto-deploy on push to `main` via Cloudflare Workers Builds. Connect this GitHub repository in your Cloudflare Workers dashboard:

- Build command: `npm install --legacy-peer-deps`
- Deploy command: `npx wrangler deploy`
- Production branch: `main`

Each commit on `main` rebuilds and redeploys the worker. Other branches build preview workers at distinct URLs.

Secrets (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `COOKIE_ENCRYPTION_KEY`, `HOSTED_DOMAIN`, `ALLOWED_EMAILS`, `ALLOWED_DOMAINS`) are set once with `wrangler secret put` and persist across deploys.

## Security notes

- All Google API calls are read-only. No write scope is requested.
- Tokens (access and refresh) are stored encrypted in the OAuth provider's KV store and as Durable Object props, never logged.
- The `.dev.vars` file (containing local secrets for development) is gitignored.
- Access is restricted by the `ALLOWED_EMAILS` and `ALLOWED_DOMAINS` allowlist, checked server-side after Google OAuth. Without at least one of these secrets set, the worker rejects all sign-ins by design.
- Each authorized user authenticates with their own Google account, so the worker only has access to the GA4 and GSC properties that user already has access to. No service account, no shared credentials.
- Set the OAuth Consent Screen to Test mode and only add trusted test users until you complete Google verification (only required for >100 users).

## Credits

This project is forked from and inspired by [bighadj22/cloudflare-mcp-google-oauth-analytics](https://github.com/bighadj22/cloudflare-mcp-google-oauth-analytics), which provided the original Cloudflare Workers + Google OAuth + MCP boilerplate. The Rablab fork:

- Replaces the dummy `add` tool with 17 production-ready Google Analytics 4 and Search Console read-only tools
- Migrates from the deprecated `mcp-analytics` package to the native `agents/mcp` SDK from Cloudflare
- Adds `access_type=offline` + automatic refresh token handling so users don't reconnect every hour
- Fixes Google OAuth token exchange request body to use snake_case as required by Google
- Adds an email/domain allowlist (`ALLOWED_EMAILS` and `ALLOWED_DOMAINS`) enforced server-side after Google OAuth, with a branded access-denied page for unauthorized accounts

## License

MIT, see [LICENSE](LICENSE).
