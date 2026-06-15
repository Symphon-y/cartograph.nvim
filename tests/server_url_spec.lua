local server = require('cartograph.server')

describe('cartograph.server.build_url', function()
  it('builds a base url with no token or params', function()
    assert.are.equal(
      'http://127.0.0.1:8080/',
      server.build_url({ host = '127.0.0.1', port = 8080, path = '/' })
    )
  end)

  it('puts the token first, then params sorted by key', function()
    local url = server.build_url({
      host = '127.0.0.1',
      port = 8080,
      token = 'abc',
      path = '/',
      params = { theme = 'dark', layout = 'dagre' },
    })
    assert.are.equal('http://127.0.0.1:8080/?token=abc&layout=dagre&theme=dark', url)
  end)

  it('omits an empty token', function()
    local url = server.build_url({ host = '127.0.0.1', port = 8080, token = '', path = '/', params = { theme = 'light' } })
    assert.are.equal('http://127.0.0.1:8080/?theme=light', url)
  end)

  it('percent-encodes reserved characters in param values', function()
    local url = server.build_url({
      host = '127.0.0.1', port = 8080, path = '/',
      params = { q = 'hello world & more' },
    })
    assert.are.equal('http://127.0.0.1:8080/?q=hello%20world%20%26%20more', url)
  end)
end)
