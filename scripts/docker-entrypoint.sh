#!/bin/sh
# ============================================================
# OpenClaw Cloud Run - Entrypoint Script
# ============================================================
set -e

CONFIG_DIR="/home/node/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"

echo "=== OpenClaw Startup ==="

# Create required directories
mkdir -p "${CONFIG_DIR}/identity"
mkdir -p "${CONFIG_DIR}/agents/main/agent"
mkdir -p "${CONFIG_DIR}/credentials"
mkdir -p "${CONFIG_DIR}/workspace"
mkdir -p "${CONFIG_DIR}/devices"
mkdir -p "${CONFIG_DIR}/memory"
mkdir -p "${CONFIG_DIR}/canvas"
mkdir -p "${CONFIG_DIR}/extensions"

# Copy extensions from build stage to home dir
if [ -d "/app/extensions" ]; then
  echo "✓ Copying extensions..."
  cp -r /app/extensions/* "${CONFIG_DIR}/extensions/"
fi

# Pre-approve devices hack
echo '{"silent": true}' > "${CONFIG_DIR}/devices/pending.json"

# Create a default SOUL for the main agent if missing
if [ ! -f "${CONFIG_DIR}/agents/main/SOUL.md" ]; then
  echo "✓ Creating default SOUL..."
  cat > "${CONFIG_DIR}/agents/main/SOUL.md" <<EOF
# Main Agent
You are a helpful AI assistant running on OpenClaw.
Respond concisely and helpfully to user requests.
EOF
fi

# Copy base config from /app/config if it exists and we don't have one
if [ -f "/app/config/openclaw.json" ] && [ ! -f "${CONFIG_FILE}" ]; then
  cp /app/config/openclaw.json "${CONFIG_FILE}"
elif [ ! -f "${CONFIG_FILE}" ]; then
  echo "{}" > "${CONFIG_FILE}"
fi

# 1. Update Main openclaw.json
node -e "
const fs = require('fs');
let config = {};
try {
  config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));
} catch (e) {
  config = {};
}

// Gateway Settings for Cloud Run
config.gateway = config.gateway || {};
config.gateway.port = parseInt(process.env.PORT || '8080');
config.gateway.bind = 'lan';
config.gateway.trustedProxies = ['loopback', '127.0.0.1', '0.0.0.0/0'];
config.gateway.controlUi = config.gateway.controlUi || {};
config.gateway.controlUi.allowInsecureAuth = true;
config.gateway.controlUi.dangerouslyDisableDeviceAuth = true;

// Auth Profile Declaration
config.auth = config.auth || {};
config.auth.profiles = config.auth.profiles || {};
config.auth.profiles['google:default'] = {
  provider: 'google',
  mode: 'api_key'
};

// Plugin Slots (Match hack-start.sh)
config.plugins = config.plugins || {};
config.plugins.slots = config.plugins.slots || {};
config.plugins.slots.memory = 'memory-core';

// Model Defaults
config.agents = config.agents || {};
config.agents.defaults = config.agents.defaults || {};
config.agents.defaults.model = config.agents.defaults.model || {};
config.agents.defaults.model.primary = process.env.PRIMARY_MODEL || 'google/gemini-3-flash-preview';

// Gateway Token
if (process.env.OPENCLAW_GATEWAY_TOKEN) {
  config.gateway.auth = {
    mode: 'token',
    token: process.env.OPENCLAW_GATEWAY_TOKEN
  };
}

fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
console.log('✓ Main configuration updated');
"

# 2. Update Agent auth-profiles.json (Exact Production Format)
if [ -n "$GOOGLE_API_KEY" ]; then
  node -e "
const fs = require('fs');
const auth = {
  version: 1,
  profiles: {
    'google:default': {
      type: 'api_key',
      provider: 'google',
      key: process.env.GOOGLE_API_KEY
    }
  },
  lastGood: {
    google: 'google:default'
  },
  usageStats: {
    'google:default': {
      lastUsed: Date.now(),
      errorCount: 0
    }
  }
};
fs.writeFileSync('${CONFIG_DIR}/agents/main/agent/auth-profiles.json', JSON.stringify(auth, null, 2));
console.log('✓ Agent auth profiles injected');
"
fi

echo "============================================================"
echo "OpenClaw Configuration Ready"
echo "============================================================"
echo "Directory Structure:"
ls -R "${CONFIG_DIR}"
echo "============================================================"

# Start the gateway
exec node dist/index.js gateway --allow-unconfigured --bind lan --port "${PORT:-8080}"
