local config = require("agent-session.config")
local session = require("agent-session.session")

local M = {}

---Get current session info formatted for statusline
---@return table|nil
function M.get_status_data()
  local cur = session.get_current()
  if not cur then
    return nil
  end

  local opts = config.get()
  local icons = opts.status_icons or { running = "⚡", idle = "🟢", stopped = "⚪" }
  local icon = icons[cur.status] or ""

  return {
    id = cur.id,
    name = cur.name,
    agent = cur.agent,
    status = cur.status,
    icon = icon,
    text = string.format("%s %s (%s)", icon, cur.name, cur.agent),
  }
end

---Heirline / AstroNvim compatible statusline component
---@param opts? { show_empty?: boolean, icon_only?: boolean, on_click?: boolean, surround?: table }
---@return table
function M.astronvim(opts)
  opts = opts or {}

  -- If AstroUI is available in AstroNvim, enhance with native surrounding and styling
  local ok, astroui_status = pcall(require, "astroui.status")
  if ok and astroui_status.component and astroui_status.component.builder then
    return astroui_status.component.builder({
      {
        condition = function()
          if opts.show_empty then
            return true
          end
          return session.get_current() ~= nil
        end,
        provider = function()
          local data = M.get_status_data()
          if not data then
            return opts.show_empty and "None" or ""
          end
          if opts.icon_only then
            return string.format("%s %s", data.icon, data.status)
          end
          return string.format("%s %s [%s]", data.icon, data.name, data.agent)
        end,
        hl = function()
          local cur = session.get_current()
          if not cur then
            return { fg = "Comment" }
          end
          if cur.status == "running" then
            return { fg = "#f1fa8c", bold = true }
          elseif cur.status == "idle" then
            return { fg = "#50fa7b" }
          else
            return { fg = "#6272a4" }
          end
        end,
        on_click = (opts.on_click ~= false) and {
          callback = function()
            local action = opts.click_action or "list"
            if action == "sidebar" then
              require("agent-session").toggle_sidebar()
            elseif action == "toggle" then
              require("agent-session").toggle()
            else
              require("agent-session").list_sessions()
            end
          end,
          name = "agent_session_select",
        } or nil,
      },
      update = {
        "User",
        pattern = { "AgentSessionStatusChanged", "AgentSessionCurrentChanged" },
      },
      surround = opts.surround or { separator = "left", color = "bg" },
    })
  end

  -- Fallback standard Heirline component
  return {
    condition = function()
      if opts.show_empty then
        return true
      end
      return session.get_current() ~= nil
    end,
    provider = function()
      local data = M.get_status_data()
      if not data then
        return opts.show_empty and " [Agent: None] " or ""
      end
      if opts.icon_only then
        return string.format(" %s %s ", data.icon, data.status)
      end
      return string.format(" %s %s [%s] ", data.icon, data.name, data.agent)
    end,
    hl = function()
      local cur = session.get_current()
      if not cur then
        return { fg = "Comment" }
      end
      if cur.status == "running" then
        return { fg = "#f1fa8c", bold = true }
      elseif cur.status == "idle" then
        return { fg = "#50fa7b" }
      else
        return { fg = "#6272a4" }
      end
    end,
    update = {
      "User",
      pattern = { "AgentSessionStatusChanged", "AgentSessionCurrentChanged" },
    },
    on_click = (opts.on_click ~= false) and {
      callback = function()
        local action = opts.click_action or "list"
        if action == "sidebar" then
          require("agent-session").toggle_sidebar()
        elseif action == "toggle" then
          require("agent-session").toggle()
        else
          require("agent-session").list_sessions()
        end
      end,
      name = "agent_session_select",
    } or nil,
  }
end

---Alias for Heirline
M.heirline = M.astronvim

---Lualine compatible component
---@param opts? { icon_only?: boolean }
---@return table
function M.lualine(opts)
  opts = opts or {}
  return {
    function()
      local data = M.get_status_data()
      if not data then
        return ""
      end
      if opts.icon_only then
        return string.format("%s %s", data.icon, data.status)
      end
      return string.format("%s %s [%s]", data.icon, data.name, data.agent)
    end,
    cond = function()
      return session.get_current() ~= nil
    end,
    color = function()
      local cur = session.get_current()
      if not cur then
        return nil
      end
      if cur.status == "running" then
        return { fg = "#f1fa8c", gui = "bold" }
      elseif cur.status == "idle" then
        return { fg = "#50fa7b" }
      else
        return { fg = "#6272a4" }
      end
    end,
    on_click = function()
      require("agent-session").toggle()
    end,
  }
end

return M
