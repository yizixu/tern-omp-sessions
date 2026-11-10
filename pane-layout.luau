local M = {}
local images = {}

local function render(layout)
	local parts = {
		'<g filter="url(#icon-shadow)"><rect x=".5" y=".5" width="15" height="15" rx="3" class="icon-bg icon-surface"/>',
		'<path d="M2 4h12" class="icon-stroke" stroke-width=".6"/>',
		'<g class="icon-ink">',
	}
	local leaves = {}
	local function visit(node, x, y, width, height)
		if node.pane then
			leaves[node.pane] = { x, y, width, height }
			table.insert(parts, string.format('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx=".4"/>', x + .45, y + .45, math.max(.3, width - .9), math.max(.3, height - .9)))
		elseif node.split == "right" then
			local first = width * node.ratio
			visit(node[1], x, y, first, height)
			visit(node[2], x + first, y, width - first, height)
		else
			local first = height * node.ratio
			visit(node[1], x, y, width, first)
			visit(node[2], x, y + first, width, height - first)
		end
	end
	visit(layout.root, 2, 4.5, 12, 9.5)
	table.insert(parts, '</g>')
	for _, float in layout.floats do
		local owner = leaves[float.over]
		if owner then
			local width, height = owner[3] * .6, owner[4] * .6
			local x = owner[1] + (if string.sub(float.corner, 2) == "r" then owner[3] - width else 0)
			local y = owner[2] + (if string.sub(float.corner, 1, 1) == "b" then owner[4] - height else 0)
			table.insert(parts, string.format('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx=".5" class="icon-bg icon-stroke" stroke-width=".6"/>', x, y, width, height))
		end
	end
	table.insert(parts, '</g>')
	return table.concat(parts)
end

function M.get(cx, tabId)
	local layout = cx.session:layout(tabId)
	if not layout then return nil end
	local image = render(layout)
	images[tabId] = image
	return image
end

function M.start(changed)
	local function watch()
		tern.timer(1000, function(cx)
			if cx then
				local nextImages, dirty = {}, false
				for _, tab in cx.session:tabs() do
					local layout = cx.session:layout(tab.id)
					if layout then
						local image = render(layout)
						nextImages[tab.id] = image
						if image ~= images[tab.id] then dirty = true end
					end
				end
				for tabId in images do if not nextImages[tabId] then dirty = true end end
				images = nextImages
				if dirty then changed() end
			end
			watch()
		end)
	end
	watch()
end

return M
