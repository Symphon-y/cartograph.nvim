-- cartograph.root — locate the workspace root to scan.

local M = {}

local MARKERS = { '.git', '.sln', 'package.json', 'Directory.Build.props' }

local function has_marker(dir)
  for _, marker in ipairs(MARKERS) do
    if vim.fn.isdirectory(dir .. '/' .. marker) == 1 or vim.fn.filereadable(dir .. '/' .. marker) == 1 then
      return true
    end
    -- glob for suffix markers like *.sln
    if marker:sub(1, 1) == '.' and #vim.fn.glob(dir .. '/*' .. marker, false, true) > 0 then
      return true
    end
  end
  return false
end

function M.find(start)
  local dir = start or vim.fn.getcwd()
  local check = dir
  while true do
    if has_marker(check) then
      return check
    end
    local parent = vim.fn.fnamemodify(check, ':h')
    if parent == check then
      break
    end
    check = parent
  end
  return dir
end

return M
