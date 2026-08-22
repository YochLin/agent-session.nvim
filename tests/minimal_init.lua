-- Minimal init file for testing agent-session.nvim with lazy.nvim
-- Run with: nvim -u tests/minimal_init.lua

local root = vim.fn.fnamemodify("./.tests", ":p")

-- Set stdpaths to use .tests directory
for _, name in ipairs({ "config", "data", "state", "cache" }) do
  vim.env[("XDG_%s_HOME"):format(name:upper())] = root .. "/" .. name
end

-- Bootstrap lazy.nvim
local lazypath = root .. "/plugins/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.runtimepath:prepend(lazypath)

-- Setup lazy.nvim with local plugin
require("lazy").setup({
  {
    dir = vim.fn.getcwd(),
    name = "agent-session.nvim",
    lazy = false,
    config = function()
      require("agent-session").setup({
        default_agent = "agy",
        agents = {
          claude = { cmd = "claude" },
          agy = { cmd = "agy" },
          codex = { cmd = "codex" },
          sh = { cmd = vim.o.shell },
        },
      })
    end,
    keys = {
      { "<leader>at", "<cmd>AgentSessionToggle<cr>", desc = "Toggle Agent Session Window" },
      { "<leader>ae", "<cmd>AgentSessionSidebar<cr>", desc = "Toggle Agent Explorer (Sidebar)" },
      { "<leader>an", "<cmd>AgentSessionNew<cr>", desc = "New Agent Session (Interactive)" },
      { "<leader>aa", "<cmd>AgentSessionSelectAgent<cr>", desc = "Select & Launch Agent" },
      { "<leader>al", "<cmd>AgentSessionList<cr>", desc = "List Active Sessions" },
      { "<leader>ap", "<cmd>AgentSessionPrompt<cr>", desc = "Prompt / Command Target Session" },
      { "<leader>ar", "<cmd>AgentSessionRename<cr>", desc = "Rename Session" },
      {
        "<leader>as",
        "<cmd>AgentSessionSendLine<cr>",
        mode = { "n", "v" },
        desc = "Send Line/Selection Ref to Session",
      },
      { "<leader>ab", "<cmd>AgentSessionSendFile<cr>", desc = "Send File Ref to Session" },
      {
        "<leader>aP",
        "<cmd>AgentSessionSendLineTo<cr>",
        mode = { "n", "v" },
        desc = "Send Selection Ref to Target Session",
      },
    },
  },
}, {
  root = root .. "/plugins",
})

vim.g.mapleader = " "
vim.opt.termguicolors = true
print("[agent-session.nvim] Test environment loaded successfully!")
