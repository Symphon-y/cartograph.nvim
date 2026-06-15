local route = require('cartograph.route')

describe('cartograph.route.normalize', function()
  it('lowercases, trims slashes and splits into segments', function()
    local n = route.normalize('/Api/Validation/')
    assert.are.same({ 'api', 'validation' }, n.segments)
    assert.are.equal('api/validation', n.str)
  end)

  it('collapses repeated slashes', function()
    assert.are.equal('api/validation', route.normalize('api//validation').str)
  end)

  it('drops a query string', function()
    assert.are.equal('api/users', route.normalize('/api/users?active=1').str)
  end)

  it('turns .NET route params into single-segment wildcards', function()
    assert.are.equal('api/users/*', route.normalize('api/users/{id}').str)
    assert.are.equal('api/users/*', route.normalize('api/users/{id:int}').str)
    assert.are.equal('files/*', route.normalize('files/{*path}').str)
  end)

  it('turns Vue/Express :params and template interpolations into wildcards', function()
    assert.are.equal('api/users/*', route.normalize('/api/users/:id').str)
    assert.are.equal('api/users/*', route.normalize('/api/users/${userId}').str)
    assert.are.equal('api/users/*/posts', route.normalize('/api/users/${userId}/posts').str)
    -- a segment that mixes literal + interpolation collapses to a wildcard
    assert.are.equal('api/*', route.normalize('/api/user-${id}').str)
  end)

  it('strips a configured base URL or prefix', function()
    local bases = { 'https://localhost:5001', '/api' }
    assert.are.equal('validation/validate', route.normalize('https://localhost:5001/validation/validate', bases).str)
    assert.are.equal('users', route.normalize('/api/users', bases).str)
  end)
end)

describe('cartograph.route.normalize_method', function()
  it('uppercases and defaults to GET', function()
    assert.are.equal('POST', route.normalize_method('post'))
    assert.are.equal('GET', route.normalize_method(nil))
  end)
end)

describe('cartograph.route.match', function()
  -- Build a normalized route entry the way an adapter would.
  local function entry(method, path)
    local n = route.normalize(path)
    return { method = route.normalize_method(method), segments = n.segments, str = n.str, path = path }
  end

  local function call(method, path)
    local n = route.normalize(path)
    return { method = route.normalize_method(method), segments = n.segments }
  end

  it('matches by method and path, ranking concrete routes above wildcards', function()
    local routes = {
      entry('GET', 'api/users/{id}'),
      entry('GET', 'api/users/me'),
      entry('POST', 'api/users'),
    }
    local res = route.match(call('GET', '/api/users/me'), routes)
    -- both the literal /me and the /{id} wildcard match; literal ranks first
    assert.are.equal('api/users/me', res[1].route.str)
    assert.are.equal('api/users/*', res[2].route.str)
    assert.is_true(res[1].score > res[2].score)
  end)

  it('excludes routes with the wrong method or arity', function()
    local routes = {
      entry('POST', 'api/users'),
      entry('GET', 'api/users/{id}'),
    }
    -- GET /api/users matches neither (POST method / extra segment)
    assert.are.equal(0, #route.match(call('GET', '/api/users'), routes))
  end)

  it('flags ambiguity when the top candidates tie', function()
    local routes = {
      entry('GET', 'api/{resource}/{id}'),
      entry('GET', 'api/users/{id}'),
    }
    local res = route.match(call('GET', '/api/users/42'), routes)
    assert.are.equal(2, #res)
    -- api/users/* is more specific (one more literal) so it wins, not a tie
    assert.are.equal('api/users/*', res[1].route.str)
    assert.is_false(route.is_ambiguous(res))
  end)

  it('reports a true tie as ambiguous', function()
    local routes = {
      entry('GET', 'a/{x}'),
      entry('GET', 'b/{y}'),
    }
    -- only one can match a given call, but craft a genuine tie:
    local tie = {
      entry('GET', 'api/{a}/x'),
      entry('GET', 'api/{b}/x'),
    }
    local res = route.match(call('GET', '/api/thing/x'), tie)
    assert.are.equal(2, #res)
    assert.is_true(route.is_ambiguous(res))
  end)
end)
