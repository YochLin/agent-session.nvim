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

---Cycle to next or previous agent session
---@param direction? 1|-1 Direction to cycle (1 for next, -1 for previous)
---@param opts? { stay_in_normal?: boolean, focus_input?: boolean, notify?: boolean }
---@return Session|nil
function M.cycle_session(direction, opts)
  direction = direction or 1
  opts = opts or {}
  session.sync_all()

  local list = session.get_ordered()
  if #list == 0 then
    vim.notify("[agent-session] No active sessions found. Create one with :AgentSessionNew", vim.log.levels.WARN)
    return nil
  end

  if #list == 1 then
    local single = list[1]
    ui.open(single, opts)
    if opts.notify ~= false then
      vim.notify(
        string.format("[agent-session] Active session: '%s' (%s) [1/1]", single.name, single.agent),
        vim.log.levels.INFO
      )
    end
    return single
  end

  -- Determine current session index
  local cur = session.get_current()
  local cur_idx = 1
  if cur then
    for i, s in ipairs(list) do
      if s.id == cur.id then
        cur_idx = i
        break
      end
    end
  end

  local count = #list
  local next_idx
  if direction >= 0 then
    next_idx = (cur_idx % count) + 1
  else
    next_idx = ((cur_idx - 2 + count) % count) + 1
  end

  local target = list[next_idx]
  ui.open(target, opts)

  if opts.notify ~= false then
    local cfg = config.get()
    local icons = cfg.status_icons or { running = "⚡", idle = "🟢", stopped = "⚪" }
    local icon = icons[target.status] or ""
    vim.notify(
      string.format(
        "[agent-session] Switched to '%s' [%s %s] (%d/%d)",
        target.name,
        icon,
        target.status,
        next_idx,
        count
      ),
      vim.log.levels.INFO
    )
  end

  return target
end

---Switch to the next agent session
---@param opts? { stay_in_normal?: boolean, focus_input?: boolean, notify?: boolean }
---@return Session|nil
function M.next_session(opts)
  return M.cycle_session(1, opts)
end

---Switch to the previous agent session
---@param opts? { stay_in_normal?: boolean, focus_input?: boolean, notify?: boolean }
---@return Session|nil
function M.prev_session(opts)
  return M.cycle_session(-1, opts)
end

---Switch directly to the agent session at the given 1-based index (e.g. from tab bar number)
---@param index integer
---@param opts? { stay_in_normal?: boolean, focus_input?: boolean, notify?: boolean }
---@return Session|nil
function M.goto_session(index, opts)
  session.sync_all()
  local list = session.get_ordered()
  if #list == 0 then
    vim.notify("[agent-session] No active sessions found. Create one with :AgentSessionNew", vim.log.levels.WARN)
    return nil
  end

  if not list[index] then
    vim.notify(
      string.format("[agent-session] No session at index %d (active sessions: %d)", index, #list),
      vim.log.levels.WARN
    )
    return nil
  end

  local target = list[index]
  ui.open(target, opts)

  if opts and opts.notify ~= false then
    local cfg = config.get()
    local icons = cfg.status_icons or { running = "⚡", idle = "🟢", stopped = "⚪" }
    local icon = icons[target.status] or ""
    vim.notify(
      string.format("[agent-session] Switched to '%s' [%s %s] (%d/%d)", target.name, icon, target.status, index, #list),
      vim.log.levels.INFO
    )
  end

  return target
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

---Send prompt / command text to a specific session (by name or ID) or choose via interactive picker
---@param target? string Session name or ID (or nil to pick interactively)
---@param text? string Prompt text to send (or nil to prompt via vim.ui.input)
---@param opts? { open?: boolean } Whether to open/focus the target session window
function M.prompt_session(target, text, opts)
  opts = opts or {}
  local all = session.get_all()
  if vim.tbl_isempty(all) then
    vim.notify("[agent-session] No active sessions found. Create one with :AgentSessionNew", vim.log.levels.WARN)
    return
  end

  local function send_to_session(sess, prompt_text)
    if not prompt_text or vim.trim(prompt_text) == "" then
      vim.ui.input({
        prompt = string.format("Prompt for '%s' (%s): ", sess.name, sess.agent),
      }, function(input)
        if input and vim.trim(input) ~= "" then
          session.send_text(sess.id, input, true)
          vim.notify(
            string.format("[agent-session] Sent prompt to '%s' (%s)", sess.name, sess.agent),
            vim.log.levels.INFO
          )
          if opts.open then
            ui.open(sess, { focus_input = true })
          end
        end
      end)
    else
      session.send_text(sess.id, prompt_text, true)
      vim.notify(string.format("[agent-session] Sent prompt to '%s' (%s)", sess.name, sess.agent), vim.log.levels.INFO)
      if opts.open then
        ui.open(sess, { focus_input = true })
      end
    end
  end

  if target and vim.trim(target) ~= "" then
    local sess = session.find(vim.trim(target))
    if not sess then
      vim.notify("[agent-session] Session not found: " .. target, vim.log.levels.ERROR)
      return
    end
    send_to_session(sess, text)
  else
    ui.select_session(function(sess)
      send_to_session(sess, text)
    end, "Select Target Session to Prompt:")
  end
end

---Alias for prompt_session
M.send_to = M.prompt_session

---@return string|nil path Current buffer's relative path, or nil + notifies on failure
local function get_current_buffer_path()
  local path = vim.fn.expand("%:.")
  if path == "" then
    vim.notify("[agent-session] Current buffer has no file path", vim.log.levels.WARN)
    return nil
  end
  return path
end

---Get visual selection or cursor line range
---@param line1? integer
---@param line2? integer
---@return integer, integer
local function resolve_line_range(line1, line2)
  if not line1 then
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
  return line1, line2 or line1
end

---Send a `@file:line` (or `@file:start-end` for a visual range) reference to the active session
---@param line1? integer Start line (defaults to current line, or the live visual selection)
---@param line2? integer End line (defaults to line1)
function M.send_line_ref(line1, line2)
  local cur = session.get_current()
  if not cur then
    vim.notify("[agent-session] No active session to send to", vim.log.levels.WARN)
    return
  end

  local path = get_current_buffer_path()
  if not path then
    return
  end

  line1, line2 = resolve_line_range(line1, line2)
  local ref = line1 == line2 and string.format("@%s:%d", path, line1) or string.format("@%s:%d-%d", path, line1, line2)

  session.send_text(cur.id, ref .. " ", false)
  ui.open(cur, { focus_input = true })
end

---Send a `@file:line` (or `@file:start-end` for a visual range) reference to a chosen target session
---@param target? string Session name or ID (or nil to pick interactively)
---@param line1? integer Start line
---@param line2? integer End line
function M.send_line_ref_to(target, line1, line2)
  local path = get_current_buffer_path()
  if not path then
    return
  end

  line1, line2 = resolve_line_range(line1, line2)
  local ref = line1 == line2 and string.format("@%s:%d", path, line1) or string.format("@%s:%d-%d", path, line1, line2)

  local function send_ref_to_session(sess)
    session.send_text(sess.id, ref .. " ", false)
    ui.open(sess, { focus_input = true })
  end

  if target and vim.trim(target) ~= "" then
    local sess = session.find(vim.trim(target))
    if not sess then
      vim.notify("[agent-session] Session not found: " .. target, vim.log.levels.ERROR)
      return
    end
    send_ref_to_session(sess)
  else
    ui.select_session(function(sess)
      send_ref_to_session(sess)
    end, "Select Target Session for Line Reference:")
  end
end

---Send a `@file` reference for the whole current buffer to the active session's input
function M.send_file_ref()
  local cur = session.get_current()
  if not cur then
    vim.notify("[agent-session] No active session to send to", vim.log.levels.WARN)
    return
  end

  local path = get_current_buffer_path()
  if not path then
    return
  end

  session.send_text(cur.id, "@" .. path .. " ", false)
  ui.open(cur, { focus_input = true })
end

---Send a `@file` reference for the whole current buffer to a chosen target session
---@param target? string Session name or ID (or nil to pick interactively)
function M.send_file_ref_to(target)
  local path = get_current_buffer_path()
  if not path then
    return
  end

  local function send_file_to_session(sess)
    session.send_text(sess.id, "@" .. path .. " ", false)
    ui.open(sess, { focus_input = true })
  end

  if target and vim.trim(target) ~= "" then
    local sess = session.find(vim.trim(target))
    if not sess then
      vim.notify("[agent-session] Session not found: " .. target, vim.log.levels.ERROR)
      return
    end
    send_file_to_session(sess)
  else
    ui.select_session(function(sess)
      send_file_to_session(sess)
    end, "Select Target Session for File Reference:")
  end
end

---Pipe output from a source session to a target session with optional instruction
---@param source_target? string Session name or ID for source (or nil to pick interactively)
---@param dest_target? string Session name or ID for target (or nil to pick interactively)
---@param instruction? string Prompt/instruction for the target session (or nil to prompt via input)
---@param opts? { lines?: number, full?: boolean, range?: integer[], open?: boolean, mode?: "auto"|"inline"|"file", pick_source?: boolean }
function M.pipe_session(source_target, dest_target, instruction, opts)
  opts = opts or {}
  local all = session.get_all()
  if vim.tbl_count(all) == 0 then
    vim.notify("[agent-session] No active sessions found to pipe.", vim.log.levels.WARN)
    return
  end

  local cur_sess = session.get_current()
  local source_sess = nil
  local dest_sess = nil
  local inst = instruction

  if source_target and vim.trim(source_target) ~= "" then
    local s1 = session.find(vim.trim(source_target))
    local s2 = dest_target and vim.trim(dest_target) ~= "" and session.find(vim.trim(dest_target)) or nil

    if s1 and s2 then
      source_sess = s1
      dest_sess = s2
    elseif s1 and not s2 then
      if dest_target and vim.trim(dest_target) ~= "" then
        inst = vim.trim(dest_target .. (inst and (" " .. inst) or ""))
      end
      if cur_sess and cur_sess.id ~= s1.id and not opts.pick_source then
        source_sess = cur_sess
        dest_sess = s1
      else
        source_sess = s1
      end
    end
  end

  local function proceed_with_source_and_dest(src, dst)
    if not src or not dst then
      return
    end

    if src.id == dst.id then
      vim.notify("[agent-session] Source and target sessions cannot be the same.", vim.log.levels.WARN)
      return
    end

    local output = session.extract_output(src, {
      last_n = opts.lines or 60,
      full = opts.full,
      range = opts.range,
    })

    if not output or vim.trim(output) == "" then
      vim.notify(string.format("[agent-session] No output captured from session '%s'", src.name), vim.log.levels.WARN)
      return
    end

    local function send_piped_payload(instruction_text)
      instruction_text = instruction_text and vim.trim(instruction_text) or ""
      local out_lines = vim.split(output, "\n", { plain = true })
      local line_count = #out_lines
      local mode = opts.mode or "auto"

      local payload
      if mode == "file" or (mode == "auto" and line_count > 35) then
        local dump_path = session.dump_pipe_context(src, output)
        if instruction_text ~= "" then
          payload = string.format("@%s %s", dump_path, instruction_text)
        else
          payload = string.format("@%s Please review and continue from the above session output.", dump_path)
        end
      else
        if instruction_text ~= "" then
          payload = string.format("[Context from session '%s']:\n---\n%s\n---\n%s", src.name, output, instruction_text)
        else
          payload = string.format(
            "[Context from session '%s']:\n---\n%s\n---\nPlease review and continue based on the above output.",
            src.name,
            output
          )
        end
      end

      session.send_text(dst.id, payload, true)
      vim.notify(
        string.format("[agent-session] Piped output from '%s' to '%s' (%s)", src.name, dst.name, dst.agent),
        vim.log.levels.INFO
      )

      if opts.open ~= false then
        ui.open(dst, { focus_input = true })
      end
    end

    if inst ~= nil and inst ~= "" then
      send_piped_payload(inst)
    else
      vim.ui.input({
        prompt = string.format("Instruction for '%s' (optional): ", dst.name),
      }, function(input)
        send_piped_payload(input)
      end)
    end
  end

  local function resolve_destination(src)
    if dest_sess then
      proceed_with_source_and_dest(src, dest_sess)
    else
      ui.select_session(function(dst)
        proceed_with_source_and_dest(src, dst)
      end, string.format("Select Target Session to Pipe from '%s' to:", src.name))
    end
  end

  if source_sess then
    resolve_destination(source_sess)
  else
    if cur_sess and not opts.pick_source then
      resolve_destination(cur_sess)
    else
      ui.select_session(function(src)
        resolve_destination(src)
      end, "Select Source Session to Pipe from:")
    end
  end
end

---Alias for pipe_session
M.pipe = M.pipe_session

---Rename the current or specified session
---@param new_name? string
---@param target? string Session name or ID (defaults to current active session)
function M.rename_session(new_name, target)
  local sess = (target and session.find(target)) or session.get_current()

  local function do_rename(s, name)
    if name and vim.trim(name) ~= "" then
      session.rename(s.id, name)
    else
      vim.ui.input({ prompt = "Rename session '" .. s.name .. "': ", default = s.name }, function(input)
        if input and vim.trim(input) ~= "" then
          session.rename(s.id, input)
        end
      end)
    end
  end

  if sess then
    do_rename(sess, new_name)
  else
    ui.select_session(function(selected)
      do_rename(selected, new_name)
    end, "Select Session to Rename:")
  end
end

---Delete the current or specified session
---@param target? string Session name or ID (defaults to current active session)
function M.delete_session(target)
  local sess = (target and session.find(target)) or session.get_current()

  local function do_delete(s)
    ui.close_window()
    session.delete(s.id)
    vim.notify(string.format("[agent-session] Deleted session '%s' (%s)", s.name, s.id), vim.log.levels.INFO)
  end

  if sess then
    do_delete(sess)
  else
    ui.select_session(function(selected)
      do_delete(selected)
    end, "Select Session to Delete:")
  end
end

---Get formatted status string for statusline / lualine
---@return string
function M.status()
  local cur = session.get_current()
  if not cur then
    return ""
  end
  session.sync_status(cur)
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
