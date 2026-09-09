local addonName, ns = ...
_G.ARDM = ns

ns.name    = addonName
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version"))
          or "0.0.0"
ns.modules = {}

-- Locale table: current client locale first, enUS as the fallback, and the
-- key itself as the last resort so a missing translation is visible in-game.
do
    local base   = ns.locales.enUS
    local active = ns.locales[GetLocale()] or base
    ns.L = setmetatable({}, {
        __index = function(_, key)
            return active[key] or base[key] or key
        end,
    })
end

function ns:RegisterModule(id, mod)
    self.modules[id] = mod
end

function ns:CallModules(method, ...)
    for _, mod in pairs(self.modules) do
        if type(mod[method]) == "function" then
            mod[method](mod, ...)
        end
    end
end

function ns:RefreshAll()
    self:CallModules("Refresh")
end

function ns:Print(msg)
    print("|cffff3333" .. self.L["ADDON_TITLE"] .. "|r: " .. tostring(msg))
end

-- Errors inside event handlers and the renderer must not be swallowed: they
-- go to the normal error handler, and to chat as well while debug is on.
function ns:CallSafe(func, ...)
    local function handler(err)
        if self.db and self.db.debug then
            self:Print("|cffff5555error|r " .. tostring(err))
        end
        return geterrorhandler()(err)
    end
    return xpcall(func, handler, ...)
end

function ns:Debug(fmt, ...)
    if not (self.db and self.db.debug) then return end
    print("|cff888888ARDM|r " .. string.format(fmt, ...))
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        ns:InitializeDB()
        ns:CallModules("OnDBReady")
    elseif event == "PLAYER_LOGIN" then
        ns:CallModules("OnPlayerLogin")
    end
end)

function ns:SetLocked(locked)
    self.db.locked = locked and true or false
    self:RefreshAll()
    self:Print(self.L[locked and "MSG_LOCKED" or "MSG_UNLOCKED"])
end

function ns:ToggleLocked()
    self:SetLocked(not self.db.locked)
end

function ns:ResetPosition()
    self.db.x = nil
    self.db.y = nil
    self:InitializeDB()
    self:RefreshAll()
    self:Print(self.L["MSG_RESET"])
end

function ns:ToggleCombatOnly()
    self.db.combatOnly = not self.db.combatOnly
    local tracker = self.modules.tracker
    if tracker then
        tracker:RefreshUnits()
    else
        self:RefreshAll()
    end
    self:Print(self.L[self.db.combatOnly and "MSG_COMBAT_ONLY_ON" or "MSG_COMBAT_ONLY_OFF"])
end

SLASH_ARDM1 = "/ardm"
SlashCmdList["ARDM"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "lock" then
        ns:SetLocked(true)
    elseif msg == "unlock" then
        ns:SetLocked(false)
    elseif msg == "reset" then
        ns:ResetPosition()
    elseif msg == "probe" then
        local tracker = ns.modules.tracker
        if tracker then tracker:Probe() end
    elseif msg == "combat" then
        ns:ToggleCombatOnly()
    elseif msg == "minimap" then
        local minimap = ns.modules.minimap
        if minimap then minimap:Toggle() end
    elseif msg == "debug" then
        ns.db.debug = not ns.db.debug
        ns:Print("debug " .. (ns.db.debug and "on" or "off"))
    elseif msg == "" then
        ns:ToggleLocked()
    else
        ns:Print(ns.L["MSG_HELP"])
    end
end
