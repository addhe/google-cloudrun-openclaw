#!/bin/bash
set -e

echo "🚀 DEBUG: Entry script started!"
echo "🚀 DEBUG: Environment variables:"
echo "🚀 DEBUG: SUPABASE_URL=${SUPABASE_URL}"
echo "🚀 DEBUG: SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}"

# Configuration
CONFIG_DIR="/home/node/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
AUTH_FILE="${CONFIG_DIR}/agents/main/agent/auth-profiles.json"

echo "🚀 OpenClaw Startup with Supabase Integration"
echo "=========================================="

# Create directories
mkdir -p "${CONFIG_DIR}/agents/main/agent"
mkdir -p "${CONFIG_DIR}/workspace"
mkdir -p "${CONFIG_DIR}/extensions"

# Install Supabase memory plugin into extensions directory if available
if [ -d "/app/extensions/supabase-memory" ]; then
    echo "✓ Installing Supabase memory plugin"
    rsync -a /app/extensions/supabase-memory "${CONFIG_DIR}/extensions/" >/dev/null 2>&1 || cp -r /app/extensions/supabase-memory "${CONFIG_DIR}/extensions/"
else
    echo "⚠️ Supabase memory plugin directory not found in image"
fi

# Create Agent SOUL
if [ ! -f "${CONFIG_DIR}/agents/main/agent/soul.md" ]; then
    cat > "${CONFIG_DIR}/agents/main/agent/soul.md" << 'SOUL'
# OpenClaw AI Assistant

You are a helpful AI assistant powered by OpenClaw framework.

## Capabilities
- Natural language conversation
- Task assistance
- Information retrieval
- Code generation
- Problem solving

## Guidelines
- Be helpful and concise
- Ask for clarification when needed
- Provide accurate information
- Respect user privacy

## Integration
- Connected to Supabase for persistent storage
- Using OpenAI for language processing
- Telegram integration for messaging
SOUL
    echo "✓ Agent SOUL created"
else
    echo "✓ Agent SOUL already exists, skipping creation"
fi

# Load configuration from Supabase if available
if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_SERVICE_ROLE_KEY" ]; then
    echo "📡 Loading configuration from Supabase..."
    
    node -e "
    const https = require('https');
    
    async function loadConfigFromSupabase() {
        try {
            const supabaseUrl = process.env.SUPABASE_URL;
            const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
            
            const response = await fetch(\`\${supabaseUrl}/rest/v1/openclaw_configs?key=eq.main_config&select=value\`, {
                headers: {
                    'apikey': supabaseKey,
                    'Authorization': \`Bearer \${supabaseKey}\`
                }
            });
            
            if (response.ok) {
                const data = await response.json();
                if (data && data.length > 0) {
                    const config = data[0].value;
                    const fs = require('fs');
                    
                    // Ensure gateway structure exists
                    config.gateway = config.gateway || {};
                    config.gateway.port = parseInt(process.env.PORT || '8080');
                    config.gateway.trustedProxies = config.gateway.trustedProxies || [
                        'loopback',
                        '127.0.0.1',
                        '0.0.0.0/0',
                        '172.17.0.1',
                        '169.254.169.126'
                    ];
                    config.gateway.controlUi = config.gateway.controlUi || {
                        allowInsecureAuth: true,
                        dangerouslyDisableDeviceAuth: true
                    };
                    config.gateway.auth = config.gateway.auth || { mode: 'token' };
                    
                    // DEBUG: Log gateway structure
                    console.log('✓ Gateway structure enforced:');
                    console.log('  - mode:', config.gateway.mode);
                    console.log('  - bind:', config.gateway.bind);
                    console.log('  - port:', config.gateway.port);
                    console.log('  - auth:', JSON.stringify(config.gateway.auth));

                    // Update dynamic values from environment
                    if (process.env.OPENCLAW_GATEWAY_TOKEN) {
                        config.gateway.auth.token = process.env.OPENCLAW_GATEWAY_TOKEN;
                    }
                    
                    if (process.env.PRIMARY_MODEL) {
                        config.agents.defaults.model.primary = process.env.PRIMARY_MODEL;
                    }
                    
                    if (process.env.TELEGRAM_BOT_TOKEN) {
                        config.channels = config.channels || {};
                        config.channels.telegram = config.channels.telegram || {};
                        config.channels.telegram.botToken = process.env.TELEGRAM_BOT_TOKEN;
                    }
                    
                    // Ensure plugins structure exists
                    config.plugins = config.plugins || {};
                    config.plugins.slots = config.plugins.slots || {};
                    config.plugins.entries = config.plugins.entries || {};
                    config.plugins.slots.memory = 'supabase-memory';
                    config.plugins.entries['supabase-memory'] = {
                        enabled: true,
                        config: {
                            supabaseUrl: process.env.SUPABASE_URL,
                            supabaseKey: '__SECRETS__'
                        }
                    };

                    fs.writeFileSync("${CONFIG_FILE}", JSON.stringify(config, null, 2));
                    console.log('✓ Configuration loaded from Supabase');
                    console.log('✓ Agent model: ' + config.agents.defaults.model.primary);
                    console.log('✓ Gateway mode: ' + config.gateway.mode);
                    console.log('✓ Gateway bind: ' + config.gateway.bind);
                    console.log('✓ Gateway port: ' + config.gateway.port);
                    console.log('✓ Config file written:');
                    console.log(fs.readFileSync('${CONFIG_FILE}', 'utf8'));
                    return;
                }
            }
        } catch (error) {
            console.log('❌ Failed to load from Supabase, using local config');
        }
        
        // Fallback to local config generation
        const fs = require('fs');
        let config = {
            meta: { lastTouchedVersion: '2026.2.3-1' },
            agents: {
                defaults: {
                    model: {
                        primary: process.env.PRIMARY_MODEL || 'openai/gpt-4o-mini'
                    },
                    workspace: "${CONFIG_DIR}/workspace"
                }
            },
            gateway: {
                mode: 'production',
                bind: '0.0.0.0',
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
                profiles: {}
            },
            plugins: {
                slots: {
                    memory: 'supabase-memory'
                },
                entries: {
                    'supabase-memory': {
                        enabled: true,
                        config: {
                            supabaseUrl: process.env.SUPABASE_URL,
                            supabaseKey: '__SECRETS__'
                        }
                    }
                }
            }
        };
        
        // Add Telegram channel if token is provided
        if (process.env.TELEGRAM_BOT_TOKEN) {
            config.channels = {
                telegram: {
                    enabled: true,
                    dmPolicy: 'open',
                    allowFrom: ['*'],
                    botToken: process.env.TELEGRAM_BOT_TOKEN,
                    groupAllowFrom: [
                        '-1001764332247',
                        '-5112221230',
                        '-370043467',
                        '-5035984652'
                    ],
                    groupPolicy: 'allowlist',
                    streamMode: 'partial'
                }
            };
            config.plugins.entries = {
                telegram: { enabled: true }
            };
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
        
        fs.writeFileSync("${CONFIG_FILE}", JSON.stringify(config, null, 2));
        console.log('✓ Configuration generated');
        console.log('✓ Agent model: ' + config.agents.defaults.model.primary);
    }
    
    loadConfigFromSupabase().catch(console.error);
"
else
    echo "⚠️ Supabase credentials not provided, using local configuration"
    
    # Original configuration logic here...
    node -e "
    const fs = require('fs');
    
    // Try to load existing config first, otherwise generate new one
    let config;
    if (fs.existsSync("${CONFIG_FILE}")) {
        config = JSON.parse(fs.readFileSync("${CONFIG_FILE}", 'utf8'));
        console.log('✓ Using existing config file');
    } else {
        config = {
            meta: { lastTouchedVersion: '2026.2.3-1' },
            agents: {
                defaults: {
                    model: {
                        primary: process.env.PRIMARY_MODEL || 'openai/gpt-4o-mini'
                    },
                    workspace: "${CONFIG_DIR}/workspace"
                }
            },
            gateway: {
                mode: 'production',
                bind: '0.0.0.0',
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
                profiles: {}
            },
            plugins: {
                slots: {
                    memory: 'supabase-memory'
                },
                entries: {
                    'supabase-memory': {
                        enabled: true,
                        config: {
                            supabaseUrl: process.env.SUPABASE_URL,
                            supabaseKey: '__SECRETS__'
                        }
                    }
                }
            }
        };
        console.log('✓ Generated new config');
    }
    
    // Add Telegram channel if token is provided
    if (process.env.TELEGRAM_BOT_TOKEN) {
        config.channels = {
            telegram: {
                enabled: true,
                dmPolicy: 'pairing',
                botToken: process.env.TELEGRAM_BOT_TOKEN,
                groupAllowFrom: [
                    '-1001764332247',
                    '-5112221230',
                    '-370043467',
                    '-5035984652'
                ],
                groupPolicy: 'allowlist',
                streamMode: 'partial'
            }
        };
        config.plugins.entries = {
            telegram: { enabled: true }
        };
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
    
    fs.writeFileSync("${CONFIG_FILE}", JSON.stringify(config, null, 2));
    console.log('✓ Config updated');
    console.log('✓ Agent model: ' + config.agents.defaults.model.primary);
"
fi

# Create auth profiles
if [ -n "$OLLAMA_BASE_URL" ] || [ -n "$GOOGLE_API_KEY" ] || [ -n "$OPENAI_API_KEY" ]; then
    node -e "
    const fs = require('fs');
    let auth = {
        version: 1,
        profiles: {}
    };
    
    // Add Ollama profile if OLLAMA_BASE_URL is provided
    if (process.env.OLLAMA_BASE_URL) {
        auth.profiles['ollama:default'] = {
            provider: 'ollama',
            mode: 'api_key',
            apiKeys: {
                'default': process.env.OLLAMA_API_KEY || 'ollama'
            },
            baseUrl: process.env.OLLAMA_BASE_URL
        };
        console.log('✓ Ollama profile added');
    }
    
    // Add OpenAI profile if OPENAI_API_KEY is provided
    if (process.env.OPENAI_API_KEY) {
        auth.profiles['openai:default'] = {
            provider: 'openai',
            mode: 'api_key',
            apiKey: process.env.OPENAI_API_KEY
        };
        console.log('✓ OpenAI profile added');
    }
    
    // Add Google profile if GOOGLE_API_KEY is provided
    if (process.env.GOOGLE_API_KEY) {
        auth.profiles['google:default'] = {
            provider: 'google',
            mode: 'api_key',
            key: process.env.GOOGLE_API_KEY
        };
        console.log('✓ Google profile added');
    }
    
    fs.writeFileSync('${AUTH_FILE}', JSON.stringify(auth, null, 2));
    console.log('✓ Auth profiles injected');
    console.log('✓ Auth file created at: ${AUTH_FILE}');
"
else
    echo "❌ WARNING: No OLLAMA_BASE_URL, GOOGLE_API_KEY, or OPENAI_API_KEY found!"
    echo "   Please set at least one AI provider environment variable."
fi

echo "============================================================"
echo "OpenClaw Ready"
echo "DEBUG: LOG_LEVEL=${LOG_LEVEL:-info}"
echo "============================================================"

# Start the gateway
exec node --max-old-space-size=1536 dist/index.js gateway --allow-unconfigured --bind 0.0.0.0 --port "${PORT:-8080}"
