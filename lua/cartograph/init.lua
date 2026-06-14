-- cartograph.nvim — visually trace and compare code paths through a codebase.
--
-- This module is the public API. It stays thin: it lazy-`require`s the heavier
-- submodules (engine, resolvers, server) so simply having the plugin on the
-- runtimepath costs nothing until something is actually opened.

local M = {}

local config = require('cartograph.config')
local state = require('cartograph.state')

function M.setup(opts)
  config.setup(opts)
  require('cartograph.highlights').setup()

  local maps = config.options.keymaps
  if maps.from_cursor then
    vim.keymap.set('n', maps.from_cursor, function()
      M.from_cursor()
    end, { desc = 'Cartograph: map from symbol under cursor' })
  end
  if maps.compare then
    vim.keymap.set('n', maps.compare, function()
      M.compare()
    end, { desc = 'Cartograph: compare two paths' })
  end
end

-- Open (or focus) the interactive map view: start the local bridge server and
-- open the browser at its tokenized URL. Idempotent — a second call just
-- re-opens the browser at the running server.
function M.open()
  if not state.active() then
    state.new()
  end

  local session = state.session
  if not session.server then
    local server_opts = config.options.server
    local holder = {}
    local engine = require('cartograph.bridge').engine(holder)
    local server = require('cartograph.server').start({
      host = server_opts.host,
      port = server_opts.port,
      token = server_opts.token,
      engine = engine,
    })
    holder.server = server
    session.server = server
  end

  -- Push whatever we already have so a freshly opened browser isn't blank.
  session.server:broadcast('graph:update', session.graph:serialize())

  local url = session.server:url('/')
  url = url .. (url:find('?', 1, true) and '&' or '?') .. 'theme=' .. config.options.view.theme
  if config.options.server.auto_open then
    require('cartograph.browser').open(url)
  end
  vim.notify('cartograph: serving map at ' .. url, vim.log.levels.INFO)
  return url
end

function M.close()
  if state.active() then
    if state.session.server then
      state.session.server:stop()
    end
    state.clear()
  end
end

function M.refresh()
  if not state.active() then
    vim.notify('cartograph: no active map', vim.log.levels.WARN)
    return
  end
  -- TODO(phase 1+): re-run resolvers for the current root.
end

-- Seed a map from the symbol under the cursor and drill its first hop. This is
-- the entry point that exercises the engine end-to-end today.
function M.from_cursor()
  if not state.active() then
    state.new()
  end

  local resolver = require('cartograph.resolver.lsp')
  resolver.from_cursor(function(root, graph)
    if not root then
      vim.notify('cartograph: nothing resolvable under cursor', vim.log.levels.WARN)
      return
    end
    state.session.graph:merge(graph)
    state.session.root = root.id
    state.session.expanded[root.id] = true
    local g = state.session.graph
    vim.notify(
      ('cartograph: mapped %s "%s" — %d node(s), %d edge(s)'):format(
        root.kind,
        root.name,
        g:node_count(),
        g:edge_count()
      ),
      vim.log.levels.INFO
    )
    if state.session.server then
      state.session.server:broadcast('graph:update', g:serialize())
    end
  end)
end

-- Compare two paths side by side. Wired up in phase 4.
function M.compare()
  vim.notify('cartograph: compare arrives in phase 4', vim.log.levels.INFO)
end

function M.save(name)
  if not name or name == '' then
    vim.notify('cartograph: save requires a name', vim.log.levels.WARN)
    return
  end
  if state.save(name) then
    vim.notify('cartograph: saved map "' .. name .. '"', vim.log.levels.INFO)
  end
end

function M.load(name)
  if not name or name == '' then
    vim.notify('cartograph: load requires a name', vim.log.levels.WARN)
    return
  end
  if state.load(name) then
    vim.notify('cartograph: loaded map "' .. name .. '"', vim.log.levels.INFO)
  end
end

return M
