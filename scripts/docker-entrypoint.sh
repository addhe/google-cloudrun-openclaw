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

# Note: We rely on /app/extensions for plugins to avoid duplication

# Pre-approve devices hack
echo '{"silent": true}' > "${CONFIG_DIR}/devices/pending.json"

# Create a default SOUL for the main agent
echo "✓ Preparing Agent SOUL..."
cat > "${CONFIG_DIR}/agents/main/SOUL.md" <<EOF
# Main Agent
You are a helpful AI assistant.
Respond concisely.
EOF

# 1. Update Main openclaw.json
node -e "
const fs = require('fs');
let config = {
  meta: { lastTouchedVersion: '2026.2.3-1' },
  agents: {
    defaults: {
      model: {
        primary: process.env.PRIMARY_MODEL || 'google/gemini-3-flash-preview'
      },
      workspace: '${CONFIG_DIR}/workspace'
    }
  },
  gateway: {
    mode: 'local',
    bind: 'lan',
    port: parseInt(process.env.PORT || '8080'),
    trustedProxies: ['loopback', '127.0.0.1', '0.0.0.0/0'],
    controlUi: {
      allowInsecureAuth: true,
      dangerouslyDisableDeviceAuth: true
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

if (process.env.OPENCLAW_GATEWAY_TOKEN) {
  config.gateway.auth = {
    mode: 'token',
    token: process.env.OPENCLAW_GATEWAY_TOKEN
  };
}

fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
console.log('✓ Config generated');
"

# 2. Update Agent auth-profiles.json
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
  }
};
fs.writeFileSync('${CONFIG_DIR}/agents/main/agent/auth-profiles.json', JSON.stringify(auth, null, 2));
console.log('✓ Auth profiles injected (Key Length: ' + process.env.GOOGLE_API_KEY.length + ')');
"
fi

echo "============================================================"
echo "OpenClaw Ready"
echo "DEBUG: Log level set to trace"
echo "============================================================"

# Start the gateway with debug logging
exec node dist/index.js gateway --allow-unconfigured --bind lan --port "${PORT:-8080}" --log-level=trace
