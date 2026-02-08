#!/bin/bash
set -e

echo "=== HACK STARTUP SCRIPT ==="

# 1. Setup Mock Plugin
echo "Creating mock memory-core plugin..."
PLUGIN_DIR="/home/node/.openclaw/extensions"
mkdir -p "$PLUGIN_DIR/memory-core"

cat > "$PLUGIN_DIR/memory-core/package.json" <<EOF
{
  "name": "@openclaw/memory-core",
  "version": "0.0.0",
  "main": "index.js",
  "openclaw": { "id": "memory-core", "kind": "memory" }
}
EOF

cat > "$PLUGIN_DIR/memory-core/index.js" <<EOF
module.exports = {
  id: "memory-core",
  register(api) {
    console.log("MOCK MEMORY CORE LOADED - Functionality will be limited");
    if (api && api.registerMemory) {
        api.registerMemory({
            id: "memory-core",
            search: async () => [],
            add: async () => {},
            get: async () => null
        });
    }
  }
};
EOF

cat > "$PLUGIN_DIR/memory-core/openclaw.plugin.json" <<EOF
{ "id": "memory-core", "kind": "memory", "configSchema": {} }
EOF


# 2. Setup Config
echo "Setting up configuration..."
CONFIG_DIR="/home/node/.openclaw"
mkdir -p "$CONFIG_DIR"

# Copy default configuration from secret mount (if exists) or create default
if [ -f "/app/config/openclaw.json" ]; then
    cp /app/config/openclaw.json "$CONFIG_DIR/openclaw.json"
else
    echo "Warning: No config found at /app/config/openclaw.json, using defaults"
    echo "{}" > "$CONFIG_DIR/openclaw.json"
fi

# 3. Inject Secrets and Config Overrides using Node.js script
echo "Injecting secrets and updating config..."
node -e "
const fs = require('fs');
const path = '$CONFIG_DIR/openclaw.json';
let config = {};
try {
    if (fs.existsSync(path)) {
        config = JSON.parse(fs.readFileSync(path, 'utf8'));
    }
} catch (e) {
    console.error('Failed to parse config:', e);
}

config.gateway = config.gateway || {};
config.gateway.auth = config.gateway.auth || {};

// Inject Token
if (process.env.OPENCLAW_GATEWAY_TOKEN) {
    config.gateway.auth.token = process.env.OPENCLAW_GATEWAY_TOKEN;
    console.log('✓ Token injected');
}

// Inject Port (Cloud Run Requirement)
const port = parseInt(process.env.PORT || '8080');
config.gateway.port = port;
console.log('✓ Port set to ' + port);

// Ensure memory plugin is configured to use default (mock)
config.plugins = config.plugins || {};
config.plugins.slots = config.plugins.slots || {};
// Force memory slot to use 'memory-core' string explicitly to match mock plugin ID
config.plugins.slots.memory = 'memory-core';

fs.writeFileSync(path, JSON.stringify(config, null, 2));
"

# 4. Start Gateway directly
echo "Starting Gateway..."
# Use exec to replace shell with node process for signal handling
exec node dist/index.js gateway --allow-unconfigured --bind 0.0.0.0 --port "${PORT:-8080}"
