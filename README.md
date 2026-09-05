# agent-session.nvim 🤖

A modern, extensible Neovim plugin for managing multiple AI agent sessions (e.g. Claude Code, terminal agents, LLM CLI sessions) with floating windows, session switching, and lifecycle management.

https://github.com/user-attachments/assets/cd545acf-2252-4ef8-a37d-2e7a003adb13

---

## ✨ Features

- ⚡ **Multi-Session Management**: Run and track multiple background AI agent processes concurrently.
- 📑 **Interactive Session Tab Bar**: Browser-like tab bar at the top of the window showing all active sessions, live animated spinners/status icons (⚡/🟢/⚪), and highlighting the active session.
- 🎯 **Targeted Prompting & Session Dispatch**: Send prompts or commands to specific agents by friendly name or interactive picker without switching contexts.
- 🏷️ **Session Renaming & Role Tagging**: Rename sessions easily to assign clear roles (e.g. `architect`, `coder`, `tester`, `reviewer`).
- 🗂️ **Left Sidebar Session Explorer**: Interactive side drawer list (like Neo-tree / Aerial) to view, launch, rename, prompt, and manage sessions with smart auto-docking beneath file trees.
- 🔔 **Background Task Notifications**: Receive automatic notifications (`vim.notify` / nvim-notify / Snacks) when unfocused background agent sessions complete tasks (idle) or exit.
- 🪟 **Floating & Split Windows**: Toggle floating modal terminals or splits (`vsplit`, `split`, `float`) seamlessly.
- 🔍 **Zoom & Center Full View Toggle**: Instantly switch between right-side split (compact view) and centered full-screen float (large reading view) with `z` or `:AgentSessionZoom`.
- 🔗 **Inter-Session Piping**: Pipe previous session output or context directly into another agent session via `:AgentSessionPipe`.
- 📌 **Code & File References**: Send `@file:line`, `@file:start-end`, or whole buffer references (`@file`) straight to active or target sessions.
- 🔍 **Universal Picker Integration**: Switch sessions easily using `vim.ui.select` (supports Telescope, Snacks, fzf-lua, dressing.nvim).
- 📊 **Statusline / Lualine / Heirline / AstroNvim Ready**: Built-in statusline components with status colors and reactive event updates.
- 🧩 **Lazy.nvim & LazyVim & AstroNvim Ready**: Zero-boilerplate setup and keymapping configuration.

---

## 📦 Installation & Setup

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
      claude = { cmd = "claude", args = {}, env = {} },
      agy = { cmd = "agy", args = {}, env = {} },
      codex = { cmd = "codex", args = {}, env = {} },
      gemini = { cmd = "gemini", args = {}, env = {} },
      sh = { cmd = vim.o.shell, args = {}, env = {} },
    },
    ui = {
      position = "vsplit", -- "float" | "split" | "vsplit"
      width = 0.35,        -- 35% screen width or fixed column count
      height = 0.8,
      float_width = 0.85,  -- Width in float / zoom view
      float_height = 0.85, -- Height in float / zoom view
      border = "rounded",
      title = " Agent Session ",
      tabbar = true,       -- Show interactive tab bar at top of session window
      restore_view = true, -- Preserve scroll position and mode when switching sessions
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
    spinner = {
      enabled = true,
      interval = 80,
      frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    },
    idle_timeout = 800, -- ms of silence before switching from running to idle
    notify_on_idle = true, -- notify when a background session finishes task (idle)
    notify_on_exit = true, -- notify when a background session process exits
    notifications = {
      enabled = true,
      on_idle = true,
      on_exit = true,
      idle_delay = 2500, -- ms session must remain idle before notifying (avoids subagent / tool pause flickers)
      cooldown = 5000, -- minimum ms between notifications for the same session
    },
    status_icons = {
      running = "⚡",
      idle = "🟢",
      stopped = "⚪",
    },
    auto_title = {
      enabled = true,      -- Automatically rename session to a short summary of the first prompt
      max_length = 24,     -- Maximum length for local heuristic title
      ai = {
        enabled = false,   -- Enable AI-powered semantic summarization
        provider = "openai", -- "openai" | "gemini" | "ollama" | "anthropic" | "custom"
        model = "gpt-4o-mini",
        api_key = nil,     -- Defaults to OPENAI_API_KEY / GEMINI_API_KEY / etc.
      },
    },
  },
}
```

---

## 📊 Statusline & Lualine Integration

`agent-session.nvim` provides preconfigured components for statuslines with dynamic status highlight colors and click actions:

### Lualine Component

```lua
-- In your lualine configuration:
sections = {
  lualine_x = {
    -- Built-in lualine component with dynamic status coloring & click-to-toggle
    require("agent-session.statusline").lualine(),
  },
}
```

Or using the standard status helper:

```lua
{
  function()
    return require("agent-session").status()
  end,
  cond = function()
    return require("agent-session.session").get_current() ~= nil
  end,
}
```

### AstroNvim & Heirline Component

```lua
-- Heirline / AstroNvim component with reactive event updates and AstroUI builder integration
local agent_status = require("agent-session.statusline").astronvim({
  show_empty = false,
  icon_only = false,
  click_action = "list", -- "list" | "sidebar" | "toggle"
})
```

---

## ⚙️ Default Configuration

```lua
require("agent-session").setup({
  session_dir = vim.fn.stdpath("data") .. "/agent-sessions",
  default_agent = "claude",
  agents = {
    claude = {
      cmd = "claude",
      args = {},
      env = {},
    },
    agy = {
      cmd = "agy",
      args = {},
      env = {},
    },
    codex = {
      cmd = "codex",
      args = {},
      env = {},
    },
    gemini = {
      cmd = "gemini",
      args = {},
      env = {},
    },
    sh = {
      cmd = vim.o.shell,
      args = {},
      env = {},
    },
  },
  keymaps = {
    toggle = false,  -- Global shortcut to toggle session window (e.g. "<C-t>", modes: n, t)
    zoom = false,    -- Global shortcut to toggle zoom / full screen (modes: n, t)
    sidebar = false, -- Global shortcut to toggle sidebar explorer (modes: n, t)
    next = false,    -- Global shortcut to cycle to next session (modes: n, t)
    prev = false,    -- Global shortcut to cycle to previous session (modes: n, t)
  },
  ui = {
    position = "vsplit", -- "float", "split", "vsplit"
    width = 0.35,
    height = 0.8,
    float_width = 0.85,  -- Width when in float / zoom mode
    float_height = 0.85, -- Height when in float / zoom mode
    border = "rounded",
    title = " Agent Session ",
    tabbar = true,       -- Show session tab bar at top of window
    restore_view = true, -- Preserve scroll position and normal/terminal mode across session switches
    terminal_mappings = {
      enabled = true,
      escape = "<C-\\><C-\\>", -- Double Ctrl-\ to exit terminal mode back to normal mode safely
    },
  },
  sidebar = {
    position = "auto", -- "auto" (bottom-left under neo-tree if open, else left), "left", "bottom-left"
    width = 0.20,      -- percentage (0.20 = 20% width) or fixed columns (e.g. 30)
    height = 0.35,     -- percentage (0.35 = 35% height) or fixed lines (e.g. 12)
  },
  spinner = {
    enabled = true,
    interval = 80, -- ms between animation frames
    frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  },
  idle_timeout = 800, -- Milliseconds of silence before marking session as idle
  notify_on_idle = true, -- Notify when a background session transitions to idle
  notify_on_exit = true, -- Notify when a background session process exits
  notifications = {
    enabled = true,
    on_idle = true,
    on_exit = true,
    idle_delay = 2500, -- Milliseconds session must remain continuously idle before notifying (avoids subagent flickers)
    cooldown = 5000, -- Minimum ms between consecutive notifications for the same session
  },
  status_icons = {
    running = "⚡",
    idle = "🟢",
    stopped = "⚪",
  },
  hooks = {
    on_session_start = nil, -- function(session)
    on_session_exit = nil,  -- function(session, exit_code)
    on_status_change = nil, -- function(session, new_status, old_status)
  },
})
```

---

## ⌨️ Commands

| Command | Description |
| :--- | :--- |
| `:AgentSession` / `:AgentSessionToggle` | Toggle current active session window |
| `:AgentSessionZoom` / `:AgentSessionToggleZoom` | Toggle between center full (float) screen and side split view |
| `:AgentSessionNext` / `:AgentSession next` | Switch to next agent session (chronological order) |
| `:AgentSessionPrev` / `:AgentSession prev` | Switch to previous agent session |
| `:AgentSessionGoto [N]` / `:AgentSession [N]` | Jump directly to agent session by tab index number (e.g. `:AgentSession 1`) |
| `:AgentSessionNew [agent\|name] [agent]` | Spawn a new agent session (e.g. `:AgentSessionNew agy`) |
| `:AgentSessionSelectAgent` | Open interactive picker to choose which agent to launch |
| `:AgentSessionList` | Open interactive session picker to switch active session |
| `:AgentSessionSidebar` / `:AgentSessionTree` | Toggle left sidebar session explorer |
| `:AgentSessionPrompt [target] [prompt]` | Send prompt/command to a specific session (interactive picker if omitted) |
| `:AgentSessionSendCommand [target] [prompt]` | Alias for `:AgentSessionPrompt` |
| `:AgentSessionPipe [source] [target] [instruction]` | Pipe output from one session into another session with optional instruction |
| `:AgentSessionRename [name] [target]` | Rename current session or specified session |
| `:AgentSessionDelete [target]` | Terminate and remove current or specified session |
| `:AgentSessionSendLine` | Send `@file:line` (normal mode) or `@file:start-end` (visual mode) to active session |
| `:AgentSessionSendLineTo [target]` | Send line/selection reference directly to a chosen target session |
| `:AgentSessionSendFile` | Send `@file` (whole current buffer) to active session |
| `:AgentSessionSendFileTo [target]` | Send whole buffer reference directly to a chosen target session |
| `:AgentSession status [idle\|running]` | Check or set current session status |

---

## 🔀 Keyboard Shortcuts & Keymaps

### 1. Terminal Window Keymaps

#### ⚡ Terminal Input Mode (`t` mode)
- `<C-\><C-\\>` : **Exit Terminal Mode** directly to Normal Mode (**100% safe, never sends `Esc`, never stops running agents**).
- Global keymaps configured with `mode = { "n", "t" }` can be triggered directly in 1 step from terminal mode.

#### 🛋️ Normal Mode (`n` mode inside session buffer)
- `z` / `Z` / `<C-w>z` / `<C-w>m` : **Toggle Zoom** (Center Full Float ⟷ Side Split)
- `q` / `<Esc>` : **Hide / Close** session window (keeps session running in background)
- `]b` / `]s` / `]a` : Cycle to **Next** Agent Session
- `[b` / `[s` / `[a` : Cycle to **Previous** Agent Session
- `1` ~ `9` / `1gt` ~ `9gt` / `]1` ~ `]9` : Jump directly to Session Tab **1 ~ 9**
- `R` : **Rename** current session
- `i` / `a` / `<CR>` : Enter Terminal Input Mode

---

### 2. 🗂️ Left Sidebar Explorer Keymaps

When focused inside the Left Sidebar Session Explorer buffer:

| Keymap | Action |
| :--- | :--- |
| `<CR>` / `o` | Open session under cursor |
| `z` / `Z` | Open session in **Zoomed Centered Float** |
| `n` | Create **New** session (prompts for name & agent) |
| `a` | Select Agent CLI and launch |
| `r` | **Rename** session under cursor |
| `p` | Send **Prompt** / command to session under cursor |
| `P` | **Pipe** output from session under cursor to another session |
| `d` / `x` | **Delete** / terminate session under cursor |
| `e` | **Expand / shrink** sidebar height (50% ⟷ 25%) or width (40% ⟷ 20%) |
| `+` / `-` (`<C-Up>` / `<C-Down>`) | Increase / decrease sidebar height |
| `>` / `<` (`<C-Right>` / `<C-Left>`) | Increase / decrease sidebar width |
| `=` | Reset sidebar to default width & height |
| `R` | Refresh session list and statuses |
| `q` / `<Esc>` | Close sidebar explorer |
| `<2-LeftMouse>` | Double click to open session under cursor |

---

## 🛠️ Lua API Reference

You can call all features programmatically in your Lua configs and custom keymaps via `require("agent-session")`:

```lua
local agent_session = require("agent-session")

-- Window & layout controls
agent_session.toggle()                     -- Toggle active session window
agent_session.toggle_zoom()                -- Toggle between center full float and side split
agent_session.toggle_sidebar()             -- Toggle left sidebar explorer
agent_session.open_sidebar()               -- Open sidebar explorer
agent_session.close_sidebar()              -- Close sidebar explorer

-- Session navigation & lifecycle
agent_session.new_session(name, agent)     -- Create new session (interactive if nil)
agent_session.select_agent(on_select)      -- Open agent selector picker
agent_session.list_sessions()              -- Open session selector picker via vim.ui.select
agent_session.next_session(opts)           -- Cycle to next session
agent_session.prev_session(opts)           -- Cycle to previous session
agent_session.goto_session(index, opts)    -- Jump directly to session index (1-based)
agent_session.rename_session(new_name, target) -- Rename session
agent_session.delete_session(target)       -- Terminate and remove session

-- Text dispatch, references & piping
agent_session.send(text)                   -- Send text into active session
agent_session.prompt_session(target, text, opts) -- Send prompt to specific or picked session
agent_session.pipe_session(src, dst, inst, opts) -- Pipe output from src to dst session
agent_session.send_line_ref(line1, line2)  -- Send @file:line to active session
agent_session.send_line_ref_to(target, line1, line2) -- Send @file:line to target session
agent_session.send_file_ref()              -- Send @file to active session
agent_session.send_file_ref_to(target)     -- Send @file to target session

-- Status & integrations
agent_session.status()                     -- Formatted status string for statusline (e.g. "⚡ running")
agent_session.set_status(status, id)       -- Manually update session status
```

---

## 🔔 Events & Autocommands

`agent-session.nvim` emits Neovim `User` autocommands for easy hook-ins and reactive UI updates:

- `AgentSessionStatusChanged`: Triggered whenever a session status changes (`running`, `idle`, `stopped`). `data` includes `{ session_id, name, status, old_status }`.
- `AgentSessionCurrentChanged`: Triggered whenever the active focused session changes. `data` includes `{ session_id }`.

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "AgentSessionStatusChanged",
  callback = function(args)
    local data = args.data or {}
    -- e.g. custom notification or statusline trigger
  end,
})
```

---

## 🧪 Local Testing

You can test the plugin in an isolated environment without affecting your main Neovim config:

```bash
nvim -u tests/minimal_init.lua
```

---

## 📁 Project Structure

```text
agent-session.nvim/
├── doc/
│   └── agent-session.txt       # Vimdoc help file (:help agent-session)
├── lua/
│   └── agent-session/
│       ├── init.lua            # Public API entry point
│       ├── config.lua          # Default configuration & options
│       ├── session.lua         # Session model & process manager
│       ├── sidebar.lua         # Left sidebar explorer drawer
│       ├── statusline.lua      # Lualine / Heirline / AstroNvim components
│       └── ui.lua              # Window management & vim.ui.select picker
├── plugin/
│   └── agent-session.lua       # User commands & autocommands
├── tests/
│   └── minimal_init.lua        # Lazy.nvim isolated repro & test harness
├── .luarc.json                 # Lua Language Server settings
├── .stylua.toml                # StyLua formatting config
├── .gitignore
└── README.md
```

