local session = require("agent-session.session")
local config = require("agent-session.config")

print("=== Running Auto-Title Unit Tests ===")

-- Test 1: clean_prompt_text
local t1 = session.clean_prompt_text("❯ 幫我重構 session.lua 的命名邏輯")
assert(t1 == "幫我重構 session.lua 的命名邏輯", "Failed t1: got " .. tostring(t1))

local t2 = session.clean_prompt_text("> Fix auth bug in backend\nMore details here...")
assert(t2 == "Fix auth bug in backend", "Failed t2: got " .. tostring(t2))

local t3 = session.clean_prompt_text("@lua/agent-session/session.lua:10-20 Add new field")
assert(t3 == "Add new field", "Failed t3: got " .. tostring(t3))

local t4 = session.clean_prompt_text("\27[31m❯\27[0m  Test colored prompt")
assert(t4 == "Test colored prompt", "Failed t4: got " .. tostring(t4))

print("✓ clean_prompt_text tests passed")

-- Test 2: generate_local_title (UTF-8 safe truncation)
local l1 = session.generate_local_title("幫我重構 session.lua 的命名邏輯與狀態管理", 12)
assert(l1 == "幫我重構 session...", "Failed l1: got " .. tostring(l1))
assert(vim.fn.strchars(l1) == 15, "UTF-8 char count mismatch")

local l2 = session.generate_local_title("Short prompt", 20)
assert(l2 == "Short prompt", "Failed l2: got " .. tostring(l2))

print("✓ generate_local_title tests passed")

-- Test 3: detect_prompt_from_buffer ignores banners and finds real prompt
local test_sess = {
  bufnr = vim.api.nvim_create_buf(false, true),
}
vim.api.nvim_buf_set_lines(test_sess.bufnr, 0, -1, false, {
  "╭─ Claude Code ────────╮",
  "│ Welcome to Claude    │",
  "│ > Try: Explain code  │",
  "│ ? for shortcuts      │",
  "╰──────────────────────╯",
  "> Try: Explain this codebase",
  "? for shortcuts",
  "",
  "❯ How do I optimize this query?",
  "Thinking...",
})
local detected = session.detect_prompt_from_buffer(test_sess)
assert(detected == "How do I optimize this query?", "Failed detected: got " .. tostring(detected))
vim.api.nvim_buf_delete(test_sess.bufnr, { force = true })
print("✓ detect_prompt_from_buffer tests passed")

-- Test 4: Startup banner only buffer does NOT detect prompt
local banner_sess = {
  bufnr = vim.api.nvim_create_buf(false, true),
}
vim.api.nvim_buf_set_lines(banner_sess.bufnr, 0, -1, false, {
  "╭─ Claude Code ────────╮",
  "│ Welcome to Claude    │",
  "│ > Try asking a query │",
  "╰──────────────────────╯",
  "> Try: Explain this codebase",
  "? for shortcuts",
})
assert(session.detect_prompt_from_buffer(banner_sess) == nil, "Startup banner should not detect prompt")
vim.api.nvim_buf_delete(banner_sess.bufnr, { force = true })
print("✓ Startup banner filtering passed")

-- Test 4: handle_first_prompt auto rename
local sess = session.create(nil, "sh")
assert(sess._custom_named == false, "Default session should not be custom named")
assert(sess._auto_titled == false, "Initial session should not be auto titled")

session.handle_first_prompt(sess, "❯ 幫我實作 JWT 驗證功能")
assert(sess._auto_titled == true, "Session should be marked auto titled")
assert(sess.name == "幫我實作 JWT 驗證功能", "Session name should be updated, got " .. tostring(sess.name))

-- Subsequent prompt should not rename
session.handle_first_prompt(sess, "❯ Another question")
assert(sess.name == "幫我實作 JWT 驗證功能", "Session name should remain unchanged")

session.delete(sess.id)
print("✓ handle_first_prompt auto rename tests passed")

-- Test 5: Custom named session should not be overridden
local custom_sess = session.create("my-custom-task", "sh")
assert(custom_sess._custom_named == true, "Explicitly named session should be custom named")
session.handle_first_prompt(custom_sess, "❯ Fix login bug")
assert(custom_sess.name == "my-custom-task", "Custom named session should not be renamed")
session.delete(custom_sess.id)
print("✓ Custom named session protection tests passed")

-- Test 6: AI custom_fn summarization
local ai_sess = session.create(nil, "sh")
config.setup({
  auto_title = {
    enabled = true,
    ai = {
      enabled = true,
      custom_fn = function(prompt, s, cb)
        cb("AI 總結: " .. vim.fn.strcharpart(prompt, 0, 6))
      end,
    },
  },
})

session.handle_first_prompt(ai_sess, "重構前端登入頁面與元件樣式")
assert(
  ai_sess.name == "AI 總結: 重構前端登入",
  "AI custom_fn should update name, got " .. tostring(ai_sess.name)
)
session.delete(ai_sess.id)
-- Test 7: Real Claude Code startup & prompt simulation
local claude_sess = {
  bufnr = vim.api.nvim_create_buf(false, true),
}
-- 1) Real Claude Code startup screen (with suggestion placeholder: ❯\194\160Try "fix typecheck errors")
vim.api.nvim_buf_set_lines(claude_sess.bufnr, 0, -1, false, {
  " ▐▛███▛█   Claude Code v2.1.258",
  "▝▜██████▀  Sonnet 5 · Claude Pro",
  "  ▝▝ ▝▝    ~/Desktop/side_project/agent-session.nvim",
  "",
  "",
  "────────────────────────────────────────────────────────────────────────────────",
  '❯\194\160Try "fix typecheck errors"',
  "────────────────────────────────────────────────────────────────────────────────",
  "  Sonnet 5 | Tokens: 0 / Ctx: 1.0M                            ● high · /effort",
  "  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents          /rc connecting…",
  "",
})
assert(
  session.detect_prompt_from_buffer(claude_sess) == nil,
  "Claude Code startup suggestion should NOT be detected as prompt!"
)

-- 2) Real Claude Code after typing actual prompt
vim.api.nvim_buf_set_lines(claude_sess.bufnr, 0, -1, false, {
  " ▐▛███▛█   Claude Code v2.1.258",
  "▝▜██████▀  Sonnet 5 · Claude Pro",
  "  ▝▝ ▝▝    ~/Desktop/side_project/agent-session.nvim",
  "",
  "",
  "────────────────────────────────────────────────────────────────────────────────",
  "❯\194\160幫我重構認證模組",
  "",
  "────────────────────────────────────────────────────────────────────────────────",
  "  Sonnet 5 | Tokens: 0 / Ctx: 1.0M                       ctrl+g to edit in Vim",
  "  ⏵⏵ auto mode on (shift+tab to cycle)                                     /rc",
  "",
})
local detected_prompt = session.detect_prompt_from_buffer(claude_sess)
assert(
  detected_prompt == "幫我重構認證模組",
  "Real user prompt should be detected! Got: " .. tostring(detected_prompt)
)
vim.api.nvim_buf_delete(claude_sess.bufnr, { force = true })
print("✓ Real Claude Code startup & prompt detection tests passed")

print("=== ALL AUTO-TITLE TESTS PASSED SUCCESSFULLY! ===")
vim.cmd("qa!")
