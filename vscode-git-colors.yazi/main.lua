--- @since 26.5.6
--- vscode-git-colors.yazi
---
--- Colors file and directory NAMES by their git status, VS Code style:
--- modified = yellow/orange, untracked/added = green, deleted = red,
--- ignored = dim. Applies to the current column, the hovered row, the
--- parent column, and the directory-preview column.
---
--- Also renders VS Code-style status decorations:
--- - current column (linemode child): files get a status letter
---   (M/U/A/D), directories get a colored dot (●), like VS Code's
---   explorer badges;
--- - preview and parent columns (no linemode there): the same letter/dot
---   is appended after the file name as a styled, display-only suffix.
---
--- The fetching machinery (git status parsing, bubble-up, propagate-down)
--- is adapted from yazi-rs/plugins:git (MIT). This plugin keeps its own
--- state because git.yazi's state is private to that plugin.

local WINDOWS = ya.target_family() == "windows"

-- How long (seconds) an on-demand fetch result is trusted before a render
-- may trigger a refresh; also throttles retries for non-repo directories.
local TTL = 5

-- Status codes; the numeric order decides which status wins for a
-- directory that contains files with different statuses (see bubble_up).
---@enum CODES
local CODES = {
	unknown = 100, -- status cannot/not yet determined
	excluded = 99, -- ignored directory
	untracked_dir = 98, -- wholly-untracked directory (git prints `?? dir/`)
	ignored = 6, -- ignored file
	untracked = 5,
	modified = 4,
	added = 3,
	deleted = 2,
	updated = 1,
	clean = 0,
}

local PATTERNS = {
	{ "!$", CODES.ignored },
	{ "?$", CODES.untracked },
	{ "[MT]", CODES.modified },
	{ "[AC]", CODES.added },
	{ "D", CODES.deleted },
	{ "U", CODES.updated },
	{ "[AD][AD]", CODES.updated },
}

---@param line string
---@return CODES, string
local function match(line)
	local signs = line:sub(1, 2)
	for _, p in ipairs(PATTERNS) do
		local path, pattern, code = nil, p[1], p[2]
		if signs:find(pattern) then
			path = line:sub(4, 4) == '"' and line:sub(5, -2) or line:sub(4)
			path = WINDOWS and path:gsub("/", "\\") or path
		end
		if not path then
		elseif path:find("[/\\]$") then
			-- A trailing slash means the whole directory has this status.
			-- Keep that meaning with a distinct code for ignored (excluded)
			-- and untracked (untracked_dir) so resolve() can extend the
			-- status to every descendant; other codes never get dir form.
			local dir_code = code
			if code == CODES.ignored then
				dir_code = CODES.excluded
			elseif code == CODES.untracked then
				dir_code = CODES.untracked_dir
			end
			return dir_code, path:sub(1, -2)
		else
			return code, path
		end
		---@diagnostic disable-next-line: missing-return
	end
end

---@param cwd Url
---@return string?
local function root(cwd)
	local is_worktree = function(url)
		local file, head = io.open(tostring(url)), nil
		if file then
			head = file:read(8)
			file:close()
		end
		return head == "gitdir: "
	end

	repeat
		local next = cwd:join(".git")
		local cha = fs.cha(next)
		if cha and (cha.is_dir or is_worktree(next)) then
			return tostring(cwd)
		end
		cwd = cwd.parent
	until not cwd
end

---@param changed table<string, CODES>
---@return table<string, CODES>
local function bubble_up(changed)
	local new, empty = {}, Url("")
	for path, code in pairs(changed) do
		if code ~= CODES.ignored then
			-- Ancestors of a wholly-untracked dir are plain untracked;
			-- never propagate the untracked_dir marker upward, or clean
			-- siblings would resolve as untracked through it.
			local c = code == CODES.untracked_dir and CODES.untracked or code
			local url = Url(path).parent
			while url and url ~= empty do
				local s = tostring(url)
				new[s] = (new[s] or CODES.clean) > c and new[s] or c
				url = url.parent
			end
		end
	end
	return new
end

---@param excluded string[]
---@param cwd Url
---@param repo Url
---@return table<string, CODES>
local function propagate_down(excluded, cwd, repo)
	local new, rel = {}, cwd:strip_prefix(repo)
	for _, path in ipairs(excluded) do
		if rel:starts_with(path) then
			new[tostring(cwd)] = CODES.excluded
		elseif cwd == repo:join(path).parent then
			new[path] = CODES.ignored
		end
	end
	return new
end

local add = ya.sync(function(st, cwd, repo, changed)
	st.dirs[cwd] = repo
	st.repos[repo] = st.repos[repo] or {}
	for path, code in pairs(changed) do
		if code == CODES.clean then
			st.repos[repo][path] = nil
		elseif code == CODES.excluded then
			st.dirs[path] = CODES.excluded
		else
			st.repos[repo][path] = code
		end
	end
	ui.render()

	-- The directory-preview column is a widget cached at peek time, so a
	-- plain re-render won't recolor it. If the hovered directory is the one
	-- we just fetched (or lies inside it), peek again to repaint it.
	local hovered = cx.active.current.hovered
	if hovered and hovered.cha.is_dir then
		local h = tostring(hovered.url)
		if h == cwd or (#h > #cwd and h:sub(1, #cwd + 1) == cwd .. "/") then
			ya.emit("peek", { force = true })
		end
	end
end)

local remove = ya.sync(function(st, cwd)
	local repo = st.dirs[cwd]
	if not repo then
		return
	end

	ui.render()
	st.dirs[cwd] = nil
	if not st.repos[repo] then
		return
	end

	for _, r in pairs(st.dirs) do
		if r == repo then
			return
		end
	end
	st.repos[repo] = nil
end)

-- Accept a hex/named color string, a theme-style table ({ fg = ... }), or
-- a ui.Style. Tables are converted to a real ui.Style so the result is
-- safe for both Span:style() and Style:patch().
local function to_style(v)
	if type(v) == "string" then
		return ui.Style():fg(v)
	elseif type(v) == "table" then
		local s = ui.Style()
		if v.fg then
			s = s:fg(v.fg)
		end
		if v.bg then
			s = s:bg(v.bg)
		end
		if v.bold then
			s = s:bold()
		end
		if v.dim then
			s = s:dim()
		end
		if v.italic then
			s = s:italic()
		end
		if v.underline then
			s = s:underline()
		end
		if v.crossed then
			s = s:crossed()
		end
		if v.reversed then
			s = s:reverse()
		end
		return s
	end
	return v
end

-- Resolve the status code for a url from the plugin's state, triggering a
-- throttled on-demand fetch when the containing directory has no data yet.
-- Returns nil while the status is unknown. Called from the Entity style
-- patch, the linemode sign, and the preview/parent suffix; lookups are
-- memoized in st.dirs and the TTL throttle keeps the emits deduplicated,
-- so the extra callers add no fetch traffic.
---@return CODES?
local function resolve(st, url)
	local dir = tostring(url.base or url.parent)

	local repo = st.dirs[dir]
	if not repo then
		-- Not fetched directly. Walk up: if any ancestor directory was
		-- fetched, its git status already covers this directory too
		-- (git pathspecs match recursively), so reuse its repo.
		local up, empty = Url(dir).parent, Url("")
		while up and up ~= empty do
			local v = st.dirs[tostring(up)]
			if v then
				repo = v
				break
			end
			up = up.parent
		end
		if type(repo) == "string" then
			-- dir may itself sit inside an ignored directory: any
			-- repo-relative ancestor marked ignored dims the subtree.
			local paths, rel = st.repos[repo] or {}, Url(dir:sub(#repo + 2))
			while rel and rel ~= empty do
				if paths[tostring(rel)] == CODES.ignored then
					repo = CODES.excluded
					break
				end
				rel = rel.parent
			end
		end
		if repo then
			st.dirs[dir] = repo
		end
	end

	local now = ya.time()
	if not repo then
		-- No data at all (parent column, or a previewed directory whose
		-- ancestors were never loaded): fetch on demand, throttled.
		if not st.tried[dir] or now - st.tried[dir] > TTL then
			st.tried[dir] = now
			ya.emit("plugin", { "vscode-git-colors", ya.quote(dir) })
		end
		return nil
	end

	-- Refresh stale on-demand data (dirs kept fresh by the regular
	-- fetcher never enter st.tried, so this only re-runs entry fetches).
	if st.tried[dir] and now - st.tried[dir] > TTL then
		st.tried[dir] = now
		ya.emit("plugin", { "vscode-git-colors", ya.quote(dir) })
	end

	if repo == CODES.excluded then
		return CODES.ignored
	end
	local paths = st.repos[repo]
	if not paths then
		return CODES.clean
	end

	local rel = Url(tostring(url):sub(#repo + 2))
	local code = paths[tostring(rel)]
	if code == CODES.untracked_dir then
		return CODES.untracked
	elseif code then
		return code
	end

	-- No status of its own: everything inside a wholly-untracked directory
	-- is untracked too (VS Code behavior), but git only reported the top
	-- directory (`?? dir/`), so check repo-relative ancestors for the
	-- untracked_dir marker. Tracked dirs that merely contain untracked
	-- files never carry this marker (bubble_up stores plain untracked),
	-- so their clean children stay clean.
	local up, empty = rel.parent, Url("")
	while up and up ~= empty do
		if paths[tostring(up)] == CODES.untracked_dir then
			return CODES.untracked
		end
		up = up.parent
	end
	return CODES.clean
end

local function setup(st, opts)
	st.dirs = {}
	st.repos = {}
	-- dirs fetched on demand (via entry) or found to be outside a repo:
	-- last attempt timestamp, used for TTL-based refresh/retry.
	st.tried = {}

	opts = opts or {}
	local t = th.git_name or {}
	local g = th.git or {} -- share git.yazi's [git] palette when themed

	-- Colors: setup() opts > [git_name] theme > [git] theme > VS Code
	-- default dark theme gitDecoration.* colors. Reading [git] keeps the
	-- palette in one theme section even with git.yazi's signs blanked.
	local styles = {
		[CODES.modified] = to_style(opts.modified or t.modified or g.modified) or ui.Style():fg("#e2c08d"),
		[CODES.added] = to_style(opts.added or t.added or g.added) or ui.Style():fg("#81b88b"),
		[CODES.untracked] = to_style(opts.untracked or t.untracked or g.untracked) or ui.Style():fg("#73c991"),
		[CODES.deleted] = to_style(opts.deleted or t.deleted or g.deleted) or ui.Style():fg("#c74e39"),
		[CODES.updated] = to_style(opts.updated or t.updated or g.updated) or ui.Style():fg("#e4676b"),
		[CODES.ignored] = to_style(opts.ignored or t.ignored or g.ignored) or ui.Style():fg("#8c8c8c"),
	}

	-- Status signs, VS Code style. Files get a letter; directories get a
	-- dot (dir_sign) whenever a file with the same status would get a
	-- letter. Deliberately NOT read from [git]: that section's *_sign
	-- values must stay blank so git.yazi's own linemode never
	-- double-renders next to ours.
	local signs = {
		[CODES.modified] = opts.modified_sign or t.modified_sign or "M",
		[CODES.added] = opts.added_sign or t.added_sign or "A",
		[CODES.untracked] = opts.untracked_sign or t.untracked_sign or "U",
		[CODES.deleted] = opts.deleted_sign or t.deleted_sign or "D",
		[CODES.updated] = opts.updated_sign or t.updated_sign or "M",
		[CODES.ignored] = opts.ignored_sign or t.ignored_sign or "",
	}
	local dir_sign = opts.dir_sign or t.dir_sign or "●"

	---@param file File
	---@param code CODES?
	---@return string
	local function sign_of(file, code)
		local s = code and signs[code] or ""
		if s == "" then
			return ""
		end
		return file.cha.is_dir and dir_sign or s
	end

	-- Monkey-patch the Entity renderer. Entity is used by the current
	-- column, the parent column, and the built-in folder previewer (which
	-- is `@sync peek`, so it sees this patch too); the whole row is styled
	-- with Entity:style(). Spans that set their own color (e.g. icons) are
	-- unaffected, so effectively this recolors the file name.
	local style = Entity.style
	function Entity:style()
		local s = style(self)

		-- Patch AFTER the original style so the git foreground also wins on
		-- the hovered row; a bg/reversed hover indicator is preserved since
		-- these styles only set the foreground.
		local code = resolve(st, self._file.url)
		local patch = code and styles[code]
		return patch and s:patch(patch) or s
	end

	-- Current-column sign column (a linemode child, like git.yazi's):
	-- letters for files, a colored dot for directories. Mirrors git.yazi's
	-- hover behavior, leaving the hovered row's sign unstyled so the
	-- flavor's hover bar renders it.
	Linemode:children_add(function(self)
		local f = self._file
		if not f.in_current then
			return ""
		end

		local code = resolve(st, f.url)
		local sign = sign_of(f, code)
		if sign == "" then
			return ""
		elseif f.is_hovered then
			return ui.Line { " ", sign }
		else
			return ui.Line { " ", ui.Span(sign):style(styles[code]) }
		end
	end, opts.order or 1500)

	-- Preview- and parent-column decoration: those columns render no
	-- linemode, so append the sign to the name as a display-only suffix
	-- (an Entity child ordered after the symlink child at 6000). Never
	-- rendered in the current column, which has the sign column above.
	Entity:children_add(function(self)
		local f = self._file
		if f.in_current then
			return ""
		end

		local code = resolve(st, f.url)
		local sign = sign_of(f, code)
		if sign == "" then
			return ""
		elseif f.is_hovered then
			return ui.Line { "   ", sign }
		else
			return ui.Line { "   ", ui.Span(sign):style(styles[code]) }
		end
	end, 7000)
end

local function fetch(_, job)
	local cwd = job.files[1].url.base or job.files[1].url.parent
	local repo = root(cwd)
	if not repo then
		remove(tostring(cwd))
		return true
	end

	local paths = {}
	for _, file in ipairs(job.files) do
		paths[#paths + 1] = tostring(file.url)
	end

	-- stylua: ignore
	local output, err = Command("git")
		:cwd(tostring(cwd))
		:arg({ "--no-optional-locks", "-c", "core.quotePath=", "status", "--porcelain", "-unormal", "--no-renames", "--ignored=matching" })
		:arg(paths)
		:output()
	if not output then
		return true, Err("Cannot spawn `git` command, error: %s", err)
	end

	local changed, excluded = {}, {}
	for line in output.stdout:gmatch("[^\r\n]+") do
		local code, path = match(line)
		if code == CODES.excluded then
			excluded[#excluded + 1] = path
		else
			changed[path] = code
		end
	end

	if job.files[1].cha.is_dir then
		ya.dict_merge(changed, bubble_up(changed))
	end
	ya.dict_merge(changed, propagate_down(excluded, cwd, Url(repo)))

	for _, path in ipairs(paths) do
		local s = path:sub(#repo + 2)
		changed[s] = changed[s] or CODES.clean
	end

	add(tostring(cwd), repo, changed)

	return false
end

-- On-demand fetch for a single directory that the regular fetcher never
-- covers (parent column, previewed directories outside the loaded tree).
-- Invoked from the render path via `ya.emit("plugin", ...)`, so it runs
-- async and reports back through the shared sync state.
local function entry(_, job)
	local dir = job.args[1]
	if not dir then
		return
	end

	local cwd = Url(dir)
	local repo = root(cwd)
	if not repo then
		return
	end

	-- stylua: ignore
	local output = Command("git")
		:cwd(dir)
		:arg({ "--no-optional-locks", "-c", "core.quotePath=", "status", "--porcelain", "-unormal", "--no-renames", "--ignored=matching", tostring(cwd) })
		:output()
	if not output then
		return
	end

	local changed, excluded = {}, {}
	for line in output.stdout:gmatch("[^\r\n]+") do
		local code, path = match(line)
		if code == CODES.excluded then
			excluded[#excluded + 1] = path
		else
			changed[path] = code
		end
	end

	ya.dict_merge(changed, bubble_up(changed))
	ya.dict_merge(changed, propagate_down(excluded, cwd, Url(repo)))

	add(tostring(cwd), repo, changed)
end

return { setup = setup, fetch = fetch, entry = entry }
