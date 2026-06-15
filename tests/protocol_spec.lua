local protocol = require('cartograph.protocol')

-- A spy engine that records the calls the protocol routes to it.
local function spy_engine()
  local calls = {}
  local function record(name)
    return function(...)
      calls[#calls + 1] = { name = name, args = { ... } }
    end
  end
  return {
    calls = calls,
    set_root = record('set_root'),
    expand = record('expand'),
    compare = record('compare'),
    reveal = record('reveal'),
    save = record('save'),
    load = record('load'),
  }
end

describe('cartograph.protocol', function()
  it('routes setRoot to engine.set_root with the query', function()
    local eng = spy_engine()
    local res = protocol.dispatch({ action = 'setRoot', query = 'Foo' }, eng)
    assert.are.equal('ok', res.status)
    assert.are.equal(1, #eng.calls)
    assert.are.equal('set_root', eng.calls[1].name)
    assert.are.equal('Foo', eng.calls[1].args[1])
  end)

  it('routes expand and reveal by nodeId', function()
    local eng = spy_engine()
    protocol.dispatch({ action = 'expand', nodeId = 'a:1:2' }, eng)
    protocol.dispatch({ action = 'reveal', nodeId = 'a:1:2' }, eng)
    assert.are.equal('expand', eng.calls[1].name)
    assert.are.equal('a:1:2', eng.calls[1].args[1])
    assert.are.equal('reveal', eng.calls[2].name)
  end)

  it('routes compare with both roots', function()
    local eng = spy_engine()
    protocol.dispatch({ action = 'compare', rootA = 'A', rootB = 'B' }, eng)
    assert.are.equal('compare', eng.calls[1].name)
    assert.are.same({ 'A', 'B' }, eng.calls[1].args)
  end)

  it('routes save and load by name', function()
    local eng = spy_engine()
    protocol.dispatch({ action = 'save', name = 'm1' }, eng)
    protocol.dispatch({ action = 'load', name = 'm1' }, eng)
    assert.are.equal('save', eng.calls[1].name)
    assert.are.equal('load', eng.calls[2].name)
  end)

  it('errors on an unknown action without touching the engine', function()
    local eng = spy_engine()
    local res = protocol.dispatch({ action = 'launchMissiles' }, eng)
    assert.are.equal('error', res.status)
    assert.is_truthy(res.message:find('unknown'))
    assert.are.equal(0, #eng.calls)
  end)

  it('errors when a required parameter is missing', function()
    local eng = spy_engine()
    local res = protocol.dispatch({ action = 'expand' }, eng)
    assert.are.equal('error', res.status)
    assert.are.equal(0, #eng.calls)
  end)

  it('decodes a raw JSON string and routes it', function()
    local eng = spy_engine()
    local res = protocol.handle('{"action":"setRoot","query":"Foo"}', eng)
    assert.are.equal('ok', res.status)
    assert.are.equal('set_root', eng.calls[1].name)
  end)

  it('errors on malformed JSON', function()
    local eng = spy_engine()
    local res = protocol.handle('{not json', eng)
    assert.are.equal('error', res.status)
    assert.are.equal(0, #eng.calls)
  end)
end)
