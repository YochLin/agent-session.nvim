if vim.g.loaded_agent_session == 1 then
  return
end
vim.g.loaded_agent_session = 1

local agent_session = require("agent-session")

local function complete_session_targets(lead)
  local session_mod = require("agent-session.session")
  local all = session_mod.get_all()
  local items = {}
  for id, sess in pairs(all) do
    table.insert(items, sess.name)
    table.insert(items, id)
  end
  if not lead or lead == "" then
    return items
  end
  return vim.tbl_filter(function(item)
    return vim.startswith(item, lead)
  end, items)
end

-- :AgentSession router
vim.api.nvim_create_user_command("AgentSession", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  local subcmd = args[1]

  if not subcmd or subcmd == "toggle" then
    agent_session.toggle()
  elseif subcmd == "zoom" or subcmd == "toggle-zoom" or subcmd == "toggle-layout" or subcmd == "maximize" then
    agent_session.toggle_zoom()
  elseif subcmd == "new" then
    agent_session.new_session(args[2], args[3])
  elseif subcmd == "list" then
    agent_session.list_sessions()
  elseif subcmd == "next" then
    agent_session.next_session()
  elseif subcmd == "prev" or subcmd == "previous" then
    agent_session.prev_session()
  elseif subcmd == "goto" then
    local idx = tonumber(args[2])
    if idx then
      agent_session.goto_session(idx)
    else
      vim.notify("[agent-session] Please specify a session index (e.g. :AgentSession goto 1)", vim.log.levels.WARN)
    end
  elseif tonumber(subcmd) then
    agent_session.goto_session(tonumber(subcmd))
  elseif subcmd == "status" then
    if args[2] then
      agent_session.set_status(args[2], args[3])
    else
      vim.notify("[agent-session] Current status: " .. agent_session.status(), vim.log.levels.INFO)
    end
  elseif subcmd == "agent" or subcmd == "select-agent" then
    agent_session.select_agent()
  elseif subcmd == "sidebar" or subcmd == "tree" or subcmd == "panel" then
    agent_session.toggle_sidebar()
  elseif subcmd == "delete" then
    agent_session.delete_session(args[2])
  elseif subcmd == "rename" then
    local new_name = args[2]
    local target = args[3]
    agent_session.rename_session(new_name, target)
  elseif subcmd == "prompt" or subcmd == "send" or subcmd == "send-to" then
    local target = args[2]
    local text = #args > 2 and table.concat(args, " ", 3) or nil
    agent_session.prompt_session(target, text)
  elseif subcmd == "pipe" then
    local source = args[2]
    local dest = args[3]
    local instruction = #args > 3 and table.concat(args, " ", 4) or nil
    agent_session.pipe_session(source, dest, instruction)
  else
    vim.notify("[agent-session] Unknown subcommand: " .. subcmd, vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    local subcommands = {
      "toggle",
      "zoom",
      "toggle-zoom",
      "toggle-layout",
      "maximize",
      "new",
      "list",
      "next",
      "prev",
      "goto",
      "status",
      "agent",
      "sidebar",
      "tree",
      "delete",
      "rename",
      "prompt",
      "send",
      "pipe",
    }
    local has_trailing_space = vim.endswith(line, " ")

    if #l == 1 and has_trailing_space then
      return subcommands
    elseif #l <= 2 and not has_trailing_space then
      return vim.tbl_filter(function(item)
        return vim.startswith(item, l[2] or "")
      end, subcommands)
    elseif (#l == 2 and has_trailing_space) or (#l == 3 and not has_trailing_space) then
      local sub = l[2]
      local lead = has_trailing_space and "" or (l[3] or "")
      if sub == "new" or sub == "agent" then
        local config = require("agent-session.config").get()
        local agents = vim.tbl_keys(config.agents or {})
        return vim.tbl_filter(function(item)
          return vim.startswith(item, lead)
        end, agents)
      elseif sub == "delete" or sub == "prompt" or sub == "send" or sub == "send-to" or sub == "pipe" then
        return complete_session_targets(lead)
      end
    elseif
      (#l == 3 and has_trailing_space and l[2] == "pipe") or (#l == 4 and not has_trailing_space and l[2] == "pipe")
    then
      local lead = has_trailing_space and "" or (l[4] or "")
      return complete_session_targets(lead)
    end
    return {}
  end,
  desc = "Manage AI agent sessions",
})

-- Shorthand commands
vim.api.nvim_create_user_command("AgentSessionToggle", function()
  agent_session.toggle()
end, { desc = "Toggle agent session window" })

vim.api.nvim_create_user_command("AgentSessionZoom", function()
  agent_session.toggle_zoom()
end, { desc = "Toggle between center full (float) screen and side split view" })

vim.api.nvim_create_user_command("AgentSessionToggleZoom", function()
  agent_session.toggle_zoom()
end, { desc = "Toggle between center full (float) screen and side split view" })

vim.api.nvim_create_user_command("AgentSessionNext", function()
  agent_session.next_session()
end, { desc = "Switch to next agent session" })

vim.api.nvim_create_user_command("AgentSessionPrev", function()
  agent_session.prev_session()
end, { desc = "Switch to previous agent session" })

vim.api.nvim_create_user_command("AgentSessionGoto", function(opts)
  local idx = tonumber(opts.args)
  if idx then
    agent_session.goto_session(idx)
  else
    vim.notify("[agent-session] Please specify a session index (e.g. :AgentSessionGoto 1)", vim.log.levels.WARN)
  end
end, { nargs = 1, desc = "Switch to agent session by index number (e.g. :AgentSessionGoto 1)" })

vim.api.nvim_create_user_command("AgentSessionNew", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  agent_session.new_session(args[1], args[2])
end, {
  nargs = "*",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    local config = require("agent-session.config").get()
    local agents = vim.tbl_keys(config.agents or {})
    local lead = l[2] or ""
    return vim.tbl_filter(function(item)
      return vim.startswith(item, lead)
    end, agents)
  end,
  desc = "Create a new agent session (e.g. :AgentSessionNew agy)",
})

vim.api.nvim_create_user_command("AgentSessionSelectAgent", function()
  agent_session.select_agent()
end, { desc = "Select and launch an AI agent from picker" })

vim.api.nvim_create_user_command("AgentSessionList", function()
  agent_session.list_sessions()
end, { desc = "List active agent sessions" })

vim.api.nvim_create_user_command("AgentSessionSidebar", function()
  agent_session.toggle_sidebar()
end, { desc = "Toggle left sidebar session explorer" })

vim.api.nvim_create_user_command("AgentSessionTree", function()
  agent_session.toggle_sidebar()
end, { desc = "Toggle left sidebar session explorer" })

-- :AgentSessionPrompt [target] [prompt text...]
vim.api.nvim_create_user_command("AgentSessionPrompt", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  local target = args[1]
  local text = #args > 1 and table.concat(args, " ", 2) or nil
  agent_session.prompt_session(target, text)
end, {
  nargs = "*",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    local has_trailing_space = vim.endswith(line, " ")
    if #l == 1 and has_trailing_space then
      return complete_session_targets("")
    elseif #l <= 2 and not has_trailing_space then
      return complete_session_targets(l[2] or "")
    end
    return {}
  end,
  desc = "Send a prompt/command to a specific session (interactive picker if omitted)",
})

vim.api.nvim_create_user_command("AgentSessionSendCommand", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  local target = args[1]
  local text = #args > 1 and table.concat(args, " ", 2) or nil
  agent_session.prompt_session(target, text)
end, {
  nargs = "*",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    local has_trailing_space = vim.endswith(line, " ")
    if #l == 1 and has_trailing_space then
      return complete_session_targets("")
    elseif #l <= 2 and not has_trailing_space then
      return complete_session_targets(l[2] or "")
    end
    return {}
  end,
  desc = "Send a command to a specific session (alias of AgentSessionPrompt)",
})

-- :AgentSessionPipe [source] [target] [instruction...]
vim.api.nvim_create_user_command("AgentSessionPipe", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  local source = args[1]
  local dest = args[2]
  local instruction = #args > 2 and table.concat(args, " ", 3) or nil
  local pipe_opts = {}
  if opts.range > 0 then
    pipe_opts.range = { opts.line1, opts.line2 }
  end
  agent_session.pipe_session(source, dest, instruction, pipe_opts)
end, {
  range = true,
  nargs = "*",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    local has_trailing_space = vim.endswith(line, " ")
    if #l == 1 and has_trailing_space then
      return complete_session_targets("")
    elseif #l <= 2 and not has_trailing_space then
      return complete_session_targets(l[2] or "")
    elseif (#l == 2 and has_trailing_space) or (#l == 3 and not has_trailing_space) then
      local lead = has_trailing_space and "" or (l[3] or "")
      return complete_session_targets(lead)
    end
    return {}
  end,
  desc = "Pipe output from one session into another session with optional instruction",
})

-- :AgentSessionRename [new_name] [target]
vim.api.nvim_create_user_command("AgentSessionRename", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  agent_session.rename_session(args[1], args[2])
end, {
  nargs = "*",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    local has_trailing_space = vim.endswith(line, " ")
    if #l == 2 and has_trailing_space then
      return complete_session_targets("")
    elseif #l == 3 and not has_trailing_space then
      return complete_session_targets(l[3] or "")
    end
    return {}
  end,
  desc = "Rename current session or specified session",
})

-- :AgentSessionDelete [target]
vim.api.nvim_create_user_command("AgentSessionDelete", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  agent_session.delete_session(args[1])
end, {
  nargs = "?",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    return complete_session_targets(l[2] or "")
  end,
  desc = "Delete current session or specified session",
})

-- :AgentSessionSendLine (normal mode: current line, visual mode: selection range)
vim.api.nvim_create_user_command("AgentSessionSendLine", function(opts)
  if opts.range > 0 then
    agent_session.send_line_ref(opts.line1, opts.line2)
  else
    agent_session.send_line_ref()
  end
end, { range = true, desc = "Send current line (or visual selection) reference to active session" })

-- :AgentSessionSendLineTo [target] (normal mode: current line, visual mode: selection range)
vim.api.nvim_create_user_command("AgentSessionSendLineTo", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  local target = args[1]
  if opts.range > 0 then
    agent_session.send_line_ref_to(target, opts.line1, opts.line2)
  else
    agent_session.send_line_ref_to(target)
  end
end, {
  range = true,
  nargs = "?",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    return complete_session_targets(l[2] or "")
  end,
  desc = "Send current line (or visual selection) reference to a chosen target session",
})

-- :AgentSessionSendFile (whole current buffer)
vim.api.nvim_create_user_command("AgentSessionSendFile", function()
  agent_session.send_file_ref()
end, { desc = "Send current file reference to active session" })

-- :AgentSessionSendFileTo [target] (whole current buffer to target session)
vim.api.nvim_create_user_command("AgentSessionSendFileTo", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  agent_session.send_file_ref_to(args[1])
end, {
  nargs = "?",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    return complete_session_targets(l[2] or "")
  end,
  desc = "Send current file reference to a chosen target session",
})
