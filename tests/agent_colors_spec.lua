vim.opt.rtp:prepend(vim.fn.getcwd())
local config = require("agent-session.config")
local session = require("agent-session.session")
local sidebar = require("agent-session.sidebar")

-- hl resolution
assert(config.get_agent_hl("claude") == "AgentSessionAgentclaude")
assert(vim.api.nvim_get_hl(0, { name = "AgentSessionAgentclaude" }).fg == tonumber("d97757", 16))
assert(config.get_agent_hl("oh-my-pi") == "AgentSessionAgentoh_my_pi")
assert(config.get_agent_hl("nope-not-an-agent") == nil, "unknown agent must have no color")
config.setup({ agents = { claude = { cmd = "claude", color = "#000001" } } })
assert(
  vim.api.nvim_get_hl(0, { name = "AgentSessionAgentclaude" }).fg == tonumber("d97757", 16),
  "default=true keeps first def"
)
config.setup({})

-- a user's flat map must not be shadowed by the default agents[name].icon/.color
-- (codex, not claude: its group is still undefined here, and `default = true` means
-- the first definition of a group wins for the rest of the session)
config.setup({ agent_icons = { codex = "X" }, agent_colors = { codex = "#010203" } })
assert(config.get_agent_icon("codex") == "X", "agent_icons override ignored")
assert(vim.api.nvim_get_hl(0, { name = config.get_agent_hl("codex"), link = false }).fg == tonumber("010203", 16))
-- and an agent definition still wins over the flat map
config.setup({ agents = { claude = { cmd = "claude", icon = "Y" } }, agent_icons = { claude = "X" } })
assert(config.get_agent_icon("claude") == "Y", "agents[].icon should win")
config.setup({})
assert(config.get_agent_icon("claude") == "✻", "defaults lost")

-- render a real sidebar and verify the brand hl covers exactly the agent icon bytes.
-- "\u{100000}" is the plane-16 private-use codepoint the README suggests for custom
-- logo fonts: 4 bytes, so it also guards the byte-offset math against wide glyphs.
local s = session.create("demo", "claude")
sidebar._bufnr = vim.api.nvim_create_buf(false, true)
local ns = vim.api.nvim_create_namespace("AgentSessionSidebar")

for _, custom_icon in ipairs({ false, "\u{100000}" }) do
  config.setup(custom_icon and { agent_icons = { claude = custom_icon } } or {})
  sidebar.render()

  local icon = config.get_agent_icon("claude")
  assert(#icon == (custom_icon and 4 or 3), "unexpected icon width")

  local found = false
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(sidebar._bufnr, ns, 0, -1, { details = true })) do
    if m[4].hl_group == "AgentSessionAgentclaude" then
      local line = vim.api.nvim_buf_get_lines(sidebar._bufnr, m[2], m[2] + 1, false)[1]
      local covered = line:sub(m[3] + 1, m[4].end_col)
      assert(covered == icon, ("expected %q, highlighted %q"):format(icon, covered))
      found = true
    end
  end
  assert(found, "no brand highlight emitted")
  assert(
    vim.api.nvim_buf_get_lines(sidebar._bufnr, 0, -1, false)[4]:find("%[" .. vim.pesc(icon) .. " claude%]"),
    "tail malformed"
  )
end
config.setup({})

-- tabbar: the split label must be byte-identical to the old single-string format,
-- and the icon's composite group must keep the tab background.
local ui = require("agent-session.ui")
config.setup({ spinner = { enabled = false } }) -- keep status icons deterministic
vim.api.nvim_set_hl(0, "TabLine", { bg = "#112233", fg = "#aaaaaa" })
vim.api.nvim_set_hl(0, "TabLineSel", { bg = "#445566", fg = "#ffffff" })

local other = session.create("plain", "definitely-not-an-agent")
for _, cur in ipairs({ s, other }) do
  local chunks = ui.format_float_title_chunks(cur)
  local winbar = ui.format_winbar(cur)

  local text = ""
  for _, c in ipairs(chunks) do
    assert(c[1] ~= "", "empty chunk")
    text = text .. c[1]
  end

  local body = ""
  for i, o in ipairs(session.get_ordered()) do
    local st, ag = ui.get_status_icon(o.status), config.get_agent_icon(o.agent)
    local seg = ag ~= "" and (st .. " " .. ag) or st
    local fmt = o.id == cur.id and " [ %s %d:%s ] " or " %s %d:%s "
    body = body .. (i > 1 and "│" or "") .. string.format(fmt, seg, i, o.name)
  end
  assert(text == " " .. body .. " ", ("chunks %q != legacy %q"):format(text, " " .. body .. " "))

  local stripped = winbar:gsub("%%#%w+#", ""):gsub("%%=", "")
  assert(stripped == body, ("winbar %q != legacy %q"):format(stripped, body))
end

-- same check for the single-session label used when tabbar = false
config.setup({ spinner = { enabled = false }, ui = { tabbar = false, title = "Agent Session" } })
for _, cur in ipairs({ s, other }) do
  local st, ag = ui.get_status_icon(cur.status), config.get_agent_icon(cur.agent)
  local seg = ag ~= "" and (st .. " " .. ag) or st
  local legacy = string.format(" %s[%s] %s %s ", "Agent Session", cur.name, seg, cur.status)

  local text = ""
  for _, c in ipairs(ui.format_float_title_chunks(cur)) do
    assert(c[1] ~= "", "empty chunk")
    text = text .. c[1]
  end
  assert(text == legacy, ("single chunks %q != legacy %q"):format(text, legacy))

  local stripped = ui.format_winbar(cur):gsub("%%#%w+#", ""):gsub("%%%*", ""):gsub("%%=", "")
  assert(stripped == legacy, ("single winbar %q != legacy %q"):format(stripped, legacy))
end
config.setup({})

for _, group in ipairs({ "AgentSessionAgentclaudeTab", "AgentSessionAgentclaudeTabSel" }) do
  local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
  assert(hl.fg == tonumber("d97757", 16), group .. " lost the brand color")
  local tab = vim.api.nvim_get_hl(0, { name = group:gsub("Agentclaude", ""), link = false })
  assert(hl.bg == tab.bg and hl.bg ~= nil, group .. " lost the tab background")
end

print("OK")
vim.cmd("qa!")
