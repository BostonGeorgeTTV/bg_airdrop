# bg_airdrop

https://www.youtube.com/watch?v=CF_teO4QrbU

<img width="1672" height="941" alt="bgairdrop" src="https://github.com/user-attachments/assets/18584f3d-29e2-4fdd-9eb7-749c0fd21967" />


Risorsa FiveM per airdrop configurabili con prop custom, ox_target e ox_inventory.

## Funzioni incluse

- Spawn automatico ogni `Config.IntervalSeconds`.
- Nessun nuovo airdrop se ne esiste già uno attivo.
- Punti random configurabili in `Config.DropPoints`.
- Prop `airdrop` spawnato in cielo e animato in caduta lenta.
- A terra il prop viene sostituito con `airdrop_box`.
- Fumogeno colorato con particle effect configurabile.
- Target `ox_target` tramite sphere zone di default, così l’interazione non dipende dalla collisione del prop. Puoi impostare `Config.Target.Type = 'entity'` se vuoi usare il target diretto sull’entità.
- Apertura stash `ox_inventory` con loot randomico configurabile.
- Rimozione automatica quando lo stash è vuoto.
- Rimozione automatica dopo `Config.DeleteAfterLandingSeconds` dal momento in cui il box tocca terra, anche se qualcuno ha già aperto lo stash.
- Compatibile con ESX, QBCore, Qbox e standalone; lo script auto-rileva il framework ma dipende da ox_lib, ox_target e ox_inventory.

## Installazione

1. Estrai la cartella `bg_airdrop` dentro `resources`.
2. Assicurati che queste risorse partano prima:

```cfg
ensure ox_lib
ensure ox_inventory
ensure ox_target
ensure bg_airdrop
```

3. Se vuoi usare i comandi admin, aggiungi un permesso ACE:

```cfg
add_ace group.admin bg_airdrop.admin allow
```

## Configurazione rapida

Apri `config.lua` e modifica:

- `Config.IntervalSeconds`: ogni quanto può partire un nuovo airdrop.
- `Config.FirstDropDelaySeconds`: dopo quanto parte il primo airdrop all'avvio.
- `Config.DeleteAfterLandingSeconds`: durata massima a terra.
- `Config.DropPoints`: coordinate randomiche.
- `Config.Loot.Items`: item, quantità e peso di estrazione.
- `Config.Smoke.Color`: colore fumogeno RGB da 0.0 a 1.0.
- `Config.Fall.DurationSeconds`: durata della caduta.
- `Config.Fall.SpawnHeight`: altezza iniziale.
- `Config.Target.Type`: `zone` consigliato, `entity` opzionale.
- `Config.Inventory.UseCoords`: lascia `false` se usi il controllo distanza interno dello script.

## Comandi

- `/airdrop_start` avvia manualmente un airdrop. Puoi passare l'indice del punto: `/airdrop_start 2`.
- `/airdrop_cancel` cancella quello attivo.

I comandi funzionano da console e per player con ACE `bg_airdrop.admin`.

## Export server

```lua
exports.bg_airdrop:IsAirdropActive()
exports.bg_airdrop:StartAirdrop(pointIndex)
exports.bg_airdrop:CancelAirdrop()
```

## Nota sugli item

Gli item configurati in `Config.Loot.Items` devono esistere in `ox_inventory/data/items.lua`, altrimenti vengono saltati se `Config.Loot.SkipInvalidItems = true`.

## Fix cleanup atterraggio

La scadenza viene ora avviata quando il client segnala al server che il box è stato realmente spawnato a terra. Se nessun client segnala l'atterraggio, il server usa comunque un fallback basato su `Config.Fall.DurationSeconds`. Quando la scadenza arriva, lo stash viene chiuso forzatamente per chi lo aveva aperto, il prop viene rimosso e l'inventario temporaneo viene cancellato.


## Fix distanza, target e cleanup

Il client invia al server le coordinate reali del `airdrop_box` quando viene spawnato a terra. Il server usa quelle coordinate per il controllo distanza in 2D, evitando errori causati dalla Z del prop o da `PlaceObjectOnGroundProperly`.

Lo stash non usa più le coordinate interne di ox_inventory di default (`Config.Inventory.UseCoords = false`), perché il controllo distanza viene già fatto dal server con le coordinate effettive della cassa. Questo evita blocchi “troppo lontano” quando la Z finale del prop cambia.

Il target usa `addSphereZone` di default: anche se la collisione del modello custom non viene letta bene da ox_target/raycast, il player può comunque interagire con l’airdrop.
