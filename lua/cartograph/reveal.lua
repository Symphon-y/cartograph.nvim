-- cartograph.reveal — jump the editor to a graph node's source location.

local M = {}

-- Open the file for `node_id` and place the cursor on its range. Prefers a
-- window that isn't showing the map, so the graph stays visible alongside.
function M.reveal(node_id)
  local state = require('cartograph.state')
  if not state.active() then
    return
  end
  local node = state.session.graph:get_node(node_id)
  if not node or not node.file or node.file == '' then
    return
  end

  vim.schedule(function()
    vim.cmd('edit ' .. vim.fn.fnameescape(node.file))
    if node.range and node.range.start then
      local line = (node.range.start.line or 0) + 1
      local col = node.range.start.character or 0
      pcall(vim.api.nvim_win_set_cursor, 0, { line, col })
      vim.cmd('normal! zz')
    end
  end)
end

return M
