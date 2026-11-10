local runtime = require("./runtime")
local PaneStatus = require("./pane-status")
local PaneIcons = require("./pane-icons")
local PaneTitles = require("./pane-titles")
local PaneLayout = require("./pane-layout")
local GLYPH_CACHE = 4
-- SVG outlines come from the configured font and render independently of native title icons.
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
		-- The icon is rendered separately so every pane title starts in the same column.
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
		local title = PaneTitles.get(pane.pane)
		if title and title ~= pane.title then
			pane = table.clone(pane)
			pane.title = title
		end
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
	local rules, lightRules = {}, {}
	local tabIds = {}
	for tabId in groups do table.insert(tabIds, tabId) end
	table.sort(tabIds)
	for _, tabId in tabIds do
		local panes = groups[tabId]
		local window = PaneLayout.get(cx, tabId)
		if window then
			local paths = if glyphs then glyphs.paths else {}
			local image, width, height = PaneIcons.background(panes, paths, window, true)
			local lightImage = PaneIcons.background(panes, paths, window, false)
			local declarations = string.format("background-image:url(%s);background-size:%dpx %dpx;", image, width, height)
			local selector
			if #panes == 1 then
				selector = string.format('#sidebar .tn-vt .tn-dk.n1 > .tn-dk-c:not(.out)[data-pane="%.0f"]::after', panes[1].pane)
			else
				local lines, selectors = table.create(#panes), table.create(#panes)
				for i, pane in panes do
					lines[i] = paneTitle(pane)
					selectors[i] = string.format('#sidebar .tn-vt .tn-dk:not(.n1) > .tn-dk-c.d0:not(.out)[data-pane="%.0f"]::after', pane.pane)
				end
				-- Every potential front node carries the same layout and captions before focus changes.
				selector = table.concat(selectors, ",")
				declarations ..= string.format("content:%s;", cssString(table.concat(lines, "\n")))
			end
			table.insert(rules, selector .. "{" .. declarations .. "}")
			-- data-theme is Tern's rendered palette; the OS media preference can disagree.
			local lightSelector = 'html[data-theme="light"] ' .. string.gsub(selector, ",", ',html[data-theme="light"] ')
			table.insert(lightRules, lightSelector .. "{background-image:url(" .. lightImage .. ");}")
		end
	end
	PaneStatus.render(groups, cx)
	local css = table.concat(rules, "\n") .. "\n" .. table.concat(lightRules, "\n")
	if css == previousCss then return end
	tern.css("sidebar-titles", css)
	previousCss = css
end

local function measureGlyphs(cx)
	local family = cx.settings:get("ui_font") or cx.settings:get("font_family")
	if type(family) ~= "string" or family == "" then glyphs = nil; return end
	if not glyphs or glyphs.family ~= family then
		local cached = tern.kv.get("glyph-paths")
		glyphs = if type(cached) == "table" and cached.version == GLYPH_CACHE and cached.family == family
			and type(cached.paths) == "table" then cached else { version = GLYPH_CACHE, family = family, paths = {} }
	end
	if measuring then return end
	local missing = {}
	for _, pane in cx.session:panes() do
		local icon = leadingIcon(PaneTitles.get(pane.pane) or pane.title)
		if icon and glyphs.paths[icon] == nil then missing[icon] = true end
	end
	local points = {}; for icon in missing do table.insert(points, icon) end
	if #points == 0 then return end
	table.sort(points)
	measuring = true
	local argv = { runtime.node, tern.plugin.dir .. "/glyphs.mjs", family }
	for _, icon in points do table.insert(argv, icon) end
	local started, err = pcall(tern.process.run, argv, { timeout_ms = 20000 }, function(result)
		measuring = nil
		if not glyphs or glyphs.family ~= family then invalidate(); return end
		local ok, data = pcall(tern.json.decode, result.stdout)
		if result.status ~= 0 or not ok or type(data) ~= "table" or type(data.paths) ~= "table" then
			for _, icon in points do glyphs.paths[icon] = false end
			tern.log.warn("omp-sessions: icon artwork unavailable for", family, result.stderr)
		else
			for icon, path in data.paths do glyphs.paths[icon] = path end
			tern.kv.set("glyph-paths", glyphs)
		end
		invalidate()
	end)
	if not started then
		measuring = nil
		for _, icon in points do glyphs.paths[icon] = false end
		tern.log.warn("omp-sessions: cannot run " .. runtime.node .. " for icon artwork:", tostring(err))
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
for _, event in { "focus", "pane_created", "pane_closed", "tab_created", "tab_closed", "session_ended", "float_moved" } do
	tern.on(event, invalidate)
end
tern.on("title", function(ev)
	-- Known OMP panes are refreshed from conversation metadata, not child-process OSC titles.
	if not PaneTitles.get(ev.pane) then invalidate() end
end)
tern.command({ id = "pick_pane", title = "Jump to Pane", group = "OMP", icon = "terminal", run = pickPane })
tern.bind("ctrl+alt+j", "plugin.omp-sessions.pick_pane")
PaneStatus.start(panesByTab)
PaneTitles.start(invalidate)
PaneLayout.start(invalidate)
invalidate()
