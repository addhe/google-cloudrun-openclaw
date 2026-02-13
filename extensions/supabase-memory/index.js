const DEFAULT_AGENT_ID = 'main';
const MAX_SEARCH_LIMIT = 20;

function resolveConfig(ctx = {}) {
  const cfg = (ctx.config && ctx.config.plugins && ctx.config.plugins.entries && ctx.config.plugins.entries['supabase-memory']) || {};
  return {
    supabaseUrl: process.env.SUPABASE_URL || cfg.supabaseUrl,
    supabaseKey: process.env.SUPABASE_SERVICE_ROLE_KEY || cfg.supabaseKey,
  };
}

async function supabaseRequest({ url, method = 'GET', headers = {}, body }) {
  const response = await fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...headers,
    },
    body,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Supabase request failed (${response.status}): ${text}`);
  }

  if (response.status === 204) return null;
  return response.json();
}

function buildClient({ supabaseUrl, supabaseKey }) {
  if (!supabaseUrl || !supabaseKey) {
    throw new Error('Supabase URL or Service Role Key is missing for supabase-memory plugin');
  }

  const baseHeaders = {
    apikey: supabaseKey,
    Authorization: `Bearer ${supabaseKey}`,
  };

  const tableUrl = `${supabaseUrl}/rest/v1/openclaw_memories`;

  return {
    add: async ({ agentId, userId, content, metadata }) => {
      if (!content) return;
      const payload = {
        agent_id: agentId || DEFAULT_AGENT_ID,
        user_id: userId || metadata?.userId || 'unknown',
        content,
        metadata: metadata || {},
      };

      await supabaseRequest({
        url: tableUrl,
        method: 'POST',
        headers: baseHeaders,
        body: JSON.stringify(payload),
      });
    },

    search: async ({ query, agentId, limit }) => {
      const cappedLimit = Math.min(limit || 10, MAX_SEARCH_LIMIT);
      const params = new URLSearchParams({
        select: 'id,agent_id,user_id,content,metadata,created_at',
        order: 'created_at.desc',
        limit: String(cappedLimit),
      });
      params.append('agent_id', `eq.${agentId || DEFAULT_AGENT_ID}`);
      if (query) {
        params.append('content', `ilike.*${encodeURIComponent(query)}*`);
      }

      const data = await supabaseRequest({
        url: `${tableUrl}?${params.toString()}`,
        headers: baseHeaders,
      });

      return Array.isArray(data)
        ? data.map((row) => ({
            id: row.id,
            agentId: row.agent_id,
            userId: row.user_id,
            content: row.content,
            metadata: row.metadata,
            createdAt: row.created_at,
          }))
        : [];
    },

    get: async (id) => {
      if (!id) return null;
      const params = new URLSearchParams({
        select: 'id,agent_id,user_id,content,metadata,created_at',
        limit: '1',
      });
      params.append('id', `eq.${id}`);

      const data = await supabaseRequest({
        url: `${tableUrl}?${params.toString()}`,
        headers: baseHeaders,
      });

      if (Array.isArray(data) && data.length > 0) {
        const row = data[0];
        return {
          id: row.id,
          agentId: row.agent_id,
          userId: row.user_id,
          content: row.content,
          metadata: row.metadata,
          createdAt: row.created_at,
        };
      }
      return null;
    },
  };
}

module.exports = {
  id: 'supabase-memory',
  kind: 'memory',
  register(api, ctx = {}) {
    let client;
    try {
      client = buildClient(resolveConfig(ctx));
      console.log('✓ Supabase memory plugin initialized');
    } catch (error) {
      console.error('❌ Supabase memory plugin disabled:', error.message);
      client = {
        add: async () => {},
        search: async () => [],
        get: async () => null,
      };
    }

    api.registerMemory({
      id: 'supabase-memory',
      add: client.add,
      search: client.search,
      get: client.get,
    });
  },
};
