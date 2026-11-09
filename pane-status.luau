local runtime = require("./runtime")
local M = {}
local LINE = 24
local FRAMES = 12
local alerts = {}
local previousCss
local sampling = false
local timer
local warned = false
local getGroups

local function icon(state, angle)
	if state == "working" then
		return '<g transform="rotate(' .. angle .. ' 8 8)"><path d="M12.95 3.05A7 7 0 1 1 3.05 3.05" fill="none" stroke="#5aa2ff" stroke-width="2"/></g>'
	elseif state == "waiting" then
		return '<circle cx="8" cy="8" r="8" fill="#e0a526"/><path d="M5.7 5.7a2.3 2.3 0 0 1 4.6 0c0 1.7-2.3 1.7-2.3 3.4" fill="none" stroke="#2b1d00" stroke-width="1.6" stroke-linecap="round"/><circle cx="8" cy="12" r=".9" fill="#2b1d00"/>'
	elseif state == "done" then
		return '<circle cx="8" cy="8" r="8" fill="#3fae6a"/><path d="m4.5 8 2.3 2.5 4.7-5" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'
	elseif state == "failed" then
		return '<circle cx="8" cy="8" r="8" fill="#e05561"/><path d="m5.3 5.3 5.4 5.4m0-5.4-5.4 5.4" stroke="white" stroke-width="1.8" stroke-linecap="round"/>'
	elseif state == "bell" then
		return '<circle cx="8" cy="8" r="8" fill="#9b7be0"/><path d="M8 4v5" stroke="white" stroke-width="1.8" stroke-linecap="round"/><circle cx="8" cy="12" r=".9" fill="white"/>'
	end
	return ""
end

local function sprite(states, count, moving)
	-- A horizontal CSS sprite rotates only working rings. Other rows are identical in every
	-- frame, so they stay still; no SVG scripts, image animation, or per-frame Lua work is needed.
	local frames = if moving then FRAMES else 1
	local parts = { string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', frames * 16, count * LINE) }
	for frame = 0, frames - 1 do
		for row = 1, count do
			if states[row] then
				table.insert(parts, string.format('<g transform="translate(%d %.1f)">', frame * 16, (row - 1) * LINE + (LINE - 16) / 2))
				table.insert(parts, icon(states[row], frame * 360 / FRAMES))
				table.insert(parts, '</g>')
			end
		end
	end
	table.insert(parts, '</svg>')
	return '"data:image/svg+xml;base64,' .. tern.base64.encode(table.concat(parts)) .. '"', frames
end

local function paneState(pane, agent)
	if pane.error or (type(pane.exited) == "number" and pane.exited ~= 0) then return "failed" end
	if agent == "waiting_input" then return "waiting" end
	if agent == "working" then return "working" end
	-- Native acknowledgement clears pane.alert. Never keep showing an old completion after it
	-- was viewed, and never infer which kind of alert it was from a boolean alone.
	if pane.alert then return alerts[pane.pane] end
	return nil
end

function M.render(groups, cx)
	local agents = {}
	for _, agent in cx.agents:list() do agents[agent.pane] = agent.state end
	local tabIds = {}
	for id in groups do table.insert(tabIds, id) end
	table.sort(tabIds)
	local rules = {}
	for _, tabId in tabIds do
		local panes = groups[tabId]
		if #panes > 1 then
			local states, selectors = {}, table.create(#panes)
			local active, moving = false, false
			for row, pane in panes do
				states[row] = paneState(pane, agents[pane.pane])
				active = active or states[row] ~= nil
				moving = moving or states[row] == "working"
				selectors[row] = string.format('#sidebar .tn-vt .tn-dk:not(.n1) > .tn-dk-c.d0:not(.out)[data-pane="%.0f"]::before', pane.pane)
			end
			if active then
				local image, frames = sprite(states, #panes, moving)
				table.insert(rules, table.concat(selectors, ",") .. string.format('{height:%dpx;background-image:url(%s);background-size:%dpx %dpx;animation:%s;}', #panes * LINE, image, frames * 16, #panes * LINE, if moving then "ompPaneStatusSpin 900ms steps(11) infinite" else "none"))
			end
		end
	end
	local css = table.concat(rules, "\n")
	if css == previousCss then return end
	tern.css("pane-status", css)
	previousCss = css
end

local sample
local function schedule(ms)
	if timer then timer:cancel() end
	timer = tern.timer(ms or 900, function(cx)
		timer = nil
		if cx then sample(cx) end
	end)
end

sample = function(cx)
	local groups = getGroups(cx)
	M.render(groups, cx)
	if sampling then return end
	local multiple = false
	for _, panes in groups do if #panes > 1 then multiple = true; break end end
	if not multiple then schedule(); return end
	-- The control CLI routes through the pane socket, not a developer control endpoint. Respect
	-- an explicit daemon socket; Tern 0.9.13 uses this per-user named pipe on Windows by default.
	local socket = tern.getenv("TERN_PANE_SOCKET") or tern.getenv("TERN_DAEMON_SOCKET")
	if not socket and runtime.windows then
		local user = tern.getenv("USERNAME")
		if user and user ~= "" then socket = "\\\\.\\pipe\\tern-" .. user end
	end
	local env = { TERN_WINDOW_KEY = cx:window_key(), TERN_PANE = "", TERN_WINDOW_SOCKET = "" }
	if socket then env.TERN_PANE_SOCKET = socket end
	sampling = true
	local ok, err = pcall(tern.process.run, { runtime.tern, "ctl", "state" }, { timeout_ms = 1800, env = env }, function(result, fresh)
		sampling = false
		local decoded, data = pcall(tern.json.decode, result.stdout)
		if result.status == 0 and decoded and type(data) == "table" and data.ok and type(data.inbox) == "table" then
			local nextAlerts, sequence = {}, {}
			for _, entry in data.inbox.entries or {} do
				local kind = ({ waiting = "waiting", finished = "done", failed = "failed", bell = "bell" })[entry.kind]
				if entry.kind == "done" or entry.kind == "exited" then kind = if entry.status == 0 then "done" else "failed" end
				if kind and (not sequence[entry.pane] or entry.seq > sequence[entry.pane]) then
					nextAlerts[entry.pane], sequence[entry.pane] = kind, entry.seq
				end
			end
			alerts, warned = nextAlerts, false
		elseif not warned then
			tern.log.warn("omp-sessions: cannot read native pane alerts:", result.stderr)
			warned = true
		end
		if fresh then M.render(getGroups(fresh), fresh) end
		schedule()
	end)
	if not ok then
		sampling = false
		if not warned then tern.log.warn("omp-sessions: cannot start pane alert reader:", tostring(err)); warned = true end
		schedule()
	end
end

function M.start(provider)
	getGroups = provider
	-- Agent state hooks run while Tern is updating its agent registry. Read that registry only
	-- on the next timer turn, never re-enter it synchronously from its own notification.
	for _, event in { "agent_state", "agent_finished", "command_started", "command_finished" } do
		tern.on(event, function() schedule(0) end)
	end
	schedule(0)
end

return M
