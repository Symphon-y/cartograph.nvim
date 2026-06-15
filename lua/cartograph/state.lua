-- cartograph.state — runtime session state.
--
-- Holds the active map(s), the live graph, comparison sets and selection so the
-- engine, server and (later) browser UI share one source of truth. Persistence
-- of named maps lives here too, reading/writing JSON under config.persist.dir.

local M = {}

M.session = nil

-- Create a fresh session and make it the active one.
function M.new()
  M.session = {
    graph = require('cartograph.graph').new(),
    root = nil, -- the node id the current map was seeded from
    compare = nil, -- { a = root_id, b = root_id } when comparing two paths
    expanded = {}, -- node id -> true, tracks which hops have been drilled
    selected = nil, -- node id currently focused in the UI
    server = nil, -- handle to the running bridge server (set in phase 2)
  }
  return M.session
end

function M.active()
  return M.session ~= nil
end

function M.clear()
  M.session = nil
end

-- Directory where named maps are persisted, ensured to exist.
local function persist_dir()
  local dir = require('cartograph.config').options.persist.dir
  vim.fn.mkdir(dir, 'p')
  return dir
end

local function valid_name(name)
  return type(name) == 'string' and name:match('^[%w%-_]+$') ~= nil
end

local function map_path(name)
  if not valid_name(name) then
    return nil
  end
  return persist_dir() .. '/' .. name .. '.json'
end

-- Names of the saved maps, sorted. Cheap enough to call for completion.
function M.list()
  local dir = require('cartograph.config').options.persist.dir
  local names = {}
  for _, path in ipairs(vim.fn.glob(dir .. '/*.json', false, true)) do
    names[#names + 1] = vim.fn.fnamemodify(path, ':t:r')
  end
  table.sort(names)
  return names
end

-- Persist the active session's graph under `name`.
function M.save(name)
  local path = map_path(name)
  if not path then
    vim.notify('cartograph: invalid map name "' .. tostring(name) .. '"', vim.log.levels.ERROR)
    return false
  end
  if not M.active() then
    vim.notify('cartograph: no active map to save', vim.log.levels.WARN)
    return false
  end
  local graph = require('cartograph.graph')
  local ok, err = pcall(function()
    local fd = assert(io.open(path, 'w'))
    fd:write(graph.to_json(M.session.graph))
    fd:close()
  end)
  if not ok then
    vim.notify('cartograph: save failed: ' .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

-- Load a named map into a fresh session and return it.
function M.load(name)
  local path = map_path(name)
  if not path then
    vim.notify('cartograph: invalid map name "' .. tostring(name) .. '"', vim.log.levels.ERROR)
    return false
  end
  local fd = io.open(path, 'r')
  if not fd then
    vim.notify('cartograph: no saved map named ' .. name, vim.log.levels.WARN)
    return nil
  end
  local content = fd:read('*a')
  fd:close()
  local graph = require('cartograph.graph')
  local ok, result = pcall(graph.from_json, content)
  if not ok then
    vim.notify('cartograph: load failed: ' .. tostring(result), vim.log.levels.ERROR)
    return nil
  end
  M.new()
  M.session.graph = result
  return M.session
end

return M
