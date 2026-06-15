local M = {}

local defaults = {
  server = {
    host = '127.0.0.1',
    port = 0, -- 0 = random free port
    auto_open = true, -- open the browser automatically
    token = true, -- per-session URL token
  },
  view = {
    layout = 'dagre', -- cytoscape layout
    theme = 'auto', -- 'light' | 'dark' | 'auto'
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
