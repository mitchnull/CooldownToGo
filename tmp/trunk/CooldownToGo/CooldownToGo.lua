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

local AceConfig = LibStub("AceConfig-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(AppName)
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
local isHidden

local GCD = 1.5

CooldownToGo = LibStub("AceAddon-3.0"):NewAddon(AppName, "AceConsole-3.0", "AceHook-3.0", "AceEvent-3.0")
CooldownToGo:SetDefaultModuleState(false)

local Fonts = SML and SML:List("font") or { [1] = DefaultFontName }

local function getFonts()
	local res = {}
	for i, v in ipairs(Fonts) do
		res[v] = v
	end
	return res
end

local FontOutlines = {
	[""] = L["None"],
	["OUTLINE"] = L["Normal"],
	["THICKOUTLINE"] = L["Thick"],
}

local FrameStratas = {
	["HIGH"] = L["High"],
	["MEDIUM"] = L["Medium"],
	["LOW"] = L["Low"],
}

local defaults = {
	profile = {
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
		y = 0,
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

local options = {
	type = "group",
	name = AppName,
	handler = CooldownToGo,
	get = function(info) return db[info[#info]] end,
	set = "setOption",
	args = {
		locked = {
			type = 'toggle',
			name = L["Locked"],
			desc = L["Lock/Unlock display frame"],
			order = 110,
		},
		holdTime = {
			type = 'range',
			name = L["Hold time"],
			desc = L["Time to hold the message in seconds"],
			min = 0.0,
			max = 5.0,
			step = 0.5,
			order = 120,
		},
		fadeTime = {
			type = 'range',
			name = L["Fade time"],
			desc = L["Fade time of the message in seconds"],
			min = 0.0,
			max = 5.0,
			step = 0.5,
			order = 125,
		},
		readyTime = {
			type = 'range',
			name = L["Ready time"],
			desc = L["Show the cooldown again this many seconds before the cooldown expires"],
			min = 0.0,
			max = 1.0,
			step = 0.1,
			order = 130,
		},
		font = {
			type = 'select',
			name = L["Font"],
			desc = L["Font"],
			values = getFonts,
			order = 135
		},
		fontSize = {
			type = 'range',
			name = L["Font size"],
			desc = L["Font size"],
			min = MinFontSize,
			max = MaxFontSize,
			step = 1,
			order = 140,
		},
		fontOutline = {
			type = 'select',
			name = L["Font outline"],
			desc = L["Font outline"],
			values = FontOutlines,
			order = 150,
		},
		color = {
			type = 'color',
			name = L["Color"],
			desc = L["Color"],
			set = "setColor",
			get = function() return db.colorR, db.colorG, db.colorB end,
			order = 115,
		},
		strata = {
			type = 'select',
			name = L["Strata"],
			desc = L["Frame strata"],
			values = FrameStratas,
			order = 170,
		},
		config = {
			type = 'execute',
			name = L["Configure"],
			desc = L["Bring up GUI configure dialog"],
			guiHidden = true,
			order = 300,
			func = function() CooldownToGo:OpenConfigDialog() end,
		},
	},
}


function CooldownToGo:OpenConfigDialog()
	local f = ACD.OpenFrames[AppName]
	ACD:Open(AppName)
	if not f then
		f = ACD.OpenFrames[AppName]
		f:SetWidth(400)
		f:SetHeight(600)
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

function CooldownToGo:setOption(info, value)
	db[info[#info]] = value
	self:applySettings()
end

function CooldownToGo:setColor(info, r, g, b)
	db.colorR, db.colorG, db.colorB = r, g, b
	if (self:IsEnabled()) then
		self.text:SetTextColor(db.colorR, db.colorG, db.colorB)
	end
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
	local dbFontPath = SML and SML:Fetch("font", db.font) or DefaultFontPath
	local fontPath, fontSize, fontOutline = self.text:GetFont()
	fontOutline = fontOutline or ""
	if (dbFontPath ~= fontPath or db.fontSize ~= fontSize or db.fontOutline ~= fontOutline) then
		self.text:SetFont(dbFontPath, db.fontSize, db.fontOutline)
	end
	self.text:SetTextColor(db.colorR, db.colorG, db.colorB)
	self.icon:SetHeight(fontSize)
	self.icon:SetWidth(fontSize)
end

function CooldownToGo:lock()
	self.frame:EnableMouse(false)
	self.frameBG:Hide()
	if (not isActive) then
		self.frame:Hide()
	end
end

function CooldownToGo:unlock()
	self.frame:EnableMouse(true)
	self.frameBG:Show()
	self.frame:Show()
end

function CooldownToGo:addConfigTab(key, group, order, isCmdInline)
	if (not self.configOptions) then
		self.configOptions = {
			type = "group",
			name = AppName,
			childGroups = "tab",
			args = {},
		}
	end
	self.configOptions.args[key] = group
	self.configOptions.args[key].order = order
	self.configOptions.args[key].cmdInline = isCmdInline
end

function CooldownToGo:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("CooldownToGoDB", defaults)
	db = self.db.profile
	self:addConfigTab('main', options, 10, true)
	self:addConfigTab('profiles', AceDBOptions:GetOptionsTable(self.db), 20, false)
	AceConfig:RegisterOptionsTable(AppName, self.configOptions, "cdtg")
	ACD:AddToBlizOptions(AppName)
	if (not self.frame) then
		self:createFrame()
	end
end

function CooldownToGo:OnEnable(first)
	self:OnProfileEnable()
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

function CooldownToGo:OnProfileEnable()
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
		isActive = false
		if (db.locked) then
			self.frame:Hide()
		end
		return
	end
	if (now >= endStamp) then
		if (not isReady) then
			isReady = true
			self.text:SetText(L["Ready"])
			self:updateStamps(currStart, currDuration, true)
--	TODO:	PlaySound()
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
--	print("### spellIdx: " .. tostring(spellIdx))
	local texture = GetSpellTexture(spellIdx, bookType)
	self:showCooldown(texture, GetSpellCooldown, spellIdx, bookType)
end

function CooldownToGo:checkSpellCooldownByName(spellName)
--	print("### spellName: " .. tostring(spellName))
	local texture = GetSpellTexture(spellName)
	self:showCooldown(texture, GetSpellCooldown, spellName, nil)
end

function CooldownToGo:ckeckActionCooldown(slot)
--	print("### action: " .. tostring(slot))
	local texture = GetActionTexture(slot)
	self:showCooldown(texture, GetActionCooldown, slot, nil)
end

function CooldownToGo:ckeckInventoryItemCooldown(item)
--	print("### invItem: " .. tostring(item))
	local texture = GetInventoryItemTexture("player", item)
	self:showCooldown(texture, GetInventoryItemCooldown, "player", item)
end

function CooldownToGo:ckeckContainerItemCooldown(bagId, bagSlot)
--	print("### containerItem: " .. tostring(bagId), .. ", " .. tostring(bagSlot))
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
