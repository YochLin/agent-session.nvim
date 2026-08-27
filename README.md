# agent-session.nvim 🤖

A modern, extensible Neovim plugin for managing multiple AI agent sessions (e.g. Claude Code, terminal agents, LLM CLI sessions) with floating windows, session switching, and lifecycle management.

---

## ✨ Features

- ⚡ **Multi-Session Management**: Run and track multiple background AI agent processes.
- 📑 **Interactive Session Tab Bar**: Browser-like tab bar at the top of the window showing all active sessions, status icons (⚡/🟢/⚪), and highlighting the active session.
- 🎯 **Targeted Prompting & Session Dispatch**: Send prompts or commands to specific agents by friendly name or interactive picker without switching contexts.
- 🏷️ **Session Renaming & Role Tagging**: Rename sessions easily to assign clear roles (e.g. `architect`, `coder`, `tester`, `reviewer`).
- 🗂️ **Left Sidebar Session Explorer**: Interactive side drawer list (like Neo-tree / Aerial) to view, launch, rename, prompt, and manage sessions.
- 🔔 **Background Task Notifications**: Receive automatic notifications (`vim.notify` / nvim-notify / Snacks) when unfocused background agent sessions complete tasks (idle) or exit.
- 🪟 **Floating & Split Windows**: Toggle floating modal terminals or splits seamlessly.
- 🔍 **Zoom & Center Full View Toggle**: Instantly switch between right-side split (compact view) and centered full-screen float (large reading view) with `z` or `:AgentSessionZoom`.
- 🔍 **Universal Picker Integration**: Switch sessions easily using `vim.ui.select` (supports Telescope, Snacks, fzf-lua, dressing.nvim).
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
      idle_delay = 2500, -- ms session must remain idle before notifying (avoids subagent / tool pause flickers)
      cooldown = 5000, -- minimum ms between notifications for the same session
    },
    status_icons = {
      running = "⚡",
      idle = "🟢",
      stopped = "⚪",
    },
  },
}
```

### Statusline / Lualine Integration

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
  },
  ui = {
    position = "float", -- "float", "split", "vsplit"
    width = 0.85,
    height = 0.8,
    border = "rounded",
    title = " Agent Session ",
    terminal_mappings = {
      enabled = true,
      escape = "<C-\\><C-\\>", -- Double Ctrl-\ to exit terminal mode back to normal mode safely
    },
  },
  idle_timeout = 800, -- Milliseconds of silence before marking session as idle
  notify_on_idle = true, -- Notify when a background session finishes task
  notify_on_exit = true, -- Notify when a background session process exits
  notifications = {
    enabled = true,
    on_idle = true,
    on_exit = true,
    idle_delay = 2500, -- Milliseconds session must remain idle before notifying (avoids subagent flickers)
    cooldown = 5000, -- Minimum ms between notifications for the same session
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

## ⌨️ Commands

| Command | Description |
| :--- | :--- |
| `:AgentSession` / `:AgentSessionToggle` | Toggle current active session window |
| `:AgentSessionZoom` / `:AgentSessionToggleZoom` | Toggle between center full (float) screen and side split view |
| `:AgentSessionNext` / `:AgentSession next` | Switch to next agent session (chronological order) |
| `:AgentSessionPrev` / `:AgentSession prev` | Switch to previous agent session |
| `:AgentSessionGoto [N]` / `:AgentSession [N]` | Jump directly to agent session by tab index number |
| `:AgentSessionNew [agent|name] [agent]` | Spawn a new agent session (e.g. `:AgentSessionNew agy`) |
| `:AgentSessionSelectAgent` | Open interactive picker to choose which agent to launch |
| `:AgentSessionList` | Open interactive session picker to switch active session |
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

### 🔀 Session Window Keymaps & Keyboard Controls

#### ⚡ Terminal Input Mode (`t` mode)
When typing inside an Agent Session window:

- `<C-\><C-\>` : **Exit Terminal Mode** directly to Normal Mode (**100% safe, never sends `Esc`, never stops running agents**)
- Global keymaps (e.g. `<C-t>` / `<leader>az`) configured with `mode = { "n", "t" }` can be triggered directly in 1 step from terminal mode!

#### 🛋️ Normal Mode (`n` mode)
When in Normal mode inside an Agent Session window:

- `z` / `Z` / `<C-w>z` / `<C-w>m` : **Toggle Zoom** (Center Full Float ⟷ Side Split)
- `q` / `<Esc>` : **Hide / Close** session window
- `]b` / `]s` / `]a` : Cycle to **Next** Agent Session
- `[b` / `[s` / `[a` : Cycle to **Previous** Agent Session
- `1` ~ `9` / `1gt` ~ `9gt` / `]1` ~ `]9` : Jump directly to Session Tab **1 ~ 9**
- `R` : Rename current session
- `i` / `a` / `<CR>` : Enter Terminal Input Mode

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
│       └── ui.lua              # Floating window & vim.ui.select picker
├── plugin/
│   └── agent-session.lua       # User commands & autocommands
├── tests/
│   └── minimal_init.lua        # Lazy.nvim isolated repro & test harness
├── .luarc.json                 # Lua Language Server settings
├── .stylua.toml                # StyLua formatting config
├── .gitignore
└── README.md
```
