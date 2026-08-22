local config = require("agent-session.config")

local M = {}

---@class Session
---@field id string Unique ID
---@field name string Session name
---@field agent string Agent key (e.g. "claude")
---@field bufnr number Terminal buffer number
---@field job_id number Terminal job ID
---@field created_at number Timestamp
---@field status "running"|"idle"|"stopped" Session status
---@field _timer userdata|nil Libuv timer for idle debouncing
---@field _saved_view table|nil Saved window view from winsaveview()
---@field _saved_mode "t"|"n"|nil Last active mode when unfocused ("t" for terminal, "n" for normal)

---@type table<string, Session>
M._active_sessions = {}
---@type string|nil
M._current_session_id = nil

---Generate a random session ID
---@return string
local function generate_id()
  return tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
end

---Get all active sessions
---@return table<string, Session>
function M.get_all()
  return M._active_sessions
end

---Get a session by ID
---@param id string
---@return Session|nil
function M.get(id)
  return M._active_sessions[id]
end

---Find a session by ID, exact name, or case-insensitive name
---@param name_or_id string
---@return Session|nil
function M.find(name_or_id)
  if not name_or_id or name_or_id == "" then
    return nil
  end

  -- 1. Exact ID match
  if M._active_sessions[name_or_id] then
    return M._active_sessions[name_or_id]
  end

  -- 2. Exact Name match
  for _, sess in pairs(M._active_sessions) do
    if sess.name == name_or_id then
      return sess
    end
  end

  -- 3. Case-insensitive Name match
  local lower = string.lower(name_or_id)
  for _, sess in pairs(M._active_sessions) do
    if string.lower(sess.name) == lower then
      return sess
    end
  end

  -- 4. Prefix match on ID or Name
  for _, sess in pairs(M._active_sessions) do
    if vim.startswith(sess.id, name_or_id) or vim.startswith(string.lower(sess.name), lower) then
      return sess
    end
  end

  return nil
end

---Get a session by buffer number
---@param bufnr number
---@return Session|nil
function M.get_by_bufnr(bufnr)
  for _, sess in pairs(M._active_sessions) do
    if sess.bufnr == bufnr then
      return sess
    end
  end
  return nil
end

---Get the currently focused session
---@return Session|nil
function M.get_current()
  if M._current_session_id then
    return M._active_sessions[M._current_session_id]
  end
  return nil
end

---Set the current active session ID
---@param id string|nil
function M.set_current(id)
  if M._current_session_id == id then
    return
  end
  M._current_session_id = id

  -- Trigger User autocommand so sidebar/statusline highlight the new current session
  vim.api.nvim_exec_autocmds("User", {
    pattern = "AgentSessionCurrentChanged",
    data = { session_id = id },
  })

  local ok_sb, sidebar_mod = pcall(require, "agent-session.sidebar")
  if ok_sb and sidebar_mod.render then
    sidebar_mod.render()
  end
end

---Set status for a session and trigger notifications & UI refresh
---@param session_or_id Session|string
---@param new_status "running"|"idle"|"stopped"
function M.set_status(session_or_id, new_status)
  local session = type(session_or_id) == "table" and session_or_id or M.get(session_or_id)
  if not session or session.status == new_status then
    return
  end

  local old_status = session.status
  session.status = new_status

  vim.schedule(function()
    local opts = config.get()
    if opts.hooks and opts.hooks.on_status_change then
      opts.hooks.on_status_change(session, new_status, old_status)
    end

    -- Trigger User autocommand for integrations (e.g. lualine, statusline)
    vim.api.nvim_exec_autocmds("User", {
      pattern = "AgentSessionStatusChanged",
      data = {
        session_id = session.id,
        name = session.name,
        status = new_status,
        old_status = old_status,
      },
    })

    -- Refresh window title / winbar
    local ok_ui, ui_mod = pcall(require, "agent-session.ui")
    if ok_ui and ui_mod.refresh_title then
      ui_mod.refresh_title(session)
    end

    -- Refresh sidebar if open
    local ok_sb, sidebar_mod = pcall(require, "agent-session.sidebar")
    if ok_sb and sidebar_mod.render then
      sidebar_mod.render()
    end
  end)
end

---Create and launch a new agent session
---@param name? string
---@param agent_name? string
---@return Session
function M.create(name, agent_name)
  local opts = config.get()
  local id = generate_id()
  name = name or ("session-" .. os.date("%m%d-%H%M"))
  agent_name = agent_name or opts.default_agent or "claude"

  local agent_def = (opts.agents and opts.agents[agent_name])
  if not agent_def then
    if vim.fn.executable(agent_name) == 1 then
      agent_def = { cmd = agent_name, args = {}, env = {} }
    else
      agent_def = { cmd = vim.o.shell, args = {}, env = {} }
    end
  end

  local cmd = agent_def.cmd
  if type(cmd) == "table" then
    cmd = vim.deepcopy(cmd)
  else
    cmd = { cmd }
  end

  if agent_def.args then
    for _, arg in ipairs(agent_def.args) do
      table.insert(cmd, arg)
    end
  end

  -- Create an unlisted buffer for the terminal
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = "hide"

  local timer = vim.loop.new_timer()

  ---@type Session
  local session = {
    id = id,
    name = name,
    agent = agent_name,
    bufnr = bufnr,
    job_id = 0,
    created_at = os.time(),
    status = "running",
    _timer = timer,
    _saved_view = nil,
    _saved_mode = "t",
  }

  M._active_sessions[id] = session
  M._current_session_id = id

  -- Track mode and view changes on session buffer
  vim.api.nvim_create_autocmd("TermEnter", {
    buffer = bufnr,
    callback = function()
      session._saved_mode = "t"
    end,
  })

  vim.api.nvim_create_autocmd("TermLeave", {
    buffer = bufnr,
    callback = function()
      session._saved_mode = "n"
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = bufnr,
    callback = function()
      local ok_ui, ui_mod = pcall(require, "agent-session.ui")
      if ok_ui and ui_mod.save_session_view then
        ui_mod.save_session_view(session)
      end
    end,
  })

  -- Build termopen options
  local term_opts = {
    cwd = vim.fn.getcwd(),
    on_exit = function(_, exit_code, _)
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
      M.set_status(session, "stopped")
      if opts.hooks and opts.hooks.on_session_exit then
        opts.hooks.on_session_exit(session, exit_code)
      end
    end,
  }
  if agent_def.env and type(agent_def.env) == "table" and next(agent_def.env) ~= nil then
    term_opts.env = agent_def.env
  end

  -- Monitor terminal output activity to detect running vs idle
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      if session.status == "stopped" then
        return
      end

      -- If not already marked as running, switch to running
      if session.status ~= "running" then
        M.set_status(session, "running")
      end

      -- Reset idle debounce timer
      if timer and not timer:is_closing() then
        timer:stop()
        timer:start(
          opts.idle_timeout or 800,
          0,
          vim.schedule_wrap(function()
            if session.status == "running" then
              M.set_status(session, "idle")
            end
          end)
        )
      end
    end,
    on_detach = function()
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end,
  })

  -- Spawn terminal in buffer
  local job_id = vim.api.nvim_buf_call(bufnr, function()
    local ok, res = pcall(vim.fn.termopen, cmd, term_opts)
    if ok and type(res) == "number" and res > 0 then
      return res
    end
    vim.notify("[agent-session] Failed to start terminal: " .. tostring(res), vim.log.levels.ERROR)
    return 0
  end)

  session.job_id = job_id
  if job_id == 0 then
    session.status = "stopped"
  else
    -- Start initial debounce timer so startup settles to idle
    if timer and not timer:is_closing() then
      timer:start(
        opts.idle_timeout or 800,
        0,
        vim.schedule_wrap(function()
          if session.status == "running" then
            M.set_status(session, "idle")
          end
        end)
      )
    end
  end
  pcall(vim.api.nvim_buf_set_name, bufnr, "agent-session://" .. name .. " (" .. id .. ")")

  if opts.hooks and opts.hooks.on_session_start then
    opts.hooks.on_session_start(session)
  end

  return session
end

---Rename a session and refresh UI (title/winbar/sidebar)
---@param id string
---@param new_name string
function M.rename(id, new_name)
  local session = M.get(id)
  new_name = new_name and vim.trim(new_name) or ""
  if not session or new_name == "" then
    return
  end

  session.name = new_name
  if vim.api.nvim_buf_is_valid(session.bufnr) then
    pcall(vim.api.nvim_buf_set_name, session.bufnr, "agent-session://" .. new_name .. " (" .. id .. ")")
  end

  vim.schedule(function()
    local ok_ui, ui_mod = pcall(require, "agent-session.ui")
    if ok_ui and ui_mod.refresh_title then
      ui_mod.refresh_title(session)
    end
    local ok_sb, sidebar_mod = pcall(require, "agent-session.sidebar")
    if ok_sb and sidebar_mod.render then
      sidebar_mod.render()
    end
  end)
end

---Send input text / prompt to the session
---@param id string
---@param text string
---Send text to a session's terminal input
---@param id string
---@param text string
---@param submit? boolean Append a newline to submit immediately (default true)
function M.send_text(id, text, submit)
  if submit == nil then
    submit = true
  end

  local session = M.get(id)
  if not session or session.status == "stopped" then
    vim.notify("[agent-session] Session is not active.", vim.log.levels.WARN)
    return
  end

  if session.job_id > 0 then
    M.set_status(session, "running")
    vim.fn.chansend(session.job_id, submit and (text .. "\n") or text)
  end
end

---Delete/kill a session
---@param id string
function M.delete(id)
  local session = M.get(id)
  if not session then
    return
  end

  if session._timer and not session._timer:is_closing() then
    session._timer:stop()
    session._timer:close()
  end

  if session.job_id > 0 and session.status ~= "stopped" then
    pcall(vim.fn.jobstop, session.job_id)
  end

  if vim.api.nvim_buf_is_valid(session.bufnr) then
    vim.api.nvim_buf_delete(session.bufnr, { force = true })
  end

  M._active_sessions[id] = nil
  if M._current_session_id == id then
    M._current_session_id = next(M._active_sessions)
  end
end

return M
