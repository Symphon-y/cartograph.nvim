-- cartograph.bridge — the engine interface the browser drives through protocol.
--
-- This is the composition seam: it closes over the active session and a holder
-- for the running server, exposing the small set of operations protocol.lua
-- routes to (set_root/expand/compare/reveal/save/load). Keeping it separate from
-- both transport (server) and routing (protocol) is the SOLID payoff — each side
-- depends only on this contract.

local M = {}

-- `holder.server` is the running server (set by init after start). Passing a
-- holder rather than the server itself breaks the start-time chicken-and-egg:
-- the engine needs the server to push updates, but the server needs the engine
-- to handle requests.
function M.engine(holder)
  local state = require('cartograph.state')
  local lsp = require('cartograph.resolver.lsp')

  local function push_graph()
    if holder.server and state.active() then
      holder.server:broadcast('graph:update', state.session.graph:serialize())
    end
  end

  local function status(message)
    if holder.server then
      holder.server:broadcast('status', { message = message })
    end
  end

  -- Summarize ranked endpoint candidates for the browser's ambiguity pick-list.
  local function candidate_list(ranked)
    local out = {}
    for _, c in ipairs(ranked) do
      local e = c.route._src
      out[#out + 1] = { method = e.method, path = e.norm.str, action = e.action, file = e.file }
    end
    return out
  end

  return {
    -- Browser-initiated root by query (e.g. an endpoint like "GET /api/x"):
    -- match it against the workspace index and seed the map from that endpoint.
    set_root = function(query)
      local index = require('cartograph.index')
      local http = require('cartograph.resolver.http')
      local g, root, info = http.from_endpoint(index.get(), query)
      if not root then
        return status('no endpoint matches: ' .. tostring(query))
      end
      if not state.active() then
        return
      end
      state.session.graph:merge(g)
      state.session.root = root.id
      state.session.expanded[root.id] = true
      push_graph()
      if info.ambiguous and holder.server then
        holder.server:broadcast('choices', { query = query, candidates = candidate_list(info.candidates) })
      end
      status('rooted at ' .. root.name)
    end,

    expand = function(node_id)
      if not state.active() then
        return
      end
      local node = state.session.graph:get_node(node_id)
      if not node then
        return
      end
      state.session.expanded[node_id] = true
      lsp.expand(node, function(g)
        state.session.graph:merge(g)
        push_graph()
      end)
    end,

    reveal = function(node_id)
      require('cartograph.reveal').reveal(node_id)
    end,

    compare = function(_, _)
      status('compare arrives in phase 4')
    end,

    save = function(name)
      require('cartograph').save(name)
    end,

    load = function(name)
      require('cartograph').load(name)
      push_graph()
    end,
  }
end

return M
