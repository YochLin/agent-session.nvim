local config = require("agent-session.config")
local uv = vim.uv or vim.loop

-- Per-project persistence of open sessions, so they can be relaunched (and their
-- agent conversations resumed) after Neovim restarts.
--
-- Write rules: the saved file for this project is read once into `_pending` and never
-- dropped implicitly. Every write stores live sessions + `_pending`, so starting a new
-- session before restoring cannot clobber the previous snapshot. `_pending` is only
-- cleared by restoring it or by an explicit discard.
local M = {}

---@class AgentSessionSavedEntry
---@field name string
---@field agent string
---@field cwd? string
---@field created_at? number
---@field agent_session_id? string

---@type string|nil Project key: global cwd captured once, so a later :cd does not switch files
M._project = nil
M._loaded = false
---@type AgentSessionSavedEntry[]
M._pending = {}
---@type string|nil Name of the session that was current when the snapshot was written
M._pending_current = nil
M._save_timer = nil
M._exiting = false
M._setup_done = false

-- Delays (ms) between attempts to find / confirm an agent conversation ID after a submit
local RETRY_DELAYS = { 1500, 4000, 10000, 25000 }

---@return AgentSessionPersistConfig
local function persist_opts()
  local p = config.get().persist
  if p == false then
    return { enabled = false }
  end
  return vim.tbl_extend(
    "force",
    { enabled = true, auto_restore = "ask", max_age_days = 30 },
    type(p) == "table" and p or {}
  )
end

---@return boolean
function M.enabled()
  return persist_opts().enabled ~= false
end

---Wall clock time in milliseconds
---@return number
function M.now_ms()
  local sec, usec = uv.gettimeofday()
  return sec * 1000 + math.floor((usec or 0) / 1000)
end

---Resolve symlinks (e.g. /tmp vs /private/tmp on macOS) so cwd comparisons are stable
---@param path? string
---@return string|nil
function M.realpath(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return uv.fs_realpath(path) or vim.fs.normalize(path)
end

---Generate an RFC 4122 version 4 UUID
---@return string
function M.gen_uuid()
  local b = {}
  local ok, bytes = pcall(uv.random, 16)
  if ok and type(bytes) == "string" and #bytes == 16 then
    for i = 1, 16 do
      b[i] = bytes:byte(i)
    end
  else
    for i = 1, 16 do
      b[i] = math.random(0, 255)
    end
  end
  b[7] = bit.bor(bit.band(b[7], 0x0f), 0x40)
  b[9] = bit.bor(bit.band(b[9], 0x3f), 0x80)
  return string.format(
    "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
    (table.unpack or unpack)(b)
  )
end

---Resume definition for an agent, or nil when the agent cannot be resumed
---@param agent_name string
---@return AgentResumeConfig|nil
function M.resume_spec(agent_name)
  local agents = config.get().agents or {}
  local def = agents[agent_name]
  if def and type(def.resume) == "table" then
    return def.resume
  end
  return nil
end

---@return string
function M.project()
  if not M._project then
    M._project = M.realpath(vim.fn.getcwd(-1, -1)) or vim.fn.getcwd(-1, -1)
  end
  return M._project
end

---@return string
local function projects_dir()
  local base = config.get().session_dir or (vim.fn.stdpath("data") .. "/agent-sessions")
  return base .. "/projects"
end

---Path of the saved file for a project (readable cwd-derived name, hashed if too long)
---@param project? string
---@return string
function M.project_file(project)
  project = project or M.project()
  local name = project:gsub("[\\/:]", "%%")
  if #name > 200 then
    name = vim.fn.sha256(project)
  end
  return projects_dir() .. "/" .. name .. ".json"
end

---@param path string
---@return table|nil
local function read_json(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content or "")
  if ok and type(data) == "table" then
    return data
  end
  return nil
end

---@param v any
---@return string|nil
local function str_or_nil(v)
  if type(v) == "string" and v ~= "" then
    return v
  end
  return nil
end

---Read this project's saved file into `_pending` (once per Neovim instance)
function M.load()
  if M._loaded then
    return
  end
  M._loaded = true
  if not M.enabled() then
    return
  end

  local data = read_json(M.project_file())
  if not data or type(data.sessions) ~= "table" then
    return
  end
  for _, e in ipairs(data.sessions) do
    if type(e) == "table" and str_or_nil(e.agent) then
      table.insert(M._pending, {
        name = str_or_nil(e.name) or e.agent,
        agent = e.agent,
        cwd = str_or_nil(e.cwd),
        created_at = tonumber(e.created_at),
        agent_session_id = str_or_nil(e.agent_session_id),
      })
    end
  end
  M._pending_current = str_or_nil(data.current)
end

---@return AgentSessionSavedEntry[]
function M.get_pending()
  M.load()
  return M._pending
end

---Remove and return all pending entries (caller is responsible for relaunching them)
---@return AgentSessionSavedEntry[] pending, string|nil current_name
function M.take_pending()
  M.load()
  local pending, current = M._pending, M._pending_current
  M._pending = {}
  M._pending_current = nil
  return pending, current
end

---Put entries back into pending (e.g. ones that failed to relaunch)
---@param entries AgentSessionSavedEntry[]
function M.put_back(entries)
  for _, e in ipairs(entries or {}) do
    table.insert(M._pending, e)
  end
  M.save()
end

---Explicitly drop the saved snapshot for this project
function M.discard_pending()
  M.load()
  M._pending = {}
  M._pending_current = nil
  M.write_now()
end

---Conversation IDs already owned by a live session or a pending entry
---@return table<string, boolean>
function M.claimed_ids()
  local session = require("agent-session.session")
  local claimed = {}
  for _, s in pairs(session.get_all()) do
    if s.agent_session_id then
      claimed[s.agent_session_id] = true
    end
  end
  for _, e in ipairs(M._pending) do
    if e.agent_session_id then
      claimed[e.agent_session_id] = true
    end
  end
  return claimed
end

---Check whether a pre-assigned conversation ID has actually been created by the agent
---@param sess Session
---@return boolean
local function confirm_conversation(sess)
  if sess._has_conversation then
    return true
  end
  if not sess.agent_session_id then
    return false
  end
  local resume = M.resume_spec(sess.agent)
  if resume and type(resume.exists) == "function" then
    local ok, exists = pcall(resume.exists, sess.agent_session_id, sess)
    if ok and exists then
      sess._has_conversation = true
    end
  end
  return sess._has_conversation == true
end

---@return AgentSessionSavedEntry[] list, string|nil current
local function collect()
  local session = require("agent-session.session")
  local list = {}
  for _, s in ipairs(session.get_ordered()) do
    if s.status ~= "stopped" and (s.job_id or 0) > 0 then
      table.insert(list, {
        name = s.name,
        agent = s.agent,
        cwd = s.cwd,
        created_at = s.created_at,
        -- Only keep IDs that point at a real conversation; resuming an unused one would fail
        agent_session_id = confirm_conversation(s) and s.agent_session_id or nil,
      })
    end
  end
  for _, e in ipairs(M._pending) do
    table.insert(list, e)
  end

  local cur = session.get_current()
  local current = (cur and cur.status ~= "stopped" and cur.name) or M._pending_current
  return list, current
end

---Write the snapshot synchronously (removes the file when there is nothing to save)
function M.write_now()
  if not M.enabled() then
    return
  end
  M.load()

  local list, current = collect()
  local path = M.project_file()
  if #list == 0 then
    if uv.fs_stat(path) then
      os.remove(path)
    end
    return
  end

  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local ok, json = pcall(vim.json.encode, {
    version = 1,
    project = M.project(),
    updated_at = os.time(),
    current = current,
    sessions = list,
  })
  if not ok then
    return
  end

  -- Write to a temp file then rename, so a crash mid-write never leaves a truncated snapshot
  local tmp = path .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    return
  end
  f:write(json)
  f:close()
  os.rename(tmp, path)
end

---Debounced save, safe to call from any session lifecycle event
function M.save()
  if M._exiting or not M.enabled() then
    return
  end
  if not M._save_timer or M._save_timer:is_closing() then
    M._save_timer = uv.new_timer()
  end
  M._save_timer:stop()
  M._save_timer:start(
    300,
    0,
    vim.schedule_wrap(function()
      if not M._exiting then
        M.write_now()
      end
    end)
  )
end

---Final synchronous save on exit. Later saves are ignored so jobs being killed during
---shutdown cannot overwrite the snapshot with an empty list.
function M.flush()
  if M._save_timer and not M._save_timer:is_closing() then
    M._save_timer:stop()
  end
  if M._exiting then
    return
  end
  M.write_now()
  M._exiting = true
end

---Delete saved files of other projects that have not been touched in `max_age_days`
function M.prune()
  local days = persist_opts().max_age_days
  if type(days) ~= "number" or days <= 0 then
    return
  end
  local dir = projects_dir()
  if not uv.fs_stat(dir) then
    return
  end
  local cutoff = os.time() - days * 86400
  local own = M.project_file()
  for name, typ in vim.fs.dir(dir) do
    if typ == "file" and name:match("%.json$") then
      local path = dir .. "/" .. name
      if path ~= own then
        local st = uv.fs_stat(path)
        if st and st.mtime and st.mtime.sec < cutoff then
          os.remove(path)
        end
      end
    end
  end
end

------------------------------------------------------------------------------
-- Conversation ID discovery for CLIs that cannot pin an ID at launch
------------------------------------------------------------------------------

---@param path string
---@return string|nil
local function read_first_line(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local line = f:read("*l")
  f:close()
  return line
end

---@param path string
---@param max_bytes number
---@return string|nil
local function read_tail(path, max_bytes)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local size = f:seek("end") or 0
  local start = math.max(0, size - max_bytes)
  f:seek("set", start)
  local text = f:read("*a") or ""
  f:close()
  if start > 0 then
    -- Drop the partial first line
    text = text:gsub("^[^\n]*\n", "", 1)
  end
  return text
end

---Parse an ISO-8601 UTC timestamp ("2026-08-22T02:43:06.643Z") into epoch milliseconds
---@param s any
---@return number|nil
local function parse_iso_utc_ms(s)
  if type(s) ~= "string" then
    return nil
  end
  local y, mo, d, h, mi, se, frac = s:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)%.?(%d*)")
  if not y then
    return nil
  end
  -- os.time() treats the table as local time; shift by the local UTC offset
  local local_t = os.time({
    year = tonumber(y),
    month = tonumber(mo),
    day = tonumber(d),
    hour = tonumber(h),
    min = tonumber(mi),
    sec = tonumber(se),
    isdst = false,
  })
  local now = os.time()
  local utc_now = os.date("!*t", now) --[[@as osdate]]
  utc_now.isdst = false
  local offset = os.difftime(now, os.time(utc_now))
  local ms = tonumber(((frac or "") .. "000"):sub(1, 3)) or 0
  return (local_t + offset) * 1000 + ms
end

---Find the codex rollout created by this session's process.
---Rollouts live at $CODEX_HOME/sessions/YYYY/MM/DD/rollout-*.jsonl and start with a
---`session_meta` line carrying the conversation id, cwd and process start timestamp.
---@param sess Session
---@param claimed table<string, boolean>
---@return string|nil
function M._discover_codex(sess, claimed)
  local home = vim.env.CODEX_HOME or ((vim.env.HOME or "~") .. "/.codex")
  local root = home .. "/sessions"
  local started = sess._started_ms or ((sess.created_at or os.time()) * 1000)
  local cwd = M.realpath(sess.cwd)
  local real_cache = {}
  local best, best_score

  local seen = {}
  for _, t in ipairs({ math.floor(started / 1000), os.time(), os.time() - 86400 }) do
    local dir = root .. os.date("/%Y/%m/%d", t)
    if not seen[dir] and uv.fs_stat(dir) then
      seen[dir] = true
      for name, typ in vim.fs.dir(dir) do
        if typ == "file" and name:match("^rollout%-.*%.jsonl$") then
          local path = dir .. "/" .. name
          local st = uv.fs_stat(path)
          if st and st.mtime and st.mtime.sec * 1000 >= started - 5000 then
            local ok, meta = pcall(vim.json.decode, read_first_line(path) or "")
            local p = ok and type(meta) == "table" and meta.type == "session_meta" and meta.payload
            if type(p) == "table" then
              local id = str_or_nil(p.id) or str_or_nil(p.session_id)
              local is_user_thread = p.thread_source == nil or p.thread_source == "user"
              if id and not claimed[id] and is_user_thread and type(p.cwd) == "string" then
                if real_cache[p.cwd] == nil then
                  real_cache[p.cwd] = M.realpath(p.cwd) or false
                end
                local ts = parse_iso_utc_ms(p.timestamp)
                if real_cache[p.cwd] == cwd and ts and ts >= started - 3000 then
                  -- The meta timestamp is the codex process start, so the closest one is ours
                  local score = math.abs(ts - started)
                  if not best_score or score < best_score then
                    best, best_score = id, score
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return best
end

---Find the agy conversation created by this session's process.
---agy appends `{ timestamp(ms), workspace, conversationId }` to history.jsonl on every
---submit; the conversation's .db file is created when the process starts.
---@param sess Session
---@param claimed table<string, boolean>
---@return string|nil
function M._discover_agy(sess, claimed)
  local home = (vim.env.HOME or "~") .. "/.gemini/antigravity-cli"
  local text = read_tail(home .. "/history.jsonl", 256 * 1024)
  if not text then
    return nil
  end
  local started = sess._started_ms or ((sess.created_at or os.time()) * 1000)
  local submit = sess._submit_ms or started
  local cwd = M.realpath(sess.cwd)
  local real_cache = {}
  local best, best_score

  for line in text:gmatch("[^\n]+") do
    local ok, e = pcall(vim.json.decode, line)
    if
      ok
      and type(e) == "table"
      and type(e.conversationId) == "string"
      and type(e.timestamp) == "number"
      and type(e.workspace) == "string"
      and not claimed[e.conversationId]
      and e.timestamp >= started - 2000
    then
      if real_cache[e.workspace] == nil then
        real_cache[e.workspace] = M.realpath(e.workspace) or false
      end
      if real_cache[e.workspace] == cwd then
        -- Skip conversations that existed before this process started (e.g. an agy
        -- running outside Neovim in the same directory)
        local st = uv.fs_stat(home .. "/conversations/" .. e.conversationId .. ".db")
        local born = st and st.birthtime and st.birthtime.sec or 0
        if born == 0 or born * 1000 >= started - 2000 then
          local score = math.abs(e.timestamp - submit)
          if not best_score or score < best_score then
            best, best_score = e.conversationId, score
          end
        end
      end
    end
  end
  return best
end

---@param sess Session
---@param strategy "codex"|"agy"|function
---@return string|nil
function M.discover(sess, strategy)
  local claimed = M.claimed_ids()
  local ok, id
  if type(strategy) == "function" then
    ok, id = pcall(strategy, sess, claimed)
  elseif strategy == "codex" then
    ok, id = pcall(M._discover_codex, sess, claimed)
  elseif strategy == "agy" then
    ok, id = pcall(M._discover_agy, sess, claimed)
  end
  if ok and type(id) == "string" and id ~= "" and not claimed[id] then
    return id
  end
  return nil
end

---Called whenever the user submits input to a session. Finds (or confirms) the agent's
---conversation ID with a few backed-off retries, since CLIs write their files lazily.
---@param sess Session
function M.on_submit(sess)
  if not M.enabled() or sess._has_conversation then
    return
  end
  local resume = M.resume_spec(sess.agent)
  if not resume then
    return
  end

  sess._submit_ms = M.now_ms()
  sess._discover_gen = (sess._discover_gen or 0) + 1
  local gen = sess._discover_gen
  local session = require("agent-session.session")

  local function attempt(i)
    if sess._discover_gen ~= gen or sess._has_conversation or not session.get(sess.id) then
      return
    end

    local found = false
    if sess.agent_session_id then
      -- Pre-assigned ID: confirm the CLI created it (or trust the submit if no checker)
      found = type(resume.exists) ~= "function" or confirm_conversation(sess)
      if found then
        sess._has_conversation = true
      end
    elseif resume.discover then
      local id = M.discover(sess, resume.discover)
      if id then
        sess.agent_session_id = id
        sess._has_conversation = true
        found = true
      end
    end

    if found then
      M.save()
    elseif RETRY_DELAYS[i + 1] then
      vim.defer_fn(function()
        attempt(i + 1)
      end, RETRY_DELAYS[i + 1])
    end
  end

  vim.defer_fn(function()
    attempt(1)
  end, RETRY_DELAYS[1])
end

------------------------------------------------------------------------------
-- Startup
------------------------------------------------------------------------------

---Ask whether to restore the pending snapshot
function M.prompt_restore()
  local pending = M.get_pending()
  if #pending == 0 then
    return
  end

  local counts, order = {}, {}
  for _, e in ipairs(pending) do
    if not counts[e.agent] then
      counts[e.agent] = 0
      table.insert(order, e.agent)
    end
    counts[e.agent] = counts[e.agent] + 1
  end
  local parts = {}
  for _, agent in ipairs(order) do
    table.insert(parts, string.format("%s x%d", agent, counts[agent]))
  end

  local choices = { "Restore", "Later", "Discard" }
  vim.ui.select(choices, {
    prompt = string.format("Restore %d agent session(s) from last time? (%s)", #pending, table.concat(parts, ", ")),
  }, function(choice)
    if choice == "Restore" then
      require("agent-session").restore_sessions()
    elseif choice == "Discard" then
      M.discard_pending()
      vim.notify("[agent-session] Discarded saved sessions for this project.", vim.log.levels.INFO)
    else
      vim.notify(
        "[agent-session] Saved sessions kept. Run :AgentSessionRestore to restore them later.",
        vim.log.levels.INFO
      )
    end
  end)
end

---Register exit hook and the startup restore check (idempotent)
function M.setup()
  if M._setup_done or not M.enabled() then
    return
  end
  M._setup_done = true
  M.project()

  local group = vim.api.nvim_create_augroup("AgentSessionPersist", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      M.flush()
    end,
  })

  local function on_start()
    pcall(M.prune)
    M.load()
    if #M._pending == 0 then
      return
    end
    local mode = persist_opts().auto_restore
    if mode == true then
      require("agent-session").restore_sessions({ open = false })
    elseif mode == "ask" then
      M.prompt_restore()
    end
  end

  -- Lazy-loaded setups may run after VimEnter already fired
  if vim.v.vim_did_enter == 1 then
    vim.schedule(on_start)
  else
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      once = true,
      callback = function()
        vim.schedule(on_start)
      end,
    })
  end
end

return M
