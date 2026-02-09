#!/bin/sh
# ============================================================
# OpenClaw Cloud Run - Entrypoint Script
# ============================================================
set -e

CONFIG_DIR="/home/node/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"

# Create required directories
mkdir -p "${CONFIG_DIR}/identity"
mkdir -p "${CONFIG_DIR}/agents/main/agent"
mkdir -p "${CONFIG_DIR}/credentials"
mkdir -p "${CONFIG_DIR}/workspace"
mkdir -p "${CONFIG_DIR}/devices"
mkdir -p "${CONFIG_DIR}/memory"
mkdir -p "${CONFIG_DIR}/canvas"

# Pre-approve devices hack
echo '{"silent": true}' > "${CONFIG_DIR}/devices/pending.json"

# Copy default config if exists
if [ -f "/app/config/openclaw.json" ]; then
  cp /app/config/openclaw.json "${CONFIG_FILE}"
fi

# 1. Update Main openclaw.json (Schema Matching Production)
node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));

// Gateway Settings for Cloud Run
config.gateway = config.gateway || {};
config.gateway.port = parseInt(process.env.PORT || '8080');
config.gateway.bind = 'lan';
config.gateway.trustedProxies = ['loopback', '127.0.0.1', '0.0.0.0/0'];
config.gateway.controlUi = config.gateway.controlUi || {};
config.gateway.controlUi.allowInsecureAuth = true;
config.gateway.controlUi.dangerouslyDisableDeviceAuth = true;

// Auth Profile Declaration (No keys here to avoid validation error)
config.auth = {
  profiles: {
    'google:default': {
      provider: 'google',
      mode: 'api_key'
    }
  }
};

// Gateway Token
if (process.env.OPENCLAW_GATEWAY_TOKEN) {
  config.gateway.auth = {
    mode: 'token',
    token: process.env.OPENCLAW_GATEWAY_TOKEN
  };
}

// Telegram
if (process.env.TELEGRAM_BOT_TOKEN) {
  config.channels = config.channels || {};
  config.channels.telegram = {
    enabled: true,
    botToken: process.env.TELEGRAM_BOT_TOKEN,
    dmPolicy: 'pairing'
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
console.log('✓ Agent auth profiles injected (Production Format)');
"
fi

echo "============================================================"
echo "OpenClaw Configuration Ready"
echo "============================================================"
echo "Gateway Port: ${PORT:-8080}"
echo "Config Ready at: ${CONFIG_FILE}"
echo "Directory Structure:"
ls -R "${CONFIG_DIR}"
echo "============================================================"

# Start the gateway
exec node dist/index.js gateway --allow-unconfigured --bind lan --port "${PORT:-8080}"
