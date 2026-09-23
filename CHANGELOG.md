# Changelog

## v1.1.0

- Adds that a boss summons now get a square: an enemy that appears before it
  can be attacked is picked up the moment it becomes attackable instead of being
  ignored until its nameplate reappears. During a boss encounter the threat
  requirement is dropped, so any attackable enemy in combat gets a square even
  before you hit it or when it ignores threat; outside encounters nothing changes.
- 首领召唤的仆从现在会显示方格:刷出时还不能攻击的敌人,一变为可攻击就会被
  收录,不再一直被忽略到姓名板重新出现。首领战期间不再要求仇恨,只要敌人可攻击
  且处于战斗中就显示方格,即使你还没打到它或它不吃仇恨;首领战以外行为不变。

## v1.0.0

- First release. While an Assassination Rogue is in combat, ARDM draws a 16x16
  square for every enemy nameplate in the player's own fight (in combat and
  with the player holding threat), eight per row and wrapping downward, and
  turns it red once both Garrote (703) and Rupture (1943) are on that enemy —
  rendered through the 12.1 AuraContainer widget, so no secret aura data is
  read. A five-second grace keeps Vanish or a threat wipe from reshuffling the
  grid; the minimap button, with an icon built from the in-game Garrote and
  Rupture icons, locks the drag anchor, and the addon is localised for enUS,
  zhCN and zhTW.
- 首个版本。刺杀盗贼进入战斗后,ARDM 为玩家自己在打的每个敌方姓名板(处于战斗中
  且玩家对其有仇恨)显示一个 16x16 方格,每行 8 个、向下换行;该敌人同时带有
  绞喉(703)与割裂(1943)时方格变红,由 12.1 的 AuraContainer 控件渲染,不读取
  任何 secret 光环数据。5 秒延时避免消失或仇恨清空打乱方格顺序;小地图按钮
  (图标由游戏内绞喉、割裂图标拼合)可锁定拖动锚点,支持英文、简体中文、繁体中文。
