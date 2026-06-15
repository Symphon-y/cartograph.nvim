-- cartograph.route — pure URL route normalization + heuristic matching.
--
-- The cross-stack bridge has no ground-truth link between a frontend request
-- string and a backend route, so it normalizes both sides aggressively and
-- ranks candidates by specificity. This module is that shared, pure core; both
-- the adapters (when building entries) and resolver/http (when linking) use it,
-- which keeps the normalization rules in exactly one place.

local M = {}

-- Does a single path segment denote a parameter (wildcard) rather than a
-- literal? Covers .NET ({id}, {id:int}, {*catchall}), Express/Vue (:id) and
-- template interpolation (${var}, or any literal mixed with one).
local function is_param_segment(seg)
  return seg:find('{', 1, true) ~= nil -- {id}, {id:int}, user-${id}
    or seg:sub(1, 1) == ':' -- :id
    or seg:find('%$') ~= nil -- ${var}
end

-- Normalize a path (optionally stripping configured base URLs/prefixes) into
-- { str, segments }. Parameter segments become '*'.
function M.normalize(path, bases)
  path = path or ''

  -- Drop a query string / fragment.
  path = path:gsub('[?#].*$', '')

  -- Strip the longest matching configured base (case-insensitive prefix).
  if bases then
    local lower = path:lower()
    local best = ''
    for _, base in ipairs(bases) do
      local b = base:lower()
      if #b > #best and lower:sub(1, #b) == b then
        best = b
      end
    end
    if best ~= '' then
      path = path:sub(#best + 1)
    end
  end

  path = path:lower()

  local segments = {}
  for seg in path:gmatch('[^/]+') do
    segments[#segments + 1] = is_param_segment(seg) and '*' or seg
  end

  return { str = table.concat(segments, '/'), segments = segments }
end

function M.normalize_method(method)
  if not method or method == '' then
    return 'GET'
  end
  return method:upper()
end

-- Score how specifically `route` matches `call` (both already normalized).
-- Returns nil when they can't match at all (wrong method/arity/literal), else a
-- number where higher = more specific (exact literals beat wildcards).
function M.score(call, route)
  if call.method and route.method and route.method ~= 'ANY' and call.method ~= route.method then
    return nil
  end
  local cs, rs = call.segments, route.segments
  if #cs ~= #rs then
    return nil
  end
  local score = 0
  for i = 1, #cs do
    local c, r = cs[i], rs[i]
    if c == r then
      score = score + 2 -- exact literal (or wildcard==wildcard) agreement
    elseif c == '*' or r == '*' then
      score = score + 1 -- one side is a wildcard
    else
      return nil -- conflicting literals: not a match
    end
  end
  return score
end

-- Rank the routes that can serve `call`, best (most specific) first.
-- Each result is { route = <entry>, score = <number> }.
function M.match(call, routes)
  local out = {}
  for _, r in ipairs(routes) do
    local score = M.score(call, r)
    if score then
      out[#out + 1] = { route = r, score = score }
    end
  end
  table.sort(out, function(a, b)
    if a.score == b.score then
      return (a.route.str or '') < (b.route.str or '')
    end
    return a.score > b.score
  end)
  return out
end

-- True when the two best candidates tie on specificity (the UI should offer a
-- pick-list / allow a manual link).
function M.is_ambiguous(ranked)
  return #ranked >= 2 and ranked[1].score == ranked[2].score
end

return M
