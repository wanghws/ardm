local addonName, ns = ...

local M = {}
ns:RegisterModule("minimap", M)

local LDB     = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub("LibDBIcon-1.0", true)

function M:OnDBReady()
    if not LDB or not LDBIcon or self.launcher then return end
    local L = ns.L
    self.launcher = LDB:NewDataObject(addonName, {
        type  = "launcher",
        icon  = [[Interface\Icons\Ability_Rogue_Rupture]],
        label = L["ADDON_TITLE"],
        OnClick = function(_, button)
            if button == "RightButton" then
                ns:ResetPosition()
            else
                ns:ToggleLocked()
            end
        end,
        OnTooltipShow = function(tip)
            tip:AddLine(L["ADDON_TITLE"] .. " |cff9d9d9dv" .. ns.version .. "|r")
            tip:AddLine(L["TOOLTIP_DESC"], 1, 1, 1)
            tip:AddLine(" ")
            tip:AddLine(L["TOOLTIP_LEFT_CLICK"], 0.8, 0.8, 0.8)
            tip:AddLine(L["TOOLTIP_RIGHT_CLICK"], 0.8, 0.8, 0.8)
        end,
    })
    LDBIcon:Register(addonName, self.launcher, ns.db.minimap)
end

function M:Toggle()
    if not LDBIcon then return end
    ns.db.minimap.hide = not ns.db.minimap.hide
    if ns.db.minimap.hide then
        LDBIcon:Hide(addonName)
        ns:Print(ns.L["MSG_MINIMAP_HIDDEN"])
    else
        LDBIcon:Show(addonName)
        ns:Print(ns.L["MSG_MINIMAP_SHOWN"])
    end
end
