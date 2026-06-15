-- End-to-end focus path: the bridge engine method -> session state ->
-- state.broadcast_focus -> server broadcast. Uses a fake server to capture the
-- focus:update overlays the browser would receive.

local state = require('cartograph.state')
local bridge = require('cartograph.bridge')
local graph_mod = require('cartograph.graph')

local function sample_graph()
  local g = graph_mod.new()
  for _, n in ipairs({ 'getUser', 'validate', 'dbQuery', 'log' }) do
    g:add_node({ id = n, kind = 'action', name = n })
  end
  g:add_edge({ from = 'getUser', to = 'validate', kind = 'calls' })
  g:add_edge({ from = 'getUser', to = 'log', kind = 'calls' })
  g:add_edge({ from = 'validate', to = 'dbQuery', kind = 'calls' })
  return g
end

local function setup()
  local events = {}
  local fake_server = {
    broadcast = function(_, event, data)
      events[#events + 1] = { event = event, data = data }
    end,
  }
  state.new()
  state.session.graph = sample_graph()
  state.session.server = fake_server
  local engine = bridge.engine({ server = fake_server })
  local function last_focus()
    for i = #events, 1, -1 do
      if events[i].event == 'focus:update' then
        return events[i].data
      end
    end
  end
  return engine, last_focus
end

describe('cartograph focus engine', function()
  after_each(function()
    state.clear()
  end)

  it('broadcasts a focus overlay lighting the clicked node and its children', function()
    local engine, last_focus = setup()
    engine.focus('getUser')
    local o = last_focus()
    assert.is_truthy(o)
    assert.is_true(o.active.getUser)
    assert.is_true(o.active.validate)
    assert.is_true(o.active.log)
    assert.is_nil(o.active.dbQuery)
    assert.are.equal(1, #o.path)
    assert.are.equal('getUser', o.path[1].name)
  end)

  it('accumulates the path when clicking a child', function()
    local engine, last_focus = setup()
    engine.focus('getUser')
    engine.focus('validate')
    local o = last_focus()
    assert.are.equal(2, #o.path)
    assert.are.equal('validate', o.tail)
    assert.is_true(o.active.dbQuery) -- child of the new tail
    assert.is_nil(o.active.log) -- sibling dims once we advance
  end)

  it('rewinds when clicking a node already on the path', function()
    local engine, last_focus = setup()
    engine.focus('getUser')
    engine.focus('validate')
    engine.focus('getUser')
    assert.are.equal(1, #last_focus().path)
    assert.are.equal('getUser', last_focus().tail)
  end)

  it('clears the overlay on clear_focus', function()
    local engine, last_focus = setup()
    engine.focus('getUser')
    engine.clear_focus()
    local o = last_focus()
    assert.are.same({}, o.path)
    assert.is_nil(state.session.focus)
  end)
end)
