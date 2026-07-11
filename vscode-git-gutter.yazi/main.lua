--- @since 26.5.6
--- vscode-git-gutter.yazi
--- Syntax-highlighted text preview (via bat) with a VS Code-style git change
--- gutter, and instant scrolling: each file is rendered ONCE per (path, mtime)
--- and the ANSI lines are cached in plugin state; peek()/seek() only slice the
--- cache by the skip offset.

local MAX_LINES = 5000 -- rendering cap; longer files are truncated (see README)
local MAX_LINE_BYTES = 4096 -- per-line cap so minified one-liners stay cheap
local MAX_FILE_BYTES = 10 * 1024 * 1024 -- refuse files larger than this

local M = {}

-- ------------------------------------------------------------------ state --
-- The cache lives in the plugin's sync-context state. Sync blocks must be
-- self-contained (no upvalues), so limits are inlined.

-- Keep at most 6 files (LRU by insertion).
local store = ya.sync(function(state, path, data)
	state.files = state.files or {}
	state.order = state.order or {}
	if not state.files[path] then
		state.order[#state.order + 1] = path
		if #state.order > 6 then
			state.files[table.remove(state.order, 1)] = nil
		end
	end
	state.files[path] = data
end)

-- Returns { slice, total, truncated } or nil on cache miss / stale mtime.
local fetch = ya.sync(function(state, path, mtime, skip, limit)
	local f = state.files and state.files[path]
	if not f or f.mtime ~= mtime then
		return nil
	end
	local slice = {}
	for i = skip + 1, math.min(skip + limit, #f.lines) do
		slice[#slice + 1] = f.lines[i]
	end
	return { slice = slice, total = #f.lines, truncated = f.truncated }
end)

-- ---------------------------------------------------------------- helpers --

local function fail(job, s)
	ya.preview_widget(job, ui.Text.parse(s):area(job.area):wrap(ui.Wrap.YES))
end

local function output_of(args, cwd)
	local cmd = Command(args[1]):arg({ table.unpack(args, 2) }):stdout(Command.PIPED):stderr(Command.PIPED)
	if cwd then
		cmd = cmd:cwd(cwd)
	end
	local out = cmd:output()
	if not out then
		return nil
	end
	return out.stdout, out.status.success
end

local function split_lines(s)
	local lines = {}
	local pos = 1
	while pos <= #s do
		local nl = s:find("\n", pos, true)
		if not nl then
			lines[#lines + 1] = s:sub(pos)
			break
		end
		lines[#lines + 1] = s:sub(pos, nl - 1)
		pos = nl + 1
	end
	return lines
end

-- Marks per (new-file) line number, from `git diff -U0` hunk headers.
--   "add"     line was added
--   "mod"     line was modified
--   "del"     content was deleted just below this line
--   "deltop"  content was deleted above line 1
-- Returns nil when the file is untracked, unchanged, or not in a git repo.
local function git_marks(path)
	local dir = path:match("^(.*)/[^/]*$") or "."
	-- Worktree vs HEAD; fall back to index diff in repos with no commits yet.
	local out, ok = output_of({ "git", "-C", dir, "diff", "-U0", "--no-color", "--no-ext-diff", "HEAD", "--", path })
	if not ok then
		out, ok = output_of({ "git", "-C", dir, "diff", "-U0", "--no-color", "--no-ext-diff", "--", path })
	end
	if not ok or not out or out == "" then
		return nil
	end

	local marks = {}
	-- NOTE: never assign to for-in loop variables here; yazi 26.x's Lua
	-- runtime silently refuses to load the plugin if you do.
	for o, s, n in ("\n" .. out):gmatch("\n@@ %-%d+,?(%d*) %+(%d+),?(%d*) @@") do
		local oldn = o == "" and 1 or tonumber(o)
		local newn = n == "" and 1 or tonumber(n)
		local start = tonumber(s)
		if newn > 0 then
			local kind = oldn > 0 and "mod" or "add"
			for i = start, start + newn - 1 do
				marks[i] = kind
			end
		elseif start == 0 then
			marks[1] = marks[1] or "deltop"
		else
			marks[start] = marks[start] or "del"
		end
	end
	return next(marks) and marks or nil
end

local GUTTER = {
	add = "\27[32m\226\150\142\27[0m ", -- green ▎
	mod = "\27[34m\226\150\142\27[0m ", -- blue ▎
	del = "\27[31m\226\150\129\27[0m ", -- red ▁ (deletion below this line)
	deltop = "\27[31m\226\150\148\27[0m ", -- red ▔ (deletion above line 1)
	none = "  ",
}

-- Render the whole file once: bat for highlighting, git for the gutter,
-- dim line numbers. Returns { lines, truncated } or nil, err.
local function render(job)
	local path = tostring(job.file.url)
	local cha = job.file.cha
	if cha and cha.len and cha.len > MAX_FILE_BYTES then
		return nil, string.format("File too large for preview (> %d MiB)", MAX_FILE_BYTES / 1024 / 1024)
	end

	local out, ok = output_of({
		"bat",
		"--style=plain",
		"--color=always",
		"--paging=never",
		"--wrap=never",
		"--tabs=" .. rt.preview.tab_size,
		"--line-range=:" .. MAX_LINES,
		"--",
		path,
	})

	if not ok or not out then
		-- bat missing or failed: fall back to plain text, no highlighting
		local f = io and io.open and io.open(path, "r")
		if not f then
			return nil, "Cannot open file"
		end
		out = f:read(MAX_FILE_BYTES)
		f:close()
		out = (out or ""):gsub("\t", string.rep(" ", rt.preview.tab_size))
	end

	local lines = split_lines(out)
	local truncated = #lines >= MAX_LINES
	local marks = git_marks(path)

	local width = math.max(3, #tostring(#lines))
	local numfmt = "\27[2m%" .. width .. "d\27[22m "
	for i = 1, #lines do
		local l = lines[i]:gsub("\r$", "")
		if #l > MAX_LINE_BYTES then
			l = l:sub(1, MAX_LINE_BYTES) .. "\27[0m"
		end
		local g = marks and (GUTTER[marks[i]] or GUTTER.none) or ""
		lines[i] = g .. string.format(numfmt, i) .. l
	end
	if truncated then
		lines[#lines + 1] = "\27[2m--- truncated at " .. MAX_LINES .. " lines ---\27[22m"
	end
	return { lines = lines, truncated = truncated }
end

-- ---------------------------------------------------------------- preview --

function M:peek(job)
	local ok, err = pcall(M.peek_impl, self, job)
	if not ok then
		ya.preview_widget(job, ui.Text.parse("vscode-git-gutter ERROR: " .. tostring(err)):area(job.area))
	end
end

function M:peek_impl(job)
	local path = tostring(job.file.url)
	local cha = job.file.cha
	local mtime = (cha and cha.mtime or 0) .. ":" .. (cha and cha.len or 0)
	local limit = job.area.h

	local hit = fetch(path, mtime, job.skip, limit)
	if not hit then
		local data, err = render(job)
		if not data then
			return fail(job, err or "Preview failed")
		end
		data.mtime = mtime
		store(path, data)
		hit = fetch(path, mtime, job.skip, limit)
		if not hit then
			return fail(job, "Cache error")
		end
	end

	if job.skip > 0 and job.skip + limit > hit.total + (hit.truncated and 1 or 0) then
		local max = math.max(0, hit.total + (hit.truncated and 1 or 0) - limit)
		if job.skip > max then
			return ya.emit("peek", { max, only_if = job.file.url, upper_bound = true })
		end
	end

	ya.preview_widget(job, ui.Text.parse(table.concat(hit.slice, "\n")):area(job.area))
end

function M:seek(job)
	require("code"):seek(job)
end

return M
