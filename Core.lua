local addonName, ns = ...

---------------------------------------------------------
--Constants
---------------------------------------------------------
local BAR_COLOR = {0.2, 0.5, 0.2}
local BG_COLOR = {0.1, 0.2, 0.1}
local DEFAULT_WIDTH = 200
local DEFAULT_HEIGHT = 55
local POWER_BAR_HEIGHT = 5
local isTestMode = false
local FERROZ_COLOR = CreateColorFromHexString("ff8FB8DD")
local log = FerrozEditModeLib.Log

---------------------------------------------------------
-- HELPERS
---------------------------------------------------------
local function IsInEditMode()
    if C_EditMode and type(C_EditMode.IsEditModeActive) == "function" then
        return C_EditMode.IsEditModeActive()
    end
    return false
end

local function FindCoTank()
    if isTestMode then return "player" end
    local groupType = IsInRaid() and "raid" or (IsInGroup() and "party")
    if not groupType then return nil end
    
    local count = GetNumGroupMembers()
    for i = 1, count do
        local unit = groupType..i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            if UnitGroupRolesAssigned(unit) == "TANK" then return unit end
        end
    end
    return nil
end

---------------------------------------------------------
-- MIXINS 
---------------------------------------------------------
Co_Tank_Frame_Mixin = {}

-- Add to Co_Tank_Frame_Mixin
function Co_Tank_Frame_Mixin:GetDebuffTypeColor(aura)
    --TODO
    return { r = 0.7, g = 0.7, b = 0.7 }
end

function Co_Tank_Frame_Mixin:UpdateDebuffs()
    local unit = self:GetAttribute("unit")
    local isEditMode = IsInEditMode() or self.isEditing

    for i = 1, #self.debuffs do self.debuffs[i]:SetAlpha(0) end

    if (not unit or not UnitExists(unit)) and not isEditMode then
        return
    end

    if not isEditMode then --actual data
        local idx = 1 -- 1 indexed
        for auraIdx = 1, 40 do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, auraIdx, "HARMFUL")
            if not aura then break end
            if idx > #self.debuffs then break end
            --if  (Co_Tank_Frame_Settings.filterMode== "ALL DEBUFFS" or aura.isBossAura or aura.dispelName)  then
            if (Co_Tank_Frame_Settings.filterMode == "ALL DEBUFFS") or aura.duration  or aura.dispelName then
                local iconFrame = self.debuffs[idx]
                iconFrame.icon:SetTexture(aura.icon)
                iconFrame.count:SetFormattedText("%s", aura.applications)
                if( iconFrame.cd.SetCooldownFromExpirationTime and type(iconFrame.cd.SetCooldownFromExpirationTime) == "function") then
                    iconFrame.cd:SetCooldownFromExpirationTime(aura.expirationTime, aura.duration)
                else
                    iconFrame.cd:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
                end
                local color = self.GetDebuffTypeColor(aura)
                if iconFrame.border and color then
                    iconFrame.border:SetBackdropBorderColor(color.r, color.g, color.b)
                end
                iconFrame:SetAlpha(1)
                idx = idx + 1
            end
        end
    else -- EDIT MODE PREVIEW/mock data
        local previewIcons = {132290, 132090, 135904}
        for i = 1, 3 do
            local iconFrame = self.debuffs[i]
            -- Fix: In 12.0, use the frame itself if .border isn't defined
            local borderFrame = iconFrame.border or iconFrame
            
            iconFrame.icon:SetTexture(previewIcons[i])
            iconFrame.count:SetText(i == 1 and "3" or "")
            
            -- FIX: SetBackdropBorderColor is a BackdropTemplate method
            if borderFrame.SetBackdropBorderColor then
                borderFrame:SetBackdropBorderColor(1, 0, 0, 1) 
            end

            iconFrame.cd:SetCooldown(GetTime(), 30)
            iconFrame.cd:Show()
            iconFrame:SetAlpha(1)
        end
    end
end

function Co_Tank_Frame_Mixin:UpdateHealthText()
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then 
        self.hpText:SetText("")
        return 
    end
    if(not self.isEditing ) then
        self.nameText:SetText(UnitName(unit))
    end
    --clears taint?
    if self.hpText.HasSecretValues and type(self.hpText.HasSecretValues) == "function" and self.hpText:HasSecretValues() then 
        self.hpText:SetToDefaults() 
    end

    -- Direct assignment only. Concatenation (..) is blocked in 12.0.
    local unitHealth
    if(AbbreviateLargeNumbers and type(AbbreviateLargeNumbers) == "function") then
        unitHealth = AbbreviateLargeNumbers(UnitHealth(unit))
    else 
        unitHealth = UnitHealth(unit)
    end
    local ok, unitHealthAsPercent
    if CurveConstants and CurveConstants.ScaleTo100 then
        ok, unitHealthAsPercent  = pcall(UnitHealthPercent, unit,false, CurveConstants.ScaleTo100)
    else
        ok, unitHealthAsPercent  = pcall(UnitHealthPercent, unit,false, true)
    end
    if(ok and unitHealthAsPercent ~= nil and unitHealth ~= nil) then 
        self.hpText:SetFormattedText("%s | %.0f%%", unitHealth, unitHealthAsPercent)
    elseif unitHealth then
        self.hpText:SetText(unitHealth)
    else
        self.hpText:SetText("??")
    end
end

function Co_Tank_Frame_Mixin:UpdateHealthBar()
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    -- 1. Handle Colors first (Non-Secret check)
    local _, class = UnitClass(unit)

    if class then
        local color = RAID_CLASS_COLORS[class]
        if color then
            self.health:SetStatusBarColor(color.r, color.g, color.b)
        end
    else
        self.health:SetStatusBarColor(0.5, 0.5, 0.5) 
    end

    -- 2. Set the Bar Values (These are Secret-Safe)
    self.health:SetMinMaxValues(0, UnitHealthMax(unit))
    self.health:SetValue(UnitHealth(unit))
    
    -- 3. THE FIX: Explicitly call the text update
    self:UpdateHealthText()
end

function Co_Tank_Frame_Mixin:UpdatePower()
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    local powerType, powerToken = UnitPowerType(unit)
    local p, maxP = UnitPower(unit), UnitPowerMax(unit)
    
    self.power:SetMinMaxValues(0, maxP)
    self.power:SetValue(p)

    -- Color the bar based on power type (Mana/Rage/Energy/etc)
    local color = PowerBarColor[powerToken] or PowerBarColor["MANA"]
    self.power:SetStatusBarColor(color.r, color.g, color.b)
end

-- Called when the unit attribute changes (Binding Logic)
function Co_Tank_Frame_Mixin:OnAttributeChanged(name, value)
    if name == "unit" then
        self:UnregisterAllEvents() -- Clear old unit tracking
        local watchUnit = isTestMode and "player" or value
        if watchUnit then
            self:RegisterUnitEvent("UNIT_HEALTH", watchUnit)
            self:RegisterUnitEvent("UNIT_MAXHEALTH", watchUnit)
            self:RegisterUnitEvent("UNIT_POWER_UPDATE", watchUnit)
            self:RegisterUnitEvent("UNIT_MAXPOWER", watchUnit)
            self:RegisterUnitEvent("UNIT_DISPLAYPOWER", watchUnit)
            self:RegisterUnitEvent("UNIT_AURA", watchUnit)
            self:UpdateVisuals()
        else
            if not isTestMode then
                self.nameText:SetText("NO CO-TANK")
            end
            self.health:SetValue(0)
            self.power:SetValue(0)
            for i = 1, #self.debuffs do self.debuffs[i]:SetAlpha(0) end
        end
    end
end

function Co_Tank_Frame_Mixin:UpdateVisuals()
    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    --these all work in editing mode so that it mocks the layout/data
    self:UpdateHealthBar()
    self:UpdatePower()
    self:UpdateDebuffs()

    if self.isEditing then return end

    local name = UnitName(unit)
    if name then
        self.nameText:SetText(name)
    end
end

function Co_Tank_Frame_Mixin:EditModeStartMock()
    if InCombatLockdown() then return end
    -- Stop listening to the real tank while editing
    self:UnregisterAllEvents()
    UnregisterUnitWatch(self)
    self:SetAttribute("unit", "player") 
    self.nameText:SetText("CO-TANK PREVIEW")
    self:UpdateVisuals()
    -- Lock the blue color so real health events don't overwrite it
    self.health:SetStatusBarColor(0.2, 0.2, 1, 1) 
    self.bg:SetColorTexture(0.2, 0.2, 1, 0.5)
    self:Show()
end

function Co_Tank_Frame_Mixin:EditModeStopMock()
    -- Put back the default background color
    self.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    self.health:SetStatusBarColor(0.5, 0.5, 0.5)
    RegisterUnitWatch(self)
    if not InCombatLockdown() then
        local realTank = FindCoTank()
        self:SetAttribute("unit", realTank)
        --Give the 12.0 engine a moment to 'unlock' the tank data
        C_Timer.After(0.1, function()
            self:UpdateVisuals()
        end)
    end
end

---------------------------------------------------------
-- INITIALIZATION
---------------------------------------------------------
local function InitializeCotankFrame()
    -- Initialize settings if they don't exist
    Co_Tank_Frame_Settings = Co_Tank_Frame_Settings or {}
    Co_Tank_Frame_Settings.layouts = Co_Tank_Frame_Settings.layouts or {}
    Co_Tank_Frame_Settings.filterMode = Co_Tank_Frame_Settings.filterMode or "ALL DEBUFFS"

    local frame = CreateFrame("Button", "Co_Tank_Frame", UIParent, "SecureUnitButtonTemplate, BackdropTemplate, EditModeSystemTemplate")

    Mixin(frame, Co_Tank_Frame_Mixin)
    
    -- Visual Setup
    frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    frame:SetBackdrop({edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    frame.health = CreateFrame("StatusBar", nil, frame)
    -- 1. Adjust Health Bar (Stop it 4px from the bottom)
    frame.health:SetPoint("TOPLEFT", 1, -1)
    frame.health:SetPoint("BOTTOMRIGHT", -1, POWER_BAR_HEIGHT + 2) -- Raised by 4px + 1px gap

    -- 2. Create Power Bar
    frame.power = CreateFrame("StatusBar", nil, frame)
    frame.power:SetHeight(POWER_BAR_HEIGHT) -- Thin, modern look
    frame.power:SetPoint("TOPLEFT", frame.health, "BOTTOMLEFT", 0, -1)
    frame.power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.power:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")

    -- 3. Power Background
    frame.powerBG = frame.power:CreateTexture(nil, "BACKGROUND")
    frame.powerBG:SetAllPoints()
    frame.powerBG:SetColorTexture(0, 0, 0, 0.5)

    frame.health:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")

    -- Name Text (Slot 1)
    frame.nameText = frame.health:CreateFontString(nil, "OVERLAY")
    frame.nameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE") 
    frame.nameText:SetPoint("BOTTOMLEFT", frame.health, "LEFT", 6, 4) -- Nudged up
    frame.nameText:SetJustifyH("LEFT")

    -- HP Text (Slot 2)
    frame.hpText = frame.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.hpText:SetPoint("TOPLEFT", frame.health, "LEFT", 6, -4) -- Nudged down
    frame.hpText:SetJustifyH("LEFT")
    frame.hpText:SetTextColor(0.9, 0.9, 0.9)
    frame:EnableMouse(false)
    frame.debuffs = {}
    for i = 1, 5 do
        -- Main Button Frame
        local iconFrame = CreateFrame("Button", nil, frame.health, "BackdropTemplate")
        iconFrame:SetFrameStrata("MEDIUM")
        iconFrame:SetFrameLevel(Co_Tank_Frame:GetFrameLevel() + 5)
        iconFrame:SetMouseClickEnabled(true)
        iconFrame:SetSize(26, 26) 

        --BORDER (Using Backdrop for a perfect 1px line)
        iconFrame:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        iconFrame.border = iconFrame

        -- ICON
        iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
        iconFrame.icon:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 1, -1)
        iconFrame.icon:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
        iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- Zoom in slightly to remove default icon edges
        
        -- COOLDOWN
        iconFrame.cd = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
        iconFrame.cd:SetAllPoints(iconFrame.icon)
        iconFrame.cd:SetReverse(true) -- Darken the spent time, keep remaining time bright
        iconFrame.cd:SetHideCountdownNumbers(false)

        -- STACK COUNT
        iconFrame.count = iconFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        iconFrame.count:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 2, 0)

        -- Tooltip and Positioning logic remains the same...
        iconFrame:EnableMouse(true)
        iconFrame:SetID(i)
        iconFrame:SetScript("OnLeave", function() 
            GameTooltip:Hide()
            if GameTooltip.ClearLines then
                GameTooltip:ClearLines()
            end
        end)
        iconFrame:SetScript("OnEnter", function(self)
            local parent = self:GetParent()
            local theFrame = parent:GetParent()
            local unit = theFrame:GetAttribute("unit")
            local index = self:GetID() 
            if unit and index then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

                GameTooltip:SetUnitAura(unit, index, "HARMFUL")
                GameTooltip:Show()
            end
        end)

        if i == 1 then
            iconFrame:SetPoint("RIGHT", frame.health, "RIGHT", -6, 0)
        else
            iconFrame:SetPoint("RIGHT", frame.debuffs[i-1], "LEFT", -4, 0)
        end

        iconFrame:SetAlpha(0)
        frame.debuffs[i] = iconFrame
    end

    -- Assign Scripts
    frame:SetScript("OnAttributeChanged", frame.OnAttributeChanged)
    frame:SetScript("OnEvent", frame.UpdateVisuals)

    if FerrozEditModeLib then
        FerrozEditModeLib:Register(frame, Co_Tank_Frame_Settings)
    end

    -- External State Controller (Manager)
    local manager = CreateFrame("Frame")
    manager:RegisterEvent("GROUP_ROSTER_UPDATE")
    manager:RegisterEvent("PLAYER_REGEN_ENABLED")
    manager:RegisterEvent("PLAYER_ENTERING_WORLD")
    manager:SetScript("OnEvent", function(self, event)
        if not InCombatLockdown() then
            local currentTank = FindCoTank()
            frame:SetAttribute("unit", currentTank)
            if FerrozEditModeLib then
                FerrozEditModeLib:ApplyLayout(frame)
            end
            frame:UpdateVisuals()
        end
    end)

    -- Initialize cotank
    frame:SetAttribute("unit", FindCoTank())
    RegisterUnitWatch(frame)
    -- Support for Clique and other click-casting addons
    _G["ClickCastFrames"] = _G["ClickCastFrames"] or {}
    _G["ClickCastFrames"][frame] = true

    local version = C_AddOns.GetAddOnMetadata("Co_Tank_Frame", "Version") or "1.0.0"
    print(FERROZ_COLOR:WrapTextInColorCode("[CoTank] v" .. version) .. " loaded (/cotank)")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == "Co_Tank_Frame" then
        InitializeCotankFrame()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

---------------------------------------------------------
-- MAIN SLASH COMMAND
---------------------------------------------------------
SLASH_COTANK1 = "/cotank"
SlashCmdList["COTANK"] = function(msg)
    local cmd, arg = string.split(" ", msg)
    cmd = cmd and cmd:lower() or ""
    if cmd == "reset" then
        Co_Tank_Frame:UpdateVisuals()
        if FerrozEditModeLib and FerrozEditModeLib.ResetPosition then
            FerrozEditModeLib:ResetPosition(Co_Tank_Frame)
        end
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank:").." Settings and position have been reset.")
    elseif cmd == "filter" or cmd == "filtermode" then
        if(Co_Tank_Frame_Settings.filterMode == "ESSENTIAL ONLY") then
            Co_Tank_Frame_Settings.filterMode = "ALL DEBUFFS"
        else
            Co_Tank_Frame_Settings.filterMode = "ESSENTIAL ONLY"
        end
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank:").." Filtermode set to: " .. Co_Tank_Frame_Settings.filterMode)
    elseif cmd == "test" then
        isTestMode = not isTestMode
        local status = isTestMode and GREEN_FONT_COLOR:WrapTextInColorCode("ON") or RED_FONT_COLOR:WrapTextInColorCode("OFF")
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank:").." Test Mode is " .. status)

        if Co_Tank_Frame then            -- If we are testing, we need to bypass UnitWatch hiding the frame
            if isTestMode then
                UnregisterUnitWatch(Co_Tank_Frame)
                Co_Tank_Frame:SetAttribute("unit", "player")
                Co_Tank_Frame:Show()
            else
                local tankUnit = FindCoTank()
                Co_Tank_Frame:SetAttribute("unit", FindCoTank())
                RegisterUnitWatch(Co_Tank_Frame)
            end
            Co_Tank_Frame:UpdateVisuals()
        end
        if Co_Tank_Frame.UpdateDebuffs then Co_Tank_Frame:UpdateDebuffs() end
    else
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank Commands"))
        print("  /cotank reset - Resets frame position")
    end
end