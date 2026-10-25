-- shows your facing in radians, coloured by how good it is for traps on 3.3.5a private server cores.
--
-- Green:  within 2 deg of a corner facing (0.393, 1.178, 1.963, 2.749, 3.534, 4.320, 5.105, 5.890).
--         A corner of the trap's square points straight ahead: = farthest reach.
-- Yellow: 2-8 deg away: part of the extra reach.
-- Red:    more than 8 deg away, towards a flat side = shortest reach.

local db

local frame = CreateFrame("Frame", "TrapAngleFrame", UIParent)
frame:SetWidth(110)
frame:SetHeight(34)
frame:SetPoint("CENTER", 0, 200)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end)

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
text:SetPoint("CENTER")

frame:SetScript("OnUpdate", function()
    local o = GetPlayerFacing()
    -- corner facings are 22.5 deg + every 45 deg
    local off = math.abs(math.deg(o) % 45 - 22.5)
    if off <= 2 then
        text:SetTextColor(0.25, 1, 0.25)
    elseif off <= 8 then
        text:SetTextColor(1, 0.82, 0)
    else
        text:SetTextColor(1, 0.25, 0.25)
    end
    text:SetFormattedText("%.3f", o)
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
    TrapAngleDB = TrapAngleDB or {}
    db = TrapAngleDB
    if db.point then
        frame:ClearAllPoints()
        frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    end
    frame:EnableMouse(not db.locked)
    if db.hidden then
        frame:Hide()
    end
end)

SLASH_TRAPANGLE1 = "/trapangle"
SlashCmdList.TRAPANGLE = function(msg)
    msg = string.lower(msg or "")
    if msg:find("unlock") then
        db.locked = false
        frame:EnableMouse(true)
        print("TrapAngle: unlocked, drag to move.")
    elseif msg:find("lock") then
        db.locked = true
        frame:EnableMouse(false)
        print("TrapAngle: locked.")
    else
        db.hidden = frame:IsShown()
        if db.hidden then
            frame:Hide()
        else
            frame:Show()
        end
    end
end
