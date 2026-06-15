-- cartograph.layer — CLEAN-architecture layer classification.
--
-- Pure (no Neovim API): given a node and the `clean` config, decide which
-- architectural layer it belongs to. Resolution order, most to least specific:
--   1. explicit overrides  — a Lua pattern matched against the node's file path
--   2. directory patterns   — a substring of the path, tried in `layers` order
--   3. kind fallback        — a coarse mapping keyed on the node's kind
--   4. 'unknown'            — nothing matched
-- This mirrors how graph.lua/route.lua keep logic pure + unit-testable.

local M = {}

-- Match `file` (lowercased) against any of `fragments` as a plain substring.
local function path_has(file, fragments)
  local lower = file:lower()
  for _, frag in ipairs(fragments) do
    if lower:find(frag:lower(), 1, true) then
      return true
    end
  end
  return false
end

-- Decide a node's layer from the `clean` config table.
function M.classify(node, cfg)
  cfg = cfg or {}
  local file = node.file

  -- 1. Overrides: { [lua_pattern] = layer } matched against the path.
  if file and cfg.overrides then
    for pattern, layer in pairs(cfg.overrides) do
      if file:match(pattern) then
        return layer
      end
    end
  end

  -- 2. Directory patterns, tried in declared layer order for determinism.
  if file and cfg.patterns and cfg.layers then
    for _, layer in ipairs(cfg.layers) do
      local fragments = cfg.patterns[layer]
      if fragments and path_has(file, fragments) then
        return layer
      end
    end
  end

  -- 3. Coarse fallback keyed on the node kind (no file required).
  if cfg.kind_fallback and node.kind then
    local layer = cfg.kind_fallback[node.kind]
    if layer then
      return layer
    end
  end

  return 'unknown'
end

-- Stamp `node.layer` on every node of a Graph in place. Returns the graph.
function M.annotate(graph, cfg)
  for _, node in pairs(graph.nodes) do
    node.layer = M.classify(node, cfg)
  end
  return graph
end

return M
