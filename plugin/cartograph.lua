if vim.g.loaded_cartograph == 1 then
  return
end
vim.g.loaded_cartograph = 1

vim.api.nvim_create_user_command('Cartograph', function(opts)
  if opts.bang then
    require('cartograph').close()
  else
    require('cartograph').open()
  end
end, { bang = true, desc = 'Open the cartograph map view (! to close)' })

vim.api.nvim_create_user_command('CartographFromCursor', function()
  require('cartograph').from_cursor()
end, { desc = 'Map from the symbol under the cursor' })

vim.api.nvim_create_user_command('CartographRepo', function()
  require('cartograph').repo()
end, { desc = 'Map the whole repository as a force-directed graph, grouped by CLEAN layer' })

vim.api.nvim_create_user_command('CartographEndpoint', function(opts)
  require('cartograph').from_endpoint(opts.args)
end, { nargs = 1, desc = 'Map from an HTTP endpoint, e.g. :CartographEndpoint GET /api/x' })

vim.api.nvim_create_user_command('CartographCompare', function(opts)
  local a, b = opts.args:match('^(.-)%s*|%s*(.+)$')
  if a and b then
    require('cartograph').compare(vim.trim(a), vim.trim(b))
  else
    require('cartograph').compare_prompt()
  end
end, { nargs = '*', desc = 'Compare two paths, e.g. :CartographCompare GET /api/x | GET /api/y' })

vim.api.nvim_create_user_command('CartographSave', function(opts)
  require('cartograph').save(opts.args)
end, { nargs = 1, desc = 'Save the active map under a name' })

vim.api.nvim_create_user_command('CartographLoad', function(opts)
  require('cartograph').load(opts.args)
end, {
  nargs = 1,
  desc = 'Load a saved map by name',
  complete = function(arglead)
    return vim.tbl_filter(function(name)
      return name:find(arglead, 1, true) == 1
    end, require('cartograph.state').list())
  end,
})

vim.api.nvim_create_user_command('CartographMaps', function()
  require('cartograph').list_maps()
end, { desc = 'List saved cartograph maps' })

vim.api.nvim_create_user_command('CartographClose', function()
  require('cartograph').close()
end, { desc = 'Close the cartograph session' })
