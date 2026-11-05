-- Blizzard's modern nameplate stretches its health bar border art around the bar with fixed offsets
-- (Blizzard_NamePlateUnitFrame.lua UpdateAnchors: bgTexture BOTTOMRIGHT 6, -6). After rounding to whole
-- screen pixels the bar's fill pokes one pixel past the border's bottom edge. Move that edge down one
-- physical pixel. Only the decorative border art is moved, never the health bar itself.
local BORDER_ATLAS = "UI-HUD-CoolDownManager-Bar-BG"
local BOTTOM_X, BOTTOM_Y = 6, -6 -- Blizzard's own BOTTOMRIGHT offsets for the border

local function FixBorder(unitFrame)
    local container = unitFrame.HealthBarsContainer
    local healthBar = container and container.healthBar
    local border = healthBar and healthBar.bgTexture
    -- the classic nameplate style uses different art and anchoring: leave it alone
    if not border or border:GetAtlas() ~= BORDER_ATLAS then return end
    local pixel = PixelUtil.GetPixelToUIUnitFactor() / border:GetEffectiveScale()
    border:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", BOTTOM_X, BOTTOM_Y - pixel)
end

-- Blizzard re-anchors the border whenever the nameplate's layout is rebuilt, so redo it after each time.
local hooked = {}

local function Hook(unitFrame)
    if hooked[unitFrame] or not unitFrame.UpdateAnchors then return end
    hooked[unitFrame] = true
    hooksecurefunc(unitFrame, "UpdateAnchors", FixBorder)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("UI_SCALE_CHANGED")
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        local unitFrame = plate and plate.UnitFrame
        if not unitFrame then return end
        Hook(unitFrame)
        FixBorder(unitFrame)
    else
        -- one pixel is a different number of UI units at the new scale
        for unitFrame in pairs(hooked) do FixBorder(unitFrame) end
    end
end)
