local runtime = require("./runtime")
local M = {}
local LINE = 24
local WIDTH = 36
local FADE = "linear-gradient(to right,rgb(from var(--omp-card-fill) r g b / 0),var(--omp-card-fill) 16px)"
local FRAMES = 54 -- 60 fps over the existing 900 ms revolution.
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
	-- The endpoint repeats frame zero, avoiding a blank or angular jump at the loop seam.
	local frames = if moving then FRAMES + 1 else 1
	local parts = { string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', frames * WIDTH, count * LINE), '<defs>' }
	local defined = {}
	for row = 1, count do
		local state = states[row]
		if state and not defined[state] then
			table.insert(parts, '<g id="status-' .. state .. '">' .. icon(state, 0) .. '</g>')
			defined[state] = true
		end
	end
	table.insert(parts, '</defs>')
	for frame = 0, frames - 1 do
		for row = 1, count do
			local state = states[row]
			if state then
				local rotation = if state == "working" then string.format(' transform="rotate(%.3f 8 8)"', (frame % FRAMES) * 360 / FRAMES) else ""
				table.insert(parts, string.format('<g transform="translate(%d %.1f)"><use href="#status-%s"%s/></g>', frame * WIDTH + WIDTH - 16, (row - 1) * LINE + (LINE - 16) / 2, state, rotation))
			end
		end
	end
	table.insert(parts, '</svg>')
	return '"data:image/svg+xml;base64,' .. tern.base64.encode(table.concat(parts)) .. '"', frames
end

local function statusRule(selector, states, count, moving, name)
	local image, frames = sprite(states, count, moving)
	local images = { "url(" .. image .. ")" }
	local sizes = { string.format("%dpx %dpx", frames * WIDTH, count * LINE) }
	local positions = { "0px 0px" }
	local endpoint = { string.format("-%dpx 0px", FRAMES * WIDTH) }
	for row = 1, count do
		local position = string.format("0px %dpx", (row - 1) * LINE)
		-- Acknowledging a completion must not change the working sprite's animation tracks.
		-- Idle rows keep a transparent layer rather than removing a background-position entry.
		table.insert(images, if states[row] then FADE else "none")
		table.insert(sizes, string.format("%dpx %dpx", WIDTH, LINE))
		table.insert(positions, position)
		table.insert(endpoint, position)
	end
	local animation = if moving then string.format("%s 900ms steps(%d) infinite", name, FRAMES) else "none"
	local rule = selector .. string.format("{height:%dpx;background-image:%s;background-size:%s;background-position:%s;animation:%s;}", count * LINE, table.concat(images, ","), table.concat(sizes, ","), table.concat(positions, ","), animation)
	-- Explicit, fixed-length endpoints keep the timeline independent of alert acknowledgement.
	if moving then rule ..= "@keyframes " .. name .. "{from{background-position:" .. table.concat(positions, ",") .. ";}to{background-position:" .. table.concat(endpoint, ",") .. ";}}" end
	return rule
end

local nativeRules = {}
for _, state in { "working", "waiting", "done", "failed", "bell" } do
	local selector = '#sidebar .tn-vt .tn-dk.n1 > .tn-dk-c:not(.out)[data-program="omp"][data-st="' .. state .. '"]::before'
	table.insert(nativeRules, statusRule(selector, { state }, 1, state == "working", "ompSingleStatus" .. state))
end
local NATIVE_RULES = table.concat(nativeRules, "\n")

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
	local rules = { NATIVE_RULES }
	for _, tabId in tabIds do
		local panes = groups[tabId]
		if #panes > 1 then
			local states, selectors = {}, table.create(#panes)
			local active, moving = false, false
			for row, pane in panes do
				states[row] = paneState(pane, agents[pane.pane])
				active = active or states[row] ~= nil
				moving = moving or states[row] == "working"
				-- Native depth classes change with focus. Keep the timeline on every pane node;
				-- CSS reveals only the front one without destroying the others' pseudo-elements.
				selectors[row] = string.format('#sidebar .tn-vt .tn-dk:not(.n1) > .tn-dk-c:not(.out)[data-pane="%.0f"]::before', pane.pane)
			end
			if active then
				table.insert(rules, statusRule(table.concat(selectors, ","), states, #panes, moving, string.format("ompPaneStatusSpin%.0f", tabId)))
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
