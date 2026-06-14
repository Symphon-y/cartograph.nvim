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

  return {
    -- Browser-initiated root by query. Workspace search lands with the index +
    -- adapters in phase 3; for now drive roots from nvim (:CartographFromCursor).
    set_root = function(query)
      status('setRoot by query arrives in phase 3: ' .. tostring(query))
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
