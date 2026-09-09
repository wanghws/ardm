local addonName, ns = ...

ns.locales = ns.locales or {}
ns.locales.zhCN = {
    ADDON_TITLE          = "刺杀盗贼流血监控",
    TOOLTIP_DESC         = "绞喉与割裂同时存在时方格变红",
    TOOLTIP_LEFT_CLICK   = "左键:锁定 / 解锁锚点",
    TOOLTIP_RIGHT_CLICK  = "右键:重置位置",
    ANCHOR_LABEL         = "ARDM(拖动)",
    MSG_LOCKED           = "锚点已锁定",
    MSG_UNLOCKED         = "锚点已解锁(拖动以移动)",
    MSG_RESET            = "位置已重置",
    MSG_COMBAT_ONLY_ON   = "仅显示战斗中的敌人",
    MSG_COMBAT_ONLY_OFF  = "显示全部敌方姓名板",
    MSG_MINIMAP_SHOWN    = "已显示小地图按钮",
    MSG_MINIMAP_HIDDEN   = "已隐藏小地图按钮",
    MSG_NO_AURA_CONTAINER = "当前客户端不支持 AuraContainer,方格将保持白色。",
    MSG_HELP             = "命令:lock | unlock | reset | combat | minimap | debug",
}
