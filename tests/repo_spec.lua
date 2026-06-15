local repo = require('cartograph.repo')

-- Definitions/references shaped exactly as repo.extract() emits them, so the
-- pure resolution logic can be tested without a Treesitter parser.
local function def(name, kind, file, line)
  return { name = name, kind = kind, file = file, line = line, col = 0, lang = 'cs' }
end
local function ref(name, file, line)
  return { name = name, file = file, line = line, col = 4 }
end

describe('cartograph.repo.build_graph', function()
  it('creates one node per definition keyed by file:line:col', function()
    local g = repo.build_graph({
      def('UserService', 'controller', 'a.cs', 1),
      def('Create', 'action', 'a.cs', 5),
    }, {})
    assert.are.equal(2, g:node_count())
    local n = g:get_node('a.cs:5:0')
    assert.are.equal('Create', n.name)
    assert.are.equal('action', n.kind)
  end)

  it('links a call to its callee by name, from the enclosing definition', function()
    -- Create() (a.cs:5) calls Validate() defined in b.cs.
    local g = repo.build_graph(
      { def('Create', 'action', 'a.cs', 5), def('Validate', 'action', 'b.cs', 2) },
      { ref('Validate', 'a.cs', 7) }
    )
    assert.are.equal(1, g:edge_count())
    local e = g.edges[1]
    assert.are.equal('a.cs:5:0', e.from)
    assert.are.equal('b.cs:2:0', e.to)
    assert.are.equal('calls', e.kind)
  end)

  it('attributes a reference to the nearest preceding definition in its file', function()
    local g = repo.build_graph(
      { def('First', 'action', 'a.cs', 1), def('Second', 'action', 'a.cs', 10), def('Helper', 'action', 'b.cs', 1) },
      { ref('Helper', 'a.cs', 12) } -- inside Second(), not First()
    )
    assert.are.equal('a.cs:10:0', g.edges[1].from)
  end)

  it('drops references with no enclosing definition', function()
    local g = repo.build_graph({ def('Helper', 'action', 'b.cs', 1) }, { ref('Helper', 'a.cs', 3) })
    assert.are.equal(0, g:edge_count())
  end)

  it('drops references to an unknown name', function()
    local g = repo.build_graph({ def('Create', 'action', 'a.cs', 5) }, { ref('Ghost', 'a.cs', 7) })
    assert.are.equal(0, g:edge_count())
  end)

  it('does not create a self-edge for a recursive call', function()
    local g = repo.build_graph({ def('Fac', 'action', 'a.cs', 1) }, { ref('Fac', 'a.cs', 3) })
    assert.are.equal(0, g:edge_count())
  end)

  it('links an ambiguous name to every matching definition', function()
    local g = repo.build_graph(
      { def('Caller', 'action', 'a.cs', 1), def('Save', 'action', 'b.cs', 1), def('Save', 'action', 'c.cs', 1) },
      { ref('Save', 'a.cs', 3) }
    )
    assert.are.equal(2, g:edge_count())
  end)

  it('caps node creation at opts.max_nodes', function()
    local defs = {}
    for i = 1, 10 do
      defs[i] = def('S' .. i, 'action', 'a.cs', i)
    end
    local g = repo.build_graph(defs, {}, { max_nodes = 3 })
    assert.are.equal(3, g:node_count())
  end)

  it('carries a definition snippet onto the node meta', function()
    local d = def('Create', 'action', 'a.cs', 5)
    d.snippet = 'void Create()\n{\n}'
    local g = repo.build_graph({ d }, {})
    assert.are.equal('void Create()\n{\n}', g:get_node('a.cs:5:0').meta.snippet)
  end)
end)

describe('cartograph.repo.extract', function()
  it('returns empty, without error, when the language has no parser or tags query', function()
    local defs, refs = repo.extract('whatever', 'x.unknownlang', 'no_such_language')
    assert.are.same({}, defs)
    assert.are.same({}, refs)
  end)

  -- End-to-end through real Treesitter using the bundled queries/lua/tags.scm
  -- (lua parser ships with Neovim). Guards the fix for the nvim-treesitter
  -- `main`-branch case where no runtime tags query exists.
  it('extracts defs/refs and snippets via the bundled lua tags query', function()
    if not repo.lang_available('lua') then
      return -- no lua parser in this runtime; skip rather than fail
    end
    assert.is_not_nil(repo.tags_query('lua'))
    local src = table.concat({
      'local M = {}',
      'function M.foo(x)',
      '  return M.bar(x)',
      'end',
      'function M.bar(y)',
      '  return y + 1',
      'end',
      'return M',
    }, '\n')
    local defs, refs = repo.extract(src, 'm.lua', 'lua')
    assert.are.equal(2, #defs)
    assert.is_true(#refs >= 1)
    local names = {}
    for _, d in ipairs(defs) do
      names[d.name] = d
    end
    assert.is_not_nil(names.foo)
    assert.is_truthy(names.foo.snippet:find('function M.foo', 1, true))

    local g = repo.build_graph(defs, refs)
    assert.are.equal(2, g:node_count())
    assert.is_true(g:edge_count() >= 1) -- foo -> bar
  end)
end)
