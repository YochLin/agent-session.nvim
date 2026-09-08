# AGENTS.md

This file provides guidance to AI coding assistants (Antigravity, Claude Code, Codex, Cursor, etc.) when working with code in this repository.

## Overview

agent-session.nvim is a Neovim plugin (pure Lua, no build step) that manages multiple AI agent CLI sessions (Claude Code, codex, gemini, arbitrary shells, etc.) as terminal buffers, with floating/split windows, a left sidebar explorer, and statusline/lualine/heirline integration.

## Development

There is no build system, no linter config beyond StyLua, and no automated test runner. This is a small, dependency-free Lua plugin loaded directly by Neovim's runtime.

- **Format**: `stylua .` (config in `.stylua.toml`: 2-space indent, 120 col width, double quotes).
- **Manual/interactive testing**: `nvim -u tests/minimal_init.lua` bootstraps lazy.nvim into an isolated `.tests/` sandbox (its own XDG dirs) and loads the plugin from the working directory. There is no headless/CI test suite; verify changes by exercising commands inside this sandboxed Neovim instance.
- **Lua LSP**: `.luarc.json` targets LuaJIT with the `vim` global and the `$VIMRUNTIME`/`luv` libraries. Keep this in mind when writing code that must satisfy the language server, since it assumes nothing beyond the Neovim/luv API surface.

## Architecture

All modules live under `lua/agent-session/` and are required lazily from `lua/agent-session/init.lua`, the public API surface (`require("agent-session")`). `plugin/agent-session.lua` wires up user commands (`:AgentSession`, `:AgentSessionNew`, etc.) and delegates directly to `init.lua` functions; it contains no logic of its own.

Module responsibilities:
- **`config.lua`** holds `M.defaults`, merges user `opts` via `vim.tbl_deep_extend("force", ...)` on `setup()`, and creates `session_dir` if configured. `M.get()` is the single source of truth read by every other module (it falls back to defaults if `setup()` was never called).
- **`session.lua`** is the process/session model. `M._active_sessions` (table keyed by generated id) and `M._current_session_id` are module-level state, with no persistence across Neovim restarts. `M.create()` opens a scratch buffer, spawns the agent command with `vim.fn.termopen`, and attaches a buffer listener (`nvim_buf_attach` `on_lines`) plus a libuv idle timer to derive session status transitions: from `running` to `idle` after `idle_timeout` ms of silence, then to `stopped` when the process exits. Status changes always flow through `M.set_status()`, which fires the `on_status_change` hook, a `User AgentSessionStatusChanged` autocmd, and refreshes both the window title (`ui.refresh_title`) and the sidebar (`sidebar.render`). Anything that needs to react to session state hooks in here.
- **`ui.lua`** manages windows for the "active" session view: floating window or split/vsplit, title/winbar formatting driven by session status, `vim.ui.select`-based pickers for choosing a session or an agent to launch. It tracks only one window at a time (`M._current_win`); opening a session while a window exists reuses it rather than creating a new one.
- **`sidebar.lua`** is a separate, persistent left-docked explorer with its own buffer/window state, independent of `ui.lua`'s window. It lists sessions grouped by status with per-line buffer-local keymaps (open/new/delete/resize), and auto-redocks itself under `neo-tree`/`NvimTree`/`aerial`/`Outline` when one of those opens, so it always sits directly beneath the file tree in the left column. It subscribes to the same `AgentSessionStatusChanged` autocmd as `ui.lua` to stay in sync.
- **`statusline.lua`** holds read-only consumers of `session.get_current()`/`config.get()` that format status for lualine, Heirline, and AstroNvim's `astroui.status` builder (auto-detected via `pcall(require, "astroui.status")`). These have no side effects on session state.

Key conventions to preserve when extending this codebase:
- Session status is derived, not set directly. Always go through `session.set_status()` so hooks/autocmds/UI refresh stay consistent; never mutate `session.status` in place elsewhere.
- Agent definitions (`opts.agents[name] = { cmd, args, env }`) resolve through a fallback chain: explicit config entry, then a `vim.fn.executable(name)` check, then `vim.o.shell`. Both `init.lua` (`new_session`) and `session.lua` (`create`) implement pieces of this resolution; keep them consistent if you change agent lookup behavior.
- UI dimensions (`width`/`height` in config) accept either a float `< 1` (percentage of `vim.o.columns`/`vim.o.lines`) or an integer (fixed columns/lines). This pattern repeats across `ui.lua` and `sidebar.lua` and should stay consistent for new size options.
- `pcall` guards most `vim.api` calls that touch windows/buffers that may have been closed asynchronously (terminal exit, user closing a split); follow this pattern for new window/buffer manipulation to avoid E5108 errors from stale handles.
