local M = {}

local defaults = {
  server = {
    host = '127.0.0.1',
    port = 0, -- 0 = random free port
    auto_open = true, -- open the browser automatically
    token = true, -- per-session URL token
  },
  view = {
    renderer = '3d', -- '3d' (force-directed) | '2d' (cytoscape/dagre)
    layout = 'dagre', -- cytoscape layout (2d renderer only)
    theme = 'auto', -- 'light' | 'dark' | 'auto'
  },
  -- CLEAN-architecture layering: how nodes are sorted/coloured into layers.
  -- Resolution order is overrides -> directory patterns (in `layers` order) ->
  -- kind_fallback -> 'unknown'. See cartograph.layer.
  clean = {
    -- Layer order also controls plane stacking in the 3D view (first = top).
    layers = { 'UI', 'Adapters', 'Application', 'Domain', 'Infrastructure' },
    patterns = {
      UI = { '/ui/', '/web/', '/views/', '/components/', '/pages/', '/client/' },
      Adapters = { '/adapters/', '/controllers/', '/api/', '/presentation/', '/interfaces/' },
      Application = { '/application/', '/usecases/', '/use_cases/', '/app/' },
      Domain = { '/domain/', '/entities/', '/entity/', '/core/' },
      Infrastructure = { '/infrastructure/', '/infra/', '/persistence/', '/data/', '/frameworks/' },
    },
    overrides = {}, -- { [lua_pattern_on_path] = layer }
    kind_fallback = {
      endpoint = 'Adapters',
      controller = 'Adapters',
      action = 'Application',
      service = 'Application',
      store = 'UI',
      call = 'UI',
      type = 'Domain',
      field = 'Domain',
    },
  },
  -- Whole-repository symbol/call graph (:CartographRepo).
  repo = {
    -- file extension -> Treesitter language; also selects which files are scanned.
    languages = {
      cs = 'c_sharp',
      ts = 'typescript',
      tsx = 'tsx',
      js = 'javascript',
      jsx = 'javascript',
      vue = 'vue',
      lua = 'lua',
      py = 'python',
      go = 'go',
      rb = 'ruby',
      rs = 'rust',
      java = 'java',
    },
    max_nodes = 2000, -- cap to keep huge repos renderable
    -- Path fragments (plain substrings) excluded from the scan. Keeps deps,
    -- build output and vendored code out of the map. Override to taste.
    ignore = {
      'node_modules',
      '/.git/',
      '/bin/',
      '/obj/',
      '/dist/',
      '/build/',
      '/out/',
      '/target/',
      '/.next/',
      '/.nuxt/',
      '/.svelte-kit/',
      '/coverage/',
      '/vendor/',
      '/packages/', -- nuget/composer restore dirs
      '/.nuget/',
      '/.venv/',
      '/venv/',
      '/.deps/',
      '/.cache/',
    },
  },
  adapters = { 'dotnet', 'vue' },
  resolvers = { lsp = true, treesitter = true, http = true },
  http = {
    base_urls = {}, -- e.g. { '/api', 'https://localhost:5001' }
    route_overrides = {}, -- explicit { frontend_call = backend_route } links
  },
  persist = {
    dir = vim.fn.stdpath('data') .. '/cartograph',
  },
  keymaps = {
    -- Neovim-side trigger maps (UI maps live in the browser)
    from_cursor = '<leader>cm',
    compare = '<leader>cc',
  },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  return M.options
end

return M
