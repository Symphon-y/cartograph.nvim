local layer = require('cartograph.layer')
local graph_mod = require('cartograph.graph')

-- A representative CLEAN config like config.lua ships, kept local so the spec is
-- independent of the shipped defaults.
local function cfg()
  return {
    layers = { 'UI', 'Adapters', 'Application', 'Domain', 'Infrastructure' },
    patterns = {
      Domain = { '/domain/', '/entities/' },
      Application = { '/application/', '/usecases/' },
      Adapters = { '/controllers/', '/api/' },
      Infrastructure = { '/infrastructure/', '/persistence/' },
      UI = { '/web/', '/components/' },
    },
    overrides = {},
    kind_fallback = {
      controller = 'Adapters',
      action = 'Application',
      service = 'Application',
      type = 'Domain',
      field = 'Domain',
      call = 'UI',
      store = 'UI',
      endpoint = 'Adapters',
    },
  }
end

describe('cartograph.layer.classify', function()
  it('classifies by directory pattern (case-insensitive)', function()
    assert.are.equal('Domain', layer.classify({ kind = 'type', file = '/repo/src/Domain/User.cs' }, cfg()))
    assert.are.equal('Application', layer.classify({ kind = 'action', file = '/repo/src/Application/Create.cs' }, cfg()))
    assert.are.equal('Adapters', layer.classify({ kind = 'controller', file = '/repo/src/API/UsersController.cs' }, cfg()))
  end)

  it('prefers an explicit override over a directory pattern', function()
    local c = cfg()
    c.overrides = { ['legacy/.*%.cs$'] = 'Infrastructure' }
    -- path also matches the Domain pattern, but the override wins.
    assert.are.equal('Infrastructure', layer.classify({ kind = 'type', file = '/repo/legacy/domain/Old.cs' }, c))
  end)

  it('respects layer order when several patterns could match', function()
    local c = cfg()
    -- file sits under both /api/ (Adapters) and /domain/ — Adapters is earlier.
    assert.are.equal('Adapters', layer.classify({ kind = 'type', file = '/repo/api/domain/Thing.cs' }, c))
  end)

  it('falls back to the kind mapping when no path matches', function()
    assert.are.equal('Domain', layer.classify({ kind = 'type', file = '/repo/misc/Thing.cs' }, cfg()))
    assert.are.equal('UI', layer.classify({ kind = 'call', file = '/repo/misc/thing.ts' }, cfg()))
  end)

  it('uses the kind fallback even when a node has no file', function()
    assert.are.equal('Domain', layer.classify({ kind = 'type' }, cfg()))
  end)

  it('returns "unknown" when neither path nor kind matches', function()
    assert.are.equal('unknown', layer.classify({ kind = 'mystery', file = '/repo/misc/Thing.cs' }, cfg()))
    assert.are.equal('unknown', layer.classify({}, cfg()))
  end)
end)

describe('cartograph.layer.annotate', function()
  it('stamps a layer on every node of a graph', function()
    local g = graph_mod.new()
    g:add_node({ id = 'a', kind = 'controller', name = 'UsersController', file = '/r/api/Users.cs' })
    g:add_node({ id = 'b', kind = 'type', name = 'User', file = '/r/domain/User.cs' })
    layer.annotate(g, cfg())
    assert.are.equal('Adapters', g:get_node('a').layer)
    assert.are.equal('Domain', g:get_node('b').layer)
  end)
end)
