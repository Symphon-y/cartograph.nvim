local M = {}

local function link(name, target)
  vim.api.nvim_set_hl(0, name, { link = target, default = true })
end

-- Neovim-side highlight groups (status/help floats). The browser UI is themed
-- separately via config.view.theme.
function M.setup()
  link('CartographStatus', 'Comment')
  link('CartographStatusOk', 'DiagnosticOk')
  link('CartographStatusWarn', 'DiagnosticWarn')
  link('CartographStatusError', 'DiagnosticError')
  link('CartographHelpHeader', 'Title')
  link('CartographHelpKey', 'Special')
end

-- Initialize eagerly so users who don't call setup() still get sensible colors.
M.setup()

-- Re-apply on colorscheme change.
vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('CartographHighlights', { clear = true }),
  callback = function()
    M.setup()
  end,
})

return M
