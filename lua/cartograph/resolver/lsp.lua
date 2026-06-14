-- cartograph.resolver.lsp — in-language hops via the Language Server Protocol.
--
-- Uses textDocument/{definition,references,documentSymbol} and callHierarchy to
-- walk connections within a single language. Everything here is async and
-- degrades gracefully: with no LSP client attached it falls back to the
-- Treesitter resolver so `from_cursor` still produces a root node.

local M = {}

local graph_mod = require('cartograph.graph')

-- Map an LSP SymbolKind to one of our coarse node kinds. Anything we don't have
-- a dedicated kind for becomes a generic 'call' node so the graph stays usable.
local SYMBOL_KIND = vim.lsp.protocol.SymbolKind
local function node_kind_for(symbol_kind)
  if symbol_kind == SYMBOL_KIND.Class or symbol_kind == SYMBOL_KIND.Interface then
    return 'controller'
  elseif symbol_kind == SYMBOL_KIND.Method or symbol_kind == SYMBOL_KIND.Function then
    return 'action'
  elseif symbol_kind == SYMBOL_KIND.Field or symbol_kind == SYMBOL_KIND.Property then
    return 'field'
  elseif symbol_kind == SYMBOL_KIND.Struct or symbol_kind == SYMBOL_KIND.Enum then
    return 'type'
  end
  return 'call'
end

-- Stable node id from a location so the same symbol dedupes across hops.
local function location_id(file, range)
  local line = range and range.start and range.start.line or 0
  local col = range and range.start and range.start.character or 0
  return ('%s:%d:%d'):format(file, line, col)
end

local function lang_for_buf(bufnr)
  return vim.bo[bufnr].filetype
end

-- Return the first LSP client attached to `bufnr` that supports documentSymbol,
-- or nil. Works across the 0.9→0.12 client API changes.
local function has_symbol_client(bufnr)
  local clients = vim.lsp.get_clients and vim.lsp.get_clients({ bufnr = bufnr })
    or vim.lsp.get_active_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    if client.server_capabilities and client.server_capabilities.documentSymbolProvider then
      return client
    end
  end
  return nil
end

-- Seed a graph from the symbol under the cursor. Calls
-- `on_done(root_node, graph)` — root_node is nil when nothing resolvable.
function M.from_cursor(on_done)
  local bufnr = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  local lang = lang_for_buf(bufnr)

  if not has_symbol_client(bufnr) then
    -- No LSP here — fall back to Treesitter for a best-effort root node.
    return require('cartograph.resolver.treesitter').from_cursor(on_done)
  end

  local params = vim.lsp.util.make_position_params(0, 'utf-16')
  vim.lsp.buf_request_all(bufnr, 'textDocument/definition', params, function(results)
    local graph = graph_mod.new()
    local root

    for _, res in pairs(results) do
      local result = res.result
      if result then
        -- definition may be a Location or an array of Location/LocationLink.
        local loc = result
        if vim.islist and vim.islist(result) then
          loc = result[1]
        elseif vim.tbl_islist and vim.tbl_islist(result) then
          loc = result[1]
        end
        if loc then
          local uri = loc.uri or loc.targetUri
          local range = loc.range or loc.targetSelectionRange or loc.targetRange
          local def_file = uri and vim.uri_to_fname(uri) or file
          root = {
            id = location_id(def_file, range),
            kind = 'action',
            name = vim.fn.expand('<cword>'),
            file = def_file,
            range = range,
            lang = lang,
            meta = { source = 'lsp.definition' },
          }
          break
        end
      end
    end

    if not root then
      -- Definition came back empty; still anchor a node at the cursor so the
      -- user sees *something* and can expand from there.
      local pos = vim.api.nvim_win_get_cursor(0)
      root = {
        id = location_id(file, { start = { line = pos[1] - 1, character = pos[2] } }),
        kind = 'call',
        name = vim.fn.expand('<cword>'),
        file = file,
        range = { start = { line = pos[1] - 1, character = pos[2] } },
        lang = lang,
        meta = { source = 'lsp.cursor' },
      }
    end

    graph:add_node(root)
    on_done(root, graph)
  end)
end

-- Expand `node` by one hop using references/callHierarchy. Stub for phase 1+;
-- returns an empty graph today so callers can already wire the shape.
function M.expand(node, on_done)
  on_done(graph_mod.new())
end

return M
