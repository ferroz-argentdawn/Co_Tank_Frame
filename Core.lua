local addonName, ns = ...
---Libraries
local lib = LibStub("FerrozEditModeLib-1.0")
--Constants
local log = lib.Log --log function, handles only printing in debug mode
local UPDATE_THROTTLE = 0.05 -- Roughly 20 updates per second (super smooth)
--general ui
local FERROZ_COLOR = CreateColorFromHexString("ff8FB8DD")
local BACKDROP_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_WIDTH = 200
local DEFAULT_HEIGHT = 55
local POWER_BAR_HEIGHT = 5
local HEALTH_BAR_INTENSITY = 0.7
--private auras
local PRIVATE_AURA_CONTAINER_SIZE = 30
--debuffs
local DEBUFF_ICON_SIZE = 26
local DEBUFF_SPACING = 4
local DEBUFF_MAX_COUNT = 5
local DEBUFF_AURA_FILTER = "HARMFUL"
--defensives
local BIG_DEFENSIVES_MAX_COUNT = 1
local BIG_DEFENSIVE_AURA_FILTER = "BIG_DEFENSIVE"
--filter mode lists
local FILTER_MODES = {
    AURAS = "Private Auras",
    DEBUFFS = "All Debuffs",
    BOTH = "Both Debuffs and Private Auras"
}
local NEXT_FILTER_MODE = {
    [FILTER_MODES.AURAS] = FILTER_MODES.DEBUFFS,
    [FILTER_MODES.DEBUFFS] = FILTER_MODES.BOTH,
    [FILTER_MODES.BOTH] = FILTER_MODES.AURAS
}
local MOCK_PREVIEW_DEBUFF_ICONS = {132290, 132090, 135904}
local MOCK_NAMES = {"Lord Doljonijiarnimorinar", "Lorem Ipsum Dolor", "M1 Abrams", "Iblameheals"}

--local values
local isTestMode = false

---------------------------------------------------------
-- HELPERS
---------------------------------------------------------
local function IsInEditMode()
    if C_EditMode and type(C_EditMode.IsEditModeActive) == "function" then
        return C_EditMode.IsEditModeActive()
    end
    return false
end
local function ShowDebuffs()
    return Co_Tank_Frame_Settings.filterMode == FILTER_MODES.DEBUFFS or Co_Tank_Frame_Settings.filterMode == FILTER_MODES.BOTH
end

local function ShowPrivateAuras()
    return Co_Tank_Frame_Settings.filterMode == FILTER_MODES.AURAS or Co_Tank_Frame_Settings.filterMode == FILTER_MODES.BOTH
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

local function GetMaxPrivateAuras()
    return (Co_Tank_Frame_Settings and Co_Tank_Frame_Settings.maxPrivateAuras) or 4
end
local function CalculateScaleFactor()
    return (DEFAULT_WIDTH)  / (GetMaxPrivateAuras() * (PRIVATE_AURA_CONTAINER_SIZE + DEBUFF_SPACING) - DEBUFF_SPACING)
end

local function IsValidFilterMode(mode)
    for _, value in pairs(FILTER_MODES) do
        if value == mode then return true end
    end
    return false
end

---------------------------------------------------------
-- MIXINS 
---------------------------------------------------------
local Co_Tank_Frame_Mixin = {}

function Co_Tank_Frame_Mixin:ClearDebuffs()
    if self.debuffs then
        for i = 1, #self.debuffs do 
            self.debuffs[i]:SetAlpha(0)
            self.debuffs[i].icon:SetTexture(nil)
            self.debuffs[i].count:SetText("");
            self.debuffs[i].cd:SetCooldown(0,0)
        end
    end
end
function Co_Tank_Frame_Mixin:ClearBidDefensives()
    if self.bigDefensives then 
        for i = 1, #self.bigDefensives do
            self.bigDefensives[i]:SetAlpha(0)
            self.bigDefensives[i].icon:SetTexture(nil)
            self.bigDefensives[i].count:SetText("");
            self.bigDefensives[i].cd:SetCooldown(0,0)
        end
    end 
end

function Co_Tank_Frame_Mixin:UpdateBigDefensives()
    local unit = self:GetAttribute("unit")
    local isEditMode = IsInEditMode() or self.isEditing

    if not ShowDebuffs() or not unit or not UnitExists(unit) or isEditMode then
        return
    end
    self:ClearBidDefensives()

    for auraIdx = 1, #self.bigDefensives do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, auraIdx, BIG_DEFENSIVE_AURA_FILTER)
        
        if not aura then break end
        local iconFrame = self.bigDefensives[auraIdx]
        iconFrame.auraInstanceID = aura.auraInstanceID
        iconFrame.icon:SetTexture(aura.icon)
        iconFrame.count:SetFormattedText("%s", aura.applications)
        if(aura.applications) then
            iconFrame.count:SetAlpha(aura.applications)
        else
            iconFrame.count:SetAlpha(0)
        end
        if( iconFrame.cd.SetCooldownFromExpirationTime and type(iconFrame.cd.SetCooldownFromExpirationTime) == "function") then
            iconFrame.cd:SetCooldownFromExpirationTime(aura.expirationTime, aura.duration)
        else
            iconFrame.cd:SetCooldown(0, 0) -- can't show it, shouldn't happen
        end
        iconFrame:SetAlpha(1)
    end

end

function Co_Tank_Frame_Mixin:UpdateDebuffs()
    local unit = self:GetAttribute("unit")
    local isEditMode = IsInEditMode() or self.isEditing

    if not ShowDebuffs() or not unit or not UnitExists(unit) or isEditMode then
        return
    end

    self:ClearDebuffs()

    local idx = 1 -- 1 indexed
    for auraIdx = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, auraIdx, DEBUFF_AURA_FILTER)
        if not aura then break end
        if idx > #self.debuffs then break end
        local iconFrame = self.debuffs[idx]
        iconFrame.auraInstanceID = aura.auraInstanceID
        iconFrame.icon:SetTexture(aura.icon)
        iconFrame.count:SetFormattedText("%s", aura.applications)
        if(aura.applications) then
            iconFrame.count:SetAlpha(aura.applications)
        else
            iconFrame.count:SetAlpha(0)
        end
        if( iconFrame.cd.SetCooldownFromExpirationTime and type(iconFrame.cd.SetCooldownFromExpirationTime) == "function") then
            iconFrame.cd:SetCooldownFromExpirationTime(aura.expirationTime, aura.duration)
        else
            iconFrame.cd:SetCooldown(0, 0) -- can't show it, shouldn't happen
        end
        iconFrame:SetAlpha(1)
        idx = idx + 1
    end

end

function Co_Tank_Frame_Mixin:UpdateHealthBarColor()
    local unit = self:GetAttribute("unit")
    local color
    if unit then
        local _, class = UnitClass(unit)

        if class then
            color = RAID_CLASS_COLORS[class]
        end
    end
    if color then
        self.health:SetStatusBarColor(color.r * HEALTH_BAR_INTENSITY, color.g * HEALTH_BAR_INTENSITY, color.b * HEALTH_BAR_INTENSITY)
    else
        self.health:SetStatusBarColor(0.5, 0.5, 0.5)
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
    self.health:SetMinMaxValues(0, UnitHealthMax(unit))
    self.health:SetValue(UnitHealth(unit))
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

function Co_Tank_Frame_Mixin:InitializePrivateAnchors()
    local unit = self:GetAttribute("unit")
    self:CleanupPrivateAnchors()
    if not unit or not self:IsVisible() or not ShowPrivateAuras() then return end

    self.privateAnchorIDs = self.privateAnchorIDs or {}
    self.anchorFrames = self.anchorFrames or {}

    for i = 1, GetMaxPrivateAuras() do
        if not self.anchorFrames[i] then
            -- Visible container for the border
            local container = CreateFrame("Frame", nil, self, "BackdropTemplate")
            container:SetSize(PRIVATE_AURA_CONTAINER_SIZE,PRIVATE_AURA_CONTAINER_SIZE)
            container:SetBackdrop({
                edgeFile = BACKDROP_TEXTURE,
                edgeSize = 1,
            })
            container:SetBackdropBorderColor(0, 0, 0, 1)

            local auraAnchor = CreateFrame("Frame", nil, container)
            auraAnchor:SetAllPoints(container)
            if i == 1 then
                container:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 0)
            else
                container:SetPoint("RIGHT", self.anchorFrames[i-1].container, "LEFT", -1 * DEBUFF_SPACING, 0)
            end
            self.anchorFrames[i] = auraAnchor
            self.anchorFrames[i].container = container
        end
        self.anchorFrames[i].container:SetAlpha(1)
        self.anchorFrames[i].container:SetScale(CalculateScaleFactor())

        local anchorData = {
            unitToken = unit,
            auraIndex = i,
            parent = self.anchorFrames[i],
            showCountdownFrame = true,
            showCountdownNumbers = true,
            iconInfo = {
                iconWidth = PRIVATE_AURA_CONTAINER_SIZE - 4,
                iconHeight = PRIVATE_AURA_CONTAINER_SIZE - 4,
                iconAnchor = {
                    point = "CENTER",
                    relativeTo = self.anchorFrames[i],
                    relativePoint = "CENTER",
                    offsetX = 0,
                    offsetY = 0,
                },
            }
        }

        local anchorID = C_UnitAuras.AddPrivateAuraAnchor(anchorData)
        if anchorID then
            table.insert(self.privateAnchorIDs, anchorID)
        end
    end
end

function Co_Tank_Frame_Mixin:CleanupPrivateAnchors()
    if self.privateAnchorIDs then
        for _, anchorID in ipairs(self.privateAnchorIDs) do
            C_UnitAuras.RemovePrivateAuraAnchor(anchorID)
        end
        self.privateAnchorIDs = {}
    end

    if self.anchorFrames then
        for i = 1, #self.anchorFrames do
            self.anchorFrames[i].container:SetAlpha(0)
        end
    end

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
            if self:IsVisible() then
                self:InitializePrivateAnchors()
            end
            self:UpdateVisuals()
        else
            if not isTestMode then
                self.nameText:SetText("NO CO-TANK")
            end
            self.health:SetValue(0)
            self.power:SetValue(0)
            for i = 1, #self.debuffs do self.debuffs[i]:SetAlpha(0) end
            self:CleanupPrivateAnchors()
        end
    end
end

function Co_Tank_Frame_Mixin:UpdateVisuals(event, unused_unit, info)
    if event == "UNIT_AURA" and info then
        if not info.isFullUpdate and not info.addedAuras and not info.updatedAuras and not info.removedAuraInstanceIDs then
            return
        end
    end
    if not self.isEditing then
        local now = GetTime()
        if (self.nextUpdate or 0) > now then
            return
        end
        self.nextUpdate = now + UPDATE_THROTTLE
    end

    local unit = self:GetAttribute("unit")
    if not unit or not UnitExists(unit) then return end

    self:UpdateHealthBar()
    self:UpdatePower()
    self:UpdateDebuffs()
    self:UpdateBigDefensives()

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
    self.nameText:SetText(MOCK_NAMES[math.random(#MOCK_NAMES)])
    self:ClearDebuffs()
    --mock debuffs
    for i = 1, #MOCK_PREVIEW_DEBUFF_ICONS do
        local iconFrame = self.debuffs[i]
        local borderFrame = iconFrame.border or iconFrame
        iconFrame.icon:SetTexture(MOCK_PREVIEW_DEBUFF_ICONS[i])
        iconFrame.count:SetText(i == 1 and "3" or "")
        iconFrame.cd:SetCooldown(GetTime(), math.random(10, 60))
        iconFrame:SetAlpha(1)
    end
    for i=1, #self.bigDefensives do
        local iconFrame = self.bigDefensives[i]
        iconFrame:Hide()--hide on edit so they don't intercept mouse clicks
    end
    --Private auras can't be mocked.  
    self:UpdateHealthBar()
    self:UpdatePower()
    self:Show()
end

function Co_Tank_Frame_Mixin:EditModeStopMock()
    -- Put back the default background color
    self:UpdateHealthBarColor()
    self:ClearDebuffs()
    for i=1, #self.bigDefensives do
        local iconFrame = self.bigDefensives[i]
        iconFrame:Show()
    end
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
local function CreateIconFrame(iconList, iconSize, point, parent, relativePoint, ofsx, ofsy)
    local iconFrame = CreateFrame("Button", nil, parent, "BackdropTemplate")
    iconFrame:SetFrameStrata("MEDIUM")
    iconFrame:SetMouseClickEnabled(true)
    iconFrame:SetSize(iconSize, iconSize)

    --BORDER (Using Backdrop for a perfect 1px line)
    iconFrame:SetBackdrop({
        edgeFile = BACKDROP_TEXTURE,
        edgeSize = 1,
    })
    iconFrame.border = iconFrame
    iconFrame:SetBackdropBorderColor(0, 0, 0, 1)

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
        if unit and self.auraInstanceID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetUnitAura(unit, self.auraInstanceID)
            GameTooltip:Show()
        end
    end)

    local auraIdx = #iconList + 1
    if auraIdx == 1 then
        iconFrame:SetPoint(point, parent, relativePoint, ofsx, ofsy )
    else
        iconFrame:SetPoint("RIGHT", iconList[auraIdx-1], "LEFT", -1 * DEBUFF_SPACING, 0)
    end
    iconFrame:SetAlpha(0)
    iconList[auraIdx] = iconFrame
end
local function InitializeCotankFrame()
    -- Initialize settings if they don't exist
    Co_Tank_Frame_Settings = Co_Tank_Frame_Settings or {}
    Co_Tank_Frame_Settings.layouts = Co_Tank_Frame_Settings.layouts or {}
    if not Co_Tank_Frame_Settings.filterMode or not IsValidFilterMode(Co_Tank_Frame_Settings.filterMode) then
        Co_Tank_Frame_Settings.filterMode = FILTER_MODES.AURAS
    end

    local frame = CreateFrame("Button", "Co_Tank_Frame", UIParent, "SecureUnitButtonTemplate, BackdropTemplate, EditModeSystemTemplate")
    frame:SetAttribute("type1", "target") -- Left click = Target
    frame:SetAttribute("type2", "togglemenu") -- Right click = Menu 

    Mixin(frame, Co_Tank_Frame_Mixin)
    
    -- Visual Setup
    frame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetColorTexture(0.05, 0.05, 0.05, 0.9)

    frame:SetBackdrop({edgeFile = BACKDROP_TEXTURE, edgeSize = 1})
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    frame.health = CreateFrame("StatusBar", nil, frame)
    -- 1. Adjust Health Bar (Stop it 4px from the bottom)
    frame.health:SetPoint("TOPLEFT", 1, -1)
    frame.health:SetPoint("BOTTOMRIGHT", -1, POWER_BAR_HEIGHT + 2) -- Raised by height + 2px gap

    -- 2. Create Power Bar
    frame.power = CreateFrame("StatusBar", nil, frame)
    frame.power:SetHeight(POWER_BAR_HEIGHT) -- Thin, modern look
    frame.power:SetPoint("TOPLEFT", frame.health, "BOTTOMLEFT", 0, -1)
    frame.power:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.power:SetStatusBarTexture(BACKDROP_TEXTURE)

    -- 3. Power Background
    frame.powerBG = frame.power:CreateTexture(nil, "BACKGROUND")
    frame.powerBG:SetAllPoints()
    frame.powerBG:SetColorTexture(0, 0, 0, 0.5)

    frame.health:SetStatusBarTexture(BACKDROP_TEXTURE)

    -- Name Text (Slot 1)
    frame.nameText = frame.health:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    local fontFace, fontSize, fontFlags = frame.nameText:GetFont()
    frame.nameText:SetFont(fontFace, 14, "OUTLINE")
    frame.nameText:SetPoint("BOTTOMLEFT", frame.health, "LEFT", 6, 4) -- Nudged up
    frame.nameText:SetJustifyH("LEFT")
    frame.nameText:SetIgnoreParentAlpha(false)

    -- HP Text (Slot 2)
    frame.hpText = frame.health:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
    frame.hpText:SetPoint("TOPLEFT", frame.health, "LEFT", 6, -4) -- Nudged down
    frame.hpText:SetJustifyH("LEFT")
    frame.hpText:SetTextColor(0.9, 0.9, 0.9)
    frame.hpText:SetIgnoreParentAlpha(false)
    
    frame.debuffs = {}
    for i = 1, DEBUFF_MAX_COUNT do
        CreateIconFrame(frame.debuffs,DEBUFF_ICON_SIZE, "TOPRIGHT", frame,"BOTTOMRIGHT", 0, 0)
    end

    frame.bigDefensives = {}
    for i = 1, BIG_DEFENSIVES_MAX_COUNT do
        local bigDefensiveIconSize = DEFAULT_HEIGHT - POWER_BAR_HEIGHT - 4 - 4
        CreateIconFrame(frame.bigDefensives,bigDefensiveIconSize,"RIGHT", frame.health, "RIGHT", -1 * DEBUFF_SPACING, 2 )
    end

    -- Assign Scripts
    frame:SetScript("OnAttributeChanged", frame.OnAttributeChanged)
    frame:SetScript("OnEvent", frame.UpdateVisuals)
    frame:SetScript("OnShow", function(self)
        self:UpdateHealthBarColor()
        self:InitializePrivateAnchors()
    end)
    frame:SetScript("OnHide", function(self)
        self:CleanupPrivateAnchors()
    end)

    if lib then
        lib:Register(frame, Co_Tank_Frame_Settings)
    end

    -- External State Controller (Manager)
    local manager = CreateFrame("Frame")
    manager:RegisterEvent("GROUP_ROSTER_UPDATE")
    manager:RegisterEvent("PLAYER_REGEN_ENABLED")
    manager:RegisterEvent("PLAYER_ENTERING_WORLD")
    manager:SetScript("OnEvent", function(self, event)
        if not InCombatLockdown() then
            local myRole = UnitGroupRolesAssigned("player")
            local currentTank = FindCoTank()
            if myRole == "TANK" and currentTank then
                frame:SetAttribute("unit", currentTank)
                RegisterUnitWatch(frame) -- Engine handles showing it
            else
                UnregisterUnitWatch(frame)
                frame:Hide()
                frame:SetAttribute("unit", nil)
            end
            if lib then
                lib:ApplyLayout(frame)
            end
            frame:UpdateHealthBarColor()
            frame:UpdateVisuals()
        end
    end)

    -- Support for Clique and other click-casting addons
    _G["ClickCastFrames"] = _G["ClickCastFrames"] or {}
    _G["ClickCastFrames"][frame] = true

    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"
    print(FERROZ_COLOR:WrapTextInColorCode("[CoTank] v" .. version) .. " loaded (/cotank)")
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, name)
    if name == addonName then
        InitializeCotankFrame()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

StaticPopupDialogs["COTANK_RELOAD_UI"] = {
    text = "CoTank: You need to reload your UI to apply the new aura settings.",
    button1 = "Reload",
    button2 = "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

---------------------------------------------------------
-- MAIN SLASH COMMAND
---------------------------------------------------------
SLASH_COTANK1 = "/cotank"
SlashCmdList["COTANK"] = function(msg)
    local cmd, arg = string.split(" ", msg)
    cmd = cmd and cmd:lower() or ""
    if cmd == "reset" then
        Co_Tank_Frame:UpdateVisuals()
        if lib and lib.ResetPosition then
            lib:ResetPosition(Co_Tank_Frame)
        end
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank:").." Settings and position have been reset.")
    elseif cmd == "filter" or cmd == "filtermode" then
        Co_Tank_Frame_Settings = Co_Tank_Frame_Settings or {}
        Co_Tank_Frame_Settings.filterMode = Co_Tank_Frame_Settings.filterMode or FILTER_MODES.AURAS
        Co_Tank_Frame_Settings.filterMode = NEXT_FILTER_MODE[Co_Tank_Frame_Settings.filterMode] or FILTER_MODES.AURAS
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank:").." Filtermode set to: " .. Co_Tank_Frame_Settings.filterMode)
    elseif cmd == "maxauras" or cmd == "limit" then
        local num = tonumber(arg)
        if num and num > 0 and num <= 10 then -- Cap it at 10 for performance/sanity
            Co_Tank_Frame_Settings.maxPrivateAuras = num
            print(FERROZ_COLOR:WrapTextInColorCode("CoTank:").." Max Private Auras set to: " .. num)
            StaticPopup_Show("COTANK_RELOAD_UI")
        end
    elseif cmd == "test" then
        isTestMode = not isTestMode
        local status = isTestMode and GREEN_FONT_COLOR:WrapTextInColorCode("ON") or RED_FONT_COLOR:WrapTextInColorCode("OFF")
        print(FERROZ_COLOR:WrapTextInColorCode("CoTank:").." Test Mode is " .. status)

        if Co_Tank_Frame then
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
        print("  /cotank maxauras # - changes the maximum number of auras shown")
    end
end