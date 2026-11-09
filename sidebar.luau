local runtime = require("./runtime")
local GLYPH_CACHE = 1
-- {version, family, offsets = {["F0566"] = -0.2}}: em shifts that centre each icon's ink.
local glyphs
local measuring
local invalidate

local function leadingIcon(title)
	local ok, cp = pcall(utf8.codepoint, title, 1)
	if ok and ((cp >= 0xE000 and cp <= 0xF8FF) or cp >= 0xF0000) then return string.format("%X", cp) end
	return nil
end

local function paneTitle(pane)
	local title = string.gsub(pane.title, "%c", " ")
	if title ~= "" then
		local first = utf8.codepoint(title)
		-- The native tab already owns the Nerd Font icon; captions are text.
		if (first >= 0xE000 and first <= 0xF8FF) or (first >= 0xF0000 and first <= 0x10FFFD) then
			title = string.sub(title, utf8.offset(title, 2) or (#title + 1))
		end
		title = string.match(title, "^%s*(.-)%s*$")
	end
	if title ~= "" then return title end
	return (pane.cwd and string.match(pane.cwd, "([^/\\]+)[/\\]*$")) or "Untitled pane"
end

local function panesByTab(cx)
	local groups = {}
	for _, pane in cx.session:panes() do
		if type(pane.tab) == "number" then
			local group = groups[pane.tab]
			if not group then group = {}; groups[pane.tab] = group end
			table.insert(group, pane)
		end
	end
	for _, group in groups do table.sort(group, function(a, b) return a.pane < b.pane end) end
	return groups
end

local function cssString(value)
	return '"' .. string.gsub(value, '[\\"\n]', function(char)
		return string.format("\\%x ", string.byte(char))
	end) .. '"'
end

local previousCss
local function renderCaptions(cx)
	local groups = panesByTab(cx)
	local rules = {}
	for _, panes in groups do
		for _, pane in panes do
			local icon = leadingIcon(pane.title)
			local shift = icon and glyphs and glyphs.offsets[icon]
			if shift then
				-- Tern centres the icon's one-cell advance; this moves its ink to the tile centre.
				table.insert(rules, string.format(
					'#sidebar .tn-vt .nav-row .tn-dk-c[data-pane="%.0f"] > .tn-dk-g{transform:translateX(%.3fem);}',
					pane.pane, shift
				))
			end
		end
	end
	for _, tab in cx.session:tabs() do
		local panes = groups[tab.id]
		if panes and #panes > 1 then
			local lines = table.create(#panes)
			for i, pane in panes do lines[i] = (if i == #panes then "└ " else "├ ") .. paneTitle(pane) end
			-- A Tern tab renders at most three icon nodes. Use its front icon only
			-- as an exact-ID anchor and render every pane, not the icon subset.
			table.insert(rules, string.format(
				'#sidebar .tn-vt .tn-dk:not(.n1) > .tn-dk-c.d0[data-pane="%.0f"]::after{content:%s;}',
				tab.pane, cssString(table.concat(lines, "\n"))
			))
		end
	end
	local css = table.concat(rules, "\n")
	if css == previousCss then return end
	tern.css("sidebar-titles", css)
	previousCss = css
end

local function measureGlyphs(cx)
	local family = cx.settings:get("ui_font") or cx.settings:get("font_family")
	if type(family) ~= "string" or family == "" then glyphs = nil; return end
	if glyphs and glyphs.family == family then return end
	local cached = tern.kv.get("glyph-offsets")
	if type(cached) == "table" and cached.version == GLYPH_CACHE and cached.family == family then glyphs = cached; return end
	if measuring == family then return end
	measuring = family
	local started, err = pcall(tern.process.run, { runtime.node, tern.plugin.dir .. "/glyphs.mjs", family }, { timeout_ms = 20000 }, function(result)
		measuring = nil
		local ok, data = pcall(tern.json.decode, result.stdout)
		if result.status ~= 0 or not ok or type(data) ~= "table" or type(data.offsets) ~= "table" then
			tern.log.warn("omp-sessions: icon metrics unavailable for", family, result.stderr)
			-- Remember the failure for this family so title changes do not respawn the scan.
			glyphs = { version = GLYPH_CACHE, family = family, offsets = {} }
		else
			glyphs = { version = GLYPH_CACHE, family = family, offsets = data.offsets }
			tern.kv.set("glyph-offsets", glyphs)
		end
		invalidate()
	end)
	if not started then
		measuring = nil
		glyphs = { version = GLYPH_CACHE, family = family, offsets = {} }
		tern.log.warn("omp-sessions: cannot run " .. runtime.node .. " for icon metrics:", tostring(err))
	end
end

local pending
invalidate = function()
	if pending then return end
	pending = tern.timer(75, function(cx)
		pending = nil
		if not cx then return end
		measureGlyphs(cx)
		renderCaptions(cx)
	end)
end

local function pickPane(cx)
	local groups, names, items = panesByTab(cx), {}, {}
	local focused = cx.session:focused()
	for _, session in cx.session:sessions() do names[session.id] = session.name end
	for _, tab in cx.session:tabs() do
		local group = (names[tab.session] or "Session") .. " · " .. (tab.name or ("Tab " .. tab.position))
		for _, pane in groups[tab.id] or {} do
			table.insert(items, { label = paneTitle(pane), detail = pane.cwd, group = group, current = pane.pane == focused, pane = pane.pane })
		end
	end
	if #items == 0 then cx:toast("info", "No panes to jump to"); return end
	cx:pick({ items = items, placeholder = "Search pane titles or project paths", icon = "terminal", action = "Jump" }):next(function(item, err, fresh)
		if not fresh then return end
		if err then fresh:toast("error", "Could not open the pane picker", err); return end
		if not item then return end
		if not fresh.session:pane(item.pane) then fresh:toast("info", "This pane has already closed"); return end
		fresh.layout:focus(item.pane)
	end)
end

tern.css("sidebar", tern.fs.read(tern.plugin.dir .. "/sidebar.css"))
tern.on("window_start", invalidate)
for _, event in { "title", "focus", "pane_created", "pane_closed", "tab_created", "tab_closed", "session_ended", "float_moved" } do
	tern.on(event, invalidate)
end
tern.command({ id = "pick_pane", title = "Jump to Pane", group = "OMP", icon = "terminal", run = pickPane })
tern.bind("ctrl+alt+j", "plugin.omp-sessions.pick_pane")
invalidate()
