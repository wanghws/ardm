# ARDM — Project Guide for Claude

Keep this file in sync with the code — if you change how things work, update
it in the same change.

## What the addon does

ARDM (Assassination Rogue Bleed Monitor, shown as 刺杀盗贼流血监控 in the
zhCN client) is a Retail World of Warcraft (12.1) addon. `ARDM` stays the
folder name, TOC name and SavedVariable; only the displayed title and
`L["ADDON_TITLE"]` are localised. When an Assassination Rogue is in combat it draws a grid of
16x16 squares, eight per row and wrapping downward, one per hostile nameplate that is itself in
combat. A square is white by default and turns
red when that enemy has **both** Garrote (703) and Rupture (1943) applied. A
minimap button locks/unlocks a drag anchor.

## Shipping

Only the inner `ARDM/` folder ships; `release.sh` packages nothing else.

### Icon

`Media/Icon.tga` is the game's own Garrote and Rupture icons split along the
top-left → bottom-right diagonal, built by `tools/make_icon.py` from the
client's BLPs (FileDataIDs 132297 / 132302, fetched from wago.tools). Edit the
script and re-run it rather than editing the TGA by hand. It is referenced by
`## IconTexture` in the TOC and by the LibDBIcon launcher in `Minimap.lua`; keep
the two paths identical. Addon textures must be BLP or TGA, and the client only
notices a *new* texture file after a full restart — `/reload` is not enough.

## Load order (from `.toc`)

Libs → Locales → `Init.lua` → `Config.lua` → Modules. Locales must load
before `Init.lua` because `Init.lua` builds `ns.L` from `ns.locales`.

## Conventions

### Namespace and modules

Every file starts with `local addonName, ns = ...`. Never use raw globals
except the SavedVariable `ARDMDB`.

Modules register with `ns:RegisterModule("<id>", M)` and may implement the
`OnDBReady` / `OnPlayerLogin` / `Refresh` hooks (see `Init.lua`).

Do not create per-file bootstrap frames for `PLAYER_LOGIN`; use
`OnPlayerLogin`.

### State flow

`Modules/Tracker.lua` is the only file that calls game APIs for combat,
nameplates and auras. It publishes `ns.state` (`eligible`, `inCombat`,
`units` oldest first).

Tracker keeps two sets: `plates` (every nameplate on screen, hostile or not)
and `tracked` (the plates that currently deserve a square). A plate enters
`tracked` only while `UnitCanAttack` says the player can attack it and, with
`db.combatOnly` on — the default — only while it looks engaged, so idle mobs
standing in range do not pad the grid.

**Hostility is re-checked, not settled on arrival.** Boss summons routinely
spawn unattackable (spawn animation, immunity window, a faction that flips once
they engage), so a plate that fails `UnitCanAttack` stays in `plates` and is
re-evaluated on `UNIT_FLAGS` / `UNIT_FACTION`. Dropping such a plate at
`NAME_PLATE_UNIT_ADDED` means the add never gets a square, because every later
event is ignored for units not in `plates`.
Hostility gates *entry* only: a tracked enemy that turns unattackable mid-fight
(an immune intermission) keeps its square, and leaving is decided by engagement
alone, through the grace below. `qualifies()` in `Tracker.lua` encodes both
rules.

Engagement requires **both** signals:

- `UnitAffectingCombat(unit)` — the enemy is fighting somebody.
- `UnitThreatSituation("player", unit) ~= nil` — the player has threat on it.

The combat flag alone lets in enemies busy with somebody else's pull; threat
alone lets in enemies whose fight the player has already left. The known cost
of the conjunction is that **enemies which never take the combat flag never get
a square — training dummies among them**; that is a deliberate trade, not a
bug, and `/ardm combat` switches the filter off wholesale.

**During a boss encounter the threat signal is waived** (combat flag only).
Boss summons are what it misses: many have no threat table at all (fixating
adds, spawns that ignore threat), and the rest list the player only after the
first hit. Adds cannot be told apart from other enemies through the API, so the
waiver is scoped by encounter rather than by unit; an encounter is one fight,
so it has no somebody-else's-pull to filter. Dungeon trash keeps the threat
requirement. `inEncounter` follows `ENCOUNTER_START` / `ENCOUNTER_END`, which
re-check every plate (leaving goes through grace), and is re-read from
`C_InstanceEncounter.IsEncounterInProgress` (pre-12 global as fallback) on
`PLAYER_ENTERING_WORLD` and eligibility changes, where the events may have been
missed.

`UnitAffectingCombat` is not one of the unit APIs 12.x made secret, and
`UnitThreatSituation` is exempt for a player-against-nameplate pair
(`SecretWhenUnitThreatStateRestricted`), but both go through the same `pcall`
guard as `UnitCanAttack`; every predicate resolves to "show the square" when a
comparison is refused, because a spurious square costs far less than a missing
one.

Qualifying applies immediately, disqualifying only after `COMBAT_GRACE` (5s)
of staying disqualified. Either signal lapses on an enemy that is still the
player's problem — a mob resets its target, a threat wipe fires, or the rogue
Vanishes and leaves the threat table with bleeds still ticking — and dropping
the square straight away would re-bind the slot's `AuraContainer` and hand the
enemy a fresh `seenAt` on the way back, jumping its square to the end of the
grid. The constant is sized for Vanish (stealth window plus re-opener), not for
flag jitter; shortening it back to ~1s re-breaks Vanish. A vanished *nameplate*
gets no grace at all: `NAME_PLATE_UNIT_REMOVED` means dead or out of range, and
the slot has to be freed.

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

Squares are ordered by when the enemy joined `tracked` (`seenAt`, a monotonic
counter rather than `GetTime` so ties are impossible). A square therefore never
moves while its enemy keeps qualifying, and a mob that loiters on screen before
joining the fight is appended at the end rather than inserted in the middle.
Squares fill `db.columns` (8) per row left to right, then wrap onto a new row
below; when an earlier enemy leaves, later squares shift back one place and
may move up a row.

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

### Performance rules

The renderer runs while the player is fighting, so keep these:

- Nothing polls. Membership changes only on `NAME_PLATE_UNIT_ADDED` /
  `NAME_PLATE_UNIT_REMOVED` and, for an enemy already on screen, on
  `UNIT_FLAGS` / `UNIT_FACTION` / `UNIT_THREAT_LIST_UPDATE`, plus one sweep
  over `plates` on `ENCOUNTER_START` / `ENCOUNTER_END`; there is no
  `OnUpdate` and no ticker. Those three unit events are the only signals that
  an enemy entered or left combat or became attackable, and all carry
  nameplate tokens. They are registered only while the player is fighting, are
  dropped in O(1) for units that are not nameplates, and re-render only on an
  actual transition.
- The one timer is the combat grace: a single one-shot `C_Timer.After` shared
  by every pending unit, armed only when an enemy actually leaves combat and
  re-armed only while `graceUntil` is non-empty. Grace is a constant, so
  deadlines are created in ascending order and the earliest is always the only
  one worth waking for. Never turn this into a per-unit timer or a ticker;
  `scheduleGrace` / `processGrace` are pre-declared for the same reason `pcall`
  never gets an inline closure.
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
  with the slot — the unlocked preview squares must never create one — and slots
  are never destroyed once created.

### Localisation

Every user-visible string goes through `ns.L["KEY"]`. Add the key to
`Locales/enUS.lua` first (the fallback), then to `zhCN.lua` and `zhTW.lua`.
Missing keys render as the key itself so they are visible in-game.

### Anchoring

The grid is anchored by its **top-left corner** (`TOPLEFT` to UIParent's
`BOTTOMLEFT`), never by its centre: `setGridSize` changes the frame's width and
height every time the enemy count changes, and any other anchor point would
slide every existing square. `db.x`/`db.y` store that corner in UIParent
coordinates and are `nil` until the frame is first placed, so `defaultPosition`
can pick something that suits the current resolution. The unlocked preview
shows one full row, because a full row is the widest the grid ever gets.
`SetClampedToScreen` is deliberately off — it would move the anchor as soon as
the grid grew past the screen edge — and `savePosition` clamps on drag release
instead: a full row is kept on screen horizontally, but only the first row
vertically, since the height depends on how many enemies are engaged.

### Config

Single SavedVariable `ARDMDB`, accessed via `ns.db`. Defaults live in
`Config.lua`; `ns:InitializeDB()` fills in missing keys without overwriting
user values and runs the numbered `dbVersion` migrations. Tracked spell IDs and the spec ID also live in `Config.lua`.
`squareSize`, `squareGap` and `columns` have no in-game UI and are only meant
to change between sessions: slots cache their size and grid position.

### Code style

- English only in code, comments and UI strings.
- Comment *why*, not *what*. No "added for X" / "fixed in Y" in source.
- No hardcoded Chinese/English in module bodies.

## Release workflow

Run `/release` (`.claude/commands/release.md`). Uploads to
CurseForge/WoWInterface are manual.
