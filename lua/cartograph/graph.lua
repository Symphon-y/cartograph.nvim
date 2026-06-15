-- cartograph.graph — language-agnostic in-memory graph model.
--
-- This is the heart of the engine: every resolver and adapter produces nodes
-- and edges that land here. It is pure data + helpers (no Neovim API calls) so
-- it can be unit-tested in isolation and, later, serialized to the browser UI.

local M = {}

-- Valid node/edge kinds, per CARTOGRAPH_PLAN.md §3. Kept as lookup tables so
-- callers (and tests) can validate without re-listing the set.
M.NODE_KINDS = {
  endpoint = true,
  controller = true,
  action = true,
  type = true,
  store = true,
  service = true,
  call = true,
  field = true,
}

M.EDGE_KINDS = {
  ['routes-to'] = true,
  calls = true,
  references = true,
  typeof = true,
  injects = true,
}

local Graph = {}
Graph.__index = Graph

-- Build the stable dedupe key for an edge.
local function edge_key(from, to, kind)
  return from .. '\0' .. to .. '\0' .. kind
end

-- Shallow-merge `src` into `dst`, preferring existing non-nil values on `dst`
-- but recursing one level into the `meta` table so node metadata accumulates.
local function merge_node(dst, src)
  for k, v in pairs(src) do
    if k == 'meta' and type(v) == 'table' then
      dst.meta = dst.meta or {}
      for mk, mv in pairs(v) do
        if dst.meta[mk] == nil then
          dst.meta[mk] = mv
        end
      end
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

function M.new()
  return setmetatable({
    nodes = {}, -- id -> node { id, kind, name, file, range, lang, meta }
    edges = {}, -- array of { from, to, kind }
    _edge_seen = {}, -- edge_key -> true (dedupe index, not serialized)
  }, Graph)
end

-- Return true if `t` looks like a Graph produced by M.new().
function M.is_graph(t)
  return getmetatable(t) == Graph
end

-- Add (or merge) a node. Nodes are deduped by `id`; re-adding an id fills in
-- any fields that were previously nil rather than clobbering them. Returns the
-- stored node.
function Graph:add_node(node)
  assert(type(node) == 'table', 'node must be a table')
  assert(node.id ~= nil, 'node.id is required')
  assert(M.NODE_KINDS[node.kind], 'invalid node kind: ' .. tostring(node.kind))

  local existing = self.nodes[node.id]
  if existing then
    return merge_node(existing, node)
  end
  self.nodes[node.id] = node
  return node
end

-- Add an edge { from, to, kind }. Edges are deduped by (from, to, kind).
-- Returns true if the edge was newly added, false if it was a duplicate.
function Graph:add_edge(edge)
  assert(type(edge) == 'table', 'edge must be a table')
  assert(edge.from ~= nil and edge.to ~= nil, 'edge.from and edge.to are required')
  assert(M.EDGE_KINDS[edge.kind], 'invalid edge kind: ' .. tostring(edge.kind))

  local key = edge_key(edge.from, edge.to, edge.kind)
  if self._edge_seen[key] then
    return false
  end
  self._edge_seen[key] = true
  self.edges[#self.edges + 1] = { from = edge.from, to = edge.to, kind = edge.kind }
  return true
end

function Graph:get_node(id)
  return self.nodes[id]
end

function Graph:node_count()
  local n = 0
  for _ in pairs(self.nodes) do
    n = n + 1
  end
  return n
end

function Graph:edge_count()
  return #self.edges
end

-- Merge another graph into this one (nodes deduped/merged by id, edges deduped).
function Graph:merge(other)
  assert(M.is_graph(other), 'merge expects another graph')
  for _, node in pairs(other.nodes) do
    self:add_node(node)
  end
  for _, edge in ipairs(other.edges) do
    self:add_edge(edge)
  end
  return self
end

-- Produce a plain, deterministic table suitable for JSON encoding or for
-- handing to the web UI. Nodes are emitted as an array sorted by id so output
-- is stable across runs (the internal node store is a hash map).
function Graph:serialize()
  local ids = {}
  for id in pairs(self.nodes) do
    ids[#ids + 1] = id
  end
  table.sort(ids, function(a, b)
    return tostring(a) < tostring(b)
  end)

  local nodes = {}
  for _, id in ipairs(ids) do
    nodes[#nodes + 1] = self.nodes[id]
  end

  return { nodes = nodes, edges = self.edges }
end

-- Encode to a JSON string (uses Neovim's vim.json when available, which it is
-- in any runtime that loads this plugin).
function M.to_json(graph)
  assert(M.is_graph(graph), 'to_json expects a graph')
  return vim.json.encode(graph:serialize())
end

-- Rebuild a Graph from a serialized table (the inverse of serialize()).
function M.from_serialized(data)
  assert(type(data) == 'table', 'from_serialized expects a table')
  local g = M.new()
  for _, node in ipairs(data.nodes or {}) do
    g:add_node(node)
  end
  for _, edge in ipairs(data.edges or {}) do
    g:add_edge(edge)
  end
  return g
end

-- Decode a Graph from a JSON string (the inverse of to_json()).
function M.from_json(str)
  return M.from_serialized(vim.json.decode(str))
end

return M
