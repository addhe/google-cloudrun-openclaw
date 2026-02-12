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

echo "✓ Directories created"
echo "✓ Agent directory: ${CONFIG_DIR}/agents/main/agent"

# Note: We rely on /app/extensions for plugins to avoid duplication

# Pre-approve devices hack
echo '{"silent": true}' > "${CONFIG_DIR}/devices/pending.json"

# Create a default SOUL for the main agent
if [ ! -f "${CONFIG_DIR}/agents/main/SOUL.md" ]; then
  echo "✓ Preparing Agent SOUL..."
  cat > "${CONFIG_DIR}/agents/main/SOUL.md" <<EOF
# Main Agent
You are a helpful AI assistant.
Respond concisely.
EOF
else
  echo "✓ Agent SOUL already exists, skipping creation"
fi

# 1. Update Main openclaw.json
node -e "
const fs = require('fs');

// Try to load existing config first, otherwise generate new one
let config;
if (fs.existsSync('${CONFIG_FILE}')) {
  config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));
  console.log('✓ Using existing config file');
} else {
  config = {
    meta: { lastTouchedVersion: '2026.2.3-1' },
    agents: {
      defaults: {
        model: {
          primary: process.env.PRIMARY_MODEL || 'glm-4.7:cloud'
        },
        workspace: '${CONFIG_DIR}/workspace'
      }
    },
    gateway: {
      mode: 'local',
      bind: 'lan',
      port: parseInt(process.env.PORT || '8080'),
      trustedProxies: ['loopback', '127.0.0.1', '0.0.0.0/0', '172.17.0.1'],
      controlUi: {
        allowInsecureAuth: true,
        dangerouslyDisableDeviceAuth: true
      },
      auth: {
        mode: 'token'
      }
    },
    auth: {
      profiles: {
        'google:default': {
          provider: 'google',
          mode: 'api_key'
        }
      }
    },
    plugins: {
      slots: {
        memory: 'memory-core'
      }
    }
  };
  console.log('✓ Generated new config');
}

// Update dynamic values
if (process.env.OPENCLAW_GATEWAY_TOKEN) {
  config.gateway.auth = {
    mode: 'token',
    token: process.env.OPENCLAW_GATEWAY_TOKEN
  };
}

if (process.env.PRIMARY_MODEL) {
  config.agents.defaults.model.primary = process.env.PRIMARY_MODEL;
}

fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
console.log('✓ Config updated');
console.log('✓ Config file at: ${CONFIG_FILE}');
console.log('✓ Agent model: ' + config.agents.defaults.model.primary);
"

# 2. Update Agent auth-profiles.json
if [ -n "$OLLAMA_BASE_URL" ] || [ -n "$GOOGLE_API_KEY" ] || [ -n "$OPENAI_API_KEY" ]; then
  node -e "
const fs = require('fs');
let auth = {
  version: 1,
  profiles: {},
  lastGood: {}
};

// Add Ollama profile if OLLAMA_BASE_URL is provided
if (process.env.OLLAMA_BASE_URL) {
  auth.profiles['ollama:default'] = {
    type: 'openai_compatible',
    provider: 'ollama',
    baseUrl: process.env.OLLAMA_BASE_URL
  };
  auth.lastGood.ollama = 'ollama:default';
}

// Add OpenAI profile if OPENAI_API_KEY is provided
if (process.env.OPENAI_API_KEY) {
  auth.profiles['openai:default'] = {
    type: 'openai_compatible',
    provider: 'openai',
    apiKey: process.env.OPENAI_API_KEY,
    baseUrl: process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1'
  };
  auth.lastGood.openai = 'openai:default';
}
if (process.env.GOOGLE_API_KEY) {
  auth.profiles['google:default'] = {
    type: 'api_key',
    provider: 'google',
    key: process.env.GOOGLE_API_KEY
  };
  auth.lastGood.google = 'google:default';
}

const authPath = '${CONFIG_DIR}/agents/main/agent/auth-profiles.json';
if (!fs.existsSync(authPath)) {
  fs.writeFileSync(authPath, JSON.stringify(auth, null, 2));
  console.log('✓ Auth profiles injected');
  console.log('✓ Auth file created at: ' + authPath);
} else {
  console.log('✓ Auth file already exists, skipping injection');
}
"
else
  echo "❌ WARNING: No OLLAMA_BASE_URL, GOOGLE_API_KEY, or OPENAI_API_KEY found!"
fi

echo "============================================================"
echo "OpenClaw Ready"
echo "DEBUG: LOG_LEVEL=${LOG_LEVEL:-info}"
echo "============================================================"

# Start the gateway
exec node dist/index.js gateway --allow-unconfigured --bind lan --port "${PORT:-8080}"
