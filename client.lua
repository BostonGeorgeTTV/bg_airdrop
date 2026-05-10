local currentDrop = nil
local openCooldown = false

local function debugPrint(...)
    if Config.Debug then
        print('[bg_airdrop:client]', ...)
    end
end

local function notify(data)
    if not Config.Notifications.Enabled then return end

    if lib and lib.notify then
        lib.notify(data)
    else
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(data.description or data.title or 'Airdrop')
        EndTextCommandThefeedPostTicker(false, false)
    end
end

local function toVec3(coords)
    return vector3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end

local function requestModel(model)
    local hash = type(model) == 'number' and model or joaat(model)

    if not IsModelInCdimage(hash) then
        print(('[bg_airdrop] Modello non trovato: %s'):format(tostring(model)))
        return nil
    end

    RequestModel(hash)

    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        Wait(10)

        if GetGameTimer() > timeout then
            print(('[bg_airdrop] Timeout caricamento modello: %s'):format(tostring(model)))
            return nil
        end
    end

    return hash
end

local function requestPtfx(asset)
    RequestNamedPtfxAsset(asset)

    local timeout = GetGameTimer() + 10000
    while not HasNamedPtfxAssetLoaded(asset) do
        Wait(10)

        if GetGameTimer() > timeout then
            print(('[bg_airdrop] Timeout caricamento particle asset: %s'):format(asset))
            return false
        end
    end

    return true
end

local function resolveGroundCoords(coords)
    if not Config.Fall.UseGroundDetection then
        return coords
    end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    for _ = 1, 35 do
        local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 80.0, false)
        if found then
            return vector3(coords.x, coords.y, groundZ)
        end

        Wait(50)
    end

    return coords
end

local function removeLocalDrop()
    if not currentDrop then return end

    if currentDrop.target then
        if currentDrop.target.type == 'zone' and currentDrop.target.id then
            pcall(function()
                exports.ox_target:removeZone(currentDrop.target.id)
            end)
        elseif currentDrop.target.type == 'entity' and currentDrop.boxObject and DoesEntityExist(currentDrop.boxObject) then
            pcall(function()
                exports.ox_target:removeLocalEntity(currentDrop.boxObject, currentDrop.target.name)
            end)
        end
    end

    if currentDrop.boxObject and DoesEntityExist(currentDrop.boxObject) then
        SetEntityAsMissionEntity(currentDrop.boxObject, true, true)
        DeleteEntity(currentDrop.boxObject)
    end

    if currentDrop.airObject and DoesEntityExist(currentDrop.airObject) then
        SetEntityAsMissionEntity(currentDrop.airObject, true, true)
        DeleteEntity(currentDrop.airObject)
    end

    if currentDrop.smoke then
        StopParticleFxLooped(currentDrop.smoke, false)
    end

    if currentDrop.blip and DoesBlipExist(currentDrop.blip) then
        RemoveBlip(currentDrop.blip)
    end

    currentDrop = nil
end

local function addDropBlip(coords)
    if not Config.Blip.Enabled then return nil end

    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, Config.Blip.Sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, Config.Blip.Scale)
    SetBlipColour(blip, Config.Blip.Color)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(Config.Blip.Name)
    EndTextCommandSetBlipName(blip)

    return blip
end

local function startSmoke(coords)
    if not Config.Smoke.Enabled then return nil end
    if not requestPtfx(Config.Smoke.Asset) then return nil end

    local offset = Config.Smoke.Offset or vector3(0.0, 0.0, 1.0)
    UseParticleFxAssetNextCall(Config.Smoke.Asset)

    local fx = StartParticleFxLoopedAtCoord(
        Config.Smoke.Effect,
        coords.x + offset.x,
        coords.y + offset.y,
        coords.z + offset.z,
        0.0, 0.0, 0.0,
        Config.Smoke.Scale,
        false, false, false, false
    )

    if fx then
        SetParticleFxLoopedColour(fx, Config.Smoke.Color.r, Config.Smoke.Color.g, Config.Smoke.Color.b, false)
        SetParticleFxLoopedAlpha(fx, Config.Smoke.Alpha)
    end

    return fx
end

local function addTarget(entity, dropId, coords)
    local targetName = ('bg_airdrop_open_%s'):format(dropId)

    local option = {
        name = targetName,
        icon = Config.Target.Icon,
        label = Config.Target.Label,
        distance = Config.Target.Distance or 3.0,
        onSelect = function()
            if openCooldown then return end

            openCooldown = true
            TriggerServerEvent('bg_airdrop:server:openStash', dropId)

            SetTimeout(1000, function()
                openCooldown = false
            end)
        end
    }

    local targetType = Config.Target.Type or 'zone'

    if targetType == 'entity' then
        local ok = pcall(function()
            exports.ox_target:addLocalEntity(entity, { option })
        end)

        if ok then
            return { type = 'entity', name = targetName }
        end

        debugPrint(('addLocalEntity fallito per %s, uso sphere zone fallback.'):format(dropId))
    end

    local zoneOffset = Config.Target.ZoneZOffset or 0.0
    local zoneCoords = vector3(coords.x, coords.y, coords.z + zoneOffset)

    local ok, zoneId = pcall(function()
        return exports.ox_target:addSphereZone({
            coords = zoneCoords,
            radius = Config.Target.ZoneRadius or 2.0,
            debug = Config.Debug or false,
            options = { option }
        })
    end)

    if ok and zoneId then
        return { type = 'zone', id = zoneId, name = targetName }
    end

    print(('[bg_airdrop] Errore: impossibile creare il target per %s'):format(dropId))
    return nil
end

local function spawnGroundBox(drop, coords)
    local boxModel = requestModel(Config.Props.Box)
    if not boxModel then return end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    local timeout = GetGameTimer() + 5000
    while GetGameTimer() < timeout do
        local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 50.0, false)
        if found then
            coords = vector3(coords.x, coords.y, groundZ)
            break
        end

        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(50)
    end

    local spawnZ

    if Config.Fall.UseModelDimensions ~= false then
        local minDim, maxDim = GetModelDimensions(boxModel)
        local bottomOffset = 0.0

        if minDim and minDim.z and minDim.z < 0.0 then
            bottomOffset = -minDim.z
        end

        spawnZ = coords.z + bottomOffset + (Config.Fall.BoxZOffset or 0.03)

        debugPrint(('Box placement model dimensions. groundZ: %.3f minZ: %.3f offset: %.3f finalZ: %.3f'):format(
            coords.z,
            minDim and minDim.z or 0.0,
            bottomOffset,
            spawnZ
        ))
    else
        spawnZ = coords.z + (Config.Fall.BoxSpawnZOffset or 1.0)
    end

    local box = CreateObjectNoOffset(boxModel, coords.x, coords.y, spawnZ, false, false, false)
    if not box or box == 0 then return end

    SetEntityAsMissionEntity(box, true, true)
    SetEntityHeading(box, drop.heading or 0.0)
    SetEntityVisible(box, true, false)
    SetEntityCollision(box, true, true)
    SetEntityLoadCollisionFlag(box, true)

    timeout = GetGameTimer() + 5000
    while DoesEntityExist(box) and not HasCollisionLoadedAroundEntity(box) and GetGameTimer() < timeout do
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        Wait(50)
    end

    if Config.Fall.UseModelDimensions == false and Config.Fall.PlaceBoxOnGround then
        Wait(150)
        PlaceObjectOnGroundProperly(box)
        Wait(250)

        coords = GetEntityCoords(box)

        if Config.Fall.BoxZOffset and Config.Fall.BoxZOffset ~= 0.0 then
            SetEntityCoordsNoOffset(
                box,
                coords.x,
                coords.y,
                coords.z + Config.Fall.BoxZOffset,
                false,
                false,
                false
            )
            Wait(100)
        end
    end

    SetEntityCollision(box, true, true)
    SetEntityLoadCollisionFlag(box, true)
    FreezeEntityPosition(box, true)

    local finalCoords = GetEntityCoords(box)

    currentDrop.boxObject = box
    currentDrop.boxCoords = finalCoords
    currentDrop.smoke = startSmoke(finalCoords)
    currentDrop.target = addTarget(box, drop.id, finalCoords)

    TriggerServerEvent('bg_airdrop:server:landed', drop.id, {
        x = finalCoords.x,
        y = finalCoords.y,
        z = finalCoords.z
    })

    SetModelAsNoLongerNeeded(boxModel)

    notify({ type = 'success', title = 'Airdrop', description = Config.Notifications.Landed })
end

local function animateFallingDrop(drop, groundCoords, elapsedSeconds)
    local fallModel = requestModel(Config.Props.Falling)
    if not fallModel then
        spawnGroundBox(drop, groundCoords)
        return
    end

    local spawnHeight = Config.Fall.SpawnHeight + 0.0
    local durationMs = math.max(1000, (Config.Fall.DurationSeconds or 60) * 1000)
    local initialElapsedMs = math.max(0, (elapsedSeconds or 0) * 1000)
    local startZ = groundCoords.z + spawnHeight
    local progress = math.min(initialElapsedMs / durationMs, 1.0)
    local currentZ = startZ - (spawnHeight * progress)

    local object = CreateObject(fallModel, groundCoords.x, groundCoords.y, currentZ, false, false, false)
    if not object or object == 0 then
        spawnGroundBox(drop, groundCoords)
        return
    end

    SetEntityHeading(object, drop.heading or 0.0)
    FreezeEntityPosition(object, true)
    SetEntityCollision(object, false, false)
    SetEntityAsMissionEntity(object, true, true)

    currentDrop.airObject = object
    SetModelAsNoLongerNeeded(fallModel)

    local startedAt = GetGameTimer()
    local baseHeading = drop.heading or 0.0

    CreateThread(function()
        while currentDrop and currentDrop.id == drop.id and DoesEntityExist(object) do
            local runtimeElapsed = initialElapsedMs + (GetGameTimer() - startedAt)
            local pct = math.min(runtimeElapsed / durationMs, 1.0)
            local z = startZ - (spawnHeight * pct)

            if Config.Fall.RotateWhileFalling then
                baseHeading = (baseHeading + Config.Fall.RotationSpeed) % 360.0
                SetEntityHeading(object, baseHeading)
            end

            SetEntityCoordsNoOffset(object, groundCoords.x, groundCoords.y, z, false, false, false)

            if pct >= 1.0 then
                SetEntityAsMissionEntity(object, true, true)
                DeleteEntity(object)
                currentDrop.airObject = nil
                spawnGroundBox(drop, groundCoords)
                break
            end

            Wait(25)
        end
    end)
end

RegisterNetEvent('bg_airdrop:client:start', function(drop, elapsedSeconds)
    if currentDrop and currentDrop.id == drop.id then return end

    removeLocalDrop()

    local coords
    if drop.groundCoords then
        coords = toVec3(drop.groundCoords)
    else
        coords = resolveGroundCoords(toVec3(drop.coords))
    end

    currentDrop = {
        id = drop.id,
        stashId = drop.stashId,
        blip = addDropBlip(coords)
    }

    debugPrint(('Airdrop %s ricevuto. Elapsed: %s'):format(drop.id, tostring(elapsedSeconds)))
    notify({ type = 'inform', title = 'Airdrop', description = Config.Notifications.Start })

    local duration = Config.Fall.DurationSeconds or 60
    if drop.landed or (elapsedSeconds or 0) >= duration then
        spawnGroundBox(drop, coords)
    else
        animateFallingDrop(drop, coords, elapsedSeconds or 0)
    end
end)

RegisterNetEvent('bg_airdrop:client:remove', function(dropId, reason)
    if not currentDrop or currentDrop.id ~= dropId then return end

    removeLocalDrop()

    if reason == 'looted' then
        notify({ type = 'success', title = 'Airdrop', description = Config.Notifications.Looted })
    elseif reason == 'expired' then
        notify({ type = 'error', title = 'Airdrop', description = Config.Notifications.Expired })
    end
end)

RegisterNetEvent('bg_airdrop:client:openStash', function(stashId)
    if currentDrop then
        currentDrop.stashId = stashId
    end

    exports.ox_inventory:openInventory('stash', stashId)
end)

RegisterNetEvent('bg_airdrop:client:forceCloseStash', function(stashId)
    if not currentDrop or currentDrop.stashId ~= stashId then return end

    pcall(function()
        exports.ox_inventory:closeInventory()
    end)
end)

RegisterNetEvent('bg_airdrop:client:notify', function(data)
    notify(data)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    removeLocalDrop()
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('bg_airdrop:server:requestState')
end)
