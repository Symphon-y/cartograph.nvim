-- Headless integration driver for the bridge server. Run with:
--   nvim --headless --noplugin -u tests/minimal_init.lua -l tests/integration_server.lua
-- Boots the server with a spy engine, prints PORT/TOKEN, then idles so an
-- external curl can exercise the real sockets. Exits on SIGTERM.
local recorded = {}
local function record(name)
  return function(...)
    recorded[#recorded + 1] = name
  end
end

local engine = {
  set_root = record('set_root'),
  expand = record('expand'),
  reveal = record('reveal'),
  compare = record('compare'),
  save = record('save'),
  load = record('load'),
}

local server = require('cartograph.server').start({ host = '127.0.0.1', port = 0, engine = engine })

-- Push a graph on a repeating timer so any SSE client that connects during the
-- test window reliably receives a graph:update.
local timer = (vim.uv or vim.loop).new_timer()
timer:start(150, 200, function()
  server:broadcast('graph:update', { nodes = { { id = 'n1', name = 'Root', kind = 'controller' } }, edges = {} })
end)

io.stdout:write('PORT=' .. server.port .. ' TOKEN=' .. server.token .. '\n')
io.stdout:flush()

-- Pump Neovim's main loop (which processes vim.schedule callbacks, where the
-- server writes its responses) until the parent kills us.
vim.wait(600000, function()
  return false
end)
