local sse = require('cartograph.sse')

describe('cartograph.sse', function()
  describe('format', function()
    it('formats a string payload as an SSE event', function()
      assert.are.equal('event: status\ndata: hello\n\n', sse.format('status', 'hello'))
    end)

    it('json-encodes table payloads', function()
      local out = sse.format('graph:update', { nodes = {}, edges = {} })
      assert.is_truthy(out:match('^event: graph:update\n'))
      assert.is_truthy(out:find('data: ', 1, true))
      local data = out:match('data: (.-)\n\n$')
      assert.are.same({ nodes = {}, edges = {} }, vim.json.decode(data))
    end)

    it('splits multi-line data into multiple data: lines per the SSE spec', function()
      local out = sse.format('log', 'line1\nline2')
      assert.are.equal('event: log\ndata: line1\ndata: line2\n\n', out)
    end)
  end)

  it('exposes SSE response headers for the stream handshake', function()
    local head = sse.headers()
    assert.is_truthy(head:find('text/event%-stream'))
    assert.is_truthy(head:lower():find('cache%-control: no%-cache'))
  end)

  describe('hub', function()
    local function fake_client()
      return { writes = {}, write = function(self, s) self.writes[#self.writes + 1] = s; return true end }
    end

    it('broadcasts a single formatted event to every client', function()
      local hub = sse.new_hub()
      local a, b = fake_client(), fake_client()
      hub:add(a)
      hub:add(b)
      assert.are.equal(2, hub:count())
      hub:broadcast('status', 'ready')
      assert.are.equal('event: status\ndata: ready\n\n', a.writes[1])
      assert.are.equal(a.writes[1], b.writes[1])
    end)

    it('stops writing to removed clients', function()
      local hub = sse.new_hub()
      local a = fake_client()
      hub:add(a)
      hub:remove(a)
      assert.are.equal(0, hub:count())
      hub:broadcast('status', 'x')
      assert.are.equal(0, #a.writes)
    end)

    it('prunes clients whose write fails', function()
      local hub = sse.new_hub()
      local dead = { write = function() return false end }
      hub:add(dead)
      hub:broadcast('status', 'x')
      assert.are.equal(0, hub:count())
    end)

    it('close_all closes every client handle and empties the registry', function()
      local hub = sse.new_hub()
      local closed = {}
      local function fake_uv_client(id)
        return {
          handle = {
            is_closing = function() return false end,
            close      = function() closed[#closed + 1] = id end,
          },
        }
      end
      hub:add(fake_uv_client('a'))
      hub:add(fake_uv_client('b'))
      hub:close_all()
      assert.are.equal(2, #closed)
      assert.are.equal(0, hub:count())
    end)
  end)
end)
