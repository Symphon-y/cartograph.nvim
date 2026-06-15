-- cartograph.health — :checkhealth cartograph
--
-- Verifies the pieces the plugin leans on: the Treesitter parsers for the v1
-- stack, an available LSP client story, and that a browser can be launched for
-- the interactive UI.

local M = {}

-- vim.health gained its current function names in 0.10; alias for older nvim.
local health = vim.health or {}
local h_start = health.start or health.report_start
local h_ok = health.ok or health.report_ok
local h_warn = health.warn or health.report_warn
local h_error = health.error or health.report_error
local h_info = health.info or health.report_info

local REQUIRED_PARSERS = { 'c_sharp', 'typescript', 'vue' }

local function has_parser(lang)
  return pcall(vim.treesitter.language.add, lang)
end

function M.check()
  h_start('cartograph: Treesitter parsers')
  for _, lang in ipairs(REQUIRED_PARSERS) do
    if has_parser(lang) then
      h_ok(lang .. ' parser installed')
    else
      h_warn(
        lang .. ' parser missing',
        { 'Install it with :TSInstall ' .. lang .. ' for full structural resolution' }
      )
    end
  end

  h_start('cartograph: LSP')
  local get_clients = vim.lsp.get_clients or vim.lsp.get_active_clients
  local clients = get_clients()
  if #clients > 0 then
    local names = {}
    for _, c in ipairs(clients) do
      names[#names + 1] = c.name
    end
    h_ok('LSP client(s) active: ' .. table.concat(names, ', '))
  else
    h_info('No LSP clients active right now — resolvers fall back to Treesitter')
  end

  h_start('cartograph: browser')
  local opener
  if vim.fn.has('mac') == 1 then
    opener = 'open'
  elseif vim.fn.has('win32') == 1 or vim.fn.has('win64') == 1 then
    opener = 'cmd'
  else
    opener = 'xdg-open'
  end
  if vim.fn.executable(opener) == 1 then
    h_ok('browser launcher available: ' .. opener)
  else
    h_warn(
      'browser launcher "' .. opener .. '" not found',
      { 'The interactive UI opens in a browser; set view to terminal mode when available' }
    )
  end

  h_start('cartograph: bundled web UI')
  local src = debug.getinfo(1, 'S').source:sub(2)
  local plugin_root = vim.fn.fnamemodify(src, ':h:h:h')
  local assets = { '/web/index.html', '/web/vendor/cytoscape.min.js' }
  local missing = false
  for _, rel in ipairs(assets) do
    if vim.fn.filereadable(plugin_root .. rel) ~= 1 then
      missing = true
      h_error('missing bundled asset: ' .. rel)
    end
  end
  if not missing then
    h_ok('web UI assets present (Cytoscape vendored offline)')
  end

  h_start('cartograph: persistence')
  local dir = require('cartograph.config').options.persist.dir
  local ok = pcall(function()
    vim.fn.mkdir(dir, 'p')
  end)
  if ok and vim.fn.isdirectory(dir) == 1 and vim.fn.filewritable(dir) == 2 then
    h_ok('saved-maps directory writable: ' .. dir)
  else
    h_warn('saved-maps directory not writable: ' .. dir, { 'Saving/loading named maps will fail' })
  end
end

return M
