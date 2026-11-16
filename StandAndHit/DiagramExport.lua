local _, SH = ...
local Export = {}
SH.DiagramExport = Export

local function clean(value)
    return (tostring(value or ""):gsub("[%z\1-\8\11\12\14-\31]", ""):gsub("\r", ""))
end

local function xml(value)
    return (clean(value):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub('"', "&quot;"):gsub("'", "&apos;"):gsub("|", "&#124;"))
end

local function characters(value)
    local result = {}
    for char in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do result[#result + 1] = char end
    return result
end

local function wrap(value, width)
    local lines, columns = {}, math.max(5, math.floor(width / 7.3))
    for paragraph in (clean(value) .. "\n"):gmatch("(.-)\n") do
        local line, count = "", 0
        for word in paragraph:gmatch("%S+") do
            local chars = characters(word)
            if count > 0 and count + 1 + #chars > columns then
                lines[#lines + 1], line, count = line, "", 0
            end
            if count > 0 then line, count = line .. " ", count + 1 end
            for _, char in ipairs(chars) do
                if count == columns then lines[#lines + 1], line, count = line, "", 0 end
                line, count = line .. char, count + 1
            end
        end
        lines[#lines + 1] = line
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

local function number(value) return string.format("%.2f", tonumber(value) or 0) end
local function color(rgb)
    return string.format("#%02x%02x%02x", math.floor(rgb[1] * 255 + 0.5), math.floor(rgb[2] * 255 + 0.5), math.floor(rgb[3] * 255 + 0.5))
end

local function textLines(out, lines, x, y, fill, size, step)
    out[#out + 1] = '<text x="' .. number(x) .. '" y="' .. number(y) .. '" fill="' .. fill
        .. '" font-family="monospace" font-size="' .. (size or 12) .. '">'
    for index, line in ipairs(lines) do
        out[#out + 1] = '<tspan x="' .. number(x) .. '" y="' .. number(y + (index - 1) * (step or 15)) .. '">' .. xml(line) .. '</tspan>'
    end
    out[#out + 1] = '</text>'
end

function Export.ToSVG(graph, title)
    if type(graph) ~= "table" or not SH.DiagramUI then return nil, "The diagram is unavailable." end
    local sizes, labels = {}, {}
    for _, node in ipairs(graph.nodes or {}) do
        local width = SH.DiagramUI.NodeWidth(node)
        local heading, body = wrap(node.title, width - 20), wrap(node.text, width - 20)
        local hasBody = node.text and node.text ~= ""
        local height = math.max(66, 20 + #heading * 16 + (hasBody and 6 + #body * 15 or 0))
        sizes[node.id], labels[node.id] = {w = width, h = height}, {heading = heading, body = hasBody and body or {}}
    end
    local notes = {graph.note or "Current draft. The first matching rule wins."}
    for _, warning in ipairs(graph.warnings or {}) do
        notes[#notes + 1] = (warning.ruleIndex and "Rule " .. warning.ruleIndex .. ": " or "") .. (warning.text or "")
    end
    local summary = wrap(table.concat(notes, "\n"), 740)
    local positions, width, height = SH.DiagramUI.Layout(graph, sizes, #summary * 15 + 28)
    local edges = {}
    for _, edge in ipairs(graph.edges or {}) do
        if positions[edge.from] and positions[edge.to] then
            local route = SH.DiagramUI.Route(edge, positions[edge.from], positions[edge.to])
            edges[#edges + 1] = route
            width = math.max(width, route.extentX or 0)
        end
    end
    width, height = math.ceil(math.max(780, width + 12)), math.ceil(height + 72)
    local out = {'<?xml version="1.0" encoding="UTF-8"?>',
        '<svg xmlns="http://www.w3.org/2000/svg" width="' .. width .. '" height="' .. height
            .. '" viewBox="0 0 ' .. width .. ' ' .. height .. '">',
        '<title>' .. xml(title or "Stand and Hit rotation diagram") .. '</title>',
        '<desc>The complete rotation draft, including every rule and condition.</desc>',
        '<rect x="0" y="0" width="' .. width .. '" height="' .. height .. '" fill="#091015"/>'}
    textLines(out, wrap(title or "Stand and Hit rotation diagram", width - 40), 18, 28, "#84deed", 16, 20)
    out[#out + 1] = '<g transform="translate(0 54)">'
    textLines(out, summary, 18, 16, "#d7dedf", 12, 15)
    for _, route in ipairs(edges) do
        local stroke = route.flow and "#ba9c52" or "#47a6b8"
        for _, part in ipairs(route.segments) do
            out[#out + 1] = '<line x1="' .. number(part.x1) .. '" y1="' .. number(part.y1)
                .. '" x2="' .. number(part.x2) .. '" y2="' .. number(part.y2) .. '" stroke="' .. stroke .. '" stroke-width="2"/>'
        end
        if route.caption.text ~= "" then textLines(out, {route.caption.text}, route.caption.x, route.caption.y + 11, "#d1d4bd", 11, 14) end
        textLines(out, {route.arrow.text}, route.arrow.x, route.arrow.y + 11, "#8fd4e0", 12, 15)
    end
    for _, node in ipairs(graph.nodes or {}) do
        local p, label = positions[node.id], labels[node.id]
        if p then
            out[#out + 1] = '<rect x="' .. number(p.x) .. '" y="' .. number(p.y) .. '" width="' .. number(p.w)
                .. '" height="' .. number(p.h) .. '" fill="' .. color(SH.DiagramUI.NodeColor(node.kind)) .. '" stroke="#527d8a" stroke-width="1"/>'
            textLines(out, label.heading, p.x + 10, p.y + 21, "#84deed", 12, 16)
            textLines(out, label.body, p.x + 10, p.y + 21 + #label.heading * 16 + 6, "#e1e5e6", 12, 15)
        end
    end
    out[#out + 1] = '</g></svg>'
    return table.concat(out, "\n"), width, height
end
