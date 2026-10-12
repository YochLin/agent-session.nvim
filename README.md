# agent-session.nvim

Run Claude Code, Codex, Gemini, or any other agent CLI side by side in Neovim. See at a glance which agent is still working, get a desktop notification when one finishes, and pipe one agent's output into another.

Pure Lua. No tmux, no dependencies.

https://github.com/user-attachments/assets/cd545acf-2252-4ef8-a37d-2e7a003adb13

## Why agent-session.nvim

- **Know who's busy.** Every session is tracked as running ⚡, idle 🟢, or stopped ⚪, shown in a tab bar, a sidebar explorer, and your statusline.
- **Fire and forget.** Hand a task to an agent, hide it, keep coding. When it goes idle or exits you get a native desktop notification (Ghostty, WezTerm, iTerm2, Warp, or the macOS / Linux notification center).
- **Agents that talk to each other.** Pipe one session's output into another with an instruction: `architect` plans, `coder` implements, `reviewer` checks.
- **Point at code instead of pasting it.** Send `@file:line` or `@file:start-end` from any buffer or visual selection straight into an agent's prompt.
- **Any CLI works.** Claude Code, Codex, Gemini, Copilot, Aider, Kimi, DeepSeek and more are preconfigured. Anything else on your `$PATH` runs too.

## Requirements

- Neovim 0.9+
- The agent CLIs you want to use, installed and on your `$PATH`
- A [Nerd Font](https://www.nerdfonts.com/) for agent icons (optional)

## Quick start

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "YochLin/agent-session.nvim", opts = {} }
```

Then:

```vim
:AgentSessionNew claude     " start a Claude Code session
:AgentSessionNew codex      " start a second one next to it
:AgentSessionSidebar        " see every session and its status
```

Inside a session window, `<C-\><C-\>` drops to normal mode. From there `]a` / `[a` cycles sessions, `z` toggles zoom, and `q` hides the window.

## Example: planner and builder

```vim
:AgentSessionNew architect claude
" ask it for an implementation plan

:AgentSessionNew coder codex
:AgentSessionPipe architect coder Implement step 1 of this plan
```

`:AgentSessionPipe` takes the last 60 lines of `architect`'s output and sends them to `coder` along with your instruction. Longer output is saved to a file and passed as an `@file` reference so it doesn't flood the prompt. Hide the window and get back to work; you'll get a desktop notification when `coder` is done.

## Recommended setup

A lazy.nvim spec with keymaps (works as-is in LazyVim and AstroNvim):

```lua
return {
  "YochLin/agent-session.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>at", "<cmd>AgentSessionToggle<cr>", mode = { "n", "t" }, desc = "Toggle Agent Session Window" },
    { "<leader>az", "<cmd>AgentSessionZoom<cr>", mode = { "n", "t" }, desc = "Toggle Center Full / Side View" },
    { "<leader>ae", "<cmd>AgentSessionSidebar<cr>", mode = { "n", "t" }, desc = "Toggle Agent Explorer (Sidebar)" },
    { "<leader>an", "<cmd>AgentSessionNew<cr>", desc = "New Agent Session (Interactive)" },
    { "<leader>aa", "<cmd>AgentSessionSelectAgent<cr>", desc = "Select & Launch Agent" },
    { "<leader>al", "<cmd>AgentSessionList<cr>", desc = "List Active Sessions" },
    { "]a", "<cmd>AgentSessionNext<cr>", mode = { "n", "t" }, desc = "Next Agent Session" },
    { "[a", "<cmd>AgentSessionPrev<cr>", mode = { "n", "t" }, desc = "Previous Agent Session" },
    { "<leader>ap", "<cmd>AgentSessionPrompt<cr>", desc = "Prompt / Command Target Session" },
    { "<leader>aP", "<cmd>AgentSessionPipe<cr>", mode = { "n", "v" }, desc = "Pipe Output to Target Session" },
    { "<leader>ar", "<cmd>AgentSessionRename<cr>", desc = "Rename Session" },
    { "<leader>as", "<cmd>AgentSessionSendLine<cr>", mode = { "n", "v" }, desc = "Send Line/Selection Ref to Session" },
    { "<leader>ab", "<cmd>AgentSessionSendFile<cr>", desc = "Send File Ref to Session" },
  },
  opts = {
    default_agent = "claude",
  },
}
```

### Custom agents

Add your own entries next to the preconfigured ones:

```lua
opts = {
  agents = {
    opus = { cmd = "claude", args = { "--model", "opus" }, icon = "✻" },
  },
}
```

Then `:AgentSessionNew opus`. A CLI that isn't in `agents` still works if it's on your `$PATH`, e.g. `:AgentSessionNew opencode`.

### Icons and brand colors

Each agent gets a Nerd Font glyph plus a brand color, so the sidebar reads at a glance. Override either:

```lua
opts = {
  agent_icons = { opus = "✻" },
  agent_colors = { opus = "#d97757" },
  -- or per agent: agents = { opus = { cmd = "claude", icon = "✻", color = "#d97757" } }
}
```

Colors land on the highlight group `AgentSessionAgent<name>` (e.g. `AgentSessionAgentclaude`), defined with `default = true` — define it in your colorscheme and yours wins.

Terminals can't render real image logos in a text buffer, so icons are glyphs. For an exact logo, build the SVG into a small icon font, map it in your terminal, and point `agent_icons` at its codepoint:

```lua
opts = { agent_icons = { claude = "\u{100000}" } }
```

Use plane 16 (`U+100000`–`U+10FFFD`) — Nerd Fonts already occupies the lower private-use ranges up to `U+F1AF0`. The glyph is monochrome and takes its color from `agent_colors`, and only machines with that font installed will render it.

### Statusline

```lua
-- lualine component
{
  function()
    return require("agent-session").status()
  end,
  cond = function()
    return require("agent-session.session").get_current() ~= nil
  end,
}
```

### Restoring sessions after a restart

Open sessions are saved per project: one small JSON file keyed by the directory Neovim was started in, under `session_dir/projects/`. The next time you start Neovim in that directory you get asked whether to restore them (`persist.auto_restore`), or you can run `:AgentSessionRestore` whenever you like.

Restored sessions keep their names and working directories. Each one also picks up its old conversation where the CLI supports it:

| Agent | How the conversation ID is tracked | Resumed with |
| :--- | :--- | :--- |
| `claude` | Pinned at launch with `--session-id <uuid>` | `claude --resume <uuid>` |
| `codex` | Read from `~/.codex/sessions/**/rollout-*.jsonl` after your first message | `codex resume <id>` |
| `agy` | Read from `~/.gemini/antigravity-cli/history.jsonl` after your first message | `agy --conversation <id>` |

Other agents are relaunched with a fresh conversation. So is a session where you never sent a message.

The saved file is never cleared implicitly. Starting new sessions before restoring adds to it instead of replacing it. It only goes away when you restore it, discard it (`:AgentSessionRestore!` or "Discard" in the prompt), or close every session. Files of other projects untouched for `persist.max_age_days` are pruned on startup. Nothing here touches the CLIs' own conversation history.

To make a custom agent resumable, give it a `resume` table:

```lua
agents = {
  opus = {
    cmd = "claude",
    args = { "--model", "opus" },
    resume = {
      assign = function(id) return { "--session-id", id } end, -- pin a UUID at launch
      args = function(id) return { "--resume", id } end, -- resume it later
    },
  },
}
```

For CLIs that can't pin an ID, use `discover = "codex"`, `discover = "agy"`, or `discover = function(session, claimed) ... end` (return the conversation ID or nil) instead of `assign`. Set `resume = false` to always start fresh.

## Commands

| Command | Description |
| :--- | :--- |
| `:AgentSession` / `:AgentSessionToggle` | Toggle the current session window |
| `:AgentSessionZoom` / `:AgentSessionToggleZoom` | Toggle between centered full-screen float and side split |
| `:AgentSessionNext` / `:AgentSessionPrev` | Cycle sessions in creation order |
| `:AgentSessionGoto [N]` / `:AgentSession [N]` | Jump to session tab N |
| `:AgentSessionNew [name] [agent]` | Start a session. A single argument matching an agent (`:AgentSessionNew codex`) picks the agent; otherwise it names the session. No arguments opens the agent picker. |
| `:AgentSessionSelectAgent` | Pick an agent and launch it |
| `:AgentSessionList` | Pick a session to switch to |
| `:AgentSessionSidebar` / `:AgentSessionTree` | Toggle the sidebar explorer |
| `:AgentSessionPrompt [target] [prompt]` | Send a prompt to a session (picker if omitted). Alias: `:AgentSessionSendCommand` |
| `:AgentSessionPipe [source] [target] [instruction]` | Send one session's output to another, with an optional instruction |
| `:AgentSessionRename [name] [target]` | Rename the current or given session |
| `:AgentSessionDelete [target]` | Stop and remove the current or given session |
| `:AgentSessionRestore` | Relaunch the sessions saved for this project and resume their conversations (see [Restoring sessions](#restoring-sessions-after-a-restart)) |
| `:AgentSessionRestore!` | Discard the saved sessions for this project |
| `:AgentSessionSendLine` | Send `@file:line` (normal) or `@file:start-end` (visual) to the active session |
| `:AgentSessionSendLineTo [target]` | Same, to a chosen session |
| `:AgentSessionSendFile` | Send `@file` for the current buffer to the active session |
| `:AgentSessionSendFileTo [target]` | Same, to a chosen session |
| `:AgentSessionTestNotify [delay] [msg]` | Send a test desktop notification |

Full reference: `:help agent-session`.

## Keymaps

**Session window, terminal mode**

- `<C-\><C-\>`: back to normal mode. Never sends `Esc`, so it never interrupts a running agent.

**Session window, normal mode**

- `z` / `Z` / `<C-w>z` / `<C-w>m`: toggle zoom
- `q` / `<Esc>`: hide the window
- `]a` / `]b` / `]s`, `[a` / `[b` / `[s`: next / previous session
- `1`-`9` / `1gt`-`9gt` / `]1`-`]9`: jump to session tab 1-9
- `R`: rename session
- `i` / `a` / `<CR>`: back to terminal input

**Sidebar**

- `<CR>` / `o`: open session, `z` / `Z`: open zoomed
- `n`: new named session, `a`: pick agent and launch
- `r`: rename, `p`: send prompt, `P`: pipe output, `d` / `x`: delete
- `e`: expand/collapse height, `+` / `-` / `>` / `<`: resize, `=`: reset size
- `R`: refresh, `q` / `<Esc>`: close

## Configuration

<details>
<summary>Default options</summary>

```lua
require("agent-session").setup({
  default_agent = "claude",
  agents = {
    claude = { cmd = "claude", args = {}, env = {}, icon = "✻" },
    codex = { cmd = "codex", args = {}, env = {}, icon = "󰡨" },
    gemini = { cmd = "gemini", args = {}, env = {}, icon = "󰛄" },
    copilot = { cmd = "copilot", args = {}, env = {}, icon = "" },
    aider = { cmd = "aider", args = {}, env = {}, icon = "🤖" },
    kimi = { cmd = "kimi", args = {}, env = {}, icon = "🌙" },
    deepseek = { cmd = "deepseek", args = {}, env = {}, icon = "🐋" },
    dsh = { cmd = "dsh", args = {}, env = {}, icon = "🐋" },
    pi = { cmd = "pi", args = {}, env = {}, icon = "π" },
    omp = { cmd = "omp", args = {}, env = {}, icon = "π" },
    agy = { cmd = "agy", args = {}, env = {}, icon = "" },
    sh = { cmd = vim.o.shell, args = {}, env = {}, icon = "" },
  },
  -- Brand color per agent icon. Keys match `agents` / `agent_icons`.
  agent_colors = {
    claude = "#d97757",
    codex = "#10a37f",
    gemini = "#4285f4",
    copilot = "#8957e5",
    aider = "#14b8a6",
    kimi = "#7c5cff",
    deepseek = "#4d6bfe",
    pi = "#f2a73b",
    agy = "#a78bfa",
    qwen = "#615ced",
    sh = "#6272a4",
  },
  -- Global keymaps that work in both normal and terminal mode. None are set by default.
  -- e.g. { toggle = "<M-a>", zoom = "<M-z>", sidebar = "<M-e>", next = "<M-]>", prev = "<M-[>" }
  keymaps = {},
  ui = {
    position = "vsplit", -- "float" | "split" | "vsplit"
    width = 0.35, -- float < 1 = fraction of the screen, integer = columns
    height = 0.8,
    float_width = 0.85, -- size in float / zoom mode
    float_height = 0.85,
    border = "rounded",
    title = " Agent Session ",
    tabbar = true, -- session tab bar at the top of the window
    restore_view = true, -- keep scroll position and mode when switching sessions
    terminal_mappings = {
      enabled = true,
      escape = "<C-\\><C-\\>",
    },
  },
  sidebar = {
    position = "auto", -- "auto" (under neo-tree / nvim-tree if open, else left) | "left" | "bottom-left"
    width = 0.20,
    height = 0.35,
  },
  spinner = {
    enabled = true,
    interval = 80,
    frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  },
  idle_timeout = 1500, -- ms of silence before a session counts as idle
  notifications = {
    enabled = true,
    on_idle = true,
    on_exit = true,
    idle_delay = 2000, -- ms a session must stay idle before notifying (skips short tool pauses)
    cooldown = 4000, -- min ms between notifications for the same session
    unfocused_only = true, -- only notify for sessions not visible in any window
    terminal = "auto", -- "auto" | true | "osc777" | "osc9" | false
    system = "auto", -- OS fallback (osascript / notify-send): "auto" | true | false
  },
  status_icons = {
    running = "⚡",
    idle = "🟢",
    stopped = "⚪",
  },
  hooks = {
    on_session_start = nil, -- function(session)
    on_session_exit = nil, -- function(session, exit_code)
    on_status_change = nil, -- function(session, new_status, old_status)
  },
  persist = {
    enabled = true, -- save open sessions per project
    auto_restore = "ask", -- on startup: "ask" | true (restore silently) | false (only :AgentSessionRestore)
    max_age_days = 30, -- prune other projects' saved files untouched this long (0 = never)
  },
  session_dir = vim.fn.stdpath("data") .. "/agent-sessions",
})
```

</details>

## Development

```bash
nvim -u tests/minimal_init.lua   # isolated sandbox that loads the plugin from this checkout
stylua .                         # format
```

## License

[MIT](LICENSE)
