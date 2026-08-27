---@class AgentSessionConfig
---@field session_dir? string Directory to save session metadata and logs
---@field default_agent? string Default agent type (e.g. "claude", "custom")
---@field agents? table<string, AgentDefinition> Pre-configured agent commands & options
---@field ui? AgentSessionUIConfig UI appearance and behavior
---@field hooks? table<string, fun(session: table)> Lifecycle hooks
---@field notify_on_idle? boolean Notify when a background session transitions to idle (default: true)
---@field notify_on_exit? boolean Notify when a background session exits (default: true)
---@field notifications? AgentSessionNotificationConfig Notification settings

---@class AgentSessionNotificationConfig
---@field enabled? boolean Enable/disable all notifications (default: true)
---@field on_idle? boolean Notify when a background session transitions to idle (default: true)
---@field on_exit? boolean Notify when a background session exits (default: true)

---@class AgentDefinition
---@field cmd string|string[] Base command or function to launch agent
---@field env? table<string, string> Environment variables
---@field args? string[] Additional CLI arguments

---@class AgentSessionUIConfig
---@field width? number Float width (0-1 float or integer)
---@field height? number Float height (0-1 float or integer)
---@field border? string Border style ("rounded", "single", "double", "solid", "shadow", "none")
---@field title? string Title for session window
---@field position? "float"|"split"|"vsplit" Window position
---@field tabbar? boolean Show session tab bar at top of window (default: true)
---@field restore_view? boolean Preserve scroll position and cursor line when switching sessions (default: true)

local M = {}

---@type AgentSessionConfig
M.defaults = {
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
  ui = {
    position = "vsplit", -- "float", "split", "vsplit"
    width = 0.35,
    height = 0.8,
    border = "rounded",
    title = " Agent Session ",
    tabbar = true, -- Show session tab bar at top of window
    restore_view = true, -- Preserve scroll position and normal/terminal mode across session switches
  },
  sidebar = {
    position = "auto", -- "auto" (bottom-left under neo-tree if open, else left), "left", "bottom-left"
    width = 0.20, -- percentage (0.20 = 20% width) or fixed columns (e.g. 30)
    height = 0.35, -- percentage (0.35 = 35% height) or fixed lines (e.g. 12)
  },
  idle_timeout = 800, -- Milliseconds of silence before marking session as idle
  notify_on_idle = true, -- Notify when a background session transitions to idle
  notify_on_exit = true, -- Notify when a background session process exits
  notifications = {
    enabled = true,
    on_idle = true,
    on_exit = true,
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

return M
