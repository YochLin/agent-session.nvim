---@class AgentSessionConfig
---@field session_dir? string Directory to save session metadata and logs
---@field default_agent? string Default agent type (e.g. "claude", "custom")
---@field agents? table<string, AgentDefinition> Pre-configured agent commands & options
---@field agent_icons? table<string, string> Icon mappings per agent CLI type (e.g. { claude = "✻", agy = "" })
---@field keymaps? AgentSessionKeymapsConfig Global keymaps working seamlessly across normal & terminal mode
---@field ui? AgentSessionUIConfig UI appearance and behavior
---@field spinner? AgentSessionSpinnerConfig Animated spinner settings
---@field hooks? table<string, fun(session: table)> Lifecycle hooks
---@field notify_on_idle? boolean Notify when a background session transitions to idle (default: true)
---@field notify_on_exit? boolean Notify when a background session exits (default: true)
---@field notifications? AgentSessionNotificationConfig Notification settings

---@class AgentSessionKeymapsConfig
---@field toggle? string|false Global shortcut to toggle session window (modes: n, t)
---@field zoom? string|false Global shortcut to toggle zoom / full screen (modes: n, t)
---@field sidebar? string|false Global shortcut to toggle sidebar explorer (modes: n, t)
---@field next? string|false Global shortcut to cycle to next session (modes: n, t)
---@field prev? string|false Global shortcut to cycle to previous session (modes: n, t)

---@class AgentSessionSpinnerConfig
---@field enabled? boolean Enable animated spinner for running sessions (default: true)
---@field interval? number Milliseconds between animation frames (default: 80)
---@field frames? string[] Animation frame characters

---@class AgentSessionNotificationConfig
---@field enabled? boolean Enable/disable all notifications (default: true)
---@field on_idle? boolean Notify when a background session transitions to idle (default: true)
---@field on_exit? boolean Notify when a background session exits (default: true)
---@field idle_delay? number Milliseconds session must remain continuously idle before notifying (default: 2000)
---@field cooldown? number Minimum milliseconds between consecutive notifications for the same session (default: 4000)
---@field unfocused_only? boolean Only send desktop notifications when session is unfocused or Neovim is in background (default: true)
---@field terminal? boolean|"auto"|"osc777"|"osc9" Send desktop notifications to host terminal (e.g. Warp, WezTerm, Ghostty, iTerm2) via OSC sequence (default: "auto")
---@field system? boolean|"auto" Send OS-native desktop notification (macOS osascript, Linux notify-send) (default: "auto", used as fallback when terminal OSC unsupported)
---@field idle_message? string|fun(session: Session):string Custom message template or function for idle notifications
---@field exit_message? string|fun(session: Session):string Custom message template or function for process exit notifications

---@class AgentDefinition
---@field cmd string|string[] Base command or function to launch agent
---@field env? table<string, string> Environment variables
---@field args? string[] Additional CLI arguments
---@field icon? string Icon or logo symbol for this agent CLI (e.g. "✻", "", "󰡨")

---@class AgentSessionTerminalMappingsConfig
---@field enabled? boolean Enable buffer-local terminal mode escape keymap (default: true)
---@field escape? string|false Key to exit terminal mode back to normal mode (default: "<C-\\><C-\\>")

---@class AgentSessionUIConfig
---@field width? number Default width (0-1 float or integer)
---@field height? number Default height (0-1 float or integer)
---@field float_width? number Center float/zoom width (0-1 float or integer, default: 0.85)
---@field float_height? number Center float/zoom height (0-1 float or integer, default: 0.85)
---@field split_width? number Side split width (0-1 float or integer, default: 0.35)
---@field split_height? number Bottom split height (0-1 float or integer, default: 0.30)
---@field border? string Border style ("rounded", "single", "double", "solid", "shadow", "none")
---@field title? string Title for session window
---@field position? "float"|"split"|"vsplit" Window position
---@field tabbar? boolean Show session tab bar at top of window (default: true)
---@field restore_view? boolean Preserve scroll position and cursor line when switching sessions (default: true)
---@field terminal_mappings? AgentSessionTerminalMappingsConfig Terminal mode keymaps configuration

local M = {}

---@type AgentSessionConfig
M.defaults = {
  session_dir = vim.fn.stdpath("data") .. "/agent-sessions",
  default_agent = "claude",
  agent_icons = {
    -- Anthropic
    claude = "✻",
    -- Google Antigravity & Gemini
    agy = "",
    antigravity = "",
    gemini = "󰛄",
    -- OpenAI
    codex = "󰡨",
    chatgpt = "󰡨",
    openai = "󰡨",
    -- DeepSeek
    dsh = "🐋",
    deepseek = "🐋",
    -- Pi / Oh My Pi Agent
    pi = "π",
    omp = "π",
    ["oh-my-pi"] = "π",
    -- Moonshot AI / Kimi
    kimi = "🌙",
    moonshot = "🌙",
    -- GitHub Copilot
    copilot = "",
    -- Aider
    aider = "🤖",
    -- Qwen
    qwen = "󰊤",
    -- Shell
    sh = "",
    bash = "",
    zsh = "",
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
    dsh = {
      cmd = "dsh",
      args = {},
      env = {},
      icon = "🐋",
    },
    deepseek = {
      cmd = "deepseek",
      args = {},
      env = {},
      icon = "🐋",
    },
    pi = {
      cmd = "pi",
      args = {},
      env = {},
      icon = "π",
    },
    omp = {
      cmd = "omp",
      args = {},
      env = {},
      icon = "π",
    },
    kimi = {
      cmd = "kimi",
      args = {},
      env = {},
      icon = "🌙",
    },
    copilot = {
      cmd = "copilot",
      args = {},
      env = {},
      icon = "",
    },
    aider = {
      cmd = "aider",
      args = {},
      env = {},
      icon = "🤖",
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
    enabled = true,
    interval = 80, -- ms between frames
    frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  },
  idle_timeout = 1500, -- Milliseconds of silence before marking session as idle
  notify_on_idle = true, -- Notify when a background session transitions to idle
  notify_on_exit = true, -- Notify when a background session process exits
  notifications = {
    enabled = true,
    on_idle = true,
    on_exit = true,
    idle_delay = 2000, -- Milliseconds session must remain continuously idle before notifying (avoids subagent/tool pause flickers)
    cooldown = 4000, -- Minimum ms between consecutive notifications for the same session
    unfocused_only = true, -- Only notify when session is unfocused or Neovim is in the background
    terminal = "auto", -- "auto" (detects WarpTerminal, WezTerm, Ghostty, iTerm2), true, "osc777", "osc9", or false
    system = "auto", -- "auto" (fallback to osascript/notify-send if terminal OSC unsupported), true, or false
  },
  status_icons = {
    running = "⚡",
    idle = "🟢",
    stopped = "⚪",
  },
  hooks = {
    on_session_start = nil,
    on_session_exit = nil,
    on_status_change = nil, -- function(session, new_status, old_status)
  },
}

---@type AgentSessionConfig
M.options = {}

---Setup configuration with user options
---@param opts? AgentSessionConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})

  -- Ensure session directory exists
  if M.options.session_dir and vim.fn.isdirectory(M.options.session_dir) == 0 then
    vim.fn.mkdir(M.options.session_dir, "p")
  end

  return M.options
end

---Get current options
---@return AgentSessionConfig
function M.get()
  if vim.tbl_isempty(M.options) then
    M.options = vim.deepcopy(M.defaults)
  end
  return M.options
end

---Get the display icon for an agent CLI
---@param agent_name? string
---@return string icon Empty string if no icon found or configured
function M.get_agent_icon(agent_name)
  if not agent_name or agent_name == "" then
    return ""
  end

  local opts = M.get()
  -- 1. Check agent definition in opts.agents
  if opts.agents and opts.agents[agent_name] and opts.agents[agent_name].icon ~= nil then
    local icon = opts.agents[agent_name].icon
    return (type(icon) == "string") and icon or ""
  end

  -- 2. Check top-level opts.agent_icons
  if opts.agent_icons and opts.agent_icons[agent_name] ~= nil then
    local icon = opts.agent_icons[agent_name]
    return (type(icon) == "string") and icon or ""
  end

  -- 3. Check defaults table
  if M.defaults.agent_icons and M.defaults.agent_icons[agent_name] then
    return M.defaults.agent_icons[agent_name]
  end

  -- 4. Specific alias / keyword checks
  local lower = agent_name:lower()
  if lower:find("claude", 1, true) then
    return M.defaults.agent_icons.claude or "✻"
  elseif lower:find("agy", 1, true) or lower:find("antigravity", 1, true) then
    return M.defaults.agent_icons.agy or ""
  elseif lower:find("deepseek", 1, true) or lower:find("dsh", 1, true) then
    return M.defaults.agent_icons.deepseek or "🐋"
  elseif lower:find("oh%-my%-pi") or lower:find("omp", 1, true) or lower:find("pi", 1, true) then
    return M.defaults.agent_icons.pi or "π"
  elseif lower:find("kimi", 1, true) or lower:find("moonshot", 1, true) then
    return M.defaults.agent_icons.kimi or "🌙"
  elseif lower:find("copilot", 1, true) then
    return M.defaults.agent_icons.copilot or ""
  elseif lower:find("codex", 1, true) or lower:find("chatgpt", 1, true) or lower:find("openai", 1, true) then
    return M.defaults.agent_icons.codex or "󰡨"
  elseif lower:find("gemini", 1, true) then
    return M.defaults.agent_icons.gemini or "󰛄"
  elseif lower:find("aider", 1, true) then
    return M.defaults.agent_icons.aider or "🤖"
  elseif lower:find("qwen", 1, true) then
    return M.defaults.agent_icons.qwen or "󰊤"
  end

  -- 5. Fuzzy fallback if agent_name contains a known agent keyword
  for known, icon in pairs(M.defaults.agent_icons or {}) do
    if lower:find(known, 1, true) then
      return icon
    end
  end

  return ""
end

local safe_notification_fallbacks = {
  claude = "✻",
  agy = "🚀",
  antigravity = "🚀",
  codex = "🤖",
  chatgpt = "🤖",
  openai = "🤖",
  gemini = "✨",
  dsh = "🐋",
  deepseek = "🐋",
  pi = "π",
  omp = "π",
  ["oh-my-pi"] = "π",
  kimi = "🌙",
  moonshot = "🌙",
  copilot = "🤖",
  aider = "🤖",
  qwen = "🪙",
  sh = "💻",
  bash = "💻",
  zsh = "💻",
}

---Check if a string contains Unicode Private Use Area (PUA) characters (e.g. Nerd Font glyphs)
---which cannot be rendered by OS system notification fonts (causing question marks [?]).
---@param str string
---@return boolean
function M.is_pua(str)
  if not str or str == "" then
    return false
  end
  for _, ch in ipairs(vim.fn.split(str, "\\zs")) do
    local cp = vim.fn.char2nr(ch)
    if (cp >= 0xE000 and cp <= 0xF8FF) or (cp >= 0xF0000 and cp <= 0x10FFFD) then
      return true
    end
  end
  return false
end

---Get an OS-safe icon for desktop notifications (avoids question mark [?] on macOS / Linux / Windows)
---@param agent_name? string
---@return string
function M.get_notification_icon(agent_name)
  if not agent_name or agent_name == "" then
    return ""
  end

  local opts = M.get()
  local notify_cfg = opts.notifications or {}

  -- 1. Explicit user override in notifications.agent_icons
  if notify_cfg.agent_icons and notify_cfg.agent_icons[agent_name] ~= nil then
    return notify_cfg.agent_icons[agent_name]
  end

  -- 2. Check standard agent icon from config if safe
  local icon = M.get_agent_icon(agent_name)
  if icon ~= "" and not M.is_pua(icon) then
    return icon
  end

  -- 3. Fallback to notification-safe mapping (standard Unicode / emojis)
  local lower = agent_name:lower()
  for name, safe_icon in pairs(safe_notification_fallbacks) do
    if lower == name or lower:find(name, 1, true) then
      return safe_icon
    end
  end

  return "🤖"
end

return M
