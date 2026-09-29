#!/usr/bin/env bash
# Worker deployment helper for the GA4 + Search Console MCP.
# Prompts for the Google OAuth Client ID and Client Secret, then sets all
# the secrets and deploys via wrangler.
#
# Prerequisites :
#   1. A Google Cloud project with the Analytics Admin, Analytics Data and
#      Search Console APIs enabled.
#   2. A Google OAuth 2.0 Web Application client created in that project,
#      with redirect URI https://<your-worker>.workers.dev/callback
#   3. A Cloudflare account with a deployed worker (run npx wrangler deploy
#      once before this script, or let this script trigger the first deploy).
#
# See DEPLOY.md for the full step-by-step.

set -euo pipefail

cd "$(dirname "$0")"

COOKIE_ENCRYPTION_KEY="$(openssl rand -hex 32)"

echo ""
echo "=== Worker deployment to Cloudflare ==="
echo ""

# Step 1, wrangler login (opens browser)
if ! npx wrangler whoami >/dev/null 2>&1; then
  echo "Cloudflare login required. A browser tab will open."
  npx wrangler login
fi
echo "Cloudflare auth OK"
echo ""

# Step 2, prompt for Google OAuth Client ID
echo "Enter your Google OAuth Client ID :"
read -r GOOGLE_CLIENT_ID
if [ -z "$GOOGLE_CLIENT_ID" ]; then
  echo "Client ID is required, aborting."
  exit 1
fi
echo ""

echo "Setting GOOGLE_CLIENT_ID..."
echo "$GOOGLE_CLIENT_ID" | npx wrangler secret put GOOGLE_CLIENT_ID
echo ""

echo "Setting COOKIE_ENCRYPTION_KEY (random 32 bytes hex)..."
echo "$COOKIE_ENCRYPTION_KEY" | npx wrangler secret put COOKIE_ENCRYPTION_KEY
echo ""

echo "Setting HOSTED_DOMAIN (empty, accept any Google account)..."
echo "" | npx wrangler secret put HOSTED_DOMAIN
echo ""

# Step 3, prompt for Google OAuth Client Secret
echo "──────────────────────────────────────────────────────────────"
echo " Now paste your Google OAuth Client Secret"
echo "──────────────────────────────────────────────────────────────"
echo " Find it at :"
echo "   https://console.cloud.google.com/auth/clients"
echo " Pick your OAuth client and copy the secret."
echo "──────────────────────────────────────────────────────────────"
echo ""
npx wrangler secret put GOOGLE_CLIENT_SECRET

echo ""
echo "Optional secrets (skip with empty value if not needed) :"
echo ""

echo "Setting ALLOWED_EMAILS (comma-separated, e.g. alice@x.com,bob@y.com)..."
npx wrangler secret put ALLOWED_EMAILS
echo ""

echo "Setting ALLOWED_DOMAINS (comma-separated, e.g. example.com)..."
npx wrangler secret put ALLOWED_DOMAINS
echo ""

echo "Setting ALIAS_PATHS for multi-account (comma-separated, e.g. /sse-secondary)..."
echo "Leave empty for single-account mode (vanilla)."
npx wrangler secret put ALIAS_PATHS
echo ""

echo "All secrets in place"
echo ""

# Step 4, deploy
echo "Deploying..."
npx wrangler deploy

echo ""
echo "══════════════════════════════════════════════════════════════"
echo " Worker deployed"
echo " MCP SSE endpoint : https://<your-worker>.workers.dev/sse"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "To test with MCP Inspector :"
echo "  npx @modelcontextprotocol/inspector"
echo "Then paste your worker URL with /sse into Inspector"
echo "and call ga4_list_account_summaries or gsc_list_sites."
echo ""
echo "To add in Claude Desktop, see install_in_claude_desktop.sh"
echo "or edit claude_desktop_config.json :"
cat <<'JSON'
{
  "mcpServers": {
    "ga4-gsc": {
      "command": "npx",
      "args": ["mcp-remote", "https://<your-worker>.workers.dev/sse"]
    }
  }
}
JSON
