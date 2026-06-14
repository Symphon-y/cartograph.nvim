-- cartograph.adapters.vue — extract HTTP request call-sites from Vue/TS/JS.
--
-- Pure, best-effort text extraction (no Treesitter dependency). Recognizes
-- axios/$http/generated-client verb calls (`x.get('/url')`), and `fetch('/url',
-- { method })`. URLs are taken as-is; template-literal interpolations become
-- wildcards at normalization time. As with the .NET side this is heuristic by
-- nature — see CARTOGRAPH_PLAN.md §7.

local M = {}

local route = require('cartograph.route')

local VERBS = { get = true, post = true, put = true, delete = true, patch = true }

function M.handles(file)
  return file:match('%.vue$') ~= nil or file:match('%.ts$') ~= nil or file:match('%.js$') ~= nil
end

local function lang_for(file)
  if file:match('%.vue$') then
    return 'vue'
  elseif file:match('%.ts$') then
    return 'typescript'
  end
  return 'javascript'
end

-- Only treat a string as a request URL if it looks like a path/endpoint. Keeps
-- us from matching things like cache.get('some-key').
local function looks_like_url(s)
  return s:sub(1, 1) == '/' or s:match('^https?://') ~= nil or s:find('/', 1, true) ~= nil
end

function M.extract(source, file)
  local calls = {}
  local lang = lang_for(file)
  local lines = vim.split(source, '\n', { plain = true })

  local function add(method, url, line)
    if not url or not looks_like_url(url) then
      return
    end
    calls[#calls + 1] = {
      kind = 'call',
      method = route.normalize_method(method),
      url = url,
      norm = route.normalize(url),
      file = file,
      line = line,
      lang = lang,
    }
  end

  for i, line in ipairs(lines) do
    -- <obj>.<verb>('url' | "url" | `url`)
    for verb, q, url in line:gmatch('%.(%a+)%(%s*(["\'`])([^"\'`]+)') do
      if VERBS[verb:lower()] then
        add(verb, url, i)
      end
      local _ = q
    end

    -- fetch('url', { method: 'POST' })  /  fetch('url')
    local furl = line:match('fetch%(%s*["\'`]([^"\'`]+)')
    if furl then
      local fmethod = line:match('method%s*:%s*["\']([%a]+)')
      add(fmethod, furl, i)
    end
  end

  return calls
end

return M
