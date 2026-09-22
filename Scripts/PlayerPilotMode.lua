---@diagnostic disable: lowercase-global, undefined-global
local aiCore = require("aiCore")
local PersistentConfig = require("PersistentConfig")

local PlayerPilotMode = {
    Debug = false,
}

local state = {
    initialized = false,
    enabled = false,
    lastAppliedEnabled = nil,
    mission = nil,
    profile = nil,
    teamNum = 1,
    lastPlayerHandle = nil,
    lastTeamRef = nil,
    baselineConfig = nil,
    transitionSerial = 0,
    cargoJobs = {},
    protectedHandles = {},
    rescanAt = 0.0,
    tugBuildAttempts = {},
    objectiveContext = nil,
    objectiveActionAt = {},
    modeCommandState = {},
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

local function Now()
    return (type(GetTime) == "function" and GetTime()) or 0.0
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

local function CaptureBaselineConfig(team)
    if state.baselineConfig or not team or not team.Config then
        return
    end
    state.baselineConfig = DeepCopyValue(team.Config)
end

local function RestoreBaselineConfig(team)
    if not team or not team.Config or not state.baselineConfig then
        return
    end

    -- Keep the existing Config table so managers that retain the reference see
    -- the same object after a rapid mode transition.
    for key, _ in pairs(team.Config) do
        if state.baselineConfig[key] == nil then
            team.Config[key] = nil
        end
    end
    for key, value in pairs(state.baselineConfig) do
        team.Config[key] = DeepCopyValue(value)
    end
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
    for h, issued in pairs(state.modeCommandState) do
        if IsLiveHandle(h) and not IsProtectedHandle(h) and issued then
            local currentCommand = GetCurrentCommand(h)
            local currentTarget = GetCurrentWho and GetCurrentWho(h) or nil
            if currentCommand == issued.command and (issued.target == nil or currentTarget == issued.target) then
                SetCommand(h, AiCommand.NONE, 0)
                Stop(h, 0)
            end
        end
    end
    state.modeCommandState = {}
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
        RestoreBaselineConfig(team)
    end
end

local function RecalculateCoreValues(enabled)
    local team = GetPlayerTeam()
    if not team then
        return false
    end

    CaptureBaselineConfig(team)

    ApplyTeamConfig(team, enabled)

    for h in AllObjects() do
        if GetTeamNum(h) == state.teamNum and not IsProtectedHandle(h) then
            aiCore.AddObject(h)
        end
    end

    if aiCore.RefreshObjectCache then
        aiCore.RefreshObjectCache(true)
    end
    if aiCore.ReapplyNativeTactics then
        aiCore.ReapplyNativeTactics()
    end

    state.lastTeamRef = team
    state.lastPlayerHandle = GetPlayerHandle()
    state.rescanAt = Now() + 5.0
    state.lastAppliedEnabled = enabled and true or false
    return true
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

local RememberModeCommand

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
            local now = Now()
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
                local issued = aiCore.TrySetCommand(tug, AiCommand.GO, 0, job.dropoff, nil, nil, nil,
                    { minInterval = job.reissueInterval or 0.75 })
                if issued then RememberModeCommand(tug, AiCommand.GO, job.dropoff) end
            else
                Goto(tug, job.dropoff, 0)
                RememberModeCommand(tug, AiCommand.GO, job.dropoff)
            end
        end
        return
    end

    if aiCore and aiCore.TryPickup then
        local issued = aiCore.TryPickup(tug, job.target, 0, { minInterval = job.reissueInterval or 0.75 })
        if issued then RememberModeCommand(tug, AiCommand.PICKUP or GetCurrentCommand(tug), job.target) end
    else
        Pickup(tug, job.target, 0)
        RememberModeCommand(tug, AiCommand.PICKUP or GetCurrentCommand(tug), job.target)
    end
end

RememberModeCommand = function(h, command, target)
    if h then
        state.modeCommandState[h] = { command = command, target = target }
    end
end

local function IsObjectiveUnit(h)
    if not IsLiveHandle(h) or GetTeamNum(h) ~= state.teamNum or not IsCraft(h) then
        return false
    end
    if IsProtectedHandle(h) or h == GetPlayerHandle() then
        return false
    end

    local cls = string.lower(tostring(GetClassLabel(h) or ""))
    return not string.find(cls, "recycler", 1, true)
        and not string.find(cls, "factory", 1, true)
        and not string.find(cls, "armory", 1, true)
        and not string.find(cls, "constructor", 1, true)
        and not string.find(cls, "scavenger", 1, true)
        and not string.find(cls, "tug", 1, true)
end

local function GetObjectiveUnits(action)
    if action and action.units then
        local result = {}
        for _, h in ipairs(action.units) do
            if IsObjectiveUnit(h) then
                result[#result + 1] = h
            end
        end
        return result
    end

    local result = {}
    for h in AllObjects() do
        if IsObjectiveUnit(h) then
            result[#result + 1] = h
        end
    end
    return result
end

local function IssueObjectiveAction(action, h)
    if not action or not IsObjectiveUnit(h) then
        return
    end

    local target = action.target
    if target and not IsLiveHandle(target) then
        return
    end

    local commandName = string.lower(tostring(action.command or ""))
    local command = AiCommand and AiCommand[string.upper(commandName)] or nil
    if not command then
        return
    end

    local now = Now()
    local throttleKey = tostring(action.id or commandName) .. ":" .. tostring(h)
    if now < (state.objectiveActionAt[throttleKey] or 0.0) then
        return
    end

    local currentCommand = GetCurrentCommand(h)
    local currentTarget = GetCurrentWho and GetCurrentWho(h) or nil
    if not action.force and IsBusy(h)
        and not (currentCommand == command and currentTarget == target) then
        return
    end
    if currentCommand == command and currentTarget == target then
        return
    end

    local priority = action.priority or GetCommandableAttackPriority()
    local interval = action.reissueInterval or 1.25
    local ok = false
    if command == AiCommand.ATTACK and aiCore.TryAttack then
        ok = aiCore.TryAttack(h, target, priority, { minInterval = interval })
    elseif aiCore.TrySetCommand then
        ok = aiCore.TrySetCommand(h, command, priority, target, action.position, nil, nil,
            { minInterval = interval })
    elseif SetCommand then
        SetCommand(h, command, priority, target, action.position, nil, nil)
        ok = true
    end

    if ok ~= false then
        state.objectiveActionAt[throttleKey] = now + interval
        RememberModeCommand(h, command, target)
    end
end

local function UpdateObjectiveContext()
    local mission = state.mission
    if not mission or type(mission.getObjectiveContext) ~= "function" then
        state.objectiveContext = nil
        return
    end

    local ok, context = pcall(mission.getObjectiveContext, PlayerPilotMode)
    if not ok or type(context) ~= "table" then
        state.objectiveContext = nil
        return
    end
    state.objectiveContext = context

    for _, action in ipairs(context.actions or {}) do
        for _, h in ipairs(GetObjectiveUnits(action)) do
            IssueObjectiveAction(action, h)
        end
    end
end

local function ReconcileTeamState()
    local desired = GetDesiredEnabled()
    local playerHandle = GetPlayerHandle()
    local team = GetPlayerTeam()

    if team ~= state.lastTeamRef or playerHandle ~= state.lastPlayerHandle
        or state.lastAppliedEnabled ~= desired then
        RecalculateCoreValues(desired)
        state.enabled = desired
        return
    end

    if desired then
        ApplyTeamConfig(team, true)
    else
        RestoreBaselineConfig(team)
    end

    if Now() >= (state.rescanAt or 0.0) then
        state.rescanAt = Now() + 5.0
        for h in AllObjects() do
            if GetTeamNum(h) == state.teamNum and not IsProtectedHandle(h) then
                aiCore.AddObject(h)
            end
        end
    end
end

function PlayerPilotMode.Initialize(adapter, persistedState)
    state.initialized = true
    state.enabled = false
    state.lastAppliedEnabled = nil
    state.lastPlayerHandle = nil
    state.lastTeamRef = nil
    state.baselineConfig = persistedState and DeepCopyValue(persistedState.baselineConfig) or nil
    state.transitionSerial = persistedState and (persistedState.transitionSerial or 0) or 0
    state.cargoJobs = {}
    state.protectedHandles = {}
    state.tugBuildAttempts = {}
    state.objectiveContext = nil
    state.objectiveActionAt = {}
    state.modeCommandState = {}
    state.mission = adapter or nil
    state.profile = adapter and adapter.profile or nil

    PlayerPilotMode.Load(persistedState)

    -- PersistentConfig is an external settings file, while the native Lua
    -- save stream is the authority for a loaded mission. Restore the saved
    -- mode selection in memory after the mission has re-initialized its UI
    -- settings; do not write it back to the user's global config file.
end

function PlayerPilotMode.SetMissionAdapter(adapter)
    state.mission = adapter or nil
    state.profile = adapter and adapter.profile or nil
end

function PlayerPilotMode.Save()
    local tugBuildCooldowns = {}
    local now = Now()
    for key, expiry in pairs(state.tugBuildAttempts or {}) do
        tugBuildCooldowns[key] = math.max(0.0, (expiry or 0.0) - now)
    end
    return {
        version = 2,
        enabled = state.enabled and true or false,
        baselineConfig = DeepCopyValue(state.baselineConfig),
        transitionSerial = state.transitionSerial or 0,
        tugBuildCooldowns = tugBuildCooldowns,
    }
end

function PlayerPilotMode.Load(persistedState)
    if type(persistedState) ~= "table" then
        return
    end
    state.baselineConfig = DeepCopyValue(persistedState.baselineConfig)
    state.transitionSerial = persistedState.transitionSerial or 0
    state.tugBuildAttempts = {}
    local now = Now()
    for key, remaining in pairs(persistedState.tugBuildCooldowns or {}) do
        state.tugBuildAttempts[key] = now + math.max(0.0, remaining or 0.0)
    end
    if persistedState.enabled ~= nil and PersistentConfig and PersistentConfig.Settings then
        PersistentConfig.Settings.PilotModeEnabled = not not persistedState.enabled
    end
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
    if not RecalculateCoreValues(true) then
        return false
    end
    state.enabled = true
    state.transitionSerial = (state.transitionSerial or 0) + 1
    Log("enabled")
    return true
end

function PlayerPilotMode.Disable()
    if state.enabled then
        ClearManagedCommands()
    end

    if not RecalculateCoreValues(false) then
        return false
    end
    state.enabled = false
    state.transitionSerial = (state.transitionSerial or 0) + 1
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

    UpdateObjectiveContext()

    for _, job in pairs(state.cargoJobs) do
        UpdateCargoJob(job)
    end
end

return PlayerPilotMode
