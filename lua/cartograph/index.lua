-- cartograph.index — workspace scanner + cache of routes/call-sites.
--
-- Walks the workspace, dispatches each file to the adapter that handles it, and
-- caches the resulting endpoint/call entries. Refreshes a single file's entries
-- on BufWritePost so the index stays warm without a full rescan.

local M = {}

local adapters = {
  require('cartograph.adapters.dotnet'),
  require('cartograph.adapters.vue'),
}

-- Directory fragments we never want to scan (build output, deps, vcs).
local IGNORE = { 'node_modules', '/bin/', '/obj/', '/.git/', '/dist/', '/.deps/' }

local cache = nil

local function ignored(path)
  for _, frag in ipairs(IGNORE) do
    if path:find(frag, 1, true) then
      return true
    end
  end
  return false
end

local function read_file(path)
  local fd = io.open(path, 'r')
  if not fd then
    return nil
  end
  local content = fd:read('*a')
  fd:close()
  return content
end

-- Candidate source files under `root` for the registered adapters.
function M.scan_files(root)
  local files = {}
  for _, pattern in ipairs({ '**/*.cs', '**/*.ts', '**/*.js', '**/*.vue' }) do
    for _, file in ipairs(vim.fn.globpath(root, pattern, false, true)) do
      if not ignored(file) then
        files[#files + 1] = file
      end
    end
  end
  return files
end

local function extract_into(idx, file, source)
  for _, adapter in ipairs(adapters) do
    if adapter.handles(file) then
      for _, entry in ipairs(adapter.extract(source, file)) do
        if entry.kind == 'endpoint' then
          idx.endpoints[#idx.endpoints + 1] = entry
        elseif entry.kind == 'call' then
          idx.calls[#idx.calls + 1] = entry
        end
      end
      return
    end
  end
end

-- Build (and cache) the index for `root` (defaults to the detected workspace).
function M.build(root)
  root = root or require('cartograph.root').find()
  local idx = { root = root, endpoints = {}, calls = {} }
  for _, file in ipairs(M.scan_files(root)) do
    local source = read_file(file)
    if source then
      extract_into(idx, file, source)
    end
  end
  cache = idx
  return idx
end

function M.get()
  return cache or M.build()
end

-- Re-extract a single file's entries in place (cheap BufWritePost refresh).
function M.refresh(file)
  if not cache then
    return
  end
  local function without(list)
    local kept = {}
    for _, entry in ipairs(list) do
      if entry.file ~= file then
        kept[#kept + 1] = entry
      end
    end
    return kept
  end
  cache.endpoints = without(cache.endpoints)
  cache.calls = without(cache.calls)
  local source = read_file(file)
  if source then
    extract_into(cache, file, source)
  end
end

function M.clear()
  cache = nil
end

return M
