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
      M.compare_prompt()
    end, { desc = 'Cartograph: compare two paths' })
  end

  -- Keep the cross-stack route/call index warm: refresh a file's entries when
  -- it is written (no-op until the index has been built once).
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = vim.api.nvim_create_augroup('CartographIndex', { clear = true }),
    pattern = { '*.cs', '*.ts', '*.js', '*.vue' },
    callback = function(args)
      require('cartograph.index').refresh(args.file)
    end,
  })
end

-- Seed a map from an HTTP endpoint matched by `query` (e.g. "GET /api/x").
-- Drives the same cross-stack bridge the browser's setRoot uses.
function M.from_endpoint(query)
  if not query or query == '' then
    vim.notify('cartograph: from_endpoint requires a query', vim.log.levels.WARN)
    return
  end
  if not state.active() then
    M.open()
  end
  local index = require('cartograph.index')
  local http = require('cartograph.resolver.http')
  local g, root, info = http.from_endpoint(index.get(), query)
  if not root then
    vim.notify('cartograph: no endpoint matches ' .. query, vim.log.levels.WARN)
    return
  end
  state.session.graph:merge(g)
  state.session.root = root.id
  state.session.expanded[root.id] = true
  if state.session.server then
    state.session.server:broadcast('graph:update', state.session.graph:serialize())
  end
  vim.notify(
    ('cartograph: rooted at %s%s'):format(root.name, info.ambiguous and ' (ambiguous — see choices)' or ''),
    vim.log.levels.INFO
  )
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

  local url = session.server:url('/', {
    theme = config.options.view.theme,
    layout = config.options.view.layout,
  })
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

-- Build a map graph for a compare seed (an endpoint query like "GET /api/x").
local function seed_graph(seed)
  local http = require('cartograph.resolver.http')
  return (http.from_endpoint(require('cartograph.index').get(), seed))
end

-- Compare two paths: build a map for each seed, diff them, and push the
-- annotated overlay to the browser. This is the single implementation the
-- command, the keymap prompt and the browser's compare action all route to.
function M.compare(a, b)
  if not a or a == '' or not b or b == '' then
    vim.notify('cartograph: compare needs two endpoints (A and B)', vim.log.levels.WARN)
    return
  end
  if not state.active() then
    M.open()
  end

  local ga, gb = seed_graph(a), seed_graph(b)
  if not ga or not gb then
    vim.notify('cartograph: no endpoint for ' .. (ga and b or a), vim.log.levels.WARN)
    return
  end

  local diff = require('cartograph.compare').diff(ga, gb)
  state.session.compare = { a = a, b = b }
  if state.session.server then
    state.session.server:broadcast('compare:update', diff)
  end
  vim.notify(
    ('cartograph: compare — %d shared, %d only-A, %d only-B'):format(
      diff.summary.shared,
      diff.summary.only_a,
      diff.summary.only_b
    ),
    vim.log.levels.INFO
  )
end

-- Prompt for two endpoints, then compare them (used by the keymap).
function M.compare_prompt()
  vim.ui.input({ prompt = 'Compare endpoint A (e.g. GET /api/x): ' }, function(a)
    if not a or a == '' then
      return
    end
    vim.ui.input({ prompt = 'Compare endpoint B: ' }, function(b)
      if b and b ~= '' then
        M.compare(a, b)
      end
    end)
  end)
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
    if state.session.server then
      state.session.server:broadcast('graph:update', state.session.graph:serialize())
    end
    vim.notify('cartograph: loaded map "' .. name .. '"', vim.log.levels.INFO)
  end
end

-- Echo the saved maps (also available as completion on :CartographLoad).
function M.list_maps()
  local names = state.list()
  if #names == 0 then
    vim.notify('cartograph: no saved maps', vim.log.levels.INFO)
    return names
  end
  vim.notify('cartograph maps:\n  ' .. table.concat(names, '\n  '), vim.log.levels.INFO)
  return names
end

return M
