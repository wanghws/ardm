# ARDM — Project Guide for Claude

Keep this file in sync with the code — if you change how things work, update
it in the same change.

## What the addon does

ARDM (Assassination Rogue Bleed Monitor, shown as 刺杀盗贼流血监控 in the
zhCN client) is a Retail World of Warcraft (12.1) addon. `ARDM` stays the
folder name, TOC name and SavedVariable; only the displayed title and
`L["ADDON_TITLE"]` are localised. When an Assassination Rogue is in combat it draws a horizontal row of
16x16 squares, one per hostile nameplate. A square is white by default and turns
red when that enemy has **both** Garrote (703) and Rupture (1943) applied. A
minimap button locks/unlocks a drag anchor.

## Directory layout

```
ardm/                            ← repo root
├── README.md                    EN + zhCN
├── CHANGELOG.md                 bilingual entries per version
├── CLAUDE.md                    ← you are here
├── release.sh                   bash script → ARDM-v<VER>.zip
├── .claude/commands/release.md  Claude command that drives releases
└── ARDM/                        ← shippable addon folder
    ├── ARDM.toc                 load order lives here
    ├── Init.lua                 ns namespace, locale metatable, /ardm slash
    ├── Config.lua               tracked spell IDs, spec ID, SavedVariables defaults
    ├── Locales/                 enUS.lua (default), zhCN.lua, zhTW.lua
    ├── Modules/
    │   ├── Tracker.lua          game state: spec, combat, nameplates, DoT check
    │   ├── Display.lua          square row + drag anchor
    │   └── Minimap.lua          LibDBIcon launcher
    └── Libs/                    LibStub, CallbackHandler, LibDataBroker, LibDBIcon
```

Only the inner `ARDM/` folder ships; `release.sh` packages nothing else.

## Load order (from `.toc`)

Libs → Locales → `Init.lua` → `Config.lua` → Modules. Locales must load
before `Init.lua` because `Init.lua` builds `ns.L` from `ns.locales`.

## Conventions

### Namespace and modules

Every file starts with `local addonName, ns = ...`. Never use raw globals
except the SavedVariable `ARDMDB`.

Modules register with `ns:RegisterModule("<id>", M)` and may implement:

```lua
function M:OnDBReady()      -- ADDON_LOADED, db initialised
function M:OnPlayerLogin()  -- PLAYER_LOGIN
function M:Refresh()        -- ns:RefreshAll() after any state/option change
```

Do not create per-file bootstrap frames for `PLAYER_LOGIN`; use
`OnPlayerLogin`.

### State flow

`Modules/Tracker.lua` is the only file that calls game APIs for combat,
nameplates and auras. It publishes into `ns.state`:

```lua
ns.state = {
    eligible = bool,   -- Assassination Rogue
    inCombat = bool,
    units    = {...},  -- nameplate unit tokens, oldest nameplate first
}
```

`Modules/Display.lua` only reads `ns.state` and renders it. Keep it that way.

### 12.x secret values (important)

During combat, aura data on enemy units is fully secret: every `C_UnitAuras`
query on a nameplate unit returns nil or a secret struct, index/instance-based
queries raise, and `COMBAT_LOG_EVENT_UNFILTERED` no longer exists. **This
codebase never queries auras.** DoT presence is rendered purely visually by
Blizzard's 12.1 `AuraContainer` widget (`CustomAuraContainerTemplate`):

- One container per square, bound to the nameplate unit via `SetUnit`.
- One aura group: filter `"HARMFUL|PLAYER"`, `candidateFilters.includeSpellIDs`
  = the tracked DoTs, `maxFrameCount` = number of tracked DoTs.
- `initializeFrame` paints each aura button solid red. That callback is the
  only place button APIs may be called; afterwards the buttons are forbidden
  (any call, even `IsShown`, raises). `CustomAuraButtonTemplate` has **no size
  of its own** and the flow layout only anchors buttons, so the red texture
  must be given an explicit size — `SetAllPoints` on a zero-sized button
  renders nothing.
- The container sits inside a `SetClipsChildren` frame and is shifted left by
  (#DoTs - 1) button pitches, so only the last possible button overlaps the
  visible white square. That button exists only when every tracked DoT is
  present.
- **The clip frame is the square.** The white base, the preview overlay and the
  aura button's red region all live inside it and all overflow it by `BLEED`,
  with pixel snapping switched off, so the clip rect is the only thing that
  decides an edge. Anchoring the white base to `root` while the red comes down
  the container's own anchor chain makes the two round differently under a
  fractional UI scale, and the white leaks out along a row. `BUTTON_PAD` must
  stay larger than `BLEED` so the bleed of the button parked outside the clip
  cannot reach into the visible square.
- Anchor and lay out the container **before** `AddAuraGroup`: registering a
  group adds `ForbiddenAspect.UntrustedLayoutScriptExecution`, so the
  container must never be re-anchored afterwards. Squares are therefore
  created once at a fixed size and only moved via their parent.

Do not add `UNIT_AURA` handlers, do not call `GetUnitAuraBySpellID` & co, and
do not try to read the container or its buttons. Any boolean returned by unit
APIs (e.g. `UnitCanAttack`) may be secret; compare inside `pcall`. Nameplate
units are discovered by enumerating `nameplate1..40` with `UnitExists`; never
touch nameplate frame objects.

### Square ordering

Squares are ordered by when the nameplate arrived (`seenAt`, a monotonic
counter rather than `GetTime` so ties are impossible). A square therefore never
moves while its enemy stays on screen.

Two orderings people ask for are **not implementable**, and both were tried:

- *By DoT state / when the square turned red.* The red state lives entirely
  inside Blizzard's `AuraContainer`; addon code never learns it. Aura data is
  secret, aura buttons are forbidden after `initializeFrame`, and
  `GetAuraGroupFrameCount` returns the button-pool size (always 10), not the
  active count.
- *By distance.* Enemy distance is not exposed at all — `UnitDistanceSquared`
  covers group members only and returns nil in instances. Nameplate screen
  position works but reads as arbitrary once the camera moves, and it forced a
  timed re-sort.

### Performance rules### Performance rules

The renderer runs while the player is fighting, so keep these:

- Nothing polls. Order changes only on `NAME_PLATE_UNIT_ADDED` /
  `NAME_PLATE_UNIT_REMOVED`, so there is no `OnUpdate` and no timer.
- Slots follow units, not positions. `AuraContainer:SetUnit` makes the client
  re-parse that unit's auras, so a reorder must only move anchors —
  `slotByUnit` in `Display.lua` guarantees a container is re-bound only when
  the set of units on screen changes.
- No allocation in the render path: `unitSet` and `freeSlots` are reused and
  wiped, never rebuilt, and `pcall` is always given a pre-declared function
  rather than an inline closure.
- `AddAuraGroup` allocates a fixed batch of ten aura buttons per container
  (`CustomAuraContainerConstants.FrameCreationBatchSize`; the table is not
  exported to `_G`, so addons cannot lower it, and `maxFrameCount` caps only
  how many are *active*). Containers are therefore built on first bind, not
  with the slot — the unlocked preview row must never create one — and slots
  are never destroyed once created.

### Localisation

Every user-visible string goes through `ns.L["KEY"]`. Add the key to
`Locales/enUS.lua` first (the fallback), then to `zhCN.lua` and `zhTW.lua`.
Missing keys render as the key itself so they are visible in-game.

### Anchoring

The row is anchored by its **left edge** (`LEFT` to UIParent's `BOTTOMLEFT`),
never by its centre: `setRowWidth` changes the frame's width every time the
enemy count changes, and a centre anchor would slide every existing square
sideways. `db.x`/`db.y` store that left edge in UIParent coordinates and are
`nil` until the frame is first placed, so `defaultPosition` can pick something
that suits the current resolution. `SetClampedToScreen` is deliberately off —
it would move the anchor as soon as the row grew past the screen edge — and
`savePosition` clamps into the screen on drag release instead.

### Config

Single SavedVariable `ARDMDB`, accessed via `ns.db`. Defaults live in
`Config.lua`; `ns:InitializeDB()` fills in missing keys without overwriting
user values and runs the numbered `dbVersion` migrations. Tracked spell IDs and the spec ID also live in `Config.lua`.

### Code style

- English only in code, comments and UI strings.
- Comment *why*, not *what*. No "added for X" / "fixed in Y" in source.
- No hardcoded Chinese/English in module bodies.

## Slash commands

`/ardm` toggles lock. Sub-commands: `lock`, `unlock`, `reset`, `minimap`, `debug` (event trace in chat).

## Release workflow

Driven by `.claude/commands/release.md`:

1. Read `## Version:` from `ARDM/ARDM.toc`.
2. Add a bilingual (EN + zhCN) entry to `CHANGELOG.md` under `## v<VER>`.
3. `bash release.sh` → `ARDM-v<VER>.zip` at repo root.
4. Commit `release: v<VER>` and tag `v<VER>` (no push).
5. Bump `## Version:` to the next minor, commit `chore: bump version to <NEW>`.

Uploads to CurseForge/WoWInterface are manual.
