-- cartograph.sse — Server-Sent Events: pure event formatting + a client hub.
--
-- The browser holds one long-lived GET to the SSE endpoint; nvim pushes graph
-- updates down it. Formatting is pure (testable); the hub tracks live client
-- writers and broadcasts to all of them, pruning any that fail to write.

local M = {}

-- Format an event for the SSE wire. `data` is JSON-encoded when it's a table;
-- multi-line strings are split into one `data:` line each, per the spec.
function M.format(event, data)
  if type(data) ~= 'string' then
    data = vim.json.encode(data)
  end
  local out = { 'event: ' .. event }
  for line in (data .. '\n'):gmatch('(.-)\n') do
    out[#out + 1] = 'data: ' .. line
  end
  return table.concat(out, '\n') .. '\n\n'
end

-- The HTTP response head that opens an SSE stream. The body (events) follows.
function M.headers()
  return table.concat({
    'HTTP/1.1 200 OK',
    'Content-Type: text/event-stream',
    'Cache-Control: no-cache',
    'Connection: keep-alive',
    '',
    '',
  }, '\r\n')
end

local Hub = {}
Hub.__index = Hub

-- A client is any object exposing `write(self, str) -> boolean`. In the server
-- that wraps a uv TCP handle; in tests it's a table that records writes.
function M.new_hub()
  return setmetatable({ clients = {} }, Hub)
end

function Hub:add(client)
  self.clients[client] = true
end

function Hub:remove(client)
  self.clients[client] = nil
end

function Hub:count()
  local n = 0
  for _ in pairs(self.clients) do
    n = n + 1
  end
  return n
end

-- Format once, write to every client, drop any whose write fails.
function Hub:broadcast(event, data)
  local payload = M.format(event, data)
  for client in pairs(self.clients) do
    local ok = client:write(payload)
    if not ok then
      self.clients[client] = nil
    end
  end
end

return M
