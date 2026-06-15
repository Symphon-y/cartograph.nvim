# cartograph.nvim — Implementation Plan

> **Purpose of this document.** This is a self-contained build spec for a new
> Neovim plugin, `cartograph.nvim`. It was drafted in a Claude Code session that
> was scoped to a different repository and could neither create the new repo nor
> push to it. **Create an empty `cartograph.nvim` repo, start a Claude Code
> session pointed at it, drop this file in the repo root, and tell Claude to
> implement it.**

---

## 1. Concept

`cartograph.nvim` lets you **visually trace and compare code paths** through a
codebase. You pick a starting point — an HTTP endpoint, or the symbol under your
cursor — and the plugin renders its immediate connections as an **interactive
graph in the browser**. You click any node to expand the next hop in the chain
(e.g. `endpoint → controller action → service/store → type`), and the graph
grows as you drill down. You can open a second path and **compare** two chains
side by side, with shared nodes and divergences highlighted. Clicking a node
also jumps your Neovim editor to that symbol.

The motivating example: in a Vue app with a .NET backend, map what a
`/validation` endpoint actually does — select the controller, see its actions /
types / a secondary auth method, pick the `Validate()` action, see that it maps
to a store and a DTO, and so on down the chain.

### Design decisions already made (do not re-litigate)

| Decision | Choice |
| --- | --- |
| Plugin name | `cartograph.nvim` |
| Rendering | **Interactive** browser graph (NOT a static export). Neovim is the brain; the browser is a live, two-way view. |
| Connection discovery | **LSP for in-language hops + Treesitter/heuristics for the cross-stack HTTP boundary.** |
| v1 stack | **Vue (TS/JS) ↔ .NET (C#)**, built on a pluggable adapter architecture so other stacks can be added later. |
| Transport | **Server-Sent Events (nvim→browser push) + HTTP POST (browser→nvim)** over a pure-Lua `vim.uv` server. (WebSocket is a possible later upgrade; SSE avoids the handshake/SHA1/frame-masking complexity for zero added dependencies.) |
| Graph lib | **Cytoscape.js**, vendored locally (offline, no CDN). |

If staying inside the terminal ever becomes preferable to a browser, the UI
layer can be swapped for an in-Neovim node-graph canvas **without touching the
engine** — the engine emits a generic graph model.

---

## 2. Conventions to follow

Match the existing `Symphon-y` plugins (`gitdiff.nvim`, `courier.nvim`,
`claude.nvim`, `preview.nvim`):

- Repo named `<thing>.nvim`; layout `lua/<name>/` + `plugin/` + `doc/` + `README.md`.
- `init.lua` exposes a small public API and lazy-`require`s submodules.
- `config.lua` pattern:
  ```lua
  local M = {}
  local defaults = { --[[ ... ]] }
  M.options = vim.deepcopy(defaults)
  function M.setup(opts)
    M.options = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  end
  return M
  ```
- Concerns split into `config` / `state` / `ui` / `highlights` submodules.
- Keymaps grouped by panel/context.
- **2-space indent, single quotes.**

---

## 3. Architecture (4 layers)

### Layer 1 — Engine (Lua, language-agnostic core)

- **`lua/cartograph/graph.lua`** — in-memory graph model.
  - Node: `{ id, kind, name, file, range, lang, meta }` where `kind` ∈
    `endpoint | controller | action | type | store | service | call | field`.
  - Edge: `{ from, to, kind }` where `kind` ∈
    `routes-to | calls | references | typeof | injects`.
  - Pure data + helpers (add/merge/dedupe nodes & edges, serialize to JSON).
- **`lua/cartograph/resolver/lsp.lua`** — in-language hops via LSP:
  `textDocument/definition`, `references`, `callHierarchy/{incoming,outgoing}`,
  `documentSymbol`. Fully async; degrade gracefully when no client is attached.
- **`lua/cartograph/resolver/treesitter.lua`** — structural members of a node
  (a controller's actions / injected fields / return types) via TS queries; also
  the fallback when LSP is unavailable.
- **`lua/cartograph/resolver/http.lua`** — **the cross-stack bridge.** Builds a
  route table from .NET route attributes and matches it against Vue/TS request
  call-sites by normalized `method + path`. Produces `routes-to` edges.

### Layer 2 — Adapters (stack-specific knowledge)

- **`lua/cartograph/adapters/dotnet.lua`** — find `[ApiController]` / `Controller`
  classes, `[Route("...")]` and `[HttpGet/Post/Put/Delete("...")]` templates,
  public actions, constructor-injected services/stores, DTO/return types.
  Normalize route tokens (`[controller]`, `{id}`, `{id:int}`). Also handle
  minimal-API `app.MapGet("...")` style.
- **`lua/cartograph/adapters/vue.lua`** — find `axios` / `fetch` / `$http` /
  generated-API-client call sites in components and Pinia stores; extract method
  + URL (best-effort on template strings and base-URL constants).
- **`lua/cartograph/index.lua`** — workspace scanner that builds & caches the
  route/symbol index; refresh incrementally on `BufWritePost`.

**Heuristic matching rules (http resolver):** normalize both sides (lowercase,
strip leading/trailing slash, collapse `//`, replace `{param}` / `:param` /
`${var}` / interpolations with a single-segment wildcard), match by
`method + path`, rank candidates by specificity. When ambiguous, surface the
candidates as a pick-list in the UI and allow a manual link. Support config
overrides for base URLs and explicit route maps.

### Layer 3 — Bridge / local server (pure Lua over `vim.uv`)

- **`lua/cartograph/server.lua`** — minimal HTTP server, bound to `127.0.0.1` on
  a random port, serving the bundled web UI. Includes a **per-session token** in
  the URL so no other local process can connect.
- **`lua/cartograph/sse.lua`** — Server-Sent Events stream (nvim→browser push).
- Browser→nvim is plain `fetch` POST to local endpoints.
- **Protocol (JSON):**
  - browser → nvim: `setRoot(query)`, `expand(nodeId)`, `compare(rootA, rootB)`,
    `reveal(nodeId)`, `save(name)`, `load(name)`.
  - nvim → browser: `graph:update`, `node:added`, `status`, `error`.

### Layer 4 — Web UI (bundled, offline)

- **`web/index.html`**, **`web/app.js`**, **`web/styles.css`**, vendored
  **`web/vendor/cytoscape*.js`** (+ a layout extension such as `dagre`).
- Interactions live in the graph itself: click-to-expand, drag, zoom, search,
  breadcrumb, compare overlay. Clicking a node fires `reveal` so the editor
  follows. Theme follows a light/dark/auto config.

---

## 4. Neovim-side glue, public API, config

- **`lua/cartograph/init.lua`** — public API:
  `setup`, `open`, `close`, `refresh`, `from_cursor`, `compare`, `save`, `load`.
  Lazy-`require`s submodules.
- **`lua/cartograph/config.lua`** — defaults (see below).
- **`lua/cartograph/state.lua`** — active maps, comparison sets,
  expansion/selection state, JSON persistence of named maps.
- **`lua/cartograph/highlights.lua`** — any Neovim-side highlight groups
  (status/help floats).
- **`doc/cartograph.txt`** — help doc.
- **`plugin/cartograph.lua`** — user commands:
  `:Cartograph[!]`, `:CartographFromCursor`, `:CartographCompare`,
  `:CartographSave`, `:CartographLoad`, `:CartographClose`.
- **health check** — `lua/cartograph/health.lua` for `:checkhealth cartograph`
  (verifies required Treesitter parsers `c_sharp`/`typescript`/`vue`, LSP
  availability, and that a browser can be opened).

### Default config sketch

```lua
local defaults = {
  server = {
    host = '127.0.0.1',
    port = 0,            -- 0 = random free port
    auto_open = true,    -- open the browser automatically
    token = true,        -- per-session URL token
  },
  view = {
    layout = 'dagre',    -- cytoscape layout
    theme = 'auto',      -- 'light' | 'dark' | 'auto'
  },
  adapters = { 'dotnet', 'vue' },
  resolvers = { lsp = true, treesitter = true, http = true },
  http = {
    base_urls = {},      -- e.g. { '/api', 'https://localhost:5001' }
    route_overrides = {},-- explicit { frontend_call = backend_route } links
  },
  persist = {
    dir = vim.fn.stdpath('data') .. '/cartograph',
  },
  keymaps = {
    -- Neovim-side trigger maps (UI maps live in the browser)
    from_cursor = '<leader>cm',
    compare     = '<leader>cc',
  },
}
```

---

## 5. Build phases

0. **Scaffold** — repo layout, `init/config/state`, commands, `doc`/`README`
   skeleton matching the other plugins.
1. **Engine + in-language resolvers** — graph model, controller→members
   expansion, definition/references hops, root-from-cursor.
2. **Server + interactive UI** — SSE/HTTP server, Cytoscape graph, click-to-
   expand wired to the engine, reveal-in-editor. *(Ship through here first so the
   core UX is clickable early.)*
3. **Cross-stack HTTP bridge** — .NET route index + Vue call index + normalizing
   matcher; root-from-endpoint; ambiguous matches surfaced as choices in the UI.
4. **Compare** — dual roots, shared-node / divergence highlighting, side-by-side
   / overlay layout.
5. **Persistence, polish, config surface, docs, healthcheck.**

---

## 6. Testing

- `plenary`/busted unit tests for pure-Lua logic (route normalization, the
  matcher, graph add/merge/dedupe).
- A tiny `tests/fixtures` workspace (minimal Vue + .NET) to validate the bridge
  end-to-end.

---

## 7. Key risks & mitigations

- **Cross-stack matching is heuristic** — there is no ground-truth link between a
  fetch string and a route. Normalize aggressively, rank candidates, surface
  ambiguity as a pick-list, allow manual links + config overrides.
- **LSP availability / async timing** — needs C# (Roslyn/OmniSharp) and
  Volar/tsserver running. Resolvers are async with Treesitter fallback when no
  LSP is attached.
- **Cytoscape bundle size** — vendored for offline use; acceptable tradeoff for
  rich interactivity.
- **Server security** — bind to loopback only, random port, per-session token in
  the URL.

---

## 8. Proposed file tree

```
cartograph.nvim/
├── README.md
├── doc/
│   └── cartograph.txt
├── plugin/
│   └── cartograph.lua
├── lua/
│   └── cartograph/
│       ├── init.lua
│       ├── config.lua
│       ├── state.lua
│       ├── highlights.lua
│       ├── health.lua
│       ├── graph.lua
│       ├── index.lua
│       ├── server.lua
│       ├── sse.lua
│       ├── resolver/
│       │   ├── lsp.lua
│       │   ├── treesitter.lua
│       │   └── http.lua
│       └── adapters/
│           ├── dotnet.lua
│           └── vue.lua
├── web/
│   ├── index.html
│   ├── app.js
│   ├── styles.css
│   └── vendor/
│       └── cytoscape*.js
└── tests/
    ├── fixtures/        (minimal Vue + .NET sample)
    └── *_spec.lua
```

---

## 9. First message to paste into the new session

> Implement `cartograph.nvim` per `CARTOGRAPH_PLAN.md` in this repo. Match the
> conventions of my other `Symphon-y` `.nvim` plugins. Start with phases 0–2
> (scaffold + engine with in-language drill-down + interactive browser UI) so I
> can click through the core UX, then we'll do the Vue↔.NET bridge and compare.
