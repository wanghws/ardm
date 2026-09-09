local addonName, ns = ...

-- Tracker owns all game-state: is the player an Assassination Rogue, are we
-- in combat, and which hostile nameplate units deserve a square. It
-- deliberately knows nothing about auras: in 12.x aura data on enemy units is
-- secret in combat, so DoT presence is rendered by Blizzard's AuraContainer
-- widget inside Display.lua instead of being queried here.
local M = {}
ns:RegisterModule("tracker", M)

ns.state = {
    eligible = false,   -- Assassination Rogue
    inCombat = false,
    units    = {},      -- tracked nameplate unit tokens, oldest first
}
local state = ns.state

local plates     = {}   -- [unit] = true: hostile nameplate on screen
local tracked    = {}   -- [unit] = true: plate that currently deserves a square
local seenAt     = {}   -- [unit] = order in which the unit entered `tracked`
local graceUntil = {}   -- [unit] = GetTime() after which a lapsed plate is dropped
local arrivals   = 0    -- monotonic counter; ties are impossible, unlike GetTime
local MAX_NAMEPLATES = 40

-- Either engagement signal can lapse while the enemy is still very much the
-- player's problem: a mob resets its target, a threat wipe fires, or the rogue
-- Vanishes and drops off the threat table with bleeds still ticking. Dropping
-- the square straight away would re-bind the slot's AuraContainer and, worse,
-- hand the enemy a fresh `seenAt` on the way back, jumping its square to the
-- end of the row. Disengagement is therefore only honoured after the enemy has
-- stayed disengaged this long; re-qualifying in the meantime costs nothing.
--
-- Sized for Vanish rather than for flag jitter: the stealth window plus the
-- re-opener has to fit inside it, so this is seconds, not frames. A dead or
-- out-of-range enemy never waits it out — its nameplate goes away first, and
-- NAME_PLATE_UNIT_REMOVED skips the grace entirely.
local COMBAT_GRACE = 5.0

-- ---------------------------------------------------------------------------
-- Eligibility (class + spec)
-- ---------------------------------------------------------------------------

local function currentSpecID()
    local index
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
        index = C_SpecializationInfo.GetSpecialization()
    elseif GetSpecialization then
        index = GetSpecialization()
    end
    if not index then return nil end

    if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
        return (C_SpecializationInfo.GetSpecializationInfo(index))
    elseif GetSpecializationInfo then
        return (GetSpecializationInfo(index))
    end
end

function M:UpdateEligibility()
    local _, classToken = UnitClass("player")
    local eligible = classToken == "ROGUE" and currentSpecID() == ns.ASSASSINATION_SPEC_ID
    if eligible ~= state.eligible then
        state.eligible = eligible
        ns:Debug("eligible=%s", tostring(eligible))
        self:ApplyEventRegistration()
        ns:RefreshAll()
    end
end

-- ---------------------------------------------------------------------------
-- Unit bookkeeping
-- ---------------------------------------------------------------------------

local function render()
    local d = ns.modules.display
    if d then d:Render() end
end

local function equalsTrue(value)
    return value == true
end

-- Any boolean a unit API hands back may be secret, and comparing one raises.
-- Every predicate below therefore resolves to "yes" when the comparison is
-- refused: a square that should not be there is a far smaller problem than a
-- missing square for an enemy the player is actually bleeding.
local function isTrue(value)
    local ok, result = pcall(equalsTrue, value)
    if not ok then return true end
    return result
end

-- Friendly nameplates (if the user enabled them) should not get a square.
local function isHostile(unit)
    local ok, canAttack = pcall(UnitCanAttack, "player", unit)
    if not ok then return true end
    return isTrue(canAttack)
end

local function isNotNil(value)
    return value ~= nil
end

-- Threat is the second engagement signal. UnitThreatSituation is only secret
-- when both tokens are restricted; player-against-nameplate is explicitly
-- exempt, and a token pair the client refuses to compare returns nothing
-- rather than raising.
local function hasThreat(unit)
    local ok, status = pcall(UnitThreatSituation, "player", unit)
    if not ok then return true end
    local ok2, present = pcall(isNotNil, status)
    if not ok2 then return true end
    return present
end

-- A unit earns a square only while it is fighting *and* the player holds
-- threat on it. The combat flag alone lets in enemies busy with somebody
-- else's pull; threat alone lets in enemies whose fight the player has already
-- left. Requiring both narrows the row to the player's own fight, at the cost
-- of enemies that never take the combat flag — training dummies among them.
--
-- UnitAffectingCombat is not among the unit APIs 12.x made secret and
-- UnitThreatSituation is exempt for a player-against-nameplate pair, but both
-- go through the same guarded path as everything else, so a future restriction
-- on either degrades to "show the square" rather than hiding a live target.
local function isFighting(unit)
    if not ns.db.combatOnly then return true end
    local ok, affectingCombat = pcall(UnitAffectingCombat, unit)
    if not ok then return true end
    if not isTrue(affectingCombat) then return false end
    return hasThreat(unit)
end

-- Debug only. Renders a value that may be secret, forbidden or absent without
-- ever comparing it, so `/ardm probe` can show what the client actually hands
-- back for a nameplate unit.
local function describe(value)
    local ok, text = pcall(tostring, value)
    if not ok then return "<inaccessible>" end
    return text
end

-- type() is itself refused for some secret values, so it stays inside the pcall
-- alongside the call being probed.
local function callAndDescribe(func, ...)
    local value = func(...)
    return describe(value) .. " (" .. describe(type(value)) .. ")"
end

local function rawCall(func, ...)
    local ok, text = pcall(callAndDescribe, func, ...)
    if not ok then return "<raised: " .. describe(text) .. ">" end
    return text
end

local function unitIndex(unit)
    return tonumber(unit:match("^nameplate(%d+)$")) or 0
end

-- Squares are ordered by when the enemy joined the tracked set, so a square
-- never moves while its enemy keeps qualifying. Sorting by DoT state is
-- impossible: the red state lives entirely inside Blizzard's AuraContainer
-- and is never readable.
local function compareUnits(a, b)
    local sa, sb = seenAt[a], seenAt[b]
    if sa and sb and sa ~= sb then return sa < sb end
    return unitIndex(a) < unitIndex(b)
end

local function rebuildUnitList()
    wipe(state.units)
    for unit in pairs(tracked) do
        state.units[#state.units + 1] = unit
    end
    table.sort(state.units, compareUnits)
end

-- seenAt is stamped on entry into the tracked set rather than on nameplate
-- arrival: an enemy that loiters on screen and only joins the fight later gets
-- a square appended on the right instead of one inserted amongst the enemies
-- already being watched. Returns whether the tracked set changed.
local function setTracked(unit, wanted)
    if wanted == (tracked[unit] ~= nil) then return false end
    if wanted then
        tracked[unit] = true
        arrivals = arrivals + 1
        seenAt[unit] = arrivals
    else
        tracked[unit] = nil
        seenAt[unit] = nil
    end
    return true
end

local function addUnit(unit)
    if plates[unit] then return end
    if not isHostile(unit) then return end

    plates[unit] = true
    if setTracked(unit, isFighting(unit)) then rebuildUnitList() end
end

-- A vanished nameplate gets no grace: unlike a lapsed combat flag it means the
-- enemy is dead or out of range, and its slot has to be freed for the next one.
local function removeUnit(unit)
    if not plates[unit] then return end
    plates[unit] = nil
    graceUntil[unit] = nil
    if setTracked(unit, false) then rebuildUnitList() end
end

-- A single one-shot timer covers every pending unit: grace is a constant, so
-- deadlines can only be created in ascending order and the earliest one is
-- always the one worth waking up for. `scheduleGrace` and `processGrace` are
-- pre-declared rather than closures so the render path allocates nothing.
local graceTimer = false
local scheduleGrace

local function processGrace()
    graceTimer = false

    local now, soonest, changed = GetTime(), nil, false
    for unit, deadline in pairs(graceUntil) do
        if not plates[unit] or isFighting(unit) then
            graceUntil[unit] = nil          -- back in the fight, or plate gone
        elseif deadline <= now then
            graceUntil[unit] = nil
            if setTracked(unit, false) then changed = true end
        elseif not soonest or deadline < soonest then
            soonest = deadline
        end
    end

    if soonest then scheduleGrace(soonest - now) end
    if not changed then return end

    rebuildUnitList()
    ns:Debug("grace elapsed -> %d unit(s)", #state.units)
    render()
end

function scheduleGrace(delay)
    if graceTimer then return end
    graceTimer = true
    C_Timer.After(delay, processGrace)
end

-- An enemy's combat state changes long after its nameplate appeared, so the
-- tracked set is re-checked whenever the client reports new flags or threat
-- for a plate we already know about. Entering combat is applied immediately;
-- leaving it only starts the grace clock. Returns whether the visible list
-- changed, so the caller only re-renders on a real transition.
local function refreshUnit(unit)
    if not plates[unit] then return false end

    if not isFighting(unit) then
        if not tracked[unit] or graceUntil[unit] then return false end
        graceUntil[unit] = GetTime() + COMBAT_GRACE
        scheduleGrace(COMBAT_GRACE)
        return false
    end

    graceUntil[unit] = nil
    if not setTracked(unit, true) then return false end
    rebuildUnitList()
    return true
end

-- Discovery goes through unit tokens rather than C_NamePlate.GetNamePlates():
-- nameplate1..nameplate40 plus UnitExists cannot go stale or hand back plates
-- belonging to units we cannot query. Plates already on screen when the fight
-- starts are seeded in token order, which is the closest thing to their real
-- arrival order that is still knowable.
local function syncUnitsFromNameplates()
    wipe(plates)
    wipe(tracked)
    wipe(seenAt)
    wipe(graceUntil)
    local plateCount = 0
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        local ok, exists = pcall(UnitExists, unit)
        if ok and exists and isHostile(unit) then
            plates[unit] = true
            plateCount = plateCount + 1
            if isFighting(unit) then
                arrivals = arrivals + 1
                tracked[unit] = true
                seenAt[unit] = arrivals
            end
        end
    end
    rebuildUnitList()
    ns:Debug("sync: %d of %d hostile nameplate(s) tracked", #state.units, plateCount)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")

-- UNIT_FLAGS and UNIT_THREAT_LIST_UPDATE are the only signals that an enemy
-- already on screen entered or left combat, and both carry nameplate tokens.
-- They are registered only while the player is fighting: nothing is rendered
-- outside combat, and combat start re-syncs every plate anyway.
local COMBAT_STATE_EVENTS = { "UNIT_FLAGS", "UNIT_THREAT_LIST_UPDATE" }

local function setCombatStateEvents(enabled)
    for _, event in ipairs(COMBAT_STATE_EVENTS) do
        if enabled then
            frame:RegisterEvent(event)
        else
            frame:UnregisterEvent(event)
        end
    end
end

local function onCombatStart()
    state.inCombat = true
    syncUnitsFromNameplates()
    setCombatStateEvents(true)
    ns:RefreshAll()
end

local function onCombatEnd()
    state.inCombat = false
    setCombatStateEvents(false)
    wipe(graceUntil)
    ns:RefreshAll()
end

local handlers = {}

function handlers.PLAYER_REGEN_DISABLED()
    onCombatStart()
end

function handlers.PLAYER_REGEN_ENABLED()
    onCombatEnd()
end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
    addUnit(unit)
    ns:Debug("added %s -> %d unit(s)", unit, #state.units)
    if state.inCombat then render() end
end

function handlers.NAME_PLATE_UNIT_REMOVED(unit)
    removeUnit(unit)
    ns:Debug("removed %s -> %d unit(s)", unit, #state.units)
    if state.inCombat then render() end
end

local function onUnitCombatStateChanged(unit)
    if ns.db.debug and plates[unit] then
        ns:Debug("event %s affectingCombat=%s threat=%s", unit,
            rawCall(UnitAffectingCombat, unit),
            rawCall(UnitThreatSituation, "player", unit))
    end
    if not refreshUnit(unit) then return end
    ns:Debug("combat state %s -> %d unit(s)", unit, #state.units)
    render()
end

handlers.UNIT_FLAGS              = onUnitCombatStateChanged
handlers.UNIT_THREAT_LIST_UPDATE = onUnitCombatStateChanged

function handlers.PLAYER_SPECIALIZATION_CHANGED(unit)
    if unit == nil or unit == "player" then
        M:UpdateEligibility()
    end
end

function handlers.PLAYER_ENTERING_WORLD()
    M:UpdateEligibility()
    if UnitAffectingCombat("player") then
        onCombatStart()
    else
        onCombatEnd()
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then ns:CallSafe(handler, ...) end
end)

-- Combat / nameplate events are only worth paying for while the character
-- is actually an Assassination Rogue.
function M:ApplyEventRegistration()
    if state.eligible then
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        syncUnitsFromNameplates()
        if UnitAffectingCombat("player") then onCombatStart() end
    else
        frame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
        frame:UnregisterEvent("NAME_PLATE_UNIT_ADDED")
        frame:UnregisterEvent("NAME_PLATE_UNIT_REMOVED")
        wipe(plates)
        wipe(tracked)
        wipe(seenAt)
        wipe(graceUntil)
        wipe(state.units)
        onCombatEnd()
    end
end

-- One-shot diagnostic behind `/ardm probe`: dumps what the client returns for
-- every nameplate token so a filter that hides everything can be told apart
-- from a client that simply never reports enemy combat state.
function M:Probe()
    ns:Print(("combatOnly=%s inCombat=%s eligible=%s tracked=%d")
        :format(tostring(ns.db.combatOnly), tostring(state.inCombat),
                tostring(state.eligible), #state.units))
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        local ok, exists = pcall(UnitExists, unit)
        if ok and exists then
            ns:Print(("%s canAttack=%s affectingCombat=%s threat=%s hostile=%s fighting=%s tracked=%s")
                :format(unit,
                        rawCall(UnitCanAttack, "player", unit),
                        rawCall(UnitAffectingCombat, unit),
                        rawCall(UnitThreatSituation, "player", unit),
                        tostring(isHostile(unit)),
                        tostring(isFighting(unit)),
                        tostring(tracked[unit] ~= nil)))
        end
    end
end

-- Re-evaluates every plate against the current options; the combat-only
-- toggle changes which enemies qualify without any game state moving.
function M:RefreshUnits()
    syncUnitsFromNameplates()
    ns:RefreshAll()
end

function M:OnPlayerLogin()
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:UpdateEligibility()
end
