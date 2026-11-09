local Input = require("./input")
local runtime = require("./runtime")
local ui = tern.ui
local running = {}
local FILTERS = { "All", "Open", "History" }
local function node(kind, props, children) return ui.node(kind, props, children) end
local function decorate(n, key, role)
	n.p = n.p or {}; n.p.key, n.p.role = key, role
	return n
end
local function alive(s)
	if running[s.cx.pane] ~= s then return false end
	for _, pane in tern.pane.list() do if pane.pane == s.cx.pane then return true end end
	running[s.cx.pane] = nil
	if s.timer then s.timer:cancel(); s.timer = nil end
	return false
end
local function live(row) return #row.panes > 0 end
local function working(row)
	for _, pane in row.panes do if pane.working then return true end end
	return false
end
local function refilter(s)
	local selected = s.selectedPath
	local tokens = {}
	for token in string.gmatch(string.lower(s.query.text), "%S+") do table.insert(tokens, token) end
	local rows = {}
	s.counts = { 0, 0, 0 }
	for _, row in s.rows do
		local haystack = string.lower(row.title .. "\n" .. row.cwd .. "\n" .. row.id .. "\n" .. row.preview)
		local matches = true
		for _, token in tokens do if not string.find(haystack, token, 1, true) then matches = false; break end end
		if matches then
			local category = if live(row) then 2 else 3
			s.counts[1] += 1; s.counts[category] += 1
			if s.filter == 1 or s.filter == category then table.insert(rows, row) end
		end
	end
	s.visible, s.selected = rows, 0
	for i, row in rows do if row.path == selected then s.selected = i - 1; break end end
	s.selectedPath = if rows[s.selected + 1] then rows[s.selected + 1].path else nil
end
local function selectRow(s, index)
	s.selected = math.clamp(index, 0, math.max(0, #s.visible - 1))
	s.selectedPath = if s.visible[s.selected + 1] then s.visible[s.selected + 1].path else nil
end
local function focusSearch(s)
	s.cx:frame({ { "focus", "main.search" } })
end
local function activate(s)
	local row = s.visible[s.selected + 1]
	if row then s.cx:open("omp-session://open/" .. tern.base64.encode(tern.json.encode({ path = row.path, cwd = row.cwd }), { url = true })) end
end
local refresh
local function schedule(s)
	if not alive(s) then return end
	if s.timer then s.timer:cancel() end
	s.timer = tern.timer(8000, function()
		s.timer = nil
		if alive(s) then refresh(s) end
	end)
end
refresh = function(s)
	if not alive(s) or s.busy then return end
	if s.timer then s.timer:cancel(); s.timer = nil end
	s.busy, s.error = true, nil
	local ok, err = pcall(function()
		tern.process.run({ runtime.node, tern.plugin.dir .. "/sessions.mjs", "list", "--tern", runtime.tern }, { timeout_ms = 12000 }, function(result)
			if not alive(s) then return end
			s.busy = false
			if result.status ~= 0 then
				s.error = if result.timed_out then "Session scan timed out. Press F5 to retry." else "Could not read sessions. Make sure " .. runtime.node .. " and " .. runtime.tern .. " are on PATH: " .. (if result.stderr and result.stderr ~= "" then result.stderr else tostring(result.status))
			else
				local parsed, data = pcall(tern.json.decode, result.stdout)
				if parsed and type(data) == "table" and type(data.sessions) == "table" then
					s.rows, s.warnings, s.loaded = data.sessions, data.warnings or {}, true
					table.sort(s.rows, function(a, b)
						if live(a) ~= live(b) then return live(a) end
						if a.modified ~= b.modified then return a.modified > b.modified end
						return a.path < b.path
					end)
					refilter(s)
				else s.error = "Session scanner returned invalid JSON. Press F5 to retry." end
			end
			schedule(s)
			s.cx:render()
		end)
	end)
	if not ok then s.busy, s.error = false, "Could not run " .. runtime.node .. ". Make sure it is on PATH: " .. tostring(err); schedule(s) end
end
local function chip(label, act, selected)
	local n = decorate(ui.badge(label, if selected then "accent" else "neutral"), act, "omp.chip")
	n.p.actions, n.p.aria = { click = act }, label
	return n
end
tern.block.define("panel", {
	features = { "edit" },
	init = function(cx)
		local s = { cx = cx, rows = {}, visible = {}, counts = { 0, 0, 0 }, selected = 0, selectedPath = nil, query = Input.new(""), filter = 1, busy = false, loaded = false, warnings = {} }
		running[cx.pane] = s
		refresh(s)
		return s
	end,
	title = function() return "OMP Sessions" end,
	view = function(s, cx)
		local filters = {}
		for i, label in FILTERS do table.insert(filters, chip(label .. " " .. s.counts[i], "filter=" .. i, s.filter == i)) end
		table.insert(filters, chip(if s.busy then "Refreshing…" else "Refresh (F5)", "refresh", false))
		local children = {
			decorate(ui.text(ui.span("OMP Sessions", "strong")), "heading", "omp.heading"),
			Input.view(s.query), decorate(ui.row(filters), "filters", "omp.filters"),
		}
		if s.error then table.insert(children, decorate(ui.text(ui.span(s.error, "error")), "error", "omp.notice")) end
		if #s.warnings > 0 then table.insert(children, decorate(ui.text(ui.span(table.concat(s.warnings, "\n"), "warning")), "warnings", "omp.notice")) end
		if #s.visible > 0 then
			local items = {}
			for _, row in s.visible do
				local locations = {}
				for _, pane in row.panes do if pane.location ~= "" then table.insert(locations, pane.location) end end
				local project = string.match(string.gsub(row.cwd, "[/\\]+$", ""), "([^/\\]+)$") or row.cwd
				table.insert(items, {
					label = if row.title ~= "" then row.title else row.id,
					detail = project .. " · " .. row.cwd .. (if #locations > 0 then " · " .. table.concat(locations, " / ") else ""),
					value = if working(row) then "Working" elseif live(row) then "Open" else "History",
				})
			end
			local list = decorate(ui.list(items), "sessions", "omp.sessions")
			local kids = list.c or {}
			for i, row in s.visible do
				local key = tern.base64.encode(row.path, { url = true })
				kids[i].p = kids[i].p or {}
				kids[i].p.key = key
				kids[i].p.actions = { click = "open=" .. key }
			end
			local selectedRow = s.visible[s.selected + 1]
			list.p.selected = if selectedRow then "main.sessions." .. tern.base64.encode(selectedRow.path, { url = true }) else nil
			list.p.max = { lines = math.max(4, cx.rows - 9) }
			table.insert(children, list)
		else
			local message = if s.busy and not s.loaded then "Loading local OMP sessions…" elseif s.error and not s.loaded then "Could not read sessions. Press F5 to retry." elseif s.query.text ~= "" then "No matching sessions. Press Esc to clear the search." elseif s.filter == 2 then "No open sessions." elseif s.filter == 3 then "No saved sessions." else "No OMP sessions yet."
			table.insert(children, decorate(ui.text(ui.span(message, "muted")), "empty", "omp.empty"))
		end
		local selected = s.visible[s.selected + 1]
		local dock = {
			decorate(ui.text(ui.span("↑/↓ Select · PgUp/PgDn Page · Enter or click to open · Ctrl+L or / Search · Esc Clear · Tab Filter · F5 Refresh", "muted")), "shortcuts", "omp.hint"),
			decorate(ui.text(ui.span("Type or paste to search. All terms must match. Refreshes every 8 seconds.", "muted")), "typing-hint", "omp.hint"),
		}
		if selected and selected.preview ~= "" then table.insert(dock, decorate(ui.text(ui.span(selected.preview, "muted")), "preview", "omp.preview")) end
		return { main = decorate(ui.col(children), "main", "omp.main"), dock = decorate(ui.col(dock), "dock", "omp.dock") }
	end,
	key = function(s, key, cx)
		local name = string.lower(key.name)
		if name == "f5" then refresh(s)
		elseif name == "enter" then activate(s)
		elseif name == "up" then selectRow(s, s.selected - 1)
		elseif name == "down" then selectRow(s, s.selected + 1)
		elseif name == "page_up" then selectRow(s, s.selected - math.max(1, cx.rows - 10))
		elseif name == "page_down" then selectRow(s, s.selected + math.max(1, cx.rows - 10))
		elseif name == "tab" then s.filter = ((s.filter - 1 + (if key.shift then -1 else 1)) % #FILTERS) + 1; refilter(s)
		elseif name == "escape" then Input.clear(s.query); refilter(s)
		elseif ((key.ctrl or key.meta) and name == "l") or name == "/" then focusSearch(s)
		else
			local changed = Input.key(s.query, key, cx)
			if not changed then return false end
			refilter(s); focusSearch(s)
		end
		return true
	end,
	event = function(s, ev)
		if ev.ev == "edit" and ev.id == "main.search" then
			if Input.edit(s.query, ev) then refilter(s) end
		elseif ev.ev == "action" and ev.act == "refresh" then refresh(s)
		elseif ev.ev == "action" and ev.act == "filter" then
			local filter = tonumber(ev.value)
			if filter and filter >= 1 and filter <= #FILTERS then s.filter = filter; refilter(s) end
		elseif ev.ev == "select" or ev.ev == "activate" or (ev.ev == "action" and ev.act == "open") then
			local key = if ev.ev == "action" then ev.value else (if type(ev.item) == "string" then string.match(ev.item, "^main%.sessions%.(.+)$") else nil)
			if type(key) == "string" then
				for i, row in s.visible do
					if tern.base64.encode(row.path, { url = true }) == key then
						selectRow(s, i - 1)
						if ev.ev ~= "select" then activate(s) end
						break
					end
				end
			end
		end
	end,
})
