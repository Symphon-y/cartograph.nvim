-- End-to-end bridge test: scan the minimal Vue + .NET fixture workspace, link
-- the call-sites to the routes, and assert the routes-to edges connect the
-- right pairs. Exercises index + adapters + route + resolver/http together.

local index = require('cartograph.index')
local http = require('cartograph.resolver.http')

local function fixtures_root()
  local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h')
  return here .. '/fixtures'
end

describe('cartograph bridge (end-to-end over fixtures)', function()
  local idx
  before_each(function()
    index.clear()
    idx = index.build(fixtures_root())
  end)

  it('indexes the .NET endpoints and Vue call-sites', function()
    assert.are.equal(3, #idx.endpoints) -- Validate, Create, Remove
    assert.are.equal(3, #idx.calls) -- check, create, remove
  end)

  it('links each call to its matching endpoint with a routes-to edge', function()
    local g, links = http.link(idx, { bases = {}, overrides = {} })
    assert.are.equal(3, #links)
    -- 3 calls + 3 endpoints, 3 edges
    assert.are.equal(6, g:node_count())
    assert.are.equal(3, g:edge_count())
    for _, edge in ipairs(g:serialize().edges) do
      assert.are.equal('routes-to', edge.kind)
    end
  end)

  it('routes GET /validate to the Validate action, not the wildcard delete', function()
    local _, links = http.link(idx, { bases = {}, overrides = {} })
    local function endpoint_for(method, url)
      for _, l in ipairs(links) do
        if l.call.method == method and l.call.url == url then
          return l.endpoint
        end
      end
    end
    assert.are.equal('Validate', endpoint_for('GET', '/api/validation/validate').action)
    assert.are.equal('Create', endpoint_for('POST', '/api/validation').action)
    assert.are.equal('Remove', endpoint_for('DELETE', '/api/validation/${id}').action)
  end)

  it('seeds a map rooted at an endpoint matched by query', function()
    local g, root, info = http.from_endpoint(idx, 'GET /api/validation/validate', { bases = {}, overrides = {} })
    assert.is_truthy(root)
    assert.are.equal('endpoint', root.kind)
    assert.are.equal('Validate', root.meta.action)
    assert.is_false(info.ambiguous)
    -- the one frontend call that hits this endpoint is attached
    assert.are.equal(2, g:node_count())
    assert.are.equal(1, g:edge_count())
  end)
end)
