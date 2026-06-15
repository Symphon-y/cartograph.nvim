local graph = require('cartograph.graph')
local compare = require('cartograph.compare')

-- Build a small graph from { nodes = {{id,kind,name}}, edges = {{from,to,kind}} }.
local function make(spec)
  local g = graph.new()
  for _, n in ipairs(spec.nodes) do
    g:add_node(n)
  end
  for _, e in ipairs(spec.edges or {}) do
    g:add_edge(e)
  end
  return g
end

describe('cartograph.compare.diff', function()
  local a = make({
    nodes = { { id = 'x', kind = 'endpoint', name = 'X' }, { id = 'y', kind = 'action', name = 'Y' } },
    edges = { { from = 'x', to = 'y', kind = 'calls' } },
  })
  local b = make({
    nodes = { { id = 'y', kind = 'action', name = 'Y' }, { id = 'z', kind = 'type', name = 'Z' } },
    edges = { { from = 'y', to = 'z', kind = 'typeof' } },
  })

  it('tags nodes as a / b / both', function()
    local d = compare.diff(a, b)
    local side = {}
    for _, n in ipairs(d.nodes) do
      side[n.id] = n.side
    end
    assert.are.equal('a', side.x)
    assert.are.equal('both', side.y)
    assert.are.equal('b', side.z)
  end)

  it('tags edges by membership', function()
    local d = compare.diff(a, b)
    local eside = {}
    for _, e in ipairs(d.edges) do
      eside[e.from .. '->' .. e.to] = e.side
    end
    assert.are.equal('a', eside['x->y'])
    assert.are.equal('b', eside['y->z'])
  end)

  it('summarizes shared / only-a / only-b counts', function()
    local d = compare.diff(a, b)
    assert.are.same({ shared = 1, only_a = 1, only_b = 1 }, d.summary)
  end)

  it('marks an edge present on both sides as shared', function()
    local a2 = make({ nodes = { { id = 'p', kind = 'action', name = 'P' }, { id = 'q', kind = 'type', name = 'Q' } }, edges = { { from = 'p', to = 'q', kind = 'typeof' } } })
    local b2 = make({ nodes = { { id = 'p', kind = 'action', name = 'P' }, { id = 'q', kind = 'type', name = 'Q' } }, edges = { { from = 'p', to = 'q', kind = 'typeof' } } })
    local d = compare.diff(a2, b2)
    assert.are.equal('both', d.edges[1].side)
    assert.are.same({ shared = 2, only_a = 0, only_b = 0 }, d.summary)
  end)

  it('emits nodes deterministically (sorted by id) and does not mutate inputs', function()
    local d = compare.diff(a, b)
    assert.are.same({ 'x', 'y', 'z' }, { d.nodes[1].id, d.nodes[2].id, d.nodes[3].id })
    -- inputs untouched: a still has no 'side' leaking onto its stored nodes
    assert.is_nil(a:get_node('x').side)
  end)
end)
