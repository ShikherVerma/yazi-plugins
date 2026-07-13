--- @since 26.5.6
--- mobile-auto-layout.yazi
---
--- Two-mode adaptive layout for yazi:
---   BROWSE  (default)  panes fit their content
---   READING (on scroll of the preview) preview takes over
---
--- Mode switching:
---   -> READING when the user scrolls the preview (J/K seek keys or the
---      mouse/touch wheel over the preview pane). Detected by REPLACING the
---      seek() of the configured previewers; both keys and wheel funnel into
---      previewer seek, so one hook sees both.
---   -> BROWSE when the hover changes in the file list (j/k, or clicking a
---      row), or on any click in the file list (covers clicking the row that
---      is already hovered, e.g. the phone sliver).
---
--- Width classes (re-evaluated every render pass, so terminal resizes are
--- picked up automatically via the Tab.layout override):
---   laptop (width >= threshold):
---     BROWSE : parent fit-to-longest-dirname (cap 30, navigable) | list fit (cap 30) | preview rest
---     READING: parent 0 | list fit (cap 30) | preview rest
---   phone (width < threshold):
---     BROWSE : parent = slim fixed gutter (parent_gutter cols), a tap-to-go-back
---              button (any click emits "leave"); hidden at root | list fit (cap 30) | preview rest
---     READING: parent 0 | list = narrow sliver (~10%) | preview rest (~90%)
---
--- Status bar is patched to show ONLY the hovered file's name.

local M = {}

local cfg = {
	threshold = 90, -- columns; below this = phone
	parent_max = 30, -- laptop BROWSE: parent pane fit-to-dirname cap (real, navigable)
	parent_gutter = 6, -- phone BROWSE: slim parent column acting as a tap-to-go-back button
	current_max = 30, -- file-list width cap
	min_width = 10, -- floor for fit-to-content panes
	reading_frac = 0.10, -- phone READING: file-list sliver fraction
	padding = 9, -- icon + sign + pane borders added to the longest name
	previewers = { "vscode-git-gutter", "code" }, -- whose seek() to hook
}

local state = {
	mode = "browse", -- "browse" | "reading"
	phone = false, -- current width class; read by the parent click handler
	hovered = nil, -- url of last seen hovered file
	last = nil, -- last ratio written, "p:c:v"
	fit = {}, -- fit-width cache: role -> { key, cap, width }
}

-- Mode switch from outside a render pass (seek / click handlers) needs an
-- explicit re-layout; inside Tab.layout it is picked up on the same pass.
local function set_mode(mode)
	if state.mode ~= mode then
		state.mode = mode
		ya.emit("app:resize", {})
	end
end

local function text_width(s)
	local ok, w = pcall(function() return ui.Line(ui.printable(s)):width() end)
	if ok and type(w) == "number" then
		return w
	end
	return #s
end

-- Width that fits the longest file name in `folder`, plus padding, capped.
-- Cached per (cwd, file count) so it is only recomputed when the folder
-- changes, not on every render pass.
local function fit_width(role, folder, cap)
	if not folder then
		return 0
	end
	local files = folder.files
	local n = #files
	if n == 0 then
		return math.min(cap, cfg.min_width)
	end
	local key = tostring(folder.cwd) .. "\0" .. n
	local hit = state.fit[role]
	if hit and hit.key == key and hit.cap == cap then
		return hit.width
	end
	local best = 0
	for i = 1, n do
		local w = text_width(files[i].name)
		if w > best then
			best = w
		end
		if best + cfg.padding >= cap then
			break
		end
	end
	local width = math.max(cfg.min_width, math.min(cap, best + cfg.padding))
	state.fit[role] = { key = key, cap = cap, width = width }
	return width
end

-- Decide the ratio for this render pass and write it (only on change) so the
-- original Tab:layout that runs right after us picks it up.
local function apply(self)
	local w = self._area and self._area.w or 0
	if w < 4 then
		return
	end
	local tab = self._tab or cx.active

	-- Hover change => back to BROWSE. We are already inside a render pass,
	-- so a plain state flip is enough; no re-layout emit needed.
	local h = tab.current.hovered
	local hkey = h and tostring(h.url) or ""
	if state.hovered == nil then
		state.hovered = hkey
	elseif hkey ~= state.hovered then
		state.hovered = hkey
		state.mode = "browse"
	end

	local phone = w < cfg.threshold
	state.phone = phone
	local p, c
	if state.mode == "reading" then
		p = 0
		if phone then
			c = math.max(3, math.floor(w * cfg.reading_frac))
		else
			c = fit_width("current", tab.current, cfg.current_max)
		end
	elseif phone then
		-- Slim back-button gutter; hidden only when there is nothing to
		-- leave to (tab.parent is nil at the filesystem root).
		p = tab.parent and cfg.parent_gutter or 0
		c = fit_width("current", tab.current, cfg.current_max)
	else
		-- Laptop: normal fit-to-dirname parent column (navigable as usual).
		p = fit_width("parent", tab.parent, cfg.parent_max)
		c = fit_width("current", tab.current, cfg.current_max)
	end

	local v = w - p - c
	if v < 1 then
		v = 1
		c = math.max(1, w - p - v)
	end

	local key = p .. ":" .. c .. ":" .. v
	if state.last ~= key then
		state.last = key
		rt.mgr.ratio = { p, c, v } -- setter takes an indexed table
	end
end

-- Replacement previewer seek. NOTE: this must be a full REPLACEMENT of the
-- preset body (yazi's require() proxies are late-bound, so calling a captured
-- "original" resolves back to this function and recurses). Body mirrors
-- preset code.lua of yazi 26.5.6.
local function seek(_, job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = math.floor(job.units * job.area.h / 10)
		step = step == 0 and ya.clamp(-1, job.units, 1) or step

		ya.emit("peek", {
			math.max(0, cx.active.preview.skip + step),
			only_if = job.file.url,
		})
	end

	-- Emit the peek BEFORE set_mode: set_mode emits app:resize, whose
	-- re-peek must run after the skip above has been stored (FIFO), or it
	-- would re-peek at the old offset.
	set_mode("reading")
end

function M:setup(opts)
	for k, v in pairs(opts or {}) do
		cfg[k] = v
	end

	-- 1) Scroll detection: replace seek() on the configured previewers.
	for _, name in ipairs(cfg.previewers) do
		local ok, mod = pcall(require, name)
		if ok and mod then
			pcall(function() mod.seek = seek end)
		end
	end

	-- 2) Width / resize detection + ratio writing: wrap Tab.layout. It runs
	-- on every render pass (including terminal resizes), and a ratio written
	-- before delegating takes effect on that same pass.
	local tab_layout = Tab.layout
	Tab.layout = function(self, ...)
		pcall(apply, self)
		return tab_layout(self, ...)
	end

	-- 3) Any click in the file list returns to BROWSE (covers clicking the
	-- already-hovered row, where no hover change would fire).
	local current_click = Current.click
	Current.click = function(self, event, up)
		if not up then
			set_mode("browse")
		end
		return current_click(self, event, up)
	end

	-- 4) On phone, the slim parent gutter is a back button: ANY click steps
	-- out one level, never navigating to the clicked row. On laptop the
	-- parent is a normal navigable column, so delegate to the preset there.
	-- Fires on the down edge only, so one tap = one leave.
	local parent_click = Parent.click
	Parent.click = function(self, event, up)
		if not state.phone then
			return parent_click(self, event, up)
		end
		if up or event.is_middle then
			return
		end
		ya.emit("leave", {})
	end

	-- 5) Status bar: only the hovered file's name (task progress overlay is
	-- kept, since it is transient feedback, not a status segment).
	Status.redraw = function(self)
		local els = {
			ui.Text(""):area(self._area):style(th.status.overall),
		}
		local hov = self._current and self._current.hovered
		if hov then
			els[#els + 1] = ui.Line(" " .. ui.printable(hov.name)):area(self._area)
		end
		local ok, prog = pcall(function() return ui.redraw(Progress:new(self._area, 0)) end)
		if ok and prog then
			for _, e in ipairs(prog) do
				els[#els + 1] = e
			end
		end
		return els
	end
end

return M
