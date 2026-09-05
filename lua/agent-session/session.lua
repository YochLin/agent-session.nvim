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
---@field _initial_ready boolean|nil Whether startup initialization has settled to idle
---@field _ready_lines_set table<string, boolean>|nil Set of startup lines to ignore for prompt detection
---@field _ready_line_count number|nil Line count when startup settled to idle
---@field _custom_named boolean|nil Whether user explicitly named this session at creation
---@field _auto_titled boolean|nil Whether auto-naming has already run for this session
---@field _raw_first_prompt string|nil Raw prompt text of first query
---@field _title_timer userdata|nil Libuv timer for debouncing prompt title extraction

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

    -- Don't notify if the user is actively focused on this session's buffer
    if M.is_focused(session) then
      return
    end

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
    return
  end

  if new_status == "idle" and old_status == "running" then
    -- Suppress notification on initial session spawn debounce and capture startup baseline lines
    if session._is_initial then
      session._is_initial = false
      session._initial_ready = true
      if session.bufnr and vim.api.nvim_buf_is_valid(session.bufnr) then
        session._ready_line_count = vim.api.nvim_buf_line_count(session.bufnr)
        local lines = vim.api.nvim_buf_get_lines(session.bufnr, 0, -1, false)
        session._ready_lines_set = {}
        for _, l in ipairs(lines) do
          local cleaned = M.strip_ansi(l)
          cleaned = vim.trim(cleaned)
          if cleaned ~= "" then
            session._ready_lines_set[cleaned] = true
          end
        end
      end
      return
    end

    -- Don't notify if the user is actively focused on this session's buffer
    if M.is_focused(session) then
      return
    end

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

    local delay = notify_cfg.idle_delay
    if delay == nil then
      delay = 2500
    end

    local function fire_idle_notification()
      if session.status ~= "idle" or M.is_focused(session) then
        return
      end

      local now = uv.now()
      local cooldown = notify_cfg.cooldown or 5000
      if session._last_notified_at and (now - session._last_notified_at < cooldown) then
        return
      end
      session._last_notified_at = now

      local msg = string.format("🤖 Agent '%s' (%s) has finished task!", session.name, session.agent)
      vim.notify(msg, vim.log.levels.INFO, {
        title = "Agent Session",
        icon = "🤖",
      })
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

    -- Check for auto-title if not custom named
    if not session._custom_named then
      local prompt = M.detect_prompt_from_buffer(session)
      if prompt and prompt ~= "" then
        M.handle_first_prompt(session, prompt)
      end
    end

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
  local custom_named = (name ~= nil and vim.trim(name) ~= "")
  name = custom_named and vim.trim(name) or ("session-" .. os.date("%m%d-%H%M"))
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
    _initial_ready = false,
    _ready_lines_set = {},
    _ready_line_count = 0,
    _custom_named = custom_named,
    _auto_titled = false,
    _raw_first_prompt = nil,
    _title_timer = nil,
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

      -- If not already marked as running, switch to running
      if session.status ~= "running" then
        M.set_status(session, "running")
      end

      -- Check for first prompt in terminal mode
      if not session._custom_named then
        local prompt = M.detect_prompt_from_buffer(session)
        if prompt and prompt ~= "" then
          M.handle_first_prompt(session, prompt)
        end
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

  -- Trigger auto-title on first user prompt if not custom named
  if not session._auto_titled and not session._custom_named and text and vim.trim(text) ~= "" then
    M.handle_first_prompt(session, text)
  end

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
  -- CSI sequences: \e[ ... <letter or ~>
  local s = text:gsub("\27%[[0-9;?<>]*[a-zA-Z~]", "")
  -- OSC sequences: \e] ... (BEL or ST)
  s = s:gsub("\27%][0-9];[^\7\27]*[\7\27\\]", "")
  s = s:gsub("\27%][0-9];[^\7]*\7", "")
  -- Charset selection: \e(B
  s = s:gsub("\27%([a-zA-Z0-9]", "")
  -- Normalize UTF-8 non-breaking spaces (U+00A0 \xC2\xA0) to standard ASCII space
  s = s:gsub("\194\160", " ")
  -- Strip zero-width spaces (U+200B) and BOM (U+FEFF)
  s = s:gsub("\226\128\139", "")
  s = s:gsub("\239\187\191", "")
  -- Control codes and carriage returns
  s = s:gsub("[\r\f]", "")
  return s
end

local BOX_CHARS = {
  "─",
  "━",
  "│",
  "┃",
  "┌",
  "┐",
  "└",
  "┘",
  "├",
  "┤",
  "┬",
  "┴",
  "┼",
  "╭",
  "╮",
  "╯",
  "╰",
  "═",
  "║",
  "╔",
  "╗",
  "╚",
  "╝",
  "╠",
  "╣",
  "╦",
  "╩",
  "╬",
}

---Check if a string contains any UI box-drawing or border character
---@param str string
---@return boolean
local function contains_box_char(str)
  for _, ch in ipairs(BOX_CHARS) do
    if str:find(ch, 1, true) then
      return true
    end
  end
  return false
end

---Clean and normalize raw prompt text for title generation
---@param text string
---@return string
function M.clean_prompt_text(text)
  if not text or text == "" then
    return ""
  end

  local s = M.strip_ansi(text)
  s = s:gsub("\r", "")

  -- Split into lines and pick the first non-empty line that isn't UI border/box characters
  local lines = vim.split(s, "\n", { plain = true })
  local first_meaningful = ""
  for _, l in ipairs(lines) do
    local trimmed = vim.trim(l)
    if trimmed ~= "" and not contains_box_char(trimmed) and not trimmed:match("^[%-_=#*]+$") then
      first_meaningful = trimmed
      break
    end
  end

  if first_meaningful == "" then
    return ""
  end

  s = first_meaningful

  -- Strip CLI prompt prefixes like ❯, >, >>>, >>, agy>, $, %
  local prefixes = { "❯", ">>>", ">>", ">", "agy>", "$", "%" }
  for _, p in ipairs(prefixes) do
    if vim.startswith(s, p) then
      s = vim.trim(s:sub(#p + 1))
      break
    end
  end

  s = s:gsub("^%[Context from session[^%]]*%]:%s*", "")
  s = s:gsub("^@%S+%s*", "") -- Strip leading file reference (e.g. @file.lua)
  s = s:gsub("%s+", " ")
  return vim.trim(s)
end

---Generate a short local heuristic title from prompt text
---@param text string
---@param max_len? number
---@return string
function M.generate_local_title(text, max_len)
  local clean = M.clean_prompt_text(text)
  if clean == "" then
    return ""
  end

  max_len = max_len or 24
  local char_count = vim.fn.strchars(clean)
  if char_count <= max_len then
    return clean
  end

  local truncated = vim.fn.strcharpart(clean, 0, max_len)
  truncated = vim.trim(truncated)
  return truncated .. "..."
end

---Check if a prompt string is a known CLI system banner, tip, or status message
---@param text string
---@return boolean
local function is_system_message(text)
  local lower = string.lower(text)
  lower = vim.trim(lower)
  if
    lower:match("^try%s*[\"'`]")
    or lower:match("^try[:%s]")
    or lower:match("^try%s+[%a%-]+%s*--")
    or lower:match("^tip[:%s]")
    or lower:match("^note[:%s]")
    or lower:match("^example[:%s]")
    or lower:match("^suggestion[:%s]")
    or lower:match("^for%s+shortcuts")
    or lower:match("^for%s+help")
    or lower:match("^type%s+%?")
    or lower:match("^%?%s+for%s+shortcuts")
    or lower:match("^help%s*$")
    or lower:match("^/help%s*$")
    or lower:match("^bypass%s+permissions")
    or lower:match("^shift%+")
    or lower:match("^ctrl%+")
    or lower:match("^enter%s+to")
    or lower:match("^esc%s+to")
    or lower:match("^tab%s+to")
    or lower:match("^to%s+continue")
    or lower:match("^to%s+quit")
    or lower:match("^welcome%s+to")
    or lower:match("^claude%s+code%s+v")
    or lower:match("^sonnet%s+%d")
    or lower:match("^opus%s+%d")
    or lower:match("^haiku%s+%d")
    or lower:match("^antigravity%s+v")
    or lower:match("^shortcuts")
    or lower:match("^cwd:")
    or lower:match("^model:")
    or lower:match("^tokens:")
    or lower:match("^cost:")
    or lower:match("^press%s+enter")
    or lower:match("^press%s+ctrl")
    or lower:match("^press%s+shift")
    or contains_box_char(text)
    or text:match("^[%-_=#*]+$")
  then
    return true
  end
  return false
end

---Detect user prompt line from a session or terminal buffer
---@param session_or_bufnr Session|number
---@return string|nil
function M.detect_prompt_from_buffer(session_or_bufnr)
  local session = type(session_or_bufnr) == "table" and session_or_bufnr or M.get_by_bufnr(session_or_bufnr)
  local bufnr = session and session.bufnr or session_or_bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local total = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, total, false)
  local prefixes = { "❯", ">>>", ">>", ">", "agy>", "$", "%" }

  for _, raw_line in ipairs(lines) do
    -- Ignore lines containing UI box borders
    if not contains_box_char(raw_line) then
      local cleaned = M.strip_ansi(raw_line)
      cleaned = vim.trim(cleaned)
      if cleaned ~= "" then
        for _, prefix in ipairs(prefixes) do
          if vim.startswith(cleaned, prefix) then
            local rest = vim.trim(cleaned:sub(#prefix + 1))
            if rest ~= "" and vim.fn.strchars(rest) >= 2 then
              if not is_system_message(rest) then
                return rest
              end
            end
            break
          end
        end
      end
    end
  end

  return nil
end

---Summarize a prompt with an AI model asynchronously
---@param prompt string
---@param session Session
---@param callback fun(title: string)
function M.summarize_with_ai(prompt, session, callback)
  local opts = config.get()
  local auto_cfg = opts.auto_title or {}
  local ai_cfg = auto_cfg.ai or {}

  if not ai_cfg.enabled then
    return
  end

  if ai_cfg.custom_fn and type(ai_cfg.custom_fn) == "function" then
    pcall(ai_cfg.custom_fn, prompt, session, callback)
    return
  end

  local provider = ai_cfg.provider or "openai"
  local model = ai_cfg.model
  local api_key = ai_cfg.api_key
  if type(api_key) == "function" then
    api_key = api_key()
  end

  local system_prompt =
    "You are a session title generator. Summarize the user prompt into a short title (2-5 words) in the exact same language as the prompt. Output ONLY the raw title without quotation marks, punctuation, backticks, or explanation."

  local cmd = { "curl", "-s", "-X", "POST" }
  local payload = nil

  if provider == "openai" then
    api_key = api_key or os.getenv("OPENAI_API_KEY") or os.getenv("GROQ_API_KEY")
    local endpoint = ai_cfg.endpoint or "https://api.openai.com/v1/chat/completions"
    table.insert(cmd, endpoint)
    table.insert(cmd, "-H")
    table.insert(cmd, "Content-Type: application/json")
    if api_key and api_key ~= "" then
      table.insert(cmd, "-H")
      table.insert(cmd, "Authorization: Bearer " .. api_key)
    end
    table.insert(cmd, "-d")
    table.insert(cmd, "@-")

    payload = vim.json.encode({
      model = model or "gpt-4o-mini",
      messages = {
        { role = "system", content = system_prompt },
        { role = "user", content = prompt },
      },
      max_tokens = 25,
      temperature = 0.3,
    })
  elseif provider == "gemini" then
    api_key = api_key or os.getenv("GEMINI_API_KEY")
    if not api_key then
      return
    end
    local endpoint = ai_cfg.endpoint
      or string.format(
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
        model or "gemini-2.5-flash",
        api_key
      )
    table.insert(cmd, endpoint)
    table.insert(cmd, "-H")
    table.insert(cmd, "Content-Type: application/json")
    table.insert(cmd, "-d")
    table.insert(cmd, "@-")

    payload = vim.json.encode({
      contents = {
        {
          parts = {
            { text = system_prompt .. "\n\nUser prompt:\n" .. prompt },
          },
        },
      },
      generationConfig = {
        maxOutputTokens = 25,
        temperature = 0.3,
      },
    })
  elseif provider == "anthropic" then
    api_key = api_key or os.getenv("ANTHROPIC_API_KEY")
    if not api_key then
      return
    end
    local endpoint = ai_cfg.endpoint or "https://api.anthropic.com/v1/messages"
    table.insert(cmd, endpoint)
    table.insert(cmd, "-H")
    table.insert(cmd, "Content-Type: application/json")
    table.insert(cmd, "-H")
    table.insert(cmd, "x-api-key: " .. api_key)
    table.insert(cmd, "-H")
    table.insert(cmd, "anthropic-version: 2023-06-01")
    table.insert(cmd, "-d")
    table.insert(cmd, "@-")

    payload = vim.json.encode({
      model = model or "claude-3-5-haiku-latest",
      system = system_prompt,
      messages = {
        { role = "user", content = prompt },
      },
      max_tokens = 25,
    })
  elseif provider == "ollama" then
    local endpoint = ai_cfg.endpoint or "http://localhost:11434/api/generate"
    table.insert(cmd, endpoint)
    table.insert(cmd, "-H")
    table.insert(cmd, "Content-Type: application/json")
    table.insert(cmd, "-d")
    table.insert(cmd, "@-")

    payload = vim.json.encode({
      model = model or "llama3.2:1b",
      system = system_prompt,
      prompt = prompt,
      stream = false,
    })
  else
    return
  end

  local function parse_and_callback(raw_output)
    if not raw_output or raw_output == "" then
      return
    end
    local ok, data = pcall(vim.json.decode, raw_output)
    if not ok or not data then
      return
    end

    local title = nil
    if provider == "openai" and data.choices and data.choices[1] and data.choices[1].message then
      title = data.choices[1].message.content
    elseif
      provider == "gemini"
      and data.candidates
      and data.candidates[1]
      and data.candidates[1].content
      and data.candidates[1].content.parts
    then
      title = data.candidates[1].content.parts[1].text
    elseif provider == "anthropic" and data.content and data.content[1] and data.content[1].text then
      title = data.content[1].text
    elseif provider == "ollama" and data.response then
      title = data.response
    end

    if title and type(title) == "string" then
      title = title:gsub("^[\"'`]+", ""):gsub("[\"'`]+$", "")
      title = title:gsub("^Title:%s*", "")
      title = title:gsub("^標題[:：]%s*", "")
      title = title:gsub("[\r\n]", " ")
      title = title:gsub("%s+", " ")
      title = vim.trim(title)
      if title ~= "" then
        title = vim.fn.strcharpart(title, 0, 30)
        callback(title)
      end
    end
  end

  if vim.system then
    vim.system(cmd, { stdin = payload, text = true }, function(out)
      vim.schedule(function()
        if out.code == 0 and out.stdout then
          parse_and_callback(out.stdout)
        end
      end)
    end)
  else
    local stdout_chunks = {}
    local job_id = vim.fn.jobstart(cmd, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if data then
          table.insert(stdout_chunks, table.concat(data, "\n"))
        end
      end,
      on_exit = function(_, code)
        if code == 0 then
          local output = table.concat(stdout_chunks, "")
          vim.schedule(function()
            parse_and_callback(output)
          end)
        end
      end,
    })
    if job_id > 0 and payload then
      vim.fn.chansend(job_id, payload)
      vim.fn.chanclose(job_id, "stdin")
    end
  end
end

---Handle automatic naming for a session upon first user prompt
---@param session Session
---@param prompt_text string
function M.handle_first_prompt(session, prompt_text)
  if not session or session._custom_named then
    return
  end

  local opts = config.get()
  local auto_cfg = opts.auto_title or {}
  if auto_cfg.enabled == false then
    return
  end

  local clean = M.clean_prompt_text(prompt_text)
  if clean == "" then
    return
  end

  -- If already titled with the exact same prompt, no-op to avoid redundant renames
  if session._auto_titled and session._raw_first_prompt == clean then
    return
  end

  -- If already titled, only allow updating if the new prompt is a more complete version of the first prompt
  if session._auto_titled then
    if not session._raw_first_prompt or not vim.startswith(clean, session._raw_first_prompt) then
      return
    end
  end

  session._raw_first_prompt = clean
  session._auto_titled = true

  -- 1. Format using custom formatter if provided
  local local_title = nil
  if auto_cfg.format and type(auto_cfg.format) == "function" then
    local ok, res = pcall(auto_cfg.format, clean, session)
    if ok and res and res ~= "" then
      local_title = vim.trim(res)
    end
  end

  if not local_title or local_title == "" then
    local_title = M.generate_local_title(clean, auto_cfg.max_length or 24)
  end

  if local_title and local_title ~= "" then
    M.rename(session.id, local_title)
  end

  -- 2. Async AI summarization (if configured)
  local ai_cfg = auto_cfg.ai
  if ai_cfg and ai_cfg.enabled then
    M.summarize_with_ai(clean, session, function(ai_title)
      if ai_title and ai_title ~= "" and M.get(session.id) then
        M.rename(session.id, ai_title)
      end
    end)
  end
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
