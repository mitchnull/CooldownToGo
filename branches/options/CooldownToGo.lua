--[[
Name: CooldownToGo
Revision: $Revision$
Author(s): mitch0
Website: http://www.wowace.com/wiki/CooldownToGo
Documentation: http://www.wowace.com/wiki/CooldownToGo
SVN: http://svn.wowace.com/wowace/trunk/CooldownToGo/
Description: Display the reamining cooldown on the last action you tried to use
Dependencies:
License: Public Domain
]]

local AppName = "CooldownToGo"
local VERSION = AppName .. "-r" .. ("$Revision$"):match("%d+")

local SML = LibStub:GetLibrary("LibSharedMedia-3.0", true);

-- cache

local GetTime = GetTime
local GetSpellName = GetSpellName
local GetSpellCooldown = GetSpellCooldown
local GetActionText = GetActionText
local GetActionCooldown = GetActionCooldown
local GetActionTexture = GetActionTexture
local GetSpellTexture = GetSpellTexture
local GetInventoryItemCooldown = GetInventoryItemCooldown 
local GetInventoryItemTexture = GetInventoryItemTexture 
local GetContainerItemCooldown = GetContainerItemCooldown
local GetContainerItemInfo = GetContainerItemInfo
local GetPetActionCooldown = GetPetActionCooldown
local GetPetActionInfo = GetPetActionInfo

-- hard-coded config stuff

local UpdateDelay = .1 -- update frequency == 1/UpdateDelay
local MinFontSize = 5
local MaxFontSize = 40
local DefaultFontName = "Friz Quadrata TT"
local DefaultFontPath = GameFontNormal:GetFont()

-- internal vars

local db
local _ -- throwaway
local lastUpdate = 0 -- time since last real update
local fadeStamp -- the timestamp when we should start fading the display
local hideStamp -- the timestamp when we should hide the display
local endStamp -- the timestamp when the cooldown will be over
local finishStamp -- the timestamp when the we are finished with this cooldown

local getCurrCooldown
local currArg1
local currArg2

local needUpdate = false
local isActive = false
local isAlmostReady = false
local isReady = false
local isHidden = false

local GCD = 1.5

CooldownToGo = LibStub("AceAddon-3.0"):NewAddon(AppName, "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0")
CooldownToGo:SetDefaultModuleState(false)

CooldownToGo.AppName = AppName
CooldownToGo.version = VERSION

local defaults = {
    profile = {
        minimap = {},
        holdTime = 1.0,
        fadeTime = 2.0,
        readyTime = 0.5,
        font = DefaultFontName,
        fontSize = 24,
        fontOutline = "",
        locked = false,
        point = "CENTER",
        relPoint = "CENTER",
        x = 0,
        y = 100,
        colorR = 1.0,
        colorG = 1.0,
        colorB = 1.0,
        strata = "HIGH",
    },
}

local function print(text)
    if (DEFAULT_CHAT_FRAME) then 
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

function CooldownToGo:createFrame()
    self.isMoving = false
    local frame = CreateFrame("MessageFrame", "CooldownToGoFrame", UIParent)
    frame:Hide()
    frame:SetFrameStrata(defaults.profile.strata)
    frame:EnableMouse(false)
    frame:SetClampedToScreen()
    frame:SetMovable(true)
    frame:SetWidth(120)
    frame:SetHeight(30)
    frame:SetPoint(defaults.profile.point, UIParent, defaults.profile.relPoint, defaults.profile.x, defaults.profile.y)
    frame:SetFont(DefaultFontPath, defaults.profile.fontSize, defaults.profile.fontOutline)
    frame:SetJustifyH("CENTER")
    self.frame = frame

    local frameBG = frame:CreateTexture("CDTGFrameBG", "BACKGROUND")
    frameBG:SetTexture(0, 0, 0, 0.42)
    frameBG:SetWidth(frame:GetWidth())
    frameBG:SetHeight(frame:GetHeight())
    frameBG:SetPoint("CENTER", frame, "CENTER", 0, 0)
    self.frameBG = frameBG

    local text = frame:CreateFontString("CDTGText", "OVERLAY", "GameFontNormal")
    text:SetFont(DefaultFontPath, defaults.profile.fontSize, defaults.profile.fontOutline)
    text:SetJustifyH("LEFT")
    text:SetPoint("LEFT", frame, "CENTER", 0, 0)
    self.text = text

    local icon = frame:CreateTexture("CDTGIcon", "OVERLAY")
    icon:SetPoint("RIGHT", frame, "CENTER", -2, 0)
    self.icon = icon

    frame:SetScript("OnMouseDown", function(frame, button)
        if (not button) then
            -- some addon is hooking us but doesn't pass button. argh...
            button = arg1
        end
        if (button == "LeftButton") then
            self.frame:StartMoving()
            self.isMoving = true
        elseif (button == "RightButton") then
            self:OpenConfigDialog()
        end
    end)
    frame:SetScript("OnMouseUp", function(frame, button)
        if (not button) then
            -- some addon is hooking us but doesn't pass button. argh...
            button = arg1
        end
        if (self.isMoving and button == "LeftButton") then
            self.frame:StopMovingOrSizing()
            self.isMoving = false
            db.point, _, db.relPoint, db.x, db.y = frame:GetPoint()
        end
    end)
    frame:SetScript("OnUpdate", function(frame, elapsed)
        lastUpdate = lastUpdate + elapsed
        if (lastUpdate < UpdateDelay) then return end
        lastUpdate = 0
        self:OnUpdate(elapsed)
    end)
end

function CooldownToGo:applyFontSettings(isCallback)
    local dbFontPath
    if (SML) then
        dbFontPath = SML:Fetch("font", db.font, true)
        if (not dbFontPath) then
            if (isCallback) then
                return
            end
            SML.RegisterCallback(self, "LibSharedMedia_Registered", "applyFontSettings", true)
            dbFontPath = DefaultFontPath
        else
            SML.UnregisterCallback(self, "LibSharedMedia_Registered")
        end
    else
        dbFontPath = DefaultFontPath
    end
    local fontPath, fontSize, fontOutline = self.text:GetFont()
    fontOutline = fontOutline or ""
    if (dbFontPath ~= fontPath or db.fontSize ~= fontSize or db.fontOutline ~= fontOutline) then
        self.text:SetFont(dbFontPath, db.fontSize, db.fontOutline)
    end
    self.icon:SetHeight(fontSize)
    self.icon:SetWidth(fontSize)
end

function CooldownToGo:applySettings()
    if (not self:IsEnabled()) then return end
    if (db.locked) then
        self:lock()
    else
        self:unlock()
    end
    self.frame:ClearAllPoints()
    self.frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    self.frame:SetFrameStrata(db.strata)
    self.text:SetTextColor(db.colorR, db.colorG, db.colorB)
    self:applyFontSettings()
end

function CooldownToGo:lock()
    self.frame:EnableMouse(false)
    self.frameBG:Hide()
    if (isActive) then
        self:updateStamps(currStart, currDuration, true)
    else
        self.frame:Hide()
    end
end

function CooldownToGo:unlock()
    self.frame:EnableMouse(true)
    self.frameBG:Show()
    self.frame:Show()
    self.frame:SetAlpha(1)
    isHidden = false
end

function CooldownToGo:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("CooldownToGoDB", defaults)
    self.db.RegisterCallback(self, "OnProfileChanged", "profileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "profileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "profileChanged")
    db = self.db.profile
    self:setupOptions()
    if (not self.frame) then
        self:createFrame()
    end
end

function CooldownToGo:OnEnable(first)
    self:profileChanged()
    self:SecureHook("CastSpell", "checkSpellCooldown")
    self:SecureHook("CastSpellByName", "checkSpellCooldownByName")
    self:SecureHook("UseAction", "ckeckActionCooldown")
    self:SecureHook("UseContainerItem", "ckeckContainerItemCooldown")
    self:SecureHook("UseInventoryItem", "ckeckInventoryItemCooldown")
    self:SecureHook("CastPetAction", "checkPetActionCooldown")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "updateCooldown")
    self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", "updateCooldown")
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", "updateCooldown")
    self:RegisterEvent("PET_BAR_UPDATE_COOLDOWN", "updateCooldown")
end

function CooldownToGo:OnDisable()
    if (self.frame) then
        self.frame:Hide()
    end
    self:UnhookAll()
    self:UnregisterAllEvents()
end

function CooldownToGo:profileChanged()
    db = self.db.profile
    self:applySettings()
end

function CooldownToGo:OnUpdate(elapsed)
    if (not isActive) then
        return
    end
    if (needUpdate) then
        needUpdate = false
        local start, duration = getCurrCooldown(currArg1, currArg2)
        if (currStart ~= start or currDuration ~= duration) then
            self:updateStamps(start, duration, false)
        end
    end
    local now = GetTime()
    if (now > finishStamp) then
        if (db.locked) then
            self.frame:Hide()
        end
        isActive = false
        self.text:SetText(nil)
        self.icon:SetTexture(nil)
        return
    end
    if (now >= endStamp) then
        if (not isReady) then
            isReady = true
            self.text:SetText(L["Ready"])
            self:updateStamps(currStart, currDuration, true)
--  TODO:   PlaySound()
        end
    else
        local cd = endStamp - now
        if (cd <= db.readyTime and not isAlmostReady) then
            self:updateStamps(currStart, currDuration, true)
            isAlmostReady = true
        end
        if cd > 90 then
            self.text:SetText(string.format("%d:%02d", cd / 60, cd % 60))
        else
            self.text:SetText(string.format("%.1f", cd))
        end
    end
    if (not db.locked) then
        return
    end
    if (now > fadeStamp) then
        local alpha = 1 - ((now - fadeStamp) / db.fadeTime)
        if (alpha <= 0) then
            if (not isHidden) then
                isHidden = true
                self.frame:SetAlpha(0)
            end
        else
            self.frame:SetAlpha(alpha)
        end
    end
end

function CooldownToGo:updateStamps(start, duration, show)
    currStart = start
    currDuration = duration
    local now = GetTime()
    endStamp = start + duration
    if (endStamp < now) then
        endStamp = now
    end
    if (now + db.holdTime >= endStamp) then
        fadeStamp = endStamp
    else
        fadeStamp = now + db.holdTime
    end
    finishStamp = endStamp + db.fadeTime
    hideStamp = fadeStamp + db.fadeTime

    lastUpdate = UpdateDelay -- to force update in next frame
    isAlmostReady = false
    if (show) then
        isHidden = false
        self.frame:SetAlpha(1)
        self.frame:Show()
    end
end

function CooldownToGo:showCooldown(texture, getCooldownFunc, arg1, arg2)
    local start, duration, enabled = getCooldownFunc(arg1, arg2)
    -- print("### " .. tostring(texture) .. ", " .. tostring(start) .. ", " .. tostring(duration) .. ", " .. tostring(enabled))
    if (not enabled) or (not start) or (not duration) or (duration <= GCD) then
        return
    end
    getCurrCooldown, currArg1, currArg2 = getCooldownFunc, arg1, arg2
    isActive = true
    isReady = false
    isAlmostReady = false
    self.icon:SetTexture(texture)
    self:updateStamps(start, duration, true)
end

function CooldownToGo:checkSpellCooldown(spellIdx, bookType)
--  print("### spellIdx: " .. tostring(spellIdx))
    local texture = GetSpellTexture(spellIdx, bookType)
    self:showCooldown(texture, GetSpellCooldown, spellIdx, bookType)
end

function CooldownToGo:checkSpellCooldownByName(spellName)
--  print("### spellName: " .. tostring(spellName))
    local texture = GetSpellTexture(spellName)
    self:showCooldown(texture, GetSpellCooldown, spellName, nil)
end

function CooldownToGo:ckeckActionCooldown(slot)
--  print("### action: " .. tostring(slot))
    local texture = GetActionTexture(slot)
    self:showCooldown(texture, GetActionCooldown, slot, nil)
end

function CooldownToGo:ckeckInventoryItemCooldown(item)
--  print("### invItem: " .. tostring(item))
    local texture = GetInventoryItemTexture("player", item)
    self:showCooldown(texture, GetInventoryItemCooldown, "player", item)
end

function CooldownToGo:ckeckContainerItemCooldown(bagId, bagSlot)
--  print("### containerItem: " .. tostring(bagId), .. ", " .. tostring(bagSlot))
    local texture = GetContainerItemInfo(bagId, bagSlot)
    self:showCooldown(texture, GetContainerItemCooldown, bagId, bagSlot)
end

function CooldownToGo:checkPetActionCooldown(index)
    local _, _, texture = GetPetActionInfo(index)
    self:showCooldown(texture, GetPetActionCooldown, index, nil)
end

function CooldownToGo:updateCooldown(event)
    if (not isActive or isReady) then
        return
    end
    needUpdate = true
end
