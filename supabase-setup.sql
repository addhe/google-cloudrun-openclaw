-- OpenClaw Configuration Storage
-- Create tables for persistent configuration storage

-- OpenClaw configurations table
CREATE TABLE IF NOT EXISTS openclaw_configs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  key TEXT UNIQUE NOT NULL,
  value JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- OpenClaw sessions table  
CREATE TABLE IF NOT EXISTS openclaw_sessions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id TEXT UNIQUE NOT NULL,
  user_id TEXT,
  agent_id TEXT DEFAULT 'main',
  data JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- OpenClaw memories table
CREATE TABLE IF NOT EXISTS openclaw_memories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  agent_id TEXT DEFAULT 'main',
  user_id TEXT,
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- OpenClaw agent states table
CREATE TABLE IF NOT EXISTS openclaw_agent_states (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  agent_id TEXT UNIQUE NOT NULL,
  state JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for better performance
CREATE INDEX IF NOT EXISTS idx_openclaw_configs_key ON openclaw_configs(key);
CREATE INDEX IF NOT EXISTS idx_openclaw_sessions_session_id ON openclaw_sessions(session_id);
CREATE INDEX IF NOT EXISTS idx_openclaw_sessions_user_id ON openclaw_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_openclaw_memories_agent_id ON openclaw_memories(agent_id);
CREATE INDEX IF NOT EXISTS idx_openclaw_memories_user_id ON openclaw_memories(user_id);
CREATE INDEX IF NOT EXISTS idx_openclaw_agent_states_agent_id ON openclaw_agent_states(agent_id);

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply triggers
CREATE TRIGGER update_openclaw_configs_updated_at BEFORE UPDATE ON openclaw_configs FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_openclaw_sessions_updated_at BEFORE UPDATE ON openclaw_sessions FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_openclaw_memories_updated_at BEFORE UPDATE ON openclaw_memories FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_openclaw_agent_states_updated_at BEFORE UPDATE ON openclaw_agent_states FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert default configuration
INSERT INTO openclaw_configs (key, value) VALUES 
('main_config', '{
  "meta": {
    "lastTouchedVersion": "2026.2.3-1",
    "lastTouchedAt": "2026-02-12T00:00:00.000Z"
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "openai/gpt-4o-mini"
      },
      "workspace": "/home/node/.openclaw/workspace",
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",
      "groupAllowFrom": [
        "-1001764332247",
        "-5112221230", 
        "-370043467",
        "-5035984652"
      ],
      "groupPolicy": "allowlist",
      "streamMode": "partial"
    }
  },
  "gateway": {
    "port": 8080,
    "mode": "local",
    "bind": "lan",
    "auth": {
      "mode": "token"
    },
    "trustedProxies": [
      "loopback",
      "127.0.0.1",
      "0.0.0.0/0",
      "172.17.0.1"
    ],
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true
    }
  },
  "plugins": {
    "entries": {
      "telegram": {
        "enabled": true
      }
    }
  }
}') ON CONFLICT (key) DO NOTHING;

-- Enable Row Level Security (RLS)
ALTER TABLE openclaw_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE openclaw_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE openclaw_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE openclaw_agent_states ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Allow all operations on configs" ON openclaw_configs FOR ALL USING (true);
CREATE POLICY "Allow all operations on sessions" ON openclaw_sessions FOR ALL USING (true);
CREATE POLICY "Allow all operations on memories" ON openclaw_memories FOR ALL USING (true);
CREATE POLICY "Allow all operations on agent states" ON openclaw_agent_states FOR ALL USING (true);
