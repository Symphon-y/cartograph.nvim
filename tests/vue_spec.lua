local vue = require('cartograph.adapters.vue')

local SOURCE = [[
import axios from 'axios'

const API = 'https://localhost:5001'

export const validationApi = {
  check() {
    return axios.get('/api/validation/validate')
  },
  create(dto) {
    return axios.post('/api/validation', dto)
  },
  remove(id) {
    return axios.delete(`/api/validation/${id}`)
  },
  health() {
    return fetch('/api/health')
  },
  login(body) {
    return fetch('/api/login', { method: 'POST', body })
  },
  legacy() {
    return this.$http.put('/api/legacy/thing')
  },
}
]]

describe('cartograph.adapters.vue', function()
  local function by_method_path(calls, method, str)
    for _, c in ipairs(calls) do
      if c.method == method and c.norm.str == str then
        return c
      end
    end
  end

  it('extracts axios verb call-sites with method + url', function()
    local calls = vue.extract(SOURCE, 'validationApi.ts')
    local check = by_method_path(calls, 'GET', 'api/validation/validate')
    assert.is_truthy(check)
    assert.are.equal('/api/validation/validate', check.url)
    assert.are.equal('typescript', check.lang)
    assert.is_true(check.line > 0)

    assert.is_truthy(by_method_path(calls, 'POST', 'api/validation'))
  end)

  it('turns template-literal interpolations into wildcards', function()
    local calls = vue.extract(SOURCE, 'validationApi.ts')
    assert.is_truthy(by_method_path(calls, 'DELETE', 'api/validation/*'))
  end)

  it('extracts fetch with a default GET and an explicit method', function()
    local calls = vue.extract(SOURCE, 'validationApi.ts')
    assert.is_truthy(by_method_path(calls, 'GET', 'api/health'))
    assert.is_truthy(by_method_path(calls, 'POST', 'api/login'))
  end)

  it('extracts $http verb calls', function()
    local calls = vue.extract(SOURCE, 'validationApi.ts')
    assert.is_truthy(by_method_path(calls, 'PUT', 'api/legacy/thing'))
  end)

  it('ignores non-URL string method calls (e.g. map.get("key"))', function()
    local calls = vue.extract([[const x = cache.get('some-key'); arr.post('nope')]], 'x.ts')
    assert.are.equal(0, #calls)
  end)

  it('reports the files it handles', function()
    assert.is_true(vue.handles('Foo.vue'))
    assert.is_true(vue.handles('api.ts'))
    assert.is_true(vue.handles('store.js'))
    assert.is_false(vue.handles('Foo.cs'))
  end)
end)
