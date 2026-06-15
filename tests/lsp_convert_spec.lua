local lsp = require('cartograph.resolver.lsp')

describe('cartograph.resolver.lsp.outgoing_to_graph', function()
  local SK = vim.lsp.protocol.SymbolKind

  local function outgoing(name, kind, file, line)
    return {
      to = {
        name = name,
        kind = kind,
        uri = vim.uri_from_fname(file),
        selectionRange = { start = { line = line, character = 0 } },
      },
    }
  end

  it('turns outgoing calls into nodes + calls edges off the source node', function()
    local items = {
      outgoing('Validate', SK.Method, '/proj/Svc.cs', 10),
      outgoing('UserDto', SK.Struct, '/proj/UserDto.cs', 3),
    }
    local g = lsp.outgoing_to_graph('root:0:0', items, 'cs')

    assert.are.equal(2, g:node_count())
    assert.are.equal(2, g:edge_count())

    local validate_id = ('%s:%d:%d'):format('/proj/Svc.cs', 10, 0)
    local node = g:get_node(validate_id)
    assert.are.equal('Validate', node.name)
    assert.are.equal('action', node.kind) -- Method -> action
    assert.are.equal('/proj/Svc.cs', node.file)

    local dto_id = ('%s:%d:%d'):format('/proj/UserDto.cs', 3, 0)
    assert.are.equal('type', g:get_node(dto_id).kind) -- Struct -> type

    for _, edge in ipairs(g:serialize().edges) do
      assert.are.equal('root:0:0', edge.from)
      assert.are.equal('calls', edge.kind)
    end
  end)

  it('dedupes repeated outgoing targets', function()
    local items = {
      outgoing('Validate', SK.Method, '/proj/Svc.cs', 10),
      outgoing('Validate', SK.Method, '/proj/Svc.cs', 10),
    }
    local g = lsp.outgoing_to_graph('root:0:0', items, 'cs')
    assert.are.equal(1, g:node_count())
    assert.are.equal(1, g:edge_count())
  end)

  it('handles an empty/nil outgoing list', function()
    assert.are.equal(0, lsp.outgoing_to_graph('root', nil, 'cs'):node_count())
    assert.are.equal(0, lsp.outgoing_to_graph('root', {}, 'cs'):edge_count())
  end)
end)
