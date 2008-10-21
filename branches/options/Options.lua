local AceConfig = LibStub("AceConfig-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(AppName)
local SML = LibStub:GetLibrary("LibSharedMedia-3.0", true)
local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0", true)

local Icon = "Interface\\Icons\\Ability_Hunter_Readiness"

local _

local function getFonts()
    local fonts = SML and SML:List("font") or { [1] = DefaultFontName }
    local res = {}
    for i, v in ipairs(fonts) do
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

local options = {
    type = "group",
    name = AppName,
    handler = CooldownToGo,
    get = "getOption",
    set = "setOption",
    args = {
        main = {
            type = 'group',
            childGroups = 'tab',
            inline = true,
            name = CooldownToGo.AppName,
            handler = CooldownToGo,
            get = "getOption",
            set = "setOption",
            order = 20,
            args = {
                locked = {
                    type = 'toggle',
                    width = 'full',
                    name = L["Locked"],
                    desc = L["Lock/Unlock display frame"],
                    order = 100,
                },
                ignore = {
                    type = 'execute',
                    name = L["Ignore last cooldown"],
                    disabled = "hasLastCooldown",
                    width = 'full',
                    order = 110,
                    func = function() CooldownToGo:OpenConfigDialog() end,
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
        },
    },
}

function RangeDisplay:registerSubOptions(name, opts)
    local appName = self.AppName .. "." .. name
    AceConfig:RegisterOptionsTable(appName, opts)
    return ACD:AddToBlizOptions(appName, opts.name or name, self.AppName)
end

function CooldownToGo:setupOptions()
    self:setupLDB()
    AceConfig:RegisterOptionsTable(self.AppName, options.args.main)
    self.opts = ACD:AddToBlizOptions(self.AppName, self.AppName)
    -- TODO add ignore lists
    local profiles = AceDBOptions:GetOptionsTable(self.db)
    profiles.order = 900
    options.args.profiles = profiles
    self.profiles = self:registerSubOptions('profiles', profiles)
    AceConfig:RegisterOptionsTable(self.AppName .. '.Cmd', options, {"cdtg", self.AppName:lower()})
end

function CooldownToGo:setupLDB()
    if (not LDB) then return end;
    local ldb = {
        type = "launcher",
        icon = Icon,
        OnClick = function(frame, button)
            if (button == "LeftButton") then
                if (SHIFT_PRESEED_TODO) then
                    self:ignoreLastCooldown()
                else
                    self:toggleLocked()
                end
            elseif (button == "RightButton") then
                self:openConfigDialog()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine(self.AppName)
            tt:AddLine(L["|cffeda55fLeft Click|r to lock/unlock frame"])
            tt:AddLine(L["|cffeda55fShift + Left Click|r to ignore last cooldown"])
            tt:AddLine(L["|cffeda55fRight Click|r to open the configuration window"])
        end,
    }
    LDB:NewDataObject(self.AppName, ldb)
    if (not LDBIcon) then return end
    LDBIcon:Register(self.AppName, ldb, self.db.profile.minimap)
    options.args.main.args.minimap = {
        type = 'toggle',
        name = L["Hide minimap icon"],
        width = 'full',
        order = 111,
        get = function() return self.db.profile.minimap.hide end,
        set = function(info, value)
            if (value) then
                LDBIcon:Hide(self.AppName)
            else
                LDBIcon:Show(self.AppName)
            end
            self.db.profile.minimap.hide = value
        end,
    }
end

function CooldownToGo:toggleLocked(flag)
    if (flag == nil) then flag = not self.db.profile.locked end
    if (flag == not self.db.profile.locked) then
        self.db.profile.locked = flag
        self:applySettings()
    end
end

function CooldownToGo:OpenConfigDialog()
    InterfaceOptionsFrame_OpenToCategory(self.profiles)
    InterfaceOptionsFrame_OpenToCategory(self.opts)
end

function CooldownToGo:hasLastCooldown()
    return true -- TODO
end

function CooldownToGo:ignoreLastCooldown()
-- TODO
end

function CooldownToGo:getOption(info)
    return self.db.profile[info[#info]]
end

function CooldownToGo:setOption(info, value)
    self.db.profile[info[#info]] = value
    self:applySettings()
end

function CooldownToGo:getColor(info)
    local db = self.db.profile
    return db.colorR, db.colorG, db.colorB
end

function CooldownToGo:setColor(info, r, g, b)
    local db = self.db.profile
    db.colorR, db.colorG, db.colorB = r, g, b
    if (self:IsEnabled()) then
        self.text:SetTextColor(db.colorR, db.colorG, db.colorB)
    end
end

