--[[
Name: CooldownToGo
Author(s): mitch0
Description: Display the reamining cooldown on the last action you tried to use
License: Public Domain
]]

local AppName = "CooldownToGo"
local OptionsAppName = AppName .. "_Options"
local VERSION = AppName .. "-@project-version@"

local L = LibStub("AceLocale-3.0"):GetLocale(AppName)
local LSM = LibStub:GetLibrary("LibSharedMedia-3.0", true)
local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
local LibDualSpec = LibStub("LibDualSpec-1.0", true)
local Masque = LibStub("Masque", true)

-- cache

local _G = _G
local tostring = tostring
local tonumber = tonumber
local pairs = pairs
local GetTime = GetTime

local GetActionInfo = GetActionInfo

local GetPetActionCooldown = GetPetActionCooldown
local GetPetActionInfo = GetPetActionInfo

local GetSpellBookItemName = GetSpellBookItemName
local GetSpellLink = GetSpellLink
local GetSpellInfo = GetSpellInfo
local GetSpellCooldown = GetSpellCooldown
local GetSpellBaseCooldown = GetSpellBaseCooldown

local GetInventoryItemLink = GetInventoryItemLink
local GetContainerItemLink = GetContainerItemLink
local GetItemInfo = GetItemInfo
local GetItemCooldown = GetItemCooldown
local wipe = wipe
local PlaySoundFile = PlaySoundFile

local NUM_PET_ACTION_SLOTS = NUM_PET_ACTION_SLOTS

-- hard-coded config stuff

local NormalUpdateDelay = 1.0/10 -- update frequency == 1/NormalUpdateDelay
local FadingUpdateDelay = 1.0/25 -- update frequency while fading == 1/FadingUpdateDelay, must be <= NormalUpdateDelay
local Width = 120
local Height = 30
local DefaultFontName = "Friz Quadrata TT"
local DefaultFontPath = GameFontNormal:GetFont()
local DefaultSoundName = "Pong"
local DefaultSoundFile = [[Interface\AddOns\]] .. AppName .. [[\sounds\pong.ogg]]
local Icon = [[Interface\AddOns\]] .. AppName .. [[\cdtg.tga]]

-- internal vars

local db
local _ -- throwaway
local lastUpdate = 0 -- time since last real update
local updateDelay = NormalUpdateDelay
local fadeStamp -- the timestamp when we should start fading the display
local hideStamp -- the timestamp when we should hide the display
local endStamp -- the timestamp when the cooldown will be over
local finishStamp -- the timestamp when the we are finished with this cooldown

local currGetCooldown
local currArg
local currStart
local currDuration

local lastTexture
local lastGetCooldown
local lastArg

local needUpdate = false
local isActive = false
local isAlmostReady = false
local isReady = false
local isHidden = false
local soundPlayedAt = 0

local ignoredSpells = {} -- contains a map of name -> id (as stored in db.profile.ignoreLists.spell). we need to store ids in the db to avoid locale related issues, but we must match by spell name because there is no generic way of "normalizing" all ranks of a spell to a common spellId

local GCD = 1.5

CooldownToGo = LibStub("AceAddon-3.0"):NewAddon(AppName, "AceHook-3.0", "AceEvent-3.0")
local CooldownToGo = CooldownToGo
CooldownToGo:SetDefaultModuleState(false)

CooldownToGo.AppName = AppName
CooldownToGo.OptionsAppName = OptionsAppName
CooldownToGo.version = VERSION

local defaults = {
  profile = {
    minimap = {},
    holdTime = 1.0,
    fadeTime = 2.0,
    readyTime = 0.5,
    font = DefaultFontName,
    fontSize = 24,
    iconSize = 24,
    padding = 2,
    textPosition = "RIGHT",
    fontOutline = "",
    locked = false,
    point = "CENTER",
    relPoint = "CENTER",
    x = 0,
    y = 100,
    colorR = 1.0,
    colorG = 1.0,
    colorB = 1.0,
    colorA = 1.0,
    strata = "HIGH",
    gracePeriod = 0.5,
    ignoreLists = {
      spell = {},
      item = {},
      petbar = {},
    },
    reverseIgnoreLogic = false,
    warnSound = true,
    warnSoundName = DefaultSoundName,
    suppressReadyNotif = false,
  },
}

local Opposite = {
  ["LEFT"] = "RIGHT",
  ["RIGHT"] = "LEFT",
  ["TOP"] = "BOTTOM",
  ["BOTTOM"] = "TOP",
}

local function textOffsetXY(padding, textPosition)
  if textPosition == "LEFT" then
    return -padding / 2, 0
  elseif textPosition == "RIGHT" then
    return padding / 2, 0
  elseif textPosition == "TOP" then
    return 0, padding / 2
  elseif textPosition == "BOTTOM" then
    return 0, -padding / 2
  end
  return 0, 0 -- just in case
end

local function iconOffsetXY(padding, textPosition)
  local tx, ty = textOffsetXY(padding, textPosition)
  return -tx, -ty
end

local function printf(fmt, ...)
  return print(fmt:format(...))
end

local function itemIdFromLink(link)
  if not link then return nil end
  local id = link:match("item:(%d+)")
  return tonumber(id)
end

local function spellIdFromLink(link)
  if not link then return nil end
  local id = link:match("spell:(%d+)")
  return tonumber(id)
end

local function petActionIndexFromLink(link)
  if not link then return nil end
  local id = link:match("petbar:(%d+)")
  return tonumber(id)
end

local function updateIgnoredSpells(ids)
  wipe(ignoredSpells)
  for id, flag in pairs(ids) do
    if flag then
      local name = GetSpellInfo(id)
      if name then -- this should always be true, but let's be sure...
        ignoredSpells[name] = id
      end
    end
  end
end

function CooldownToGo:updateLayout()
  if db.textPosition == "LEFT" then
    self.text:SetJustifyH("RIGHT")
  elseif db.textPosition == "RIGHT" then
    self.text:SetJustifyH("LEFT")
  else
    self.text:SetJustifyH("CENTER")
  end
  self.text:ClearAllPoints()
  self.text:SetPoint(Opposite[db.textPosition], self.frame, "CENTER", textOffsetXY(db.padding, db.textPosition))

  self.icon:ClearAllPoints()
  self.icon:SetPoint(db.textPosition, self.frame, "CENTER", iconOffsetXY(db.padding, db.textPosition))
  self.icon:SetHeight(db.iconSize)
  self.icon:SetWidth(db.iconSize)
end

function CooldownToGo:createFrame()
  self.isMoving = false
  local frame = CreateFrame("MessageFrame", "CooldownToGoFrame", UIParent)
  frame:Hide()
  frame:SetFrameStrata(defaults.profile.strata)
  frame:EnableMouse(false)
  frame:SetClampedToScreen(false)
  frame:SetMovable(true)
  frame:SetWidth(Width)
  frame:SetHeight(Height)
  frame:SetPoint(defaults.profile.point, UIParent, defaults.profile.relPoint, defaults.profile.x, defaults.profile.y)
  frame:SetFont(DefaultFontPath, defaults.profile.fontSize, defaults.profile.fontOutline)
  frame:SetJustifyH("CENTER")
  self.frame = frame

  local frameBG = frame:CreateTexture("CDTGFrameBG", "BACKGROUND")
  frameBG:SetColorTexture(0, 0.42, 0, 0.42)
  frameBG:SetWidth(frame:GetWidth())
  frameBG:SetHeight(frame:GetHeight())
  frameBG:SetPoint("CENTER", frame, "CENTER", 0, 0)
  self.frameBG = frameBG

  local text = frame:CreateFontString("CDTGText", "OVERLAY", "GameFontNormal")
  text:SetFont(DefaultFontPath, defaults.profile.fontSize, defaults.profile.fontOutline)
  text:SetText("cdtg")
  self.text = text

  if Masque then
    local icon =  CreateFrame("Button", "CDTGButton", frame)
    icon:EnableMouse(false)
    local iconTexture = icon:CreateTexture("CDTGIcon", "OVERLAY")
    self.masqueGroup = Masque:Group(AppName)
    self.masqueGroup:AddButton(icon, { Icon = iconTexture })
    self.icon = icon
    self.iconTexture = iconTexture
  else
    local icon = frame:CreateTexture("CDTGIcon", "OVERLAY")
    self.icon = icon
    self.iconTexture = icon
  end
  self.iconTexture:SetTexture(Icon)

  self:updateLayout()

  frame:SetScript("OnMouseDown", function(frame, button)
    if button == "LeftButton" then
      if IsControlKeyDown() then
        self.db.profile.locked = true
        self:applySettings()
        return
      end
      self.frame:StartMoving()
      self.isMoving = true
      GameTooltip:Hide()
    elseif button == "RightButton" then
      self:openConfigDialog()
    end
  end)
  frame:SetScript("OnMouseUp", function(frame, button)
    if self.isMoving and button == "LeftButton" then
      self.frame:StopMovingOrSizing()
      self.isMoving = false
      db.point, _, db.relPoint, db.x, db.y = frame:GetPoint()
    end
  end)
  frame:SetScript("OnEnter", function(frame)
    GameTooltip:SetOwner(frame)
    GameTooltip:AddLine(AppName)
    GameTooltip:AddLine(L["|cffeda55fDrag|r to move the frame"])
    GameTooltip:AddLine(L["|cffeda55fControl + Left Click|r to lock frame"])
    GameTooltip:AddLine(L["|cffeda55fRight Click|r to open the configuration window"])
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function(frame)
    GameTooltip:Hide()
  end)
  frame:SetScript("OnUpdate", function(frame, elapsed)
    lastUpdate = lastUpdate + elapsed
    if lastUpdate < updateDelay then return end
    lastUpdate = 0
    self:OnUpdate(elapsed)
  end)
end

function CooldownToGo:mediaUpdate(event, mediaType, key)
  if mediaType == 'font' then
    if key == db.font then
      self:applyFontSettings()
    end
  elseif mediaType == 'sound' then
    if key == db.warnSoundName then
      self.soundFile = LSM:Fetch("sound", db.warnSoundName) or DefaultSoundFile
    end
  end
end

function CooldownToGo:applyFontSettings()
  local dbFontPath
  if LSM then
    dbFontPath = LSM:Fetch("font", db.font, true)
    if not dbFontPath then
      LSM.RegisterCallback(self, "LibSharedMedia_Registered", "mediaUpdate")
      dbFontPath = DefaultFontPath
    end
  else
    dbFontPath = DefaultFontPath
  end
  local fontPath, fontSize, fontOutline = self.text:GetFont()
  fontOutline = fontOutline or ""
  if dbFontPath ~= fontPath or db.fontSize ~= fontSize or db.fontOutline ~= fontOutline then
    self.text:SetFont(dbFontPath, db.fontSize, db.fontOutline)
  end
end

function CooldownToGo:applySettings()
  if not self:IsEnabled() then return end
  if db.locked then
    self:lock()
  else
    self:unlock()
  end
  self.frame:ClearAllPoints()
  self.frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
  self.frame:SetFrameStrata(db.strata)
  self.text:SetTextColor(db.colorR, db.colorG, db.colorB, db.colorA)
  self.icon:SetAlpha(db.colorA)
  if LSM then
    self.soundFile = LSM:Fetch("sound", db.warnSoundName)
    if not self.soundFile then
      LSM.RegisterCallback(self, "LibSharedMedia_Registered", "mediaUpdate")
      self.soundFile = DefaultSoundFile
    end
  else
    self.soundFile = DefaultSoundFile
  end
  self:applyFontSettings()
  if self.masqueGroup then
    self.masqueGroup:ReSkin()
  end
  self:updateLayout()
end

function CooldownToGo:lock()
  self.frame:EnableMouse(false)
  self.frameBG:Hide()
  if isActive then
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
  if LSM then
    LSM:Register("font", "Vera Sans Mono Bold",
      [[Interface\AddOns\]] .. AppName .. [[\fonts\VeraMoBd.ttf]])
    LSM:Register("font", "Vera Sans Mono Bold Oblique",
      [[Interface\AddOns\]] .. AppName .. [[\fonts\VeraMoBI.ttf]])
    LSM:Register("font", "Vera Sans Mono Oblique",
      [[Interface\AddOns\]] .. AppName .. [[\fonts\VeraMoIt.ttf]])
    LSM:Register("font", "Vera Sans Mono",
      [[Interface\AddOns\]] .. AppName .. [[\fonts\VeraMono.ttf]])

    -- The original sound samples are made by pera and acclivity of freesound.org,
    -- I just tailored them a bit. Thanks pera and acclivity!
    LSM:Register("sound", "Pong",
      [[Interface\AddOns\]] .. AppName .. [[\sounds\pong.ogg]])
    LSM:Register("sound", "BeepBeepBeep",
      [[Interface\AddOns\]] .. AppName .. [[\sounds\3beeps.ogg]])
    LSM:Register("sound", "DooDaDee",
      [[Interface\AddOns\]] .. AppName .. [[\sounds\doodadee.ogg]])
  end
  self.db = LibStub("AceDB-3.0"):New("CooldownToGoDB", defaults)
  if LibDualSpec then
    LibDualSpec:EnhanceDatabase(self.db, AppName)
  end
  self.db.RegisterCallback(self, "OnProfileChanged", "profileChanged")
  self.db.RegisterCallback(self, "OnProfileCopied", "profileChanged")
  self.db.RegisterCallback(self, "OnProfileReset", "profileChanged")
  db = self.db.profile
  updateIgnoredSpells(db.ignoreLists.spell)
  if not self.frame then
    self:createFrame()
  end
  self:applySettings()
  self:loadOptions()
  self:setupLDB()
  if not self.db.profile.locked then
    self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
      if not self.db.profile.locked then
        self:toggleLocked(true)
      end
    end)
  end
end

function CooldownToGo:OnEnable(first)
  self:SecureHook("UseAction", "checkActionCooldown")
  self:SecureHook("UseContainerItem", "checkContainerItemCooldown")
  self:SecureHook("UseInventoryItem", "checkInventoryItemCooldown")
  self:SecureHook("UseItemByName", "checkItemCooldown")
  self:SecureHook("CastSpellByName", "checkSpellCooldown") -- only needed for pet spells
  self:SecureHook("CastPetAction", "checkPetActionCooldown")
  self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "updateCooldown")
  self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", "updateCooldown")
  self:RegisterEvent("BAG_UPDATE_COOLDOWN", "updateCooldown")
  self:RegisterEvent("PET_BAR_UPDATE_COOLDOWN", "updateCooldown")
  self:RegisterEvent("UNIT_SPELLCAST_FAILED") -- FIXME: RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player", "pet")
  self:applySettings()
end

function CooldownToGo:OnDisable()
  if self.frame then
    self.frame:Hide()
  end
  self:UnhookAll()
  self:UnregisterAllEvents()
end

function CooldownToGo:profileChanged()
  db = self.db.profile
  updateIgnoredSpells(db.ignoreLists.spell)
  self:applySettings()
end

function CooldownToGo:OnUpdate(elapsed)
  if not isActive then
    return
  end
  if needUpdate then
    needUpdate = false
    local start, duration = currGetCooldown(currArg)
    if currStart ~= start or currDuration ~= duration then
      self:updateStamps(start, duration, false)
    end
  end
  local now = GetTime()
  if now > finishStamp then
    if db.locked then
      self.frame:Hide()
    end
    isActive = false
    self.text:SetText(nil)
    self.iconTexture:SetTexture(nil)
    self:updateCooldown() -- check lastGetCooldown, lastArg
    return
  end
  if now >= endStamp then
    if not isReady then
      isReady = true
      if not db.suppressReadyNotif then
        self.text:SetText(L["Ready"])
        self:updateStamps(currStart, currDuration, true)
      end
    end
  else
    local cd = endStamp - now
    if cd <= db.readyTime and not isAlmostReady then
      isAlmostReady = true
      if not db.suppressReadyNotif then
        self:updateStamps(currStart, currDuration, true)
        if db.warnSound and (now - soundPlayedAt) > db.readyTime then
          PlaySoundFile(self.soundFile)
          soundPlayedAt = now
        end
      end
    end
    if cd > 90 then
      self.text:SetFormattedText("%2d:%02d", cd / 60, cd % 60)
    else
      self.text:SetFormattedText("%4.1f", cd)
    end
  end
  if isHidden or not db.locked then
    return
  end
  if now > fadeStamp then
    local alpha = 1 - ((now - fadeStamp) / db.fadeTime)
    if alpha <= 0 then
      isHidden = true
      self.frame:SetAlpha(0)
      updateDelay = NormalUpdateDelay
    else
      self.frame:SetAlpha(alpha)
      updateDelay = FadingUpdateDelay
    end
  end
end

function CooldownToGo:updateStamps(start, duration, show, startHidden)
  if not start then
    return
  end
  currStart = start
  currDuration = duration
  local now = GetTime()
  endStamp = start + duration
  if endStamp < now then
    endStamp = now
  end
  if now + db.holdTime >= endStamp then
    fadeStamp = endStamp
  else
    fadeStamp = now + db.holdTime
  end
  if db.suppressReadyNotif then
    finishStamp = endStamp
  else
    finishStamp = endStamp + db.fadeTime
  end
  hideStamp = fadeStamp + db.fadeTime

  lastUpdate = NormalUpdateDelay -- to force update in next frame
  isAlmostReady = false
  isHidden = false
  if show then
    updateDelay = NormalUpdateDelay
    self.frame:Show()
    if startHidden then
      isHidden = true
      self.frame:SetAlpha(0)
    else
      self.frame:SetAlpha(1)
    end
  end
end

function CooldownToGo:showCooldown(texture, getCooldownFunc, arg, hasCooldown)
  -- printf("### showCooldown: texture: %s, arg: %s", texture, arg)
  local start, duration, enabled = getCooldownFunc(arg)
  -- print("### " .. tostring(texture) .. ", " .. tostring(start) .. ", " .. tostring(duration) .. ", " .. tostring(enabled))
  if not start or enabled ~= 1 or duration <= GCD then
    if hasCooldown and (isReady or not isActive) then
      lastTexture, lastGetCooldown, lastArg = texture, getCooldownFunc, arg
    end
    return
  end
  if GetTime() - start < db.gracePeriod then
    return
  end
  currGetCooldown, currArg = getCooldownFunc, arg
  isActive = true
  isReady = false
  isAlmostReady = false
  self.iconTexture:SetTexture(texture)
  self:updateStamps(start, duration, true)
end

function CooldownToGo:checkActionCooldown(slot)
  local type, id, subtype = GetActionInfo(slot)
  -- printf("### action: %s, type=%s, id=%s, subtype=%s", tostring(slot), tostring(type), tostring(id), tostring(subtype))
  if type == 'spell' then
    self:checkSpellCooldown(id)
  elseif type == 'item' then
    self:checkItemCooldown(id)
  end
end

local function findPetActionIndexForSpell(spell)
  if not spell then return end
  -- printf("### findPetActionIndexForSpell(%s)", tostring(spell))
  for i = 1, NUM_PET_ACTION_SLOTS do
    local name, sub, _, isToken = GetPetActionInfo(i)
    if isToken then name = _G[name] end
    -- printf("### %s: name: %s, sub: %s, isToken: %s", tostring(i), tostring(name), tostring(sub), tostring(isToken))
    if name == spell then
      return i
    end
  end
end

function CooldownToGo:checkSpellCooldown(spell)
  -- print("### spell: " .. tostring(spell))
  if not spell then return end
  local name, _, texture = GetSpellInfo(spell)
  if not name then
     return self:checkPetActionCooldown(findPetActionIndexForSpell(spell))
  end
  if self.ignoreNext then
    self.ignoreNext = nil
    local link = GetSpellLink(spell)
    self:setIgnoredState(link, true)
    return
  end
  if db.reverseIgnoreLogic then
    if not ignoredSpells[name] then return end
  else
    if ignoredSpells[name] then return end
  end
  local baseCooldown = GetSpellBaseCooldown(spell)
  self:showCooldown(texture, GetSpellCooldown, spell, (baseCooldown and baseCooldown > 0))
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
  if not item then return end
  local _, itemLink, _, _, _, _, _, _, _, texture = GetItemInfo(item)
  local itemId = itemIdFromLink(itemLink)
  if not itemId then return end
  if self.ignoreNext then
    self.ignoreNext = nil
    self:setIgnoredState(itemLink, true)
    return
  end
  if db.reverseIgnoreLogic then
    if not db.ignoreLists.item[itemId] then return end
  else
    if db.ignoreLists.item[itemId] then return end
  end
  self:showCooldown(texture, GetItemCooldown, itemId)
end

function CooldownToGo:checkPetActionCooldown(index)
  -- print("### checkPetActionCooldown: " .. tostring(index))
  if not index then return end
  if self.ignoreNext then
    self.ignoreNext = nil
    self:setIgnoredState('petbar:' .. tostring(index), true)
    return
  end
  if db.reverseIgnoreLogic then
    if not db.ignoreLists.petbar[index] then return end
  else
    if db.ignoreLists.petbar[index] then return end
  end
  local _, _, texture, _, _, _, _, spellId = GetPetActionInfo(index)
  if spellId then
    self:checkSpellCooldown(spellId)
  else
    self:showCooldown(texture, GetPetActionCooldown, index)
  end
end

function CooldownToGo:UNIT_SPELLCAST_FAILED(event, unit, name, rank, seq, id)
  -- print("### unit: " .. tostring(unit) .. ", name: " .. tostring(name) .. ", rank: " .. tostring(rank) .. ", seq: " .. tostring(seq) .. ", id: " .. tostring(id))
  if unit == 'player' or unit == 'pet' then
    self:checkSpellCooldown(id)
  end
end

function CooldownToGo:updateCooldown(event)
  -- printf("### updateCooldown: %s", tostring(event))
  if not isActive then
    if lastGetCooldown then
      local start, duration, enabled = lastGetCooldown(lastArg)
      if not start or enabled ~= 1 or duration <= GCD then
        return
      end
      currGetCooldown, currArg = lastGetCooldown, lastArg
      lastGetCooldown = nil
      isActive = true
      isReady = false
      isAlmostReady = false
      self.iconTexture:SetTexture(lastTexture)
      self:updateStamps(start, duration, true, true)
      self.frame:SetAlpha(0)
    end
    return
  end
  if isReady then
    return
  end
  needUpdate = true
end

function CooldownToGo:notifyIgnoredChange(text, flag)
  if not text then return end
  if flag then
    self:printf(L["added %s to ignore list"], text)
  else
    self:printf(L["removed %s from ignore list"], text)
  end
  if self.updateIgnoreListOptions then
    self:updateIgnoreListOptions()
  end
end

function CooldownToGo:setIgnoredState(link, flag)
  if not flag then flag = nil end
  if spellIdFromLink(link) then
    local id = spellIdFromLink(link)
    if not id then return end
    local spell = GetSpellInfo(id)
    if not spell then return end
    local oldId = ignoredSpells[spell]
    if oldId then -- avoid dups
      db.ignoreLists.spell[oldId] = nil
      ignoredSpells[spell] = nil
    end
    db.ignoreLists.spell[id] = flag
    if flag then
      ignoredSpells[spell] = id
    end
    link = GetSpellLink(id) -- to make notify() nicer in case we got only a pseudo-link (just "spell:id")
    self:notifyIgnoredChange(link, flag)
  elseif itemIdFromLink(link) then
    local id = itemIdFromLink(link)
    if not id then return end
    db.ignoreLists.item[id] = flag
    _, link = GetItemInfo(id) -- to make notify() nicer in case we got only a pseudo-link (just "item:id")
    self:notifyIgnoredChange(link, flag)
  elseif petActionIndexFromLink(link) then
    local id = petActionIndexFromLink(link)
    if not id then return end
    db.ignoreLists.petbar[id] = flag
    local text, _, _, isToken = GetPetActionInfo(id)
    text = isToken and _G[text] or text
    if text then
       text = text .. '[' .. tostring(id) .. ']'
    else
       text = 'petbar:' .. tostring(id)
    end
    self:notifyIgnoredChange(text, flag)
  end
end

function CooldownToGo:toggleLocked(flag)
  if flag == nil
     then flag = not self.db.profile.locked
  end
  if flag == not self.db.profile.locked then
    self.db.profile.locked = flag
    self:notifyOptionsChange()
    self:applySettings()
  end
end

function CooldownToGo:setupLDB()
  local ldb = {
    type = "launcher",
    icon = Icon,
    OnClick = function(frame, button)
      if button == "LeftButton" then
        if IsShiftKeyDown() then
          self:ignoreNextAction()
        else
          self:toggleLocked()
        end
      elseif button == "RightButton" then
        self:openConfigDialog()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine(self.AppName)
      tt:AddLine(L["|cffeda55fLeft Click|r to lock/unlock frame"])
      tt:AddLine(L["|cffeda55fShift + Left Click|r to ignore next action"])
      tt:AddLine(L["|cffeda55fRight Click|r to open the configuration window"])
    end,
  }
  LDB:NewDataObject(self.AppName, ldb)
end

function CooldownToGo:ignoreNextAction()
  self:printf(L["Next action will be added to ignore list"])
  self.ignoreNext = true
end

function CooldownToGo:printf(fmt, ...)
  fmt = "|cff33ff99" .. AppName .. "|r: " .. fmt
  print(fmt:format(...))
end

-- Stubs for CooldownToGo_Options

function CooldownToGo:notifyOptionsChange()
end

-- BEGIN LoD Options muckery

function CooldownToGo:loadOptions()
  self.optionsLoaded, self.optionsLoadError = LoadAddOn(OptionsAppName)
end

function CooldownToGo:openConfigDialog()
  -- this function will be overwritten by the Options module when loaded
  print(OptionsAppName .. " not loaded: " .. tostring(self.optionsLoadError))
  self.openConfigDialog = function() end
end

-- END LoD Options muckery


-- register slash command

SLASH_COOLDOWNTOGO1 = "/cooldowntogo"
SLASH_COOLDOWNTOGO2 = "/cdtg"
SlashCmdList["COOLDOWNTOGO"] = function(msg)
  msg = strtrim(msg or "")
  local _, _, cmd, param = msg:find("(%a*)%s*(.*)")
  cmd = cmd and cmd:lower()
  if cmd == "locked" then
    CooldownToGo:toggleLocked()
  elseif cmd == "ignorenext" then
    CooldownToGo:ignoreNextAction()
  elseif cmd == "ignore" then
    CooldownToGo:setIgnoredState(param, true)
  elseif cmd == "remove" then
    CooldownToGo:setIgnoredState(param, false)
  else
    CooldownToGo:openConfigDialog()
  end
end

-- CONFIGMODE

CONFIGMODE_CALLBACKS = CONFIGMODE_CALLBACKS or {}
CONFIGMODE_CALLBACKS[AppName] = function(action)
  if action == "ON" then
     CooldownToGo:toggleLocked(false)
  elseif action == "OFF" then
     CooldownToGo:toggleLocked(true)
  end
end
