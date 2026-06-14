# cartograph.nvim

Visually trace and compare **code paths** through a codebase. Pick a starting
point — an HTTP endpoint, or the symbol under your cursor — and cartograph
renders its connections as an interactive graph you drill into hop by hop
(`endpoint → controller → action → service/store → type`). Open a second path to
**compare** two chains side by side, with shared nodes and divergences
highlighted. Clicking a node jumps your editor to that symbol.

The v1 stack is **Vue (TS/JS) ↔ .NET (C#)**, built on a pluggable adapter
architecture so other stacks can be added later.

> **Status: early.** Phase 0 (scaffold) and the start of phase 1 (engine +
> in-language drill-down) are in place. The interactive browser UI, the
> cross-stack HTTP bridge, and compare are on the way — see
> [`CARTOGRAPH_PLAN.md`](CARTOGRAPH_PLAN.md) for the full roadmap.

## Requirements

- Neovim 0.9+ (`vim.uv`/`vim.loop` are both handled)
- For full resolution: Treesitter parsers `c_sharp`, `typescript`, `vue`, and an
  LSP server per language (OmniSharp/Roslyn, Volar/tsserver). Resolvers degrade
  gracefully to Treesitter when no LSP is attached.

Run `:checkhealth cartograph` to see what's available.

## Installation

**lazy.nvim**

```lua
{ "Symphon-y/cartograph.nvim", opts = {} }
```

**packer.nvim**

```lua
use "Symphon-y/cartograph.nvim"
```

The plugin registers its commands automatically via `plugin/cartograph.lua`. A
`setup()` call is only needed to override defaults or bind the trigger keymaps.

## Usage

| Command | Description |
|---|---|
| `:Cartograph` | Open the map view (`:Cartograph!` to close) |
| `:CartographFromCursor` | Seed a map from the symbol under the cursor |
| `:CartographCompare` | Compare two code paths *(phase 4)* |
| `:CartographSave <name>` | Save the active map |
| `:CartographLoad <name>` | Load a saved map |
| `:CartographClose` | Close the session |

## Configuration

Defaults (pass overrides to `setup()`):

```lua
require('cartograph').setup({
  server = { host = '127.0.0.1', port = 0, auto_open = true, token = true },
  view = { layout = 'dagre', theme = 'auto' }, -- 'light' | 'dark' | 'auto'
  adapters = { 'dotnet', 'vue' },
  resolvers = { lsp = true, treesitter = true, http = true },
  http = { base_urls = {}, route_overrides = {} },
  persist = { dir = vim.fn.stdpath('data') .. '/cartograph' },
  keymaps = {
    from_cursor = '<leader>cm',
    compare     = '<leader>cc',
  },
})
```

## Architecture

cartograph is split into four layers so the browser UI can be swapped for an
in-Neovim canvas without touching the engine:

1. **Engine** (`lua/cartograph/graph.lua`, `resolver/`) — a language-agnostic
   graph model fed by LSP (in-language hops) and Treesitter (structure).
2. **Adapters** (`adapters/dotnet.lua`, `adapters/vue.lua`) — stack-specific
   knowledge of routes, controllers, request call-sites.
3. **Bridge** (`server.lua`, `sse.lua`) — a pure-Lua `vim.uv` server pushing
   graph updates to the browser over Server-Sent Events.
4. **Web UI** (`web/`) — a bundled, offline Cytoscape.js graph.

See [`CARTOGRAPH_PLAN.md`](CARTOGRAPH_PLAN.md) for the full design and roadmap.

## Development

```sh
make test   # runs the pure-Lua engine specs headlessly (clones plenary on first run)
```
