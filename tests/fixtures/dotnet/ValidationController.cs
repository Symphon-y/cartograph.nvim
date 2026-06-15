using Microsoft.AspNetCore.Mvc;

namespace Sample.Api.Controllers
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
