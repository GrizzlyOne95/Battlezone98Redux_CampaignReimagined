---@diagnostic disable: lowercase-global, undefined-global
local aiCore = require("aiCore")
local PersistentConfig = require("PersistentConfig")

local PlayerPilotMode = {
    Debug = false,
}

local state = {
    initialized = false,
    enabled = false,
    mission = nil,
    profile = nil,
    teamNum = 1,
    lastPlayerHandle = nil,
    lastTeamRef = nil,
    cargoJobs = {},
    protectedHandles = {},
    rescanAt = 0.0,
    tugBuildAttempts = {},
}

local function Log(msg)
    if not PlayerPilotMode.Debug then
        return
    end

    if Print then
        Print("PlayerPilotMode: " .. msg)
    else
        print("PlayerPilotMode: " .. msg)
    end
end

local function DeepCopyValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = DeepCopyValue(v)
    end
    return copy
end

local function MergeTables(base, override)
    local result = DeepCopyValue(base or {})
    for k, v in pairs(override or {}) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = MergeTables(result[k], v)
        else
            result[k] = DeepCopyValue(v)
        end
    end
    return result
end

local function IsLiveHandle(h)
    return h and IsValid(h) and IsAlive(h)
end

local function GetDesiredEnabled()
    return not not (PersistentConfig and PersistentConfig.Settings and PersistentConfig.Settings.PilotModeEnabled)
end

local function GetPlayerTeam()
    return aiCore and aiCore.ActiveTeams and aiCore.ActiveTeams[state.teamNum] or nil
end

local function GetPersistentSetting(key, fallback)
    if PersistentConfig and PersistentConfig.Settings and PersistentConfig.Settings[key] ~= nil then
        return PersistentConfig.Settings[key]
    end
    return fallback
end

local function GetProfile()
    local defaults = {
        autoManage = true,
        autoRepairWingmen = true,
        autoRescue = true,
        autoTugs = false,
        stickToPlayer = true,
        scavengerAssist = true,
        manageFactories = true,
        autoBuild = true,
        dynamicMinefields = false,
        passiveRegen = false,
    }

    return MergeTables(defaults, state.profile or {})
end

local function IsProtectedHandle(h)
    if not h or not IsValid(h) then
        return true
    end

    if h == GetPlayerHandle() then
        return true
    end

    if state.protectedHandles[h] then
        return true
    end

    local mission = state.mission
    if mission and mission.shouldManageHandle then
        local ok, result = pcall(mission.shouldManageHandle, h)
        if ok and result == false then
            return true
        end
    end

    return false
end

local function ClearManagedCommands()
    for h in AllObjects() do
        if GetTeamNum(h) == state.teamNum and not IsProtectedHandle(h) and (IsCraft(h) or IsPerson(h)) and IsAlive(h) then
            SetCommand(h, AiCommand.NONE, 0)
            Stop(h, 0)
        end
    end
end

local function ApplyTeamConfig(team, enabled)
    if not team or not team.Config then
        return
    end

    local profile = GetProfile()
    team:SetConfig("autoRepairWingmen", GetPersistentSetting("AutoRepairWingmen", team.Config.autoRepairWingmen))
    team:SetConfig("scavengerAssist", GetPersistentSetting("ScavengerAssistEnabled", team.Config.scavengerAssist))

    if enabled then
        for key, value in pairs(profile) do
            if team.Config[key] ~= nil then
                team:SetConfig(key, value)
            end
        end
    else
        team:SetConfig("autoManage", false)
        team:SetConfig("autoRescue", false)
        team:SetConfig("autoTugs", false)
        team:SetConfig("stickToPlayer", false)
        team:SetConfig("manageFactories", false)
        team:SetConfig("autoBuild", false)
        team:SetConfig("dynamicMinefields", false)
        team:SetConfig("passiveRegen", false)
    end
end

local function RebuildPlayerTeam(enabled)
    local previous = GetPlayerTeam()
    local faction = previous and previous.faction or state.teamNum
    local configTemplate = previous and previous.Config or nil
    local team = aiCore.ResetTeam(state.teamNum, faction, configTemplate)

    ApplyTeamConfig(team, enabled)

    for h in AllObjects() do
        if GetTeamNum(h) == state.teamNum and not IsProtectedHandle(h) then
            aiCore.AddObject(h)
        end
    end

    if aiCore.RefreshObjectCache then
        aiCore.RefreshObjectCache(true)
    end

    state.lastTeamRef = team
    state.lastPlayerHandle = GetPlayerHandle()
    state.rescanAt = GetTime() + 5.0
    return team
end

local function FindAvailableTug(preferredHandle)
    if IsLiveHandle(preferredHandle) and GetTeamNum(preferredHandle) == state.teamNum and not IsProtectedHandle(preferredHandle) then
        return preferredHandle
    end

    local team = GetPlayerTeam()
    if not team or not team.tugHandles then
        return nil
    end

    aiCore.RemoveDead(team.tugHandles)

    local player = GetPlayerHandle()
    local bestHandle = nil
    local bestDist = math.huge

    for _, tug in ipairs(team.tugHandles) do
        if IsLiveHandle(tug) and not IsProtectedHandle(tug) then
            local dist = IsValid(player) and GetDistance(tug, player) or 0.0
            if dist < bestDist then
                bestDist = dist
                bestHandle = tug
            end
        end
    end

    return bestHandle
end

local function UpdateCargoJob(job)
    if not state.enabled or not job or not job.enabled then
        return
    end

    if not IsLiveHandle(job.target) or not IsLiveHandle(job.dropoff) then
        return
    end

    local tug = FindAvailableTug(job.preferredCarrier)
    if not IsLiveHandle(tug) then
        if job.autoProduceTug then
            local buildKey = job.name or tostring(job.target)
            local now = GetTime()
            local retryDelay = job.tugBuildRetryDelay or 10.0
            local nextAttempt = state.tugBuildAttempts[buildKey] or 0.0

            if now >= nextAttempt then
                local team = GetPlayerTeam()
                local recycler = team and team.recyclerMgr and team.recyclerMgr.handle or GetRecyclerHandle(state.teamNum)
                local tugOdf = nil

                if team and team.faction and aiCore.Units and aiCore.Units[team.faction] then
                    tugOdf = aiCore.Units[team.faction].tug
                end

                state.tugBuildAttempts[buildKey] = now + retryDelay

                if tugOdf and IsLiveHandle(recycler) and IsDeployed(recycler) and not IsBusy(recycler) then
                    local ok, result = pcall(Build, recycler, tugOdf, 0)
                    if ok and result then
                        state.tugBuildAttempts[buildKey] = now + (job.tugBuildSuccessDelay or 20.0)
                    end
                end
            end
        end
        return
    end

    if HasCargo(tug) then
        if GetDistance(tug, job.dropoff) > (job.dropoffRadius or 70.0) then
            if aiCore and aiCore.TrySetCommand then
                aiCore.TrySetCommand(tug, AiCommand.GO, 0, job.dropoff, nil, nil, nil,
                    { minInterval = job.reissueInterval or 0.75 })
            else
                Goto(tug, job.dropoff, 0)
            end
        end
        return
    end

    if aiCore and aiCore.TryPickup then
        aiCore.TryPickup(tug, job.target, 0, { minInterval = job.reissueInterval or 0.75 })
    else
        Pickup(tug, job.target, 0)
    end
end

local function ReconcileTeamState()
    local desired = GetDesiredEnabled()
    local playerHandle = GetPlayerHandle()
    local team = GetPlayerTeam()

    if team ~= state.lastTeamRef or playerHandle ~= state.lastPlayerHandle then
        RebuildPlayerTeam(desired)
        state.enabled = desired
        return
    end

    ApplyTeamConfig(team, desired)

    if GetTime() >= (state.rescanAt or 0.0) then
        state.rescanAt = GetTime() + 5.0
        for h in AllObjects() do
            if GetTeamNum(h) == state.teamNum and not IsProtectedHandle(h) then
                aiCore.AddObject(h)
            end
        end
    end
end

function PlayerPilotMode.Initialize(adapter)
    state.initialized = true
    state.enabled = false
    state.lastPlayerHandle = nil
    state.lastTeamRef = nil
    state.cargoJobs = {}
    state.protectedHandles = {}
    state.tugBuildAttempts = {}
    state.mission = adapter or nil
    state.profile = adapter and adapter.profile or nil
end

function PlayerPilotMode.SetMissionAdapter(adapter)
    state.mission = adapter or nil
    state.profile = adapter and adapter.profile or nil
end

function PlayerPilotMode.SetProtectedHandle(h, protected)
    if not h then
        return
    end

    if protected == false then
        state.protectedHandles[h] = nil
    else
        state.protectedHandles[h] = true
    end
end

function PlayerPilotMode.SetCargoJob(name, job)
    if not name or name == "" then
        return
    end

    if not job or job.enabled == false then
        state.cargoJobs[name] = nil
        return
    end

    job.name = name
    state.cargoJobs[name] = job
end

function PlayerPilotMode.ClearCargoJob(name)
    state.cargoJobs[name] = nil
end

function PlayerPilotMode.Enable()
    if state.enabled then
        return true
    end

    RebuildPlayerTeam(true)
    state.enabled = true
    Log("enabled")
    return true
end

function PlayerPilotMode.Disable()
    if state.enabled then
        ClearManagedCommands()
    end

    RebuildPlayerTeam(false)
    state.enabled = false
    Log("disabled")
    return true
end

function PlayerPilotMode.SetEnabled(value)
    if value then
        return PlayerPilotMode.Enable()
    end
    return PlayerPilotMode.Disable()
end

function PlayerPilotMode.IsEnabled()
    return state.enabled
end

function PlayerPilotMode.AddObject(h)
    if not h or not IsValid(h) then
        return false
    end

    if GetTeamNum(h) ~= state.teamNum or IsProtectedHandle(h) then
        return false
    end

    aiCore.AddObject(h)
    return true
end

function PlayerPilotMode.DeleteObject(h)
    if not h then
        return
    end

    state.protectedHandles[h] = nil
end

function PlayerPilotMode.Update()
    if not state.initialized then
        PlayerPilotMode.Initialize()
    end

    local desired = GetDesiredEnabled()
    if desired ~= state.enabled then
        PlayerPilotMode.SetEnabled(desired)
    else
        ReconcileTeamState()
    end

    if not state.enabled then
        return
    end

    local mission = state.mission
    if mission and mission.update then
        pcall(mission.update, PlayerPilotMode)
    end

    for _, job in pairs(state.cargoJobs) do
        UpdateCargoJob(job)
    end
end

return PlayerPilotMode
