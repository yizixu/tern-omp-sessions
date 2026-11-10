local M = {}
local LINE = 24
local WIDTH = 44
local HEADER = 26
local DEFS = '<defs><filter id="icon-shadow" x="-35%" y="-30%" width="170%" height="180%"><feDropShadow dx="0" dy="1" stdDeviation=".7" flood-color="#000" flood-opacity=".3"/></filter></defs>'

local function titleIcon(title)
	if title == "" then return nil end
	local cp = utf8.codepoint(title)
	if (cp >= 0xE000 and cp <= 0xF8FF) or (cp >= 0xF0000 and cp <= 0x10FFFD) then return cp end
	return nil
end

local function tile(pane, paths)
	local plate = '<rect x=".5" y=".5" width="15" height="15" rx="3.2" class="icon-bg icon-surface"/>'
	local cp = titleIcon(pane.title)
	local path = cp and paths[string.format("%X", cp)]
	if type(path) == "string" then
		return plate .. '<path d="' .. path .. '" class="icon-ink"/>'
	end
	if pane.kind == "git" then
		return plate .. '<path d="M5 4v5a3 3 0 0 0 3 3h3M5 6h3a3 3 0 0 0 3-3" fill="none" class="icon-stroke" stroke-width="1.3"/><g class="icon-bg icon-stroke" stroke-width="1.3"><circle cx="5" cy="3" r="1.3"/><circle cx="5" cy="12" r="1.3"/><circle cx="11" cy="3" r="1.3"/></g>'
	elseif pane.kind == "browser" then
		return plate .. '<g fill="none" class="icon-stroke" stroke-width="1.1"><circle cx="8" cy="8" r="5"/><ellipse cx="8" cy="8" rx="2.3" ry="5"/><path d="M3 8h10"/></g>'
	elseif pane.kind == "file" then
		return plate .. '<path d="M5 3h4l3 3v7H5zM9 3v3h3M7 9h3M7 11h3" fill="none" class="icon-stroke" stroke-width="1.1" stroke-linejoin="round"/>'
	end
	return plate .. '<path d="m4 4.5 3 3-3 3m5 0h3" fill="none" class="icon-stroke" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>'
end

function M.background(panes, paths, window, dark)
	local count = #panes
	local width = if count == 1 then 16 else WIDTH
	local height = if count == 1 then 16 else HEADER + count * LINE
	local background, ink = if dark then "#fff" else "#454545", if dark then "#000" else "#fff"
	-- Only the surface reveals the CSS accent shadow; artwork and inset details stay opaque.
	local palette = string.format('<style>.icon-bg{fill:%s}.icon-surface{fill-opacity:.88}.icon-ink{fill:%s}.icon-stroke{stroke:%s}</style>', background, ink, ink)
	local parts = { string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">', width, height), DEFS, palette, window }
	if count > 1 then
		-- The header and pane tree share one image so focus cannot swap the parent art.
		local path = { string.format("M8 %dV%.1f", HEADER, HEADER + (count - 1) * LINE + LINE / 2) }
		for row, pane in panes do
			local y = HEADER + (row - 1) * LINE
			table.insert(path, string.format("M8 %.1fH14", y + LINE / 2))
			table.insert(parts, string.format('<g transform="translate(20 %.1f)" filter="url(#icon-shadow)">', y + (LINE - 16) / 2))
			table.insert(parts, tile(pane, paths))
			table.insert(parts, '</g>')
		end
		table.insert(parts, '<path d="' .. table.concat(path, " ") .. '" fill="none" stroke="#8995a6" stroke-width="1"/>')
	end
	table.insert(parts, '</svg>')
	return '"data:image/svg+xml;base64,' .. tern.base64.encode(table.concat(parts)) .. '"', width, height
end

return M
