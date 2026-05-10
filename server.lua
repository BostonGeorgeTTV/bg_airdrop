local activeDrop = nil
local nextDropAt = 0
local framework = 'standalone'
local finishDrop

local function beginExpiryTimer(dropId)
    if not activeDrop or activeDrop.id ~= dropId or not activeDrop.expiresAt then return end

    local expiresAt = activeDrop.expiresAt
    local waitMs = math.max(0, (expiresAt - os.time()) * 1000)

    SetTimeout(waitMs, function()
        if activeDrop and activeDrop.id == dropId and activeDrop.expiresAt and os.time() >= activeDrop.expiresAt then
            finishDrop('expired')
        end
    end)
end

local function debugPrint(...)
    if Config.Debug then
        print('[bg_airdrop:server]', ...)
    end
end

local function detectFramework()
    if Config.Framework ~= 'auto' then
        return Config.Framework
    end

    if GetResourceState('qbx_core') == 'started' then
        QBXCore = exports['qbx_core']:GetCoreObject()
        return 'qbox'
    end

    if GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        return 'qbcore'
    end

    if GetResourceState('es_extended') == 'started' then
        ESX = exports.es_extended:getSharedObject()
        return 'esx'
    end

    return 'standalone'
end

local function notifyPlayer(source, message, nType)
    if source == 0 then
        print(('[bg_airdrop] %s'):format(message))
        return
    end

    TriggerClientEvent('bg_airdrop:client:notify', source, {
        type = nType or 'inform',
        title = 'Airdrop',
        description = message
    })
end

local function coordsToTable(coords)
    return {
        x = coords.x + 0.0,
        y = coords.y + 0.0,
        z = coords.z + 0.0
    }
end

local function tableToVec3(coords)
    return vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end

local function normalisePoint(point)
    if point.coords then
        return point.coords, point.label
    end

    return point, nil
end

local function pickDropPoint(index)
    if not Config.DropPoints or #Config.DropPoints == 0 then
        return nil, nil
    end

    local selectedIndex = tonumber(index) or math.random(1, #Config.DropPoints)
    selectedIndex = math.max(1, math.min(selectedIndex, #Config.DropPoints))

    local coords, label = normalisePoint(Config.DropPoints[selectedIndex])
    return coords, label or ('Punto %s'):format(selectedIndex)
end

local function cloneTable(tbl)
    if type(tbl) ~= 'table' then return tbl end

    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = cloneTable(v)
    end

    return copy
end

local function isValidItem(itemName)
    if not Config.Loot.SkipInvalidItems then return true end

    local ok, item = pcall(function()
        return exports.ox_inventory:Items(itemName)
    end)

    return ok and item ~= nil
end

local function weightedPick(pool)
    local totalWeight = 0

    for _, item in ipairs(pool) do
        totalWeight = totalWeight + (item.weight or item.chance or 1)
    end

    if totalWeight <= 0 then return nil end

    local roll = math.random() * totalWeight
    local cursor = 0

    for index, item in ipairs(pool) do
        cursor = cursor + (item.weight or item.chance or 1)
        if roll <= cursor then
            return item, index
        end
    end

    return pool[#pool], #pool
end

local function generateLoot()
    local generated = {}
    local sourcePool = {}

    for _, item in ipairs(Config.Loot.Items or {}) do
        if item.name and isValidItem(item.name) then
            sourcePool[#sourcePool + 1] = item
        elseif Config.Debug then
            print(('[bg_airdrop] Item ignorato perché non valido in ox_inventory: %s'):format(tostring(item.name)))
        end
    end

    if #sourcePool == 0 then
        return generated
    end

    local rollsConfig = Config.Loot.Rolls or { min = 1, max = 1 }
    local minRolls = math.max(1, rollsConfig.min or 1)
    local maxRolls = math.max(minRolls, rollsConfig.max or minRolls)
    local rolls = math.random(minRolls, maxRolls)
    rolls = math.min(rolls, Config.Inventory.Slots or rolls)

    for _ = 1, rolls do
        if #sourcePool == 0 then break end

        local selected, selectedIndex = weightedPick(sourcePool)
        if selected then
            local minCount = selected.min or selected.count or 1
            local maxCount = selected.max or minCount
            local count = math.random(minCount, maxCount)

            generated[#generated + 1] = {
                selected.name,
                count,
                cloneTable(selected.metadata)
            }

            if not Config.Loot.AllowDuplicates then
                table.remove(sourcePool, selectedIndex)
            end
        end
    end

    return generated
end

local function publicDropData(drop)
    return {
        id = drop.id,
        stashId = drop.stashId,
        coords = drop.coords,
        groundCoords = drop.groundCoords,
        heading = drop.heading,
        label = drop.label,
        createdAt = drop.createdAt,
        landsAt = drop.landsAt,
        expiresAt = drop.expiresAt,
        landed = drop.landed,
        landedAt = drop.landedAt
    }
end

local function removeInventory(stashId)
    if not stashId then return end

    pcall(function()
        exports.ox_inventory:ClearInventory(stashId)
    end)

    pcall(function()
        exports.ox_inventory:RemoveInventory(stashId)
    end)
end

finishDrop = function(reason)
    if not activeDrop then return end

    local drop = activeDrop
    local dropId = drop.id
    local stashId = drop.stashId

    debugPrint(('Fine airdrop %s. Motivo: %s'):format(dropId, reason))

    activeDrop = nil
    nextDropAt = os.time() + (Config.IntervalSeconds or 1800)

    for playerId in pairs(drop.openedBy or {}) do
        TriggerClientEvent('bg_airdrop:client:forceCloseStash', playerId, stashId)
    end

    TriggerClientEvent('bg_airdrop:client:remove', -1, dropId, reason)

    SetTimeout(250, function()
        removeInventory(stashId)
    end)
end

local function normaliseCoords(coords)
    if type(coords) ~= 'table' then return nil end

    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)

    if not x or not y or not z then return nil end

    return {
        x = x + 0.0,
        y = y + 0.0,
        z = z + 0.0
    }
end

local function markDropLanded(dropId, source, coords)
    if not activeDrop or activeDrop.id ~= dropId then return false end

    local now = os.time()

    if type(source) == 'number' and now < (activeDrop.landsAt - 2) then
        debugPrint(('Segnale atterraggio ignorato per %s: troppo presto.'):format(dropId))
        return false
    end

    local groundCoords = normaliseCoords(coords)
    if groundCoords then
        activeDrop.groundCoords = groundCoords
    elseif not activeDrop.groundCoords then
        activeDrop.groundCoords = activeDrop.coords
    end

    if activeDrop.landed then
        return true
    end

    activeDrop.landed = true
    activeDrop.landedAt = now
    activeDrop.expiresAt = now + math.max(1, Config.DeleteAfterLandingSeconds or 900)
    activeDrop.nextEmptyCheck = now + math.max(1, Config.EmptyCheckSeconds or 2)

    debugPrint(('Airdrop %s marcato a terra da %s. Scade alle %s.'):format(dropId, tostring(source or 'server'), activeDrop.expiresAt))

    beginExpiryTimer(dropId)
    return true
end

local function stashHasItems(stashId)
    local ok, items = pcall(function()
        return exports.ox_inventory:GetInventoryItems(stashId, false)
    end)

    if not ok or not items then
        return true
    end

    for _, item in pairs(items) do
        if item and item.name and (item.count or 0) > 0 then
            return true
        end
    end

    return false
end

local function createStash(coords)
    local items = generateLoot()

    local stashData = {
        label = Config.Inventory.Label,
        slots = Config.Inventory.Slots,
        maxWeight = Config.Inventory.MaxWeight,
        owner = false,
        items = items
    }

    if Config.Inventory.UseCoords then
        stashData.coords = coords
    end

    local stashId = exports.ox_inventory:CreateTemporaryStash(stashData)

    return stashId, items
end

local function startAirdrop(pointIndex)
    if activeDrop then
        return false, 'already_active'
    end

    if GetResourceState('ox_inventory') ~= 'started' then
        return false, 'ox_inventory_missing'
    end

    if GetResourceState('ox_target') ~= 'started' then
        return false, 'ox_target_missing'
    end

    local coords, label = pickDropPoint(pointIndex)
    if not coords then
        return false, 'no_points'
    end

    local now = os.time()
    local stashId, items = createStash(coords)

    if not stashId then
        return false, 'stash_failed'
    end

    activeDrop = {
        id = ('airdrop_%s_%s'):format(now, math.random(1000, 9999)),
        stashId = stashId,
        coords = coordsToTable(coords),
        label = label,
        heading = math.random(0, 359) + 0.0,
        createdAt = now,
        landsAt = now + (Config.Fall.DurationSeconds or 60),
        expiresAt = nil,
        landed = false,
        landedAt = nil,
        openedBy = {},
        itemCount = #items
    }

    debugPrint(('Airdrop creato: %s stash=%s lootSlots=%s point=%s'):format(activeDrop.id, activeDrop.stashId, activeDrop.itemCount, activeDrop.label))

    TriggerClientEvent('bg_airdrop:client:start', -1, publicDropData(activeDrop), 0)

    return true, activeDrop.id
end

local function canUseAdminCommand(source)
    if source == 0 then return true end

    if Config.Commands.Ace and IsPlayerAceAllowed(source, Config.Commands.Ace) then
        return true
    end

    local groups = Config.Groups or {}

    if framework == 'qbox' then
        for _, group in pairs(groups) do
            local ok, allowed = pcall(function()
                if exports.qbx_core.HasPermission then
                    return exports.qbx_core:HasPermission(source, group)
                end

                if exports.qbx_core.IsPlayerInGroup then
                    return exports.qbx_core:IsPlayerInGroup(source, group)
                end

                return false
            end)

            if ok and allowed then
                return true
            end
        end
    elseif framework == 'qbcore' then
        for _, group in pairs(groups) do
            local ok, allowed = pcall(function()
                if QBCore and QBCore.Functions and QBCore.Functions.HasPermission then
                    return QBCore.Functions.HasPermission(source, group)
                end

                if exports['qb-core'] and exports['qb-core'].HasPermission then
                    return exports['qb-core']:HasPermission(source, group)
                end

                return false
            end)

            if ok and allowed then
                return true
            end
        end
    elseif framework == 'esx' then
        local xPlayer = ESX and ESX.GetPlayerFromId and ESX.GetPlayerFromId(source)
        if xPlayer and xPlayer.getGroup then
            local playerGroup = xPlayer.getGroup()

            for _, group in pairs(groups) do
                if playerGroup == group then
                    return true
                end
            end
        end
    end

    return false
end

RegisterNetEvent('bg_airdrop:server:requestState', function()
    local source = source
    if not activeDrop then return end

    local elapsed = math.max(0, os.time() - activeDrop.createdAt)
    TriggerClientEvent('bg_airdrop:client:start', source, publicDropData(activeDrop), elapsed)
end)

RegisterNetEvent('bg_airdrop:server:landed', function(dropId, coords)
    markDropLanded(dropId, source, coords)
end)

RegisterNetEvent('bg_airdrop:server:openStash', function(dropId)
    local source = source

    if not activeDrop or activeDrop.id ~= dropId then
        notifyPlayer(source, 'Questo airdrop non è più disponibile.', 'error')
        return
    end

    if not activeDrop.landed then
        notifyPlayer(source, Config.Notifications.NotReady, 'error')
        return
    end

    local ped = GetPlayerPed(source)
    if not ped or ped == 0 then return end

    if Config.Target.ServerDistanceCheck ~= false then
        local playerCoords = GetEntityCoords(ped)
        local dropCoords = activeDrop.groundCoords or activeDrop.coords
        local maxDistance = (Config.Target.Distance or 3.0) + (Config.Target.ServerDistanceBuffer or 4.0)

        local dx = playerCoords.x - dropCoords.x
        local dy = playerCoords.y - dropCoords.y
        local distance = math.sqrt((dx * dx) + (dy * dy))

        if distance > maxDistance then
            debugPrint(('Player %s troppo lontano. Distanza %.2f / %.2f. Player: %.2f %.2f %.2f Drop: %.2f %.2f %.2f'):format(
                source,
                distance,
                maxDistance,
                playerCoords.x, playerCoords.y, playerCoords.z,
                dropCoords.x, dropCoords.y, dropCoords.z
            ))

            notifyPlayer(source, Config.Notifications.TooFar, 'error')
            return
        end
    end

    activeDrop.openedBy = activeDrop.openedBy or {}
    activeDrop.openedBy[source] = true

    TriggerClientEvent('bg_airdrop:client:openStash', source, activeDrop.stashId)
end)

AddEventHandler('playerDropped', function()
    if activeDrop and activeDrop.openedBy then
        activeDrop.openedBy[source] = nil
    end
end)

if Config.Commands.Enabled then
    RegisterCommand(Config.Commands.Start, function(source, args)
        if not canUseAdminCommand(source) then
            notifyPlayer(source, 'Non hai il permesso per usare questo comando.', 'error')
            return
        end

        local ok, result = startAirdrop(args[1])
        if not ok then
            local message = result == 'already_active' and Config.Notifications.AlreadyActive or ('Errore avvio airdrop: %s'):format(result)
            notifyPlayer(source, message, 'error')
            return
        end

        notifyPlayer(source, ('Airdrop avviato: %s'):format(result), 'success')
    end, false)

    RegisterCommand(Config.Commands.Cancel, function(source)
        if not canUseAdminCommand(source) then
            notifyPlayer(source, 'Non hai il permesso per usare questo comando.', 'error')
            return
        end

        if not activeDrop then
            notifyPlayer(source, 'Nessun airdrop attivo.', 'error')
            return
        end

        finishDrop('cancelled')
        notifyPlayer(source, 'Airdrop cancellato.', 'success')
    end, false)
end

exports('IsAirdropActive', function()
    return activeDrop ~= nil
end)

exports('StartAirdrop', function(pointIndex)
    return startAirdrop(pointIndex)
end)

exports('CancelAirdrop', function()
    if not activeDrop then return false end
    finishDrop('cancelled')
    return true
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if activeDrop and activeDrop.stashId then
        removeInventory(activeDrop.stashId)
    end
end)

CreateThread(function()
    math.randomseed(os.time())
    framework = detectFramework()
    print(('[bg_airdrop] Framework rilevato: %s'):format(framework))

    nextDropAt = os.time() + (Config.FirstDropDelaySeconds or 60)

    while true do
        Wait(1000)

        if activeDrop then
            local now = os.time()

            if not activeDrop.landed and now >= activeDrop.landsAt then
                markDropLanded(activeDrop.id, 'server_fallback')
            end

            if activeDrop and activeDrop.expiresAt and now >= activeDrop.expiresAt then
                finishDrop('expired')
            elseif activeDrop and activeDrop.landed then
                local checkEvery = math.max(1, Config.EmptyCheckSeconds or 2)
                if not activeDrop.nextEmptyCheck or now >= activeDrop.nextEmptyCheck then
                    activeDrop.nextEmptyCheck = now + checkEvery

                    if not stashHasItems(activeDrop.stashId) then
                        finishDrop('looted')
                    end
                end
            end
        else
            local now = os.time()
            if Config.Enabled and now >= nextDropAt then
                local ok, reason = startAirdrop()
                if not ok then
                    debugPrint(('Airdrop non avviato: %s'):format(tostring(reason)))
                    nextDropAt = os.time() + 60
                end
            end
        end
    end
end)
