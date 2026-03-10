local MissionLifecycle = {}
MissionLifecycle.__index = MissionLifecycle

local function Call(module, fnName, ...)
    if module and module[fnName] then
        return module[fnName](...)
    end
end

function MissionLifecycle.New(cfg)
    return setmetatable({
        cfg = cfg or {},
        difficultyPollAt = 0.0,
        turboSweepAt = 0.0,
        turboSweepsRemaining = 0
    }, MissionLifecycle)
end

function MissionLifecycle:ApplyQOL()
    local cfg = self.cfg
    local exu = cfg.exu

    if cfg.requireExuForQOL ~= false and not exu then
        return
    end

    if exu then
        if cfg.shotConvergence ~= false and exu.SetShotConvergence then
            exu.SetShotConvergence(true)
        end
        if cfg.reticleRange and exu.SetReticleRange then
            exu.SetReticleRange(cfg.reticleRange)
        end
        if cfg.ordnanceVelocityInheritance and exu.SetOrdnanceVelocInheritance then
            exu.SetOrdnanceVelocInheritance(true)
        end
        if cfg.globalTurbo ~= nil and exu.SetGlobalTurbo then
            exu.SetGlobalTurbo(cfg.globalTurbo)
        end
    end

    Call(cfg.PersistentConfig, "Initialize")
    Call(cfg.Environment, "Init")

    if cfg.initPhysicsImpact then
        Call(cfg.PhysicsImpact, "Init")
    end
end

function MissionLifecycle:InitializeDifficulty(state)
    local cfg = self.cfg
    local exu = cfg.exu
    local defaultDifficulty = cfg.defaultDifficulty or 2

    if not exu then
        state.difficulty = state.difficulty or defaultDifficulty
        return state.difficulty
    end

    local ver = (type(exu.GetVersion) == "function" and exu.GetVersion()) or exu.version or "Unknown"
    print("EXU Version: " .. tostring(ver))

    state.difficulty = (exu.GetDifficulty and exu.GetDifficulty()) or defaultDifficulty
    print("Difficulty: " .. tostring(state.difficulty))

    self:ApplyDifficultyObjectives(state)

    return state.difficulty
end

function MissionLifecycle:RefreshDifficulty(state)
    local cfg = self.cfg
    local exu = cfg.exu
    local defaultDifficulty = cfg.defaultDifficulty or 2

    state.difficulty = (exu and exu.GetDifficulty and exu.GetDifficulty()) or defaultDifficulty
    return state.difficulty
end

function MissionLifecycle:ApplyDifficultyObjectives(state)
    local cfg = self.cfg

    if cfg.addDifficultyObjectives == false then
        return
    end

    if state.difficulty >= (cfg.hardDifficultyThreshold or 3) and cfg.hardDifficultyObjective then
        AddObjective(cfg.hardDifficultyObjective[1], cfg.hardDifficultyObjective[2], cfg.hardDifficultyObjective[3],
            cfg.hardDifficultyObjective[4])
    elseif state.difficulty <= (cfg.easyDifficultyThreshold or 1) and cfg.easyDifficultyObjective then
        AddObjective(cfg.easyDifficultyObjective[1], cfg.easyDifficultyObjective[2], cfg.easyDifficultyObjective[3],
            cfg.easyDifficultyObjective[4])
    end
end

function MissionLifecycle:ApplyTurbo(state, h)
    local cfg = self.cfg
    local exu = cfg.exu

    if not (exu and exu.SetUnitTurbo and IsCraft(h) and cfg.turboValue) then
        return
    end

    local value = cfg.turboValue(h, GetTeamNum(h), state)
    if value ~= nil and value ~= false then
        exu.SetUnitTurbo(h, value)
    elseif cfg.clearTurboWhenDisabled then
        exu.SetUnitTurbo(h, false)
    end
end

function MissionLifecycle:ApplyTurboToAll(state)
    if not self.cfg.turboValue then
        return
    end

    for h in AllCraft() do
        self:ApplyTurbo(state, h)
    end
end

function MissionLifecycle:QueueTurboSweeps()
    local cfg = self.cfg
    self.turboSweepAt = 0.0
    self.turboSweepsRemaining = cfg.initialTurboSweepCount or 3
end

function MissionLifecycle:InitializeSubtitles()
    local cfg = self.cfg
    if cfg.subtitleInit then
        cfg.subtitleInit()
    elseif cfg.subtit and cfg.subtit.Initialize then
        cfg.subtit.Initialize()
    end

    -- Re-apply persistent subtitle/UI settings after subtitle init resets its channel state.
    Call(cfg.PersistentConfig, "ApplySettings")
end

function MissionLifecycle:Start(state)
    local cfg = self.cfg

    state.TPS = state.TPS or cfg.defaultTPS or 20
    self.difficultyPollAt = 0.0
    self.turboSweepAt = 0.0
    self.turboSweepsRemaining = 0

    self:InitializeDifficulty(state)
    self:ApplyQOL()

    if cfg.setupAI then
        cfg.setupAI(state)
    end

    if cfg.beforeBootstrapStart then
        cfg.beforeBootstrapStart(state)
    end

    Call(cfg.aiCore, "Bootstrap")

    if cfg.refreshHandlesOnStart and cfg.refreshHandles then
        cfg.refreshHandles(state)
    end

    if cfg.applyTurboOnStart ~= false then
        self:ApplyTurboToAll(state)
        self:QueueTurboSweeps()
    end

    if cfg.initializeSubtitlesOnStart ~= false then
        self:InitializeSubtitles()
    end

    if cfg.afterStart then
        cfg.afterStart(state)
    end
end

function MissionLifecycle:Load(state, aiData)
    local cfg = self.cfg
    self.difficultyPollAt = 0.0
    self.turboSweepAt = 0.0
    self.turboSweepsRemaining = 0

    if cfg.refreshDifficultyOnLoad then
        self:RefreshDifficulty(state)
    end

    if aiData then
        Call(cfg.aiCore, "Load", aiData)
    end

    if cfg.beforeBootstrapLoad then
        cfg.beforeBootstrapLoad(state)
    end

    Call(cfg.aiCore, "Bootstrap")

    if cfg.refreshHandles then
        cfg.refreshHandles(state)
    end

    self:ApplyQOL()

    if cfg.applyTurboOnLoad ~= false then
        self:ApplyTurboToAll(state)
        self:QueueTurboSweeps()
    end

    if cfg.initializeSubtitlesOnLoad then
        self:InitializeSubtitles()
    end

    if cfg.afterLoad then
        cfg.afterLoad(state)
    end
end

function MissionLifecycle:CheckDifficultyChange(state)
    local cfg = self.cfg
    local exu = cfg.exu

    if not (cfg.monitorDifficultyChanges and exu and exu.GetDifficulty) then
        return
    end

    local now = GetTime()
    if now < (self.difficultyPollAt or 0.0) then
        return
    end

    self.difficultyPollAt = now + (cfg.difficultyPollInterval or 1.0)

    local oldDifficulty = state.difficulty
    local newDifficulty = self:RefreshDifficulty(state)
    if oldDifficulty == newDifficulty then
        return
    end

    print("Difficulty changed: " .. tostring(oldDifficulty) .. " -> " .. tostring(newDifficulty))

    if cfg.applyTurboOnDifficultyChange ~= false then
        self:ApplyTurboToAll(state)
    end

    if cfg.onDifficultyChanged then
        cfg.onDifficultyChanged(state, oldDifficulty, newDifficulty)
    end
end

function MissionLifecycle:RunPendingTurboSweeps(state)
    if (self.turboSweepsRemaining or 0) <= 0 then
        return
    end

    local now = GetTime()
    if now < (self.turboSweepAt or 0.0) then
        return
    end

    self:ApplyTurboToAll(state)
    self.turboSweepsRemaining = self.turboSweepsRemaining - 1
    self.turboSweepAt = now + (self.cfg.initialTurboSweepInterval or 1.0)
end

function MissionLifecycle:OnObjectCreated(state, h)
    if self.cfg.persistentConfigOnObjectCreated ~= false then
        Call(self.cfg.PersistentConfig, "OnObjectCreated", h)
    end

    if self.cfg.environmentOnObjectCreated ~= false then
        Call(self.cfg.Environment, "OnObjectCreated", h)
    end

    if self.cfg.physicsImpactOnObjectCreated then
        Call(self.cfg.PhysicsImpact, "OnObjectCreated", h)
    end

    self:ApplyTurbo(state, h)
end

function MissionLifecycle:Update(state, dt)
    local cfg = self.cfg
    local exu = cfg.exu

    self:RunPendingTurboSweeps(state)
    self:CheckDifficultyChange(state)

    if cfg.updateOrdnance and exu and exu.UpdateOrdnance then
        exu.UpdateOrdnance()
    end

    if cfg.updateEnvironment ~= false then
        Call(cfg.Environment, "Update", dt)
    end

    if cfg.updateSubtitles ~= false then
        Call(cfg.subtit, "Update")
    end

    if cfg.updatePersistentConfig ~= false then
        Call(cfg.PersistentConfig, "UpdateInputs")
        Call(cfg.PersistentConfig, "UpdateHeadlights")
    end

    if cfg.updatePhysicsImpact then
        Call(cfg.PhysicsImpact, "Update", dt)
    end
end

function MissionLifecycle:Save(state)
    if self.cfg.aiCore and self.cfg.aiCore.Save then
        return state, self.cfg.aiCore.Save()
    end

    return state
end

return MissionLifecycle
