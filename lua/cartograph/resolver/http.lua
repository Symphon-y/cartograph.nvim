-- cartograph.resolver.http — the cross-stack bridge (Vue <-> .NET).
--
-- Builds a route table from the .NET endpoints in the index and matches it
-- against the Vue/TS request call-sites by normalized method+path, producing
-- `routes-to` edges. All the heuristic matching lives in cartograph.route; this
-- module turns its rankings into graph nodes/edges and seeds maps from an
-- endpoint. Config supplies base-URL stripping and explicit route overrides.

local M = {}

local route = require('cartograph.route')
local graph_mod = require('cartograph.graph')

local function http_options(opts)
  opts = opts or {}
  if opts.bases and opts.overrides then
    return opts
  end
  local cfg = require('cartograph.config').options.http
  return {
    bases = opts.bases or cfg.base_urls,
    overrides = opts.overrides or cfg.route_overrides,
  }
end

local function range_at(line)
  return { start = { line = math.max((line or 1) - 1, 0), character = 0 } }
end

-- Build a graph node for a .NET endpoint. Its file/line point at the action, so
-- reveal-in-editor and LSP expand work straight off it.
function M.endpoint_node(e)
  return {
    id = ('endpoint:%s:%s@%s:%d'):format(e.method, e.norm.str, e.file or '', e.line or 0),
    kind = 'endpoint',
    name = e.method .. ' /' .. e.norm.str,
    file = e.file,
    range = range_at(e.line),
    lang = e.lang,
    meta = { method = e.method, path = e.norm.str, controller = e.controller, action = e.action },
  }
end

-- Build a graph node for a frontend request call-site.
function M.call_node(c)
  return {
    id = ('call:%s:%s@%s:%d'):format(c.method, c.url, c.file or '', c.line or 0),
    kind = 'call',
    name = c.method .. ' ' .. c.url,
    file = c.file,
    range = range_at(c.line),
    lang = c.lang,
    meta = { method = c.method, url = c.url },
  }
end

-- A route view route.match understands (segments + method + str), tagged with
-- the source endpoint so we can recover it from a ranking.
local function endpoint_views(endpoints)
  local views = {}
  for _, e in ipairs(endpoints) do
    views[#views + 1] = { method = e.method, segments = e.norm.segments, str = e.norm.str, _src = e }
  end
  return views
end

-- Rank the endpoints a single call could route to (applying base stripping and
-- explicit overrides). Returns { ranked, ambiguous } where ranked is the
-- route.match result.
function M.candidates_for(call, endpoints, opts)
  opts = http_options(opts)
  local views = endpoint_views(endpoints)

  -- An explicit override pins the call to a specific normalized backend route.
  local override = opts.overrides[call.url] or opts.overrides[call.norm and call.norm.str]
  if override then
    local target = route.normalize(override).str
    for _, v in ipairs(views) do
      if v.str == target then
        return { ranked = { { route = v, score = math.huge } }, ambiguous = false }
      end
    end
  end

  local call_view = {
    method = call.method,
    segments = route.normalize(call.url, opts.bases).segments,
  }
  local ranked = route.match(call_view, views)
  return { ranked = ranked, ambiguous = route.is_ambiguous(ranked) }
end

-- Link every call in the index to its best-matching endpoint, returning a graph
-- of routes-to edges plus a structured list of links (with ambiguity flags).
function M.link(index, opts)
  opts = http_options(opts)
  local g = graph_mod.new()
  local links = {}

  for _, call in ipairs(index.calls) do
    local result = M.candidates_for(call, index.endpoints, opts)
    local best = result.ranked[1]
    if best then
      local cnode = M.call_node(call)
      local enode = M.endpoint_node(best.route._src)
      g:add_node(cnode)
      g:add_node(enode)
      g:add_edge({ from = cnode.id, to = enode.id, kind = 'routes-to' })
      links[#links + 1] = {
        call = call,
        endpoint = best.route._src,
        ambiguous = result.ambiguous,
        candidates = result.ranked,
      }
    end
  end

  return g, links
end

-- Seed a map rooted at an endpoint matched from `query` (e.g. "GET /api/x" or
-- just "/api/x"). Returns graph, root_node, info{ ambiguous, candidates }.
function M.from_endpoint(index, query, opts)
  opts = http_options(opts)
  local method, path = query:match('^%s*(%u+)%s+(.+)$')
  if not method then
    path = query
  end

  local call_view = {
    method = route.normalize_method(method),
    segments = route.normalize(path, opts.bases).segments,
  }
  -- When no method was given, match path-only (ignore endpoint method).
  if not method then
    call_view.method = nil
  end

  local ranked = route.match(call_view, endpoint_views(index.endpoints))
  local best = ranked[1]
  if not best then
    return nil, nil, { ambiguous = false, candidates = {} }
  end

  local g = graph_mod.new()
  local root = M.endpoint_node(best.route._src)
  g:add_node(root)

  -- Attach the frontend calls that route to this same endpoint.
  for _, call in ipairs(index.calls) do
    local res = M.candidates_for(call, index.endpoints, opts)
    if res.ranked[1] and M.endpoint_node(res.ranked[1].route._src).id == root.id then
      local cnode = M.call_node(call)
      g:add_node(cnode)
      g:add_edge({ from = cnode.id, to = root.id, kind = 'routes-to' })
    end
  end

  return g, root, { ambiguous = route.is_ambiguous(ranked), candidates = ranked }
end

return M
