-- ForeverQuestMark: quest icons on nameplates. Reads the unit's tooltip data for quest objective lines
-- and classifies each objective (slay / loot / object / event / talk / interact) from the quest log's own
-- objective types.
local addonName, ns = ...
local icons = {}
local Relayout -- defined below, referenced by the event handler
-- The objective categories, each with its own icon setting (the setting's key is the category's).
local KINDS = { "kill", "loot", "object", "event", "talk", "interact" }
-- Saved variables load after this file runs, so adopt them on ADDON_LOADED (see bottom).
local DB = setmetatable({}, { __index = { kill = "Crosshair_Attack_32", loot = "Crosshair_pickup_32",
    object = "Crosshair_Interact_32", event = "Crosshair_Inspect_32", talk = "Crosshair_speak_32",
    interact = "Crosshair_Interact_32",
    side = "right", x = 4, y = -8, size = 20, avoidAuras = true, auraGap = 2,
    enabled = true, progress = true, groupObjectives = false, hideInInstances = false } })

-- Objective text reduced to its words, so a tooltip line and the matching quest log objective
-- compare equal however their counts are written ("3/8 Foo slain", "Foo slain (3/8)", "35%").
local function NormalizeObjective(text)
    text = text:lower()
    text = text:gsub("%d+%s*/%s*%d+", ""):gsub("%d+%%", ""):gsub("[%(%):]", "")
    text = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return text
end

-- The quest log's own type for each active objective ("monster", "item", "object", "progressbar",
-- ...), keyed by normalized objective text. Built on demand; cleared when the quest log changes.
local objectiveKinds = nil

local function ObjectiveKinds()
    if objectiveKinds then return objectiveKinds end
    objectiveKinds = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                if o.text and o.type then
                    objectiveKinds[NormalizeObjective(o.text)] = o.type
                end
            end
        end
    end
    return objectiveKinds
end

-- A category's icon (its setting): the gear when that atlas isn't on this client, so a mark never
-- shows blank.
local FALLBACK_ICON = "Crosshair_Interact_32"
local function Icon(kind)
    local atlas = DB[kind]
    if atlas and C_Texture.GetAtlasInfo(atlas) then return atlas end
    return FALLBACK_ICON
end

-- Wording fallback for kills the quest log doesn't type as "monster" (e.g. progress bars filled
-- by killing). Each matches at the start of a word, so "kill" covers "killed" but not "skill", and
-- "defeat" covers "defeated". Only English wording is recognised.
local KILL_WORDS = { "%f[%a]slay", "%f[%a]slain", "%f[%a]kill", "%f[%a]defeat" }

local function HasKillWording(text)
    if not text then return false end
    local lower = text:lower()
    for _, pattern in ipairs(KILL_WORDS) do
        if lower:find(pattern) then return true end
    end
    return false
end

--- The icon for an objective from its quest log type and text:
---   loot      "item" objectives;
---   slay      kill wording, or "monster" objectives on a unit that can be attacked;
---   talk      "monster" objectives on a unit that can't be (the quest log types talk-to objectives,
---             "Speak with X", as "monster" too);
---   object    "object" objectives;
---   event     "event" and "log" objectives, and progress bars on a unit that can't be attacked (one on
---             a unit that can be is filled by killing it, so it's slay);
---   interact  any other known type (use, ...); also units the game ties to a quest without an
---             objective line (Update).
--- An objective of unknown type keeps the original behaviour: loot unless kill wording.
--- Used for both tooltip lines (open world) and quest log objectives (instance fallback).
--- @param kind string|nil The quest log objective type, if known.
--- @param text string|nil The objective text.
--- @param hostile boolean|nil Whether the unit can be attacked; nil when unknown.
local function ClassifyObjective(kind, text, hostile)
    if kind == "item" then return Icon("loot") end
    if HasKillWording(text) then return Icon("kill") end
    if kind == "monster" then return hostile == false and Icon("talk") or Icon("kill") end
    if kind == "progressbar" then return hostile and Icon("kill") or Icon("event") end
    if kind == "object" then return Icon("object") end
    if kind == "event" or kind == "log" then return Icon("event") end
    return kind and Icon("interact") or Icon("loot")
end

--------------------------------------------------------------------------------
-- Questie's categories, when Questie is loaded. Its database (QuestieDB) knows each creature's part in each
-- quest, and its Talk and Interact objectives are picked by hand, quest by quest, so where it has a creature
-- its category wins; elsewhere (no Questie, or a creature it doesn't list) ours above decides. Read from
-- QuestieTooltips.lookupByKey["m_<npc id>"], each entry's objective (Icon, Description, Completed,
-- Collected/Needed, Update): the table Questie's own nameplate icons and Plater read. Read, not called into,
-- except the objective's Update, which Questie's nameplates call the same way for fresh quest log data.
--------------------------------------------------------------------------------

-- Questie's icon types (Questie.lua's ICON_TYPE_*) -> our categories. Questie shows its Object type as loot
-- on creatures (QuestieNameplate.lua: a creature never holds an object), so that's loot here too.
local QUESTIE_KINDS = { [1] = "kill", [2] = "loot", [3] = "event", [4] = "loot", [5] = "talk", [17] = "interact" }

local questieTooltips
local function QuestieLookup()
    if questieTooltips then return questieTooltips.lookupByKey end
    local loader = _G.QuestieLoader
    local module = loader and type(loader._modules) == "table" and loader._modules.QuestieTooltips
    if module and type(module.lookupByKey) == "table" then questieTooltips = module return module.lookupByKey end
end

-- Questie's objectives on the unit (a table of { objective = ... }), or nil: no Questie, not a creature
-- it lists, or the unit's id hidden (secret, in instances).
local function QuestieObjectives(unit)
    local lookup = QuestieLookup()
    if not lookup then return end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not guid or (issecretvalue and issecretvalue(guid)) then return end
    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    if (unitType ~= "Creature" and unitType ~= "Vehicle") or not npcId then return end
    return lookup["m_" .. npcId]
end

-- The objective is still open (after Questie's own refresh of it from the quest log)
local function QuestieOpen(objective)
    if type(objective.Update) == "function" then pcall(objective.Update, objective) end
    return not objective.Completed
end

-- Questie's category for a tooltip objective line, from its objective with the same text; nil when it has
-- none of that text.
local function QuestieKindFor(entries, text)
    if not entries then return end
    local want = NormalizeObjective(text)
    for _, entry in pairs(entries) do
        local o = entry.objective
        local kind = type(o) == "table" and QUESTIE_KINDS[o.Icon]
        if kind and type(o.Description) == "string" then
            local desc = NormalizeObjective(o.Description)
            if desc ~= "" and (want:find(desc, 1, true) or desc:find(want, 1, true)) then return kind end
        end
    end
end

-- Marks from Questie alone, for a unit whose tooltip lists no objective: one per category of its open
-- objectives on the unit, with Questie's count; nil when there are none.
local function QuestieMarks(entries)
    if not entries then return end
    local marks, seen = {}, {}
    for _, entry in pairs(entries) do
        local o = entry.objective
        local kind = type(o) == "table" and QUESTIE_KINDS[o.Icon]
        if kind and QuestieOpen(o) then
            local icon = Icon(kind)
            if not seen[icon] then
                seen[icon] = true
                local have, need = tonumber(o.Collected), tonumber(o.Needed)
                marks[#marks + 1] = { icon = icon, progress = (have and need and need > 1) and (have .. "/" .. need) or "" }
                if #marks == 2 then break end   -- (MAX_MARKS, below)
            end
        end
    end
    return marks[1] and marks or nil
end

--- The icon for a tooltip quest objective line: Questie's category for it when Questie has one, else
--- classified by its matching quest log objective.
local function ObjectiveIcon(text, hostile, questie)
    local kind = QuestieKindFor(questie, text)
    if kind then return Icon(kind) end
    return ClassifyObjective(ObjectiveKinds()[NormalizeObjective(text)], text, hostile)
end

--- Whether the player can attack the unit; nil when unknown (e.g. a secret value in instances).
local function IsHostile(unit)
    local ok, hostile = pcall(UnitCanAttack, "player", unit)
    if not ok or (issecretvalue and issecretvalue(hostile)) then return nil end
    return hostile and true or false
end

-- A unit that counts for objectives of different kinds (e.g. a kill and a loot objective) shows one
-- icon per kind, side by side, up to this many.
local MAX_MARKS = 2

-- Returns a list of marks ({ icon = atlas, progress = text }) for the unit's incomplete objectives,
-- one per kind in tooltip order, or nil when there are none. Progress is "3/8" for counted
-- objectives, "35%" for progress bars, and "" when the line has neither.
local function QuestInfo(unit)
    local data = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit)
    if not data then return end
    if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
    local marks, seen = {}, {}
    local hostile = IsHostile(unit)
    local questie = QuestieObjectives(unit)
    -- In a group, the tooltip lists each party member who shares the quest: a QuestPlayer line with
    -- their name, then their objectives. Only the player's own objectives count: those before any
    -- name line under a quest title, or under the player's own name.
    -- With Group Objectives on, a party member's open objective still shows its icon (no progress:
    -- the count is theirs), after the player's own marks and only for a kind they don't already show.
    local types = Enum.TooltipDataLineType
    local me = UnitName("player")
    local mine = true
    local party = {}
    for _, line in ipairs(data.lines or {}) do
        if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
        if line.type == types.QuestTitle then
            mine = true
        elseif types.QuestPlayer and line.type == types.QuestPlayer then
            local name = line.leftText and line.leftText:match("^%s*([^%-]+)")
            mine = name ~= nil and strtrim(name) == me
        elseif not mine and DB.groupObjectives and line.type == types.QuestObjective and line.leftText then
            if not line.completed then
                local text = line.leftText
                local have, need = text:match("^(%d+)%s*/%s*(%d+)")
                local percent = not have and text:match("(%d+)%%")
                if line.completed == false or (have and tonumber(have) < tonumber(need))
                    or (percent and tonumber(percent) < 100) or not (have or percent) then
                    party[#party + 1] = ObjectiveIcon(text, hostile, questie)
                end
            end
        elseif mine and line.type == types.QuestObjective and line.leftText then
            local text = line.leftText
            local have, need = text:match("^(%d+)%s*/%s*(%d+)")
            local percent = not have and text:match("(%d+)%%")
            local incomplete
            if line.completed ~= nil then
                incomplete = not line.completed
            elseif have then
                incomplete = tonumber(have) < tonumber(need)
            elseif percent then
                incomplete = tonumber(percent) < 100
            else
                incomplete = true
            end
            if incomplete then
                local icon = ObjectiveIcon(text, hostile, questie)
                if not seen[icon] and #marks < MAX_MARKS then
                    seen[icon] = true
                    marks[#marks + 1] = {
                        icon = icon,
                        progress = have and (have .. "/" .. need) or percent and (percent .. "%") or "",
                    }
                end
            end
        end
    end
    for _, icon in ipairs(party) do
        if #marks == MAX_MARKS then break end
        if not seen[icon] then
            seen[icon] = true
            marks[#marks + 1] = { icon = icon, progress = "" }
        end
    end
    return marks[1] and marks or nil
end

--- Progress text for a quest log objective: "73%" for progress bars, "3/8" for counts, else "".
local function ObjectiveProgress(questID, o)
    if o.type == "progressbar" and GetQuestProgressBarPercent then
        local ok, percent = pcall(GetQuestProgressBarPercent, questID)
        if ok and percent and not (issecretvalue and issecretvalue(percent)) then
            return math.floor(percent) .. "%"
        end
    end
    if o.numRequired and o.numRequired > 1 then
        return o.numFulfilled .. "/" .. o.numRequired
    end
    return ""
end

-- Instance fallback: tooltips are secret there, so guess the objective kind from the quest log.
-- Picks the incomplete objective whose text names the unit; else, for a hostile unit, a kill
-- objective if there is one (talk/interact objectives don't apply to enemies), then a loot one;
-- else the one kind if all open objectives on this map share it. Returns atlas and progress text
-- (progress only when it's clear which objective it is).
local function LogGuess(unit)
    local name = UnitName(unit)
    if issecretvalue and issecretvalue(name) then name = nil end
    local hostile = IsHostile(unit)
    local perKind, kindCount, only, count = {}, 0, nil, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.isOnMap then
            for _, o in ipairs(C_QuestLog.GetQuestObjectives(info.questID) or {}) do
                if not o.finished and o.type then
                    local icon = ClassifyObjective(o.type, o.text, hostile)
                    local prog = ObjectiveProgress(info.questID, o)
                    if name and o.text and o.text:find(name, 1, true) then return icon, prog end
                    local entry = perKind[icon]
                    if entry then
                        entry.count = entry.count + 1
                    else
                        perKind[icon] = { count = 1, progress = prog }
                        kindCount = kindCount + 1
                    end
                    count = count + 1
                    only = { icon, prog }
                end
            end
        end
    end
    if count == 1 then return only[1], only[2] end

    --- The icon for a kind, with its progress when it's the only objective of that kind.
    local function pick(icon)
        local entry = perKind[icon]
        return icon, entry.count == 1 and entry.progress or ""
    end

    -- Unknown counts as hostile: in instances, where this fallback runs, addons don't get friendly
    -- nameplates, so a unit whose hostility is hidden is almost certainly an enemy.
    if hostile ~= false then
        if perKind[Icon("kill")] then return pick(Icon("kill")) end
        if perKind[Icon("loot")] then return pick(Icon("loot")) end
    end
    if kindCount == 1 then return pick(only[1]) end
    return Icon("loot"), "" -- mixed or unknown: loot is the likelier kind for a named-but-unmatched mob
end

local GAP = 2 -- between the icon, the second icon and the progress text

-- The whole mark's width: the icon, the second icon if shown, and the progress text if any.
local function MarkWidth(f)
    local width = DB.size
    if f.tex2:IsShown() then width = width + GAP + DB.size end
    local text = f.text:GetText()
    if text and text ~= "" then
        local ok, w = pcall(f.text.GetStringWidth, f.text)
        if not ok or not w or (issecretvalue and issecretvalue(w)) then w = #text * 6 end -- (a guess, if it can't be read)
        width = width + GAP + w
    end
    return width
end

-- Avoid Auras. Nameplates are restricted on this client: an addon can't measure them or anything on
-- them (GetRect fails), so it can't tell whether an aura icon overlaps the mark. It can still anchor
-- to Blizzard's frames, so while the aura list on the mark's side has icons, the mark is anchored past
-- that list instead: right of the crowd control icons (Right), left of the buff icons (Left), above the
-- debuff icons (Center), Aura Spacing away.
local AURA_LISTS = { "DebuffListFrame", "BuffListFrame", "CrowdControlListFrame" }
local SIDE_LIST = { right = "CrowdControlListFrame", left = "BuffListFrame", center = "DebuffListFrame" }
local FAR = 1000 -- (the helper's far edges: well past anything on a nameplate, so it never turns inside out)

-- how many of a list's aura icons are showing (only whether they're shown is read)
local function ShownCount(list)
    if not (list and list:IsShown()) then return 0 end
    local n = 0
    for _, item in ipairs({ list:GetChildren() }) do
        local ok, shown = pcall(item.IsShown, item)
        if ok and shown and not (issecretvalue and issecretvalue(shown)) then n = n + 1 end
    end
    return n
end

-- the aura list in the way of the mark: the one on its side, while it has icons
local function ListInTheWay(plate)
    local auras = plate.UnitFrame and plate.UnitFrame.AurasFrame
    local list = auras and auras[SIDE_LIST[DB.side] or SIDE_LIST.right]
    if list and ShownCount(list) > 0 then return list end
    if DB.side ~= "left" and DB.side ~= "center" then
        -- (loss of control shows in the crowd control icons' place)
        local loc = auras and auras.LossOfControlFrame
        if loc and loc:IsShown() then return loc end
    end
end

-- Place a plate's mark again whenever one of its aura lists lays itself out (Blizzard does that each
-- time the unit's auras change) or loss of control shows or hides. Nameplates swap their unit frame
-- (and so their aura lists) from a pool, so each is hooked the first time it's seen on any plate and
-- finds its plate's mark when called. Secure hooks: Blizzard's code isn't touched.
local Place
local hooked = setmetatable({}, { __mode = "k" })

local function Replace(frame)
    if not DB.avoidAuras then return end
    local unitFrame = frame:GetParent() and frame:GetParent():GetParent()
    local f = unitFrame and icons[unitFrame:GetParent()]
    if f and f:IsShown() then Place(f) end
end

local function HookAuraLists(plate)
    local auras = plate.UnitFrame and plate.UnitFrame.AurasFrame
    if not auras then return end
    for _, key in ipairs(AURA_LISTS) do
        local list = auras[key]
        if list and list.Layout and not hooked[list] then
            hooked[list] = true
            hooksecurefunc(list, "Layout", Replace)
        end
    end
    local loc = auras.LossOfControlFrame
    if loc and not hooked[loc] then
        hooked[loc] = true
        loc:HookScript("OnShow", Replace)
        loc:HookScript("OnHide", Replace)
    end
end

-- The mark reads left to right (icon, second icon, progress text). Placed by the whole mark:
-- Right: its left edge (the icon's) the horizontal offset right of the nameplate.
-- Left: its right edge (the progress text's) the offset left of the nameplate.
-- Center: its middle the offset right of the nameplate's middle.
-- With Avoid Auras and auras in the way, Right and Left measure from the auras' outer edge (the
-- horizontal offset is replaced by Aura Spacing), and Center sits Aura Spacing above the debuffs.
function Place(f)
    local plate, width = f:GetParent(), MarkWidth(f)
    HookAuraLists(plate)
    local list = DB.avoidAuras and ListInTheWay(plate)
    local helper = f.helper
    f:ClearAllPoints()
    if list then
        -- The helper is an empty frame whose corner is where two things meet: the auras' edge on one
        -- axis and the nameplate's middle on the other (anchoring can't take x and y from different
        -- frames in one point). Its far edges are pushed well out so it always has a positive size.
        if not helper then
            helper = CreateFrame("Frame", nil, plate)
            f.helper = helper
        end
        helper:ClearAllPoints()
        if DB.side == "left" then
            helper:SetPoint("TOPRIGHT", list, "TOPLEFT", 0, FAR)
            helper:SetPoint("BOTTOMLEFT", plate, "LEFT", -FAR, 0)
            f:SetPoint("LEFT", helper, "BOTTOMRIGHT", -DB.auraGap - width, DB.y)
        elseif DB.side == "center" then
            helper:SetPoint("TOPRIGHT", list, "TOPRIGHT", FAR, 0)
            helper:SetPoint("BOTTOMLEFT", plate, "CENTER", 0, -FAR)
            f:SetPoint("BOTTOMLEFT", helper, "TOPLEFT", DB.x - width / 2, DB.auraGap)
        else
            helper:SetPoint("TOPLEFT", list, "TOPRIGHT", 0, FAR)
            helper:SetPoint("BOTTOMRIGHT", plate, "RIGHT", FAR, 0)
            f:SetPoint("LEFT", helper, "BOTTOMLEFT", DB.auraGap, DB.y)
        end
    elseif DB.side == "left" then
        f:SetPoint("LEFT", plate, "LEFT", -DB.x - width, DB.y)
    elseif DB.side == "center" then
        f:SetPoint("LEFT", plate, "CENTER", DB.x - width / 2, DB.y)
    else
        f:SetPoint("LEFT", plate, "RIGHT", DB.x, DB.y)
    end
    f.tex2:ClearAllPoints()
    f.tex2:SetPoint("LEFT", f, "RIGHT", GAP, 0)
    f.text:ClearAllPoints()
    f.text:SetPoint("LEFT", f.tex2:IsShown() and f.tex2 or f, "RIGHT", GAP, 0)
end


local function GetIcon(plate)
    if icons[plate] then return icons[plate] end
    local f = CreateFrame("Frame", nil, plate)
    f:SetSize(DB.size, DB.size)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    -- second icon, for a unit that counts for objectives of two different kinds
    f.tex2 = f:CreateTexture(nil, "OVERLAY")
    f.tex2:SetSize(DB.size, DB.size)
    f.tex2:Hide()
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icons[plate] = f
    Place(f)
    return f
end

--- Set an icon frame's textures and progress text from a list of marks (see QuestInfo), without
--- changing whether it's shown. Progress for each mark is listed in the same order as the icons.
local function SetMarks(icon, marks)
    icon.tex:SetAtlas(marks[1].icon)

    local second = marks[2]
    if second then
        icon.tex2:SetAtlas(second.icon)
        icon.tex2:Show()
    else
        icon.tex2:Hide()
    end

    local parts = {}
    if DB.progress then
        for _, mark in ipairs(marks) do
            if mark.progress ~= "" then parts[#parts + 1] = mark.progress end
        end
    end
    icon.text:SetText(table.concat(parts, "  "))
    Place(icon) -- the mark's width changed with its icons and text
end

-- Optional: turn marks off inside instances, where the icon kind is only a guess (see LogGuess).
local function Suppressed()
    if not DB.enabled then return true end
    if not DB.hideInInstances then return false end
    local _, instanceType = IsInInstance()
    return instanceType and instanceType ~= "none"
end

--- Whether the game reports the unit as related to an active quest. False when unknown, or when
--- the answer is a secret value (in instances), since it can't be branched on then.
local function UnitIsQuestRelated(unit)
    if not C_QuestLog.UnitIsRelatedToActiveQuest then return false end
    local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
    if not ok or (issecretvalue and issecretvalue(related)) then return false end
    return related and true or false
end

--- Whether the unit is the player (their own nameplate). UnitIsUnit can return a secret boolean in
--- instances, which can't be branched on; treat that as "not the player".
local function IsPlayer(unit)
    local ok, isPlayer = pcall(UnitIsUnit, unit, "player")
    if not ok or (issecretvalue and issecretvalue(isPlayer)) then return false end
    return isPlayer and true or false
end

local function Update(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local icon = GetIcon(plate)
    if Suppressed() then icon:Hide(); return end
    if IsPlayer(unit) then icon:Hide(); return end
    local ok, marks = pcall(QuestInfo, unit)
    if ok then
        -- no objective line in the tooltip: Questie's objectives on the unit, when it has any (e.g. an NPC
        -- to talk to, or a creature dropping a quest item the game doesn't tie to it)
        if not marks then
            local qok, qmarks = pcall(QuestieMarks, QuestieObjectives(unit))
            marks = qok and qmarks or nil
        end
        if marks then
            SetMarks(icon, marks)
            icon:Show()
        elseif UnitIsQuestRelated(unit) then
            -- no objective line in the tooltip, but the game says this unit is part of an active quest
            -- (e.g. an NPC to talk to, whose tooltip doesn't list the objective)
            SetMarks(icon, { { icon = Icon("interact"), progress = "" } })
            icon:Show()
        else
            icon:Hide()
        end
        return
    end
    -- Tooltip lines are secret (seen in dungeons): fall back to a yes/no quest check, no kind or progress.
    local related = C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest(unit)
    local gok, atlas, prog = pcall(LogGuess, unit)
    SetMarks(icon, { { icon = gok and atlas or Icon("loot"), progress = gok and prog or "" } })
    if issecretvalue and issecretvalue(related) then
        -- can't branch on a secret boolean, but SetShown may accept one; hide if it doesn't
        if not pcall(icon.SetShown, icon, related) then icon:Hide() end
    else
        icon:SetShown(related and true or false)
    end
end

--- The unit a nameplate currently shows, or nil. Retail (12.x) nameplates store it as unitToken;
--- namePlateUnitToken is the older field name, kept as a fallback.
local function PlateUnit(plate)
    return plate.unitToken or plate.namePlateUnitToken
end

local function UpdateAll()
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = PlateUnit(plate)
        if unit then Update(unit) end
    end
end

-- Quest log events often fire several times in a row (looting, objective progress), and each one
-- rescans every visible nameplate. Batch them into at most one rescan per UPDATE_DELAY seconds.
local UPDATE_DELAY = 0.2
local updatePending = false

local function ScheduleUpdateAll()
    if updatePending then return end
    updatePending = true
    C_Timer.After(UPDATE_DELAY, function()
        updatePending = false
        UpdateAll()
    end)
end

-- A unit's quest lines are sometimes not in its tooltip data yet when its nameplate first appears,
-- which would leave it unmarked until the next quest log change. Look once more after this delay.
local RECHECK_DELAY = 0.5

local function RecheckLater(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    C_Timer.After(RECHECK_DELAY, function()
        if PlateUnit(plate) == unit then Update(unit) end
    end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD") -- zoning in or out of an instance
ev:SetScript("OnEvent", function(_, event, unit)
    if event == "ADDON_LOADED" then
        -- adopt the saved table once this addon's saved variables have loaded
        if unit == addonName then
            if type(ForeverQuestMarkDB) == "table" then Mixin(DB, ForeverQuestMarkDB) end
            DB._savedAt = nil -- leftover from the old Forever-client save workaround
            -- the old "other" icon (talk, interact and the rest, before they had their own) carries on as
            -- the interact icon
            if rawget(DB, "other") then
                if not rawget(DB, "interact") then DB.interact = DB.other end
                DB.other = nil
            end
            ForeverQuestMarkDB = DB
            if next(icons) then Relayout() end
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        Update(unit)
        RecheckLater(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate.GetNamePlateForUnit(unit)
        if plate and icons[plate] then icons[plate]:Hide() end
    else
        objectiveKinds = nil -- quest log (or zone) changed: rebuild the objective kinds on next use
        ScheduleUpdateAll()
    end
end)

function Relayout()
    for _, f in pairs(icons) do
        f:SetSize(DB.size, DB.size)
        f.tex2:SetSize(DB.size, DB.size)
        Place(f)
    end
    UpdateAll()
end

-- Settings page (Options > AddOns), drawn in Blizzard's settings style by SettingsKit ----------------
local Kit = ns.SettingsKit
local page = Kit.NewPage("Nameplate Quest Markers", { onDefaults = function() wipe(DB); Relayout() end })
local function Setter(key) return function(v) DB[key] = v; Relayout() end end
local function Getter(key) return function() return DB[key] end end

-- Blizzard atlases that read well as a quest mark; ones missing on this client are skipped.
local ICONS = {
    -- the cursor's icons
    "Crosshair_Attack_32", "Crosshair_pickup_32", "Crosshair_lootall_32", "Crosshair_Interact_32", "Crosshair_speak_32",
    "Crosshair_Quest_32", "Crosshair_Questturnin_32", "Crosshair_Directions_32", "Crosshair_Inspect_32",
    -- the map pin
    "Waypoint-MapPin-Tracked",
}
local function IconOptions()
    local out, seen = {}, {}
    local function Add(atlas)
        out[#out + 1] = { value = atlas, label = ("|A:%s:18:18|a  %s"):format(atlas, atlas) }
        seen[atlas] = true
    end
    for _, atlas in ipairs(ICONS) do
        if C_Texture.GetAtlasInfo(atlas) then Add(atlas) end
    end
    -- keep a custom atlas set by /fqm selectable
    for _, key in ipairs(KINDS) do
        if not seen[DB[key]] then Add(DB[key]) end
    end
    return out
end

local function Pixels(v) return tostring(v) end

page:Header("General")
page:Checkbox("Enabled", Getter("enabled"), Setter("enabled"), "Show quest marks on nameplates.")
page:Checkbox("Show Progress", Getter("progress"), Setter("progress"), "Show the objective progress (e.g. 3/8 or 35%) next to the icon.")
page:Checkbox("Group Objectives", Getter("groupObjectives"), Setter("groupObjectives"),
    "Also mark units a party member still needs for a quest you share, after your own part is done. The icon shows without progress, since the count is theirs.")
page:Checkbox("Hide Inside Instances", Getter("hideInInstances"), Setter("hideInInstances"),
    "Turn marks off in dungeons, raids, battlegrounds and arenas. Inside instances the icon kind is guessed from the quest log and may be wrong when kill and loot quests mix.")
page:Header("Icon")
page:Slider("Size", 10, 48, 1, Getter("size"), Setter("size"), Pixels, "Size of the quest mark.")
page:Dropdown("Position", {
    { label = "Left", value = "left", tooltip = "Left of the nameplate." },
    { label = "Center", value = "center", tooltip = "Over the middle of the nameplate." },
    { label = "Right", value = "right", tooltip = "Right of the nameplate." },
}, Getter("side"), Setter("side"), "Which side of the nameplate the quest mark goes on.")
page:Slider("Horizontal Offset", -60, 60, 1, Getter("x"), Setter("x"), Pixels,
    "Right: the gap from the nameplate to the icon. Left: the gap from the progress text to the nameplate. Center: how far right of the nameplate's middle the middle of the icon and text is. Higher is further out (Center: further right).")
page:Slider("Vertical Offset", -60, 60, 1, Getter("y"), Setter("y"), Pixels, "Distance up or down from the middle of the nameplate.")
page:Checkbox("Avoid Auras", Getter("avoidAuras"), Setter("avoidAuras"),
    "While the nameplate shows aura icons on the quest mark's side, move the mark past them: right of the crowd control icons when Position is Right, left of the buff icons when Left, above the debuff icons when Center. It moves back when they're gone.")
page:Slider("Aura Spacing", 0, 20, 1, Getter("auraGap"), Setter("auraGap"), Pixels,
    "The space between the aura icons and the quest mark while it's moved past them (in place of the horizontal offset for Left and Right, and the vertical offset for Center).", { indent = true, enabled = Getter("avoidAuras") })
page:Header("Objective Icons")
page:Dropdown("Slay Objectives", IconOptions, Getter("kill"), Setter("kill"),
    "Units you need to kill, including progress bars you fill by killing them.")
page:Dropdown("Loot Objectives", IconOptions, Getter("loot"), Setter("loot"), "Units that drop quest items.")
page:Dropdown("Object Objectives", IconOptions, Getter("object"), Setter("object"),
    "Units counted by a quest's object objectives (things to use or click).")
page:Dropdown("Event Objectives", IconOptions, Getter("event"), Setter("event"),
    "Units counted by event objectives, and progress bars you don't fill by killing.")
page:Dropdown("Talk Objectives", IconOptions, Getter("talk"), Setter("talk"),
    "Friendly NPCs a quest asks you to speak with.")
page:Dropdown("Interact Objectives", IconOptions, Getter("interact"), Setter("interact"),
    "Units the game ties to one of your quests without naming an objective on them, and any other kind of objective.")
Kit.Register(page)

local debugFrame -- reused by /fqm debug to test whether SetShown accepts a secret boolean

SLASH_FOREVERQUESTMARK1 = "/fqm"
SlashCmdList.FOREVERQUESTMARK = function(msg)
    local cmd, arg = msg:match("^(%S+)%s*(.-)$")
    if (cmd == "x" or cmd == "y" or cmd == "size") and tonumber(arg) then
        DB[cmd] = tonumber(arg)
    elseif cmd == "side" and (arg == "left" or arg == "center" or arg == "right") then
        DB.side = arg
    elseif cmd and tContains(KINDS, cmd) and arg ~= "" then
        if not C_Texture.GetAtlasInfo(arg) then print("Nameplate Quest Markers: no atlas named " .. arg); return end
        DB[cmd] = arg
    elseif cmd == "reset" then
        wipe(DB)
    elseif cmd == "debug" then
        -- dump what the tooltip API returns for the target, to see why marks fail (e.g. in instances)
        local p = function(...) print("|cff33ff99FQM|r", ...) end
        local _, itype = IsInInstance()
        p("instance:", tostring(itype), "suppressed:", tostring(Suppressed()), "exists:", tostring(UnitExists("target")))
        local ok, data = pcall(C_TooltipInfo.GetUnit, "target")
        if not ok then p("GetUnit error:", data); return end
        if not data then p("GetUnit returned nil"); return end
        p("lines:", data.lines and #data.lines or "none")
        for i, line in ipairs(data.lines or {}) do
            local secret = issecretvalue and (issecretvalue(line.leftText) or issecretvalue(line.type))
            if secret then p(i, "<secret>")
            else p(i, "type", tostring(line.type), tostring(line.leftText)) end
        end
        local rel = C_QuestLog.UnitIsRelatedToActiveQuest and C_QuestLog.UnitIsRelatedToActiveQuest("target")
        if issecretvalue and issecretvalue(rel) then
            debugFrame = debugFrame or CreateFrame("Frame")
            p("RelatedToQuest: <secret>, SetShown accepts it:", tostring((pcall(debugFrame.SetShown, debugFrame, rel))))
            debugFrame:Hide()
        else p("RelatedToQuest:", tostring(rel)) end
        p("LogGuess:", pcall(LogGuess, "target"))
        -- Questie's objectives on the target, with the category each maps to
        if not QuestieLookup() then
            p("Questie: not loaded")
        else
            local entries = QuestieObjectives("target")
            if not entries then p("Questie: nothing on this unit") end
            for key, entry in pairs(entries or {}) do
                local o = entry.objective or {}
                p("Questie", key, tostring(o.Description), "icon type", tostring(o.Icon), "->",
                    tostring(QUESTIE_KINDS[o.Icon]), "completed", tostring(o.Completed))
            end
        end
        -- Avoid Auras: the target's aura icons as the addon sees them, and which list the mark sits past
        local plate = C_NamePlate.GetNamePlateForUnit("target")
        local auras = plate and plate.UnitFrame and plate.UnitFrame.AurasFrame
        if auras then
            p("aura icons: debuffs", ShownCount(auras.DebuffListFrame), "buffs", ShownCount(auras.BuffListFrame),
                "crowd control", ShownCount(auras.CrowdControlListFrame), "loss of control",
                tostring(auras.LossOfControlFrame and auras.LossOfControlFrame:IsShown()))
            local list = DB.avoidAuras and ListInTheWay(plate)
            p("position:", DB.side, "avoid auras:", tostring(DB.avoidAuras), "anchored past:",
                list and (list == auras.LossOfControlFrame and "loss of control" or list == auras.DebuffListFrame
                    and "debuffs" or list == auras.BuffListFrame and "buffs" or "crowd control") or "nothing")
        else
            p("no auras frame on the target's nameplate")
        end
        local qok, marks = pcall(QuestInfo, "target")
        if not qok then
            p("QuestInfo error:", tostring(marks))
        elseif not marks then
            p("QuestInfo: no objective lines")
        else
            for i, mark in ipairs(marks) do p("QuestInfo mark", i, mark.icon, mark.progress) end
        end
        return
    else
        Kit.Open(page)
        return
    end
    Relayout()
    page:Refresh() -- keep an open settings page in sync with the change
end
