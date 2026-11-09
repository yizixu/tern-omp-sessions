local M = {}
local LINE = 24
local WIDTH = 40

local function titleIcon(title)
	if title == "" then return nil end
	local cp = utf8.codepoint(title)
	if (cp >= 0xE000 and cp <= 0xF8FF) or (cp >= 0xF0000 and cp <= 0x10FFFD) then return cp end
	return nil
end

local function tile(pane, paths)
	local cp = titleIcon(pane.title)
	local path = cp and paths[string.format("%X", cp)]
	if type(path) == "string" then
		return '<rect width="16" height="16" rx="3.5" fill="#edf0f5"/><path d="' .. path .. '" fill="#202632"/>'
	end
	if pane.kind == "git" then
		return '<rect width="16" height="16" rx="3.5" fill="#f5764c"/><path d="M5 4v5a3 3 0 0 0 3 3h3M5 6h3a3 3 0 0 0 3-3" fill="none" stroke="white" stroke-width="1.3"/><g fill="#f5764c" stroke="white" stroke-width="1.3"><circle cx="5" cy="3" r="1.3"/><circle cx="5" cy="12" r="1.3"/><circle cx="11" cy="3" r="1.3"/></g>'
	elseif pane.kind == "browser" then
		return '<rect width="16" height="16" rx="3.5" fill="#6779cf"/><g fill="none" stroke="white" stroke-width="1.1"><circle cx="8" cy="8" r="5"/><ellipse cx="8" cy="8" rx="2.3" ry="5"/><path d="M3 8h10"/></g>'
	elseif pane.kind == "file" then
		return '<rect width="16" height="16" rx="3.5" fill="#668bb7"/><path d="M5 3h4l3 3v7H5zM9 3v3h3M7 9h3M7 11h3" fill="none" stroke="white" stroke-width="1.1" stroke-linejoin="round"/>'
	end
	local fill = if pane.kind == "agent" then "#3e8fdb" else "#58687c"
	return '<rect width="16" height="16" rx="3.5" fill="' .. fill .. '"/><path d="m4 4.5 3 3-3 3m5 0h3" fill="none" stroke="white" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>'
end

function M.background(panes, paths)
	local count = #panes
	local parts = { string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', WIDTH, count * LINE) }
	-- The last branch stops at its row centre rather than trailing below the final pane.
	local path = { string.format("M4 0V%.1f", (count - 1) * LINE + LINE / 2) }
	for row, pane in panes do
		local y = (row - 1) * LINE
		table.insert(path, string.format("M4 %.1fH10", y + LINE / 2))
		table.insert(parts, string.format('<g transform="translate(16 %.1f)">', y + (LINE - 16) / 2))
		table.insert(parts, tile(pane, paths))
		table.insert(parts, '</g>')
	end
	table.insert(parts, '<path d="' .. table.concat(path, " ") .. '" fill="none" stroke="#8995a6" stroke-width="1"/>')
	table.insert(parts, '</svg>')
	return '"data:image/svg+xml;base64,' .. tern.base64.encode(table.concat(parts)) .. '"', WIDTH, count * LINE
end

return M
