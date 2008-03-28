--[[
Name: CooldownToGo
Revision: $Revision$
Author(s): mitch0
Website: 
Documentation: 
SVN: http://svn.wowace.com/wowace/trunk/CooldownToGo/
Description: Display the reamining cooldown on the last action you tried to use
Dependencies:
License: Public Domain
]]

local VERSION = "CooldownToGo-r" .. ("$Revision$"):match("%d+")

local AceConfig = LibStub("AceConfig-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("CooldownToGo")
local AppName = "CooldownToGo"
local SML = LibStub:GetLibrary("LibSharedMedia-3.0", true);
local db

CooldownToGo = LibStub("AceAddon-3.0"):NewAddon("CooldownToGo", "AceConsole-3.0", "AceHook-3.0")
CooldownToGo:SetDefaultModuleState(false)

local MinFontSize = 5
local MaxFontSize = 40
local DefaultFontName = "Friz Quadrata TT"
local DefaultFontPath = GameFontNormal:GetFont()

local Fonts = SML and SML:List("font") or { [1] = DefaultFontName }

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
	name = "CooldownToGo",
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
		font = {
			type = 'select',
			name = L["Font"],
			desc = L["Font"],
			values = Fonts,
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
			order = 160,
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
		f:SetHeight(500)
	end
end

function CooldownToGo:createFrame()
	self.isMoving = false
	local cdtgFrame = CreateFrame("MessageFrame", "CooldownToGoFrame", UIParent)
	cdtgFrame:Hide()
	cdtgFrame:SetFrameStrata(defaults.profile.strata)
	cdtgFrame:EnableMouse(false)
	cdtgFrame:SetClampedToScreen()
	cdtgFrame:SetMovable(true)
	cdtgFrame:SetWidth(120)
	cdtgFrame:SetHeight(30)
	cdtgFrame:SetPoint(defaults.profile.point, UIParent, defaults.profile.relPoint, defaults.profile.x, defaults.profile.y)
	cdtgFrame:SetFont(DefaultFontPath, defaults.profile.fontSize, defaults.profile.fontOutline)
	cdtgFrame:SetJustifyH("CENTER")
	self.cdtgFrame = cdtgFrame

	local cdtgFrameBG = cdtgFrame:CreateTexture("CooldownToGoFrameBG", "BACKGROUND")
	cdtgFrameBG:SetTexture(0, 0, 0, 0.42)
	cdtgFrameBG:SetWidth(cdtgFrame:GetWidth())
	cdtgFrameBG:SetHeight(cdtgFrame:GetHeight())
	cdtgFrameBG:SetPoint("CENTER", cdtgFrame, "CENTER", 0, 0)
	self.cdtgFrameBG = cdtgFrameBG

	cdtgFrame:SetScript("OnMouseDown", function(frame, button)
		if (not button) then
			-- some addon is hooking us but doesn't pass button. argh...
			button = arg1
		end
		if (button == "LeftButton") then
			self.cdtgFrame:StartMoving()
			self.isMoving = true
		elseif (button == "RightButton") then
			self:OpenConfigDialog()
		end
	end)
	cdtgFrame:SetScript("OnMouseUp", function(frame, button)
		if (not button) then
			-- some addon is hooking us but doesn't pass button. argh...
			button = arg1
		end
		if (self.isMoving and button == "LeftButton") then
			self.cdtgFrame:StopMovingOrSizing()
			self.isMoving = false
			db.point, _, db.relPoint, db.x, db.y = cdtgFrame:GetPoint()
		end
	end)
end

function CooldownToGo:setOption(info, value)
	db[info[#info]] = value
	self:applySettings()
end

function CooldownToGo:setColor(info, r, g, b)
	db.colorR, db.colorG, db.colorB = r, g, b
	if (self:IsEnabled()) then
		self.cdtgFrame:SetTextColor(db.colorR, db.colorG, db.colorB)
	end
end

function CooldownToGo:applySettings()
	if (not self:IsEnabled()) then return end
	if (db.locked) then
		self:lock()
	else
		self:unlock()
	end
	self.cdtgFrame:ClearAllPoints()
	self.cdtgFrame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
	self.cdtgFrame:SetFrameStrata(db.strata)
	local dbFontPath = SML and SML:Fetch("font", db.font) or DefaultFontPath
	local fontPath, fontSize, fontOutline = self.cdtgFrame:GetFont()
	fontOutline = fontOutline or ""
	if (dbFontPath ~= fontPath or db.fontSize ~= fontSize or db.fontOutline ~= fontOutline) then
		self.cdtgFrame:SetFont(dbFontPath, db.fontSize, db.fontOutline)
	end
	self.cdtgFrame:SetTextColor(db.colorR, db.colorG, db.colorB)
	self.cdtgFrame:SetTimeVisible(db.holdTime)
	self.cdtgFrame:Show()
end

function CooldownToGo:lock()
	self.cdtgFrame:EnableMouse(false)
	self.cdtgFrameBG:Hide()
end

function CooldownToGo:unlock()
	self.cdtgFrame:EnableMouse(true)
	self.cdtgFrameBG:Show()
end

function CooldownToGo:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("CooldownToGoDB", defaults)
	self.configOptions = options
	AceConfig:RegisterOptionsTable(AppName, options, "cdtg")
	db = self.db.profile
	self:createFrame()
end

function CooldownToGo:OnEnable(first)
	self:OnProfileEnable()
--	self:SecureHook("CastSpell", "checkSpellCooldown")
--	self:SecureHook("CastSpellByName", "checkSpellCooldownByName")
	self:SecureHook("UseAction", "ckeckActionCooldown")
end

function CooldownToGo:OnDisable()
	if (self.cdtgFrame) then
		self.cdtgFrame:Hide()
	end
	self:UnhookAll();
end

function CooldownToGo:OnProfileEnable()
	db = self.db.profile
	self:applySettings()
end

function CooldownToGo:showCooldown(name, start, duration, enabled)
	local GCD = 1.5
--	print("### " .. tostring(name) .. ", " .. tostring(start) .. ", " .. tostring(duration) .. ", " .. tostring(enabled))
	if (not enabled) or (not start) or (not duration) or (duration <= GCD) then return end
	local cd = start + duration - GetTime();
	if cd > 90 then
		self.cdtgFrame:AddMessage(string.format("%d:%02d", cd / 60, cd % 60), db.colorR, db.colorG, db.colorB, 1, db.holdTime)
	else
		self.cdtgFrame:AddMessage(string.format("%.1f", cd), db.colorR, db.colorG, db.colorB, 1, db.holdTime)
	end
end

function CooldownToGo:checkSpellCooldown(spellId, bookType)
--	print("### id: " .. tostring(spellId))
	self:showCooldown(GetSpellName(spellId, bookType), GetSpellCooldown(spellId, bookType))
end

function CooldownToGo:checkSpellCooldownByName(spellName)
--	print("### name: " .. tostring(spellName))
	self:showCooldown(spellName, GetSpellCooldown(spellName))
end

function CooldownToGo:ckeckActionCooldown(slot)
--	print("### slot: " .. tostring(slot))
	self:showCooldown(GetActionText(slot), GetActionCooldown(slot))
end

