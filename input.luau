-- UTF-8 byte offsets internally; native input offsets are UTF-16 code units.
local M = {}
local function boundaries(text)
	local points = { { byte = 0, units = 0 } }
	local units = 0
	for byte, code in utf8.codes(text) do
		units += if code > 0xFFFF then 2 else 1
		table.insert(points, { byte = (utf8.offset(text, 2, byte) or (#text + 1)) - 1, units = units })
	end
	return points
end
local function indexAt(points, byte)
	local found = 1
	for i, point in points do if point.byte > byte then break end; found = i end
	return found
end
function M.new(text)
	text = tostring(text or "")
	return { text = text, cursor = #text, anchor = nil }
end
function M.clear(field)
	field.text, field.cursor, field.anchor = "", 0, nil
end
function M.view(field)
	local points = boundaries(field.text)
	return tern.ui.node("input", {
		key = "search", role = "omp.search", aria = "Search session titles, project paths, IDs, and first messages",
		text = field.text, cursor = points[indexAt(points, field.cursor)].units,
		anchor = if field.anchor then points[indexAt(points, field.anchor)].units else nil,
		placeholder = "Search titles, paths, IDs, or first messages…",
	})
end
local function replace(field, text, from, to)
	field.text = string.sub(field.text, 1, from) .. text .. string.sub(field.text, to + 1)
	field.cursor, field.anchor = from + #text, nil
end
function M.key(field, key, cx)
	local points = boundaries(field.text)
	local i = indexAt(points, field.cursor)
	local from, to = math.min(field.cursor, field.anchor or field.cursor), math.max(field.cursor, field.anchor or field.cursor)
	local command, name = key.ctrl or key.meta, string.lower(key.name)
	if command and name == "a" then field.anchor, field.cursor = 0, #field.text
	elseif command and (name == "c" or name == "x") then
		if from ~= to then cx:copy(string.sub(field.text, from + 1, to)); if name == "x" then replace(field, "", from, to) end end
	elseif name == "left" or name == "right" or name == "home" or name == "end" then
		local target
		if name == "left" then target = if from ~= to and not key.shift then from else points[math.max(1, i - 1)].byte
		elseif name == "right" then target = if from ~= to and not key.shift then to else points[math.min(#points, i + 1)].byte
		elseif name == "home" then target = 0 else target = #field.text end
		if key.shift then field.anchor = field.anchor or field.cursor else field.anchor = nil end
		field.cursor = target
	elseif name == "backspace" or name == "delete" then
		if from == to then
			if name == "backspace" then from = points[math.max(1, i - 1)].byte else to = points[math.min(#points, i + 1)].byte end
		end
		replace(field, "", from, to)
	elseif key.text and (not command or name == "paste") and not key.alt then
		local text = string.gsub(key.text, "[\r\n]", " ")
		if utf8.len(text) then replace(field, text, from, to) end
	else return false end
	return true
end
function M.edit(field, ev)
	local points = boundaries(field.text)
	if ev.len ~= points[#points].units then return false end
	local function byteAt(units)
		local result = 0
		for _, point in points do if point.units > units then break end; result = point.byte end
		return result
	end
	local text = string.gsub(tostring(ev.text or ""), "[\r\n]", " ")
	if not utf8.len(text) then return false end
	replace(field, text, byteAt(ev.from or 0), byteAt(ev.to or 0))
	return true
end
return M
