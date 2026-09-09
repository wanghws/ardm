# Changelog

## v1.0.0

- First release. Shows one 16x16 square per hostile nameplate while an
  Assassination Rogue is in combat; a square turns red when both Garrote (703)
  and Rupture (1943) are on that enemy, rendered through the 12.1
  AuraContainer widget so no secret aura data is read. Minimap button
  locks/unlocks a drag anchor. Only enemies that are themselves in combat get
  a square — in combat and with the player holding threat, so the row stays
  limited to the player's own fight — with a five-second grace period so
  Vanish, a threat wipe or a lapsed combat flag cannot make a square vanish and
  reappear at the end of the row;
  `/ardm combat` turns the filter off and `/ardm probe` dumps what the client
  reports per nameplate. Localised for enUS, zhCN and zhTW.
- 首个版本。刺杀盗贼进入战斗后,按敌对姓名板数量显示 16x16 方格;当该敌人同时
  带有绞喉(703)与割裂(1943)时方格变红,通过 12.1 的 AuraContainer 控件
  渲染,不读取任何 secret 光环数据。小地图按钮可锁定/解锁拖动锚点。
  只有交战中的敌人才会占一个方格——需同时处于战斗中且玩家对其有仇恨,因此整行
  只包含玩家自己在打的目标——并带 5 秒延时,避免消失、仇恨清空或战斗标志抖动
  导致方格消失后又排到行尾;`/ardm combat` 可关闭该过滤,`/ardm probe` 可导出客户端对每个姓名板的
  原始返回值。
  支持英文、简体中文、繁体中文。
