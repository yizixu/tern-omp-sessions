require("./sidebar")

local KIND = "omp-sessions.panel"
local PREFIX = "omp-session://open/"
local runtime = require("./runtime")
local opening = false

local function pathKey(path)
	local normalized = string.gsub(path, "\\", "/")
	return if runtime.windows then string.lower(normalized) else normalized
end

local function quote(value)
	if runtime.windows then
		-- PowerShell also treats typographic single quotes as delimiters.
		value = string.gsub(value, "'", "''")
		value = string.gsub(value, "‘", "‘‘")
		value = string.gsub(value, "’", "’’")
		return "'" .. value .. "'"
	end
	return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

local function openPanel(cx)
	for _, pane in cx.session:panes() do
		if pane.block == KIND or pane.program == KIND then
			if pane.parked then
				local ok, err = cx.layout:unpark(pane.pane)
				if not ok then cx:toast("error", "Could not unpark OMP Sessions", err); return end
			end
			cx.layout:focus(pane.pane)
			return
		end
	end
	if not cx:new_block(KIND, nil, "tab") then
		cx:toast("error", "Could not open OMP Sessions", "The omp-sessions plugin is not loaded on this host")
	end
end

local function activate(target, cx)
	if opening then return end
	opening = true
	local ok, err = pcall(function()
		tern.process.run({ runtime.node, tern.plugin.dir .. "/sessions.mjs", "live", "--tern", runtime.tern }, { timeout_ms = 12000 }, function(result, fresh)
			opening = false
			if result.status ~= 0 then
				fresh:toast("error", "Could not check active sessions. No duplicate was started.", result.stderr)
				return
			end
			local success, failure = pcall(function()
				local snapshot = tern.json.decode(result.stdout)
				for _, row in snapshot.sessions do
					if pathKey(row.path) == pathKey(target.path) and #row.panes > 0 then
						local chosen
						for _, live in row.panes do
							local pane = fresh.session:pane(live.pane)
							if pane and (not chosen or pane.focused) then chosen = pane end
						end
						if not chosen then error("This session is open in another Tern window. No duplicate was started.") end
						if chosen.parked then
							local dealt, why = fresh.layout:unpark(chosen.pane)
							if not dealt then error(why or "Could not unpark the session") end
						end
						fresh.layout:focus(chosen.pane)
						return
					end
				end
				if not tern.fs.exists(target.path) then error("The session file no longer exists. Refresh the panel.") end
				if not tern.fs.exists(target.cwd) then error("The project directory no longer exists. The original session was not moved or modified: " .. target.cwd) end
				local command = (if runtime.windows then "& " else "") .. quote(runtime.omp) .. " --resume " .. quote(target.path)
				if not fresh.layout:new_tab({ cwd = target.cwd, command = command }) then error("Could not open a new tab to resume the session") end
			end)
			if not success then fresh:toast("error", "Could not switch OMP sessions", tostring(failure)) end
		end)
	end)
	if not ok then opening = false; cx:toast("error", "Could not read session state", tostring(err)) end
end

tern.command({ id = "open", title = "Open OMP Sessions", icon = "terminal", group = "OMP", run = openPanel })
tern.bind("ctrl+alt+o", "plugin.omp-sessions.open")

tern.route.link(function(link, cx)
	if string.sub(link.url, 1, #PREFIX) ~= PREFIX then return nil end
	local ok, target = pcall(function()
		return tern.json.decode(tern.base64.decode(string.sub(link.url, #PREFIX + 1)))
	end)
	if not ok or type(target) ~= "table" or type(target.path) ~= "string" or type(target.cwd) ~= "string" then
		cx:toast("error", "Invalid OMP session link")
	else
		activate(target, cx)
	end
	return { handled = true }
end)
