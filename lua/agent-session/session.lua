local config = require("agent-session.config")
local uv = vim.uv or vim.loop

local M = {}

---@class Session
---@field id string Unique ID
---@field name string Session name
---@field agent string Agent key (e.g. "claude")
---@field bufnr number Terminal buffer number
---@field job_id number Terminal job ID
---@field created_at number Timestamp
---@field status "running"|"idle"|"stopped" Session status
---@field exit_code number|nil Process exit code
---@field _timer userdata|nil Libuv timer for idle debouncing
---@field _notify_timer userdata|nil Libuv timer for delayed idle notifications
---@field _last_notified_at number|nil Timestamp (ms) of last notification sent
---@field _saved_view table|nil Saved window view from winsaveview()
---@field _saved_mode "t"|"n"|nil Last active mode when unfocused ("t" for terminal, "n" for normal)
---@field _is_initial boolean|nil Whether this is the initial startup before any task
---@field _ready boolean|nil Whether startup has settled and session is ready for tasks
---@field _busy boolean|nil Whether an active task is running (set on input/output after ready)

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

---Get ordered list of all active sessions (by creation timestamp or name)
---@return Session[]
function M.get_ordered()
  local list = {}
  for _, s in pairs(M._active_sessions) do
    table.insert(list, s)
  end
  table.sort(list, function(a, b)
    if (a.created_at or 0) == (b.created_at or 0) then
      return a.name < b.name
    end
    return (a.created_at or 0) < (b.created_at or 0)
  end)
  return list
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

---Write raw escape sequence to host terminal
---@param seq string
---@return boolean success
local function write_to_terminal(seq)
  -- 1. Neovim 0.12+ nvim_ui_send: official API for sending raw sequences to TUI host terminal
  if vim.api.nvim_ui_send then
    local ok = pcall(vim.api.nvim_ui_send, seq)
    if ok then
      return true
    end
  end

  -- 2. Direct write to /dev/tty (Unix standard controlling terminal, bypasses Neovim process pipes)
  local ok_tty = pcall(function()
    local tty = io.open("/dev/tty", "w")
    if tty then
      tty:write(seq)
      tty:flush()
      tty:close()
      return true
    end
    return false
  end)
  if ok_tty then
    return true
  end

  -- 3. Neovim channel 2 (v:stderr), widely supported by plugins (e.g. nvim-osc52)
  if vim.v.stderr and vim.fn.chansend then
    local ok_chan, res = pcall(vim.fn.chansend, vim.v.stderr, seq)
    if ok_chan and res and res > 0 then
      return true
    end
  end

  -- 4. Lua io.stdout fallback
  local ok_stdout = pcall(function()
    if io and io.stdout then
      io.stdout:write(seq)
      io.stdout:flush()
      return true
    end
    return false
  end)
  if ok_stdout then
    return true
  end

  -- 5. Lua io.stderr fallback
  local ok_stderr = pcall(function()
    if io and io.stderr then
      io.stderr:write(seq)
      io.stderr:flush()
      return true
    end
    return false
  end)
  return ok_stderr or false
end

---Send an OSC desktop notification to the host terminal (Warp, Ghostty, WezTerm, iTerm2, etc.)
---@param title string Notification title
---@param body string Notification message body
---@param term_mode? boolean|"auto"|"osc777"|"osc9" Terminal notification protocol (default: "auto" from config)
---@return boolean success Whether an escape sequence was sent
function M.send_terminal_notification(title, body, term_mode)
  if term_mode == nil then
    local opts = config.get()
    term_mode = (opts.notifications and opts.notifications.terminal)
    if term_mode == nil then
      term_mode = "auto"
    end
  end

  if term_mode == false then
    return false
  end

  local proto = nil
  if term_mode == "osc9" then
    proto = "osc9"
  elseif term_mode == "osc777" or term_mode == true then
    proto = "osc777"
  elseif term_mode == "auto" then
    local term_prog = vim.env.TERM_PROGRAM or ""
    local is_warp = term_prog == "WarpTerminal"
      or vim.env.WARP_IS_TERM ~= nil
      or vim.env.WARP_TERMINAL_SESSION_UUID ~= nil
      or vim.env.WARP_CLIENT_VERSION ~= nil
    local is_ghostty = term_prog == "ghostty" or vim.env.GHOSTTY_RESOURCES_DIR ~= nil
    local is_wezterm = term_prog == "WezTerm" or vim.env.WEZTERM_PANE ~= nil
    local is_iterm = term_prog == "iTerm.app"
    local is_foot = vim.env.FOOT_SERVER_PATH ~= nil

    if is_iterm then
      proto = "osc9"
    elseif is_warp or is_ghostty or is_wezterm or is_foot then
      proto = "osc777"
    end
  end

  if not proto then
    return false
  end

  -- Sanitize title and body to prevent escaping or injection issues (strip ESC, BEL, semicolon, newlines)
  local clean_title = tostring(title or ""):gsub("[\027\007;\r\n\t]", " ")
  local clean_body = tostring(body or ""):gsub("[\027\007;\r\n\t]", " ")

  local seq
  if proto == "osc9" then
    seq = string.format("\027]9;%s\007", clean_body)
  else
    seq = string.format("\027]777;notify;%s;%s\007", clean_title, clean_body)
  end

  -- If inside tmux, wrap in DCS pass-through sequence (requires `set -g allow-passthrough on` in tmux)
  if vim.env.TMUX then
    local escaped = seq:gsub("\027", "\027\027")
    seq = "\027Ptmux;\027" .. escaped .. "\027\\"
  end

  return write_to_terminal(seq)
end

---Handle background notifications when session status changes
---@param session Session
---@param new_status "running"|"idle"|"stopped"
---@param old_status "running"|"idle"|"stopped"
---@param opts AgentSessionConfig
function M._handle_status_notification(session, new_status, old_status, opts)
  local notify_cfg = opts.notifications or {}
  if notify_cfg.enabled == false then
    if session._notify_timer and not session._notify_timer:is_closing() then
      session._notify_timer:stop()
    end
    return
  end

  -- If returning to running, immediately cancel any pending delayed idle notification
  if new_status == "running" then
    if session._notify_timer and not session._notify_timer:is_closing() then
      session._notify_timer:stop()
    end
    return
  end

  if new_status == "stopped" then
    if session._notify_timer and not session._notify_timer:is_closing() then
      session._notify_timer:stop()
    end

    local should_notify = notify_cfg.on_exit
    if should_notify == nil then
      should_notify = opts.notify_on_exit
    end
    if should_notify == nil then
      should_notify = true
    end

    if should_notify then
      local msg = session.exit_code
          and string.format("Agent '%s' (%s) stopped with exit code %d", session.name, session.agent, session.exit_code)
        or string.format("Agent '%s' (%s) process stopped", session.name, session.agent)
      local title = "Agent Session"

      -- Host terminal desktop notification (e.g. Warp, Ghostty): terminal emulator handles OS-level focus
      M.send_terminal_notification(title, msg, notify_cfg.terminal)
    end
    return
  end

  if new_status == "idle" and old_status == "running" then
    local is_ready = (session._ready ~= false)
    local is_busy = (session._busy == true)

    -- If this is the initial startup debounce settling to idle, mark as ready and don't notify
    if not is_ready or not is_busy or session._is_initial then
      session._ready = true
      session._busy = false
      session._is_initial = false
      return
    end

    -- Session was actively busy and has now completed its task/conversation
    session._busy = false

    local should_notify = notify_cfg.on_idle
    if should_notify == nil then
      should_notify = opts.notify_on_idle
    end
    if should_notify == nil then
      should_notify = true
    end

    if not should_notify then
      return
    end

    local delay = notify_cfg.idle_delay or 0

    local function fire_idle_notification()
      if session.status ~= "idle" then
        return
      end

      local now = uv.now()
      local cooldown = notify_cfg.cooldown or 1000
      if cooldown > 0 and session._last_notified_at and (now - session._last_notified_at < cooldown) then
        return
      end
      session._last_notified_at = now

      local msg = string.format("🤖 Agent '%s' (%s) has finished task!", session.name, session.agent)
      local title = "Agent Session"

      -- Host terminal desktop notification (e.g. Warp, Ghostty): terminal emulator handles OS-level focus
      M.send_terminal_notification(title, msg, notify_cfg.terminal)
    end

    if delay <= 0 then
      fire_idle_notification()
    else
      if not session._notify_timer or session._notify_timer:is_closing() then
        session._notify_timer = uv.new_timer()
      else
        session._notify_timer:stop()
      end

      session._notify_timer:start(
        delay,
        0,
        vim.schedule_wrap(function()
          fire_idle_notification()
        end)
      )
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

  local timer = uv.new_timer()

  ---@type Session
  local session = {
    id = id,
    name = name,
    agent = agent_name,
    bufnr = bufnr,
    job_id = 0,
    created_at = os.time(),
    status = "running",
    exit_code = nil,
    _timer = timer,
    _notify_timer = nil,
    _last_notified_at = nil,
    _saved_view = nil,
    _saved_mode = "t",
    _is_initial = true,
    _ready = false,
    _busy = false,
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
      if session._notify_timer and not session._notify_timer:is_closing() then
        session._notify_timer:stop()
        session._notify_timer:close()
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

      -- If output arrives, cancel any pending delayed idle notification immediately
      if session._notify_timer and not session._notify_timer:is_closing() then
        session._notify_timer:stop()
      end

      -- If output arrives after the session has settled to ready, mark as active task running
      if session._ready then
        session._busy = true
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
      if session._notify_timer and not session._notify_timer:is_closing() then
        session._notify_timer:stop()
        session._notify_timer:close()
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
  session._ready = true
  session._busy = true

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

  if session._notify_timer and not session._notify_timer:is_closing() then
    session._notify_timer:stop()
    session._notify_timer:close()
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

  vim.schedule(function()
    local ok_ui, ui_mod = pcall(require, "agent-session.ui")
    if ok_ui and ui_mod.refresh_title then
      ui_mod.refresh_title()
    end
    local ok_sb, sidebar_mod = pcall(require, "agent-session.sidebar")
    if ok_sb and sidebar_mod.render then
      sidebar_mod.render()
    end
  end)
end

return M
