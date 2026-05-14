Config = {}

-- Framework support: 'auto', 'esx', 'qbcore', 'qbox', 'standalone'
Config.Framework = 'auto'

Config.Debug = false
Config.Enabled = true

-- Timer in secondi.
Config.FirstDropDelaySeconds = 60          -- primo airdrop dopo l'avvio della risorsa in secondi
Config.IntervalSeconds = 30 * 60          -- tempo tra un airdrop concluso e il prossimo in secondi
Config.DeleteAfterLandingSeconds = 5 * 60  -- tempo massimo a terra prima della cancellazione automatica in secondi
Config.EmptyCheckSeconds = 2              -- ogni quanti secondi controllare se lo stash è stato svuotato

-- Caduta.
Config.Fall = {
    SpawnHeight = 220.0,                  -- altezza sopra il punto scelto
    DurationSeconds = 60,                 -- tempo di discesa dal cielo a terra
    RotateWhileFalling = true,
    RotationSpeed = 0.35,                 -- gradi per frame circa
    UseGroundDetection = true,            -- prova a correggere Z lato client
    -- Per i custom prop è meglio non usare PlaceObjectOnGroundProperly: può piazzare il box mezzo sotto terra.
    -- UseModelDimensions calcola la Z usando il fondo reale del modello.
    UseModelDimensions = true,
    BoxZOffset = 0.03,                   -- alza/abbassa leggermente il box: prova 0.05 / 0.10 se serve
    BoxSpawnZOffset = 1.0,               -- usato solo se UseModelDimensions = false
    PlaceBoxOnGround = false,            -- usato solo se UseModelDimensions = false
}

-- Modelli inclusi nello stream dello zip.
Config.Props = {
    Falling = 'airdrop',
    Box = 'airdrop_box'
}

-- Punti randomici. Aggiungi/rimuovi coordinate qui.
-- Z deve essere vicina al terreno; se UseGroundDetection è true il client prova a correggerla.
Config.DropPoints = {
    { coords = vector3(1698.82, 3253.21, 41.10), label = 'Sandy Shores' },
    { coords = vector3(-2169.4517, 3209.5852, 32.8102), label = 'Fort Zancudo' },
    { coords = vector3(2546.4583, -383.1520, 92.9928), label = 'Tataviam' },
    { coords = vector3(-1187.83, -1743.26, 4.04), label = 'Vespucci' }
}

-- ox_target.
Config.Target = {
    Label = 'Apri airdrop',
    Icon = 'fa-solid fa-box-open',
    Distance = 3.0,
    Type = 'zone',                       -- 'zone' consigliato: non dipende dalla collisione del prop. Puoi usare 'entity'.
    ZoneRadius = 2.2,
    ZoneZOffset = 0.0,
    ServerDistanceCheck = true,
    ServerDistanceBuffer = 6.0
}

-- ox_inventory stash.
Config.Inventory = {
    Label = 'Airdrop',
    Slots = 20,
    MaxWeight = 120000,
    UseCoords = false                    -- il controllo distanza lo fa lo script usando le coordinate reali del box
}

-- Loot randomico.
-- weight/chance è un peso relativo, non una percentuale obbligatoria.
-- metadata è opzionale e può essere una table ox_inventory valida.
Config.Loot = {
    Rolls = { min = 5, max = 10 },
    AllowDuplicates = true,
    SkipInvalidItems = true,
    Items = {
        { name = 'water', min = 2, max = 6, weight = 30 },
        { name = 'burger', min = 2, max = 5, weight = 30 },
        { name = 'bandage', min = 1, max = 4, weight = 22 },
        { name = 'lockpick', min = 1, max = 3, weight = 15 },
        { name = 'ammo-9', min = 12, max = 36, weight = 10 },
        { name = 'WEAPON_PISTOL', min = 1, max = 1, weight = 3, metadata = { durability = 100 } }
    }
}

-- Fumogeno colorato applicato al prop a terra.
-- Puoi cambiare colore con valori 0.0 - 1.0.
Config.Smoke = {
    Enabled = true,
    Asset = 'core',
    Effect = 'exp_grd_flare',
    Scale = 1.8,
    Offset = vector3(0.0, 0.0, 1.15),
    Color = { r = 0.20, g = 0.55, b = 1.00 },
    Alpha = 0.85
}

Config.Blip = {
    Enabled = true,
    Sprite = 478,
    Color = 1,
    Scale = 0.85,
    Name = 'Airdrop'
}

Config.Notifications = {
    Enabled = true,
    Start = 'Un airdrop sta scendendo dal cielo.',
    Landed = 'L\'airdrop è arrivato a terra.',
    Looted = 'L\'airdrop è stato svuotato.',
    Expired = 'L\'airdrop è scaduto.',
    AlreadyActive = 'C\'è già un airdrop in corso.',
    NotReady = 'L\'airdrop non è ancora arrivato a terra.',
    TooFar = 'Sei troppo lontano dall\'airdrop.'
}

-- Comandi opzionali admin/console.
-- Permesso ACE consigliato nel server.cfg: add_ace group.admin bg_airdrop.admin allow
Config.Commands = {
    Enabled = true,
    Start = 'airdrop_start',
    Cancel = 'airdrop_cancel',
    Ace = 'bg_airdrop.admin'
}

Config.Groups = {
    'admin',
    'mod',
    'superadmin',
    'god'
}
