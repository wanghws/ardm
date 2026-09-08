# ARDM — Assassination Rogue Bleed Monitor

A tiny World of Warcraft Retail (12.1) addon for Assassination Rogues. In
combat it draws one small square per hostile nameplate; the square turns red
when that enemy has both of your bleeds up. The folder and SavedVariable are
named `ARDM`; the addon list shows the localised name.

## Features

- **Assassination only** — activates solely on Rogues in the Assassination
  specialization. Other classes/specs see nothing.
- **Combat only** — appears when you enter combat and hides when you leave.
- **One square per enemy** — a 16x16 white square for every hostile nameplate,
  laid out left to right with spacing, in the order the nameplates showed up —
  a square never moves while its enemy stays on screen. The row is pinned by
  its left edge and grows to the right.
- **DoT status** — a square turns red when the enemy has both
  Garrote (spell 703) and Rupture (spell 1943) applied.
- **Minimap button** — left-click locks/unlocks the anchor, right-click resets
  the position. While unlocked a drag handle and a preview row are shown so
  you can place the frame out of combat.
- **Localised** — English, Simplified Chinese, Traditional Chinese.

## Slash commands

| Command | Result |
| --- | --- |
| `/ardm` | Toggle lock / unlock |
| `/ardm lock` / `/ardm unlock` | Lock or unlock the anchor |
| `/ardm reset` | Reset the frame position |
| `/ardm minimap` | Show / hide the minimap button |
| `/ardm debug` | Toggle event trace in chat (for bug reports) |

## Installation

Extract the `ARDM` folder into
`World of Warcraft/_retail_/Interface/AddOns/`. Restart the client or
`/reload`.

## Notes on 12.x aura restrictions

Since patch 12.0 aura data on enemy units is secret during combat and addons
cannot read it. ARDM therefore never queries auras: each square hosts a
Blizzard `AuraContainer` (new in 12.1) filtered to your own Garrote and
Rupture, and the red overlay you see is the container's own aura button. The
addon only controls how it looks, never what it knows.

---

# 刺杀盗贼流血监控 (ARDM)

面向魔兽世界正式服(12.1)刺杀盗贼的小插件。进入战斗后,每个敌对姓名板对应
一个小方格;当该敌人同时带有你的两个流血(绞喉、割裂)时方格变红。插件文件夹
与存档变量仍叫 `ARDM`,插件列表里显示为「刺杀盗贼流血监控」。

## 主要功能

- **仅刺杀专精** — 只在盗贼的刺杀专精下启用,其他职业/专精不显示任何内容。
- **仅战斗中显示** — 进入战斗显示,脱离战斗隐藏。
- **每个敌人一个方格** — 每个敌对姓名板对应一个 16x16 白色方格,从左向右横向
  排列,带间距,按姓名板出现的先后顺序排列——敌人只要还在屏幕上,它的方格
  就不会移动。整行以左端为锚点固定,向右增长。
- **DoT 状态** — 敌人同时带有绞喉(法术 703)与割裂(法术 1943)时方格变红。
- **小地图按钮** — 左键锁定/解锁锚点,右键重置位置。解锁时会显示拖动手柄和
  预览方格,方便在非战斗状态下调整位置。
- **多语言** — 英文、简体中文、繁体中文。

## 命令

| 命令 | 作用 |
| --- | --- |
| `/ardm` | 切换锁定 / 解锁 |
| `/ardm lock` / `/ardm unlock` | 锁定或解锁锚点 |
| `/ardm reset` | 重置位置 |
| `/ardm minimap` | 显示 / 隐藏小地图按钮 |
| `/ardm debug` | 切换聊天框事件日志(用于报错排查) |

## 安装

将 `ARDM` 文件夹解压到
`World of Warcraft/_retail_/Interface/AddOns/`,然后重启客户端或 `/reload`。

## 关于 12.x 光环限制

自 12.0 起,战斗中敌方单位的光环数据对插件是 secret 的,无法读取。因此 ARDM
完全不查询光环:每个方格内放置一个暴雪 12.1 新增的 `AuraContainer`,只过滤你
自己的绞喉与割裂,你看到的红色覆盖就是容器自己生成的光环按钮。插件只控制外观,
不接触任何光环数据。
