--[[
Name: CooldownToGo
Revision: $Revision$
Author(s): mitch0
Website: http://www.wowace.com/wiki/CooldownToGo
Documentation: http://www.wowace.com/wiki/CooldownToGo
SVN: http://svn.wowace.com/wowace/trunk/CooldownToGo/
Description: Display the reamining cooldown on the last action you tried to use
License: Public Domain
]]

local AppName = "CooldownToGo"
local VERSION = AppName .. "-r" .. ("$Revision$"):match("%d+")

local L = LibStub("AceLocale-3.0"):GetLocale(AppName)
local SML = LibStub:GetLibrary("LibSharedMedia-3.0", true)

-- cache

local GetTime = GetTime

local GetActionInfo = GetActionInfo

local GetPetActionCooldown = GetPetActionCooldown
local GetPetActionInfo = GetPetActionInfo

local GetSpellName = GetSpellName
local GetSpellLink = GetSpellLink
local GetSpellInfo = GetSpellInfo
local GetSpellCooldown = GetSpellCooldown

local GetInventoryItemLink = GetInventoryItemLink 
local GetContainerItemLink = GetContainerItemLink
local GetItemInfo = GetItemInfo
local GetItemCooldown = GetItemCooldown

-- hard-coded config stuff

local UpdateDelay = .1 -- update frequency == 1/UpdateDelay
local Width = 120
local Height = 30
local DefaultFontPath = GameFontNormal:GetFont()
local DefaultFontName = "Friz Quadrata TT"
local Icon = "Interface\\Icons\\Ability_Hunter_Readiness"

local Rank1 = "Rank 1"
-- internal vars

local db
local _ -- throwaway
local lastUpdate = 0 -- time since last real update
local fadeStamp -- the timestamp when we should start fading the display
local hideStamp -- the timestamp when we should hide the display
local endStamp -- the timestamp when the cooldown will be over
local finishStamp -- the timestamp when the we are finished with this cooldown

local currGetCooldown
local currArg

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
        ignoreLists = {
            spell = {},
            item = {},
            petbar = {},
        },
    },
}

local function print(text)
    if (DEFAULT_CHAT_FRAME) then 
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

local function printf(fmt, ...)
    return print(fmt:format(...))
end

local function itemIdFromLink(link)
    if (not link) then return nil end
    local id = link:match("item:(%d+)")
    return tonumber(id)
end

local function spellIdFromLink(link)
    if (not link) then return nil end
    local id = link:match("spell:(%d+)")
    return tonumber(id)
end

local normalizedSpellLinks = {}
local function getNormalizedSpellLink(spell)
    local link = normalizedSpellLinks[spell]
    if (link) then return link end
    local name, rank = GetSpellInfo(spell)
    if (not name) then
        link = ""
        normalizedSpellLinks[spell] = link
        return link
    end
    if (rank ~= "") then 
        link = GetSpellLink(name, Rank1)
    else
        link = GetSpellLink(name, "")
    end
    if (not link) then link = "" end
    normalizedSpellLinks[spell] = link
    return link
end

local function petActionIndexFromLink(link)
    local id = link:match("petbar:(%d+)")
    return tonumber(id)
end

function CooldownToGo:createFrame()
    self.isMoving = false
    local frame = CreateFrame("MessageFrame", "CooldownToGoFrame", UIParent)
    frame:Hide()
    frame:SetFrameStrata(defaults.profile.strata)
    frame:EnableMouse(false)
    frame:SetClampedToScreen()
    frame:SetMovable(true)
    frame:SetWidth(Width)
    frame:SetHeight(Height)
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
    text:SetText("cdtg")
    self.text = text

    local icon = frame:CreateTexture("CDTGIcon", "OVERLAY")
    icon:SetTexture(Icon)
    icon:SetPoint("RIGHT", frame, "CENTER", -2, 0)
    self.icon = icon

    frame:SetScript("OnMouseDown", function(frame, button)
        if (button == "LeftButton") then
            self.frame:StartMoving()
            self.isMoving = true
        elseif (button == "RightButton") then
            self:openConfigDialog()
        end
    end)
    frame:SetScript("OnMouseUp", function(frame, button)
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
    self.icon:SetHeight(db.fontSize)
    self.icon:SetWidth(db.fontSize)
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
    if (not self.frame) then
        self:createFrame()
    end
    self:applySettings()
    self:setupOptions()
end

function CooldownToGo:OnEnable(first)
    self:SecureHook("CastSpell", "checkSpellCooldownByIdx")
    self:SecureHook("CastSpellByName", "checkSpellCooldown")
    self:SecureHook("UseAction", "checkActionCooldown")
    self:SecureHook("UseContainerItem", "checkContainerItemCooldown")
    self:SecureHook("UseInventoryItem", "checkInventoryItemCooldown")
    self:SecureHook("UseItemByName", "checkItemCooldown")
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
        local start, duration = currGetCooldown(currArg)
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

function CooldownToGo:showCooldown(texture, getCooldownFunc, arg, cat, id)
    if (self.ignoreNext) then
        self.ignoreNext = nil
        self:setIgnoredState(cat .. ':' .. id, true)
        return
    end
    local start, duration, enabled = getCooldownFunc(arg)
    -- print("### " .. tostring(texture) .. ", " .. tostring(start) .. ", " .. tostring(duration) .. ", " .. tostring(enabled))
    if (not enabled) or (not start) or (not duration) or (duration <= GCD) then
        return
    end
    currGetCooldown, currArg = getCooldownFunc, arg
    isActive = true
    isReady = false
    isAlmostReady = false
    self.icon:SetTexture(texture)
    self:updateStamps(start, duration, true)
end

function CooldownToGo:checkActionCooldown(slot)
    local type, id, subtype = GetActionInfo(slot)
    -- printf("### action: %s, type=%s, id=%s, subtype=%s", tostring(slot), tostring(type), tostring(id), tostring(subtype))
    if (type == 'spell') then
        self:checkSpellCooldownByIdx(id, subtype)
    elseif (type == 'item') then
        self:checkItemCooldown(id)
    end
end

function CooldownToGo:checkSpellCooldownByIdx(spellIdx, bookType)
    -- printf("### spellIdx: %s, book: %s", tostring(spellIdx), tostring(bookType))
    local spell = GetSpellName(spellIdx, bookType)
    self:checkSpellCooldown(spell)
end

function CooldownToGo:checkSpellCooldown(spell)
    -- print("### spell: " .. tostring(spell))
    local spellLink = getNormalizedSpellLink(spell)
    local spellId = spellIdFromLink(spellLink)
    if (not spellId) then return end
    if (db.ignoreLists.spell[spellId]) then return end
    local name, _, texture = GetSpellInfo(spellId)
    self:showCooldown(texture, GetSpellCooldown, name, 'spell', spellId)
end

function CooldownToGo:checkInventoryItemCooldown(invSlot)
    -- print("### invItem: " .. tostring(invSlot))
    local itemLink = GetInventoryItemLink("player", invSlot)
    self:checkItemCooldown(itemLink)
end

function CooldownToGo:checkContainerItemCooldown(bagId, bagSlot)
    -- print("### containerItem: " .. tostring(bagId) .. ", " .. tostring(bagSlot))
    local itemLink = GetContainerItemLink(bagId, bagSlot)
    self:checkItemCooldown(itemLink)
end

function CooldownToGo:checkItemCooldown(item)
    -- print("### item: " .. tostring(item))
    local _, itemLink, _, _, _, _, _, _, _, texture = GetItemInfo(item)
    local itemId = itemIdFromLink(itemLink)
    if (not itemId) then return end
    if (db.ignoreLists.item[itemId]) then return end
    self:showCooldown(texture, GetItemCooldown, itemId, 'item', itemId)
end

function CooldownToGo:checkPetActionCooldown(index)
    local _, _, texture = GetPetActionInfo(index)
    self:showCooldown(texture, GetPetActionCooldown, index, 'petbar', index)
end

function CooldownToGo:updateCooldown(event)
    -- printf("### updateCooldown: %s", tostring(event))
    if (not isActive) then
        return
    end
    if (isReady) then
        return
    end
    needUpdate = true
end

function CooldownToGo:notifyIgnoredChange(text, flag)
    if (not text) then return end
    if (flag) then
        self:Print(L["added %s to ignore list"]:format(text))
    else
        self:Print(L["removed %s from ignore list"]:format(text))
    end
    self:updateIgnoreListOptions()
end

function CooldownToGo:setIgnoredState(link, flag)
    if (not flag) then flag = nil end
    if (spellIdFromLink(link)) then
        local id = spellIdFromLink(link)
        -- "normalize" to Rank1 id
        local spell = GetSpellInfo(id)
        link = getNormalizedSpellLink(spell)
        id = spellIdFromLink(link)
		if (not id) then return end
        db.ignoreLists.spell[id] = flag 
        self:notifyIgnoredChange(link, flag)
    elseif  (itemIdFromLink(link)) then
        local id = itemIdFromLink(link)
		if (not id) then return end
        db.ignoreLists.item[id] = flag
        local _, link = GetItemInfo(id)
        self:notifyIgnoredChange(link, flag)
    elseif (petActionIndexFromLink(link)) then
        local id = petActionIndexFromLink(link)
		if (not id) then return end
        local text = GetPetActionInfo(id)
        db.ignoreLists.petbar[id] = flag
        self:notifyIgnoredChange(text, flag)
    end
end

