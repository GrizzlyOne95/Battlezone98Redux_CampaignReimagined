-- Tran03Mission: faithful stock Battlezone 98 Redux / Lua 5.1 port.
-- Source blob: 629c7201ed63e70e4afede182f1f3ad5cca189b4.
-- Complete source, including every comment, unused member and native save/load:
-- References/Tran03Source/Tran03Mission.cpp.
-- No campaign helpers, EXU or OpenShim required.

local function NewState()
    return {
        found = false, start_done = false,
        first_message = false, second_message = false,
        third_message = false, fourth_message = false,
        fifth_message = false, fifthb_message = false,
        sixth_message = false, seventh_message = false,
        eighth_message = false, scav_died = false,
        delay_message = 99999.0,
        -- Unused native bool members, deterministically initialized here:
        first_objective = false, second_objective = false,
        third_objecitve = false, combat_start = false, combat_start2 = false,
        start_path1 = false, start_path2 = false,
        start_path3 = false, start_path4 = false,
        hint1 = false, hint2 = false, jump_start = false, dummy = 0,
        -- scav, attacker, geyser, recycler: native zero handles become nil.
        -- p1..p4 are unused native AiPath pointers; no Lua equivalent needed.
    }
end
local M = NewState()
local function Alive(h)
    return h ~= nil and h ~= 0 and IsAlive(h)
end
local function Valid(h)
    return h ~= nil and h ~= 0 and IsValid(h)
end

function Start()
    -- State exists at script load, before initial AddObject callbacks.
    -- Do not reset it here: that could discard the source's scav tracking.
end

-- this is the handle thing brad made for me
function AddObject(h)
    if Valid(h) and GetTeamNum(h) == 1 and IsOdf(h, "avscav") then
        M.found = true
        M.scav = h
    end
end

function Update(dt)
    local now = GetTime()
    if not M.start_done then
        AudioMessage("tran0301.wav")
        AudioMessage("tran0302.wav")
        M.geyser = GetHandle("eggeizr111_geyser")
        M.recycler = GetHandle("avrecy-1_recycler")
        M.attacker = GetHandle("svfigh-1_wingman")
        if Valid(M.recycler) then
            SetObjectiveOn(M.recycler)
            SetObjectiveName(M.recycler, "recycler")
        end
        SetScrap(1, 7)
        ClearObjectives()
        AddObjective("tran0301.otf", "white")
        AddObjective("tran0302.otf", "white")
        M.start_done = true
    end

    if M.start_done and not M.first_message and Alive(M.recycler) and IsSelected(M.recycler) then
        AudioMessage("tran0303.wav")
        -- Switch objective
        SetObjectiveOff(M.recycler)
        if Valid(M.geyser) then
            SetObjectiveOn(M.geyser)
            SetObjectiveName(M.geyser, "Check Point 1")
        end
        M.first_message = true
    end

    if M.first_message and not M.second_message and Alive(M.recycler) then
        if not IsDeployed(M.recycler) then
            AudioMessage("tran0304.wav")
            M.second_message = true
        end
    end

    if M.second_message and not M.third_message and Alive(M.recycler) and Valid(M.geyser)
        and GetDistance(M.recycler, M.geyser) < 200.0 then
        -- ClearObjectives();
        -- AddObjective("tran0301.otf",GREEN);
        AudioMessage("tran0305.wav")
        M.third_message = true
    end
    if M.third_message and not M.fourth_message and Alive(M.recycler) and IsSelected(M.recycler) then
        AudioMessage("tran0306.wav")
        M.fourth_message = true
    end

    if M.third_message and not M.fifth_message and Alive(M.recycler) then
        if IsDeployed(M.recycler) then
            if Valid(M.geyser) then SetObjectiveOff(M.geyser) end
            ClearObjectives()
            AddObjective("tran0301.otf", "green")
            AddObjective("tran0302.otf", "white")
            AudioMessage("tran0307.wav")
            M.fifth_message = true
        end
    end
    -- PORT FIX: the native fifthb branch dereferences a destroyed recycler.
    -- Guard its selection query; living-recycler narration is unchanged.
    if M.fifth_message and not M.fifthb_message and Alive(M.recycler) and IsSelected(M.recycler) then
        AudioMessage("tran0309.wav")
        M.fifthb_message = true
    end
    if Alive(M.attacker) and not M.sixth_message then
        -- Preserve source AddHealth(50) per Update, including its frame dependence.
        AddHealth(M.attacker, 50.0)
    end

    -- PORT FIX: team scrap replaces the native recycler pointer dereference.
    -- Require the recycler alive so its destruction enters the existing failure
    -- branch instead of issuing combat orders through a destroyed object.
    if M.fifth_message and not M.sixth_message and Alive(M.recycler) then
        local money = GetScrap(1)
        if money < 5 and M.found then
            AudioMessage("tran0308.wav")
            -- scav=GetHandle("avscav-1_scavenger");
            M.sixth_message = true
            M.delay_message = now + 5.0
            -- info.priority=1;  // so the computer doesn't interupt
            -- info.where=NULL;  // just in case
            -- Stock Attack supplies CMD_ATTACK, target and priority directly.
            -- PORT FIX: native SetCommand dereferences an already-killed attacker.
            -- Skip that invalid command; the existing kill-complete branch still
            -- runs below in the same frame, preserving early-kill progression.
            if Alive(M.attacker) and Alive(M.scav) then Attack(M.attacker, M.scav, 1) end
        end
    end
    if not M.scav_died and (not Alive(M.recycler) or (M.sixth_message and not Alive(M.scav))) then
        M.scav_died = true
        AudioMessage("tran0313.wav")
        FailMission(now + 10.0, "tran03l1.des")
    end
    if now > M.delay_message then
        -- "protect the scavenger"
        -- AudioMessage("tran0311.wav");
        M.delay_message = 99999.0
    end
    if M.sixth_message and not M.seventh_message and not Alive(M.attacker) then
        -- you killed him
        AudioMessage("tran0314.wav")
        M.seventh_message = true
    end
    -- PORT FIX: native success could follow FailMission on the same frame,
    -- and also dereferenced a destroyed recycler. Keep failure authoritative
    -- using the existing scav_died latch. All successful tutorial triggers,
    -- scrap thresholds, audio and the twenty-second completion delay are intact.
    if M.seventh_message and not M.eighth_message and not M.scav_died and Alive(M.recycler) then
        local money = GetScrap(1)
        if money > 1 then
            AudioMessage("tran0310.wav")
            AudioMessage("tran0315.wav")
            M.eighth_message = true
            SucceedMission(now + 20.0, "tran03w1.des")
        end
    end
end

function Save()
    return M
end
function Load(state)
    -- LuaMission serializes tables and remaps handles, replacing native
    -- Load/Save/PostLoad unions and ConvertHandle. Do not replay Setup/audio.
    M = state
end
