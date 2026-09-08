local addonName, ns = ...

-- Tracker owns all game-state: is the player an Assassination Rogue, are we
-- in combat, and which hostile nameplate units exist. It deliberately knows
-- nothing about auras: in 12.x aura data on enemy units is secret in combat,
-- so DoT presence is rendered by Blizzard's AuraContainer widget inside
-- Display.lua instead of being queried here.
local M = {}
ns:RegisterModule("tracker", M)

ns.state = {
    eligible = false,   -- Assassination Rogue
    inCombat = false,
    units    = {},      -- nameplate unit tokens, oldest nameplate first
}
local state = ns.state

local activeUnits = {}   -- [unit] = true
local seenAt      = {}   -- [unit] = arrival sequence number
local arrivals    = 0    -- monotonic counter; ties are impossible, unlike GetTime
local MAX_NAMEPLATES = 40

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

local function equalsTrue(value)
    return value == true
end

-- Friendly nameplates (if the user enabled them) should not get a square.
-- UnitCanAttack may hand back a secret boolean; comparing one raises, and in
-- that case we keep the unit rather than drop it.
local function isHostile(unit)
    local ok, canAttack = pcall(UnitCanAttack, "player", unit)
    if not ok then return true end
    local ok2, hostile = pcall(equalsTrue, canAttack)
    if not ok2 then return true end
    return hostile
end

local function unitIndex(unit)
    return tonumber(unit:match("^nameplate(%d+)$")) or 0
end

-- Squares are ordered by when the nameplate showed up, so a square never moves
-- while its enemy stays on screen. Sorting by DoT state is impossible: the red
-- state lives entirely inside Blizzard's AuraContainer and is never readable.
local function compareUnits(a, b)
    local sa, sb = seenAt[a], seenAt[b]
    if sa and sb and sa ~= sb then return sa < sb end
    return unitIndex(a) < unitIndex(b)
end

local function rebuildUnitList()
    wipe(state.units)
    for unit in pairs(activeUnits) do
        state.units[#state.units + 1] = unit
    end
    table.sort(state.units, compareUnits)
end

local function addUnit(unit)
    if activeUnits[unit] then return end
    if not isHostile(unit) then return end

    activeUnits[unit] = true
    arrivals = arrivals + 1
    seenAt[unit] = arrivals
    rebuildUnitList()
end

local function removeUnit(unit)
    if not activeUnits[unit] then return end
    activeUnits[unit] = nil
    seenAt[unit] = nil
    rebuildUnitList()
end

-- Discovery goes through unit tokens rather than C_NamePlate.GetNamePlates():
-- nameplate1..nameplate40 plus UnitExists cannot go stale or hand back plates
-- belonging to units we cannot query. Plates already on screen when the fight
-- starts are seeded in token order, which is the closest thing to their real
-- arrival order that is still knowable.
local function syncUnitsFromNameplates()
    wipe(activeUnits)
    wipe(seenAt)
    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        local ok, exists = pcall(UnitExists, unit)
        if ok and exists and isHostile(unit) then
            activeUnits[unit] = true
            arrivals = arrivals + 1
            seenAt[unit] = arrivals
        end
    end
    rebuildUnitList()
    ns:Debug("sync: %d nameplate unit(s)", #state.units)
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local frame = CreateFrame("Frame")

local function render()
    local d = ns.modules.display
    if d then d:Render() end
end

local function onCombatStart()
    state.inCombat = true
    syncUnitsFromNameplates()
    ns:RefreshAll()
end

local function onCombatEnd()
    state.inCombat = false
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
        wipe(activeUnits)
        wipe(seenAt)
        wipe(state.units)
        onCombatEnd()
    end
end

function M:OnPlayerLogin()
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:UpdateEligibility()
end
