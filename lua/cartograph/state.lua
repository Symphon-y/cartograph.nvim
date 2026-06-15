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
    focus = nil, -- { path = { node_id, … } } the active focus/trace path
    server = nil, -- handle to the running bridge server (set in phase 2)
  }
  return M.session
end

function M.active()
  return M.session ~= nil
end

-- Annotate the active graph with CLEAN layers and push it to every browser.
-- The single place graph updates leave the engine, so layer stamping and the
-- SSE wire format live in one spot (used by init, the bridge and the repo cmd).
function M.broadcast_graph()
  if not (M.active() and M.session.server) then
    return
  end
  local cfg = require('cartograph.config').options.clean
  require('cartograph.layer').annotate(M.session.graph, cfg)
  M.session.server:broadcast('graph:update', M.session.graph:serialize())
  -- A graph change (e.g. an expand adding children) may light new nodes in the
  -- active focus path — recompute and re-push the overlay so it stays in sync.
  if M.session.focus and M.session.focus.path and #M.session.focus.path > 0 then
    M.broadcast_focus()
  end
end

-- Push the focus/trace overlay (active node set + breadcrumb path) to browsers.
-- An empty path broadcasts a cleared overlay so the UI un-dims the full graph.
function M.broadcast_focus()
  if not (M.active() and M.session.server) then
    return
  end
  local path = M.session.focus and M.session.focus.path or {}
  local overlay
  if #path > 0 then
    overlay = require('cartograph.focus').overlay(path, M.session.graph)
  else
    overlay = { active = vim.empty_dict(), path = {} }
  end
  M.session.server:broadcast('focus:update', overlay)
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
