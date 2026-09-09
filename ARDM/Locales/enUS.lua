local addonName, ns = ...

-- enUS is the default locale: every key must exist here. Other locales fall
-- back to these strings through the metatable installed in Init.lua.
ns.locales = ns.locales or {}
ns.locales.enUS = {
    ADDON_TITLE          = "ARDM",
    TOOLTIP_DESC         = "Assassination Rogue Bleed Monitor",
    TOOLTIP_LEFT_CLICK   = "Left-click: lock / unlock the anchor",
    TOOLTIP_RIGHT_CLICK  = "Right-click: reset position",
    ANCHOR_LABEL         = "ARDM (drag)",
    MSG_LOCKED           = "anchor locked",
    MSG_UNLOCKED         = "anchor unlocked (drag to move)",
    MSG_RESET            = "position reset",
    MSG_COMBAT_ONLY_ON   = "showing enemies in combat only",
    MSG_COMBAT_ONLY_OFF  = "showing every enemy nameplate",
    MSG_MINIMAP_SHOWN    = "minimap icon shown",
    MSG_MINIMAP_HIDDEN   = "minimap icon hidden",
    MSG_NO_AURA_CONTAINER = "This client has no AuraContainer support; squares will stay white.",
    MSG_HELP             = "commands: lock | unlock | reset | combat | minimap | debug",
}
