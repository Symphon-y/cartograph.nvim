-- Minimal init for headless test runs. Puts this plugin and plenary on the
-- runtimepath. plenary is expected at ../plenary.nvim (cloned by `make test`)
-- or anywhere already on the runtimepath.
local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')
local root = vim.fn.fnamemodify(here, ':h')

vim.opt.runtimepath:prepend(root)

local plenary_candidates = {
  root .. '/.deps/plenary.nvim',
  vim.fn.fnamemodify(root, ':h') .. '/plenary.nvim',
}
for _, path in ipairs(plenary_candidates) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.runtimepath:append(path)
    break
  end
end

vim.cmd('runtime plugin/plenary.vim')
