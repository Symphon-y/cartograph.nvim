-- cartograph.adapters.dotnet — extract .NET HTTP routes from C# source.
--
-- Pure text extraction (no Treesitter dependency, so it is unit-testable and
-- works without the c_sharp parser installed). Handles attribute routing on
-- [ApiController] classes — class-level [Route], [HttpVerb("template")] on
-- actions, [controller]/[action] token substitution, route params — and the
-- minimal-API app.MapVerb("...") style. Treesitter can refine this later
-- without changing the entry shape it produces.

local M = {}

local route = require('cartograph.route')

local HTTP_VERBS = { Get = 'GET', Post = 'POST', Put = 'PUT', Delete = 'DELETE', Patch = 'PATCH' }

function M.handles(file)
  return file:match('%.cs$') ~= nil
end

-- Short controller name used for the [controller] token (class name minus the
-- conventional "Controller" suffix).
local function controller_token(class_name)
  return (class_name:gsub('Controller$', ''))
end

-- Join a class route template with an action template and resolve the
-- [controller]/[action] tokens. An action template starting with '/' is
-- absolute and ignores the class route (ASP.NET semantics).
local function combine(class_route, action_tmpl, controller, action)
  local full
  if action_tmpl and action_tmpl:sub(1, 1) == '/' then
    full = action_tmpl
  elseif action_tmpl and action_tmpl ~= '' then
    full = (class_route or '') .. '/' .. action_tmpl
  else
    full = class_route or ''
  end
  full = full:gsub('%[[Cc]ontroller%]', controller_token(controller or ''))
  full = full:gsub('%[[Aa]ction%]', action or '')
  return full
end

local function add(routes, info)
  info.lang = 'cs'
  info.kind = 'endpoint'
  info.norm = route.normalize(info.path)
  routes[#routes + 1] = info
end

function M.extract(source, file)
  local routes = {}

  local lines = vim.split(source, '\n', { plain = true })
  local class_name, class_route
  local pending_route -- a [Route("...")] seen but not yet attached to a class
  local pending = {} -- queued { verb, template, line } http attrs for the next method

  for i, line in ipairs(lines) do
    -- Class-level / standalone [Route("...")]
    local rt = line:match('%[Route%(%s*"([^"]*)"')
    -- Http verb attribute, with or without a template.
    local verb, tmpl = line:match('%[Http(%a+)%(%s*"([^"]*)"')
    if not verb then
      verb = line:match('%[Http(%a+)%]')
    end

    -- minimal API: app.MapGet("/path", ...)
    local map_verb, map_path = line:match('%.Map(%a+)%(%s*"([^"]+)"')
    if map_verb and HTTP_VERBS[map_verb] then
      add(routes, { method = HTTP_VERBS[map_verb], path = map_path, file = file, line = i })
    end

    if verb and HTTP_VERBS[verb] then
      pending[#pending + 1] = { method = HTTP_VERBS[verb], template = tmpl, line = i }
    elseif rt then
      pending_route = rt
    end

    -- Class declaration: attach the most recent pending [Route] as its base.
    local cls = line:match('class%s+([%w_]+)')
    if cls and (line:match('Controller') or pending_route) then
      class_name = cls
      class_route = pending_route
      pending_route = nil
      pending = {}
    end

    -- Action method: `public <ret> Name(`. Flush queued http attrs against it.
    local method_name = line:match('public%s+[%w_<>%[%]%.,%s]-%s+([%w_]+)%s*%(')
    if method_name and method_name ~= class_name and #pending > 0 then
      for _, attr in ipairs(pending) do
        add(routes, {
          method = attr.method,
          path = combine(class_route, attr.template, class_name, method_name),
          controller = class_name and controller_token(class_name) or nil,
          action = method_name,
          file = file,
          line = attr.line,
        })
      end
      pending = {}
    end
  end

  return routes
end

return M
