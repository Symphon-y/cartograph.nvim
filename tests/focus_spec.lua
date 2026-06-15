local focus = require('cartograph.focus')
local graph_mod = require('cartograph.graph')

-- Build a small call graph: getUser -> validate -> dbQuery, getUser -> log.
-- (Edges are directed; "children" are outgoing targets.)
local function sample()
  local g = graph_mod.new()
  local function node(id, name)
    g:add_node({ id = id, kind = 'action', name = name })
  end
  node('getUser', 'getUser')
  node('validate', 'validate')
  node('dbQuery', 'dbQuery')
  node('log', 'log')
  node('orphan', 'orphan')
  g:add_edge({ from = 'getUser', to = 'validate', kind = 'calls' })
  g:add_edge({ from = 'getUser', to = 'log', kind = 'calls' })
  g:add_edge({ from = 'validate', to = 'dbQuery', kind = 'calls' })
  return g
end

describe('cartograph.focus.successors', function()
  it('returns the outgoing targets of a node', function()
    local s = focus.successors(sample(), 'getUser')
    assert.is_true(s.validate)
    assert.is_true(s.log)
    assert.is_nil(s.dbQuery) -- not a direct child
  end)

  it('is empty for a leaf and for an unknown node', function()
    assert.are.same({}, focus.successors(sample(), 'dbQuery'))
    assert.are.same({}, focus.successors(sample(), 'nope'))
  end)
end)

describe('cartograph.focus.step', function()
  local g = sample()

  it('seeds the path from an empty selection', function()
    assert.are.same({ 'getUser' }, focus.step({}, 'getUser', g))
    assert.are.same({ 'getUser' }, focus.step(nil, 'getUser', g))
  end)

  it('appends a child of the current tail', function()
    assert.are.same({ 'getUser', 'validate' }, focus.step({ 'getUser' }, 'validate', g))
    assert.are.same({ 'getUser', 'validate', 'dbQuery' }, focus.step({ 'getUser', 'validate' }, 'dbQuery', g))
  end)

  it('leaves the path unchanged when re-clicking the tail', function()
    assert.are.same({ 'getUser', 'validate' }, focus.step({ 'getUser', 'validate' }, 'validate', g))
  end)

  it('rewinds (truncates) when clicking a node already on the path', function()
    assert.are.same({ 'getUser' }, focus.step({ 'getUser', 'validate', 'dbQuery' }, 'getUser', g))
  end)

  it('starts a fresh path when clicking a node not connected to the tail', function()
    -- dbQuery is not a child of getUser
    assert.are.same({ 'dbQuery' }, focus.step({ 'getUser' }, 'dbQuery', g))
    assert.are.same({ 'orphan' }, focus.step({ 'getUser', 'validate' }, 'orphan', g))
  end)
end)

describe('cartograph.focus.overlay', function()
  local g = sample()

  it('lights the path plus the tail children, and reports the tail', function()
    local o = focus.overlay({ 'getUser' }, g)
    assert.is_true(o.active.getUser)
    assert.is_true(o.active.validate) -- child
    assert.is_true(o.active.log) -- child
    assert.is_nil(o.active.dbQuery) -- grandchild, not lit
    assert.is_nil(o.active.orphan)
    assert.are.equal('getUser', o.tail)
  end)

  it('keeps every node of the path active as it grows', function()
    local o = focus.overlay({ 'getUser', 'validate' }, g)
    assert.is_true(o.active.getUser)
    assert.is_true(o.active.validate)
    assert.is_true(o.active.dbQuery) -- child of tail
    assert.is_nil(o.active.log) -- sibling of validate dims once we advance
  end)

  it('carries breadcrumb name/kind for each path node', function()
    local o = focus.overlay({ 'getUser', 'validate' }, g)
    assert.are.equal(2, #o.path)
    assert.are.equal('getUser', o.path[1].id)
    assert.are.equal('getUser', o.path[1].name)
    assert.are.equal('action', o.path[1].kind)
    assert.are.equal('validate', o.path[2].id)
  end)

  it('ignores path ids missing from the graph (robust to graph replacement)', function()
    local o = focus.overlay({ 'ghost', 'getUser' }, g)
    assert.is_nil(o.active.ghost)
    assert.is_true(o.active.getUser)
    assert.are.equal('getUser', o.tail) -- last surviving node
    assert.are.equal(1, #o.path) -- ghost dropped from the breadcrumb
  end)

  it('returns an empty overlay for an empty path', function()
    local o = focus.overlay({}, g)
    assert.are.same({}, o.active)
    assert.are.same({}, o.path)
    assert.is_nil(o.tail)
  end)
end)
