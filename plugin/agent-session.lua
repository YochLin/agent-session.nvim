if vim.g.loaded_agent_session == 1 then
  return
end
vim.g.loaded_agent_session = 1

local agent_session = require("agent-session")

-- :AgentSession (toggle)
vim.api.nvim_create_user_command("AgentSession", function(opts)
  local args = vim.split(opts.args, "%s+", { trimempty = true })
  local subcmd = args[1]

  if not subcmd or subcmd == "toggle" then
    agent_session.toggle()
  elseif subcmd == "new" then
    agent_session.new_session(args[2], args[3])
  elseif subcmd == "list" then
    agent_session.list_sessions()
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
    local new_name = table.concat(args, " ", 2)
    agent_session.rename_session(new_name ~= "" and new_name or nil)
  else
    vim.notify("[agent-session] Unknown subcommand: " .. subcmd, vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  complete = function(_, line)
    local l = vim.split(line, "%s+", { trimempty = true })
    local subcommands = { "toggle", "new", "list", "status", "agent", "sidebar", "tree", "delete", "rename" }
    if #l <= 2 then
      return vim.tbl_filter(function(item)
        return vim.startswith(item, l[2] or "")
      end, subcommands)
    elseif #l == 3 and (l[2] == "new" or l[2] == "agent") then
      local config = require("agent-session.config").get()
      local agents = vim.tbl_keys(config.agents or {})
      return vim.tbl_filter(function(item)
        return vim.startswith(item, l[3] or "")
      end, agents)
    end
    return {}
  end,
  desc = "Manage AI agent sessions",
})

-- Shorthand commands
vim.api.nvim_create_user_command("AgentSessionToggle", function()
  agent_session.toggle()
end, { desc = "Toggle agent session window" })

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

-- :AgentSessionSendLine (normal mode: current line, visual mode: selection range)
vim.api.nvim_create_user_command("AgentSessionSendLine", function(opts)
  -- opts.range is 0 when no explicit range (e.g. "2,4Cmd" or "'<,'>Cmd") was given,
  -- letting send_line_ref() detect a live visual selection itself.
  if opts.range > 0 then
    agent_session.send_line_ref(opts.line1, opts.line2)
  else
    agent_session.send_line_ref()
  end
end, { range = true, desc = "Send current line (or visual selection) reference to active session" })

-- :AgentSessionSendFile (whole current buffer)
vim.api.nvim_create_user_command("AgentSessionSendFile", function()
  agent_session.send_file_ref()
end, { desc = "Send current file reference to active session" })
