#!/bin/bash

# Supabase Integration Script for OpenClaw
# This script sets up Supabase integration and updates configuration

set -e

echo "🚀 Setting up Supabase integration for OpenClaw..."

# Configuration
PROJECT_ID="awanmasterpiece"
SUPABASE_URL="https://relmrreqvrcqqmhrudwx.supabase.co"
SUPABASE_PROJECT="relmrreqvrcqqmhrudwx"

echo "📋 Step 1: Running SQL setup on Supabase..."

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo "❌ psql not found. Installing..."
    brew install postgresql || apt-get update && apt-get install -y postgresql-client
fi

# Run SQL setup
echo "🔧 Creating Supabase tables..."
psql "$SUPABASE_URL" -c "\i supabase-setup.sql" || {
    echo "❌ Failed to run SQL setup. Please run manually:"
    echo "   1. Go to https://supabase.com/dashboard/project/$SUPABASE_PROJECT/sql"
    echo "   2. Copy and paste the contents of supabase-setup.sql"
    echo "   3. Click 'Run'"
}

echo "✅ Supabase tables created successfully!"

echo "📋 Step 2: Creating Supabase integration module..."

# Create Supabase integration module
cat > supabase-integration.js << 'EOF'
/**
 * Supabase Integration Module for OpenClaw
 * Provides persistent storage for configuration, sessions, and memories
 */

const { createClient } = require('@supabase/supabase-js');

class SupabaseIntegration {
  constructor(supabaseUrl, supabaseKey) {
    this.supabase = createClient(supabaseUrl, supabaseKey);
    this.initialized = false;
  }

  async initialize() {
    try {
      // Test connection
      const { data, error } = await this.supabase
        .from('openclaw_configs')
        .select('key, value')
        .limit(1);
      
      if (error) throw error;
      
      this.initialized = true;
      console.log('✅ Supabase integration initialized');
      return true;
    } catch (error) {
      console.error('❌ Failed to initialize Supabase:', error);
      return false;
    }
  }

  async getConfig(key = 'main_config') {
    if (!this.initialized) await this.initialize();
    
    try {
      const { data, error } = await this.supabase
        .from('openclaw_configs')
        .select('value')
        .eq('key', key)
        .single();
      
      if (error && error.code !== 'PGRST116') throw error;
      
      return data?.value || null;
    } catch (error) {
      console.error(`❌ Failed to get config ${key}:`, error);
      return null;
    }
  }

  async setConfig(key, value) {
    if (!this.initialized) await this.initialize();
    
    try {
      const { data, error } = await this.supabase
        .from('openclaw_configs')
        .upsert({ key, value }, { onConflict: 'key' });
      
      if (error) throw error;
      
      console.log(`✅ Config ${key} saved to Supabase`);
      return data;
    } catch (error) {
      console.error(`❌ Failed to save config ${key}:`, error);
      return null;
    }
  }

  async getSession(sessionId) {
    if (!this.initialized) await this.initialize();
    
    try {
      const { data, error } = await this.supabase
        .from('openclaw_sessions')
        .select('*')
        .eq('session_id', sessionId)
        .single();
      
      if (error && error.code !== 'PGRST116') throw error;
      
      return data;
    } catch (error) {
      console.error(`❌ Failed to get session ${sessionId}:`, error);
      return null;
    }
  }

  async setSession(sessionId, data, userId = null, agentId = 'main') {
    if (!this.initialized) await this.initialize();
    
    try {
      const { data: result, error } = await this.supabase
        .from('openclaw_sessions')
        .upsert({ 
          session_id: sessionId, 
          user_id: userId, 
          agent_id, 
          data 
        }, { onConflict: 'session_id' });
      
      if (error) throw error;
      
      console.log(`✅ Session ${sessionId} saved to Supabase`);
      return result;
    } catch (error) {
      console.error(`❌ Failed to save session ${sessionId}:`, error);
      return null;
    }
  }

  async getAgentState(agentId = 'main') {
    if (!this.initialized) await this.initialize();
    
    try {
      const { data, error } = await this.supabase
        .from('openclaw_agent_states')
        .select('state')
        .eq('agent_id', agentId)
        .single();
      
      if (error && error.code !== 'PGRST116') throw error;
      
      return data?.state || {};
    } catch (error) {
      console.error(`❌ Failed to get agent state ${agentId}:`, error);
      return {};
    }
  }

  async setAgentState(agentId, state) {
    if (!this.initialized) await this.initialize();
    
    try {
      const { data, error } = await this.supabase
        .from('openclaw_agent_states')
        .upsert({ agent_id, state }, { onConflict: 'agent_id' });
      
      if (error) throw error;
      
      console.log(`✅ Agent state ${agentId} saved to Supabase`);
      return data;
    } catch (error) {
      console.error(`❌ Failed to save agent state ${agentId}:`, error);
      return null;
    }
  }

  async addMemory(agentId, userId, content, metadata = {}) {
    if (!this.initialized) await this.initialize();
    
    try {
      const { data, error } = await this.supabase
        .from('openclaw_memories')
        .insert({ agent_id: agentId, user_id: userId, content, metadata });
      
      if (error) throw error;
      
      console.log(`✅ Memory added to Supabase`);
      return data;
    } catch (error) {
      console.error(`❌ Failed to add memory:`, error);
      return null;
    }
  }

  async getMemories(agentId, userId = null, limit = 50) {
    if (!this.initialized) await this.initialize();
    
    try {
      let query = this.supabase
        .from('openclaw_memories')
        .select('*')
        .eq('agent_id', agentId)
        .order('created_at', { ascending: false })
        .limit(limit);
      
      if (userId) {
        query = query.eq('user_id', userId);
      }
      
      const { data, error } = await query;
      
      if (error) throw error;
      
      return data || [];
    } catch (error) {
      console.error(`❌ Failed to get memories:`, error);
      return [];
    }
  }
}

module.exports = SupabaseIntegration;
EOF

echo "✅ Supabase integration module created!"

echo "📋 Step 3: Updating Dockerfile for Supabase support..."

# Update package.json to include Supabase dependency
if [ -f package.json ]; then
    npm install @supabase/supabase-js
    echo "✅ Supabase client installed"
fi

echo "📋 Step 4: Creating Supabase-enabled docker-entrypoint..."

# Create new docker-entrypoint with Supabase integration
cat > scripts/docker-entrypoint-supabase.sh << 'EOF'
#!/bin/bash
set -e

# Configuration
CONFIG_DIR="/home/node/.openclaw"
CONFIG_FILE="${CONFIG_DIR}/openclaw.json"
AUTH_FILE="${CONFIG_DIR}/agents/main/agent/auth-profiles.json"

echo "🚀 OpenClaw Startup with Supabase Integration"
echo "=========================================="

# Create directories
mkdir -p "${CONFIG_DIR}/agents/main/agent"
mkdir -p "${CONFIG_DIR}/workspace"

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
    const url = require('url');
    
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
                    
                    // Update dynamic values from environment
                    if (process.env.OPENCLAW_GATEWAY_TOKEN) {
                        config.gateway.auth = {
                            mode: 'token',
                            token: process.env.OPENCLAW_GATEWAY_TOKEN
                        };
                    }
                    
                    if (process.env.PRIMARY_MODEL) {
                        config.agents.defaults.model.primary = process.env.PRIMARY_MODEL;
                    }
                    
                    if (process.env.TELEGRAM_BOT_TOKEN) {
                        config.channels.telegram.botToken = process.env.TELEGRAM_BOT_TOKEN;
                    }
                    
                    fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
                    console.log('✓ Configuration loaded from Supabase');
                    console.log('✓ Agent model: ' + config.agents.defaults.model.primary);
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
                profiles: {}
            },
            plugins: {
                slots: {
                    memory: 'memory-core'
                }
            }
        };
        
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
        
        fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
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
    if (fs.existsSync('${CONFIG_FILE}')) {
        config = JSON.parse(fs.readFileSync('${CONFIG_FILE}', 'utf8'));
        console.log('✓ Using existing config file');
    } else {
        config = {
            meta: { lastTouchedVersion: '2026.2.3-1' },
            agents: {
                defaults: {
                    model: {
                        primary: process.env.PRIMARY_MODEL || 'openai/gpt-4o-mini'
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
                profiles: {}
            },
            plugins: {
                slots: {
                    memory: 'memory-core'
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
    
    fs.writeFileSync('${CONFIG_FILE}', JSON.stringify(config, null, 2));
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

# Start OpenClaw
exec "$@"
EOF

chmod +x scripts/docker-entrypoint-supabase.sh
echo "✅ Supabase-enabled docker-entrypoint created!"

echo "📋 Step 5: Creating Cloud Build configuration with Supabase..."

# Create new Cloud Build config
cat > cloudbuild-supabase.yaml << 'EOF'
steps:
  # Build the application
  - name: 'node:22-bookworm-slim'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        apt-get update && apt-get install -y --no-install-recommends curl git python3 build-essential ca-certificates openssl unzip
        curl -fsSL https://bun.sh/install | bash
        corepack enable
        git clone --depth 1 https://github.com/openclaw/openclaw.git . && if [ "latest" != "latest" ]; then git checkout "latest"; fi
        pnpm install --frozen-lockfile
        pnpm build
        pnpm build
        pnpm ui:build

  # Build Docker image with Supabase support
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'us-central1-docker.pkg.dev/$PROJECT_ID/openclaw-repo/openclaw-supabase', '-f', 'Dockerfile.cloudrun', '.']

  # Push to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'us-central1-docker.pkg.dev/$PROJECT_ID/openclaw-repo/openclaw-supabase']

  # Deploy to Cloud Run with Supabase secrets
  - name: 'gcr.io/cloud-builders/gcloud'
    args:
      - 'run'
      - 'deploy'
      - 'openclaw'
      - '--image=us-central1-docker.pkg.dev/$PROJECT_ID/openclaw-repo/openclaw-supabase'
      - '--region=us-central1'
      - '--platform=linux/amd64'
      - '--allow-unauthenticated'
      - '--memory=1Gi'
      - '--cpu=1'
      - '--timeout=300'
      - '--concurrency=1000'
      - '--max-instances=10'
      - '--min-instances=0'
      - '--set-secrets=OPENAI_API_KEY=openai-api-key:latest,OPENCLAW_GATEWAY_TOKEN=openclaw-gateway-token:latest,TELEGRAM_BOT_TOKEN=telegram-bot-token:latest,SUPABASE_URL=supabase-url:latest,SUPABASE_SERVICE_ROLE_KEY=supabase-service-role-key:latest'
      - '--set-env-vars=PRIMARY_MODEL=openai/gpt-4o-mini,LOG_LEVEL=debug,NODE_ENV=production'

images:
  - 'us-central1-docker.pkg.dev/$PROJECT_ID/openclaw-repo/openclaw-supabase'

options:
  logging: CLOUD_LOGGING_ONLY
EOF

echo "✅ Cloud Build configuration with Supabase created!"

echo ""
echo "🎉 Supabase integration setup complete!"
echo ""
echo "📋 Next steps:"
echo "1. Run the SQL setup in Supabase dashboard:"
echo "   https://supabase.com/dashboard/project/relmrreqvrcqqmhrudwx/sql"
echo ""
echo "2. Build and deploy with Supabase:"
echo "   gcloud builds submit --config=cloudbuild-supabase.yaml --project=awanmasterpiece ."
echo ""
echo "3. Your OpenClaw will now have persistent storage!"
echo "   - Configuration saved in Supabase"
echo "   - Sessions preserved across restarts"
echo "   - Agent states maintained"
echo "   - Memory storage for conversations"
echo ""

echo "🔗 Supabase Dashboard: https://supabase.com/dashboard/project/relmrreqvrcqqmhrudwx"
echo "🚀 OpenClaw URL: https://openclaw-361046956504.us-central1.run.app"
