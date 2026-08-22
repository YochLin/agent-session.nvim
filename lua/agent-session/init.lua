local config = require("agent-session.config")
local session = require("agent-session.session")
local ui = require("agent-session.ui")

local M = {}

---Initialize agent-session.nvim with user configuration
---@param opts? AgentSessionConfig
function M.setup(opts)
  config.setup(opts)
end

---Create a new agent session and open its UI
---@param name? string Session name or agent name
---@param agent_name? string Agent name (e.g. "claude", "agy", "codex")
---@return Session|nil
function M.new_session(name, agent_name)
  local opts = config.get()
  local agents = opts.agents or {}

  -- If single argument passed and it matches a registered agent or executable, treat as agent_name
  if name and not agent_name and (agents[name] ~= nil or vim.fn.executable(name) == 1) then
    agent_name = name
    name = nil
  end

  -- If no arguments provided at all, open interactive agent picker
  if not name and not agent_name then
    ui.select_agent(function(selected_agent)
      local sess = session.create(nil, selected_agent)
      ui.open(sess, { focus_input = true })
    end)
    return nil
  end

  local sess = session.create(name, agent_name)
  ui.open(sess, { focus_input = true })
  return sess
end

---Open interactive picker to select an agent
---@param on_select? fun(agent_name: string) Called with the chosen agent instead of the default create+open
function M.select_agent(on_select)
  ui.select_agent(function(selected_agent)
    if on_select then
      on_select(selected_agent)
    else
      local sess = session.create(nil, selected_agent)
      ui.open(sess, { focus_input = true })
    end
  end)
end

---Toggle current session floating/split window
function M.toggle()
  ui.toggle()
end

---Open session selector picker
function M.list_sessions()
  ui.select_session(function(sess)
    ui.open(sess)
  end)
end

---Send prompt / command text to active session
---@param text string
function M.send(text)
  local cur = session.get_current()
  if cur then
    session.send_text(cur.id, text)
  else
    vim.notify("[agent-session] No active session to send text to", vim.log.levels.WARN)
  end
end

---@return Session|nil, string|nil path Current session and current buffer's relative path, or nil + notifies on failure
local function current_session_and_path()
  local cur = session.get_current()
  if not cur then
    vim.notify("[agent-session] No active session to send to", vim.log.levels.WARN)
    return nil
  end

  local path = vim.fn.expand("%:.")
  if path == "" then
    vim.notify("[agent-session] Current buffer has no file path", vim.log.levels.WARN)
    return nil
  end

  return cur, path
end

---Send a `@file:line` (or `@file:start-end` for a visual range) reference for the
---current buffer to the active session's input, without submitting it, so the
---user can add a prompt before pressing enter.
---@param line1? integer Start line (defaults to current line, or the live visual selection)
---@param line2? integer End line (defaults to line1)
function M.send_line_ref(line1, line2)
  local cur, path = current_session_and_path()
  if not cur then
    return
  end

  if not line1 then
    -- opts.line1/line2 from a bare `<Cmd>` invocation always default to the cursor
    -- line, even mid-visual-selection (marks '< / '> aren't updated until the
    -- selection ends) — so read the live selection directly via mode()/line("v").
    local mode = vim.fn.mode()
    if mode == "v" or mode == "V" or mode == "\22" then
      line1, line2 = vim.fn.line("v"), vim.fn.line(".")
      if line1 > line2 then
        line1, line2 = line2, line1
      end
      vim.cmd("normal! \27") -- leave visual mode
    else
      line1 = vim.fn.line(".")
    end
  end
  line2 = line2 or line1

  local ref = line1 == line2 and string.format("@%s:%d", path, line1) or string.format("@%s:%d-%d", path, line1, line2)

  session.send_text(cur.id, ref .. " ", false)
  ui.open(cur, { focus_input = true })
end

---Send a `@file` reference for the whole current buffer to the active session's
---input, without submitting it, so the user can add a prompt before pressing enter.
function M.send_file_ref()
  local cur, path = current_session_and_path()
  if not cur then
    return
  end

  session.send_text(cur.id, "@" .. path .. " ", false)
  ui.open(cur, { focus_input = true })
end

---Rename the current or specified session
---@param new_name? string
---@param id? string
function M.rename_session(new_name, id)
  id = id or (session.get_current() and session.get_current().id)
  if not id then
    vim.notify("[agent-session] No session selected to rename", vim.log.levels.WARN)
    return
  end

  if new_name and new_name ~= "" then
    session.rename(id, new_name)
    return
  end

  local cur = session.get(id)
  vim.ui.input({ prompt = "Rename session: ", default = cur and cur.name or "" }, function(input)
    if input and vim.trim(input) ~= "" then
      session.rename(id, input)
    end
  end)
end

---Delete the current or specified session
---@param id? string
function M.delete_session(id)
  id = id or (session.get_current() and session.get_current().id)
  if not id then
    vim.notify("[agent-session] No session selected to delete", vim.log.levels.WARN)
    return
  end
  ui.close_window()
  session.delete(id)
  vim.notify("[agent-session] Deleted session " .. id, vim.log.levels.INFO)
end

---Get formatted status string for statusline / lualine
---@return string
function M.status()
  local cur = session.get_current()
  if not cur then
    return ""
  end
  local opts = config.get()
  local icons = opts.status_icons or { running = "⚡", idle = "🟢", stopped = "⚪" }
  local icon = icons[cur.status] or ""
  return string.format("%s %s", icon, cur.status)
end

---Manually set status of a session
---@param new_status "running"|"idle"|"stopped"
---@param id? string
function M.set_status(new_status, id)
  id = id or (session.get_current() and session.get_current().id)
  if id then
    session.set_status(id, new_status)
  end
end

---Toggle the Left Sidebar Session Explorer
function M.toggle_sidebar()
  require("agent-session.sidebar").toggle()
end

---Open the Left Sidebar Session Explorer
function M.open_sidebar()
  require("agent-session.sidebar").open()
end

---Close the Left Sidebar Session Explorer
function M.close_sidebar()
  require("agent-session.sidebar").close()
end

---Get AstroNvim / Heirline component
---@param opts? table
---@return table
function M.astronvim_component(opts)
  return require("agent-session.statusline").astronvim(opts)
end

---Export modules for advanced usage
M.session = session
M.ui = ui
M.sidebar = require("agent-session.sidebar")
M.config = config
M.statusline = require("agent-session.statusline")

return M
