-- cartograph.resolver.treesitter — structural members & LSP-free fallback.
--
-- Two jobs: (1) expand a node into its structural members (a controller's
-- actions, injected fields, return types) via Treesitter queries, and (2) serve
-- as the fallback root resolver when no LSP client is attached. Phase 1 lands
-- the fallback path; richer member queries grow with the adapters in phase 3.

local M = {}

local graph_mod = require('cartograph.graph')

local function location_id(file, line, col)
  return ('%s:%d:%d'):format(file, line, col)
end

-- Best-effort root node from the cursor using only the buffer + Treesitter.
-- Names the node from the smallest identifier/name node under the cursor when a
-- parser is available, otherwise falls back to <cword>.
function M.from_cursor(on_done)
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  local lang = vim.bo[bufnr].filetype
  local pos = vim.api.nvim_win_get_cursor(0)
  local line, col = pos[1] - 1, pos[2]

  local name = vim.fn.expand('<cword>')
  local ok, node = pcall(function()
    return vim.treesitter.get_node({ bufnr = bufnr, pos = { line, col } })
  end)
  if ok and node then
    local text_ok, text = pcall(vim.treesitter.get_node_text, node, bufnr)
    if text_ok and text and not text:find('\n') and #text > 0 then
      name = text
    end
  end

  if name == nil or name == '' then
    return on_done(nil, graph_mod.new())
  end

  local graph = graph_mod.new()
  local root = {
    id = location_id(file, line, col),
    kind = 'call',
    name = name,
    file = file,
    range = { start = { line = line, character = col } },
    lang = lang,
    meta = { source = 'treesitter.cursor' },
  }
  graph:add_node(root)
  on_done(root, graph)
end

-- Expand `node` into its structural members. Stub for phase 1; the per-stack
-- queries land with the dotnet/vue adapters in phase 3.
function M.expand(node, on_done)
  on_done(graph_mod.new())
end

return M
