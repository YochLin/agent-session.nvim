local config = require("agent-session.config")
local uv = vim.uv or vim.loop

local M = {}

---@class Session
---@field id string Unique ID
---@field name string Session name
---@field agent string Agent key (e.g. "claude")
---@field cli_session_id string Unique CLI Session ID (UUID)
---@field bufnr number Terminal buffer number
---@field job_id number Terminal job ID
---@field created_at number Timestamp
---@field status "running"|"idle"|"stopped" Session status
---@field exit_code number|nil Process exit code
---@field _timer userdata|nil Libuv timer for idle debouncing
---@field _saved_view table|nil Saved window view from winsaveview()
---@field _saved_mode "t"|"n"|nil Last active mode when unfocused ("t" for terminal, "n" for normal)
---@field _is_initial boolean|nil Whether this is the initial startup before any task

---@type table<string, Session>
M._active_sessions = {}
---@type string|nil
M._current_session_id = nil

---Generate a standard UUIDv4 string
---@return string
local function generate_uuid()
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return (
    string.gsub(template, "[xy]", function(c)
      local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
      return string.format("%x", v)
    end)
  )
end

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

  local ok_ui, ui_mod = pcall(require, "agent-session.ui")
  if ok_ui and ui_mod.refresh_title then
    ui_mod.refresh_title()
  end

  local ok_sb, sidebar_mod = pcall(require, "agent-session.sidebar")
  if ok_sb and sidebar_mod.render then
    sidebar_mod.render()
  end
end

---Check and synchronize real process/buffer status for a session
---@param session_or_id Session|string
---@return string status
function M.sync_status(session_or_id)
  local sess = type(session_or_id) == "table" and session_or_id or M.find(session_or_id)
  if not sess then
    return "stopped"
  end

  if sess.status ~= "stopped" then
    if not sess.bufnr or not vim.api.nvim_buf_is_valid(sess.bufnr) then
      M.set_status(sess, "stopped")
    elseif sess.job_id and sess.job_id > 0 then
      local ok, res = pcall(vim.fn.jobwait, { sess.job_id }, 0)
      if ok and res and res[1] and res[1] ~= -1 then
        M.set_status(sess, "stopped")
      end
    end
  end

  return sess.status
end

---Synchronize status for all active sessions
function M.sync_all()
  for _, sess in pairs(M._active_sessions) do
    M.sync_status(sess)
  end
end

---Check if session is currently focused in the active window
---@param session Session
---@return boolean
function M.is_focused(session)
  if not session or not session.bufnr or not vim.api.nvim_buf_is_valid(session.bufnr) then
    return false
  end
  return vim.api.nvim_get_current_buf() == session.bufnr
end

---Handle background notifications when session status changes
---@param session Session
---@param new_status "running"|"idle"|"stopped"
---@param old_status "running"|"idle"|"stopped"
---@param opts AgentSessionConfig
function M._handle_status_notification(session, new_status, old_status, opts)
  local notify_cfg = opts.notifications or {}
  if notify_cfg.enabled == false then
    return
  end

  -- Don't notify if the user is actively focused on this session's buffer
  if M.is_focused(session) then
    return
  end

  if new_status == "idle" and old_status == "running" then
    -- Suppress notification on initial session spawn debounce
    if session._is_initial then
      session._is_initial = false
      return
    end

    local should_notify = notify_cfg.on_idle
    if should_notify == nil then
      should_notify = opts.notify_on_idle
    end
    if should_notify == nil then
      should_notify = true
    end

    if should_notify then
      local msg = string.format("🤖 Agent '%s' (%s) has finished task!", session.name, session.agent)
      vim.notify(msg, vim.log.levels.INFO, {
        title = "Agent Session",
        icon = "🤖",
      })
    end
  elseif new_status == "stopped" and (old_status == "running" or old_status == "idle") then
    local should_notify = notify_cfg.on_exit
    if should_notify == nil then
      should_notify = opts.notify_on_exit
    end
    if should_notify == nil then
      should_notify = true
    end

    if should_notify then
      local level = (session.exit_code and session.exit_code ~= 0) and vim.log.levels.WARN or vim.log.levels.INFO
      local msg = session.exit_code
          and string.format("Agent '%s' (%s) stopped with exit code %d", session.name, session.agent, session.exit_code)
        or string.format("Agent '%s' (%s) process stopped", session.name, session.agent)
      vim.notify(msg, level, {
        title = "Agent Session",
        icon = "⚪",
      })
    end
  end
end

---Set status for a session and trigger notifications & UI refresh
---@param session_or_id Session|string
---@param new_status "running"|"idle"|"stopped"
function M.set_status(session_or_id, new_status)
  local session = type(session_or_id) == "table" and session_or_id or M.find(session_or_id)
  if not session or session.status == new_status then
    return
  end

  local old_status = session.status
  session.status = new_status

  if new_status == "stopped" and session._timer and not session._timer:is_closing() then
    session._timer:stop()
    session._timer:close()
  end

  vim.schedule(function()
    local opts = config.get()
    if opts.hooks and opts.hooks.on_status_change then
      opts.hooks.on_status_change(session, new_status, old_status)
    end

    -- Background task notification (when unfocused / hidden)
    M._handle_status_notification(session, new_status, old_status, opts)

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

---Build command arguments for launching or resuming an agent
---@param agent_def AgentDefinition
---@param cli_session_id string
---@param is_resume boolean
---@return string[]
local function build_agent_cmd(agent_def, cli_session_id, is_resume)
  local cmd = agent_def.cmd
  if type(cmd) == "table" then
    cmd = vim.deepcopy(cmd)
  else
    cmd = { cmd }
  end

  if is_resume then
    if agent_def.resume_args and type(agent_def.resume_args) == "function" then
      local custom_args = agent_def.resume_args(cli_session_id)
      if type(custom_args) == "table" then
        for _, arg in ipairs(custom_args) do
          table.insert(cmd, arg)
        end
      end
    elseif agent_def.resume_flag then
      table.insert(cmd, agent_def.resume_flag)
      if cli_session_id and cli_session_id ~= "" then
        table.insert(cmd, cli_session_id)
      end
    end
  else
    if agent_def.session_id_flag and cli_session_id and cli_session_id ~= "" then
      table.insert(cmd, agent_def.session_id_flag)
      table.insert(cmd, cli_session_id)
    end
  end

  if agent_def.args then
    for _, arg in ipairs(agent_def.args) do
      table.insert(cmd, arg)
    end
  end

  return cmd
end

---Create and launch a new agent session
---@param name? string
---@param agent_name? string
---@param create_opts? { cli_session_id?: string, is_resume?: boolean }
---@return Session
function M.create(name, agent_name, create_opts)
  create_opts = create_opts or {}
  local opts = config.get()
  local id = generate_id()
  name = name or ("session-" .. os.date("%m%d-%H%M"))
  agent_name = agent_name or opts.default_agent or "claude"
  local cli_session_id = create_opts.cli_session_id or generate_uuid()

  local agent_def = (opts.agents and opts.agents[agent_name])
  if not agent_def then
    if vim.fn.executable(agent_name) == 1 then
      agent_def = { cmd = agent_name, args = {}, env = {} }
    else
      agent_def = { cmd = vim.o.shell, args = {}, env = {} }
    end
  end

  local cmd = build_agent_cmd(agent_def, cli_session_id, create_opts.is_resume == true)

  -- Create an unlisted buffer for the terminal
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = "hide"

  local timer = uv.new_timer()

  ---@type Session
  local session = {
    id = id,
    name = name,
    agent = agent_name,
    cli_session_id = cli_session_id,
    bufnr = bufnr,
    job_id = 0,
    created_at = os.time(),
    status = "running",
    exit_code = nil,
    _timer = timer,
    _saved_view = nil,
    _saved_mode = "t",
    _is_initial = true,
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
      session.exit_code = exit_code
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

  session._is_initial = false

  if session.job_id > 0 then
    M.set_status(session, "running")
    vim.fn.chansend(session.job_id, submit and (text .. "\n") or text)
  end
end

---Strip ANSI escape codes, OSC sequences, and carriage returns from text
---@param text string
---@return string
function M.strip_ansi(text)
  if not text or text == "" then
    return ""
  end
  local s = text:gsub("\27%[[0-9;?]*[a-zA-Z]", "")
  s = s:gsub("\27%][0-9];[^\7\27]*[\7\27\\]", "")
  s = s:gsub("\27%][0-9];[^\7]*\7", "")
  s = s:gsub("\27%([a-zA-Z0-9]", "")
  s = s:gsub("\r", "")
  return s
end

---Extract and clean output text from a session's terminal buffer
---@param session_or_id Session|string
---@param opts? { last_n?: number, full?: boolean, range?: integer[] }
---@return string|nil
function M.extract_output(session_or_id, opts)
  local sess = type(session_or_id) == "table" and session_or_id or M.find(session_or_id)
  if not sess or not sess.bufnr or not vim.api.nvim_buf_is_valid(sess.bufnr) then
    return nil
  end

  opts = opts or {}
  local lines = {}
  local total_lines = vim.api.nvim_buf_line_count(sess.bufnr)

  if opts.range and #opts.range >= 2 then
    local start_line = math.max(0, opts.range[1] - 1)
    local end_line = math.min(total_lines, opts.range[2])
    lines = vim.api.nvim_buf_get_lines(sess.bufnr, start_line, end_line, false)
  elseif opts.full then
    lines = vim.api.nvim_buf_get_lines(sess.bufnr, 0, -1, false)
  else
    local n = opts.last_n or 60
    local start_idx = math.max(0, total_lines - n)
    lines = vim.api.nvim_buf_get_lines(sess.bufnr, start_idx, -1, false)
  end

  local cleaned = {}
  for _, line in ipairs(lines) do
    local s = M.strip_ansi(line)
    table.insert(cleaned, s)
  end

  while #cleaned > 0 and vim.trim(cleaned[1]) == "" do
    table.remove(cleaned, 1)
  end
  while #cleaned > 0 and vim.trim(cleaned[#cleaned]) == "" do
    table.remove(cleaned, #cleaned)
  end

  return table.concat(cleaned, "\n")
end

---Dump extracted session content to a temporary context file
---@param session_or_id Session|string
---@param content string
---@return string File path
function M.dump_pipe_context(session_or_id, content)
  local sess = type(session_or_id) == "table" and session_or_id or M.find(session_or_id)
  local sess_name = sess and sess.name or "session"
  local opts = config.get()
  local pipes_dir = (opts.session_dir or (vim.fn.stdpath("data") .. "/agent-sessions")) .. "/pipes"

  if vim.fn.isdirectory(pipes_dir) == 0 then
    vim.fn.mkdir(pipes_dir, "p")
  end

  local filename = string.format("pipe_%s_%s.md", sess_name:gsub("[^%w_%-]", "_"), os.date("%m%d-%H%M%S"))
  local filepath = pipes_dir .. "/" .. filename

  local file, err = io.open(filepath, "w")
  if file then
    file:write(content .. "\n")
    file:close()
  else
    vim.notify("[agent-session] Failed to write pipe context file: " .. tostring(err), vim.log.levels.ERROR)
  end

  return filepath
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

---Restart a session (in-place in the same session object / window)
---@param session_or_id Session|string
---@return Session|nil
function M.restart(session_or_id)
  local sess = type(session_or_id) == "table" and session_or_id or M.find(session_or_id)
  if not sess then
    vim.notify("[agent-session] Session not found to restart.", vim.log.levels.WARN)
    return nil
  end

  local opts = config.get()
  local agent_def = (opts.agents and opts.agents[sess.agent])
  if not agent_def then
    if vim.fn.executable(sess.agent) == 1 then
      agent_def = { cmd = sess.agent, args = {}, env = {} }
    else
      agent_def = { cmd = vim.o.shell, args = {}, env = {} }
    end
  end

  -- Ensure session has a CLI session UUID
  if not sess.cli_session_id or sess.cli_session_id == "" then
    sess.cli_session_id = generate_uuid()
  end

  -- Build command with resume capability
  local cmd = build_agent_cmd(agent_def, sess.cli_session_id, true)

  -- Stop active job and timer
  if sess._timer and not sess._timer:is_closing() then
    sess._timer:stop()
    sess._timer:close()
  end

  if sess.job_id > 0 and sess.status ~= "stopped" then
    pcall(vim.fn.jobstop, sess.job_id)
  end

  local old_bufnr = sess.bufnr

  -- Create fresh unlisted buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = "hide"

  local timer = uv.new_timer()
  sess.bufnr = bufnr
  sess.status = "running"
  sess.exit_code = nil
  sess._timer = timer
  sess._is_initial = true

  -- Track mode and view changes on session buffer
  vim.api.nvim_create_autocmd("TermEnter", {
    buffer = bufnr,
    callback = function()
      sess._saved_mode = "t"
    end,
  })

  vim.api.nvim_create_autocmd("TermLeave", {
    buffer = bufnr,
    callback = function()
      sess._saved_mode = "n"
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = bufnr,
    callback = function()
      local ok_ui, ui_mod = pcall(require, "agent-session.ui")
      if ok_ui and ui_mod.save_session_view then
        ui_mod.save_session_view(sess)
      end
    end,
  })

  local term_opts = {
    cwd = vim.fn.getcwd(),
    on_exit = function(_, exit_code, _)
      if timer and not timer:is_closing() then
        timer:stop()
        timer:close()
      end
      sess.exit_code = exit_code
      M.set_status(sess, "stopped")
      if opts.hooks and opts.hooks.on_session_exit then
        opts.hooks.on_session_exit(sess, exit_code)
      end
    end,
  }
  if agent_def.env and type(agent_def.env) == "table" and next(agent_def.env) ~= nil then
    term_opts.env = agent_def.env
  end

  -- Monitor terminal output activity
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      if sess.status == "stopped" then
        return
      end
      if sess.status ~= "running" then
        M.set_status(sess, "running")
      end
      if timer and not timer:is_closing() then
        timer:stop()
        timer:start(
          opts.idle_timeout or 800,
          0,
          vim.schedule_wrap(function()
            if sess.status == "running" then
              M.set_status(sess, "idle")
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

  -- Delete old buffer if valid
  if old_bufnr and vim.api.nvim_buf_is_valid(old_bufnr) then
    pcall(vim.api.nvim_buf_delete, old_bufnr, { force = true })
  end

  -- Spawn terminal in buffer
  local job_id = vim.api.nvim_buf_call(bufnr, function()
    local ok, res = pcall(vim.fn.termopen, cmd, term_opts)
    if ok and type(res) == "number" and res > 0 then
      return res
    end
    vim.notify("[agent-session] Failed to restart terminal: " .. tostring(res), vim.log.levels.ERROR)
    return 0
  end)

  sess.job_id = job_id
  if job_id == 0 then
    sess.status = "stopped"
  else
    if timer and not timer:is_closing() then
      timer:start(
        opts.idle_timeout or 800,
        0,
        vim.schedule_wrap(function()
          if sess.status == "running" then
            M.set_status(sess, "idle")
          end
        end)
      )
    end
  end
  pcall(vim.api.nvim_buf_set_name, bufnr, "agent-session://" .. sess.name .. " (" .. sess.id .. ")")

  -- Map q to hide window in normal mode
  vim.keymap.set("n", "q", function()
    local ok_ui, ui_mod = pcall(require, "agent-session.ui")
    if ok_ui and ui_mod.close_window then
      ui_mod.close_window()
    end
  end, { buffer = bufnr, nowait = true, silent = true })

  -- Map R to rename this session in normal mode
  vim.keymap.set("n", "R", function()
    vim.ui.input({ prompt = "Rename session: ", default = sess.name }, function(new_name)
      if new_name and vim.trim(new_name) ~= "" then
        M.rename(sess.id, new_name)
      end
    end)
  end, { buffer = bufnr, nowait = true, silent = true })

  -- If currently open in UI window, switch window to new bufnr
  local ok_ui, ui_mod = pcall(require, "agent-session.ui")
  if ok_ui and ui_mod._current_win and vim.api.nvim_win_is_valid(ui_mod._current_win) then
    local cur_sess = M.get_current()
    if cur_sess and cur_sess.id == sess.id then
      vim.api.nvim_win_set_buf(ui_mod._current_win, bufnr)
      ui_mod.refresh_title(sess)
    end
  end

  M.set_current(sess.id)
  vim.notify(string.format("[agent-session] Restarted session '%s' (%s)", sess.name, sess.agent), vim.log.levels.INFO)
  return sess
end

---Export a session's transcript to a markdown file
---@param session_or_id Session|string
---@param file_path? string File path (if nil, uses default exports dir)
---@return string|nil Exported file path
function M.export(session_or_id, file_path)
  local sess = type(session_or_id) == "table" and session_or_id or M.find(session_or_id)
  if not sess then
    vim.notify("[agent-session] Session not found to export.", vim.log.levels.WARN)
    return nil
  end

  local output = M.extract_output(sess, { full = true })
  if not output or output == "" then
    vim.notify(string.format("[agent-session] Session '%s' has no output to export.", sess.name), vim.log.levels.WARN)
    return nil
  end

  local opts = config.get()
  local exports_dir = (opts.session_dir or (vim.fn.stdpath("data") .. "/agent-sessions")) .. "/exports"
  if vim.fn.isdirectory(exports_dir) == 0 then
    vim.fn.mkdir(exports_dir, "p")
  end

  if not file_path or vim.trim(file_path) == "" then
    local safe_name = sess.name:gsub("[^%w_%-]", "_")
    local filename = string.format("%s_%s.md", safe_name, os.date("%Y%m%d_%H%M%S"))
    file_path = exports_dir .. "/" .. filename
  else
    file_path = vim.fn.fnamemodify(file_path, ":p")
    local parent = vim.fn.fnamemodify(file_path, ":h")
    if vim.fn.isdirectory(parent) == 0 then
      vim.fn.mkdir(parent, "p")
    end
  end

  local header = string.format(
    "# Agent Session Transcript: %s\n\n- **Agent**: `%s`\n- **Session ID**: `%s`\n- **CLI Session ID**: `%s`\n- **Created At**: `%s`\n- **Exported At**: `%s`\n- **Status**: `%s`\n\n---\n\n```text\n",
    sess.name,
    sess.agent,
    sess.id,
    sess.cli_session_id or "N/A",
    os.date("%Y-%m-%d %H:%M:%S", sess.created_at or os.time()),
    os.date("%Y-%m-%d %H:%M:%S"),
    sess.status
  )
  local footer = "\n```\n"

  local file, err = io.open(file_path, "w")
  if not file then
    vim.notify("[agent-session] Failed to open export file: " .. tostring(err), vim.log.levels.ERROR)
    return nil
  end

  file:write(header .. output .. footer)
  file:close()

  vim.notify(
    string.format("[agent-session] Exported transcript of '%s' to %s", sess.name, vim.fn.fnamemodify(file_path, ":~:.")),
    vim.log.levels.INFO
  )
  return file_path
end

---Get project storage file path
---@param cwd? string
---@return string
local function get_project_file_path(cwd)
  cwd = cwd or vim.fn.getcwd()
  local opts = config.get()
  local projects_dir = (opts.session_dir or (vim.fn.stdpath("data") .. "/agent-sessions")) .. "/projects"
  if vim.fn.isdirectory(projects_dir) == 0 then
    vim.fn.mkdir(projects_dir, "p")
  end
  local hash = vim.fn.sha256(cwd):sub(1, 16)
  return projects_dir .. "/proj_" .. hash .. ".json"
end

---Save active sessions for current project / directory
---@param cwd? string
---@return boolean
function M.save_project(cwd)
  cwd = cwd or vim.fn.getcwd()
  local all = M.get_all()
  local count = vim.tbl_count(all)
  if count == 0 then
    return false
  end

  local sessions_data = {}
  for _, s in pairs(all) do
    table.insert(sessions_data, {
      name = s.name,
      agent = s.agent,
      cli_session_id = s.cli_session_id,
    })
  end

  local cur = M.get_current()
  local payload = {
    project_dir = cwd,
    saved_at = os.time(),
    current_session = cur and cur.name or nil,
    sessions = sessions_data,
  }

  local ok, encoded = pcall(vim.json.encode, payload)
  if not ok or not encoded then
    return false
  end

  local file_path = get_project_file_path(cwd)
  local f, err = io.open(file_path, "w")
  if f then
    f:write(encoded)
    f:close()
    vim.notify(
      string.format(
        "[agent-session] Saved %d sessions for project: %s",
        #sessions_data,
        vim.fn.fnamemodify(cwd, ":~:.")
      ),
      vim.log.levels.INFO
    )
    return true
  else
    vim.notify("[agent-session] Failed to save project sessions: " .. tostring(err), vim.log.levels.ERROR)
    return false
  end
end

---Restore saved sessions for current project / directory
---@param cwd? string
---@return Session[]
function M.restore_project(cwd)
  cwd = cwd or vim.fn.getcwd()
  local file_path = get_project_file_path(cwd)

  if vim.fn.filereadable(file_path) == 0 then
    vim.notify(
      "[agent-session] No saved sessions found for project: " .. vim.fn.fnamemodify(cwd, ":~:."),
      vim.log.levels.WARN
    )
    return {}
  end

  local f = io.open(file_path, "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()

  local ok, data = pcall(vim.json.decode, content)
  if not ok or not data or not data.sessions then
    vim.notify("[agent-session] Failed to parse saved session data.", vim.log.levels.ERROR)
    return {}
  end

  local restored = {}
  for _, item in ipairs(data.sessions) do
    local existing = M.find(item.name)
    if not existing then
      local s = M.create(item.name, item.agent, {
        cli_session_id = item.cli_session_id,
        is_resume = true,
      })
      table.insert(restored, s)
    else
      table.insert(restored, existing)
    end
  end

  if data.current_session then
    local cur = M.find(data.current_session)
    if cur then
      M.set_current(cur.id)
    end
  end

  vim.notify(
    string.format("[agent-session] Restored %d sessions for project: %s", #restored, vim.fn.fnamemodify(cwd, ":~:.")),
    vim.log.levels.INFO
  )

  local ok_sb, sidebar_mod = pcall(require, "agent-session.sidebar")
  if ok_sb and sidebar_mod.render then
    sidebar_mod.render()
  end

  return restored
end

-- Auto-save project sessions on exit if configured
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("AgentSessionAutoSave", { clear = true }),
  callback = function()
    local opts = config.get()
    if opts.auto_save_sessions then
      M.save_project()
    end
  end,
})

return M
