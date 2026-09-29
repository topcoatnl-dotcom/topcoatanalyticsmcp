#!/usr/bin/env bash
# Adds the GA4 + Search Console MCP to Claude Desktop without overwriting
# other MCPs already configured. Edit WORKER_URL and KEY below to match your
# deployed worker.
set -euo pipefail

CONFIG_DIR="$HOME/Library/Application Support/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

# Override these two values for your deployment.
WORKER_URL="${WORKER_URL:-https://<your-worker>.workers.dev/sse}"
KEY="${KEY:-ga4-gsc}"

mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "{\"mcpServers\":{}}" > "$CONFIG_FILE"
fi

# Backup
cp "$CONFIG_FILE" "$CONFIG_FILE.bak.$(date +%s)"

# Merge via node, preserve existing keys
node <<NODE
const fs = require('fs');
const path = "$CONFIG_FILE";
const cfg = JSON.parse(fs.readFileSync(path, 'utf8') || '{"mcpServers":{}}');
cfg.mcpServers = cfg.mcpServers || {};
cfg.mcpServers["$KEY"] = {
  command: "npx",
  args: ["-y", "mcp-remote", "$WORKER_URL"]
};
fs.writeFileSync(path, JSON.stringify(cfg, null, 2));
console.log("Updated " + path);
console.log("Existing MCPs preserved:");
Object.keys(cfg.mcpServers).forEach(k => console.log("  - " + k));
NODE

echo ""
echo "MCP $KEY added to Claude Desktop"
echo ""
echo "Restart Claude Desktop (Cmd+Q then relaunch) so the MCP is loaded."
echo "On the first tool call, a browser opens for the OAuth flow."
