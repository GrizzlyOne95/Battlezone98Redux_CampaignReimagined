-- Faithful stock misn14 port for Battlezone 98 Redux / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/Misn14Mission.cpp.
-- All disabled statements remain below as original C++ comments. The complete
-- native source, including serialization and comments, is in References/Misn14Source/.
-- Single player; only stock BZR APIs are required.

local NEVER = 99999.0
local function NewState()
    return {
        -- bools (including unused source fields, for cut-content reconstruction)
        start_done = false, camera1 = false, camera2 = false, camera3 = false,
        alien_warning = false, alien_attack = false, cca_surrender = false,
        gen_message = false, rescue_message = false, rescue_start = false,
        rescue_reminder = false, found = false, pick_up = false,
        won = false, lost = false,
        finishcam1 = false, finishcam2 = false, finishcam3 = false,
        rescuecam1 = false, rescuecam2 = false, rescuecam3 = false,
        rescue1 = false, rescue2 = false, rescue3 = false,
        -- floats. Native Load initializes even the two not assigned in Setup.
        camera_time = NEVER, alien_time = NEVER, pick_up_time = NEVER,
        beacon_time1 = NEVER, beacon_time2 = NEVER, beacon_time3 = NEVER,
        rescue_finish1 = NEVER, rescue_finish2 = NEVER, rescue_finish3 = NEVER,
        next_second = NEVER,
        -- Initialize the darned handles. audmsg is an audio message in Lua,
        -- not an object handle; nil represents native NULL for all of these.
        beacon1 = nil, beacon2 = nil, beacon3 = nil, audmsg = nil,
        player = nil, recy = nil, cam1 = nil, cam2 = nil, cam3 = nil, cam4 = nil,
        erecy = nil, base = nil, apc = nil, guy1 = nil, guy2 = nil, guy3 = nil,
        tow1 = nil, tow2 = nil, tow3 = nil, tow4 = nil,
        -- integers
        wave_count = 0,
    }
end
local M = NewState()

-- Native distance queries with nonexistent objects return a very large distance.
-- BUGFIX / Lua adaptation: never feed nil/removed/dead objects to the overloaded
-- Lua GetDistance. Otherwise an absent APC can trigger a pickup or raise an error.
-- Live-object thresholds and their order are unchanged; absent objects are far away.
local function Distance(a, b)
    if a == nil or a == 0 or b == nil or b == 0 then return math.huge end
    if not IsAlive(a) or not IsAlive(b) then return math.huge end
    return GetDistance(a, b)
end

local function IsOdfBase(h, name)
    return IsValid(h) and (IsOdf(h, name) or IsOdf(h, name .. ".odf"))
end

local function ApcCamera()
    -- BUGFIX: the native script blindly uses an APC destroyed during a short
    -- rescue shot. Release the camera if it disappears; rescue timers still run.
    if IsAlive(M.apc) then
        CameraObject(M.apc, 1000, 1000, 1000, M.apc)
    end
    return not IsAlive(M.apc) or CameraCancelled() or GetTime() > M.camera_time
end

function Start()
    -- M is initialized at chunk load, before AddObject can discover a map APC.
    -- Do not reset it here and erase objects reported before Start.
    -- LuaMission needs the native AiMission's strategic-AI behavior explicitly
    -- enabled for the CCA AIP. SetAIControl is only safe at startup, never Update.
    SetAIControl(2, true)
end

function AddObject(h)
    if IsOdfBase(h, "avapc") and GetTeamNum(h) == 1 then
        M.found = true
        -- BUGFIX: original `apc = h` replaced the scientist carrier every time
        -- another APC was built. Freeze the selected handle once pick_up begins:
        -- the same carrier must return home or die. Selection before pickup and
        -- the normal one-APC gameplay flow remain exactly as in the source.
        if not M.pick_up then M.apc = h end
    end
end

function Update(dt)
    -- Original disabled native pointer declaration:
    --GameObject *fcycler,*ecycler;
    M.player = GetPlayerHandle()
    if not M.start_done then
        M.recy = GetHandle("avrecy-1_recycler")
        M.erecy = GetHandle("svrecy-1_recycler")
        M.base = GetHandle("sbbarr0_i76building")
        SetAIP("misn14.aip")
        --AddPilot(1,10);
        AddPilot(2, 30)
        SetScrap(1, 30)
        SetScrap(2, 45)
        M.cam1 = GetHandle("apcamr0_camerapod")
        M.cam2 = GetHandle("apcamr1_camerapod")
        M.cam3 = GetHandle("apcamr2_camerapod")
        M.cam4 = GetHandle("apcamr3_camerapod")
        M.tow1 = GetHandle("sbtowe0_turret")
        M.tow2 = GetHandle("sbtowe1_turret")
        M.tow3 = GetHandle("sbtowe55_turret")
        M.tow4 = GetHandle("sbtowe56_turret")
        if IsValid(M.cam1) then SetObjectiveName(M.cam1, "Foothill Geysers") end
        if IsValid(M.cam2) then SetObjectiveName(M.cam2, "Canyon Geysers") end
        if IsValid(M.cam3) then SetObjectiveName(M.cam3, "CCA Base") end
        if IsValid(M.cam4) then SetObjectiveName(M.cam4, "Plateau Geysers") end
        M.start_done = true
        M.next_second = GetTime() + 1.0
        M.camera1 = true
        CameraReady()
        M.camera_time = GetTime() + 12.0
        M.audmsg = AudioMessage("misn1401.wav")
        if IsAlive(M.base) then
            SetMaxHealth(M.base, 100000.0)
            M.next_second = GetTime() + 1.0
        end
    end
    if M.camera1 then
        if IsValid(M.recy) then CameraPath("cam_path1", 2000, 1000, M.recy) end
    end
    if M.camera1 and (GetTime() > M.camera_time or CameraCancelled()) then
        -- Original disabled statement (the briefing was combined):
        -- StopAudioMessage(audmsg);
        -- Now the message is longer and see below
        M.camera1 = false
        M.camera2 = true
        M.camera_time = GetTime() + 15.0
        -- audmsg=AudioMessage("misn1402.wav");
        -- The above message is part of the first..
    end
    if M.camera2 then
        if IsValid(M.recy) then CameraPath("cam_path2", 2000, 500, M.recy) end
    end
    if M.camera2 and (GetTime() > M.camera_time or CameraCancelled()) then
        if M.audmsg ~= nil then StopAudioMessage(M.audmsg) end
        M.camera2 = false
        CameraFinish()
        ClearObjectives()
        AddObjective("misn1401.otf", "white")
        M.alien_time = GetTime() + 720.0 -- six minutes to alien arrival
        -- Source comment says six minutes, but the active value is 720 (twelve).
        -- Preserve the numeric value; do not restore an earlier shorter delay.
        M.beacon_time1 = GetTime() + 15.0
    end
    --[[
        Rescue the
        NSDF
    ]]
    if GetTime() > M.beacon_time1 then
        AudioMessage("misn1416.wav")
        M.beacon_time1 = NEVER
        M.beacon1 = BuildObject("apcamr", 1, "rescue1")
        M.guy1 = BuildObject("aspilo", 1, "help1")
        M.guy2 = BuildObject("aspilo", 1, "help2")
        M.guy3 = BuildObject("aspilo", 1, "help3")
        Defend(M.guy1)
        Defend(M.guy2)
        Defend(M.guy3)
        SetObjectiveName(M.beacon1, "Rescue 1")
        SetObjectiveOn(M.beacon1)
    end
    if M.beacon1 ~= nil and Distance(M.player, M.beacon1) < 200.0
        and not M.rescue_reminder and Distance(M.apc, M.beacon1) > 300.0 then
        --[[
            Bring in an APC to
            rescue the survivors.
        ]]
        AudioMessage("misn1415.wav")
        M.rescue_reminder = true
    end
    if not M.lost and M.beacon1 ~= nil and not M.rescue1
        and (not IsAlive(M.guy1) or not IsAlive(M.guy2) or not IsAlive(M.guy3)) then
        AudioMessage("misn1421.wav")
        FailMission(GetTime() + 15.0, "misn14l2.des")
        M.lost = true
    end
    if M.beacon1 ~= nil and M.apc ~= nil and not M.rescue1
        and Distance(M.apc, M.beacon1) < 100.0 then
        M.rescue1 = true
        Goto(M.guy1, M.beacon1)
        Goto(M.guy2, M.beacon1)
        Goto(M.guy3, M.beacon1)
        M.rescue_finish1 = GetTime() + 25.0
        AudioMessage("misn1409.wav")
        M.camera_time = GetTime() + 3.0
        CameraReady()
        M.rescuecam1 = true
    end
    if M.rescuecam1 then
        if ApcCamera() then
            CameraFinish()
            M.rescuecam1 = false
        end
    end
    if M.beacon1 ~= nil and M.rescue1 and M.rescue_finish1 < GetTime() then
        --[[
            We're done here
        ]]
        if IsAlive(M.guy1) then RemoveObject(M.guy1) end
        if IsAlive(M.guy2) then RemoveObject(M.guy2) end
        if IsAlive(M.guy3) then RemoveObject(M.guy3) end
        if IsAlive(M.beacon1) then RemoveObject(M.beacon1) end
        M.beacon_time2 = GetTime() + 10.0
        CameraReady()
        AudioMessage("misn1417.wav")
        M.finishcam1 = true
        M.rescue_finish1 = NEVER
        M.camera_time = GetTime() + 3.0
    end
    if M.finishcam1 then
        if ApcCamera() then
            CameraFinish()
            M.finishcam1 = false
        end
    end
    if GetTime() > M.beacon_time2 then
        M.beacon_time2 = NEVER
        M.beacon2 = BuildObject("apcamr", 1, "rescue2")
        M.guy1 = BuildObject("aspilo", 1, "help4")
        M.guy2 = BuildObject("aspilo", 1, "help5")
        M.guy3 = BuildObject("aspilo", 1, "help6")
        Defend(M.guy1)
        Defend(M.guy2)
        Defend(M.guy3)
        SetObjectiveName(M.beacon2, "Rescue 2")
        SetObjectiveOn(M.beacon2)
    end
    if not M.lost and M.beacon2 ~= nil and not M.rescue2
        and (not IsAlive(M.guy1) or not IsAlive(M.guy2) or not IsAlive(M.guy3)) then
        M.lost = true
        AudioMessage("misn1421.wav")
        FailMission(GetTime() + 15.0, "misn14l2.des")
    end
    if M.beacon2 ~= nil and M.apc ~= nil and not M.rescue2
        and Distance(M.apc, M.beacon2) < 100.0 then
        M.rescue2 = true
        Goto(M.guy1, M.beacon2)
        Goto(M.guy2, M.beacon2)
        Goto(M.guy3, M.beacon2)
        M.rescue_finish2 = GetTime() + 25.0
        AudioMessage("misn1409.wav")
    end
    if M.beacon2 ~= nil and M.rescue2 and M.rescue_finish2 < GetTime() then
        --[[
            We're done here
        ]]
        if IsAlive(M.guy1) then RemoveObject(M.guy1) end
        if IsAlive(M.guy2) then RemoveObject(M.guy2) end
        if IsAlive(M.guy3) then RemoveObject(M.guy3) end
        if IsAlive(M.beacon2) then RemoveObject(M.beacon2) end
        AudioMessage("misn1418.wav")
        M.rescue_finish2 = NEVER
        M.beacon_time3 = GetTime() + 10.0
    end
    if GetTime() > M.beacon_time3 then
        M.beacon_time3 = NEVER
        M.beacon3 = BuildObject("apcamr", 1, "rescue3")
        M.guy1 = BuildObject("aspilo", 1, "help7")
        M.guy2 = BuildObject("aspilo", 1, "help8")
        M.guy3 = BuildObject("aspilo", 1, "help9")
        Defend(M.guy1)
        Defend(M.guy2)
        Defend(M.guy3)
        SetObjectiveName(M.beacon3, "Rescue 3")
        SetObjectiveOn(M.beacon3)
    end
    if not M.lost and M.beacon3 ~= nil and not M.rescue3
        and (not IsAlive(M.guy1) or not IsAlive(M.guy2) or not IsAlive(M.guy3)) then
        M.lost = true
        AudioMessage("misn1421.wav")
        FailMission(GetTime() + 15.0, "misn14l2.des")
    end
    if M.beacon3 ~= nil and M.apc ~= nil and not M.rescue3
        and Distance(M.apc, M.beacon3) < 100.0 then
        M.rescue3 = true
        Goto(M.guy1, M.beacon3)
        Goto(M.guy2, M.beacon3)
        Goto(M.guy3, M.beacon3)
        M.rescue_finish3 = GetTime() + 25.0
        AudioMessage("misn1409.wav")
    end
    if M.beacon3 ~= nil and M.rescue3 and M.rescue_finish3 < GetTime() then
        --[[
            We're done here
        ]]
        if IsAlive(M.guy1) then RemoveObject(M.guy1) end
        if IsAlive(M.guy2) then RemoveObject(M.guy2) end
        if IsAlive(M.guy3) then RemoveObject(M.guy3) end
        if IsAlive(M.beacon3) then RemoveObject(M.beacon3) end
        AudioMessage("misn1419.wav")
        M.rescue_finish3 = NEVER
    end
    --[[
        We need to keep the base
        alive so the game can finish.
    ]]
    if IsAlive(M.base) then
        if GetTime() > M.next_second then
            AddHealth(M.base, 5000.0)
            M.next_second = GetTime() + 1.0
        end
    end
    --[[
        The aliens are on
        the way and ready to
        give us grief.
    ]]
    if GetTime() > M.alien_time then
        M.alien_attack = true
        M.wave_count = M.wave_count + 1
        -- rand()%3 chooses one of three native branches. Lua 5.1 math.random
        -- provides the same alternatives; no BZ2-only random API is assumed.
        local x = math.random(0, 2)
        if x == 0 then
            BuildObject("hvsav", 3, "alien1")
            BuildObject("hvsav", 3, "alien2")
            BuildObject("hvsav", 3, "alien5")
        elseif x == 1 then
            BuildObject("hvsav", 3, "alien3")
            BuildObject("hvsav", 3, "alien4")
            BuildObject("hvsav", 3, "alien1")
        else
            BuildObject("hvsav", 3, "alien5")
            BuildObject("hvsav", 3, "alien6")
            BuildObject("hvsav", 3, "alien3")
        end
        M.alien_time = GetTime() + 180.0 -- was 70.0, now we explore
    end
    if M.alien_attack and not M.alien_warning then
        AudioMessage("misn1403.wav")
        M.alien_warning = true
    end
    if M.wave_count > 2 and not M.cca_surrender then
        AudioMessage("misn1404.wav")
        AudioMessage("misn1405.wav") -- it's a trick!
        M.cca_surrender = true
        --[[
            Here is where we should
            switch sides or destroy people.
        ]]
        for h in AllCraft() do
            if GetTeamNum(h) == 2 then
                SetTeamNum(h, 0) -- crazy!!  team 0 now
                if IsOdfBase(h, "svtank") or IsOdfBase(h, "svturr")
                    or IsOdfBase(h, "svfigh") then
                    Retreat(h, "escape", 1) --run away
                end
            end
        end
        --[[
            Convert the russian base
        ]]
        if IsAlive(M.base) then SetTeamNum(M.base, 1) end
        if IsAlive(M.tow1) then SetTeamNum(M.tow1, 1) end
        if IsAlive(M.tow2) then SetTeamNum(M.tow2, 1) end
        if IsAlive(M.tow3) then SetTeamNum(M.tow3, 1) end
        if IsAlive(M.tow4) then SetTeamNum(M.tow4, 1) end
    end
    if M.wave_count > 3 and not M.gen_message and M.rescue3 then
        SetScrap(2, 0)
        M.audmsg = AudioMessage("misn1406.wav")
        M.gen_message = true
        local foe = GetNearestEnemy(M.player)
        if Distance(M.player, foe) > 150.0 then
            M.camera3 = true
            M.camera_time = GetTime() + 20.0
            CameraReady()
        else
            M.camera3 = false
        end
    end
    if M.camera3 then
        -- BUGFIX: a missing base must not become a nil camera target. Finish the
        -- existing shot; the source's subsequent missing-base failure still applies.
        if IsAlive(M.base) then
            CameraPath("camera_path", 2500, 300, M.base)
        end
    end
    if M.camera3 and (GetTime() > M.camera_time or CameraCancelled()
        or not IsAlive(M.base)) then
        if M.audmsg ~= nil then StopAudioMessage(M.audmsg) end
        M.camera3 = false
        CameraFinish()
    end
    --[[
        Now we need you
        to rescue CCA personel
    ]]
    if M.wave_count > 4 and not M.rescue_message and M.rescue3 then
        SetScrap(2, 0)
        AudioMessage("misn1407.wav")
        M.rescue_message = true
        if IsAlive(M.base) then
            SetObjectiveOn(M.base)
            SetObjectiveName(M.base, "Rescue CCA")
        else
            -- just in case its not there
            -- BUGFIX: source FailMission(5.0,"misn14l.des") uses absolute
            -- simulation time, already past after five waves. Keep its intended
            -- five-second delay and mark lost so success cannot override failure.
            FailMission(GetTime() + 5.0, "misn14l.des")
            M.lost = true
        end
    end
    if M.wave_count > 4 and M.found and not M.rescue_start and M.rescue3 then
        --[[
            Now that you've built
            an APC, get it to the
            base to rescue the soviet scientists
            AudioMessage
        ]]
        AudioMessage("misn1408.wav")
        M.rescue_start = true
    end
    if not M.pick_up and M.rescue_start and Distance(M.apc, M.base) < 200.0 then
        --[[
            AudioMessage ..
            We're picking up the
            key personel..
        ]]
        M.pick_up = true
        M.pick_up_time = GetTime() + 15.0
        AudioMessage("misn1409.wav")
    end
    if M.pick_up and GetTime() > M.pick_up_time then
        --[[
            Audio Message
            Ready to go.
        ]]
        M.pick_up_time = NEVER
        AudioMessage("misn1410.wav")
    end
    if not M.lost and M.pick_up and not IsAlive(M.apc) then
        --[[
            Lost the APC with the
            Russian scientists-- you
            lose.
        ]]
        AudioMessage("misn1412.wav")
        AudioMessage("misn1413.wav")
        FailMission(GetTime() + 10.0, "misn14l3.des")
        M.lost = true
    end
    -- BUGFIX: require a live carrier/recycler and no pending failure. The native
    -- victory block could override APC/survivor failure (or win on a dead recycler)
    -- in the same frame. Normal successful returns keep the 300 m / 10 s trigger.
    -- Source permits returning during the 15 s pickup VO delay; retain that flow.
    if not M.won and not M.lost and M.pick_up and Distance(M.recy, M.apc) < 300.0 then
        --[[
            You won..
        ]]
        M.won = true
        SucceedMission(GetTime() + 10.0, "misn14w1.des")
        AudioMessage("misn1411.wav")
    end
    if not M.lost and not IsAlive(M.recy) then
        AudioMessage("misn1414.wav")
        FailMission(GetTime() + 10.0, "misn14l1.des")
        M.lost = true
    end
end

function Save()
    -- BZR serializes the state table and supported game values. Native b/f/h/i
    -- arrays and object-handle conversion are engine-managed in LuaMission.
    return M
end

function Load(state)
    M = state
end
