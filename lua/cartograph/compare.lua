-- cartograph.compare — diff two maps into one annotated, renderable payload.
--
-- Pure: takes two graph models and produces a single { nodes, edges, summary }
-- structure where every node/edge is tagged with which side it belongs to
-- ('a', 'b', or 'both'). The browser renders that overlay with shared nodes and
-- divergences highlighted. Inputs are never mutated.

local M = {}

local function edge_key(e)
  return e.from .. '\0' .. e.to .. '\0' .. e.kind
end

local function sorted_keys(map)
  local keys = {}
  for k in pairs(map) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(x, y)
    return tostring(x) < tostring(y)
  end)
  return keys
end

-- Combine membership: seen on A then also on B => both.
local function fold(side, key, this_side)
  side[key] = side[key] and 'both' or this_side
end

function M.diff(a, b)
  local A = a:serialize()
  local B = b:serialize()

  -- Node membership + a representative node table per id.
  local nside, node_of = {}, {}
  for _, n in ipairs(A.nodes) do
    fold(nside, n.id, 'a')
    node_of[n.id] = n
  end
  for _, n in ipairs(B.nodes) do
    fold(nside, n.id, 'b')
    node_of[n.id] = node_of[n.id] or n
  end

  local nodes = {}
  local summary = { shared = 0, only_a = 0, only_b = 0 }
  for _, id in ipairs(sorted_keys(nside)) do
    local node = vim.deepcopy(node_of[id])
    node.side = nside[id]
    nodes[#nodes + 1] = node
    if node.side == 'both' then
      summary.shared = summary.shared + 1
    elseif node.side == 'a' then
      summary.only_a = summary.only_a + 1
    else
      summary.only_b = summary.only_b + 1
    end
  end

  -- Edge membership.
  local eside, edge_of = {}, {}
  for _, e in ipairs(A.edges) do
    local k = edge_key(e)
    fold(eside, k, 'a')
    edge_of[k] = e
  end
  for _, e in ipairs(B.edges) do
    local k = edge_key(e)
    fold(eside, k, 'b')
    edge_of[k] = edge_of[k] or e
  end

  local edges = {}
  for _, k in ipairs(sorted_keys(eside)) do
    local edge = vim.deepcopy(edge_of[k])
    edge.side = eside[k]
    edges[#edges + 1] = edge
  end

  return { nodes = nodes, edges = edges, summary = summary }
end

return M
