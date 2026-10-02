-- BlackDog06Mission, stock Battlezone 98 Redux 2.1+ / Lua 5.1.
-- Source: Battlezone_Source/BZ1/from_bz2_dll_src/blackdog06mission.cpp
-- Git blob: 4103fbfa8032b89fc3592c46f2366e4f0f115839.
-- Exact source including ALL comments/cut code and native save scaffolding:
-- References/BlackDog06Source/blackdog06mission.cpp. No helper dependencies.

local MS_STARTUP, MS_STARTCAMERA, MS_WAITING1 = 0, 1, 2
local MS_WAITFORSOUND2, MS_WAITING2, MS_FAKEATTACKCAMERA = 3, 4, 5
local MS_WAITFORALL2BDESTDEAD, MS_WAITFORREDDEVIL = 6, 7
local MS_WAITFORBADGUY, MS_WAITFORBADGUY1DIE = 8, 9
local MS_WAITFORBADGUY2, MS_WAITFORBADGUY2DIE = 10, 11
local MS_WAITFORSOUND3, MS_WAITFOROBJECTIVE2, MS_WAITFORRECYCLER = 12, 13, 14
local MS_WAITFORBADGUY3, MS_WAITFORAPC, MS_ENDCUTSCENE = 15, 16, 17
local MS_WAITING3, MS_WAITAPCFINISHED, MS_WAITAPCOUT = 18, 19, 20
-- Cut states remain named for reconstruction; their handlers stay disabled.
local MS_WAITFORSOUND8, MS_WAITING4, MS_RECYCLERDEAD, MS_ATTACKTOEARLY = 21, 22, 23, 24

local function NewState()
    return {
        lost = false, portalours = false, recyclerDropped = false,
        randomAttack = true, -- unused in the active native mission
        stateTimer = 99999, stateTimer2 = 99999,
        stateTimer3 = 0, stateTimer4 = 0, missionState = MS_STARTUP,
        -- Native null handles/messages are nil, not Lua's truthy numeric zero.
        -- Keep zero-based arrays so source indices can be compared directly.
        bdtank = {}, silo_attack = {}, h2bdest = {}, portalattack = {},
        randomattack = {}, badguy = {},
        portalWaveActive = false, portalWaveSpawned = false, apcEntered = false,
        apcEntryAudioPending = false,
    }
end
local M = NewState()

local function Valid(h) return h ~= nil and h ~= 0 and IsValid(h) end
local function Alive(h) return Valid(h) and IsAlive(h) end
local function AudioDone(h)
    -- PORT FIX: a failed/missing audio file must not block its completion gate.
    -- Existing messages still finish at the original gate; no timer is added.
    return h == nil or h == 0 or IsAudioMessageDone(h)
end
local function Order(command, h, target)
    -- PORT FIX: deleted objects/failed spawns cannot receive handle commands.
    -- Every successful spawn retains the source's default priority (1).
    if Valid(h) then
        if target == nil then
            if command == Hunt then command(h) end
        elseif type(target) == "string" or Valid(target) then
            command(h, target)
        end
    end
end
local function Spawn(odf, team, path, command, target)
    local h = BuildObject(odf, team, path)
    Order(command, h, target)
    return h
end
local function resetObjectives()
    ClearObjectives()
    if M.missionState >= MS_WAITFORSOUND3 then
        AddObjective("bd06001.otf", "green")
    elseif M.missionState >= MS_WAITING1 then
        AddObjective("bd06001.otf", "white")
    end
    if M.portalours then
        AddObjective("bd06002.otf", "green")
    elseif M.missionState >= MS_WAITFORRECYCLER then
        AddObjective("bd06002.otf", "white")
    end
end

function Start()
    M = NewState()
    -- Cut setup: portalAttackStage = 0; portalAttackNum = 0;
    M.portal = GetHandle("portal")
    for i = 0, 9 do
        M.silo_attack[i] = GetHandle("silo_attack" .. (i + 1))
        M.bdtank[i] = GetHandle("bdtank_" .. (i + 1))
    end
    local labels = {"2bdest_1", "2bdest_2", "2bdest_3", "2bdest_7", "2bdest_9", "2bdest_10"}
    for i = 0, 5 do M.h2bdest[i] = GetHandle(labels[i + 1]) end
end
function AddObject(h)
    -- Native AddObject(Handle) is empty; no extra construction trigger.
end
function Save() return M end
function Load(state)
    -- LuaMission serializes/remaps state and object handles. Do not rerun Setup.
    if state ~= nil then M = state end
end

local function FakeAttackCamera()
    -- PORT FIX: if the subject was destroyed, finish the existing shot instead
    -- of calling CameraPath with a deleted handle. Intact-map timing is kept.
    local arrived = not Valid(M.silo_attack[3])
    if not arrived then arrived = CameraPath("camera_go", 2000, 2000, M.silo_attack[3]) end
    if arrived or CameraCancelled() or M.stateTimer < GetTime() then
        for i = 0, 9 do
            if Valid(M.silo_attack[i]) then RemoveObject(M.silo_attack[i]) end
        end
        CameraFinish()
        M.missionState = MS_WAITFORALL2BDESTDEAD
    end
end

local function PortalWaves()
    if M.stateTimer4 ~= 0 and M.stateTimer4 < GetTime() then
        local diff = GetTime() - M.stateTimer4
        -- ADAPTATION: native portalOut(h, strength) has no stock Lua strength
        -- overload. Set outward direction and activate for the same two-second
        -- window. Unit appearance is still delayed until diff >= 1 second.
        if not M.portalWaveActive then
            PortalOut(M.portal)
            ActivatePortal(M.portal)
            M.portalWaveActive = true
        end
        if diff >= 1 then
            for i = 0, 1 do
                if M.portalattack[i] == nil then
                    local r, odf = math.random(), "cvrckt"
                    if r < 0.33 then odf = "cvfigh"
                    elseif r < 0.66 then odf = "cvtnk" end
                    M.portalattack[i] = BuildObjectAtPortal(odf, 2, M.portal)
                    Order(Goto, M.portalattack[i], "camera_go")
                end
            end
        end
        -- PORT FIX: native resets stateTimer4 inside the two-unit loop, so
        -- iteration 1 can compute a negative diff and an out-of-range strength.
        -- Reset once AFTER both slots have been processed. Keep the two units,
        -- >=2-second close, and original next-wave delay of 80 seconds.
        -- Native gives a late first spawn one Update before resetting; keep it.
        if diff >= 2 and M.portalWaveSpawned then
            DeactivatePortal(M.portal)
            M.portalWaveActive, M.portalWaveSpawned = false, false
            M.stateTimer4 = GetTime() + 80
            M.portalattack[0], M.portalattack[1] = nil, nil
        elseif diff >= 1 then
            M.portalWaveSpawned = true
        end
    end
end

local function APCEntry()
    -- PORT FIX: the native entry/removal/audio block lived only in the camera
    -- state. Early camera arrival could skip it forever and reuse the old
    -- 11-minute timer for the return APC. Continue that SAME entry sequence
    -- after the camera exits; normal cinematics keep all original timings.
    if not M.apcEntered and Valid(M.apchandle)
        and GetCurrentCommand(M.apchandle) == AiCommand.NONE then
        RemoveObject(M.apchandle)
        M.apchandle = nil
        M.apcEntered = true
        M.soundhandle = AudioMessage("bd06009.wav")
        M.apcEntryAudioPending = true
        M.stateTimer2 = GetTime() + 60
    end
    if M.apcEntryAudioPending and AudioDone(M.soundhandle) then
        M.soundhandle, M.apcEntryAudioPending = nil, false
        for i = 0, 6 do Spawn("cvtnk", 2, "dummy_1", Goto, "dummy_1_path") end
        if M.missionState == MS_ENDCUTSCENE then M.stateTimer = GetTime() + 3 end
    end
end

function Update(dt)
    M.user = GetPlayerHandle() -- assigns the player a handle every frame
    if M.lost then return end

    if not M.portalours and M.recycler ~= nil then
        -- Count ALL bvapc objects, as the native cfg comparison does. Do not
        -- impose an invented team filter. AllObjects is stock (not the broken
        -- ObjectiveObjects iterator). Player-built APCs must also be detected.
        local apclist = 0
        for apc in AllObjects() do
            if Valid(apc) and IsOdf(apc, "bvapc") then
                if GetDistance(apc, "apc_in") < 100 then
                    Order(Goto, apc, "apc_in")
                    M.apchandle, M.portalours, M.soundhandle = apc, true, nil
                    resetObjectives() -- deliberately before changing state
                    for i = 0, 2 do Spawn("cvartl", 2, "portal_attack_1", Attack, M.portal) end
                    M.missionState, M.stateTimer = MS_ENDCUTSCENE, 0
                    CameraReady()
                    break
                end
                apclist = apclist + 1
            end
        end
        if not M.portalours and apclist == 0 and not Alive(M.recycler)
            and M.missionState ~= MS_RECYCLERDEAD then
            -- PORT FIX: restarting bd06006 every frame prevents it finishing.
            -- Enter loss state once, preserving the audio-then-failure flow.
            M.missionState = MS_RECYCLERDEAD
            M.soundhandle = AudioMessage("bd06006.wav")
        end
    end

    if not Alive(M.portal) then
        FailMission(GetTime() + 2, "bd06lseb.des")
        M.lost = true
        -- PORT FIX: stop this Update as well, preventing simultaneous success
        -- or portal spawns on a destroyed portal. This retains the source loss.
        return
    end

    PortalWaves()
    if M.stateTimer3 ~= 0 and M.stateTimer3 < GetTime() then
        for i = 0, 4 do
            local odf = math.random() < 0.5 and "cvfigh" or "cvtnk"
            M.randomattack[i] = Spawn(odf, 2, "attack_always", Hunt)
        end
        M.stateTimer3 = GetTime() + 60 + 50
    end
    if M.portalours and M.missionState >= MS_ENDCUTSCENE
        and M.missionState <= MS_WAITAPCFINISHED then APCEntry() end

    if M.missionState == MS_STARTUP then
        SetScrap(1, 75)
        SetPilot(1, 10)
        resetObjectives()
        M.missionState, M.stateTimer, M.soundhandle = MS_STARTCAMERA, GetTime() + 2, nil
        CameraReady()
        -- Source's commented-out break intentionally falls through this frame.
        -- // break;
    end
    if M.missionState == MS_STARTCAMERA then
        local arrived = CameraPath("camera_start", 1000, 2500, M.portal)
        if arrived or CameraCancelled() then
            CameraFinish()
            M.missionState = MS_WAITING1
            resetObjectives()
            M.stateTimer = GetTime() + 20
            -- // resetObjectives();
            M.stateTimer2 = GetTime() + (11 * 60)
            -- // StartCockpitTimer(11 * 60);
        end
        if M.stateTimer < GetTime() and M.soundhandle == nil then
            M.soundhandle = AudioMessage("bd06001.wav")
            --[==[ Cut source:
            else if (IsAudioMessageDone(soundhandle))
            {
                missionState = MS_WAITING1;
            }
            ]==]
        end
    elseif M.missionState == MS_WAITING1 then
        if M.stateTimer < GetTime() then
            M.soundhandle = AudioMessage("bd06002.wav")
            for i = 0, 9 do Order(Goto, M.silo_attack[i], "fake_attack") end
            M.missionState = MS_WAITFORSOUND2
        else
            for i = 0, 9 do
                --[==[ Cut source (friendly damage check remains disabled):
                if(i < 5)
                {
                    o = GameObjectHandle::GetObj(bdtank[i]);
                    if(o->GetCurHealth() != o->GetMaxHealth())
                    {
                        missionState = MS_ATTACKTOEARLY;
                        soundhandle = AudioMessage("bd06007.wav");
                    }
                }
                ]==]
                -- PORT FIX: native dereferences a null object if a silo unit
                -- was killed. Treat destruction as damage, the same loss gate.
                if not Valid(M.silo_attack[i])
                    or GetCurHealth(M.silo_attack[i]) ~= GetMaxHealth(M.silo_attack[i]) then
                    M.missionState = MS_ATTACKTOEARLY
                    M.soundhandle = AudioMessage("bd06007.wav")
                    break -- one loss message, even when several are damaged
                end
            end
        end
    elseif M.missionState == MS_WAITFORSOUND2 then
        if AudioDone(M.soundhandle) then
            M.missionState, M.stateTimer = MS_WAITING2, GetTime() + 3
        end
    elseif M.missionState == MS_WAITING2 then
        if M.stateTimer < GetTime() then
            M.missionState, M.stateTimer = MS_FAKEATTACKCAMERA, GetTime() + 5
            CameraReady()
            FakeAttackCamera() -- source switch fallthrough, same Update
        end
    elseif M.missionState == MS_FAKEATTACKCAMERA then
        FakeAttackCamera()
    elseif M.missionState == MS_WAITFORALL2BDESTDEAD then
        -- out of time? Cut: if(GetCockpitTimer() < 1)
        if M.stateTimer2 < GetTime() then
            FailMission(GetTime() + 2, "bd06lsed.des")
            M.lost = true
        else
            local allDead = true
            for i = 0, 5 do if Alive(M.h2bdest[i]) then allDead = false; break end end
            if allDead then
                M.missionState = MS_WAITFORREDDEVIL
                resetObjectives()
                M.stateTimer = GetTime() + (60 * 1.5)
                M.stateTimer3, M.stateTimer4 = GetTime() + 60 + 50, GetTime() + 80
                M.portalattack[0], M.portalattack[1] = nil, nil
                M.soundhandle, M.recyclerDropped = nil, false
                -- // HideCockpitTimer();
            end
        end
    elseif M.missionState == MS_WAITFORREDDEVIL then
        if M.stateTimer < GetTime() then
            local maxgoodguysdead = 0
            -- PORT FIX: native `i < 10 || maxgoodguysdead == 5` reads beyond
            -- bdtank[9] when exactly five died. Bound the ten actual slots.
            -- Do NOT invent a five-unit cap: retain one replacement per dead
            -- tank (0..10), the same spawn point/path and 90-second timing.
            for i = 0, 9 do if not Alive(M.bdtank[i]) then maxgoodguysdead = maxgoodguysdead + 1 end end
            for i = 0, maxgoodguysdead - 1 do Spawn("bvrdeva", 1, "backup_1", Goto, "backup_path") end
            M.stateTimer, M.missionState = GetTime() + 60 + 30, MS_WAITFORBADGUY
        end
    elseif M.missionState == MS_WAITFORBADGUY then
        if M.stateTimer < GetTime() then
            for i = 0, 1 do M.badguy[i] = Spawn("cvtnk", 2, "attack_1", Attack, M.user) end
            M.missionState = MS_WAITFORBADGUY1DIE
        end
    elseif M.missionState == MS_WAITFORBADGUY1DIE then
        -- Preserve the source's FIRST-tank-only gate (not both tanks).
        if not Alive(M.badguy[0]) then
            M.stateTimer, M.missionState = GetTime() + (60 * 3), MS_WAITFORBADGUY2
        end
    elseif M.missionState == MS_WAITFORBADGUY2 then
        if M.stateTimer < GetTime() then
            for i = 0, 2 do M.badguy[i] = Spawn("cvtnk", 2, "attack_2", Attack, M.user) end
            M.missionState = MS_WAITFORBADGUY2DIE
        end
    elseif M.missionState == MS_WAITFORBADGUY2DIE then
        if not Alive(M.badguy[0]) and not Alive(M.badguy[1]) and not Alive(M.badguy[2]) then
            M.missionState = MS_WAITFORSOUND3
            resetObjectives()
            M.soundhandle = AudioMessage("bd06003.wav")
        end
    elseif M.missionState == MS_WAITFORSOUND3 then
        if AudioDone(M.soundhandle) then
            M.recycler = Spawn("bvrecy", 1, "recycler_spawn", Goto, "recycler_path")
            for i = 0, 1 do Spawn("bvrdeva", 1, "recycler_spawn", Follow, M.recycler) end
            M.stateTimer, M.missionState = GetTime() + 30, MS_WAITFOROBJECTIVE2
        end
    elseif M.missionState == MS_WAITFOROBJECTIVE2 then
        if M.stateTimer < GetTime() then
            M.missionState = MS_WAITFORRECYCLER
            resetObjectives()
        end
    elseif M.missionState == MS_WAITFORRECYCLER then
        if Valid(M.recycler) and GetCurrentCommand(M.recycler) == AiCommand.NONE then
            Deploy(M.recycler) -- stock equivalent of Recycler::Deploy()
            AudioMessage("bd06004.wav")
            M.missionState, M.stateTimer = MS_WAITFORBADGUY3, GetTime() + 60
        end
    elseif M.missionState == MS_WAITFORBADGUY3 then
        -- Preserve the native next-Update spawn: its +60 timer is NOT checked.
        for i = 0, 4 do Spawn("cvtnk", 2, "attack_3", Hunt) end
        M.missionState = MS_WAITFORAPC
    elseif M.missionState == MS_WAITFORAPC then
        -- APC proximity is checked before the state machine, as in Execute.
    elseif M.missionState == MS_ENDCUTSCENE then
        -- PORT FIX: source removes apchandle then uses that null camera target.
        -- The portal is the stationary subject once the APC has entered it;
        -- the camera path, height, speed and original finish gates are retained.
        local target = Valid(M.apchandle) and M.apchandle or M.portal
        local arrived = CameraPath("camera_end_scene", 2000, 0, target)
        if arrived or (M.stateTimer ~= 0 and (CameraCancelled() or M.stateTimer < GetTime())) then
            CameraFinish()
            M.missionState, M.stateTimer = MS_WAITING3, GetTime() + 5
        end
    elseif M.missionState == MS_WAITING3 then
        if M.stateTimer < GetTime() then
            for i = 0, 6 do Spawn("cvfigh", 2, "portal_attack_2", Attack, M.portal) end
            M.missionState = MS_WAITAPCFINISHED
        end
    elseif M.missionState == MS_WAITAPCFINISHED then
        if M.apcEntered and M.stateTimer2 < GetTime() then
            M.apchandle = Spawn("bvapc", 1, "portal", Goto, "apc_out")
            M.missionState = MS_WAITAPCOUT
        end
    elseif M.missionState == MS_WAITAPCOUT then
        -- PORT FIX: a null/destroyed exit APC must not masquerade as CMD_NONE
        -- and grant victory. No new loss condition is invented by this guard.
        if Valid(M.apchandle) and GetCurrentCommand(M.apchandle) == AiCommand.NONE then
            SucceedMission(GetTime() + 10, "bd06wina.des")
            M.lost = true
        end
        --[==[ Cut source: alternate audio-driven victory (still disabled).
                soundhandle = AudioMessage("bd06008.wav");
                missionState = MS_WAITFORSOUND8;
            }
            break;

        case MS_WAITFORSOUND8:
            if(IsAudioMessageDone(soundhandle))
            {
                missionState = MS_WAITING4;
                stateTimer = GetTime() + 5;
            }
            break;

        case MS_WAITING4:
            if(stateTimer < GetTime())
            {
                AudioMessage("bd06005.wav");
                SucceedMission(GetTime() + 10.0f, "bd06wina.des");
                lost = TRUE;
            }
            break;
        ]==]
    elseif M.missionState == MS_RECYCLERDEAD then
        if AudioDone(M.soundhandle) then
            FailMission(GetTime() + 2, "bd06lsec.des")
            M.lost = true
        end
    elseif M.missionState == MS_ATTACKTOEARLY then
        if AudioDone(M.soundhandle) then
            FailMission(GetTime() + 2, "bd06lsea.des")
            M.lost = true
        end
    end
end

-- Cut declarations: number of fighters attacking through the portal (2-5)
-- // portalAttackNum,
-- portal attack stage
-- // portalAttackStage,
