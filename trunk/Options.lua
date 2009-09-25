local CooldownToGo = CooldownToGo
local AceConfig = LibStub("AceConfig-3.0")
local ACD = LibStub("AceConfigDialog-3.0")
local ACR = LibStub("AceConfigRegistry-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(CooldownToGo.AppName)
local SML = LibStub:GetLibrary("LibSharedMedia-3.0", true)
local LibDualSpec = LibStub("LibDualSpec-1.0", true)
local LDB = LibStub:GetLibrary("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0", true)

local Icon = [[Interface\Icons\Ability_Hunter_Readiness]]
local MinFontSize = 5
local MaxFontSize = 240
local DefaultFontName = "Friz Quadrata TT"

local _

local LinkPattern = '(%l+):(%d+)'

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
                gracePeriod = {
                    type = 'range',
                    name = L["Grace Period"],
                    desc = L["Delay before cooldown display is activated (useful for button-smashers)"],
                    min = 0.0,
                    max = 1.0,
                    step = 0.05,
                    order = 131,
                },
                warnSound = {
                    type = 'toggle',
                    name = L["Warning Sound"],
                    desc = L["Play a sound when the cooldown reaches Ready Time"],
                    order = 132,
                },
                warnSoundName = {
                    type = "select", dialogControl = 'LSM30_Sound',
                    disabled = function() return not CooldownToGo.db.profile.warnSound end,
                    name = L["Warning Sound Name"],
                    values = AceGUIWidgetLSMlists.sound,
                    order = 133,
                },
                font = {
                    type = "select", dialogControl = 'LSM30_Font',
                    name = L["Font"],
                    desc = L["Font"],
                    values = AceGUIWidgetLSMlists.font,
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
                    hasAlpha = true,
                    name = L["Color"],
                    desc = L["Color"],
                    set = "setColor",
                    get = "getColor",
                    order = 190,
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
                    func = function() CooldownToGo:openConfigDialog() end,
                },
            },
        },
        ignoreLists = {
            type = 'group',
            childGroups = 'tab',
            inline = true,
            name = L["Ignore list"],
            handler = CooldownToGo,
            order = 50,
            args = {
                ignoreNext = {
                    type = 'execute',
                    name = L["Ignore next action"],
                    order = 10,
                    func = "ignoreNextAction",
                },
                ignore = {
                    type = 'input',
                    guiHidden = 'true',
                    name = L["Ignore"],
                    desc = L["Spell link, item link or petbar:index"],
                    order = 20,
                    pattern = LinkPattern,
                    get = function() return nil end,
                    set = "ignoreByLink",
                },
                remove = {
                    type = 'input',
                    name = L["Remove"],
                    desc = L["Spell link, item link or petbar:index"],
                    guiHidden = 'true',
                    order = 30,
                    pattern = LinkPattern,
                    get = function() return nil end,
                    set = "removeByLink",
                },
                spell = {
                    type = 'group',
                    inline = true,
                    name = L["Spells"],
                    cmdHidden = true,
                    order = 120,
                    args = {},
                },
                item = {
                    type = 'group',
                    inline = true,
                    name = L["Items"],
                    cmdHidden = true,
                    order = 130,
                    args = {},
                },
                petbar = {
                    type = 'group',
                    inline = true,
                    name = L["Petbar"],
                    cmdHidden = true,
                    order = 140,
                    args = {},
                },
            },
        },
    },
}

function CooldownToGo:registerSubOptions(name, opts)
    local appName = self.AppName .. "." .. name
    AceConfig:RegisterOptionsTable(appName, opts)
    return ACD:AddToBlizOptions(appName, opts.name or name, self.AppName)
end

function CooldownToGo:setupOptions()
    self:setupLDB()
    AceConfig:RegisterOptionsTable(self.AppName, options.args.main)
    self.opts = ACD:AddToBlizOptions(self.AppName, self.AppName)
    self:updateIgnoreListOptions()
    self.ignoreListOpts = self:registerSubOptions('ignoreLists', options.args.ignoreLists)
    local profiles = AceDBOptions:GetOptionsTable(self.db)
    if LibDualSpec then
        LibDualSpec:EnhanceOptions(profiles, self.db)
    end
    profiles.order = 900
    options.args.profiles = profiles
    self.profiles = self:registerSubOptions('profiles', profiles)
    AceConfig:RegisterOptionsTable(self.AppName .. '.Cmd', options, {"cdtg", self.AppName:lower()})
end

function CooldownToGo:setupLDB()
    if (not LDB) then return end
    local ldb = {
        type = "launcher",
        icon = Icon,
        OnClick = function(frame, button)
            if (button == "LeftButton") then
                if (IsShiftKeyDown()) then
                    self:ignoreNextAction()
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
            tt:AddLine(L["|cffeda55fShift + Left Click|r to ignore next action"])
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

function CooldownToGo:openConfigDialog()
    InterfaceOptionsFrame_OpenToCategory(self.profiles)
    InterfaceOptionsFrame_OpenToCategory(self.opts)
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
    return db.colorR, db.colorG, db.colorB, db.colorA
end

function CooldownToGo:setColor(info, r, g, b, a)
    local db = self.db.profile
    db.colorR, db.colorG, db.colorB, db.colorA = r, g, b, a
    if (self:IsEnabled()) then
        self.text:SetTextColor(db.colorR, db.colorG, db.colorB, db.colorA)
        self.icon:SetAlpha(db.colorA)
    end
end

function CooldownToGo:notifyOptionsChange()
    ACR:NotifyChange(self.AppName)
    -- for some reason the gui is not updated, the below "flipflop" will make it update
    if (self.ignoreListOpts and InterfaceOptionsFrame:IsShown() and (not self.skipFlipFlop)) then
        InterfaceOptionsFrame_OpenToCategory(self.opts)
        InterfaceOptionsFrame_OpenToCategory(self.ignoreListOpts)
    end
end

local function updateOpts(opts, db, descFunc)
    local changed
    for id, _ in pairs(opts) do
        id = tonumber(id)
        if (not db[id]) then
            opts[tostring(id)] = nil
            changed = true
        end
    end
    for id, flag in pairs(db) do
        if (flag) then
            local description = descFunc(id)
            if (description) then
                opts[tostring(id)] = {
                    type = 'toggle',
                    name = description,
                    get = function() return true end,
                    set = "removeIgnored",
                }
                changed = true
            end
        end
    end
    -- TODO: sort
    return changed
end

local function getSpellDesc(id)
    return GetSpellInfo(id)
end

local function getItemDesc(id)
    return GetItemInfo(id)
end

local function getPetbarDesc(id)
    local text, _, _, isToken = GetPetActionInfo(id)
    text = ((isToken and _G[text] or text) or L['Petbar']) .. '[' .. tostring(id) .. ']'
    return text
end

function CooldownToGo:updateIgnoreListOptions()
    local changed
    changed = updateOpts(options.args.ignoreLists.args.spell.args, self.db.profile.ignoreLists.spell, getSpellDesc) or changed
    changed = updateOpts(options.args.ignoreLists.args.item.args, self.db.profile.ignoreLists.item, getItemDesc) or changed
    changed = updateOpts(options.args.ignoreLists.args.petbar.args, self.db.profile.ignoreLists.petbar, getPetbarDesc) or changed
    if (changed) then
        self:notifyOptionsChange() 
    end
end

function CooldownToGo:ignoreNextAction()
    self:Print(L["Next action will be added to ignore list"])
    self.ignoreNext = true
end

function CooldownToGo:removeIgnored(info)
    local id = info[#info]
    local cat = info[#info - 1]
    self.skipFlipFlop = true -- hack to avoid an AceConfigDialog error
    self:setIgnoredState(cat .. ":" .. id, false)
    self.skipFlipFlop = nil
end

function CooldownToGo:ignoreByLink(info, link)
    return self:setIgnoredState(link, true)
end

function CooldownToGo:removeByLink(info, link)
    return self:setIgnoredState(link, false)
end

