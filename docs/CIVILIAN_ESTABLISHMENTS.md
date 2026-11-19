# Adventurers Guild, Tavern and private lodging

The public buildings are part of the existing city, with open front entrances.
The Guild occupies world `(-32, 0, -160)` (`LAT 010N / LON 002W`), and the Tavern
occupies `(-16, 0, -224)` (`LAT 014N / LON 001W`). Their original scenery lots
are reserved so no generated skyscraper blocks the interiors. The Guild has
ground-floor reception, a crystal exchange, contract board, common tables,
physical stairs and three distinct upstairs private-room doors. The independent
Tavern has a bar, shelves, stools, tables and chairs. Both use black surfaces,
cyan wireframes and restrained colored window accents.

## Playing

- Walk through either public entrance without a scene transition. Use **G /
  tap RT** at the nearest service or usable furniture. Chairs take priority
  over a more distant adjacent computer/table. Occupied seats remain occupied.
- At reception, choose **Sell monster crystals** to sell one unit at a time.
  The actual crystal enters Guild stock, and existing Guild coins enter your
  wallet. Your wallet is also shown in inventory.
- Rent one of three rooms for **30 coins / 60 real minutes**. Renewing the same
  room adds time. An active rental cannot be switched to another room. Use its
  upstairs door to enter, and the room's door to return to that exact hallway.
- The storage computer offers **Deposit** and **Withdraw**. Select a stack to
  transfer it in full. Equipment transfers preserve the unique item identity
  and properties; storing equipped gear removes its equipment-slot reference.
  Existing capacity, stacking and transfer policies apply to both inventories.
- Storage belongs to that specific room and survives unloading and rental
  expiry. Renew that room to retrieve its contents after expiry.
- Use a chair to sit. **Move / jump / G / tap RT** stands up using existing
  safe-exit handling. Use the bed menu for Rest or Sleep; movement, jump or
  interaction ends the resting pose.
- Tavern purchases enter your actual inventory. Consume them from the bar or
  table menu, or choose **Eat / Drink** when inspecting them in inventory.
  One timed recovery effect can run at a time. Full-health consumption is refused.
- Menus accept **D-pad / stick / arrows / W/S**, **A / Enter** to choose,
  **B / Escape** to go back, and **Left / Right** for pages. **PgUp / PgDn**
  scroll details; **F5** saves. **Select / View** switches to inventory;
  **Start** opens the system menu. The world keeps running.

| Item/action | Price | Duration | Effect |
| --- | ---: | ---: | --- |
| Private room rental | 30 coins | 60 real minutes | Access to one room |
| Electron Meal | 8 coins | 2 seconds | Recover 60 HP |
| Electron Draught | 12 coins | 3 seconds | Recover 120 HP |
| Bed Rest | Included | 5 seconds | Recover 60 HP |
| Bed Sleep | Included | 10 seconds | Recover 180 HP |

Guild purchase prices are Common crystal 12, Uncommon 30, Rare 75 and
Apep-Lorai Catalyst 180 coins. A sale fails without sufficient Guild funds.
The initial Guild treasury is 100, so selling a catalyst requires later rental
income or other authorized transfers first. Food and rental settings are
exported on their service nodes; item definitions supply the catalog entries.

## Coins and persistence

The original opening blessing covers the 100 city residents, receptionist,
bartender and two seated adventurers. The Code Form civilization extends that
census to regional pedestrians and drivers, each receiving 100 coins once.
The receptionist and bartender transfer their own opening shares
into their respective business treasuries. Visiting players start at zero.
The opening census uses stable profile IDs, independent of deferred NPC-body
construction. Loading a checkpoint restores its ledger without reissuing coins.

Rent, crystal sales and food purchases transfer existing coins. Insufficient
funds/capacity, invalid ownership and reentrant transactions fail without moving
items or money. A bounded transaction journal and replayable audit base record
issuance and transfers; validation checks the total against issued supply.
The shared civilian clock now calls `bless_cycle()` every 30 game days. One real
hour is one game day; each active Code Form receives the same 100-coin payment.
See [Code Form civilization](CODE_FORM_CIVILIZATION.md) for lifetime, replacement,
transaction XP, currency destruction and migration rules.

The single-player checkpoint stores the ledger, rental deadline, all three
room inventories and Guild stock alongside owned inventory and world drops.
Validation rejects duplicate identities across these stores and rejects
inconsistent ledgers. Failed loads restore the prior inventory and ledger.
Older checkpoints without civilian data receive the initial civilian state.

Room geometry is disposable; authority inventories and location IDs are not.
Only the occupied private bedroom has rendered geometry. Dormant room worlds
retain 28 static collision boxes each, generated from the same cached recipe
as their furnishings. This supports saved items dropped on a bed or desk even
on a cold restart, without creating rendered bedrooms. Leaving removes room
meshes, labels, lights and seat registrations while preserving real pickups.

Death in a room uses the existing equipment-loss sequence. The default respawn
returns to the public Guild hallway, while either existing selected Respawn
Glyph can still take precedence. Room losses remain tracked in that room.
Permanent respawn glyphs cannot be placed in rented accommodation. Loading an
expired room checkpoint returns to the hallway and retains its storage/drops.

## Reused systems and components

- `WorldRegions`, `WorldChunk`, `Neon`, cached primitive shapes and window
  accents build the two batched public structures and the private bedroom.
- `DungeonTravel`, `EnvironmentManifest` and independent `World3D` contexts
  perform the existing deconstruction/reconstruction transition. The same
  player, camera, combat, movement and inventory services survive travel.
- `Inventory`, `ItemInstance`, `ItemCatalog`, `InventoryStore` and
  `InventorySession` provide real item ownership, effects and checkpointing.
- `WorldActions` supplies seat claiming, attachment, poses and safe exits.
  Cached seats and vehicles are scoped to the player's physical world.
- `ResidentVisual` supplies inexpensive batched keeper/adventurer rigs.
- New `CivilianEstablishments` supplies reusable public furniture and service
  anchors. `PrivateRoomInterior` separates rendered furnishing from collision.
  `CivilianEconomy` owns balances, rentals and persistent stores.
  `CivilianServices` binds proximity, dialogue, consumption and bed use.
  `CivilianMenu` supplies bounded pages with keyboard/controller navigation.

## Current boundaries

The contract board is a visible placeholder without active quests. Sleep is
configurable timed recovery; the civilian clock advances normally. Tables expose
consumption and reserve future food placement. The two seated adventurers
provide short conversations and occupy real seats. Their Code Form identities
now participate in lightweight goals, memories, relationships and economic
decisions; physical quest expeditions remain future work. Keepers retain static
service positions and lightweight idle gestures. This authority and private lodging
flow is enabled in single-player, matching the existing dungeon travel boundary.

No dynamic point lights or heavyweight libraries were added. Public architecture
uses immutable mesh batches; each bedroom exists visually only while occupied.
Economy work is event-driven, and the four nearby civilian rigs update at 10 Hz
with a distance gate. Native tests establish rendering and functional behavior,
not a new low-end hardware frame-rate guarantee.

## Verification

Run these Godot scripts with isolated `APPDATA` profiles. Native captures can
use the fixtures' `--capture` option where supported.

```powershell
& $Godot --headless --path . --fixed-fps 60 --script res://tests/civilian_economy.gd
& $Godot --headless --path . --fixed-fps 60 --script res://tests/civilian_persistence.gd
& $Godot --headless --path . --fixed-fps 60 --script res://tests/civilian_services_integration.gd
& $Godot --headless --path . --fixed-fps 60 --script res://tests/civilian_services_input.gd
& $Godot --headless --path . --fixed-fps 60 --script res://tests/civilian_menu.gd
& $Godot --headless --path . --fixed-fps 60 --script res://tests/establishment_architecture.gd
```

The fixtures cover public entry/stairs, denied and paid room access, transitions,
actual storage/commerce, input routing, world isolation, currency conservation,
capacity and rollback, duplicate rejection, cold/warm room saves, expiry, room
death recovery, sitting/resting/food and bounded visual architecture. Existing
dungeon, drawn Scribe/Paintbrush transitions, startup, inventory filters, respawn
glyphs, system-menu recovery, mounted poses and lost-gear guidance are regression
checks for the integration.

Verified on Godot 4.7.2:

| Fixture | Checks | Result |
| --- | ---: | --- |
| Civilian economy | 56 | Passed |
| Civilian persistence, including cold furniture drops | 53 | Passed |
| Services integration | 36 at each of 30/60/120 Hz | Passed |
| Service input routing | 21 | Passed |
| Service menu | 19 | Passed |
| Establishment architecture and stair traversal | 19 | Passed |
| Existing dungeon foundation | 92 | Passed |
| Drawn Scribe/Paintbrush dungeon travel | 68 | Passed |
| Dungeon enemy respawn | 32 | Passed |
| Inventory startup / integration / filters | 21 / 36 / 64 | Passed |
| Respawn glyphs / lost-gear HUD | 24 / 22 | Passed |
| System menu recovery / mounted poses | 29 / 102 | Passed |
| Existing performance budgets | 29 | Passed |

Native architecture, services, menu and input runs also pass. Reception, bar,
computer storage and the actual bed-rest pose were inspected at 1280x720.
On this ANGLE setup, test image readbacks intermittently omit cached menu text;
`civilian_services_input.gd -- --capture --capture-page=tavern` limits capture to
one page after the full input sequence. Labels and control bounds are also
asserted. Complete captures were inspected, but the computer-use connection
could not target these test windows for an independent live-window comparison.
The intermittent capture omission remains an unconfirmed renderer/test concern.
