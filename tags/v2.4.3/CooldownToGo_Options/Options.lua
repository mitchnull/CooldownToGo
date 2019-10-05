local CooldownToGo = CooldownToGo
local ACD = LibStub("AceConfigDialog-3.0")
local ACR = LibStub("AceConfigRegistry-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale(CooldownToGo.OptionsAppName)
local LibDualSpec = LibStub("LibDualSpec-1.0", true)

local MinFontSize = 5
local MaxFontSize = 240
local MinIconSize = MinFontSize
local MaxIconSize = MaxFontSize
local MinPadding = -100
local MaxPadding = 100
local DefaultFontName = "Friz Quadrata TT"
local Huge = math.huge
local Large = 10000

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

local TextPositions = {
    ["LEFT"] = L["Left"],
    ["RIGHT"] = L["Right"],
    ["TOP"] = L["Top"],
    ["BOTTOM"] = L["Bottom"],
}

local mainOptions = {
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
        --    width = 'full',
            name = L["Locked"],
            desc = L["Lock/Unlock display frame"],
            order = 100,
        },
        holdTime = {
            type = 'range',
            name = L["Hold time"],
            desc = L["Time to hold the message in seconds"],
            min = 0.0,
            softMax = 5.0,
            max = Huge,
            step = 0.5,
            order = 120,
        },
        fadeTime = {
            type = 'range',
            name = L["Fade time"],
            desc = L["Fade time of the message in seconds"],
            min = 0.0,
            softMax = 5.0,
            max = Huge,
            step = 0.5,
            order = 125,
        },
        suppressReadyNotif = {
            type = 'toggle',
        --    width = 'full',
            name = L["Suppress Ready Notification"],
            desc = L["Disable showing the cooldown near the expiry time without user action"],
            order = 127,
        },
        readyTime = {
            type = 'range',
            name = L["Ready time"],
            desc = L["Show the cooldown again this many seconds before the cooldown expires"],
            min = 0.0,
            softMax = 1.0,
            max = Huge,
            step = 0.1,
            disabled = function() return CooldownToGo.db.profile.suppressReadyNotif end,
            order = 130,
        },
        gracePeriod = {
            type = 'range',
            name = L["Grace Period"],
            desc = L["Delay before cooldown display is activated (useful for button-smashers)"],
            min = 0.0,
            softMax = 1.0,
            max = Huge,
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
            softMax = MaxFontSize,
            max = Large,
            step = 1,
            order = 140,
        },
        iconSize = {
            type = 'range',
            name = L["Icon size"],
            desc = L["Icon size"],
            min = MinIconSize,
            softMax = MaxIconSize,
            max = Large,
            step = 1,
            order = 142,
        },
        textPosition = {
            type = 'select',
            name = L["Text position"],
            desc = L["Text position"],
            values = TextPositions,
            order = 144,
        },
        padding = {
            type = 'range',
            name = L["Padding"],
            desc = L["Padding"],
            softMin = MinPadding,
            min = -Large,
            softMax = MaxPadding,
            max = Large,
            step = 1,
            order = 146,
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
            order = 101,
        },
        strata = {
            type = 'select',
            name = L["Strata"],
            desc = L["Frame strata"],
            values = FrameStratas,
            order = 170,
        },
    },
}

local ignoreLists = {
    type = 'group',
    childGroups = 'tab',
    inline = true,
    name = L["Ignore list"],
    handler = CooldownToGo,
    get = "getOption",
    set = "setOption",
    order = 50,
    args = {
        ignoreNext = {
            type = 'execute',
            name = L["Ignore next action"],
            order = 10,
            func = "ignoreNextAction",
        },
        reverseIgnoreLogic = {
            type = 'toggle',
            name = L["Reverse Ignore Logic"],
            desc = L["If checked, then only trigger for actions that are on the ignore list, and ignore the others."],
            order = 15,
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
}

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
    if self:IsEnabled() then
        self.text:SetTextColor(db.colorR, db.colorG, db.colorB, db.colorA)
        self.icon:SetAlpha(db.colorA)
    end
end

function CooldownToGo:notifyOptionsChange()
    ACR:NotifyChange(self.AppName)
    ACR:NotifyChange(self.AppName .. ".ignoreLists") 
end

local function updateOpts(opts, db, descFunc)
    local changed
    for id, _ in pairs(opts) do
        id = tonumber(id)
        if not db[id] then
            opts[tostring(id)] = nil
            changed = true
        end
    end
    for id, flag in pairs(db) do
        if flag then
            local description = descFunc(id)
            if description then
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
    return GetSpellInfo(id) or "spell:" .. id
end

local function getItemDesc(id)
    return GetItemInfo(id) or "item:" .. id
end

local function getPetbarDesc(id)
    local text, _, _, isToken = GetPetActionInfo(id)
    text = ((isToken and _G[text] or text) or L['Petbar']) .. '[' .. tostring(id) .. ']'
    return text
end

function CooldownToGo:updateIgnoreListOptions()
    local changed
    changed = updateOpts(ignoreLists.args.spell.args, self.db.profile.ignoreLists.spell, getSpellDesc) or changed
    changed = updateOpts(ignoreLists.args.item.args, self.db.profile.ignoreLists.item, getItemDesc) or changed
    changed = updateOpts(ignoreLists.args.petbar.args, self.db.profile.ignoreLists.petbar, getPetbarDesc) or changed
    if changed then
        self:notifyOptionsChange() 
    end
end

function CooldownToGo:removeIgnored(info)
    local id = info[#info]
    local cat = info[#info - 1]
    self:setIgnoredState(cat .. ":" .. id, false)
end

do
    local self = CooldownToGo

    local function registerSubOptions(name, opts)
        local appName = self.AppName .. "." .. name
        ACR:RegisterOptionsTable(appName, opts)
        return ACD:AddToBlizOptions(appName, opts.name or name, self.AppName)
    end

    self.optionsLoaded = true

    -- remove dummy options frame, ugly hack
    if self.dummyOpts then
        for k, f in ipairs(INTERFACEOPTIONS_ADDONCATEGORIES) do
            if f == self.dummyOpts then
                tremove(INTERFACEOPTIONS_ADDONCATEGORIES, k)
                f:SetParent(UIParent)
                break
            end
        end
        self.dummyOpts = nil
    end

    ACR:RegisterOptionsTable(self.AppName, mainOptions)
    self.opts = ACD:AddToBlizOptions(self.AppName, self.AppName)
    self.ignoreListOpts = registerSubOptions('ignoreLists', ignoreLists)
    self:updateIgnoreListOptions()
    local profiles =  AceDBOptions:GetOptionsTable(self.db)
    if LibDualSpec then
        LibDualSpec:EnhanceOptions(profiles, self.db)
    end
    self.profiles = registerSubOptions('profiles', profiles)
end
