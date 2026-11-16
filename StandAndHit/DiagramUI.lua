local _, SH = ...
local DiagramUI = {}
SH.DiagramUI = DiagramUI

local colors = {
    condition = {0.12, 0.24, 0.29}, ["and"] = {0.13, 0.32, 0.25},
    ["or"] = {0.26, 0.22, 0.36}, ["not"] = {0.37, 0.20, 0.16},
    action = {0.25, 0.28, 0.12}, check = {0.13, 0.29, 0.34},
    disabled = {0.16, 0.17, 0.18}, warning = {0.37, 0.19, 0.10},
    start = {0.11, 0.25, 0.22}, ["end"] = {0.19, 0.21, 0.23},
    global = {0.27, 0.21, 0.14}, note = {0.13, 0.17, 0.21},
}
local function text(value) return (tostring(value or ""):gsub("|", "||")) end
local function label(parent, font)
    local item = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    item:SetJustifyH("LEFT"); item:SetJustifyV("TOP"); item:SetWordWrap(true)
    return item
end
local function backdrop(frame, color)
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    frame:SetBackdropColor(color[1], color[2], color[3], 1)
    frame:SetBackdropBorderColor(0.32, 0.49, 0.54, 1)
end
local function isGate(node) return node.kind == "and" or node.kind == "or" or node.kind == "not" end
local function nodeWidth(node)
    if isGate(node) then return 84 end
    if node.kind == "check" or node.kind == "disabled" then return 156 end
    if node.kind == "action" or node.kind == "end" then return 195 end
    return 236
end
local function acquireNode(view, index, node, editor)
    local button = view.nodePool[index]
    if not button then
        button = CreateFrame("Button", nil, view.content, "BackdropTemplate")
        button.title, button.body = label(button, "GameFontNormal"), label(button)
        button.title:SetPoint("TOPLEFT", 10, -9)
        button.title:SetTextColor(0.52, 0.87, 0.93)
        button.body:SetPoint("TOPLEFT", button.title, "BOTTOMLEFT", 0, -6)
        button:SetScript("OnClick", function(self)
            if self.node and self.node.editable and view.onSelect then view.onSelect(self.node) end
        end)
        button:SetScript("OnEnter", function(self)
            if not self.node or not GameTooltip or not GameTooltip.SetOwner then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(text(self.node.title))
            if self.node.text and self.node.text ~= "" then GameTooltip:AddLine(text(self.node.text), 1, 1, 1, true) end
            if self.node.editable and view.onSelect then GameTooltip:AddLine("Click to edit this block.", 0.5, 0.9, 0.8, true) end
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        view.nodePool[index] = button
    end
    local width = nodeWidth(node)
    local expanded = editor and editor.nodeID == node.id
    if expanded then width = math.max(width, (tonumber(editor.width) or 0) + 20) end
    button.node = node
    button.title:SetWidth(width - 20); button.body:SetWidth(width - 20)
    button.title:SetText(text(node.title))
    button.body:SetText(text(node.text))
    local height = math.max(isGate(node) and 48 or 66,
        button.title:GetStringHeight() + (node.text and node.text ~= "" and button.body:GetStringHeight() + 6 or 0) + 20)
    button.editorTop = expanded and height or nil
    if expanded then height = height + math.max(0, tonumber(editor.height) or 0) + 10 end
    button:SetSize(width, height)
    backdrop(button, colors[node.kind] or colors.condition)
    button:EnableMouse(node.editable == true and view.onSelect ~= nil)
    button:Show()
    return button, width, height
end

local function layoutGroup(graph, group, byID, sizes)
    local included, rank, visiting = {}, {}, {}
    for _, id in ipairs(group.nodeIDs or {}) do included[id] = true end
    local function level(id)
        if rank[id] then return rank[id] end
        if visiting[id] then return 0 end
        visiting[id] = true
        local value = 0
        for _, child in ipairs(byID[id] and byID[id].inputs or {}) do
            if included[child] then value = math.max(value, level(child) + 1) end
        end
        visiting[id], rank[id] = nil, value
        return value
    end
    local widths, maximum = {}, 0
    for _, id in ipairs(group.nodeIDs or {}) do
        if byID[id] then
            local col = level(id)
            widths[col] = math.max(widths[col] or 0, sizes[id].w)
            maximum = math.max(maximum, col)
        end
    end
    local xs, total = {}, 0
    for col = 0, maximum do xs[col], total = total, total + (widths[col] or 84) + 38 end
    local points, bottoms, height = {}, {}, 0
    local function place(id)
        if points[id] then return points[id] end
        local node, size = byID[id], sizes[id]
        if not node or not size then return nil end
        local centers = {}
        for _, child in ipairs(node.inputs or {}) do
            if included[child] then local point = place(child); if point then centers[#centers + 1] = point.y + point.h / 2 end end
        end
        local col, y = rank[id], 0
        if #centers > 0 then y = (centers[1] + centers[#centers]) / 2 - size.h / 2 end
        y = math.max(0, y, bottoms[col] or 0)
        local point = {x = xs[col], y = y, w = size.w, h = size.h}
        points[id], bottoms[col] = point, y + size.h + 28
        height = math.max(height, y + size.h)
        return point
    end
    for _, id in ipairs(group.nodeIDs or {}) do place(id) end
    return points, total - 38, height
end

local function position(view, graph, byID, sizes)
    local placed, width, y = {}, 0, view.summaryHeight or 18
    local sections = graph.sections
    if graph.mode ~= "rotation" or type(sections) ~= "table" then
        local ids = {}; for _, node in ipairs(graph.nodes or {}) do ids[#ids + 1] = node.id end
        local points, w, h = layoutGroup(graph, {nodeIDs = ids}, byID, sizes)
        for id, p in pairs(points) do p.x, p.y = p.x + 18, p.y + y; placed[id] = p end
        return placed, w + 36, h + y + 18
    end
    local members, layouts, commonCheckX = {}, {}, 0
    for _, section in ipairs(sections) do
        for _, id in ipairs(section.nodeIDs or {}) do members[id] = true end
        local points, w, h = layoutGroup(graph, section, byID, sizes)
        layouts[#layouts + 1] = {points = points, width = w, height = h, section = section}
        local p = points[section.checkID]
        if p then commonCheckX = math.max(commonCheckX, p.x) end
    end
    local tails = {}
    for _, node in ipairs(graph.nodes or {}) do
        if not members[node.id] then
            if node.kind == "end" then tails[#tails + 1] = node
            else
                local s = sizes[node.id]
                placed[node.id] = {x = 18, y = y, w = s.w, h = s.h}
                y, width = y + s.h + 36, math.max(width, s.w + 36)
            end
        end
    end
    for _, item in ipairs(layouts) do
        local check = item.points[item.section.checkID]
        if check then
            check.x = commonCheckX
            local action = item.points[item.section.actionID]
            if action then action.x, action.y = commonCheckX + check.w + 56, check.y end
        end
        local sectionHeight = item.height
        for id, point in pairs(item.points) do
            local p = {x = point.x + 18, y = point.y + y, w = point.w, h = point.h}
            placed[id] = p
            width, sectionHeight = math.max(width, p.x + p.w + 36), math.max(sectionHeight, point.y + point.h)
        end
        y = y + sectionHeight + 78
    end
    local terminalHeight = 0
    for _, node in ipairs(tails) do
        local s = sizes[node.id]
        local x, top = commonCheckX + 18, y
        if node.id == graph.endID then x = x + 212 end
        if node.id == "channel-hold" and placed.channels then
            x, top = placed.channels.x + placed.channels.w + 140, placed.channels.y
        else terminalHeight = math.max(terminalHeight, s.h) end
        placed[node.id] = {x = x, y = top, w = s.w, h = s.h}
        width = math.max(width, x + s.w + 36)
    end
    y = y + terminalHeight + 38
    return placed, width, y + 18
end

local function segment(edge, index, x1, y1, x2, y2)
    edge.segments = edge.segments or {}
    edge.segments[index] = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
    local piece = edge.pieces[index]
    if not piece then
        piece = edge.owner:CreateTexture(nil, "BACKGROUND")
        edge.pieces[index] = piece
    end
    piece:ClearAllPoints()
    piece:SetPoint("TOPLEFT", math.min(x1, x2), -math.min(y1, y2))
    piece:SetSize(math.max(2, math.abs(x2 - x1)), math.max(2, math.abs(y2 - y1)))
    if edge.flow then piece:SetColorTexture(0.73, 0.61, 0.32, 0.9)
    else piece:SetColorTexture(0.28, 0.65, 0.72, 0.9) end
    piece:Show()
end
local function acquireEdge(view, index, data, a, b)
    local edge = view.edgePool[index]
    if not edge then
        edge = {owner = view.content, pieces = {}, caption = label(view.content), arrow = label(view.content, "GameFontNormal")}
        edge.caption:SetTextColor(0.82, 0.83, 0.74)
        edge.arrow:SetTextColor(0.56, 0.83, 0.88)
        view.edgePool[index] = edge
    end
    edge.data, edge.flow = data, data.kind == "flow"
    edge.segments = {}
    edge.extentX = nil
    for _, piece in ipairs(edge.pieces) do piece:Hide() end
    local x1, y1, x2, y2 = a.x + a.w, a.y + a.h / 2, b.x, b.y + b.h / 2
    local selectedReturn = edge.flow and data.label == "Selected"
    local continuation = edge.flow and data.label == "Continue on this press"
    local firstRule = edge.flow and ((data.from == "channels" and data.label == "No") or data.from == "start" and data.to ~= "channels")
    local vertical = edge.flow and not selectedReturn and b.y >= a.y + a.h and math.abs(a.x - b.x) < 4
    local labelX, labelY
    edge.arrow:ClearAllPoints()
    if continuation then
        x2, y2 = b.x + b.w / 2, b.y
        local route, bridge = math.max(a.x + a.w, b.x + b.w) + 58, b.y - 18
        segment(edge, 1, x1, y1, route, y1)
        segment(edge, 2, route, y1, route, bridge)
        segment(edge, 3, route, bridge, x2, bridge)
        segment(edge, 4, x2, bridge, x2, y2 - 4)
        edge.extentX = route + 18
        labelX, labelY = x2 + 8, bridge - 17
        edge.arrow:SetText("v"); edge.arrow:SetPoint("TOPLEFT", x2 - 3, -y2 + 13)
    elseif firstRule then
        x1, y1, x2, y2 = a.x + a.w / 2, a.y + a.h, b.x + b.w / 2, b.y
        local bridge = y1 + 18
        segment(edge, 1, x1, y1, x1, bridge)
        segment(edge, 2, x1, bridge, x2, bridge)
        segment(edge, 3, x2, bridge, x2, y2 - 4)
        labelX, labelY = x1 + 7, y1 + 1
        edge.arrow:SetText("v"); edge.arrow:SetPoint("TOPLEFT", x2 - 3, -y2 + 13)
    elseif selectedReturn then
        x2 = b.x + b.w
        local route = math.max(x1, x2) + 24
        segment(edge, 1, x1, y1, route, y1)
        segment(edge, 2, route, y1, route, y2)
        segment(edge, 3, route, y2, x2 + 5, y2)
        labelX, labelY = x1 - 53, y1 - 17
        edge.arrow:SetText("<"); edge.arrow:SetPoint("TOPLEFT", x2 + 1, -y2 + 7)
    elseif vertical then
        x1, y1, x2, y2 = a.x + a.w / 2, a.y + a.h, b.x + b.w / 2, b.y
        segment(edge, 1, x1, y1, x1, y2 - 9)
        segment(edge, 2, x1, y2 - 9, x2, y2 - 9)
        segment(edge, 3, x2, y2 - 9, x2, y2 - 4)
        labelX, labelY = x1 + 7, y1 + 8
        edge.arrow:SetText("v"); edge.arrow:SetPoint("TOPLEFT", x2 - 3, -y2 + 13)
    else
        local mid = x2 > x1 and (x1 + x2) / 2 or math.max(x1, x2 + b.w) + 18
        segment(edge, 1, x1, y1, mid, y1)
        segment(edge, 2, mid, y1, mid, y2)
        segment(edge, 3, mid, y2, x2 - 4, y2)
        labelX, labelY = math.min(x1, x2) + 4, math.min(y1, y2) - 17
        edge.arrow:SetText("> "); edge.arrow:SetPoint("TOPLEFT", x2 - 9, -y2 + 7)
    end
    edge.caption:ClearAllPoints(); edge.caption:SetPoint("TOPLEFT", labelX, -labelY)
    edge.caption:SetWidth(154); edge.caption:SetText(data.label == "Conditions" and "" or text(data.label)); edge.caption:Show(); edge.arrow:Show()
    edge.geometry = {x1 = x1, y1 = y1, x2 = x2, y2 = y2}
    return edge
end

-- The image exporter uses the same layout and wire routing with measured static text.
function DiagramUI.Layout(graph, sizes, summaryHeight)
    local byID = {}
    for _, node in ipairs(graph.nodes or {}) do byID[node.id] = node end
    return position({summaryHeight = summaryHeight}, graph, byID, sizes)
end

function DiagramUI.NodeColor(kind) return colors[kind] or colors.condition end
function DiagramUI.NodeWidth(node) return nodeWidth(node) end

function DiagramUI.Route(data, a, b)
    -- Only records geometry; it does not create frames or read the game state.
    local function item()
        return {ClearAllPoints = function() end, SetSize = function() end,
            SetColorTexture = function() end, SetTextColor = function() end,
            SetJustifyH = function() end, SetJustifyV = function() end,
            SetWordWrap = function() end, SetWidth = function() end,
            Hide = function() end, Show = function() end,
            SetPoint = function(self, _, x, y) self.x, self.y = x, -y end,
            SetText = function(self, value) self.text = value end}
    end
    local owner = {CreateTexture = item, CreateFontString = item}
    return acquireEdge({content = owner, edgePool = {}}, 1, data, a, b)
end

function DiagramUI.Create(parent, width, height)
    local view = CreateFrame("Frame", nil, parent)
    view:SetSize(width or 710, height or 480)
    view.nodePool, view.edgePool, view.nodes, view.edges = {}, {}, {}, {}
    view.scroll = CreateFrame("ScrollFrame", nil, view, "UIPanelScrollFrameTemplate")
    view.scroll:SetSize(math.max(1, (width or 710) - 25), math.max(1, (height or 480) - 34))
    view.scroll:SetPoint("TOPLEFT", 0, 0); view.scroll:SetPoint("BOTTOMRIGHT", -25, 34)
    view.content = CreateFrame("Frame", nil, view.scroll)
    view.content:SetSize(1, 1); view.scroll:SetScrollChild(view.content)
    view.summary = label(view.content)
    view.summary:SetPoint("TOPLEFT", 18, -8)
    view.horizontal = CreateFrame("Slider", nil, view, "BackdropTemplate")
    view.horizontal:SetPoint("BOTTOMLEFT", 2, 19); view.horizontal:SetPoint("BOTTOMRIGHT", -27, 19)
    view.horizontal:SetHeight(13); view.horizontal:SetOrientation("HORIZONTAL")
    view.horizontal:SetMinMaxValues(0, 0); view.horizontal:SetValueStep(1); view.horizontal:SetValue(0)
    view.horizontal:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    if type(view.horizontal.GetThumbTexture) == "function" then
        local thumb = view.horizontal:GetThumbTexture()
        if thumb then thumb:SetSize(16, 16) end
    end
    backdrop(view.horizontal, {0.07, 0.09, 0.11})
    view.horizontal:SetScript("OnValueChanged", function(_, value) view.scroll:SetHorizontalScroll(value) end)
    view.hint = label(view)
    view.hint:SetPoint("BOTTOMLEFT", 2, 0); view.hint:SetWidth((width or 710) - 30)
    view.hint:SetText("Draft diagram. Scroll down; hold Shift and scroll to move sideways.")
    view:SetScript("OnSizeChanged", function(self, w, h)
        self.scroll:SetSize(math.max(1, w - 25), math.max(1, h - 34))
        self.hint:SetWidth(math.max(1, w - 30))
    end)
    view.scroll:EnableMouseWheel(true)
    view.scroll:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown and IsShiftKeyDown() then
            view.horizontal:SetValue(math.max(0, math.min(view.maxHorizontal or 0, (self:GetHorizontalScroll() or 0) - delta * 60)))
        else
            local maximum = math.max(0, view.content:GetHeight() - self:GetHeight())
            local value = math.max(0, math.min(maximum, self:GetVerticalScroll() - delta * 70))
            self:SetVerticalScroll(value)
            if self.ScrollBar then self.ScrollBar:SetValue(value) end
        end
    end)
    function view:ClearEditor()
        local previous = self.editorSpec
        self.editorSpec, self.editorNodeID, self.editorKey, self.editorNode = nil, nil, nil, nil
        if previous and type(previous.unmount) == "function" then previous.unmount(self.editorHost) end
        if self.editorHost then self.editorHost:Hide() end
    end
    view:SetScript("OnHide", function(self) self:ClearEditor() end)
    function view:Render(graph, onSelect, editorSpec)
        self.graph, self.onSelect = graph, onSelect
        self.nodes, self.edges = {}, {}
        local requested
        for _, node in ipairs(graph and graph.nodes or {}) do
            if editorSpec and node.id == editorSpec.nodeID then requested = node; break end
        end
        if not requested then editorSpec = nil end
        local changed = self.editorNodeID ~= (editorSpec and editorSpec.nodeID)
            or self.editorKey ~= (editorSpec and editorSpec.key)
        if changed then self:ClearEditor() end
        local notes = {graph and graph.note or ""}
        for _, item in ipairs(graph and graph.warnings or {}) do
            notes[#notes + 1] = (item.ruleIndex and ("Rule " .. item.ruleIndex .. ": ") or "") .. tostring(item.text or "")
        end
        self.summary:SetWidth(math.max(236, math.min(760, self:GetWidth() - 65)))
        self.summary:SetText(text(table.concat(notes, "\n")))
        self.summaryHeight = self.summary:GetStringHeight() + 28
        local byID, sizes, editorButton = {}, {}, nil
        for index, node in ipairs(graph and graph.nodes or {}) do
            local button, w, h = acquireNode(self, index, node, editorSpec)
            self.nodes[index], byID[node.id], sizes[node.id] = button, node, {w = w, h = h}
            if editorSpec and node.id == editorSpec.nodeID then editorButton = button end
        end
        if editorButton then
            local host = self.editorHost
            if not host then host = CreateFrame("Frame", nil, self.content); self.editorHost = host end
            host:SetFrameLevel(editorButton:GetFrameLevel() + 2)
            host:ClearAllPoints(); host:SetPoint("TOPLEFT", editorButton, "TOPLEFT", 10, -editorButton.editorTop)
            host:SetSize(math.max(1, tonumber(editorSpec.width) or 1), math.max(1, tonumber(editorSpec.height) or 1))
            self.editorSpec, self.editorNodeID, self.editorKey, self.editorNode = editorSpec, editorSpec.nodeID, editorSpec.key, requested
            host:Show()
            if changed and type(editorSpec.mount) == "function" then editorSpec.mount(host, requested)
            elseif type(editorSpec.refresh) == "function" then editorSpec.refresh(host, requested) end
        end
        for i = #self.nodes + 1, #self.nodePool do self.nodePool[i]:Hide(); self.nodePool[i].node = nil end
        local positions, w, h = position(self, graph or {}, byID, sizes)
        self.positions = positions
        for _, button in ipairs(self.nodes) do
            local p = positions[button.node.id]
            if p then button:ClearAllPoints(); button:SetPoint("TOPLEFT", p.x, -p.y) else button:Hide() end
        end
        for _, edge in ipairs(graph and graph.edges or {}) do
            local a, b = positions[edge.from], positions[edge.to]
            if a and b then
                local drawn = acquireEdge(self, #self.edges + 1, edge, a, b)
                self.edges[#self.edges + 1] = drawn
                w = math.max(w, drawn.extentX or 0)
            end
        end
        for i = #self.edges + 1, #self.edgePool do
            local edge = self.edgePool[i]
            for _, piece in ipairs(edge.pieces) do piece:Hide() end
            edge.caption:Hide(); edge.arrow:Hide()
        end
        self.content:SetSize(math.max(self:GetWidth() - 25, w), math.max(1, h))
        self.scroll:UpdateScrollChildRect()
        self.maxHorizontal = math.max(0, w - (self:GetWidth() - 25))
        self.horizontal:SetMinMaxValues(0, self.maxHorizontal)
        self.horizontal:SetValue(math.min(self.maxHorizontal, self.scroll:GetHorizontalScroll() or 0))
        self.horizontal:SetShown(self.maxHorizontal > 0)
        local offset = math.min(self.scroll:GetVerticalScroll(), math.max(0, h - self.scroll:GetHeight()))
        self.scroll:SetVerticalScroll(offset)
        if self.scroll.ScrollBar then self.scroll.ScrollBar:SetValue(offset) end
    end
    return view
end
