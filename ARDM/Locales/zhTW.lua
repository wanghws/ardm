local addonName, ns = ...

ns.locales = ns.locales or {}
ns.locales.zhTW = {
    ADDON_TITLE          = "刺殺盜賊流血監控",
    TOOLTIP_DESC         = "絞喉與割裂同時存在時方格變紅",
    TOOLTIP_LEFT_CLICK   = "左鍵:鎖定 / 解鎖錨點",
    TOOLTIP_RIGHT_CLICK  = "右鍵:重置位置",
    ANCHOR_LABEL         = "ARDM(拖曳)",
    MSG_LOCKED           = "錨點已鎖定",
    MSG_UNLOCKED         = "錨點已解鎖(拖曳以移動)",
    MSG_RESET            = "位置已重置",
    MSG_MINIMAP_SHOWN    = "已顯示小地圖按鈕",
    MSG_MINIMAP_HIDDEN   = "已隱藏小地圖按鈕",
    MSG_NO_AURA_CONTAINER = "目前客戶端不支援 AuraContainer,方格將保持白色。",
    MSG_HELP             = "指令:lock | unlock | reset | minimap | debug",
}
