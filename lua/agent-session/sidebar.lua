local config = require("agent-session.config")
local session_mod = require("agent-session.session")
local ui = require("agent-session.ui")

local M = {}

---@type number|nil
M._bufnr = nil
---@type number|nil
M._win = nil
---@type table<number, string> Map line number to session ID
M._line_map = {}

---Setup syntax highlights for sidebar
local function setup_highlights()
  vim.api.nvim_set_hl(0, "AgentSessionHeader", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "AgentSessionActive", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "AgentSessionRunning", { fg = "#f1fa8c", bold = true, default = true })
  vim.api.nvim_set_hl(0, "AgentSessionIdle", { fg = "#50fa7b", default = true })
  vim.api.nvim_set_hl(0, "AgentSessionStopped", { fg = "#6272a4", default = true })
  vim.api.nvim_set_hl(0, "AgentSessionAgent", { fg = "#8be9fd", default = true })
  vim.api.nvim_set_hl(0, "AgentSessionHelp", { link = "Comment", default = true })
end

---Render sidebar content
function M.render()
  if not M._bufnr or not vim.api.nvim_buf_is_valid(M._bufnr) then
    return
  end

  setup_highlights()
  vim.bo[M._bufnr].modifiable = true
  M._line_map = {}

  local opts = config.get()
  local icons = opts.status_icons or { running = "⚡", idle = "🟢", stopped = "⚪" }
  local all = session_mod.get_all()
  local cur_sess = session_mod.get_current()
  local total_count = vim.tbl_count(all)

  local lines = {}
  local highlights = {} -- { { line, col_start, col_end, group } }

  -- Header
  table.insert(lines, " 🤖 Agent Sessions (" .. total_count .. ")")
  table.insert(highlights, { 1, 0, -1, "AgentSessionHeader" })
  table.insert(lines, string.rep("─", 32))
  table.insert(highlights, { 2, 0, -1, "AgentSessionHelp" })

  local running_sessions = {}
  local idle_sessions = {}
  local stopped_sessions = {}

  for _, s in pairs(all) do
    if s.status == "running" then
      table.insert(running_sessions, s)
    elseif s.status == "idle" then
      table.insert(idle_sessions, s)
    else
      table.insert(stopped_sessions, s)
    end
  end

  -- Sort by name
  local function sort_by_name(a, b)
    return a.name < b.name
  end
  table.sort(running_sessions, sort_by_name)
  table.sort(idle_sessions, sort_by_name)
  table.sort(stopped_sessions, sort_by_name)

  local active_list = {}
  for _, s in ipairs(running_sessions) do
    table.insert(active_list, s)
  end
  for _, s in ipairs(idle_sessions) do
    table.insert(active_list, s)
  end

  -- Render Active Sessions
  if #active_list > 0 then
    table.insert(lines, " ▼ Active (" .. #active_list .. ")")
    table.insert(highlights, { #lines, 0, -1, "AgentSessionActive" })

    for _, s in ipairs(active_list) do
      local is_current = cur_sess and cur_sess.id == s.id
      local prefix = is_current and " ➜ " or "   "
      local icon = icons[s.status] or "•"
      local line_text = string.format("%s%s %-12s [%s]", prefix, icon, s.name, s.agent)

      table.insert(lines, line_text)
      local line_idx = #lines
      M._line_map[line_idx] = s.id

      local hl_group = s.status == "running" and "AgentSessionRunning" or "AgentSessionIdle"
      table.insert(highlights, { line_idx, 0, -1, hl_group })
    end
  else
    table.insert(lines, "   (No active sessions)")
    table.insert(highlights, { #lines, 0, -1, "AgentSessionHelp" })
  end

  -- Render Stopped Sessions
  if #stopped_sessions > 0 then
    table.insert(lines, "")
    table.insert(lines, " ▼ Stopped (" .. #stopped_sessions .. ")")
    table.insert(highlights, { #lines, 0, -1, "AgentSessionHelp" })

    for _, s in ipairs(stopped_sessions) do
      local icon = icons[s.status] or "⚪"
      local line_text = string.format("   %s %-12s [%s]", icon, s.name, s.agent)
      table.insert(lines, line_text)
      local line_idx = #lines
      M._line_map[line_idx] = s.id
      table.insert(highlights, { line_idx, 0, -1, "AgentSessionStopped" })
    end
  end

  -- Footer / Help
  table.insert(lines, "")
  table.insert(lines, string.rep("─", 32))
  table.insert(lines, " <CR>: Open  n: New    d: Delete")
  table.insert(lines, " r: Rename   p: Prompt P: Pipe")
  table.insert(lines, " e: Expand   +/-: Hgt  >/<: Width")
  table.insert(lines, " a: Agent    =: Reset  q: Close")
  for i = #lines - 5, #lines do
    table.insert(highlights, { i, 0, -1, "AgentSessionHelp" })
  end

  vim.api.nvim_buf_set_lines(M._bufnr, 0, -1, false, lines)
  vim.bo[M._bufnr].modifiable = false

  -- Apply syntax highlights
  local ns_id = vim.api.nvim_create_namespace("AgentSessionSidebar")
  vim.api.nvim_buf_clear_namespace(M._bufnr, ns_id, 0, -1)
  for _, hl in ipairs(highlights) do
    local line_0 = hl[1] - 1
    local col_s = hl[2]
    local col_e = hl[3]
    local group = hl[4]
    if line_0 >= 0 and line_0 < #lines then
      pcall(vim.api.nvim_buf_add_highlight, M._bufnr, ns_id, group, line_0, col_s, col_e)
    end
  end
end

---Find an existing left-docked sidebar window (e.g. neo-tree, NvimTree, aerial)
---@return number|nil
local function find_left_dock_win()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) and win ~= M._win then
      local pos = vim.api.nvim_win_get_position(win)
      if pos[2] == 0 then -- At the leftmost edge (column == 0)
        local bufnr = vim.api.nvim_win_get_buf(win)
        local ft = vim.bo[bufnr].filetype
        if ft == "neo-tree" or ft == "NvimTree" or ft == "aerial" or ft == "Outline" or ft == "undotree" then
          return win
        end
      end
    end
  end
  return nil
end

---Calculate sidebar width (supports percentage like 0.20 or fixed number like 30)
---@param sidebar_opts table
---@return number
local function get_sidebar_width(sidebar_opts)
  local width = sidebar_opts.width or 0.20
  if width < 1 then
    width = math.floor(vim.o.columns * width)
  end
  return math.max(20, math.floor(width))
end

---Calculate sidebar height when docked in bottom-left (supports percentage like 0.35 or fixed lines like 12)
---@param sidebar_opts table
---@param parent_win? number
---@return number
local function get_sidebar_height(sidebar_opts, parent_win)
  local height = sidebar_opts.height or 0.35
  local parent_height = (parent_win and vim.api.nvim_win_is_valid(parent_win))
      and vim.api.nvim_win_get_height(parent_win)
    or vim.o.lines

  if height < 1 then
    height = math.floor(parent_height * height)
  end
  return math.max(6, math.floor(height))
end

---Get session under cursor
---@return Session|nil
local function get_cursor_session()
  if not M._win or not vim.api.nvim_win_is_valid(M._win) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(M._win)
  local line = cursor[1]
  local session_id = M._line_map[line]
  if session_id then
    return session_mod.get(session_id)
  end
  return nil
end

---Set up keymaps for sidebar buffer
local function setup_keymaps(bufnr)
  local map_opts = { buffer = bufnr, nowait = true, silent = true }

  -- <CR> or o: Open session
  vim.keymap.set("n", "<CR>", function()
    local s = get_cursor_session()
    if s then
      ui.open(s)
    end
  end, map_opts)

  vim.keymap.set("n", "o", function()
    local s = get_cursor_session()
    if s then
      ui.open(s)
    end
  end, map_opts)

  -- n: New session
  vim.keymap.set("n", "n", function()
    vim.ui.input({ prompt = "Session Name (optional): " }, function(name)
      if name == "" then
        name = nil
      end
      require("agent-session").select_agent(function(agent_name)
        session_mod.create(name, agent_name)
        M.render()
      end)
    end)
  end, map_opts)

  -- a: Pick agent & launch
  vim.keymap.set("n", "a", function()
    require("agent-session").select_agent(function(agent_name)
      session_mod.create(nil, agent_name)
      M.render()
    end)
  end, map_opts)

  -- r: Rename session
  vim.keymap.set("n", "r", function()
    local s = get_cursor_session()
    if s then
      vim.ui.input({ prompt = "Rename session: ", default = s.name }, function(new_name)
        if new_name and vim.trim(new_name) ~= "" then
          session_mod.rename(s.id, new_name)
        end
      end)
    end
  end, map_opts)

  -- p: Prompt session under cursor
  vim.keymap.set("n", "p", function()
    local s = get_cursor_session()
    if s then
      require("agent-session").prompt_session(s.id)
    end
  end, map_opts)

  -- P: Pipe output from session under cursor to another session
  vim.keymap.set("n", "P", function()
    local s = get_cursor_session()
    if s then
      require("agent-session").pipe_session(s.id)
    end
  end, map_opts)

  -- d or x: Delete session
  vim.keymap.set("n", "d", function()
    local s = get_cursor_session()
    if s then
      vim.ui.select({ "Yes", "No" }, {
        prompt = "Delete session " .. s.name .. " (" .. s.id .. ")?",
      }, function(choice)
        if choice == "Yes" then
          session_mod.delete(s.id)
          M.render()
        end
      end)
    end
  end, map_opts)

  vim.keymap.set("n", "x", function()
    local s = get_cursor_session()
    if s then
      session_mod.delete(s.id)
      M.render()
    end
  end, map_opts)

  -- e: Toggle height expand (上下高度切換：展開至 50% 或收合回 25%)
  local is_expanded = false
  vim.keymap.set("n", "e", function()
    if not M._win or not vim.api.nvim_win_is_valid(M._win) then
      return
    end
    is_expanded = not is_expanded
    local parent_win = find_left_dock_win()
    if parent_win then
      local total_h = vim.o.lines
      local target_h = is_expanded and math.floor(total_h * 0.50) or math.floor(total_h * 0.25)
      pcall(vim.api.nvim_win_set_height, M._win, math.max(6, target_h))
    else
      local total_w = vim.o.columns
      local target_w = is_expanded and math.floor(total_w * 0.40) or math.floor(total_w * 0.20)
      pcall(vim.api.nvim_win_set_width, M._win, math.max(20, target_w))
    end
  end, map_opts)

  -- +/- or <C-Up>/<C-Down>: Resize height
  vim.keymap.set("n", "+", function()
    if M._win and vim.api.nvim_win_is_valid(M._win) then
      local h = vim.api.nvim_win_get_height(M._win)
      pcall(vim.api.nvim_win_set_height, M._win, h + 2)
    end
  end, map_opts)

  vim.keymap.set("n", "-", function()
    if M._win and vim.api.nvim_win_is_valid(M._win) then
      local h = vim.api.nvim_win_get_height(M._win)
      pcall(vim.api.nvim_win_set_height, M._win, math.max(5, h - 2))
    end
  end, map_opts)

  vim.keymap.set("n", "<C-Up>", "<cmd>resize +2<cr>", map_opts)
  vim.keymap.set("n", "<C-Down>", "<cmd>resize -2<cr>", map_opts)

  -- >/< or <C-Right>/<C-Left>: Resize width
  vim.keymap.set("n", ">", "<cmd>vertical resize +4<cr>", map_opts)
  vim.keymap.set("n", "<", "<cmd>vertical resize -4<cr>", map_opts)
  vim.keymap.set("n", "<C-Right>", "<cmd>vertical resize +4<cr>", map_opts)
  vim.keymap.set("n", "<C-Left>", "<cmd>vertical resize -4<cr>", map_opts)

  -- =: Reset default height / width
  vim.keymap.set("n", "=", function()
    if M._win and vim.api.nvim_win_is_valid(M._win) then
      local opts = config.get()
      local parent_win = find_left_dock_win()
      if parent_win then
        local def_h = get_sidebar_height(opts.sidebar or {}, parent_win)
        pcall(vim.api.nvim_win_set_height, M._win, def_h)
      else
        local def_w = get_sidebar_width(opts.sidebar or {})
        pcall(vim.api.nvim_win_set_width, M._win, def_w)
      end
    end
  end, map_opts)

  -- R: Refresh sidebar
  vim.keymap.set("n", "R", function()
    M.render()
  end, map_opts)

  -- q / <Esc>: Close sidebar
  vim.keymap.set("n", "q", function()
    M.close()
  end, map_opts)

  vim.keymap.set("n", "<Esc>", function()
    M.close()
  end, map_opts)

  -- Mouse double click: Open session
  vim.keymap.set("n", "<2-LeftMouse>", function()
    local mouse_pos = vim.fn.getmousepos()
    if mouse_pos.winid == M._win and mouse_pos.line > 0 then
      pcall(vim.api.nvim_win_set_cursor, M._win, { mouse_pos.line, 0 })
      local s = get_cursor_session()
      if s then
        ui.open(s)
      end
    end
  end, map_opts)
end

---Open the sidebar panel
function M.open()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_set_current_win(M._win)
    return
  end

  local opts = config.get()
  local sidebar_opts = opts.sidebar or {}

  -- Create buffer if needed
  if not M._bufnr or not vim.api.nvim_buf_is_valid(M._bufnr) then
    M._bufnr = vim.api.nvim_create_buf(false, true)
    vim.bo[M._bufnr].buftype = "nofile"
    vim.bo[M._bufnr].bufhidden = "hide"
    vim.bo[M._bufnr].filetype = "agent-session-sidebar"
    vim.bo[M._bufnr].swapfile = false
    vim.api.nvim_buf_set_name(M._bufnr, "Agent Sessions")
    setup_keymaps(M._bufnr)
  end

  local left_dock_win = find_left_dock_win()

  if left_dock_win and (sidebar_opts.position == "auto" or sidebar_opts.position == "bottom-left") then
    -- Dock in the bottom-left under neo-tree/aerial in the exact same left column!
    local target_height = get_sidebar_height(sidebar_opts, left_dock_win)
    vim.api.nvim_set_current_win(left_dock_win)
    vim.cmd(string.format("belowright %dsplit", target_height))
    M._win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M._win, M._bufnr)
    vim.wo[M._win].winfixheight = true
    pcall(vim.api.nvim_win_set_height, M._win, target_height)
  else
    -- Standalone left vertical split
    local target_width = get_sidebar_width(sidebar_opts)
    vim.cmd(string.format("topleft vertical %dsplit", target_width))
    M._win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M._win, M._bufnr)
    vim.wo[M._win].winfixwidth = true
    pcall(vim.api.nvim_win_set_width, M._win, target_width)
  end

  -- Window options
  vim.wo[M._win].number = false
  vim.wo[M._win].relativenumber = false
  vim.wo[M._win].signcolumn = "no"
  vim.wo[M._win].foldcolumn = "0"
  vim.wo[M._win].spell = false
  if vim.fn.has("nvim-0.9") == 1 then
    vim.wo[M._win].statuscolumn = ""
  end

  -- Track window close
  local cur_win = M._win
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(cur_win),
    once = true,
    callback = function()
      if M._win == cur_win then
        M._win = nil
      end
    end,
  })

  M.render()
end

---Close the sidebar
function M.close()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    vim.api.nvim_win_close(M._win, true)
    M._win = nil
  end
end

---Toggle sidebar visibility
function M.toggle()
  if M._win and vim.api.nvim_win_is_valid(M._win) then
    M.close()
  else
    M.open()
  end
end

-- Auto-refresh sidebar when session status changes
vim.api.nvim_create_autocmd("User", {
  pattern = "AgentSessionStatusChanged",
  callback = function()
    if M._win and vim.api.nvim_win_is_valid(M._win) then
      M.render()
    end
  end,
})

-- Auto-redock sidebar to bottom-left whenever neo-tree, NvimTree, or aerial opens
vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
  pattern = { "neo-tree", "NvimTree", "aerial", "Outline" },
  callback = function(args)
    if not M._win or not vim.api.nvim_win_is_valid(M._win) then
      return
    end

    vim.schedule(function()
      if not M._win or not vim.api.nvim_win_is_valid(M._win) then
        return
      end

      local tree_win = vim.fn.bufwinid(args.buf)
      if tree_win and tree_win ~= -1 and tree_win ~= M._win and vim.api.nvim_win_is_valid(tree_win) then
        local pos_tree = vim.api.nvim_win_get_position(tree_win)
        local pos_sb = vim.api.nvim_win_get_position(M._win)

        -- If tree is in column 0 and sidebar is either in another column or not underneath tree
        if pos_tree[2] == 0 and (pos_sb[2] ~= 0 or pos_sb[1] == 0) then
          pcall(vim.api.nvim_win_close, M._win, true)
          M._win = nil
          M.open()
        end
      end
    end)
  end,
})

return M
