-- PersistentConfigR.lua
---@diagnostic disable: lowercase-global, undefined-global

local M = {}

function M.Create(deps)
    local PersistentConfig = deps.PersistentConfig
    local InputState = deps.InputState
    local PresetProducerKinds = deps.PresetProducerKinds
    local CleanString = deps.CleanString
    local ClampIndex = deps.ClampIndex
    local ShowFeedback = deps.ShowFeedback
    local GetProducerHandleForKind = deps.GetProducerHandleForKind
    local GetProducerBuildEntries = deps.GetProducerBuildEntries
    local GetPresetSurchargeForEntry = deps.GetPresetSurchargeForEntry
    local GetUnitBuildEntry = deps.GetUnitBuildEntry
    local InitializeTrackedWorldHandles = deps.InitializeTrackedWorldHandles
    local GetPlayerTeamNum = deps.GetPlayerTeamNum
    local GetPowerRadius = deps.GetPowerRadius

    local function NormalizeGameKey(key)
        if type(key) ~= "string" then return "" end
        return string.upper(CleanString(key))
    end

    local function QueueGameKey(key)
        local normalized = NormalizeGameKey(key)
        if normalized == "" then return end
        InputState.pendingGameKeys = InputState.pendingGameKeys or {}
        table.insert(InputState.pendingGameKeys, normalized)
        if #InputState.pendingGameKeys > 32 then
            table.remove(InputState.pendingGameKeys, 1)
        end
    end

    local function ConsumePendingGameKeyMatch(variants)
        local queue = InputState.pendingGameKeys
        if not queue or #queue == 0 then
            return false
        end
        for index, key in ipairs(queue) do
            for _, variant in ipairs(variants) do
                if key == variant then
                    table.remove(queue, index)
                    return true
                end
            end
        end
        return false
    end

    local function ConsumePendingNumberKey()
        local queue = InputState.pendingGameKeys
        if not queue or #queue == 0 then
            return nil
        end
        for index, key in ipairs(queue) do
            local digit = nil
            if #key == 1 and key:match("%d") then
                digit = tonumber(key)
            else
                local match = key:match("NUMPAD(%d)") or key:match("KP(%d)") or key:match("NUM(%d)")
                if match then
                    digit = tonumber(match)
                end
            end
            if digit and digit >= 1 and digit <= 9 then
                table.remove(queue, index)
                return digit
            end
        end
        return nil
    end

    local function GetSelectedProducerHandle(team)
        if type(IsSelected) ~= "function" then return nil end
        for kindIndex, _ in ipairs(PresetProducerKinds) do
            local producer = GetProducerHandleForKind(kindIndex, team)
            if IsValid(producer) and IsSelected(producer) then
                return producer
            end
        end
        return nil
    end

    local function GetBuildEntryForProducer(producer, index)
        if not IsValid(producer) or not index then return nil end
        local entries = GetProducerBuildEntries(producer)
        return entries and entries[index] or nil
    end

    local function GetProducerQueueState(kindIndex)
        InputState.producerQueues = InputState.producerQueues or {}
        if not InputState.producerQueues[kindIndex] then
            InputState.producerQueues[kindIndex] = {
                itemIndex = 1,
                count = 0,
                remaining = 0,
                unitOdf = "",
                status = "Queue Off",
                pendingIssue = nil,
                inProgress = false,
                locked = false,
            }
        end
        return InputState.producerQueues[kindIndex]
    end

    local function GetUnitBuildTimeSeconds(unitOdfName)
        if not unitOdfName or unitOdfName == "" then return 0.0 end
        PersistentConfig.UnitBuildTimeCache = PersistentConfig.UnitBuildTimeCache or {}
        local key = string.lower(unitOdfName)
        if PersistentConfig.UnitBuildTimeCache[key] ~= nil then
            return PersistentConfig.UnitBuildTimeCache[key]
        end
        local buildTime = 0.0
        if OpenODF and GetODFFloat then
            local odf = OpenODF(unitOdfName)
            if odf then
                local val, found = GetODFFloat(odf, nil, "buildTime", 0.0)
                if found then
                    buildTime = val
                end
            end
        end
        PersistentConfig.UnitBuildTimeCache[key] = buildTime
        return buildTime
    end

    local function UpdateTeamScrapSnapshot(team)
        if type(GetScrap) ~= "function" then return nil end
        local current = GetScrap(team) or 0.0
        local last = InputState.lastTeamScrap[team]
        if last == nil then
            InputState.lastTeamScrap[team] = current
            return 0.0
        end
        InputState.lastTeamScrap[team] = current
        return last - current
    end

    local function StartPresetSurchargeForEntry(team, producer, entry)
        if not entry then return end
        local now = GetTime()
        local surcharge = math.floor(GetPresetSurchargeForEntry(entry) + 0.5)
        local applyAllowed = true
        local charged = false
        if surcharge > 0 and type(GetScrap) == "function" then
            local currentScrap = GetScrap(team)
            if currentScrap < surcharge then
                applyAllowed = false
                ShowFeedback("Not enough scrap for upgrades. Building stock loadout.", 1.0, 0.35, 0.35, 2.5, false,
                    "pda")
            elseif type(AddScrap) == "function" then
                AddScrap(team, -surcharge)
                charged = true
            end
        end

        if surcharge > 0 or not applyAllowed then
            local buildTime = GetUnitBuildTimeSeconds(entry.odf)
            local expectedFinish = now + (buildTime or 0.0)
            table.insert(InputState.pendingBuilds, {
                producer = producer,
                team = team,
                unitOdf = entry.odf,
                unitKey = string.lower(CleanString(entry.odf or "")),
                surcharge = surcharge,
                charged = charged,
                applyAllowed = applyAllowed,
                startedAt = now,
                expectedFinishAt = expectedFinish,
            })
        end
    end

    local function RecordBuildKeyIfPressed(team)
        local keyIndex = ConsumePendingNumberKey()
        if not keyIndex then return end
        local producer = GetSelectedProducerHandle(team)
        if not producer then return end
        InputState.lastBuildKey = {
            producer = producer,
            keyIndex = keyIndex,
            time = GetTime(),
            team = team,
        }
    end

    local function TryStartBuildForProducer(producer, team, scrapDelta)
        local keyInfo = InputState.lastBuildKey
        if not keyInfo or keyInfo.producer ~= producer or keyInfo.team ~= team then return end
        local now = GetTime()
        local buildConfig = PersistentConfig.PresetConfig and PersistentConfig.PresetConfig.build
        if (now - (keyInfo.time or 0.0)) > ((buildConfig and buildConfig.keyWindow) or 0.5) then
            return
        end
        local entry = GetBuildEntryForProducer(producer, keyInfo.keyIndex)
        if not entry then return end

        local stockCost = entry.scrapCost or 0.0
        local tolerance = (buildConfig and buildConfig.scrapConfirmTolerance) or 0.5
        if type(scrapDelta) == "number" and stockCost > 0.0 then
            if scrapDelta < (stockCost - tolerance) then
                return
            end
        end

        StartPresetSurchargeForEntry(team, producer, entry)
        InputState.lastBuildKey = nil
    end

    local function UpdateProducerQueues(team)
        local now = GetTime()
        for kindIndex, _ in ipairs(PresetProducerKinds) do
            local producer = GetProducerHandleForKind(kindIndex, team)
            local queue = GetProducerQueueState(kindIndex)
            queue.handle = producer
            local entries = IsValid(producer) and GetProducerBuildEntries(producer) or {}
            local entryCount = #entries
            local selectedEntry = nil
            if entryCount == 0 then
                queue.itemIndex = 1
                queue.unitOdf = ""
                queue.status = "Queue Off"
                queue.remaining = 0
                queue.pendingIssue = nil
                queue.inProgress = false
                queue.count = 0
                queue.locked = false
            else
                queue.itemIndex = ClampIndex(queue.itemIndex, 1, entryCount, 1)
                selectedEntry = entries[queue.itemIndex]
                queue.unitOdf = selectedEntry and selectedEntry.odf or ""
            end

            if queue.count <= 0 then
                queue.remaining = 0
                queue.status = "Queue Off"
                queue.pendingIssue = nil
                queue.inProgress = false
                queue.locked = false
            elseif not IsValid(producer) then
                queue.status = "Queue Paused: Producer Missing"
            else
                if not queue.locked then
                    queue.status = "Queue Ready: Press Enter"
                else
                    if queue.pendingIssue and not IsBusy(producer) then
                        local window = ((PersistentConfig.PresetConfig and PersistentConfig.PresetConfig.build)
                            and PersistentConfig.PresetConfig.build.keyWindow) or 0.5
                        if (now - (queue.pendingIssue.time or 0.0)) > window then
                            queue.remaining = queue.remaining + 1
                            queue.pendingIssue = nil
                        end
                    end

                    if IsSelected(producer) then
                        queue.status = "Queue Paused: Prod Selected"
                    elseif IsBusy(producer) then
                        if queue.inProgress then
                            queue.status = "Queue Building"
                        else
                            queue.status = "Queue Paused: Manual Build"
                        end
                    else
                        if queue.remaining <= 0 then
                            queue.status = "Queue Complete"
                        else
                            local stockCost = selectedEntry and selectedEntry.scrapCost or 0.0
                            local pilotCost = selectedEntry and selectedEntry.pilotCost or 0.0
                            local lowScrap = type(GetScrap) == "function" and stockCost > 0.0 and GetScrap(team) < stockCost
                            local lowPilots = type(GetPilot) == "function" and pilotCost > 0.0 and GetPilot(team) <
                                pilotCost
                            if lowScrap and lowPilots then
                                queue.status = "Queue Paused: Low Scrap/Pilots"
                            elseif lowScrap then
                                queue.status = "Queue Paused: Low Scrap"
                            elseif lowPilots then
                                queue.status = "Queue Paused: Low Pilots"
                            elseif not queue.pendingIssue then
                                if queue.unitOdf and queue.unitOdf ~= "" and type(Build) == "function" then
                                    Build(producer, queue.unitOdf)
                                    queue.pendingIssue = { unitOdf = queue.unitOdf, time = now }
                                    queue.remaining = math.max(0, (queue.remaining or 0) - 1)
                                    queue.status = "Queue Starting..."
                                end
                            else
                                queue.status = "Queue Starting..."
                            end
                        end
                    end
                end
                if queue.count > 0 then
                    local remaining = math.max(0, queue.remaining or 0)
                    queue.status = string.format("%s (%d/%d)", queue.status, remaining, queue.count)
                end
            end
        end
    end

    local function UpdateProducerBuildState(team, scrapDelta)
        local busyState = InputState.producerBusyState
        for kindIndex, _ in ipairs(PresetProducerKinds) do
            local producer = GetProducerHandleForKind(kindIndex, team)
            if IsValid(producer) then
                local isBusy = IsBusy(producer)
                local wasBusy = busyState[producer] or false
                if not wasBusy and isBusy then
                    local queue = GetProducerQueueState(kindIndex)
                    local window = ((PersistentConfig.PresetConfig and PersistentConfig.PresetConfig.build)
                        and PersistentConfig.PresetConfig.build.keyWindow) or 0.5
                    if queue and queue.pendingIssue and (GetTime() - (queue.pendingIssue.time or 0.0)) <= window then
                        queue.inProgress = true
                        local entry = GetUnitBuildEntry(queue.pendingIssue.unitOdf)
                        StartPresetSurchargeForEntry(team, producer, entry)
                        queue.pendingIssue = nil
                    else
                        TryStartBuildForProducer(producer, team, scrapDelta)
                    end
                elseif wasBusy and not isBusy then
                    local queue = GetProducerQueueState(kindIndex)
                    if queue and queue.inProgress then
                        queue.inProgress = false
                    end
                end
                busyState[producer] = isBusy
            end
        end
        for handle, _ in pairs(busyState) do
            if not IsValid(handle) then
                busyState[handle] = nil
            end
        end
    end

    local function FindPendingBuildForUnit(team, unitOdfName, h)
        local pending = InputState.pendingBuilds
        if not pending or #pending == 0 then return nil end
        local wanted = string.lower(CleanString(unitOdfName or ""))
        local now = GetTime()
        local grace = ((PersistentConfig.PresetConfig and PersistentConfig.PresetConfig.build)
            and PersistentConfig.PresetConfig.build.refundGrace) or 1.0
        local bestIndex = nil
        for index, record in ipairs(pending) do
            if record.team == team and record.unitKey == wanted then
                if now <= ((record.expectedFinishAt or 0.0) + grace) then
                    if IsValid(h) and IsValid(record.producer) and type(GetDistance) == "function" then
                        local distance = GetDistance(h, record.producer)
                        if distance and distance <= 12.0 then
                            return index, record
                        end
                    end
                    if not bestIndex then
                        bestIndex = index
                    end
                end
            end
        end
        if bestIndex then
            return bestIndex, pending[bestIndex]
        end
        return nil
    end

    local function UpdatePendingBuildRefunds()
        local pending = InputState.pendingBuilds
        if not pending or #pending == 0 then return end
        local now = GetTime()
        local grace = ((PersistentConfig.PresetConfig and PersistentConfig.PresetConfig.build)
            and PersistentConfig.PresetConfig.build.refundGrace) or 1.0
        for index = #pending, 1, -1 do
            local record = pending[index]
            local expireAt = (record.expectedFinishAt or 0.0) + grace
            local producerValid = IsValid(record.producer)
            local earlyExpire = (not producerValid) and now > ((record.startedAt or 0.0) + 0.5)
            if now > expireAt or earlyExpire then
                if record.charged and record.surcharge and record.surcharge > 0 and type(AddScrap) == "function" then
                    AddScrap(record.team, record.surcharge)
                end
                table.remove(pending, index)
            end
        end
    end

    local function IsCommanderTrackedHandle(h)
        if not IsValid(h) then return false end
        if type(IsBuilding) == "function" and IsBuilding(h) then
            return true
        end
        local label = CleanString((type(GetClassLabel) == "function" and GetClassLabel(h)) or "")
        return label == "turret" or label == "commtower" or label == "powerplant"
    end

    local function RegisterCommanderHandle(h)
        local overview = InputState.commanderOverview
        if not overview or not IsCommanderTrackedHandle(h) then return end
        if overview.handleSet[h] then return end
        overview.handleSet[h] = true
        table.insert(overview.handles, h)
    end

    local function RemoveCommanderHandle(h)
        local overview = InputState.commanderOverview
        if not overview or not h or not overview.handleSet[h] then
            return
        end

        overview.handleSet[h] = nil
        for index = #overview.handles, 1, -1 do
            if overview.handles[index] == h then
                table.remove(overview.handles, index)
                break
            end
        end
    end

    local function ResetCommanderOverview()
        local overview = InputState.commanderOverview
        if not overview then
            return
        end

        overview.initialized = false
        overview.lastUpdate = 0.0
        overview.handles = {}
        overview.handleSet = {}
        overview.stats = {
            counts = {},
            unpoweredTurrets = 0,
            unpoweredComm = 0,
            powerSources = 0,
        }
    end

    local function InitializeCommanderOverview()
        local overview = InputState.commanderOverview
        if not overview or overview.initialized then return end
        InitializeTrackedWorldHandles()
        overview.initialized = true
    end

    local function UpdateCommanderOverview()
        local overview = InputState.commanderOverview
        if not overview then return end
        InitializeCommanderOverview()
        local now = GetTime()
        if now - (overview.lastUpdate or 0.0) < (overview.interval or 1.0) then return end
        overview.lastUpdate = now
        local playerTeam = GetPlayerTeamNum()

        local counts = {
            hangar = 0,
            supply = 0,
            comm = 0,
            silo = 0,
            barracks = 0,
            turret = 0,
        }
        local powerSources = {}
        local turrets = {}
        local comms = {}

        for index = #overview.handles, 1, -1 do
            local h = overview.handles[index]
            if not IsValid(h) or (type(IsAlive) == "function" and not IsAlive(h)) then
                overview.handleSet[h] = nil
                table.remove(overview.handles, index)
            elseif type(GetTeamNum) == "function" and GetTeamNum(h) ~= playerTeam then
                -- Keep the handle tracked for future team changes/captures, but skip counting it for the current player team.
            else
                local label = CleanString((type(GetClassLabel) == "function" and GetClassLabel(h)) or "")
                if label == "powerplant" then
                    local odf = type(GetOdf) == "function" and GetOdf(h) or nil
                    local radius = GetPowerRadius(odf)
                    table.insert(powerSources, { handle = h, radius = radius })
                elseif label == "repairdepot" then
                    counts.hangar = counts.hangar + 1
                elseif label == "supplydepot" then
                    counts.supply = counts.supply + 1
                elseif label == "commtower" then
                    counts.comm = counts.comm + 1
                    table.insert(comms, h)
                elseif label == "turret" then
                    counts.turret = counts.turret + 1
                    table.insert(turrets, h)
                elseif label == "scrapsilo" then
                    counts.silo = counts.silo + 1
                elseif label == "barracks" then
                    counts.barracks = counts.barracks + 1
                end
            end
        end

        local unpoweredTurrets = 0
        local unpoweredComm = 0
        if #powerSources > 0 then
            for _, turret in ipairs(turrets) do
                local powered = false
                for _, power in ipairs(powerSources) do
                    if GetDistance(turret, power.handle) < power.radius then
                        powered = true
                        break
                    end
                end
                if not powered then
                    unpoweredTurrets = unpoweredTurrets + 1
                end
            end
            for _, comm in ipairs(comms) do
                local powered = false
                for _, power in ipairs(powerSources) do
                    if GetDistance(comm, power.handle) < power.radius then
                        powered = true
                        break
                    end
                end
                if not powered then
                    unpoweredComm = unpoweredComm + 1
                end
            end
        else
            unpoweredTurrets = #turrets
            unpoweredComm = #comms
        end

        overview.stats = {
            counts = counts,
            unpoweredTurrets = unpoweredTurrets,
            unpoweredComm = unpoweredComm,
            powerSources = #powerSources,
        }
    end

    return {
        QueueGameKey = QueueGameKey,
        ConsumePendingGameKeyMatch = ConsumePendingGameKeyMatch,
        GetProducerQueueState = GetProducerQueueState,
        UpdateTeamScrapSnapshot = UpdateTeamScrapSnapshot,
        RecordBuildKeyIfPressed = RecordBuildKeyIfPressed,
        UpdateProducerQueues = UpdateProducerQueues,
        UpdateProducerBuildState = UpdateProducerBuildState,
        FindPendingBuildForUnit = FindPendingBuildForUnit,
        UpdatePendingBuildRefunds = UpdatePendingBuildRefunds,
        IsCommanderTrackedHandle = IsCommanderTrackedHandle,
        RegisterCommanderHandle = RegisterCommanderHandle,
        RemoveCommanderHandle = RemoveCommanderHandle,
        ResetCommanderOverview = ResetCommanderOverview,
        UpdateCommanderOverview = UpdateCommanderOverview,
    }
end

return M
