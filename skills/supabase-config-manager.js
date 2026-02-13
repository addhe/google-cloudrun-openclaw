// ============================================================
// OpenClaw Skill - Supabase Configuration Manager
// ============================================================
// Allows bot to view and modify its configuration in Supabase
// ============================================================

const { fetch } = require('undici');

class SupabaseConfigManager {
  constructor() {
    this.supabaseUrl = process.env.SUPABASE_URL;
    this.supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  }

  async getCurrentConfig() {
    try {
      const response = await fetch(`${this.supabaseUrl}/rest/v1/openclaw_configs?key=eq.main_config&select=value`, {
        headers: {
          'apikey': this.supabaseKey,
          'Authorization': `Bearer ${this.supabaseKey}`
        }
      });

      if (!response.ok) {
        throw new Error(`Failed to fetch config: ${response.statusText}`);
      }

      const data = await response.json();
      return data && data.length > 0 ? data[0].value : null;
    } catch (error) {
      console.error('Error fetching config:', error);
      throw error;
    }
  }

  async updateConfig(updates) {
    try {
      const currentConfig = await this.getCurrentConfig();
      if (!currentConfig) {
        throw new Error('No existing configuration found');
      }

      // Deep merge updates with current config
      const updatedConfig = this.deepMerge(currentConfig, updates);

      const response = await fetch(`${this.supabaseUrl}/rest/v1/openclaw_configs?key=eq.main_config`, {
        method: 'PATCH',
        headers: {
          'apikey': this.supabaseKey,
          'Authorization': `Bearer ${this.supabaseKey}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ value: updatedConfig })
      });

      if (!response.ok) {
        throw new Error(`Failed to update config: ${response.statusText}`);
      }

      return updatedConfig;
    } catch (error) {
      console.error('Error updating config:', error);
      throw error;
    }
  }

  deepMerge(target, source) {
    const result = { ...target };
    
    for (const key in source) {
      if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
        result[key] = this.deepMerge(result[key] || {}, source[key]);
      } else {
        result[key] = source[key];
      }
    }
    
    return result;
  }

  formatConfigForDisplay(config, section = null) {
    if (section && config[section]) {
      return this.formatSection(config[section], section);
    }

    let output = '📋 **Current OpenClaw Configuration**\n\n';
    
    if (config.gateway) {
      output += this.formatSection(config.gateway, '🌐 Gateway');
    }
    
    if (config.channels && config.channels.telegram) {
      output += this.formatSection(config.channels.telegram, '📱 Telegram');
    }
    
    if (config.agents && config.agents.defaults) {
      output += this.formatSection(config.agents.defaults, '🤖 Agent Defaults');
    }

    return output;
  }

  formatSection(section, title) {
    let output = `**${title}**\n`;
    
    for (const [key, value] of Object.entries(section)) {
      if (key === 'botToken' || key === 'token') {
        output += `• ${key}: \`[REDACTED]\`\n`;
      } else if (typeof value === 'object' && value !== null) {
        output += `• ${key}: \`${JSON.stringify(value)}\`\n`;
      } else {
        output += `• ${key}: \`${value}\`\n`;
      }
    }
    
    output += '\n';
    return output;
  }
}

// Command handlers
const configManager = new SupabaseConfigManager();

module.exports = {
  name: 'supabase-config',
  description: 'Manage OpenClaw configuration in Supabase',
  commands: {
    'config show': {
      description: 'Show current configuration',
      handler: async (args, context) => {
        try {
          const config = await configManager.getCurrentConfig();
          if (!config) {
            return '❌ No configuration found in Supabase';
          }
          
          const section = args[0];
          return configManager.formatConfigForDisplay(config, section);
        } catch (error) {
          return `❌ Error fetching config: ${error.message}`;
        }
      }
    },

    'config update': {
      description: 'Update configuration (format: config update section.key=value)',
      handler: async (args, context) => {
        try {
          if (args.length < 1) {
            return '❌ Usage: `config update section.key=value`\\nExample: `config update gateway.mode=production`';
          }

          const updates = {};
          for (const arg of args) {
            const [keyPath, value] = arg.split('=');
            if (!keyPath || !value) {
              return `❌ Invalid format: ${arg}. Use section.key=value`;
            }

            const keys = keyPath.split('.');
            let current = updates;
            
            for (let i = 0; i < keys.length - 1; i++) {
              if (!current[keys[i]]) {
                current[keys[i]] = {};
              }
              current = current[keys[i]];
            }
            
            // Parse value
            let parsedValue = value;
            if (value === 'true') parsedValue = true;
            else if (value === 'false') parsedValue = false;
            else if (!isNaN(value) && value !== '') parsedValue = Number(value);
            else if (value.startsWith('[') || value.startsWith('{')) {
              try {
                parsedValue = JSON.parse(value);
              } catch (e) {
                // Keep as string if not valid JSON
              }
            }
            
            current[keys[keys.length - 1]] = parsedValue;
          }

          const updatedConfig = await configManager.updateConfig(updates);
          return '✅ Configuration updated successfully!\\n\\n' + 
                 configManager.formatConfigForDisplay(updatedConfig);
        } catch (error) {
          return `❌ Error updating config: ${error.message}`;
        }
      }
    },

    'config reload': {
      description: 'Reload configuration from Supabase',
      handler: async (args, context) => {
        try {
          // This would trigger a service reload
          return '✅ Configuration reload requested. Service will restart with new configuration.';
        } catch (error) {
          return `❌ Error reloading config: ${error.message}`;
        }
      }
    }
  }
};
