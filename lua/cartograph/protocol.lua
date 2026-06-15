-- cartograph.protocol — pure browser->nvim action routing.
--
-- The browser POSTs JSON messages ({ action = ..., ...params }); this module
-- validates them and routes to an injected `engine` interface. It knows nothing
-- about transport (server.lua) or how the engine fulfils a request — only the
-- contract between them. That keeps it pure and trivially testable.

local M = {}

local unpack = table.unpack or unpack

-- action -> { engine method, required params (in call order) }.
local ROUTES = {
  setRoot = { method = 'set_root', params = { 'query' } },
  expand = { method = 'expand', params = { 'nodeId' } },
  compare = { method = 'compare', params = { 'rootA', 'rootB' } },
  reveal = { method = 'reveal', params = { 'nodeId' } },
  focus = { method = 'focus', params = { 'nodeId' } },
  clearFocus = { method = 'clear_focus', params = {} },
  save = { method = 'save', params = { 'name' } },
  load = { method = 'load', params = { 'name' } },
}

local function err(message)
  return { status = 'error', message = message }
end

-- Route a decoded message table to the engine. Returns { status = 'ok' } or
-- { status = 'error', message = ... }.
function M.dispatch(msg, engine)
  if type(msg) ~= 'table' or msg.action == nil then
    return err('missing action')
  end

  local route = ROUTES[msg.action]
  if not route then
    return err('unknown action: ' .. tostring(msg.action))
  end

  local args = {}
  for i, name in ipairs(route.params) do
    local value = msg[name]
    if value == nil then
      return err(('%s requires "%s"'):format(msg.action, name))
    end
    args[i] = value
  end

  local fn = engine[route.method]
  if type(fn) ~= 'function' then
    return err('engine cannot handle: ' .. msg.action)
  end
  fn(unpack(args, 1, #route.params))

  return { status = 'ok' }
end

-- Decode a raw JSON request body and dispatch it.
function M.handle(raw, engine)
  local ok, msg = pcall(vim.json.decode, raw)
  if not ok then
    return err('malformed JSON')
  end
  return M.dispatch(msg, engine)
end

return M
