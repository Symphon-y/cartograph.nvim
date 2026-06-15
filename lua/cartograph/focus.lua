-- cartograph.focus — pure path-tracing / focus model.
--
-- Clicking a node builds an ordered path through the graph (node => node =>
-- node) and decides which nodes stay lit ("active") while the rest dim. This is
-- the single source of truth for the focus overlay the browser renders; it is
-- pure (no Neovim API) so it unit-tests like graph.lua / layer.lua / route.lua.
--
-- "Children" are outgoing edge targets (callees): the path builds downstream.
-- Reads only graph.nodes (id -> node) and graph.edges (array of {from,to,kind}),
-- so it works with a cartograph.graph object or any plain table of that shape.

local M = {}

local function has_node(graph, id)
  return graph and graph.nodes and graph.nodes[id] ~= nil
end

-- Outgoing edge targets of `id` that still exist in the graph, as a set.
function M.successors(graph, id)
  local out = {}
  if not (graph and graph.edges) then
    return out
  end
  for _, e in ipairs(graph.edges) do
    if e.from == id and has_node(graph, e.to) then
      out[e.to] = true
    end
  end
  return out
end

local function index_of(path, id)
  for i, v in ipairs(path) do
    if v == id then
      return i
    end
  end
  return nil
end

local function truncated(path, n)
  local out = {}
  for i = 1, n do
    out[i] = path[i]
  end
  return out
end

-- Advance/rewind the selection path given a freshly clicked node. PURE.
--   empty path            -> { id }
--   id == tail            -> unchanged
--   id already on path    -> truncate to it (rewind)
--   id is a child of tail -> append (advance)
--   otherwise             -> { id } (fresh path elsewhere)
function M.step(path, node_id, graph)
  path = path or {}
  if #path == 0 then
    return { node_id }
  end
  local tail = path[#path]
  if node_id == tail then
    return path
  end
  local at = index_of(path, node_id)
  if at then
    return truncated(path, at)
  end
  if M.successors(graph, tail)[node_id] then
    local out = truncated(path, #path)
    out[#out + 1] = node_id
    return out
  end
  return { node_id }
end

-- Compute the focus overlay for a path. PURE.
--   active = path nodes (that still exist) ∪ children of the surviving tail
--   path   = breadcrumb entries { id, name, kind } for surviving nodes
--   tail   = the last surviving node id (nil when nothing survives)
function M.overlay(path, graph)
  path = path or {}
  local crumbs, active = {}, {}
  for _, id in ipairs(path) do
    local node = graph and graph.nodes and graph.nodes[id]
    if node then
      crumbs[#crumbs + 1] = { id = id, name = node.name, kind = node.kind }
      active[id] = true
    end
  end
  local tail = crumbs[#crumbs] and crumbs[#crumbs].id or nil
  if tail then
    for child in pairs(M.successors(graph, tail)) do
      active[child] = true
    end
  end
  return { active = active, path = crumbs, tail = tail }
end

return M
