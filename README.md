# agent-session.nvim 🤖

A modern, extensible Neovim plugin for managing multiple AI agent sessions (e.g. Claude Code, terminal agents, LLM CLI sessions) with floating windows, session switching, and lifecycle management.

---

## ✨ Features

- ⚡ **Multi-Session Management**: Run and track multiple background AI agent processes.
- 🎯 **Targeted Prompting & Session Dispatch**: Send prompts or commands to specific agents by friendly name or interactive picker without switching contexts.
- 🏷️ **Session Renaming & Role Tagging**: Rename sessions easily to assign clear roles (e.g. `architect`, `coder`, `tester`, `reviewer`).
- 🗂️ **Left Sidebar Session Explorer**: Interactive side drawer list (like Neo-tree / Aerial) to view, launch, rename, prompt, and manage sessions.
- 🪟 **Floating & Split Windows**: Toggle floating modal terminals or splits seamlessly.
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
    { "<leader>at", "<cmd>AgentSessionToggle<cr>", desc = "Toggle Agent Session Window" },
    { "<leader>ae", "<cmd>AgentSessionSidebar<cr>", desc = "Toggle Agent Explorer (Sidebar)" },
    { "<leader>an", "<cmd>AgentSessionNew<cr>", desc = "New Agent Session (Interactive)" },
    { "<leader>aa", "<cmd>AgentSessionSelectAgent<cr>", desc = "Select & Launch Agent" },
    { "<leader>al", "<cmd>AgentSessionList<cr>", desc = "List Active Sessions" },
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
    },
    sidebar = {
      position = "auto", -- "auto" (bottom-left under neo-tree), "left", "bottom-left"
      width = 0.20,      -- 20% screen width (if neo-tree not open)
      height = 0.35,     -- 35% height under neo-tree (in bottom-left)
    },
    idle_timeout = 800, -- ms of silence before switching from running to idle
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
  },
  idle_timeout = 800, -- Milliseconds of silence before marking session as idle
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
| `:AgentSessionNew [agent\|name] [agent]` | Spawn a new agent session (e.g. `:AgentSessionNew agy`) |
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
| `:AgentSession status [idle\|running]` | Check or set current session status |

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
