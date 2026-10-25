-- MapGrid: a small radar showing the server's map squares around you.
--
-- The server files every unit under a 66.67 x 66.67 yd square by its centre, and a hunter trap only
-- finds enemies whose centre is in the trap's own square (or one within a few yards of it). For huge
-- bosses this matters: stand and trap on the same side of the orange lines as the boss.
--
-- Drag the window to move it, drag its bottom-right corner to resize it, and the -/+ button folds
-- away the text under the map. /mapgrid hides or shows it.

-- 66.6667 yd
local SIZE = 533.3333 / 8    
-- CENTER_GRID_CELL_ID (8 cells * 64 grids / 2)      
local CENTER = 256                 
local ZOOM = 40                    
local PX = 200                     
local INFO_H = 36                  
local MIN_PX, MAX_PX = 150, 800

local function cellIndex(v)
    -- Trinity::ComputeCellCoord: int((v - SIZE/2) / SIZE + CENTER + 0.5)
    return math.floor((v - SIZE / 2) / SIZE + CENTER + 0.5)
end

local function cellLow(i)
    return (i - CENTER) * SIZE
end

local function currentBounds()
    local name = GetMapInfo()
    local level = GetCurrentMapDungeonLevel() or 0
    if DungeonUsesTerrainMap() then
        level = level - 1
    end
    local maps = name and MapGridData[name]
    return maps and (maps[level] or maps[0])
end

local function worldPos()
    local mx, my = GetPlayerMapPosition("player")
    if not mx or (mx == 0 and my == 0) then
        return nil
    end
    local b = currentBounds()
    if not b then
        return nil
    end
    return b[4] - my * (b[4] - b[3]), b[2] - mx * (b[2] - b[1])
end

local function newPool(make)
    local pool = { used = 0 }
    function pool:get()
        self.used = self.used + 1
        local t = self[self.used] or make()
        self[self.used] = t
        t:ClearAllPoints()
        t:Show()
        return t
    end
    function pool:reset()
        for i = 1, #self do
            self[i]:Hide()
        end
        self.used = 0
    end
    return pool
end

local radar = CreateFrame("Frame", "MapGridRadar", UIParent)
radar:SetSize(PX, PX + INFO_H)
radar:SetPoint("RIGHT", -60, 60)
radar:SetMovable(true)
radar:SetResizable(true)
radar:EnableMouse(true)
radar:RegisterForDrag("LeftButton")
radar:SetScript("OnDragStart", radar.StartMoving)
radar:SetScript("OnDragStop", radar.StopMovingOrSizing)
radar:SetClampedToScreen(true)

local frameBg = radar:CreateTexture(nil, "BACKGROUND")
frameBg:SetPoint("TOPLEFT", -1, 1)
frameBg:SetPoint("BOTTOMRIGHT", 1, -1)
frameBg:SetTexture(0.3, 0.3, 0.3, 0.6)

local view = CreateFrame("Frame", nil, radar)
view:SetPoint("TOPLEFT")
view:SetPoint("BOTTOMRIGHT", 0, INFO_H)
local viewBg = view:CreateTexture(nil, "BORDER")
viewBg:SetAllPoints()
viewBg:SetTexture(0, 0, 0, 0.55)

local title = radar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("BOTTOMLEFT", view, "TOPLEFT", 2, 2)
title:SetText("MapGrid")

local info = radar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
info:SetPoint("TOPLEFT", view, "BOTTOMLEFT", 3, -4)
info:SetJustifyH("LEFT")

local function save()
    MapGridDB = MapGridDB or {}
    MapGridDB.width, MapGridDB.height = radar:GetSize()
end

local toggle = CreateFrame("Button", nil, radar)
toggle:SetSize(14, 14)
toggle:SetPoint("BOTTOMRIGHT", view, "TOPRIGHT", 0, 1)
toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")

local collapsed = false
local function setCollapsed(c, resize)
    local strip = c and 0 or INFO_H
    if resize and c ~= collapsed then
        local left, top = radar:GetLeft(), radar:GetTop()
        if left then
            radar:ClearAllPoints()
            radar:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        end
        radar:SetHeight(radar:GetHeight() + (c and -INFO_H or INFO_H))
    end
    collapsed = c
    radar:SetMinResize(MIN_PX, MIN_PX + strip)
    radar:SetMaxResize(MAX_PX, MAX_PX + strip)
    view:SetPoint("BOTTOMRIGHT", 0, strip)
    if c then
        info:Hide()
        toggle:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
        toggle:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    else
        info:Show()
        toggle:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
        toggle:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
    end
end
setCollapsed(false)

toggle:SetScript("OnClick", function()
    setCollapsed(not collapsed, true)
    save()
    MapGridDB.collapsed = collapsed
end)

local grip = CreateFrame("Button", nil, radar)
grip:SetSize(16, 16)
grip:SetPoint("BOTTOMRIGHT", -1, 1)
grip:SetFrameLevel(radar:GetFrameLevel() + 10)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        radar:StartSizing("BOTTOMRIGHT")
    end
end)
grip:SetScript("OnMouseUp", function()
    radar:StopMovingOrSizing()
    save()
end)

radar:RegisterEvent("ADDON_LOADED")
radar:SetScript("OnEvent", function(self, event, name)
    if name ~= "MapGrid" then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")
    if MapGridDB and MapGridDB.width then
        setCollapsed(MapGridDB.collapsed and true or false)
        self:SetSize(MapGridDB.width, MapGridDB.height)
    end
	if MapGridDB and MapGridDB.hidden then
        self:Hide()
    end
end)

local lines = newPool(function() return view:CreateTexture(nil, "ARTWORK") end)
local dots = newPool(function() return view:CreateTexture(nil, "OVERLAY") end)
local labels = newPool(function() return view:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") end)

local function dot(sx, sy, size, r, g, b)
    local t = dots:get()
    t:SetSize(size, size)
    t:SetPoint("CENTER", view, "CENTER", sx, sy)
    t:SetTexture(r, g, b, 1)
end

local function draw(px, py)
    lines:reset()
    dots:reset()
    labels:reset()
    local w, h = view:GetSize()
    local halfW, halfH = w / 2, h / 2
    local scale = math.min(halfW, halfH) / ZOOM   -- pixels per yard
    local rangeX, rangeY = halfH / scale, halfW / scale   -- yards shown north/south and east/west

    -- borders of constant x (north/south) are horizontal lines; north is up
    for i = cellIndex(px - rangeX), cellIndex(px + rangeX) + 1 do
        local sy = (cellLow(i) - px) * scale
        if math.abs(sy) <= halfH then
            local t = lines:get()
            t:SetTexture(1, 0.55, 0.1, 0.9)
            t:SetSize(w, 2)
            t:SetPoint("CENTER", view, "CENTER", 0, sy)
        end
    end
    -- borders of constant y (west/east) are vertical lines; east is right
    for j = cellIndex(py - rangeY), cellIndex(py + rangeY) + 1 do
        local sx = -(cellLow(j) - py) * scale
        if math.abs(sx) <= halfW then
            local t = lines:get()
            t:SetTexture(1, 0.55, 0.1, 0.9)
            t:SetSize(2, h)
            t:SetPoint("CENTER", view, "CENTER", sx, 0)
        end
    end

    for i = cellIndex(px - rangeX), cellIndex(px + rangeX) do
        for j = cellIndex(py - rangeY), cellIndex(py + rangeY) do
            local sx = -(cellLow(j) + SIZE / 2 - py) * scale
            local sy = (cellLow(i) + SIZE / 2 - px) * scale
            local label = labels:get()
            label:SetPoint("CENTER", view, "CENTER",
                math.max(-halfW + 24, math.min(halfW - 24, sx)), math.max(-halfH + 8, math.min(halfH - 8, sy)))
            label:SetText(string.format("|cffffaa33%d,%d|r", i, j))
        end
    end

    local facing = GetPlayerFacing() or 0    -- radians, 0 = north, counter-clockwise
    for k = 1, 4 do
        dot(-math.sin(facing) * (4 + k * 3), math.cos(facing) * (4 + k * 3), 2, 1, 1, 0.3)
    end
    dot(0, 0, 6, 1, 1, 0.3)

    local cx, cy = cellIndex(px), cellIndex(py)
    local loX, loY = cellLow(cx), cellLow(cy)
    local nearest, side = loX + SIZE - px, "north"
    for name, d in pairs({ south = px - loX, west = loY + SIZE - py, east = py - loY }) do
        if d < nearest then
            nearest, side = d, name
        end
    end
    info:SetText(string.format("Square %d,%d\nNearest border: %.1f yd %s", cx, cy, nearest, side))
end

local elapsed, sinceReset = 0, 0
radar:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < 0.1 then
        return
    end
    sinceReset = sinceReset + elapsed
    elapsed = 0
    local px, py = worldPos()
    if px then
        draw(px, py)
        return
    end
    lines:reset()
    dots:reset()
    labels:reset()
    local mx, my = GetPlayerMapPosition("player")
    if mx == 0 and my == 0 then
        -- the map API points at another zone (the world map is open elsewhere) re-point it now and then
        if sinceReset > 2 and not WorldMapFrame:IsShown() then
            SetMapToCurrentZone()
            sinceReset = 0
        end
        info:SetText("Position unknown\n(close the world map)")
    else
        info:SetText("No map data for this zone")
    end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED")
events:RegisterEvent("ZONE_CHANGED_INDOORS")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function()
    if not WorldMapFrame:IsShown() then
        SetMapToCurrentZone()
    end
end)
WorldMapFrame:HookScript("OnHide", function() SetMapToCurrentZone() end)

SLASH_MAPGRID1 = "/mapgrid"
SlashCmdList.MAPGRID = function()
    if radar:IsShown() then radar:Hide() else radar:Show() end
    MapGridDB = MapGridDB or {}
    MapGridDB.hidden = not radar:IsShown()
end

