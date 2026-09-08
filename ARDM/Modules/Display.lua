local addonName, ns = ...

-- Display renders ns.state as a horizontal row of squares and owns the drag
-- anchor shown while unlocked.
--
-- How the red state works without reading aura data (12.x secret values):
-- each square is a white texture with a clipping frame on top. Inside the
-- clipping frame lives a Blizzard AuraContainer bound to that nameplate unit
-- with a single group filtered to "HARMFUL|PLAYER" and includeSpellIDs =
-- the tracked DoTs. The client creates one aura button per matching aura and
-- flows them left to right; each button paints itself solid red. The
-- container is shifted left by (#DoTs - 1) button widths, so every button but
-- the last falls outside the clip region. The last button exists only when
-- every tracked DoT is present, which is exactly the condition we want to
-- show. Addon code never inspects the buttons, so nothing here touches
-- secret values.
local M = {}
ns:RegisterModule("display", M)

local WHITE = { 1, 1, 1, 1 }
local RED   = { 1, 0.15, 0.15, 1 }
local PREVIEW_COUNT = 5   -- squares shown while unlocked so the position is visible out of combat

-- Every visible region bleeds this far past the clipping frame on all sides.
-- The clip rect is then the single thing that defines a square's edges, so the
-- white base and the red aura button cannot disagree by a pixel when the UI
-- scale puts a square's origin on a fractional coordinate.
local BLEED = 2

-- Horizontal gap between aura buttons inside a container. It must exceed BLEED
-- so that the bleed of the button parked outside the clip region cannot reach
-- into the visible square.
local BUTTON_PAD = 4

local HAS_AURA_CONTAINERS = C_XMLUtil and C_XMLUtil.GetTemplateInfo
    and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") and true or false

local root, anchor = nil, nil

-- Slots follow units, not positions. Re-binding a container to a different
-- unit forces the client to re-parse that unit's auras, so a slot keeps its
-- unit for as long as the unit is on screen and only its anchor moves when the
-- left-to-right order changes.
local pool       = {}   -- every slot ever created
local slotByUnit = {}   -- [unit] = slot
local unitSet    = {}   -- scratch: units present in the current render
local freeSlots  = {}   -- scratch: slots not currently bound to a unit

-- The row is anchored by its left edge only, so adding squares always extends
-- it to the right instead of pushing the existing ones sideways. Screen
-- clamping happens on release rather than through SetClampedToScreen, which
-- would shift the anchor whenever the row grew past the screen edge.
local function defaultPosition()
    local width = PREVIEW_COUNT * ns.db.squareSize + (PREVIEW_COUNT - 1) * ns.db.squareGap
    return (GetScreenWidth() - width) / 2, GetScreenHeight() / 2 - 120
end

local function applyPosition()
    if not ns.db.x or not ns.db.y then
        ns.db.x, ns.db.y = defaultPosition()
    end
    root:ClearAllPoints()
    root:SetPoint("LEFT", UIParent, "BOTTOMLEFT", ns.db.x, ns.db.y)
end

local function savePosition()
    local left = root:GetLeft()
    local _, centreY = root:GetCenter()
    if not left or not centreY then return end

    local scale  = root:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local size   = ns.db.squareSize
    ns.db.x = math.max(0, math.min(left * scale, GetScreenWidth() - size))
    ns.db.y = math.max(size / 2, math.min(centreY * scale, GetScreenHeight() - size / 2))
end

-- ---------------------------------------------------------------------------
-- Aura container
-- ---------------------------------------------------------------------------

local function includeSpellMap()
    local map = {}
    for _, spellID in ipairs(ns.TRACKED_SPELLS) do
        map[spellID] = true
    end
    return map
end

-- Runs once per aura button, before Blizzard applies access restrictions.
-- This callback is the only place button APIs may be called at all; from here
-- on the button is forbidden and even :IsShown() raises.
--
-- CustomAuraButtonTemplate carries no size of its own and the flow layout
-- only anchors buttons, so the red region is given an explicit size instead
-- of :SetAllPoints(); a zero-sized button would otherwise render nothing.
local function paintBleedTexture(tex, size, r, g, b, a)
    tex:SetPoint("TOPLEFT", -BLEED, BLEED)
    tex:SetSize(size + BLEED * 2, size + BLEED * 2)
    tex:SetColorTexture(r, g, b, a)
    -- Independent pixel snapping is exactly what makes the two anchor chains
    -- disagree; let the clip rect do the rounding for everything.
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
end

local function makeButtonInitializer(size)
    local pitch = size + BUTTON_PAD
    return function(button)
        pcall(button.SetMouseMotionEnabled, button, false)
        pcall(button.SetSize, button, pitch, pitch)
        paintBleedTexture(button:CreateTexture(nil, "ARTWORK"), size, RED[1], RED[2], RED[3], RED[4])
    end
end

-- Everything here must happen before AddAuraGroup: registering a group marks
-- the container as forbidding untrusted layout scripts, after which addon
-- anchoring of the container may no longer be permitted.
local function createContainer(clip, size)
    if not HAS_AURA_CONTAINERS then return nil end

    local pitch = size + BUTTON_PAD
    local container = CreateFrame("AuraContainer", nil, clip, "CustomAuraContainerTemplate")
    container:SetSize(size, size)
    container:SetFrameLevel(clip:GetFrameLevel() + 1)

    -- Hide every button except the last possible one behind the clip edge.
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", clip, "TOPLEFT", -(#ns.TRACKED_SPELLS - 1) * pitch, 0)

    container:SetFlowLayoutAnchorPoint("TOPLEFT")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutMaximumLineSize(math.huge)

    container:AddAuraGroup("dots", "HARMFUL|PLAYER", {
        maxFrameCount    = #ns.TRACKED_SPELLS,
        candidateFilters = { includeSpellIDs = includeSpellMap() },
        initializeFrame  = makeButtonInitializer(size),
        layout           = {
            elementWidth   = pitch,
            elementHeight  = pitch,
            elementSpacing = 0,
            lineSpacing    = 0,
        },
    })

    container:SetEnabled(false)
    container:Hide()
    return container
end

-- Containers are built on first use rather than with the slot: each one
-- allocates a fixed batch of aura buttons, and the preview row shown while the
-- frame is unlocked never needs one.
local function ensureContainer(slot)
    if slot.containerTried then return slot.container end
    slot.containerTried = true

    local ok, container = pcall(createContainer, slot.clip, ns.db.squareSize)
    if ok then
        slot.container = container
    else
        ns:Debug("container creation failed: %s", tostring(container))
    end
    return slot.container
end

local function assignUnit(slot, unit)
    if slot.unit == unit then return end

    if slot.unit then slotByUnit[slot.unit] = nil end
    slot.unit = unit
    if unit then slotByUnit[unit] = slot end

    local c = unit and ensureContainer(slot) or slot.container
    if not c then return end
    if unit then
        c:SetEnabled(true)
        c:SetUnit(unit)
        c:Show()
        ns:Debug("container bound to %s", unit)
    else
        c:SetEnabled(false)
        c:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

local function createFrames()
    if root then return end

    root = CreateFrame("Frame", "ARDMDisplay", UIParent)
    root:SetSize(ns.db.squareSize, ns.db.squareSize)
    root:SetFrameStrata("MEDIUM")
    root:SetMovable(true)

    -- The anchor is a translucent handle drawn over the square row; it is the
    -- only part that receives mouse input, and it is shown only while unlocked.
    anchor = CreateFrame("Frame", nil, root)
    anchor:SetPoint("TOPLEFT", root, "TOPLEFT", -6, 16)
    anchor:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 6, -6)
    anchor:SetFrameLevel(root:GetFrameLevel() + 20)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetScript("OnDragStart", function()
        if not ns.db.locked then root:StartMoving() end
    end)
    anchor:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        savePosition()
        applyPosition()
    end)

    anchor.bg = anchor:CreateTexture(nil, "BACKGROUND")
    anchor.bg:SetAllPoints()
    anchor.bg:SetColorTexture(0, 0.6, 1, 0.35)

    anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    anchor.label:SetPoint("TOP", anchor, "TOP", 0, -1)
    anchor.label:SetText(ns.L["ANCHOR_LABEL"])

    applyPosition()
end

-- Slots are created once and never resized: the aura container is anchored
-- relative to a fixed square size at creation time and must not be re-anchored
-- afterwards.
local function createSlot()
    local size = ns.db.squareSize
    local slot = {}

    -- The clip frame is the square. Everything drawn for this slot lives
    -- inside it and overflows it, so the clip rect alone decides the edges.
    slot.clip = CreateFrame("Frame", nil, root)
    slot.clip:SetSize(size, size)
    slot.clip:SetClipsChildren(true)
    slot.clip:SetFrameLevel(root:GetFrameLevel() + 5)

    slot.base = slot.clip:CreateTexture(nil, "BACKGROUND")
    paintBleedTexture(slot.base, size, WHITE[1], WHITE[2], WHITE[3], WHITE[4])

    slot.preview = slot.clip:CreateTexture(nil, "ARTWORK")
    paintBleedTexture(slot.preview, size, RED[1], RED[2], RED[3], RED[4])
    slot.preview:Hide()

    pool[#pool + 1] = slot
    return slot
end

local function placeSlot(slot, i)
    if slot.index == i then return end
    slot.index = i

    local size, gap = ns.db.squareSize, ns.db.squareGap
    slot.clip:ClearAllPoints()
    slot.clip:SetPoint("LEFT", root, "LEFT", (i - 1) * (size + gap), 0)
end

local function hideSlot(slot)
    slot.index = nil
    slot.preview:Hide()
    slot.clip:Hide()
    assignUnit(slot, nil)
end

-- Unbind slots whose unit left, and collect everything unbound so the assign
-- pass can hand them to units that just arrived.
local function reclaimSlots()
    wipe(freeSlots)
    for i = 1, #pool do
        local slot = pool[i]
        if slot.unit and not unitSet[slot.unit] then
            assignUnit(slot, nil)
        end
        if not slot.unit then
            freeSlots[#freeSlots + 1] = slot
        end
    end
end

local function setRowWidth(count)
    local size, gap = ns.db.squareSize, ns.db.squareGap
    local width = count > 0 and (count * size + (count - 1) * gap) or size
    root:SetSize(width, size)
end

local function render()
    local state = ns.state
    local unlocked = not ns.db.locked

    if not state.eligible then
        root:Hide()
        return
    end

    local count
    if state.inCombat then
        count = #state.units
    elseif unlocked then
        count = PREVIEW_COUNT
    else
        for i = 1, #pool do hideSlot(pool[i]) end
        root:Hide()
        return
    end

    wipe(unitSet)
    if state.inCombat then
        for i = 1, count do
            unitSet[state.units[i]] = true
        end
    end
    reclaimSlots()

    local nextFree = #freeSlots
    for i = 1, count do
        local unit = state.inCombat and state.units[i] or nil
        local slot = unit and slotByUnit[unit]

        if not slot then
            slot = freeSlots[nextFree]
            if slot then
                freeSlots[nextFree] = nil
                nextFree = nextFree - 1
            else
                slot = createSlot()
            end
            assignUnit(slot, unit)
        end

        placeSlot(slot, i)
        slot.clip:Show()
        -- Preview alternates colours so both states are visible while placing.
        slot.preview:SetShown(not state.inCombat and i % 2 == 0)
    end

    for i = 1, nextFree do
        hideSlot(freeSlots[i])
    end

    setRowWidth(count)
    anchor:SetShown(unlocked)
    root:Show()
end

function M:Render()
    if not root then return end
    ns:CallSafe(render)
end

function M:Refresh()
    if not root then return end
    applyPosition()
    self:Render()
end

function M:OnPlayerLogin()
    if not HAS_AURA_CONTAINERS then
        ns:Print(ns.L["MSG_NO_AURA_CONTAINER"])
    end
    createFrames()
    self:Render()
end
