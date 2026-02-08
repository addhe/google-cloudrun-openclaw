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

# Create config directory
mkdir -p "${CONFIG_DIR}"

# Copy default config if exists
if [ -f "/app/config/openclaw.json" ]; then
    cp /app/config/openclaw.json "${CONFIG_FILE}"
fi

# Inject gateway token if provided
if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    # Use node to update JSON (safer than sed for JSON manipulation)
    node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));
config.gateway = config.gateway || {};
config.gateway.auth = config.gateway.auth || {};
config.gateway.auth.token = process.env.OPENCLAW_GATEWAY_TOKEN;
fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
console.log('✓ Gateway token configured');
"
fi

# Inject Telegram bot token if provided
if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
    node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));
config.channels = config.channels || {};
config.channels.telegram = config.channels.telegram || {};
config.channels.telegram.enabled = true;
config.channels.telegram.botToken = process.env.TELEGRAM_BOT_TOKEN;
fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
console.log('✓ Telegram bot configured');
"
fi

# Update port and bind from environment
PORT="${PORT:-8080}"
node -e "
const fs = require('fs');
const config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));
config.gateway = config.gateway || {};
config.gateway.port = parseInt(process.env.PORT || '8080');
config.gateway.bind = 'lan';
fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
console.log('✓ Gateway port set to ' + config.gateway.port);
console.log('✓ Gateway bind set to lan');
"

echo "============================================================"
echo "OpenClaw Configuration Ready"
echo "============================================================"
echo "Gateway Port: ${PORT}"
echo "============================================================"

# Start the gateway
exec node dist/index.js gateway --allow-unconfigured --bind lan --port "${PORT}"
