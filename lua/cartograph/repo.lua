-- cartograph.repo — whole-repository symbol/call graph builder.
--
-- Builds one graph for the entire workspace: a node per top-level symbol and a
-- `calls` edge per resolved call-site. Symbols and call references come from
-- Treesitter `tags` queries (fast, offline, language-agnostic); call targets are
-- resolved by name. This is deliberately approximate — whole-repo LSP does not
-- scale — and LSP stays the precise resolver for on-demand single-node expansion.
--
-- The pure resolution (build_graph) is split from the Treesitter extraction so
-- the graph-shaping logic is unit-testable without a parser, mirroring how the
-- rest of the engine separates pure modules from Neovim-facing ones.

local M = {}

local graph_mod = require('cartograph.graph')

-- Treesitter `tags` definition capture -> our node kind.
local KIND_BY_CAPTURE = {
  ['definition.class'] = 'controller',
  ['definition.interface'] = 'controller',
  ['definition.struct'] = 'controller',
  ['definition.method'] = 'action',
  ['definition.function'] = 'action',
  ['definition.type'] = 'type',
  ['definition.enum'] = 'type',
  ['definition.module'] = 'type',
  ['definition.namespace'] = 'type',
  ['definition.field'] = 'field',
  ['definition.constant'] = 'field',
}

local function location_id(file, line, col)
  return ('%s:%d:%d'):format(file, line, col)
end

-- Plugin root (…/cartograph.nvim), so we can read our bundled queries/.
local function plugin_root()
  local src = debug.getinfo(1, 'S').source:sub(2) -- lua/cartograph/repo.lua
  return vim.fn.fnamemodify(src, ':h:h:h')
end

local query_cache = {} -- lang -> parsed Query | false (tried, none)

-- Resolve the `tags` query for a language. Prefer a runtime/user query (so a
-- full nvim-treesitter `master` install or a user override wins), then fall back
-- to the query we vendor under queries/<lang>/tags.scm. The bundled fallback is
-- what keeps :CartographRepo working on nvim-treesitter `main`, which ships no
-- tags queries at all. Cached; safe to call per-file. Returns nil when neither
-- a query nor a parser is available.
function M.tags_query(lang)
  if query_cache[lang] ~= nil then
    return query_cache[lang] or nil
  end
  local ok, q = pcall(vim.treesitter.query.get, lang, 'tags')
  if ok and q then
    query_cache[lang] = q
    return q
  end
  local fd = io.open(plugin_root() .. '/queries/' .. lang .. '/tags.scm', 'r')
  if not fd then
    query_cache[lang] = false
    return nil
  end
  local src = fd:read('*a')
  fd:close()
  local pok, parsed = pcall(vim.treesitter.query.parse, lang, src)
  query_cache[lang] = (pok and parsed) or false
  return query_cache[lang] or nil
end

-- Is a Treesitter parser available for `lang`? Mirrors health.has_parser.
function M.lang_available(lang)
  if not lang or lang == '' then
    return false
  end
  local ok, res = pcall(vim.treesitter.language.add, lang)
  return ok and res ~= false
end

-- Build a graph from extracted definitions and call references. PURE.
--   definitions: array of { name, kind, file, line, col, lang }
--   references:  array of { name, file, line, col } (call-sites)
--   opts.max_nodes: cap on the number of definition nodes created
-- A reference is attributed to the nearest preceding definition in the same file
-- (its enclosing symbol) and linked to every definition sharing the callee name.
function M.build_graph(definitions, references, opts)
  opts = opts or {}
  references = references or {}
  local g = graph_mod.new()

  local by_name = {} -- callee name -> array of defs
  local by_file = {} -- file -> array of defs (sorted by line below)
  local created = 0

  for _, d in ipairs(definitions) do
    if opts.max_nodes and created >= opts.max_nodes then
      break
    end
    d.id = location_id(d.file, d.line, d.col)
    g:add_node({
      id = d.id,
      kind = d.kind or 'call',
      name = d.name,
      file = d.file,
      range = { start = { line = d.line, character = d.col } },
      lang = d.lang,
      meta = { source = 'treesitter.tags', snippet = d.snippet },
    })
    by_name[d.name] = by_name[d.name] or {}
    by_name[d.name][#by_name[d.name] + 1] = d
    by_file[d.file] = by_file[d.file] or {}
    by_file[d.file][#by_file[d.file] + 1] = d
    created = created + 1
  end

  for _, defs in pairs(by_file) do
    table.sort(defs, function(a, b)
      return a.line < b.line
    end)
  end

  -- The enclosing symbol of a reference: the last definition in the same file
  -- that starts at or before the reference's line.
  local function enclosing(ref)
    local defs = by_file[ref.file]
    if not defs then
      return nil
    end
    local found
    for _, d in ipairs(defs) do
      if d.line <= ref.line then
        found = d
      else
        break
      end
    end
    return found
  end

  for _, ref in ipairs(references) do
    local from = enclosing(ref)
    local targets = by_name[ref.name]
    if from and targets then
      for _, t in ipairs(targets) do
        if t.id ~= from.id then
          g:add_edge({ from = from.id, to = t.id, kind = 'calls' })
        end
      end
    end
  end

  return g
end

-- Extract definitions + call references from one file's source via Treesitter.
-- Returns (definitions, references). Empty when the language has no parser or no
-- `tags` query. Impure (Treesitter); kept thin so build_graph carries the logic.
function M.extract(source, file, lang)
  local defs, refs = {}, {}
  if not M.lang_available(lang) then
    return defs, refs
  end
  local query = M.tags_query(lang)
  if not query then
    return defs, refs
  end
  -- Source lines (1-indexed) for cheap definition snippets shown on hover.
  local lines = vim.split(source, '\n', { plain = true })
  local function snippet_at(line0)
    local out = {}
    for k = line0, math.min(line0 + 2, #lines - 1) do
      out[#out + 1] = lines[k + 1]
    end
    local s = table.concat(out, '\n')
    if #s > 400 then
      s = s:sub(1, 400) .. '…'
    end
    return s
  end
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  if not ok or not parser then
    return defs, refs
  end
  local tree = parser:parse()[1]
  if not tree then
    return defs, refs
  end

  -- iter_matches yields one node per capture on older Neovim and an array of
  -- nodes on 0.10+; normalize to a single node.
  local function one(value)
    if type(value) == 'table' then
      return value[#value]
    end
    return value
  end

  for _, match in query:iter_matches(tree:root(), source, 0, -1) do
    local name, line, col, kind, is_call
    for id, value in pairs(match) do
      local cap = query.captures[id]
      local node = one(value)
      if node then
        if cap == 'name' then
          local trow, tcol = node:range()
          line, col = trow, tcol
          name = vim.treesitter.get_node_text(node, source)
        elseif cap:sub(1, 11) == 'definition.' then
          kind = KIND_BY_CAPTURE[cap] or 'call'
        elseif cap == 'reference.call' then
          is_call = true
        end
      end
    end
    if name and #name > 0 and not name:find('\n') then
      if kind then
        defs[#defs + 1] =
          { name = name, kind = kind, file = file, line = line, col = col, lang = lang, snippet = snippet_at(line) }
      elseif is_call then
        refs[#refs + 1] = { name = name, file = file, line = line, col = col }
      end
    end
  end

  return defs, refs
end

local function read_file(path)
  local fd = io.open(path, 'r')
  if not fd then
    return nil
  end
  local content = fd:read('*a')
  fd:close()
  return content
end

-- Build the whole-repo graph asynchronously, processing files in scheduled
-- chunks so a large scan never blocks the UI. Calls on_done(graph) when complete.
function M.build(opts, on_done)
  opts = opts or {}
  local config = require('cartograph.config').options.repo
  local root = opts.root or require('cartograph.root').find()
  local langs = config.languages or {}

  local patterns = {}
  for ext in pairs(langs) do
    patterns[#patterns + 1] = '**/*.' .. ext
  end
  local files = require('cartograph.index').scan_files(root, patterns)

  local definitions, references = {}, {}
  local missing = {} -- lang -> count of files skipped (parser not installed)
  local i = 1
  local CHUNK = 40

  local function finish()
    local g = M.build_graph(definitions, references, { max_nodes = config.max_nodes })
    require('cartograph.layer').annotate(g, require('cartograph.config').options.clean)
    on_done(g, {
      root = root,
      files = #files,
      missing = missing,
      truncated = g:node_count() >= (config.max_nodes or math.huge),
    })
  end

  local function step()
    local stop = math.min(i + CHUNK - 1, #files)
    for n = i, stop do
      local file = files[n]
      local ext = file:match('%.([%w]+)$')
      local lang = ext and langs[ext]
      if lang and not M.lang_available(lang) then
        missing[lang] = (missing[lang] or 0) + 1
      end
      local source = lang and read_file(file)
      if source then
        local d, r = M.extract(source, file, lang)
        for _, e in ipairs(d) do
          definitions[#definitions + 1] = e
        end
        for _, e in ipairs(r) do
          references[#references + 1] = e
        end
      end
    end
    i = stop + 1
    if i > #files then
      finish()
    else
      vim.schedule(step)
    end
  end

  if #files == 0 then
    return finish()
  end
  step()
end

return M
