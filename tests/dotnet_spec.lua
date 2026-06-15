local dotnet = require('cartograph.adapters.dotnet')

local CONTROLLER = [[
using Microsoft.AspNetCore.Mvc;

namespace Api.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ValidationController : ControllerBase
    {
        private readonly IValidationStore _store;

        public ValidationController(IValidationStore store)
        {
            _store = store;
        }

        [HttpGet("validate")]
        public ActionResult<ValidationDto> Validate()
        {
            return _store.Check();
        }

        [HttpPost]
        public IActionResult Create([FromBody] ValidationDto dto)
        {
            return Ok();
        }

        [HttpDelete("{id:int}")]
        public IActionResult Remove(int id)
        {
            return NoContent();
        }
    }
}
]]

local MINIMAL_API = [[
var app = builder.Build();
app.MapGet("/api/health", () => "ok");
app.MapPost("/api/login", (LoginDto dto) => Results.Ok());
]]

describe('cartograph.adapters.dotnet', function()
  local function by_action(routes, name)
    for _, r in ipairs(routes) do
      if r.action == name then
        return r
      end
    end
  end

  it('combines class [Route] with action templates and substitutes [controller]', function()
    local routes = dotnet.extract(CONTROLLER, 'ValidationController.cs')
    local validate = by_action(routes, 'Validate')
    assert.is_truthy(validate)
    assert.are.equal('GET', validate.method)
    assert.are.equal('api/validation/validate', validate.norm.str)
    assert.are.equal('Validation', validate.controller)
    assert.are.equal('cs', validate.lang)
    assert.is_true(validate.line > 0)
  end)

  it('handles an action attribute with no template (controller route only)', function()
    local routes = dotnet.extract(CONTROLLER, 'ValidationController.cs')
    local create = by_action(routes, 'Create')
    assert.are.equal('POST', create.method)
    assert.are.equal('api/validation', create.norm.str)
  end)

  it('turns route params into wildcards', function()
    local routes = dotnet.extract(CONTROLLER, 'ValidationController.cs')
    local remove = by_action(routes, 'Remove')
    assert.are.equal('DELETE', remove.method)
    assert.are.equal('api/validation/*', remove.norm.str)
  end)

  it('extracts minimal-API MapGet/MapPost endpoints', function()
    local routes = dotnet.extract(MINIMAL_API, 'Program.cs')
    assert.are.equal(2, #routes)
    assert.are.equal('GET', routes[1].method)
    assert.are.equal('api/health', routes[1].norm.str)
    assert.are.equal('POST', routes[2].method)
    assert.are.equal('api/login', routes[2].norm.str)
  end)

  it('captures [Route] when it appears on the same line as the class declaration', function()
    local src = [[
[Route("api/[controller]")] public class ItemsController : ControllerBase
{
    [HttpGet("list")]
    public IActionResult List() => Ok();
}
]]
    local routes = dotnet.extract(src, 'ItemsController.cs')
    assert.are.equal(1, #routes)
    assert.are.equal('GET', routes[1].method)
    assert.are.equal('api/items/list', routes[1].norm.str)
  end)

  it('reports the language it handles', function()
    assert.is_true(dotnet.handles('Foo.cs'))
    assert.is_false(dotnet.handles('foo.ts'))
  end)
end)
