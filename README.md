# agent-session.nvim

A Neovim plugin for managing multiple AI agent sessions (Claude Code, terminal agents, LLM CLI sessions) with floating windows, session switching, and lifecycle management.

https://github.com/user-attachments/assets/cd545acf-2252-4ef8-a37d-2e7a003adb13

---

## Features

- **Multi-session management.** Run and track multiple background AI agent processes.
- **Interactive session tab bar.** A browser-like tab bar at the top of the window shows every active session, its status icon (⚡/🟢/⚪, animated while running), and highlights the active one.
- **Targeted prompting and session dispatch.** Send prompts or commands to a specific agent by name or through an interactive picker, without switching windows.
- **Session renaming and role tagging.** Rename sessions to assign roles such as `architect`, `coder`, `tester`, or `reviewer`.
- **Left sidebar session explorer.** A side drawer, similar to Neo-tree or Aerial, to view, launch, rename, prompt, and manage sessions.
- **Background task notifications.** Get a native desktop notification through the host terminal (Warp, Ghostty, WezTerm, or iTerm2 via OSC 777 / OSC 9) or the OS notification center (macOS `osascript`, Linux `notify-send`) when a background agent session goes idle or exits.
- **Floating and split windows.** Toggle floating modal terminals or splits.
- **Zoom and center full-view toggle.** Switch between a right-side split (compact view) and a centered full-screen float (large reading view) with `z` or `:AgentSessionZoom`.
- **Universal picker integration.** Switch sessions through `vim.ui.select` (Telescope, Snacks, fzf-lua, dressing.nvim all work).
- **Lazy.nvim, LazyVim, and AstroNvim ready.** Setup and keymapping configuration with no boilerplate.

---

## Installation and setup

### Using [lazy.nvim](https://github.com/folke/lazy.nvim) / LazyVim / AstroNvim

Add the following spec to your plugin configuration (e.g. `lua/plugins/agent-session.lua`):

```lua
return {
  "yoch/agent-session.nvim",
  cmd = {
    "AgentSession",
    "AgentSessionToggle",
    "AgentSessionZoom",
    "AgentSessionToggleZoom",
    "AgentSessionNext",
    "AgentSessionPrev",
    "AgentSessionGoto",
    "AgentSessionSidebar",
    "AgentSessionTree",
    "AgentSessionNew",
    "AgentSessionList",
    "AgentSessionSelectAgent",
    "AgentSessionPrompt",
    "AgentSessionSendCommand",
    "AgentSessionPipe",
    "AgentSessionRename",
    "AgentSessionDelete",
    "AgentSessionSendLine",
    "AgentSessionSendLineTo",
    "AgentSessionSendFile",
    "AgentSessionSendFileTo",
  },
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
    default_agent = "agy", -- "claude" | "agy" | "codex" | "gemini" | "sh"
    agents = {
      claude = { cmd = "claude", args = {}, env = {}, icon = "✻" },
      agy = { cmd = "agy", args = {}, env = {}, icon = "" },
      codex = { cmd = "codex", args = {}, env = {}, icon = "󰡨" },
      gemini = { cmd = "gemini", args = {}, env = {}, icon = "󰛄" },
      sh = { cmd = vim.o.shell, args = {}, env = {}, icon = "" },
    },
    ui = {
      position = "vsplit", -- "float" | "split" | "vsplit"
      width = 0.35,        -- 35% screen width or fixed column count
      height = 0.8,
      border = "rounded",
      title = " Agent Session ",
      terminal_mappings = {
        enabled = true,
        escape = "<C-\\><C-\\>", -- Double Ctrl-\ to exit terminal mode back to normal mode safely
      },
    },
    sidebar = {
      position = "auto", -- "auto" (bottom-left under neo-tree), "left", "bottom-left"
      width = 0.20,      -- 20% screen width (if neo-tree not open)
      height = 0.35,     -- 35% height under neo-tree (in bottom-left)
    },
    idle_timeout = 800, -- ms of silence before switching from running to idle
    notify_on_idle = true, -- notify when a background session finishes task (idle)
    notify_on_exit = true, -- notify when a background session process exits
    notifications = {
      enabled = true,
      on_idle = true,
      on_exit = true,
      idle_delay = 0, -- ms session must remain idle before notifying (0 = immediate upon idle)
      cooldown = 1000, -- minimum ms between notifications for the same session
      terminal = "auto", -- "auto" (detects Warp, WezTerm, Ghostty, iTerm2), true, "osc777", "osc9", or false
      system = "auto", -- "auto" (OS-native fallback via osascript / notify-send if terminal unsupported), true, or false
    },
    status_icons = {
      running = "⚡",
      idle = "🟢",
      stopped = "⚪",
    },
  },
}
```

### Statusline / lualine integration

You can display the active agent session status in your statusline:

```lua
-- Lualine component
{
  function()
    return require("agent-session").status()
  end,
  cond = function()
    return require("agent-session.session").get_current() ~= nil
  end,
}
```

---

## Default configuration

```lua
require("agent-session").setup({
  session_dir = vim.fn.stdpath("data") .. "/agent-sessions",
  default_agent = "claude",
  agent_icons = {
    claude = "✻",
    agy = "",
    codex = "󰡨",
    gemini = "󰛄",
    sh = "",
  },
  agents = {
    claude = {
      cmd = "claude",
      args = {},
      env = {},
      icon = "✻",
    },
    agy = {
      cmd = "agy",
      args = {},
      env = {},
      icon = "",
    },
    codex = {
      cmd = "codex",
      args = {},
      env = {},
      icon = "󰡨",
    },
    gemini = {
      cmd = "gemini",
      args = {},
      env = {},
      icon = "󰛄",
    },
    sh = {
      cmd = vim.o.shell,
      args = {},
      env = {},
      icon = "",
    },
  },
  ui = {
    position = "vsplit", -- "float", "split", "vsplit"
    width = 0.35,
    height = 0.8,
    float_width = 0.85, -- Width when in float / zoom mode
    float_height = 0.85, -- Height when in float / zoom mode
    border = "rounded",
    title = " Agent Session ",
    tabbar = true, -- Show session tab bar at top of window
    restore_view = true, -- Preserve scroll position and normal/terminal mode across session switches
    terminal_mappings = {
      enabled = true,
      escape = "<C-\\><C-\\>", -- Double Ctrl-\ to exit terminal mode back to normal mode safely
    },
  },
  sidebar = {
    position = "auto", -- "auto" (bottom-left under neo-tree if open, else left), "left", "bottom-left"
    width = 0.20, -- percentage (0.20 = 20% width) or fixed columns (e.g. 30)
    height = 0.35, -- percentage (0.35 = 35% height) or fixed lines (e.g. 12)
  },
  spinner = {
    enabled = true, -- Animated spinner for running sessions
    interval = 80, -- Milliseconds between animation frames
    frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  },
  idle_timeout = 800, -- Milliseconds of silence before marking session as idle
  notify_on_idle = true, -- Notify when a background session finishes task
  notify_on_exit = true, -- Notify when a background session process exits
  notifications = {
    enabled = true,
    on_idle = true,
    on_exit = true,
    idle_delay = 0, -- Milliseconds session must remain idle before notifying (0 = immediate upon idle)
    cooldown = 1000, -- Minimum ms between notifications for the same session
    terminal = "auto", -- "auto" (detects WarpTerminal, WezTerm, Ghostty, iTerm2), true, "osc777", "osc9", or false
    system = "auto", -- "auto" (OS-native fallback via osascript / notify-send if terminal unsupported), true, or false
  },
  status_icons = {
    running = "⚡",
    idle = "🟢",
    stopped = "⚪",
  },
  hooks = {
    on_session_start = nil,  -- function(session)
    on_session_exit = nil,   -- function(session, exit_code)
    on_status_change = nil,  -- function(session, new_status, old_status)
  },
})
```

---

## Commands

| Command | Description |
| :--- | :--- |
| `:AgentSession` / `:AgentSessionToggle` | Toggle current active session window |
| `:AgentSessionZoom` / `:AgentSessionToggleZoom` | Toggle between center full (float) screen and side split view |
| `:AgentSessionNext` / `:AgentSession next` | Switch to next agent session (chronological order) |
| `:AgentSessionPrev` / `:AgentSession prev` | Switch to previous agent session |
| `:AgentSessionGoto [N]` / `:AgentSession [N]` | Jump directly to agent session by tab index number |
| `:AgentSessionNew [name] [agent]` | Spawn a new agent session. A single argument that matches a registered agent (e.g. `:AgentSessionNew agy`) is treated as the agent; otherwise it's used as the session name. With no arguments, opens the agent picker. |
| `:AgentSessionSelectAgent` | Open interactive picker to choose which agent to launch |
| `:AgentSessionList` | Open interactive session picker to switch active session |
| `:AgentSessionSidebar` / `:AgentSessionTree` | Toggle the left sidebar session explorer |
| `:AgentSessionPrompt [target] [prompt]` | Send prompt/command to a specific session (interactive picker if omitted) |
| `:AgentSessionSendCommand [target] [prompt]` | Alias for `:AgentSessionPrompt` |
| `:AgentSessionPipe [source] [target] [instruction]` | Pipe output from one session into another session with optional instruction |
| `:AgentSessionRename [name] [target]` | Rename current session or specified session |
| `:AgentSessionDelete [target]` | Terminate and remove current or specified session |
| `:AgentSessionSendLine` | Send `@file:line` (normal mode) or `@file:start-end` (visual mode) to active session |
| `:AgentSessionSendLineTo [target]` | Send line/selection reference directly to a chosen target session |
| `:AgentSessionSendFile` | Send `@file` (whole current buffer) to active session |
| `:AgentSessionSendFileTo [target]` | Send whole buffer reference directly to a chosen target session |
| `:AgentSession status [idle|running]` | Check or set current session status |
| `:AgentSessionTestNotify [delay] [msg]` | Send a test desktop notification (terminal OSC or OS-native fallback) |

### Session window keymaps and keyboard controls

#### Terminal input mode (`t` mode)
When typing inside an Agent Session window:

- `<C-\><C-\>`: exit terminal mode directly to normal mode. It never sends `Esc` and never stops a running agent.
- Global keymaps (e.g. `<C-t>` / `<leader>az`) configured with `mode = { "n", "t" }` fire directly from terminal mode, no extra step.

#### Normal mode (`n` mode)
When in normal mode inside an Agent Session window:

- `z` / `Z` / `<C-w>z` / `<C-w>m`: toggle zoom (center full float vs. side split)
- `q` / `<Esc>`: hide or close the session window
- `]b` / `]s` / `]a`: cycle to the next agent session
- `[b` / `[s` / `[a`: cycle to the previous agent session
- `1`-`9` / `1gt`-`9gt` / `]1`-`]9`: jump directly to session tab 1-9
- `R`: rename the current session
- `i` / `a` / `<CR>`: enter terminal input mode

---

## Local testing

You can test the plugin in an isolated environment without affecting your main Neovim config:

```bash
nvim -u tests/minimal_init.lua
```

---

## Project structure

```text
agent-session.nvim/
├── doc/
│   └── agent-session.txt       # Vimdoc help file (:help agent-session)
├── lua/
│   └── agent-session/
│       ├── init.lua            # Public API entry point
│       ├── config.lua          # Default configuration and options
│       ├── session.lua         # Session model and process manager
│       ├── ui.lua              # Floating window and vim.ui.select picker
│       ├── sidebar.lua         # Left-docked session explorer
│       └── statusline.lua      # Lualine / Heirline / AstroNvim status formatters
├── plugin/
│   └── agent-session.lua       # User commands and autocommands
├── tests/
│   └── minimal_init.lua        # Lazy.nvim isolated repro and test harness
├── .luarc.json                 # Lua Language Server settings
├── .stylua.toml                # StyLua formatting config
├── .gitignore
└── README.md
```
