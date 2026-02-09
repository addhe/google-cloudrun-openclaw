#!/bin/sh
# ============================================================
# OpenClaw Cloud Run - Entrypoint Script
# ============================================================
# Injects secrets from environment variables into openclaw.json
# before starting the gateway.
# ============================================================

set -e

CONFIG_DIR="/home/node/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"

# EXTREME HACK: Ensure we have GEMINI_API_KEY if GOOGLE_API_KEY is present
if [ -n "$GOOGLE_API_KEY" ] && [ -z "$GEMINI_API_KEY" ]; then
  export GEMINI_API_KEY="$GOOGLE_API_KEY"
fi

# Create required directories
mkdir -p "${CONFIG_DIR}/identity"
mkdir -p "${CONFIG_DIR}/agents"
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

# Multi-stage configuration injection
node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));

// 1. Gateway Settings - Listen on all interfaces for Cloud Run
config.gateway = config.gateway || {};
config.gateway.port = parseInt(process.env.PORT || '8080');
config.gateway.bind = 'lan';
config.gateway.trustedProxies = ['loopback', '127.0.0.1', '0.0.0.0/0'];
config.gateway.controlUi = config.gateway.controlUi || {};
config.gateway.controlUi.allowInsecureAuth = true;
config.gateway.controlUi.dangerouslyDisableDeviceAuth = true;

// 2. Auth Profiles (Main Config) - Use 'token' instead of 'apiKey' or 'key'
config.auth = config.auth || {};
config.auth.profiles = config.auth.profiles || {};
if (process.env.GOOGLE_API_KEY) {
  const googleProfile = {
    provider: 'google',
    mode: 'api_key',
    token: process.env.GOOGLE_API_KEY
  };
  config.auth.profiles['google:default'] = googleProfile;
  config.auth.profiles['google'] = googleProfile;
}

// 3. Environment variables block - fallback for some providers
config.env = config.env || {};
if (process.env.GOOGLE_API_KEY) config.env.GOOGLE_API_KEY = process.env.GOOGLE_API_KEY;
if (process.env.GEMINI_API_KEY) config.env.GEMINI_API_KEY = process.env.GEMINI_API_KEY;

// 4. Gateway Token
if (process.env.OPENCLAW_GATEWAY_TOKEN) {
  config.gateway.auth = config.gateway.auth || {};
  config.gateway.auth.mode = 'token';
  config.gateway.auth.token = process.env.OPENCLAW_GATEWAY_TOKEN;
}

// 5. Telegram
if (process.env.TELEGRAM_BOT_TOKEN) {
  config.channels = config.channels || {};
  config.channels.telegram = {
    enabled: true,
    botToken: process.env.TELEGRAM_BOT_TOKEN
  };
}

fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
console.log('✓ Main configuration updated');
"

# Agent-specific Auth Profiles Injection - Also use 'token'
if [ -n "$GOOGLE_API_KEY" ]; then
  AGENT_AUTH_DIR="${CONFIG_DIR}/agents/main/agent"
  mkdir -p "$AGENT_AUTH_DIR"
  node -e "
const fs = require('fs');
const auth = {
  profiles: {
    'google:default': {
      provider: 'google',
      mode: 'api_key',
      token: process.env.GOOGLE_API_KEY
    },
    'google': {
      provider: 'google',
      mode: 'api_key',
      token: process.env.GOOGLE_API_KEY
    }
  }
};
fs.writeFileSync('${AGENT_AUTH_DIR}/auth-profiles.json', JSON.stringify(auth, null, 2));
console.log('✓ Agent auth profiles injected');
"
fi

echo "============================================================"
echo "OpenClaw Configuration Ready"
echo "============================================================"
echo "Gateway Port: ${PORT}"
echo "Config (Redacted):"
node -e "
const fs = require('fs');
const c = JSON.parse(fs.readFileSync('${CONFIG_FILE}'));
if(c.gateway && c.gateway.auth && c.gateway.auth.token) c.gateway.auth.token = '***';
if(c.auth && c.auth.profiles) {
  Object.values(c.auth.profiles).forEach(p => { if(p.token) p.token = '***'; if(p.apiKey) p.apiKey = '***'; if(p.key) p.key = '***' });
}
if(c.env) {
  if(c.env.GOOGLE_API_KEY) c.env.GOOGLE_API_KEY = '***';
  if(c.env.GEMINI_API_KEY) c.env.GEMINI_API_KEY = '***';
}
console.log(JSON.stringify(c, null, 2));
" || echo "[Redaction failed, config hidden]"
echo "============================================================"

# Start the gateway
exec node dist/index.js gateway --allow-unconfigured --bind lan --port "${PORT}"
