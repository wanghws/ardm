local addonName, ns = ...

-- Garrote and Rupture. A square turns red only when both are present.
ns.TRACKED_SPELLS = { 703, 1943 }

-- Assassination specialization ID (SpecializationID, not the spec index).
ns.ASSASSINATION_SPEC_ID = 259

local defaults = {
    locked      = true,
    -- Left edge of the row, in UIParent coordinates from the bottom-left of
    -- the screen. nil means "not placed yet"; Display.lua picks a default that
    -- suits the current resolution. The row always grows to the right from
    -- here, so the anchor never moves as enemies come and go.
    x           = nil,
    y           = nil,
    squareSize  = 16,
    squareGap   = 4,
    -- Only enemies that are actually fighting get a square. Idle nameplates
    -- within range can never turn red, so they would only pad the row.
    combatOnly  = true,
    dbVersion   = 0,
    minimap     = { hide = false },
    debug       = false,
}

local function applyDefaults(dst, src)
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then dst[key] = {} end
            applyDefaults(dst[key], value)
        elseif dst[key] == nil then
            dst[key] = value
        end
    end
end

function ns:InitializeDB()
    if type(ARDMDB) ~= "table" then ARDMDB = {} end
    applyDefaults(ARDMDB, defaults)
    -- v1 saves shipped with an 8px default; carry existing users over to 16px.
    if ARDMDB.dbVersion < 1 then
        if ARDMDB.squareSize == 8 then ARDMDB.squareSize = 16 end
        ARDMDB.dbVersion = 1
    end

    -- v2 replaced the free-form anchor point with a fixed left edge; the old
    -- offsets meant something else and cannot be converted.
    if ARDMDB.dbVersion < 2 then
        ARDMDB.point = nil
        ARDMDB.x     = nil
        ARDMDB.y     = nil
        ARDMDB.dbVersion = 2
    end
    self.db = ARDMDB
end
