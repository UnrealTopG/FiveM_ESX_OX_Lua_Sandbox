# FiveM ESX + OX Lua Sandbox

A **local, deterministic Lua test environment** for writing and testing FiveM resources that use **ESX Legacy**, **ox_lib**, **ox_inventory**, and a small **oxmysql** mock — without starting FXServer. Inspired by [LuaGround](https://github.com/AndyBodnar/LuaGround), which primarily targets QBCore. This is a new ESX/OX-oriented implementation, **not** a complete port of LuaGround's native library or its desktop application.

> **Safety:** This is a development test harness, **not a security sandbox**. `dofile` executes trusted Lua with your OS permissions. Never run untrusted scripts in it. It does not replace tests on an actual FiveM server.

## Requirements

- Lua **5.3+** (recommended: Lua 5.4). No FiveM installation and no runtime dependencies.
- Windows: install Lua 5.4, then run `lua tests/run.lua` or `lua54 tests/run.lua`, depending on the executable name.
- Linux: `sudo apt install lua5.4 && lua5.4 tests/run.lua`.

## Quick start

```lua
local Sandbox = dofile('init.lua')
local player = Sandbox.createPlayer(1, {
    name = 'Test Player',
    job = { name = 'police', grade = 2 },
    accounts = { money = 500, bank = 5000 },
})

-- ESX Legacy account and job APIs
assert(ESX.GetPlayerFromId(1) == player)
assert(player.getJob().name == 'police')
player.addAccountMoney('bank', 250)

-- ox_inventory export (stateful, with slots and metadata)
assert(exports.ox_inventory:AddItem(1, 'water', 3, { quality = 100 }))
assert(exports.ox_inventory:Search(1, 'count', 'water') == 3)

-- Simulate a client calling an ox_lib server callback
Sandbox.setSide('server')
lib.callback.register('demo:getBalance', function(source)
    return ESX.GetPlayerFromId(source).getAccount('bank').money
end)
Sandbox.setSide('client', 1)
assert(lib.callback.await('demo:getBalance', false) == 5250)
```

### Loading existing resource files

Use `Sandbox.loadResource(path, side, resourceName)` for each `server.lua` and `client.lua` file, then set the active client player. `source` is set while dispatching server events. An `fxmanifest.lua` is **not automatically parsed**; the test author controls load order.

```lua
local S = dofile('init.lua')
S.createPlayer(11, { accounts = { money = 0, bank = 100 } })
S.loadResource('examples/basic_resource.lua', 'server', 'demo')
S.loadResource('examples/basic_resource.lua', 'client', 'demo')
S.setSide('client', 11)
TriggerServerEvent('demo:buyWater')
assert(exports.ox_inventory:Search('count', 'water') == 1)
```

## Implemented mock API surface

| Area | Implemented |
|------|-------------|
| **ESX** | `exports.es_extended:getSharedObject()`, `GetPlayerFromId`, `GetPlayerFromIdentifier`, `GetPlayers`, `GetExtendedPlayers`, `GetJobs`, `RegisterServerCallback`, `TriggerServerCallback`, `AwaitServerCallback`, `RegisterUsableItem` |
| **xPlayer** | identity, name, job/grade, group, accounts, cash, metadata, coords, `getInventoryItem`, `addInventoryItem`, `removeInventoryItem`, `setInventoryItem`, `hasItem`, `canCarryItem`, notifications |
| **ox_inventory** | item definitions, player inventory, stashes, slots, weight limits, `AddItem`, `RemoveItem`, `Search`, `GetItem`, `GetItemCount`, `GetInventoryItems`, `GetSlot*`, `CanCarryItem`, metadata, durability, `ClearInventory`, `SetMaxWeight`, `RegisterStash` |
| **ox_lib** | server/client callbacks, notifications, progress bar/circle, skill checks, input/alert dialogs, contexts/menus/radials/text UI, math/string/table helpers, command registration |
| **FiveM** | side-specific events, net events, `source`, export access, deterministic `CreateThread`/`Wait`/`SetTimeout` scheduler, vectors, selected player/entity functions, convars and resource state |
| **oxmysql** | `MySQL.query/single/scalar/update/insert/prepare/transaction.await`, callback forms, and basic `Async`/`Sync` forms with explicitly configured query results |

### Configure test fixtures

```lua
local S = dofile('init.lua')
S.defineItem('diamond', {label='Diamond',weight=250,stack=true})
S.defineJob('mechanic', {label='Mechanic', grades={['0']={name='trainee',salary=100}}})
S.createPlayer(5, {accounts={money=0,bank=1000}, maxWeight=1500, slots=10})
S.setReturn('lib:progressCircle', false)             -- simulate cancellation
S.setReturn('lib:inputDialog', {'example answer'})   -- mock UI input
S.setReturn('GetEntityCoords:1005', vector3(1,2,3))
S.setSQL('SELECT * FROM users WHERE id = ?', {{id=5,name='Test'}})
local users = MySQL.query.await('SELECT * FROM users WHERE id = ?', {5})
assert(users[1].name == 'Test')
```

`S.state` exposes recorded `events`, `notices`, `progress`, `dbCalls`, inventories, and registered commands. `S.reset()` clears the scenario. `S.advance(milliseconds)` explicitly advances the scheduled tasks; a 10,000-step guard prevents accidental infinite timer loops. No actual time delays or networking occur.

## Run tests

```bash
lua tests/run.lua
lua tests/example_resource_test.lua
```

The automated suite covers player state, money/inventory synchronization, jobs, items and metadata, weight limits, callback direction, events, time scheduling, mocks, and isolation. It also includes a small purchase resource tested from client to server to client.

## Deliberate limitations

- This package **does not provide LuaGround's thousands of native stubs, QBCore support, Electron UI, or full FXServer runtime behavior**. Unsupported natives fail rather than silently faking success; model their return values and use local resource adapters as needed.
- No physical world, actual game entities, OneSync networking, SQL database, inventory UI, Discord, or CFX permission enforcement.
- ox_lib callback `await` behavior is synchronous in this local simulation; actual asynchronous coroutine/network latency behavior must be tested in FiveM.
- ox_lib zones are recorded stubs, not a spatial engine. UI methods log interactions instead of rendering NUI.
- This covers common APIs, not every API in ESX/ox_lib/ox_inventory. Test important permission, anti-dupe, inventory capacity, and race-condition paths on a real server before deployment.

## Attribution

Inspired by [AndyBodnar/LuaGround](https://github.com/AndyBodnar/LuaGround) (MIT license, Black Mesa RP Community, 2026). The source code here is an independently written ESX/OX-focused mock implementation; no LuaGround-generated native files are bundled. See [`CREDITS.md`](CREDITS.md).

License: MIT (see `LICENSE`).
