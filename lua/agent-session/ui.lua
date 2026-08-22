local config = require("agent-session.config")
local session_mod = require("agent-session.session")

local M = {}

---@type number|nil
M._current_win = nil

---Calculate floating window dimensions
---@param ui_opts AgentSessionUIConfig
---@return table
local function get_float_dims(ui_opts)
  local width = ui_opts.width or 0.85
  local height = ui_opts.height or 0.8

  if width < 1 then
    width = math.floor(vim.o.columns * width)
  end
  if height < 1 then
    height = math.floor(vim.o.lines * height)
  end

  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  return {
    relative = "editor",
    width = math.max(20, math.floor(width)),
    height = math.max(10, math.floor(height)),
    row = math.max(0, row),
    col = math.max(0, col),
    border = ui_opts.border or "rounded",
    style = "minimal",
  }
end

---Calculate sidebar split width
---@param ui_opts AgentSessionUIConfig
---@return number
local function get_split_width(ui_opts)
  local width = ui_opts.width
  if not width or (width == 0.85 and ui_opts.position == "vsplit") then
    width = 0.35
  end
  if width < 1 then
    width = math.floor(vim.o.columns * width)
  end
  return math.max(15, math.floor(width))
end

---Calculate panel split height
---@param ui_opts AgentSessionUIConfig
---@return number
local function get_split_height(ui_opts)
  local height = ui_opts.height
  if not height or (height == 0.8 and ui_opts.position == "split") then
    height = 0.3
  end
  if height < 1 then
    height = math.floor(vim.o.lines * height)
  end
  return math.max(5, math.floor(height))
end

---Apply clean window options for terminal display
---@param win number
local function apply_win_options(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].spell = false
  if vim.fn.has("nvim-0.9") == 1 then
    vim.wo[win].statuscolumn = ""
  end
end

---Format title for session window
---@param session Session
---@return string
function M.format_title(session)
  local opts = config.get()
  local ui_opts = opts.ui or {}
  local icons = opts.status_icons or { running = "⚡", idle = "🟢", stopped = "⚪" }
  local icon = icons[session.status] or ""
  local base_title = ui_opts.title or " Agent Session "

  return string.format("%s[%s] %s %s ", base_title, session.name, icon, session.status)
end

---Refresh title and winbar when status updates
---@param session? Session
function M.refresh_title(session)
  session = session or session_mod.get_current()
  if not session or not M._current_win or not vim.api.nvim_win_is_valid(M._current_win) then
    return
  end

  local opts = config.get()
  local ui_opts = opts.ui or {}
  local title = M.format_title(session)

  if ui_opts.position == "float" then
    pcall(vim.api.nvim_win_set_config, M._current_win, {
      title = title,
      title_pos = "center",
    })
  else
    pcall(function()
      vim.wo[M._current_win].winbar = "%=" .. title .. "%="
    end)
  end
end

---Save the window view and mode of the session currently displayed in M._current_win
function M.save_current_view()
  if not M._current_win or not vim.api.nvim_win_is_valid(M._current_win) then
    return
  end

  local cur_buf = vim.api.nvim_win_get_buf(M._current_win)
  local cur_sess = session_mod.get_by_bufnr(cur_buf)
  if cur_sess then
    pcall(function()
      cur_sess._saved_view = vim.api.nvim_win_call(M._current_win, vim.fn.winsaveview)
    end)
    if vim.api.nvim_get_current_win() == M._current_win then
      local mode = vim.fn.mode()
      cur_sess._saved_mode = (mode == "t") and "t" or "n"
    end
  end
end

---Save view for a specific session if it is currently displayed
---@param session Session
function M.save_session_view(session)
  if not session or not session.bufnr or not vim.api.nvim_buf_is_valid(session.bufnr) then
    return
  end
  if M._current_win and vim.api.nvim_win_is_valid(M._current_win) then
    local cur_buf = vim.api.nvim_win_get_buf(M._current_win)
    if cur_buf == session.bufnr then
      pcall(function()
        session._saved_view = vim.api.nvim_win_call(M._current_win, vim.fn.winsaveview)
      end)
      if vim.api.nvim_get_current_win() == M._current_win then
        local mode = vim.fn.mode()
        session._saved_mode = (mode == "t") and "t" or "n"
      end
    end
  end
end

---Restore saved view and mode for a session in M._current_win
---@param session Session
---@param focus_input? boolean Force terminal insert mode
local function restore_session_view_and_mode(session, focus_input)
  if not M._current_win or not vim.api.nvim_win_is_valid(M._current_win) then
    return
  end

  local opts = config.get()
  local ui_opts = opts.ui or {}
  local restore_enabled = ui_opts.restore_view ~= false

  vim.api.nvim_set_current_win(M._current_win)

  if focus_input then
    vim.cmd("startinsert")
    return
  end

  if restore_enabled and session._saved_view then
    pcall(function()
      vim.api.nvim_win_call(M._current_win, function()
        vim.fn.winrestview(session._saved_view)
      end)
    end)
  end

  if restore_enabled and session._saved_mode == "n" then
    vim.cmd("stopinsert")
  else
    vim.cmd("startinsert")
  end
end

---Open a session in window
---@param session Session
---@param open_opts? { focus_input?: boolean }
function M.open(session, open_opts)
  if not session or not vim.api.nvim_buf_is_valid(session.bufnr) then
    vim.notify("[agent-session] Invalid session buffer", vim.log.levels.ERROR)
    return
  end

  open_opts = open_opts or {}
  local opts = config.get()
  local ui_opts = opts.ui or {}

  -- If window already exists, bring it to focus and switch buffer
  if M._current_win and vim.api.nvim_win_is_valid(M._current_win) then
    M.save_current_view()
    vim.api.nvim_set_current_win(M._current_win)
    vim.api.nvim_win_set_buf(M._current_win, session.bufnr)
    apply_win_options(M._current_win)
    session_mod.set_current(session.id)
    M.refresh_title(session)
    restore_session_view_and_mode(session, open_opts.focus_input)
    return
  end

  if ui_opts.position == "split" then
    local target_height = get_split_height(ui_opts)
    vim.cmd(string.format("botright %dsplit", target_height))
    M._current_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M._current_win, session.bufnr)
    vim.wo[M._current_win].winfixheight = true
    pcall(vim.api.nvim_win_set_height, M._current_win, target_height)
  elseif ui_opts.position == "vsplit" then
    local target_width = get_split_width(ui_opts)
    vim.cmd(string.format("botright vertical %dsplit", target_width))
    M._current_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M._current_win, session.bufnr)
    vim.wo[M._current_win].winfixwidth = true
    pcall(vim.api.nvim_win_set_width, M._current_win, target_width)
  else
    -- Default: float
    local float_opts = get_float_dims(ui_opts)
    float_opts.title = M.format_title(session)
    float_opts.title_pos = "center"

    local win = vim.api.nvim_open_win(session.bufnr, true, float_opts)
    M._current_win = win
  end

  apply_win_options(M._current_win)
  M.refresh_title(session)

  -- Track when window is closed externally
  local cur_win = M._current_win
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(cur_win),
    once = true,
    callback = function()
      if M._current_win == cur_win then
        M.save_current_view()
        M._current_win = nil
      end
    end,
  })

  session_mod.set_current(session.id)
  restore_session_view_and_mode(session, open_opts.focus_input)

  -- Map q to hide window in normal mode
  vim.keymap.set("n", "q", function()
    M.close_window()
  end, { buffer = session.bufnr, nowait = true, silent = true })

  -- Map R to rename this session (normal mode only, doesn't interfere with terminal input)
  vim.keymap.set("n", "R", function()
    vim.ui.input({ prompt = "Rename session: ", default = session.name }, function(new_name)
      if new_name and vim.trim(new_name) ~= "" then
        session_mod.rename(session.id, new_name)
      end
    end)
  end, { buffer = session.bufnr, nowait = true, silent = true })
end

---Close current UI window (without killing the session)
function M.close_window()
  if M._current_win and vim.api.nvim_win_is_valid(M._current_win) then
    M.save_current_view()
    vim.api.nvim_win_close(M._current_win, true)
    M._current_win = nil
  end
end

---Toggle current session window
function M.toggle()
  if M._current_win and vim.api.nvim_win_is_valid(M._current_win) then
    M.close_window()
    return
  end

  local session = session_mod.get_current()
  if not session then
    local all = session_mod.get_all()
    local _, first = next(all)
    session = first
  end

  if not session then
    -- Create new default session if none exists
    session = session_mod.create()
  end

  M.open(session)
end

---Select and open a session from a picker
---@param on_select? fun(session: Session)
---@param opts_or_prompt? string|{ prompt?: string }
function M.select_session(on_select, opts_or_prompt)
  local prompt = type(opts_or_prompt) == "string" and opts_or_prompt
    or (type(opts_or_prompt) == "table" and opts_or_prompt.prompt)
    or "Select Agent Session:"
  local all = session_mod.get_all()
  local opts = config.get()
  local icons = opts.status_icons or { running = "⚡", idle = "🟢", stopped = "⚪" }
  local items = {}
  local session_lookup = {}

  for id, sess in pairs(all) do
    local icon = icons[sess.status] or "•"
    local label = string.format("[%s %s] %s (%s) - %s", icon, sess.status, sess.name, sess.agent, id)
    table.insert(items, label)
    session_lookup[label] = sess
  end

  if #items == 0 then
    vim.notify("[agent-session] No active sessions found. Create one with :AgentSessionNew", vim.log.levels.INFO)
    return
  end

  vim.ui.select(items, {
    prompt = prompt,
  }, function(choice)
    if choice and session_lookup[choice] then
      local selected = session_lookup[choice]
      if on_select then
        on_select(selected)
      else
        M.open(selected)
      end
    end
  end)
end

---Select an agent from configured agents list
---@param on_select fun(agent_name: string)
function M.select_agent(on_select)
  local opts = config.get()
  local agents = opts.agents or {}
  local items = {}

  for name, _ in pairs(agents) do
    table.insert(items, name)
  end
  table.sort(items)

  if #items == 0 then
    table.insert(items, opts.default_agent or "claude")
  end

  vim.ui.select(items, {
    prompt = "Select AI Agent to Launch:",
  }, function(choice)
    if choice and on_select then
      on_select(choice)
    end
  end)
end

return M
