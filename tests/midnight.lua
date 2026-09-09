-- Run from the CooldownToGo directory: lua tests/midnight.lua
-- WoW-facing doubles supply opaque timers; the addon logic is loaded unchanged.
local now, sounds = 100, 0
local secret = setmetatable({}, {
  __add = function() error('secret arithmetic') end,
  __sub = function() error('secret arithmetic') end,
  __lt = function() error('secret comparison') end,
  __le = function() error('secret comparison') end,
})
local durations, states, gcd = {}, {}, {}
local function region()
  local r = { shown = true, alpha = 1, scripts = {}, font = {'font', 24, ''} }
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:SetAlpha(a) self.alpha = a end
  function r:SetText(t) self.text = t end
  function r:SetFormattedText(...) error('Modern countdown must be rendered natively') end
  function r:SetTexture(t) self.texture = t end
  function r:SetFont(...) self.font = {...} end
  function r:GetFont() return table.unpack(self.font) end
  function r:SetScript(n, f) self.scripts[n] = f end
  function r:GetWidth() return 120 end
  function r:GetHeight() return 30 end
  function r:CreateTexture() return region() end
  function r:CreateFontString() return region() end
  function r:GetCountdownFontString() self.counter = rawget(self, 'counter') or region(); return self.counter end
  function r:SetCooldownFromDurationObject(d) self.durationObject = d end
  function r:Clear() self.durationObject = nil; if self.scripts.OnCooldownDone then self.scripts.OnCooldownDone(self) end end
  return setmetatable(r, {__index = function() return function() end end})
end
UIParent = region()
GameFontNormal = region()
CreateFrame = function() return region() end
GetTime = function() return now end
PlaySoundFile = function() sounds = sounds + 1 end
issecretvalue = function(v) return v == secret end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
SlashCmdList = {}
NUM_PET_ACTION_SLOTS = 10
local petActions = {}
GetPetActionInfo = function(index)
  local action = petActions[index]
  if action then return table.unpack(action, 1, 9) end
end
C_SpellBook = {}
local itemSecret = false
C_Container = {GetItemCooldown = function() if itemSecret then return secret, secret, secret end; return 100, 20, 1 end}
C_Item = {GetItemInfo = function() return 'Item', 'item:1', nil,nil,nil,nil,nil,nil,nil,123 end, UseItemByName = function() end}
C_AddOns = {LoadAddOn = function() return false end}
C_Spell = {
  GetSpellInfo = function(id) return {name = 'Spell' .. id, iconID = id, spellID = id} end,
  GetSpellLink = function(id) return 'spell:' .. id end,
  GetSpellCooldown = function(id) return {isActive = states[id], isOnGCD = gcd[id] or false, startTime = secret, duration = secret, isEnabled = secret, modRate = secret} end,
  GetSpellCooldownDuration = function(id, ignoreGCD) assert(ignoreGCD, 'Must exclude GCD'); return durations[id] end,
}
local addon = {}
function addon:IsEnabled() return self.enabled ~= false end
function addon:SetDefaultModuleState() end
function addon:SecureHook() end
function addon:UnhookAll() end
function addon:RegisterEvent() end
function addon:UnregisterAllEvents() end
local function copy(t) local r = {}; for k,v in pairs(t) do r[k] = type(v) == 'table' and copy(v) or v end; return r end
local libraries = {
  ['AceAddon-3.0'] = {NewAddon = function() return addon end},
  ['AceLocale-3.0'] = {GetLocale = function() return setmetatable({}, {__index = function(_,k) return k end}) end},
  ['AceDB-3.0'] = {New = function(_,_,defaults) return {profile = copy(defaults.profile), RegisterCallback = function() end} end},
  ['LibDataBroker-1.1'] = {NewDataObject = function() end},
}
LibStub = setmetatable({GetLibrary = function(_,name) return libraries[name] end}, {__call = function(_,name) return libraries[name] end})
dofile('CooldownToGo.lua')
addon:OnInitialize()
addon:OnEnable()
addon.db.profile.locked = true
addon:applySettings()
local function failSpell(id)
  states[id] = true
  durations[id] = {opaque = id}
  addon:UNIT_SPELLCAST_FAILED('UNIT_SPELLCAST_FAILED', 'player', 'cast', id)
  addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
end
failSpell(42)
assert(addon.cooldown and addon.cooldown.durationObject == durations[42], 'Failed spell must bind opaque duration to native cooldown')
addon:OnUpdate(0.2)
addon:applySettings()
assert(addon.frame.shown, 'Active failed spell must show frame')
assert(not addon.text.shown, 'Legacy text must not overlap native counter')
now = 104
addon:OnUpdate(0.2)
assert(addon.frame.alpha == 0, 'Attempt display must fade using public elapsed time')
states[42] = false
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
addon:OnUpdate(0.2)
assert(addon.text.text == 'Ready' and addon.text.shown, 'Cooldown state transition must show Ready')
assert(sounds == 1, 'Ready must sound exactly once')
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
addon:OnUpdate(0.2)
assert(sounds == 1, 'Repeated updates must not repeat Ready sound')
failSpell(43)
states[42] = false
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
assert(addon.cooldown.durationObject == durations[43], 'Replacement must retain newest cooldown')
addon:OnDisable()
states[43] = false
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
addon:OnUpdate(0.2)
assert(not addon.frame.shown and sounds == 1, 'Disabled addon must ignore pending completion')
addon.enabled = true
addon:OnEnable()
now = 110
addon:UNIT_SPELLCAST_SUCCEEDED('UNIT_SPELLCAST_SUCCEEDED', 'player', 'cast', 44)
failSpell(44)
assert(not addon.frame.shown, 'Grace window after own successful cast must suppress button smashing')
now = 111
failSpell(44)
assert(addon.frame.shown, 'Failed cast after grace window must display')
addon.db.profile.ignoreLists.spell[45] = true
addon:profileChanged()
failSpell(45)
assert(addon.cooldown.durationObject == durations[44], 'Ignored spell must not replace current countdown')
addon:OnDisable()
addon:OnEnable()
states[46], durations[46], gcd[46] = true, {}, true
addon:checkSpellCooldown(46)
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
addon:UNIT_SPELLCAST_FAILED('UNIT_SPELLCAST_FAILED', 'player', 'cast', 46)
assert(not addon.frame.shown, 'Known GCD-only state must not show a blank icon')
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
assert(not addon.frame.shown, 'GCD-only failure must not show blank icon or announce Ready')
states[46] = false
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
assert(sounds == 1, 'GCD completion must not sound')
failSpell(47)
gcd[47] = true
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
assert(addon.text.text == 'Ready' and sounds == 2, 'Real cooldown ending during GCD must announce Ready')
addon:OnDisable()
addon:OnEnable()
states[48], durations[48] = true, {}
addon:checkSpellCooldown(48)
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
assert(not addon.frame.shown, 'Successful secure action hook must not show cooldown')
addon.db.profile.fadeTime = 0
addon.db.profile.holdTime = 0
failSpell(49)
addon:OnUpdate(0.2)
assert(addon.frame.alpha == 0, 'Zero fade must not divide by zero')
states[49] = false
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
addon:OnUpdate(0.2)
assert(not addon.frame.shown, 'Zero fade Ready must finish cleanly')
addon.db.profile.suppressReadyNotif = true
failSpell(50)
local soundsBefore = sounds
states[50] = false
addon:updateCooldown('SPELL_UPDATE_COOLDOWN')
addon:OnUpdate(0.2)
assert(sounds == soundsBefore and not addon.frame.shown, 'Suppressed Ready must neither sound nor reshow')
addon.db.profile.suppressReadyNotif = false
addon.db.profile.fadeTime = 2
addon.db.profile.holdTime = 1
itemSecret = true
addon:checkItemCooldown(1)
assert(not addon.frame.shown, 'Restricted item values must be skipped safely')
itemSecret = false
addon:checkItemCooldown(1)
assert(addon.frame.shown and addon.text.shown and not addon.cooldown.shown, 'Public item cooldown must retain legacy display')
failSpell(51)
assert(addon.cooldown.shown and not addon.text.shown, 'Spell must replace legacy item display cleanly')
addon:UNIT_SPELLCAST_SUCCEEDED('UNIT_SPELLCAST_SUCCEEDED', 'player', 'cast', 52)
states[52], durations[52] = true, {}
addon:UNIT_SPELLCAST_FAILED('UNIT_SPELLCAST_FAILED', 'pet', 'cast', 52)
assert(addon.cooldown.durationObject == durations[52], 'Player success must not suppress pet spell failure')
petActions[1] = {'Spell53', 53, false, true, false, false, 53, false, true}
addon.db.profile.ignoreLists.petbar[1] = true
states[53], durations[53] = true, {}
addon:checkPetActionCooldown(1)
addon:UNIT_SPELLCAST_FAILED('UNIT_SPELLCAST_FAILED', 'pet', 'cast', 53)
assert(addon.cooldown.durationObject == durations[52], 'Ignored petbar slot must block failed pet spell event')
addon.db.profile.ignoreLists.petbar[1] = nil
addon.ignoreNext = true
addon:UNIT_SPELLCAST_FAILED('UNIT_SPELLCAST_FAILED', 'pet', 'cast', 53)
assert(not addon.ignoreNext and addon.db.profile.ignoreLists.petbar[1], 'Pet failure must consume Ignore Next on its slot')
assert(not addon.db.profile.ignoreLists.spell[53], 'Pet Ignore Next must not also consume spell ignore')
addon.db.profile.reverseIgnoreLogic = true
addon.db.profile.ignoreLists.spell[53] = true
addon:profileChanged()
addon:UNIT_SPELLCAST_FAILED('UNIT_SPELLCAST_FAILED', 'pet', 'cast', 53)
assert(addon.cooldown.durationObject == durations[53], 'Reverse ignore mode must allow listed pet slot and spell')
addon.db.profile.ignoreLists.petbar[1] = nil
local displayedPetDuration = durations[53]
durations[53] = {}
addon:UNIT_SPELLCAST_FAILED('UNIT_SPELLCAST_FAILED', 'pet', 'cast', 53)
assert(addon.cooldown.durationObject == displayedPetDuration, 'Unlisted slot in reverse mode must preserve existing display')
addon.db.profile.reverseIgnoreLogic = false
CDTG_PET_SPELL54 = 'Spell54'
petActions[2] = {'CDTG_PET_SPELL54', 5400, true, false, false, false, 54}
addon.db.profile.ignoreLists.petbar[2] = true
states[54], durations[54] = true, {}
addon:UNIT_SPELLCAST_FAILED('UNIT_SPELLCAST_FAILED', 'pet', 'cast', 54)
assert(addon.cooldown.durationObject == displayedPetDuration, 'Token-named Retail pet action must resolve slot ignore')
local petName, _, petTexture, petIsToken, _, _, _, petSpellID = addon.GetPetActionInfo(2)
assert(petName == 'CDTG_PET_SPELL54' and petTexture == 5400 and petIsToken and petSpellID == 54, 'Shared options adapter must preserve Retail pet name, texture, token and spell ID')
print('PASS: Midnight opaque countdown, ready, fade, replacement, disable, grace, ignore list')
