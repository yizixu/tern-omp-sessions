local runtime = require("./runtime")
local M = {}
local titles = {}
local timer
local scanning = false
local warned = false
local onChange
local schedule

local function same(a, b)
	for pane, title in a do if b[pane] ~= title then return false end end
	for pane in b do if a[pane] == nil then return false end end
	return true
end

local function warn(detail)
	if warned then return end
	tern.log.warn("omp-sessions: cannot read OMP session titles:", detail)
	warned = true
end

local function scan(cx)
	if scanning then return end
	local socket = tern.getenv("TERN_PANE_SOCKET") or tern.getenv("TERN_DAEMON_SOCKET")
	if not socket and runtime.windows then
		local user = tern.getenv("USERNAME")
		if user and user ~= "" then socket = "\\\\.\\pipe\\tern-" .. user end
	end
	local env = { TERN_WINDOW_KEY = cx:window_key(), TERN_PANE = "", TERN_WINDOW_SOCKET = "" }
	if socket then env.TERN_PANE_SOCKET = socket end
	scanning = true
	local ok, err = pcall(tern.process.run,
		{ runtime.node, tern.plugin.dir .. "/sessions.mjs", "live", "--tern", runtime.tern },
		{ timeout_ms = 12000, env = env }, function(result, fresh)
			scanning = false
			if not fresh then return end
			local decoded, data = pcall(tern.json.decode, result.stdout)
			if result.status == 0 and decoded and type(data) == "table" and type(data.sessions) == "table" then
				local nextTitles = {}
				for _, session in data.sessions do
					for _, pane in session.panes do nextTitles[pane.pane] = session.title end
				end
				warned = false
				if not same(titles, nextTitles) then
					titles = nextTitles
					onChange()
					tern.chrome.refresh()
				end
			else
				warn(if result.stderr and result.stderr ~= "" then result.stderr else "invalid session scan")
			end
			schedule(2000)
		end)
	if not ok then
		scanning = false
		warn(tostring(err))
		schedule(2000)
	end
end

schedule = function(ms)
	if timer then timer:cancel() end
	timer = tern.timer(ms, function(cx)
		timer = nil
		if cx then scan(cx) end
	end)
end

function M.get(pane)
	return titles[pane]
end

function M.start(changed)
	onChange = changed
	-- A custom tab name remains authoritative. Otherwise use the focused OMP conversation,
	-- never the title of a temporary child process sharing its terminal.
	tern.chrome.tab_title(function(tab)
		local title = titles[tab.pane]
		if not title then return nil end
		return if tab.name and tab.name ~= "" then tab.name else title
	end)
	for _, event in { "pane_created", "pane_closed", "session_ended" } do
		tern.on(event, function() schedule(0) end)
	end
	schedule(0)
end

return M
