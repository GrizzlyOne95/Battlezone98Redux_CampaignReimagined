-- PersistentConfigP.lua
---@diagnostic disable: lowercase-global, undefined-global

local M = {}

function M.Create(deps)
    local PersistentConfig = deps.PersistentConfig
    local InputState = deps.InputState
    local PdaPages = deps.PdaPages
    local AppendPdaFooter = deps.AppendPdaFooter
    local AppendPdaNavHints = deps.AppendPdaNavHints
    local BuildPdaHeader = deps.BuildPdaHeader
    local ClampIndex = deps.ClampIndex
    local ClampRange = deps.ClampRange
    local CleanString = deps.CleanString
    local FormatPresetSlotValue = deps.FormatPresetSlotValue
    local GetAimInfo = deps.GetAimInfo
    local GetDisplayedWeaponStats = deps.GetDisplayedWeaponStats
    local GetEffectiveWeaponRangeMeters = deps.GetEffectiveWeaponRangeMeters
    local GetHardpointCategoryLabel = deps.GetHardpointCategoryLabel
    local GetHudTargetInfo = deps.GetHudTargetInfo
    local GetHorizontalDistanceBetweenHandles = deps.GetHorizontalDistanceBetweenHandles
    local GetHorizontalDistanceBetweenPositions = deps.GetHorizontalDistanceBetweenPositions
    local GetInstalledWeaponMask = deps.GetInstalledWeaponMask
    local GetPlayerSpeedMeters = deps.GetPlayerSpeedMeters
    local GetPresetPageContext = deps.GetPresetPageContext
    local GetPresetSlotOption = deps.GetPresetSlotOption
    local GetPresetSurchargeForEntry = deps.GetPresetSurchargeForEntry
    local GetProducerQueueState = deps.GetProducerQueueState
    local GetQueuePageContext = deps.GetQueuePageContext
    local GetSettingsPageEntries = deps.GetSettingsPageEntries
    local GetTargetClosureInfo = deps.GetTargetClosureInfo
    local GetUnitPresetRecord = deps.GetUnitPresetRecord
    local GetVehicleDisplayName = deps.GetVehicleDisplayName
    local GetWeaponReticleName = deps.GetWeaponReticleName
    local GetWeaponStats = deps.GetWeaponStats
    local IsMaskBitSet = deps.IsMaskBitSet
    local ResolveLiveSelectedWeaponMask = deps.ResolveLiveSelectedWeaponMask

    local function FormatWholeNumber(value)
        if value == nil then return "n/a" end
        return tostring(math.floor(value + 0.5))
    end

    local function FormatDps(value)
        if value == nil then return "n/a" end
        if value >= 100 then
            return FormatWholeNumber(value)
        end
        return string.format("%.1f", value)
    end

    local function BuildMeterBar(label, fraction, currentValue, maxValue)
        local width = 28
        local clamped = math.max(0.0, math.min(1.0, fraction or 0.0))
        local filled = math.floor((clamped * width) + 0.5)
        if filled > width then filled = width end
        local empty = width - filled
        local currentText = currentValue and FormatWholeNumber(currentValue) or nil
        local maxText = maxValue and FormatWholeNumber(maxValue) or nil
        local numericText = ""
        if currentText and maxText then
            numericText = " " .. currentText .. "/" .. maxText
        end
        return string.format("%-4s [%s%s] %3d%%%s", label, string.rep("=", filled), string.rep(".", empty),
            math.floor((clamped * 100.0) + 0.5), numericText)
    end

    local function FormatWeaponRangeText(weaponStats, effectiveRange)
        local minRange = weaponStats and weaponStats.rangeMin or nil
        local maxRange = weaponStats and weaponStats.rangeMax or nil
        local baseRange = weaponStats and weaponStats.range or nil
        local rangeText = FormatWholeNumber(baseRange)

        if minRange and maxRange and math.abs(maxRange - minRange) >= 5.0 then
            rangeText = FormatWholeNumber(minRange) .. "-" .. FormatWholeNumber(maxRange)
        end

        if weaponStats and weaponStats.ballistic and effectiveRange and baseRange and
            math.abs(effectiveRange - baseRange) >= 5.0 then
            rangeText = rangeText .. ">" .. FormatWholeNumber(effectiveRange)
        end

        return rangeText
    end

    local function FormatWeaponDamageText(weaponStats)
        if not weaponStats then return "n/a" end
        local splashRadius = weaponStats.splashRadiusMax or weaponStats.splashRadius
        if splashRadius and splashRadius > 0.0 and weaponStats.damageMin and weaponStats.damageMax and
            math.abs(weaponStats.damageMax - weaponStats.damageMin) >= 1.0 then
            return "~" ..
                FormatWholeNumber(PersistentConfig._EstimateSplashAverageValue(weaponStats.damageMin, weaponStats.damageMax, splashRadius))
        end
        if weaponStats.damageMin and weaponStats.damageMax and math.abs(weaponStats.damageMax - weaponStats.damageMin) >= 1.0 then
            return FormatWholeNumber(weaponStats.damageMin) .. "-" .. FormatWholeNumber(weaponStats.damageMax)
        end
        return FormatWholeNumber(weaponStats.damage)
    end

    local function FormatWeaponDpsText(weaponStats)
        if not weaponStats then return "n/a" end
        local splashRadius = weaponStats.splashRadiusMax or weaponStats.splashRadius
        if splashRadius and splashRadius > 0.0 and weaponStats.dpsMin and weaponStats.dpsMax and
            math.abs(weaponStats.dpsMax - weaponStats.dpsMin) >= 0.1 then
            return "~" ..
                FormatDps(PersistentConfig._EstimateSplashAverageValue(weaponStats.dpsMin, weaponStats.dpsMax, splashRadius))
        end
        if weaponStats.dpsMin and weaponStats.dpsMax and math.abs(weaponStats.dpsMax - weaponStats.dpsMin) >= 0.1 then
            return FormatDps(weaponStats.dpsMin) .. "-" .. FormatDps(weaponStats.dpsMax)
        end
        return FormatDps(weaponStats.dps)
    end

    local function FormatWeaponSplashText(weaponStats)
        if not weaponStats then return nil end

        local minRadius = weaponStats.splashRadiusMin or weaponStats.splashRadius
        local maxRadius = weaponStats.splashRadiusMax or weaponStats.splashRadius
        if not maxRadius or maxRadius <= 0.0 then
            return nil
        end
        if minRadius and math.abs(maxRadius - minRadius) >= 1.0 then
            return FormatWholeNumber(minRadius) .. "-" .. FormatWholeNumber(maxRadius) .. "m"
        end
        return FormatWholeNumber(maxRadius) .. "m"
    end

    local function FormatWeaponShotsLeftText(weaponStats, currentAmmo)
        if not weaponStats then return nil end

        local function ComputeShots(ammoCost)
            if ammoCost == nil then
                return nil
            end
            ammoCost = tonumber(ammoCost) or 0.0
            if ammoCost <= 0.001 then
                return math.huge
            end
            if type(currentAmmo) ~= "number" then
                return nil
            end
            return math.max(0, math.floor((currentAmmo / ammoCost) + 0.0001))
        end

        local minShots = ComputeShots(weaponStats.ammoCostMax or weaponStats.ammoCost)
        local maxShots = ComputeShots(weaponStats.ammoCostMin or weaponStats.ammoCost)
        if minShots == nil and maxShots == nil then
            return nil
        end

        local function FormatShots(value)
            if value == math.huge then
                return "INF"
            end
            if value == nil then
                return "n/a"
            end
            return tostring(value)
        end

        if minShots == maxShots then
            return FormatShots(minShots)
        end

        if minShots == nil then
            return FormatShots(maxShots)
        end
        if maxShots == nil then
            return FormatShots(minShots)
        end

        local low = math.min(minShots, maxShots)
        local high = math.max(minShots, maxShots)
        return FormatShots(low) .. "-" .. FormatShots(high)
    end

    local function BuildChargeSummaryText(weaponStats)
        local levels = weaponStats and weaponStats.chargeLevels or nil
        if not levels or #levels <= 0 then return nil end

        local picks = {}
        local candidateIndices = { 1, math.floor((#levels + 1) * 0.5), #levels }
        local currentChargeLevel = weaponStats and weaponStats.currentChargeLevel or nil
        for _, idx in ipairs(candidateIndices) do
            idx = math.max(1, math.min(#levels, idx))
            if not picks[idx] then
                picks[idx] = true
            end
        end
        if currentChargeLevel then
            for idx, level in ipairs(levels) do
                if (level.chargeIndex or idx) == currentChargeLevel then
                    picks[idx] = true
                    break
                end
            end
        end

        local parts = { "  CHG" }
        for idx = 1, #levels do
            if picks[idx] then
                local level = levels[idx]
                local statText = FormatWholeNumber(level.damage)
                if level.dps then
                    statText = statText .. "/" .. FormatDps(level.dps)
                end
                local levelLabel = string.format("L%d", level.chargeIndex or idx)
                if currentChargeLevel and (level.chargeIndex or idx) == currentChargeLevel then
                    levelLabel = levelLabel .. "*"
                end
                table.insert(parts, string.format("%s %s", levelLabel, statText))
            end
        end

        return table.concat(parts, "  ")
    end

    local function AppendWeaponStatsLines(lines, h, installedMask, activeMask, compareTarget, comparePosition, compareDistance)
        local hardpointCount = 0
        local shooterPos = type(GetPosition) == "function" and GetPosition(h) or nil
        local currentAmmo = type(GetCurAmmo) == "function" and GetCurAmmo(h) or nil

        for slot = 0, 4 do
            if IsMaskBitSet(installedMask, slot) then
                local weapon = CleanString(GetWeaponClass(h, slot))
                if weapon ~= "" then
                    if hardpointCount > 0 then
                        table.insert(lines, "")
                    end
                    hardpointCount = hardpointCount + 1
                    local weaponStats = GetDisplayedWeaponStats(h, weapon, GetWeaponStats(weapon) or {}) or {}
                    local effectiveRange = weaponStats.range
                    local distanceForCompare = compareDistance
                    if compareTarget and IsValid(compareTarget) then
                        local targetPos = type(GetPosition) == "function" and GetPosition(compareTarget) or nil
                        effectiveRange = GetEffectiveWeaponRangeMeters(weaponStats, shooterPos, targetPos) or weaponStats.range
                        distanceForCompare = GetHorizontalDistanceBetweenHandles(h, compareTarget) or compareDistance
                    elseif comparePosition then
                        effectiveRange = GetEffectiveWeaponRangeMeters(weaponStats, shooterPos, comparePosition) or weaponStats.range
                        distanceForCompare = GetHorizontalDistanceBetweenPositions(shooterPos, comparePosition) or compareDistance
                    end
                    local status = "  "
                    if distanceForCompare then
                        if effectiveRange then
                            status = (distanceForCompare <= effectiveRange) and "+ " or "- "
                        else
                            status = "? "
                        end
                    end
                    local rangeText = FormatWeaponRangeText(weaponStats, effectiveRange)

                    table.insert(lines, string.format("S%d %s %s", slot + 1, status, weaponStats.displayName or weapon))
                    table.insert(lines,
                        string.format("  Range %sm  Damage %s  DPS %s", rangeText,
                            FormatWeaponDamageText(weaponStats), FormatWeaponDpsText(weaponStats)))
                    local shotsText = FormatWeaponShotsLeftText(weaponStats, currentAmmo)
                    local splashText = FormatWeaponSplashText(weaponStats)
                    if shotsText or splashText then
                        local detailParts = {}
                        if shotsText then
                            detailParts[#detailParts + 1] = "SHOTS " .. shotsText
                        end
                        if splashText then
                            detailParts[#detailParts + 1] = "AOE " .. splashText
                        end
                        table.insert(lines, "  " .. table.concat(detailParts, "  "))
                    end
                    local chargeSummary = BuildChargeSummaryText(weaponStats)
                    if chargeSummary then
                        table.insert(lines, chargeSummary)
                    end
                end
            end
        end

        if hardpointCount == 0 then
            table.insert(lines, "NONE")
        end

        return hardpointCount
    end

    local function AppendTargetWeaponStatusLines(lines, h, selectedMask, compareTarget, comparePosition, compareDistance)
        local count = 0
        local shooterPos = type(GetPosition) == "function" and GetPosition(h) or nil

        for slot = 0, 4 do
            if IsMaskBitSet(selectedMask, slot) then
                local weapon = CleanString(GetWeaponClass(h, slot))
                if weapon ~= "" then
                    count = count + 1
                    local weaponStats = GetDisplayedWeaponStats(h, weapon, GetWeaponStats(weapon) or {}) or {}
                    local effectiveRange = weaponStats.range
                    local distanceForCompare = compareDistance

                    if compareTarget and IsValid(compareTarget) then
                        local targetPos = type(GetPosition) == "function" and GetPosition(compareTarget) or nil
                        effectiveRange = GetEffectiveWeaponRangeMeters(weaponStats, shooterPos, targetPos) or weaponStats.range
                        distanceForCompare = GetHorizontalDistanceBetweenHandles(h, compareTarget) or compareDistance
                    elseif comparePosition then
                        effectiveRange = GetEffectiveWeaponRangeMeters(weaponStats, shooterPos, comparePosition) or weaponStats.range
                        distanceForCompare = GetHorizontalDistanceBetweenPositions(shooterPos, comparePosition) or compareDistance
                    end

                    local status = "UNKNOWN"
                    if distanceForCompare and effectiveRange then
                        status = (distanceForCompare <= effectiveRange) and "IN RANGE" or "OUT OF RANGE"
                    end

                    local displayName = CleanString(weaponStats.displayName or weapon)
                    table.insert(lines, string.format("S%d %-18s %s", slot + 1, displayName, status))
                end
            end
        end

        if count == 0 then
            table.insert(lines, "NONE")
        end

        return count
    end

    local function GetTargetPageWeaponSummary(player, selectedMask)
        if not IsValid(player) then return nil end

        local searchMask = ResolveLiveSelectedWeaponMask(player, selectedMask)
        if not searchMask or searchMask <= 0 then
            return nil
        end

        local parts = {}
        for slot = 0, 4 do
            if IsMaskBitSet(searchMask, slot) then
                local weapon = CleanString(GetWeaponClass(player, slot))
                if weapon ~= "" then
                    local displayedStats = GetDisplayedWeaponStats(player, weapon, GetWeaponStats(weapon) or {}) or {}
                    local reticle = GetWeaponReticleName(weapon, displayedStats.currentChargeLevel)
                    local displayName = CleanString(displayedStats.displayName or weapon)
                    local part = string.format("S%d %s", slot + 1, displayName)
                    if reticle and reticle ~= "" then
                        part = string.format("S%d %s/%s", slot + 1, reticle, displayName)
                    end
                    parts[#parts + 1] = part
                end
            end
        end

        if #parts == 0 then
            return nil
        end

        return "Weapons  " .. table.concat(parts, " | ")
    end

    local function DescribeAimMode(aimInfo)
        if not aimInfo then
            return "NO TARGET"
        end
        if aimInfo.source == "target" then
            return "TARGET LOCK"
        end
        if aimInfo.source == "reticle_object" then
            return "SMART RETICLE"
        end
        if aimInfo.source == "reticle_pos" then
            return "GROUND RETICLE"
        end
        return "TARGET"
    end

    local function BuildStatsPageText(player, mask)
        local lines = { BuildPdaHeader(PdaPages.STATS) }
        local speed = math.floor(GetPlayerSpeedMeters(player) + 0.5)
        local _, targetDistance = GetHudTargetInfo(player)
        local unitName = GetVehicleDisplayName(player) or "Unknown"
        local playerHealth = (type(GetHealth) == "function") and (GetHealth(player) or 0.0) or 0.0
        local playerAmmo = (type(GetAmmo) == "function") and (GetAmmo(player) or 0.0) or 0.0
        local curHealth = type(GetCurHealth) == "function" and GetCurHealth(player) or nil
        local maxHealth = type(GetMaxHealth) == "function" and GetMaxHealth(player) or nil
        local curAmmo = type(GetCurAmmo) == "function" and GetCurAmmo(player) or nil
        local maxAmmo = type(GetMaxAmmo) == "function" and GetMaxAmmo(player) or nil
        local installedMask = GetInstalledWeaponMask(player)
        local distanceText = targetDistance and (tostring(math.floor(targetDistance + 0.5)) .. "m") or "--"

        table.insert(lines, "UNIT " .. unitName)
        table.insert(lines, "Speed  " .. tostring(speed) .. "m/s  Distance  " .. distanceText)
        table.insert(lines, BuildMeterBar("HULL", playerHealth, curHealth, maxHealth))
        table.insert(lines, BuildMeterBar("AMMO", playerAmmo, curAmmo, maxAmmo))
        table.insert(lines, "")
        table.insert(lines, "HARDPOINTS")

        local hardpointCount = AppendWeaponStatsLines(lines, player, installedMask, mask, nil, nil, nil)
        table.insert(lines, "TOTAL " .. tostring(hardpointCount))
        AppendPdaNavHints(lines)
        return table.concat(lines, "\n")
    end

    local function BuildTargetPageText(player, selectedMask)
        local lines = { BuildPdaHeader(PdaPages.TARGET) }
        local aimInfo = GetAimInfo(player, true)
        local target = aimInfo and aimInfo.handle or nil
        local targetDistance = aimInfo and aimInfo.distance or nil
        local aimPosition = aimInfo and aimInfo.position or nil
        local reticleLine = GetTargetPageWeaponSummary(player, selectedMask)

        table.insert(lines, "MODE " .. DescribeAimMode(aimInfo))
        if reticleLine then
            table.insert(lines, reticleLine)
        end

        if not aimInfo or not targetDistance then
            table.insert(lines, "NO TARGET")
            table.insert(lines, "Aim at a unit to inspect it.")
            AppendPdaNavHints(lines)
            return table.concat(lines, "\n")
        end

        if not target and aimPosition then
            local playerPos = type(GetPosition) == "function" and GetPosition(player) or nil
            local deltaY = playerPos and ((aimPosition.y or 0.0) - (playerPos.y or 0.0)) or 0.0
            table.insert(lines, "UNIT AIM POINT")
            table.insert(lines, "ROLE TERRAIN")
            table.insert(lines, "Distance  " .. tostring(math.floor(targetDistance + 0.5)) .. "m")
            table.insert(lines, "ELV  " .. tostring(math.floor(deltaY + (deltaY >= 0 and 0.5 or -0.5))) .. "m")
            table.insert(lines,
                string.format("POS  %d %d %d", math.floor((aimPosition.x or 0.0) + 0.5), math.floor((aimPosition.y or 0.0) + 0.5),
                    math.floor((aimPosition.z or 0.0) + 0.5)))
            table.insert(lines, "Reticle position")
            AppendPdaNavHints(lines)
            return table.concat(lines, "\n")
        end

        local speed = math.floor(GetPlayerSpeedMeters(target) + 0.5)
        local unitName = GetVehicleDisplayName(target) or "Unknown"
        local role = CleanString((type(GetClassLabel) == "function" and GetClassLabel(target)) or "")
        local targetHealth = (type(GetHealth) == "function") and (GetHealth(target) or 0.0) or 0.0
        local targetAmmo = (type(GetAmmo) == "function") and (GetAmmo(target) or 0.0) or 0.0
        local curHealth = type(GetCurHealth) == "function" and GetCurHealth(target) or nil
        local maxHealth = type(GetMaxHealth) == "function" and GetMaxHealth(target) or nil
        local curAmmo = type(GetCurAmmo) == "function" and GetCurAmmo(target) or nil
        local maxAmmo = type(GetMaxAmmo) == "function" and GetMaxAmmo(target) or nil
        local selectedWeaponMask = ResolveLiveSelectedWeaponMask(player, selectedMask)
        local _, eta = GetTargetClosureInfo(player, target, targetDistance)

        table.insert(lines, "UNIT " .. unitName)
        if role ~= "" then
            table.insert(lines, "ROLE " .. role)
        end
        table.insert(lines, "Distance  " .. tostring(math.floor(targetDistance + 0.5)) .. "m")
        table.insert(lines, "Speed  " .. tostring(speed) .. "m/s")
        table.insert(lines, "Arrival  " .. (eta and string.format("%.1fs", eta) or "--"))

        local selectedWeaponLines = {}
        local selectedWeaponCount = 0
        if selectedWeaponMask > 0 then
            selectedWeaponCount = AppendTargetWeaponStatusLines(selectedWeaponLines, player, selectedWeaponMask, target, nil,
                targetDistance)
        end
        if selectedWeaponCount > 0 then
            table.insert(lines, "SELECTED")
            for _, line in ipairs(selectedWeaponLines) do
                table.insert(lines, line)
            end
            table.insert(lines, "TOTAL " .. tostring(selectedWeaponCount))
        else
            table.insert(lines, "Weapons  None selected")
        end
        table.insert(lines, BuildMeterBar("AMMO", targetAmmo, curAmmo, maxAmmo))
        table.insert(lines, BuildMeterBar("HULL", targetHealth, curHealth, maxHealth))
        AppendPdaNavHints(lines)
        return table.concat(lines, "\n")
    end

    local function BuildSettingsPageText()
        local lines = { BuildPdaHeader(PdaPages.SETTINGS) }
        local settingsEntries = (GetSettingsPageEntries and GetSettingsPageEntries()) or {}
        local count = math.max(#settingsEntries, 1)
        local selection = ClampIndex(InputState.pdaSettingsIndex, 1, count, 1)
        local visibleRows = 10
        local startIndex = math.max(1, math.min(selection - math.floor(visibleRows / 2), math.max(1, count - visibleRows + 1)))
        local endIndex = math.min(count, startIndex + visibleRows - 1)
        local labelWidth = 0
        local selectableCount = 0
        local selectedOrdinal = 0

        if #settingsEntries == 0 then
            table.insert(lines, "Item 00/00")
            table.insert(lines, "No settings available")
        else
            for index = 1, #settingsEntries do
                local entry = settingsEntries[index]
                if entry and entry.selectable ~= false then
                    selectableCount = selectableCount + 1
                    if index == selection then
                        selectedOrdinal = selectableCount
                    end
                end
            end
            table.insert(lines, string.format("Item %02d/%02d", selectedOrdinal, selectableCount))

            for index = startIndex, endIndex do
                local entry = settingsEntries[index]
                if entry and entry.selectable ~= false then
                    labelWidth = math.max(labelWidth, #(entry.label or ""))
                end
            end
            labelWidth = ClampRange(labelWidth, 8, 20, 12)

            for index = startIndex, endIndex do
                local entry = settingsEntries[index]
                if entry and entry.selectable == false then
                    table.insert(lines, string.format("  [%s]", entry.label or "Section"))
                else
                    local prefix = (selection == index) and ">" or ((entry and entry.warning) and "!" or " ")
                    table.insert(lines, string.format("%s %-" .. tostring(labelWidth) .. "s %s", prefix, entry.label, entry.value))
                end
            end
        end

        AppendPdaFooter(lines,
            "--------------------------------",
            string.format("Show %02d-%02d/%02d  [ / ] Page", startIndex, endIndex, count),
            "Up/Down Select  Left/Right Change")
        return table.concat(lines, "\n")
    end

    local function BuildPresetPageText()
        local lines = { BuildPdaHeader(PdaPages.PRESETS) }
        local context = GetPresetPageContext()

        if not context.available then
            table.insert(lines, "Armory not available")
            table.insert(lines, "Build an Armory to edit")
            table.insert(lines, "unit upgrade presets.")
            AppendPdaNavHints(lines)
            return table.concat(lines, "\n")
        end

        if #context.producerKinds == 0 then
            table.insert(lines, "No producers available")
            table.insert(lines, "Recycler/Factory missing.")
            AppendPdaNavHints(lines)
            return table.concat(lines, "\n")
        end

        local selectedEntry = context.selectedEntry
        local rowIndex = ClampIndex(InputState.presetRow, 1, math.max(#context.rows, 1), 1)

        local function RowPrefix(index)
            return (rowIndex == index) and ">" or " "
        end

        table.insert(lines, string.format("%s %-11s %s", RowPrefix(1), "Producer", context.producerInfo.label))
        if selectedEntry then
            table.insert(lines, string.format("%s %-11s %s", RowPrefix(2), "Unit", selectedEntry.displayName))
            local unitPreset = GetUnitPresetRecord(selectedEntry.odf)
            for slotOffset, slotInfo in ipairs(selectedEntry.slots or {}) do
                local option = GetPresetSlotOption(slotInfo, context.armoryOptions, unitPreset)
                table.insert(lines,
                    string.format("%s S%d %-8s %s", RowPrefix(2 + slotOffset), slotInfo.slotIndex,
                        GetHardpointCategoryLabel(slotInfo.category), FormatPresetSlotValue(slotInfo, option)))
            end
            local surchargeRow = 2 + #(selectedEntry.slots or {}) + 1
            table.insert(lines,
                string.format("%s %-11s +%s", RowPrefix(surchargeRow), "Surcharge",
                    FormatWholeNumber(GetPresetSurchargeForEntry(selectedEntry)) .. " scrap"))
        else
            table.insert(lines, string.format("%s %-11s %s", RowPrefix(2), "Unit", "None"))
        end

        local selectedRow = context.rows and context.rows[rowIndex] or nil
        if selectedRow and selectedRow.kind == "slot" and selectedEntry then
            local slotInfo = selectedRow.slotInfo
            local unitPreset = GetUnitPresetRecord(selectedEntry.odf)
            local option = GetPresetSlotOption(slotInfo, context.armoryOptions, unitPreset)
            local selectedWeapon = option and option.weaponName or ""
            local stockWeapon = slotInfo and slotInfo.stockWeapon or ""
            if selectedWeapon == "" then
                selectedWeapon = stockWeapon
            end
            local stockStats = (stockWeapon ~= "" and GetWeaponStats(stockWeapon)) or nil
            local selectedStats = (selectedWeapon ~= "" and GetWeaponStats(selectedWeapon)) or nil

            local function FormatDelta(value, unit, decimals)
                if value == nil then return "n/a" end
                local format = "%+.0f"
                if decimals and decimals > 0 then
                    format = "%+." .. tostring(decimals) .. "f"
                end
                return string.format(format, value) .. (unit or "")
            end

            local baseSurcharge = math.floor(GetPresetSurchargeForEntry(selectedEntry) + 0.5)
            local original = unitPreset and unitPreset[slotInfo.slotIndex] or nil
            if unitPreset then
                unitPreset[slotInfo.slotIndex] = nil
            end
            local withoutSurcharge = math.floor(GetPresetSurchargeForEntry(selectedEntry) + 0.5)
            if unitPreset then
                unitPreset[slotInfo.slotIndex] = original
            end
            local deltaCost = math.max(0, baseSurcharge - withoutSurcharge)

            local dpsDelta = (selectedStats and selectedStats.dps or nil) and
                ((selectedStats.dps or 0.0) - (stockStats and stockStats.dps or 0.0)) or nil
            local rangeDelta = (selectedStats and selectedStats.range or nil) and
                ((selectedStats.range or 0.0) - (stockStats and stockStats.range or 0.0)) or nil
            local delayDelta = (selectedStats and selectedStats.shotDelay or nil) and
                ((selectedStats.shotDelay or 0.0) - (stockStats and stockStats.shotDelay or 0.0)) or nil

            table.insert(lines, "")
            table.insert(lines, string.format("Compare S%d", slotInfo.slotIndex))
            table.insert(lines, string.format("Cost +%d scrap", deltaCost))
            table.insert(lines, string.format("DPS  %s", FormatDelta(dpsDelta, "", 1)))
            table.insert(lines, string.format("Range  %s", FormatDelta(rangeDelta, "m", 0)))
            table.insert(lines, string.format("Delay  %s", FormatDelta(delayDelta, "s", 2)))
        end

        table.insert(lines, "")
        table.insert(lines, "Preset applies after build.")
        table.insert(lines, "No refunds for downgrades.")
        AppendPdaFooter(lines, "--------------------------------", "Enter Action  [ / ] Switch Page",
            "Up/Down Select  Left/Right Change")
        return table.concat(lines, "\n")
    end

    local function BuildQueuePageText()
        local lines = { BuildPdaHeader(PdaPages.QUEUE) }
        local context = GetQueuePageContext()

        if not context.available then
            table.insert(lines, "")
            table.insert(lines, "Undeployed")
            AppendPdaNavHints(lines)
            return table.concat(lines, "\n")
        end

        local rowIndex = ClampIndex(InputState.queueRow, 1, math.max(#context.rows, 1), 1)
        local queue = GetProducerQueueState(context.producerInfo.kindIndex)

        local function RowPrefix(index)
            return (rowIndex == index) and ">" or " "
        end

        local queueItemName = "NONE"
        if #context.unitEntries > 0 then
            local queueEntry = context.unitEntries[ClampIndex(queue.itemIndex or 1, 1, #context.unitEntries, 1)]
            queueItemName = queueEntry and (queueEntry.displayName or queueEntry.odf) or "NONE"
        end

        table.insert(lines, string.format("%s %-11s %s", RowPrefix(1), "Producer", context.producerInfo.label))
        table.insert(lines, string.format("%s %-11s %s", RowPrefix(2), "Queue Item", queueItemName))
        table.insert(lines, string.format("%s %-11s %d", RowPrefix(3), "Queue Count", queue.count or 0))
        table.insert(lines, string.format("%s %-11s %s", RowPrefix(4), "Queue", queue.status or "Queue Off"))

        AppendPdaFooter(lines, "--------------------------------", "Enter Lock/Unlock  [ / ] Page",
            "Up/Down Select  Left/Right Change")
        return table.concat(lines, "\n")
    end

    local function BuildCommandPageText()
        local lines = { BuildPdaHeader(PdaPages.COMMAND) }
        local overview = InputState.commanderOverview
        if not overview or not overview.initialized then
            table.insert(lines, "Commander Overview")
            table.insert(lines, "Scanning structures...")
            AppendPdaNavHints(lines)
            return table.concat(lines, "\n")
        end

        local stats = overview.stats or {}
        local counts = stats.counts or {}
        table.insert(lines, "Commander Overview")
        table.insert(lines, string.format("HANGAR   %d", counts.hangar or 0))
        table.insert(lines, string.format("SUPPLY   %d", counts.supply or 0))
        table.insert(lines, string.format("COMM     %d", counts.comm or 0))
        table.insert(lines, string.format("SILO     %d", counts.silo or 0))
        table.insert(lines, string.format("BARRACKS %d", counts.barracks or 0))
        table.insert(lines, string.format("TOWER    %d", counts.turret or 0))
        table.insert(lines, "")
        table.insert(lines, string.format("UNPOWERED TOWERS %d", stats.unpoweredTurrets or 0))
        table.insert(lines, string.format("UNPOWERED COMM   %d", stats.unpoweredComm or 0))
        AppendPdaNavHints(lines)
        return table.concat(lines, "\n")
    end

    local function BuildWeaponStatsText(player, mask)
        local page = ClampIndex(InputState.pdaPage, 1, PdaPages.COUNT, PdaPages.STATS)
        if page == PdaPages.TARGET then
            return BuildTargetPageText(player, mask)
        end
        if page == PdaPages.SETTINGS then
            return BuildSettingsPageText()
        end
        if page == PdaPages.PRESETS then
            return BuildPresetPageText()
        end
        if page == PdaPages.QUEUE then
            return BuildQueuePageText()
        end
        if page == PdaPages.COMMAND then
            return BuildCommandPageText()
        end
        return BuildStatsPageText(player, mask)
    end

    return {
        BuildWeaponStatsText = BuildWeaponStatsText,
    }
end

return M
