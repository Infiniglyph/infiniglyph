# Infiniglyph · Phase 003

A small, genuine 3D neon city and third-person movement foundation for a future
skill-based martial arts game. Open `project.godot` in Godot 4.7.2 and
press **F6** on `scenes/main.tscn`, or **F5** to run the project. Development and
verification use Godot 4.7.2; earlier 4.x versions have not been tested. The
project feature tag is 4.7, matching the editor line used for development;
the PowerShell launcher selects the actual executable independently of that tag.

To add this project to Godot's project manager, click **Import**, choose
`project.godot` inside your clone, then click **Import & Edit**. Creating a
project folder outside Godot does not automatically add it to the project
manager's list.

Launch directly from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\tools\run_infiniglyph.ps1" -GodotPath "C:\path\to\Godot.exe"
```

The launcher defaults to the Godot 4.7.2 executable on your OneDrive Desktop.
Pass `-GodotPath "path\to\Godot.exe"` to use another installation.
The launcher opens a normal visible game window. Press Start / Escape for the
live system menu, or Alt+F4 to close the game.

## Guild, tavern and private lodging

The two-story **Adventurers Guild** is at `LAT 010N / LON 002W`; the separate
**Tavern** is at `LAT 014N / LON 001W`. Walk inside either public building and
use **G / tap RT** at reception, the bar, a notice board, table or chair.
Sell monster crystals to reception to earn Glyph Coins, then rent an upstairs
private room or buy electron meals and drinks. Private-room storage survives
room deconstruction, rental expiry and checkpoint reloads. All menus stay live.

[Civilian establishments guide](docs/CIVILIAN_ESTABLISHMENTS.md) covers controls,
prices, conservation of coins, storage, room instances and current placeholders.

## Persistent Code Form civilians

The four factions now contain **12 independent founding guilds**, with separate
leaders, treasuries, membership and headquarters. Suitable scenery buildings are
enterable shells: occupy a vacant one with **G / tap RT**, then install real owned
furniture, change its use, store goods or control access. NPCs can occupy and
furnish their own premises. The shared catalogue adds **56 placeables and 24
foods/drinks**; food restores HP and drinks restore shield according to rarity,
quality and preparation complexity.

**74 careers** share eight reusable work templates. Native Code Forms choose
and reconsider occupations, take funded jobs, operate businesses and retain
employment histories. Ask about a resident's identity, then choose **Career and
employment** to inspect their actual work. Titles and waiting do not pay wages.
See [guilds, buildings and careers](docs/GUILDS_BUILDINGS_AND_CAREERS.md) for
locations, controls, economic rules and the current production recipes.

Residents and keepers now share a six-choice intent conversation system, with
procedural electronic voices and live subtitles. The guild has separate Security,
Commerce and Exploration boards with finite funded contracts; private Underworld
work requires an earned tavern introduction. NPCs use the same work and intent
authorities. [Civic intents and quests](docs/CIVIC_INTENTS_AND_QUESTS.md) covers
controls, membership, actual deliveries, evidence and checkpoint continuity.
[Economic XP](docs/ECONOMIC_XP.md) explains provenance, legal/criminal parity and
bounded retrospective exploit corrections.

City residents, regional pedestrians, drivers and guild/tavern staff now have
individual persistent identities, motivations, memories, relationships and goals.
They choose local errands or lightweight background work, meals, trade, social
visits and guild activities. Conversations reflect remembered encounters; service
staff offer **Ask about their plans**. The world continues inside instances.

The civilian clock runs at one real hour per game day. Code Forms start with
100 game years, gain another 100 per level, and receive 100 Glyph Coins every
30 game days. Combat death retains the person; lifetime expiry creates one new
individual and preserves the old economic history. The player, bosses and
dungeon enemies receive no civilian XP, levels or lifetime mechanics.

[Code Form civilization guide](docs/CODE_FORM_CIVILIZATION.md) describes the
configuration, save migration, transaction rules, simulation limits and tests.

## Avat Ar and Glyphic Wonders

**Glyphic Wonders** is at **LAT 038N / LON 007W**, beside the pyramid district.
Use **G / tap RT** at its small storefront to enter an enormous separate hall.
Avat Ar welcomes customers at the central counter; twelve spaced pedestals
display a selection from the same catalogue as the Tower Exchange. Approach a
pedestal to inspect and buy its item with **A / Enter**. **B / Escape** returns.

The selection rotates every seven game days and survives leaving and reloading.
Health Glyphs and all three Shield Glyph tiers are always sold at the counter.
Purchases require real Glyph Coins and permanently remove those coins from
circulation. Civilians shop using their own wallets. The Tower Exchange remains
the player's development/testing interface.

[Glyphic Wonders guide](docs/GLYPHIC_WONDERS.md) covers prices, persistence,
instance boundaries, merchant presentation and verification.

## Repository and recovery

The standalone project is published at
[Infiniglyph/infiniglyph](https://github.com/Infiniglyph/infiniglyph).
The tag **`checkpoint-2026-11-08`** preserves the first public baseline, including
the 100-resident city and the corrected NPC shoulders and walking anatomy.
[Recovery instructions](docs/RECOVERY.md) explain how to launch that checkpoint
in a separate folder and how to use the independent offline Git bundle.

Godot 4.7.2 is the verified engine. Python 3.10 or newer is optional for the
live TED-RAG pose helper; its required constraint builder is bundled in
`vendor/ted_rag`. Gameplay uses local animation defaults when Python is absent.
An existing sibling `rag/context_builder.py` takes precedence, preserving the
development workspace's live connection. No API keys, cloud services or Python
packages are required to play.

## Gameplay HUD

The permanent HUD contains a cyan HP bar in the top left, a numbered blue
shield bar beneath it when protection is equipped, a thin orange exhaustion
bar below that, a small grid address below the bars, and
the Health Glyph count at bottom left. The grid uses 16-metre cells centered on
the central district origin: latitude increases north (-Z), longitude increases
east (+X). For example, `GRID  LAT 054N  LON 032E` identifies the cell containing
world position (512, -864). These are local grid indices. Height and camera
rotation do not change the address; movement, teleports and respawns update it.
The bars use the actual combat maximum/current
values; exhaustion fills as strain accumulates and empties during recovery.
The phase title, weapon/debug panel, control sheet, move/guard text, momentum
readout and permanent objective text are removed. Controls and weapon arts
remain documented here; equipment and item arts remain available in inventory.

Nearby interaction prompts, short notices/dialogue and encounter health appear
only in their relevant context. Unclaimed death losses keep a bottom-screen
`LOST GEAR` readout showing the latest item's distance, LAT/LON grid address,
altitude and the total unclaimed count. It survives short notifications and
respawns, restores from checkpoints and clears when the gear is recovered or
removed. The readout moves above resident dialogue while someone is speaking.
Hold **Select / View / Back** (or keyboard **B**) for **0.7 seconds** to dismiss
the guide and start a **five-minute** disappearance countdown on all your current
unclaimed death drops. Each timed pickup shows its remaining time in the world
and can still be recovered before expiry. The deadline survives checkpoint
reloads and time outside the item's area; holding again cannot extend it.
A later death creates fresh guidance. A short tap still opens inventory; with
lost gear visible, inventory opens on release so a hold does not open a menu.
Start, Settings and inventory continue to run the world without pausing.

## Window glow and stars

Selected windows glow cyan, blue, violet, purple, pink, red, orange, gold,
green, mint and soft white throughout the hub, outer city, homes and farms.
Their fixed occupancy and varied brightness keep most facades dark; each
window's color stays stable as you travel.
The panes sit against the existing solid walls, above working lobby entrances;
home panes fit the existing front-window frames. They share one material and
163 opaque spatial batches for the full region, with no added realtime lights,
shadows, collision bodies or per-frame animation work.

The black sky contains 1,100 subtle blue-white specks in a single 2048 x 1024
panorama, generated once at startup using a private random generator. Stars
stay at infinity through camera travel and rotation. Existing ambient lighting
is retained and sky reflections are disabled.

`tests/window_lights.gd` audits batching, physical facade support, deterministic
occupancy and lighting configuration. Run it with `-- --capture` on a native
display to review `captures/night_*.png` and verify varied window hues, sparse
stars and zero sky parallax. Existing world traversal, graphics-budget and
inventory-startup regressions also pass at 60 Hz.

## NPC visual attention

TED-RAG-guided attention budgets NPC pose updates. Offscreen NPC poses skip
rebuilds and visible distant poses update less often, while nearby residents
retain full-rate poses. Identities, journeys and meeting memories remain live.
The existing asynchronous TED-RAG worker supplies bounded detail budgets, with
local fallback. Map meshes, lights, shadows and collision use their original
rendering and are independent of this optimization.
See [WORLD_MEMORY.md](docs/WORLD_MEMORY.md) for behavior, limits and profiling.

## Beyond Central District

The continuous playable region is **2,304 x 2,304 metres**, approximately
5.3 square kilometres. The original hub stays at its existing coordinates.
It now connects in all four directions to a much larger city, residential
neighborhoods, and open countryside. This is a finite first region, with room
for further authored areas rather than an infinite-world claim.

Completing Greefer's first confrontation **by winning or losing** opens four
visible sliding road gates. Existing completed encounter saves open them on
launch; losing a rematch cannot close them. Follow the north road behind Central
Tower for the clearest route: urban blocks to about 448 m from the center,
suburbs to about 704 m, then rural roads, farms, woods, hills, ravine bridges
and a country lookout at `(0,0,-1048)`. The side and country road loops connect
back into the city. A normal fast run from the north gate to the lookout takes
about 95 seconds at the unchanged 10.2 m/s speed.

Added geometry includes **209 urban buildings, 317 homes, 33 farm buildings,
666 geometric trees, 34 rock outcrops and three solid ravine bridges**, alongside
the authored Kyren homestead and pyramid. The
new neighborhoods have sealed facades, solid gabled/flat roofs and open streets;
they do not yet have enterable household interiors. The existing 100 residents
retain their Central District routines and building visits. The regional life
system adds 780 neighborhood residents and 238 vehicle records across the
larger map, with nearby activity budgets described below. New encounters remain
future content.

Gates are real geometry, not invisible encounter walls. Sky Jump and all combat
movement remain unrestricted; creative aerial shortcuts do not grant the
intro-completion flag. Greefer remains territorial to the original district.
The new map is already physically present during his fight, so opening the
roads never teleports the player or loads terrain beneath a falling character.

`scripts/world_regions.gd` lays out the deterministic neighborhoods and matching
triangulated terrain. Farm pads are leveled into the actual terrain.
`scripts/world_chunk.gd` builds 81 immutable spatial mesh batches with full
collision; the original hub's expansion rim uses four narrow physics bodies
instead of making every hub NPC query a surrounding terrain mesh. Engine
frustum culling handles the meshes using their real local bounds. No custom
world-memory visibility toggles, unloading collision, or rebuilding map meshes
while moving are used. The 106 new orange fixtures have real local spotlights
with engine distance fading; their geometry remains solid and visible.

Set `world.wider_world_enabled = false` only for isolated baseline profiling.
Normal play enables the complete region. The minimalist HP/exhaustion HUD and
non-pausing menus are retained.

Before the regional life/traffic pass, native Intel HD 620 / Compatibility-ANGLE
review observed roughly 33 ms median
frames in the expanded hub, 12 ms in the suburbs and 5 ms in the country; a fresh
hub without the expansion measured about 28 ms. These are live-scene samples,
not identical-population benchmark runs or an FPS guarantee. The original hub
remains the heaviest view and the larger skyline has a render cost. The game
camera's far plane is 1,800 m for the expanded landscape. Use the native capture
helper with `-- --performance` to inspect frame time, physics time and draw calls.

The **2026-11-10 pre-optimization audit** adds `tests/performance_audit.gd` for native,
uncapped rendering and civilian-simulation comparisons. The startup warning is
Godot selecting its ANGLE OpenGL ES-over-Direct3D 11 compatibility path for this
Intel driver, as described in the [Windows driver settings](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-gl-compatibility-driver-windows).
The audit retains that working backend. On the i5-7200U / Intel
HD 620 through Compatibility/ANGLE at 1280x720, the outer-city simulation pass
observed these median frame times (lower is better):

| Diagnostic state | Outer city | Countryside |
| --- | ---: | ---: |
| Live scene | 44.8 ms | 14.4 ms |
| Original hub civilian updates stopped | 32.0 ms | 6.4 ms |
| Regional people/traffic updates stopped | 16.5 ms | 13.5 ms |
| Both civilian systems' updates stopped | 11.9 ms | 7.3 ms |

These temporary switches are confined to the diagnostic process. Bodies and
geometry stay present. Normal gameplay still runs continuously behind menus.
The same-view live repeats were 45.2 ms and 19.8 ms; changing crowds and desktop
load affect the samples. Player movement, boss thinking and the retrieval helper
are disabled for repeatability. This is a debug executable, with VSync disabled,
120 sampled frames per variant and at least 1.1 seconds of warmup. GPU timestamp
queries returned zero on this driver, so no isolated GPU-time claim is made.
These comparisons identify costs; they do not predict playable optimized FPS.

A separate render snapshot observed about 750 hub draw calls versus about
24 in the country. Frozen hub frames measured 26-27 ms, versus 21 ms with street
light shadows disabled. A 640x360 window measured about 21 ms in that snapshot;
reduced resolution alone leaves substantial overhead. Glow and lighting changes
varied by view and need paired validation before choosing quality defaults.
Full raw local results are in `captures/performance_audit.json` and
`captures/performance_simulation.json` (generated, excluded from Git).

The recommended implementation order is civilian simulation LOD for both hub
and regional rosters; cached/staggered vehicle probes and incremental spawn/route
validation; then spatial batching/material reuse for hub props and vehicle
details. The hub's distant residents currently retain full movement physics,
while TED-RAG budgets their poses only. Regional residents and seated vehicle
drivers have separate animation loops. Preserve full-rate player/combat physics,
identity and live virtual journeys, and all static map collision. A nearby
shadow budget and cheaper glow/render-resolution options can follow. Validate a
release export separately before setting a hardware FPS target.

Run the audit alone, from this directory, with a native Godot executable:

```powershell
godot --path . --script res://tests/performance_audit.gd
godot --path . --script res://tests/performance_audit.gd -- --simulation-only --views=urban,country --output=res://captures/performance_simulation.json
```

## Performance budgets and graphics controls

The four audit recommendations are implemented without changing player movement,
combat timing or static world collision. The world continues running behind
every menu.

- Hub residents retire distant movement physics beyond 180 m and return within
  140 m, with extra lead distance for fast travel. Their existing identities,
  paths, destination choices, building visits and relationships stay live in
  quarter-second route updates. Restoration checks real support and free space.
- Regional residents use the same near/virtual distinction at 65/90 m, with
  speed-dependent lead distance. Visible far motion interpolates between route
  records; articulated poses use the existing TED-RAG worker's bounded rates.
  Regional pedestrians and seated drivers share those pose budgets. Combat
  proxies remain in the normal full-rate combat pipeline.
- Traffic reuses its obstacle shape/query and samples at approximately 10 Hz,
  including extra lookahead travel. Swept vehicle movement and collision remain
  full-rate. Neighborhood activation constructs at most one vehicle and one
  resident per tick; cached route validation uses at most twelve probes per tick.
  Distant regional residents now advance their own route records as traffic does.
- Immutable hub prop geometry is combined by material/shadow mode in 16 m cells
  once at startup. Source structural meshes remain hidden inspection references;
  all original collision shapes remain enabled. No runtime map hide/unload or
  camera-driven mesh rebuilding is used. Wheels use two instanced batches per
  vehicle, and immutable materials are shared. Fading effects retain unique inks.

**Start / Escape > Settings > Graphics** now exposes:

| Setting | Default | Choices |
| --- | --- | --- |
| Nearby streetlight shadow budget | 4 | 0-16; 16 restores all hub casters |
| Neon glow | Full | Off, Soft (one filtered sample), Full (two samples) |
| 3D resolution | 100% | 50-100%; HUD and menus retain native resolution |

Orange lights continue illuminating even with shadows disabled. Shadow selection
uses a nearby budget with hysteresis, independently of map geometry. Settings
apply immediately, persist in the existing versioned configuration, and scroll
with controller focus. Existing settings files load with these graphics defaults.

`tests/performance_budgets.gd` passes **29 checks at 30/60/120 Hz**, covering real
near/far transitions, identity, smooth virtual travel, occupied-space recovery,
bounded spawning/sensing, combat handoff, graphics persistence and live menus. Native captures
review the graphics controls and all three vehicle types. Existing vehicle
steering, theft combat, world-memory, world traversal and structural-support
checks also pass. The 180-second population-flow soak retains 98 distinct outdoor
identities, 58 building entries and 76 exits with no unsupported falls or contacts
beyond its 2 cm tolerance.

The native audit accepts `--live-only`, `--outdoors=64`, `--shadow-budget=16` and
`--settle=5` for comparable before/after sampling. Use real frame time (no
`--fixed-fps`) and run each rendering benchmark alone. Generated reports and
captures remain under the ignored `captures` directory.

The same-machine comparison against `checkpoint-2026-11-10-performance-audit`
uses the same updated harness, seed 1893, 64 hub outdoor slots, 1280x720, full glow,
100% 3D resolution and all 16 hub shadow casters. Each visit settles for at least
five seconds, then samples two 120-frame windows. Median frame-time ranges were:

| View | Previous checkpoint | Optimized |
| --- | ---: | ---: |
| Dense hub | 65.6-67.4 ms | 55.1-64.4 ms |
| Outer city | 50.5-82.1 ms | 15.5-16.1 ms |
| Country | 14.0-14.1 ms | 7.1-8.1 ms |

Hub draw calls fell from about 763 to 691-699. The largest gains come from
retiring distant civilian physics, and the dense hub remains the limiting view.
The default four-caster budget is available in normal play; it was deliberately
raised for this comparison. Dynamic journeys change which people/vehicles are
visible, and other desktop applications were left running. These are debug-build
observations, not an exported-release FPS guarantee. Raw reports are
`.godot/perf-audit-baseline/captures/perf-before.json` and
`captures/perf-after.json`; the baseline game source is unchanged, with only the
same diagnostic harness copied into its isolated directory.

## Seating, neighborhood life, vehicles and Health Glyphs

Tap **RT** or press **G** near a bench to sit; use it again, move, or jump to
stand. Hub benches, quarter benches and outer neighborhood park seats all use
claimed seat anchors and checked standing positions, following the Infinite
Library's seating pattern. Weapons stow while seated. Standing restores the
original movement/collision state. Start > Unstick can also use a safe exit.
Seated hips now sit 8 cm higher and 12 cm farther forward to improve clearance
from the seat and backrest. Vehicle contacts use their existing anchors.

The expanded world has **780 additional residents** (390 of each body profile,
eleven colors), neighborhood walking/break routines, repeat greetings and
**238 vehicle records**, mixing moving traffic and parked driveway vehicles.
Cars, motorcycles and trucks have distinct silhouettes, seating, speed and
physical collision. Taking an occupied vehicle puts its driver onto checked
footing as a resident; it does not delete the driver. Cars stop for nearby
physical obstacles and residents, and briefly at corners. No police/crime
system, household interiors or extra combat mechanics are implied.

Tap **RT / G** beside a slow/stopped vehicle to drive it. Use **W/S or left-stick
forward/back** to accelerate, brake and reverse, and **A/D or left-stick
left/right** to steer. The right stick/mouse still controls the camera. Release
the movement input to slow down. Exit with **RT / G** at any speed, including
while airborne. You retain the vehicle's current velocity, and the abandoned
vehicle coasts under its existing braking. Exits use clear capsule space and a
swept route beside the vehicle; a solid wall can still block a dismount.
Entering and leaving keeps the camera attached and restores the player's
original capsule settings.

**L3 / Ctrl** toggles a driving boost, increasing forward top speed to 1.65×
with stronger acceleration. Braking, reverse, steering and swept body collision
retain their existing behavior. **R3 / Tab** toggles a vivid light wall matching
the vehicle's color, emitted from the rear of any driven car, motorcycle or
truck. R3 returns to target lock
after dismounting. A bottom-left driving readout shows speed and both toggles.

The wall is 1.2 m high, lasts up to four seconds and contains at most 128
segments. It deals 750 combat damage per target every 0.5 seconds of contact.
Swept contact catches fast crossings between physics samples; overlapping
panels share a cooldown. The source vehicle and its driver are immune. Turning
the emitter off or dismounting stops new panels while existing ones fade.
Relocation clears the path instead of drawing a line across the world.
Vehicles have 1,000 HP (car), 650 HP (motorcycle) or 1,600 HP (truck). Destroyed
vehicles stop, extinguish their lamps, display a red wreck marker and cannot
be driven; their physical bodies remain. Damage survives distance streaming
within the current world session. Vehicle condition is not a new disk-save
system. Light-wall rendering uses two mesh surfaces and no per-panel nodes.

### Shield Glyphs

The Tower Exchange's Items / Glyphs category offers **Light Shield Glyphs
(250 points)**, **Medium Shield Glyphs (500)** and **Heavy Shield Glyphs (1,000)**.
**Hold RT+B for 0.45 s**, or **hold V+H for 0.45 s**, to use the strongest
owned Shield Glyph: **heavy, then medium, then light**. This chord does not jump
or trigger nearby interactions. The blue **Shield Glyphs** count above Health
Glyphs shows the total owned across all three tiers and updates on use, pickup,
purchase and save/load. Driving status sits above both counters.
You can also open Inventory, select a glyph and choose **Use Shield Glyph**.
Each consumes one owned item and establishes that tier's protection. Shields absorb combat
damage after normal guard mitigation, before HP; excess damage spills into HP.
Parries and dodge invulnerability consume no shield. Falls retain their existing
direct HP damage. Shields do not regenerate or stack, and a glyph is not
consumed when current protection is already at least its offered amount.
Respawning clears protection. The optional shield state in version-one
inventory checkpoints preserves tier and remaining points; older saves start
without a shield. These consumables do not reintroduce retired shield cosmetics.

**Void Soul Greaves** add eight color editions to the Tower Exchange / Equipment
Archive's Armour / Legs catalog: cyan, violet, gold, mint, pink, blue, silver and
ember. Their original design combines a clasped waist belt, four long split
cloth folds, two layered scale aprons, wrapped greaves and enclosed boots.
The description remembers a gift from the void to a weary traveler. All colors
share the same cut and use existing cloth motion, vehicle folding, equipment
previews and save/load. They remain cosmetic Legs equipment.
Sideways cloth flow blends gently through direction changes, with reduced
lateral inertia and bounded hem roll. Raised Sky Jump knees use a stable
downward reference, so skirts and the Scribe robe cannot flip their folds as
a thigh crosses above its hip. Forward trailing and vehicle folds remain active.

`tests/gameplay_tweaks.gd` exercises real inventory use, shield spillover,
save/load, parry/dodge, weapon carry, boost, wall contacts and expiry, wrecks,
fast crossings, dismount input and uninterrupted pyramid facing. Use
`-- --hz=30`, `-- --hz=60` or `-- --hz=120`; add `--capture` for native review.
All 49 checks pass at 30/60/120 Hz and in the native 60 Hz Compatibility/ANGLE
capture run. The 9-check garment audit confirms distinct authored cuts and
bounded geometry; the eight Void Soul color editions share one cut.
Existing inventory/startup, shop,
equipment preview, cloth, defensive combat, driving, moving exit, terrain,
input, HUD and 92-check dungeon foundation suites also pass.

New implementation files are `scripts/shield_glyphs.gd`,
`scripts/vehicle_light_wave.gd`, `scripts/garment_variants.gd`,
`tests/gameplay_tweaks.gd` and `tests/garment_variety.gd`, with UID sidecars.
They integrate through the existing inventory/loot authority, weapon combat,
garment renderer, vehicle, input, world actions, shop/preview and HUD scripts.
Native review captures are `captures/garment_variety.png` and
`captures/tweaks_{dagger,fist,twin_blades,shield_heavy,vehicle_wave}.png`.

`tests/moving_vehicle_exit.gd` passes 92 checks at each of 30/60/120 Hz for all
three vehicle types, reverse/top speeds, coasting, airborne exits, blocked-door
alternatives, collision-enclosed exits and attachment restoration. The updated
city-life fixture passes 60 checks at 60 Hz; mounted poses, vehicle handling
and the live Start/Unstick menu retain their existing regression coverage.

Mounted limbs use vehicle-local hand and foot contacts. Motorcycles have a
forward-leaning sport riding pose with rear-set pegs behind the hips, bent knees
and hands on the handlebars. Cars and trucks keep both feet in the pedal well.
Traffic drivers use the same contacts in their existing mesh batches. Bike
headlight lenses connect to a front fairing instead of floating ahead of the
frame. None of these pose changes alter driving controls, speed or collision.
Leaving a seat restores the complete local limb pose, including shoulder and
elbow twist axes, before locomotion resumes. Mounted IK cannot leave the arms
folded backward after dismounting.
Scribe coat tails fold over the belt and stream behind a bike's saddle, above
the rear wheel. Enclosed cabins hide the long hems; stepping out restores them.

Driving is **vehicle-relative**: stick up/W always moves toward the vehicle's
nose, and left/right always steer toward its physical left/right. Camera yaw
does not enter the driving calculation. Entering starts the camera behind the
vehicle; after that, right-stick/mouse orbit is free. Reverse naturally reverses
the steering response. The original acceleration, braking and speed limits are
preserved. The +Z-facing models use a negative yaw change for a right turn.
Low/medium-speed steering now allows much tighter intersection turns: about a
5 m radius with strong steering and 40% throttle, rather than the previous
20 m radius at the same input. The turning rate is capped at higher speeds,
and partial stick steering remains proportional. `traffic_vehicle.gd` exposes
`steering_turn_per_meter` (0.22) and `steering_max_yaw_rate` (2.1 rad/s) for tuning.

Cars, motorcycles and trucks can climb small curbs and raised driveway slabs.
`traffic_vehicle.gd` exposes `max_step_height` (0.35 m). Grounded movement checks
the complete body's upward/forward clearance and a supported landing before
lifting by the measured step height. Low ceilings limit the available lift;
floor pressure/snap are suppressed for the ascent frame so a slow approach is
not pulled back down. Taller walls, residents and other vehicles remain solid
obstacles. Autonomous traffic's lookahead clears these low slabs too. Existing
38-degree slope handling, acceleration, steering, speed limits and rider contacts
are retained. Unsupported edges still use gravity; this is not a stunt/suspension
or ramp-launch physics system.

Stealing an occupied vehicle provokes its displaced driver. Up to six nearby,
visible residents can also witness theft (including original hub residents).
They use varied anti-human remarks and individual temperament-based **anger**;
calmer residents can complain without immediately fighting. A brief overhead
anger readout accompanies their remarks. Further thefts can build on existing
anger, which cools after the incident. Reentering the same stolen vehicle does
not generate another theft, and residents cannot perceive theft through walls.

Attacking a civilian uses the same personal anger system. Each landed attack
adds **22% of that resident's vehicle-owner theft gain**, with temperament still
affecting the buildup. An overhead amber-to-red meter progresses through
**Annoyed, Irritated, Furious and Hostile**, accompanied by escalating trash talk.
Fresh gestures can raise anger; extra damage pulses from the same move do not
multiply the anger gain. Whiffs and hits blocked by architecture add none.
Talking to an annoyed citizen repeats its current taunt. Leaving it alone allows
anger to cool and the meter to disappear.

At **100 anger**, a resident shouts before starting normal combat. Every provoked
street opponent can join the fight; there is no three-fighter cap. They use the same 1000 HP, weapon arts,
momentum damage, chip, parries, one-second parry stagger, exhaustion, dodges and
Sky Jumps as the player/Ember. Their existing identity, color and body silhouette
remain. Civilians take real damage before fighting, and their remaining health
carries into the combat adapter. Lethal civilian hits use the same respawn flow.
Once hostile, they can damage the player. Red/orange damage
sparks and normal damage numbers come from the shared hit pipeline. Physical
vehicles stop weapon hits. There is no new player stamina cost or global police
system. Street fights yield to Ember/Greefer encounters; distant pursuers give
up after a short grace period.

A defeated resident reappears at its own spawn after **six seconds**, with anger
reset and the same identity/memories. A blocked spawn waits for safe clearance.
NPC death clears that resident's anger, taunts, warning timers and meter. Player
death or respawn ends all civilian fights and pending retaliation, including
unloaded regional identities. Surviving residents resume their routines with
their current health; defeated residents keep their normal safe respawn delay.
Old attack buffers and deferred defeat callbacks cannot carry hostility into
the next life. A new theft or assault starts a fresh annoyance buildup.
Hub building schedules reserve the fighter's civilian slot so combat and respawn
cannot duplicate an NPC. These reactions/respawns are current-session state.
Balance values are exported on `TheftReactions`: `enrage_threshold`,
`anger_recovery`, `assault_anger_scale`, `respawn_delay` and `max_fighters`.
The final warning lasts 0.8 seconds and cannot be delayed indefinitely by
continued hits. Calm civilians retain their existing lightweight physical bodies;
only enraged residents construct a full combat rig. Hub-only worlds also support
these reactions. Protected encounters and the current single-player authority
boundary remain in force.

`tests/assault_reactions.gd` passes **27 checks at 30/60/120 Hz**, including real
melee and Scribe geometry contacts, escalating taunts, cooldown, injury carryover,
retaliatory damage, regional rematerialization, blocked respawn, and protection
against through-wall or missed-hit provocation. Native captures show the stages
under `captures/assault_*`.

`tests/npc_hostility_reset.gd` passes 22 checks at 60/120 Hz. It covers lethal
civilian/fighter hits, actual player
death and fall respawn, same-frame deaths, stale taunts and warning timers,
safe blocked respawns, identity rematerialization, target/collision cleanup,
preserved injuries and fresh provocation after reset.

Nearby activity is bounded to **28 regional pedestrians and 22 vehicles**,
in addition to the original hub population. Distant traffic retains lightweight
route/driver records rather than full physics and animated meshes. Neighborhood
identities, colors, conversation counts, abandoned vehicles and takeovers persist
through distance changes in the current session. Physical driveways use spatial
batches. World terrain/building meshes and collision are never toggled or
unloaded by this system. Vehicle journeys/positions are session state, not a
new disk-save or multiplayer replication system. Regional traffic currently
runs in offline play; the existing host inventory validation governs healing.

**Hold RT and tap B**, or press **H**, to use one owned **Health Glyph** and
restore up to **350 HP**. Healing works while moving and has no stamina cost or
new animation lock. Full HP, no glyphs, or a defeated actor consumes nothing.
The small bottom-left count reads the actual inventory; glyphs also appear in
the inventory's Consumables category. New and existing valid saves receive
**three once**; a persisted migration flag prevents launch/load refills. A
collectible three-glyph stack is available near the arrival court. Consumption,
ownership and quantities use the existing checkpoint/loot transaction pipeline.
Invalid checkpoints still fail closed without a starter regrant.

Bare **RT interactions resolve on release**. A/Space always jumps, including with
RT/V held. A quick RT+B tap heals on release; holding it uses a Shield Glyph.
B alone
still dodges, and RT+X/Y still use the existing modified charged arts. Held or
repeated button-down events cannot consume multiple glyphs, and returning from
menus/focus changes requires neutral triggers. Menus never pause traffic or the
world. Set `world.district_life_enabled = false` only for isolated profiling.

`tests/city_life.gd` exercises actual inventory/HP, controller chords, save/load,
seating, steering, three body types, safe entry/exit and driver takeover at
30/60/120 Hz. `tests/traffic_flow.gd` follows six neighborhood visits, checks
bounded activation, real autonomous travel, support and a solid obstacle sweep.
Native captures are available through `city_life.gd -- --capture`; add
`--performance` for live frame-time/draw-call samples in urban/suburban/country
views. Generated captures and personal saves are excluded from source backups.

`tests/vehicle_terrain.gd` passes **63 checks at each of 30/60/120 Hz** using real
car, motorcycle and truck bodies: 5/20/32 cm parking lips, reverse, diagonal and
full-speed approaches, autonomous curb crossings, both fitting and obstructed low
roofs, over-height walls, resident/vehicle obstacles, airborne side contacts,
30-degree hill ascent/descent and unsupported drops. `tests/city_life.gd` also
drives all three vehicles from the street into a real generated suburban
driveway while orbiting the camera, then checks safe dismounts. Add
`--capture --parking-only` to capture just its three parking views.
The rendered city-life run passes **57 checks at 30 Hz**; all three parking
captures were reviewed. Traffic flow passes **10 checks**, and the performance
budget suite passes **29**, at 60 Hz.

`tests/vehicle_controls.gd` checks vehicle-relative directions at four headings,
camera orbit, analog throttle, reverse and live menus for all three vehicle
types, plus measured tight left/right turns, stationary steering and bounded
high-speed/partial-stick response. `tests/theft_combat.gd` checks actual theft,
witness visibility, escalation, shared defenses/strain/momentum, real AI damage,
death/blocked-spawn recovery,
fighter limits, encounter isolation and hub identity reservations. Both accept
`-- --hz=30` or `-- --hz=120` with a matching engine `--fixed-fps` value. The
theft test accepts `-- --capture` for native reaction and combat screenshots.

`tests/mounted_pose.gd` passes **102 checks at each of 30/60/120 Hz**, measuring
real limb endpoints, peg/pedal support, attached headlights, cabin roof and robe
clearance, safe exits and stable contacts on distant roads. Native checks also
inspect the traffic drivers' actual mesh batches; seven mounted captures were
reviewed, including visible sheathed katana views. `tests/camera_distance.gd`
passes **37 checks at each rate**, covering live controller adjustment, saved and
legacy settings, lock-on, spring-arm obstruction, vehicle transitions and truck
clearance at the closest setting. Its native Settings preview was also reviewed.

The steering suite passes **147 checks at each of 30/60/120 Hz**; the theft suite
passes **27 at each rate**, including native captures at 60 Hz. Charge/sparring,
Greefer, lock/momentum, vehicle interactions, traffic and live-menu regressions
also pass. The earlier civilian curb-overlap issue is addressed by suppressing
floor snap while a rounded heel is still supported by the curb edge. Both the
160-second interaction soak and 300-second population-flow soak now pass their
physical contact checks at 60 Hz.

## Equipment library

Ready daggers and twin blades now point forward; fist weapons point down.
Authored attacks and guards retain their existing grip curves. The pyramid's
deconstruction/reconstruction maps character facing and camera orbit through the
doorway frame, so entering faces into the corridor without changing their relative angle.

All 371 tailored catalog armor pieces now have distinct rendered geometry,
including 85 hand and 90 leg items. Eight stable construction families combine
flared cuffs, fitted palms, individual knuckle plates, spiral wraps, lapped
bracers, articulated greaves, shaped knees and varied closed boots. Body
contours, collars, capes, tabards and helmet crests also vary by item identity.
`garment_variants.gd` supplies stable dimensions to the same renderer used by
worn equipment and previews. IDs, ownership, slots and combat values are kept.
`tests/garment_variety.gd` hashes actual mesh vertices, verifies uniqueness and
bounded geometry, checks foot restoration, and can capture all eight hand/leg
styles with `-- --capture`.

The [equipment library](docs/EQUIPMENT.md) contains 2,193 additional definitions, including
**1,690 named weapons**, 374 cosmetics and 129 rings. The original four starter
weapons remain available. At the central bipyramid, Tower Exchange now opens
separate **Weapons**, **Items** and **Armour** departments. Search, filter, preview
and acquire items for free. Armour previews wear the actual garment on our rig.
Health Glyphs are in Items; all menus keep the world running.

Named weapons use sampled DAR-derived motion adapted to our existing skeleton:
383 distinct reference clips supply 15 vocabularies, with individual combo/art
orders, support grips, leverage, stance, tempo and loading. Related variants
share motifs; these are not thousands of independently hand-keyed animations.
Reference attacks use the basic four weapons' pace, with family-specific timing,
earlier buffered combos and smooth, extended follow-through (especially staves).
Slow light cycles now approach 0.34–0.65 s plus at most 0.07 s of item variation.
The next buffered attack can take over after the final hit and early recovery;
visual return to ready does not add an input lock. Scribe, Paintbrush and the
four starters retain their handling. See [equipment playback](docs/EQUIPMENT.md)
for tuning and verification.
Grounded, aerial and charged sequences preserve existing momentum damage,
defenses, cancellations and free traversal. The Fractured Moon, Event Horizon
and The Last Argument also receive the motion upgrade.

Sampled swings now hinge forward through the actual smoothed torso pose,
including turns, then blend back into locomotion during recovery. Movement,
hit schedules and damage remain unchanged. Sampled hands and wrists use the
figure's forward axis; extreme windups ease into a small rear shoulder load
instead of reaching behind the back, while elbows bend relative to the moving
chest. A short visual return to ready blends hand endpoints and elbow bends
together, with immediate attack, guard and dodge interruption. Sheathed scythes
carry head-up in the same back mount as spears; sword and katana mounts retain
their angles.

All 371 wearable pieces now use fitted, articulated Scribe-derived construction:
shaped torsos, layered plate, shoulders, sleeves, collars, headpieces, boots,
split hems and capes. Reference silhouettes and fabric colors guide the cuts.
Hems follow their thighs around pinned seams. Flexible robes and capes add
smoothed trailing, turn/acceleration response and a second free-hem bend,
opposing actual travel even while backpedaling or strafing. Plate tassets stay
firmer. Cloth trails behind a bike and tucks inside cars, restoring on dismount.
Existing meshes are posed without per-frame mesh rebuilding. Armor remains cosmetic.
Six corrected head/hand/leg classifications migrate old equipment assignments
without losing owned items. IDs and version-one saves remain compatible.

Inventory rows, equipment assignments and item inspection now show weapon
family or armour type and slot, including the original equipment. Long lore
and arts scroll with the mouse, PageUp/PageDown or right stick while type,
assignment and menu controls remain visible at 720p.

| Equipment motion/tailoring verification | Result |
| --- | --- |
| Complete catalog, geometry and checkpoint | 14 checks passed |
| Every named signature, all wearables, pulse timing and six save migrations | 15 checks passed |
| All 15 motion cuts on the actual player rig, including forward contact lean | 46 checks at each of 30/60/120 Hz |
| Natural arm workspace, continuous release, shared grips and immediate interruptions | 190 checks at each of 30/60/120 Hz |
| Forward contact audit, moving headings and smooth release | 12 checks at each of 30/60/120 Hz; 568 reference contacts |
| Scythe/pole stow, sword/katana/twin preservation and repeated equips | 78 checks passed |
| Leg-follow, directional cloth flow, firm plate and mounted clearance | 17 checks at each of 30/60/120 Hz, plus 20 native checks |
| Combat, acquisition, saves and separate shop departments | 53 checks at each of 30/60/120 Hz, plus native 60 Hz |
| Existing weapons / body motion / charged sparring / lock and momentum | 123 / 146 / 146 / 110 checks passed |
| Defender exhaustion / responsive dodge / mounted poses | 36 / 68 / 102 checks passed |
| Inventory model / UI / integration / Tower shop | 55 / 58 / 36 / 36 checks passed |
| Scribe robe / fitted robe / performance budgets | 31 / 21 / 29 checks passed |

The guide records architecture, reference coverage, source-rig assumptions,
bounded caches, regeneration and remaining visual limits. Native captures also
review eight garment cuts and all three shop departments. Existing source
checkpoints remain available alongside this milestone.

## Eturnull equipment and Scribe combat

**Eturnull Hat** is a separate Head cosmetic in Tower Exchange > Armour. Its dark
conical brim and silver-blue ribs match the Eternal Scribe robes. The hat sits
13 cm lower, with its brim below eye level and its crown clear of the head.
Forty-four pooled glyphs in the robes' silver-blue, violet, silver, gold and cyan fall from
the brim; three staggered groups assemble recognizable equations, hold, then fade.
Sixteen additional flat symbols emerge from the crown's center and flow outward
over its sloping top, cycling cached mathematical shapes in the same five colors.
They stay above the opaque fabric so they remain visible from overhead.
Motion trails stay bounded, and offscreen/distant effects skip pose updates.
The robe retains its existing inscriptions and effects;
equipping headwear hides its overlapping hood. Existing crowns remain available.

**Eturnull Manuscript** introduces the **Scribe** weapon family, available through
Tower Exchange > Weapons > Scribe and assignable to any weapon direction. The
character's anatomical left hand supports an open procedural Grimoire while its
right hand conducts a floating feather quill adapted from the Infinite Library's Scriptorus design.
Individual pages turn and flutter, with stronger reactions for heavy attacks,
charging and the existing parry window. Sheathing dives the quill into the book,
then closes and stows it on the anatomical left hip; drawing reverses the sequence.
Both the sheathed Manuscript and the robe's belt tome sit flat against the hip,
with page edges facing forward and broad covers visible from the side.
The ready stance rests over the rear left foot with a softened front knee and
the right arm hanging relaxed with a nearly straight elbow. Its lower-body pose
yields to travel and air motion. The idle quill floats independently about one
metre to the anatomical right, with its tip just above shoulder height. Its small
velocity-based trail follows forward, backward and lateral travel, capped at
30 cm (10 cm vertically) to stay attached during Sky Jump and fast movement.
Nine distinct conducting curves adapt existing Fractured Moon, Event Horizon and
Last Argument gestures, with separate flick, cross, overhead, circular and
finishing silhouettes. The left book arm remains supported through them.

Right basic attack cycles Quick Inscription, Crossed Expression, Descending Proof
and Circular Derivation. Left basic attack uses Final Statement. The four arts
are Theorem and Integral Closure, plus the RT equation-tracing arts described
below. The two unmodified arts retain hold/release charging, momentum damage,
guard strain, timed parry, dodge and Sky Jump. The Manuscript's block power is 72%. All four light stages match
the starter twin blades: 0.34-second duration, 0.10-second windup and 0.14-second
contact. Base damage is now **30** for Final Statement (previously 52); light
stages deal 13/16/18/17 and the two unmodified arts deal 28/24 per pulse. Grounded
and aerial variants share this reduction; normal charge and momentum bonuses
still apply. The heavy uses a 0.395-second named twin-blade tempo; the four arts use
the starter twin-blade timings. Ordinary written strokes extend from the near caster to
7 m, matching the spear's Prism Skewer; normal full charging extends this to 9.1 m.

The quill tip follows the actual progressively revealed equation strokes. Contact
pulses query capsules along those same visible segments, then use the shared
wall, ownership, guard, parry and damage resolver. Being inside a generic reach
sphere alone cannot cause a Scribe hit. Writing is one fixed 160-instance mesh
pool; cancellation, sheathing and weapon switching clear it. These are local
written strokes, with no new resource meter. Ordinary casts keep their original
horizontal free aim committed at attack start, with target lock taking priority.
The Manuscript's equations share the purple trace palette. A fixed six-entry mesh
pool leaves harmless, world-fixed afterglows for 0.65 s beyond normal recovery;
damage timing, damage amounts and animation duration stay unchanged.

Holding **RT / V** with the Manuscript open brings its quill upright into the
right hand. Holding the modifier alone does not attack. Releasing it returns
the quill to its existing independent hover; sheathing still stores it in the
closed book at the left hip.

**RT+X / V+Q** continuously traces intersecting X expressions; **RT+Y / V+R**
continuously traces circular expressions. A tap leaves a tiny X or circle.
Holding repeats the pattern along actual quill-tip movement, including turns,
sprinting, jumping and Sky Jump. Release stops new writing immediately; the
existing mathematical strokes remain fixed in world space and fade after **3 s**.
**A / Space always jumps or Sky Jumps**, even while holding RT/V without tracing.
With the Manuscript drawn, holding RT also collects nearby loot through existing
host validation; it never automatically sits down or starts dialogue. Hold
**RT+B / V+H for 0.45 s** to use a Shield Glyph. Theorem and Integral Closure
retain their existing charge/release controls. Only held-quill tracing uses
camera pitch as well as yaw.

The equations reuse the vehicle light wave's bounded trail storage and fade rule,
with independently balanced **30 damage** and a **0.5 s victim cooldown**. Overlapping
pieces cannot stack damage inside that cooldown. Arbitrary 3D stroke contacts work
instead of a vehicle-height wall. They use existing ownership, walls, block,
dodge, exhaustion and parry mechanics. A parry preserves the normal one-second
attacker stun, opens a gap in nearby intercepted sections and sends those
sections in the defender's facing direction. Reflected ink can hit its author
but cannot be parried again. Death, travel and actor removal clear hazards;
ordinary cancellation stops writing while already written ink expires naturally.

`scripts/equation_trace_settings.gd` exposes X/Y periods (0.25/0.35 s), minimum
tap size (0.025 m), contact thickness (0.04 m), lifetime, damage, glyph scale,
spacing (0.13 m), fade duration (0.6 s), reflection speed (9 m/s), sampling
interval and limits (192 sections / 4,096 strokes). One shared cylinder mesh
batch and cached glyph paths serve the entire trail; there are no per-symbol
physics bodies or scene nodes. The existing vehicle wave keeps its appearance,
dimensions, lifetime and damage behavior.

`tests/equation_tracing.gd` exercises real controller/keyboard input, horizontal
casting versus pitched tracing, harmless afterglow lifetime, held quill IK, taps, live movement
and Sky Jump, swept contacts, timed parry/reflection, fading, bounded storage and
cancellation. All 55 checks pass at 30/60/120 Hz. Run with `-- --hz=30`, `60` or
`120`; `--capture` saves native views. The native production-world capture tool
also reviews the post-recovery cast afterglow, held quill and aerial traces.

The **Paintbrush** is a separate weapon family available in the Tower Exchange /
Equipment Archive's **PAINTBRUSHES** filter. Its eight editions use the existing
cyan, violet, gold, mint, pink, blue, silver and ember palette. Each brush's paint
matches its pigment, including redirected paint; already drawn strokes retain
their color when switching brushes. All editions share the same handling.

The anatomical right hand holds a physical calligraphy brush tilted 45° forward. The
empty left hand stays low and forward, with a forward-leaning martial stance.
Sheathing uses the normal back mount. There is no book or floating quill.

| Paintbrush input | Keyboard | Paint |
|---|---|---|
| LB / RB | Left / right mouse | Opposing quick diagonal strokes |
| Hold X | Hold Q | Repeating squares |
| Hold Y | Hold R | Repeating triangles |
| Hold RT+X | Hold V+Q | Repeating crosses |
| Hold RT+Y | Hold V+R | Repeating circles |

Taps leave tiny geometric marks; holds continue drawing from the actual brush
tip. RT alone does not attack. Run, sprint, jump, Sky Jump and dodge retain
their existing controls. Movement carries new paint through 3D space while old
paint stays suspended. Dodge, guard, forced reactions, menus, sheathing and
weapon changes stop drawing; existing paint expires normally. Death, travel
and actor removal clear hazards. There is no new resource meter or movement lock.

All six attacks reuse the Manuscript's bounded world-space contact, ownership,
wall, guard, fade and one-time parry redirection logic. Paint is smooth luminous
geometry with no mathematical notation. Intercepted sections leave a safe
opening, travel in the defender's facing direction and may hit their author;
they cannot be parried again. The existing one-second attacker stun remains.
The Manuscript retains its equations, quill, ordinary casts and RT arts; vehicle
light waves retain their existing 750-damage behavior.

Brush-only tuning in `scripts/paintbrush_settings.gd` defaults to **30 damage**
for lights and trails, **0.34 s** light duration, **1.1 m** light stroke length,
**0.55/0.50/0.25/0.35 s** square/triangle/cross/circle periods, **0.30 m** pattern
radius, **0.025 m** tap radius, **0.04 m** contact thickness, **3 s** lifetime,
**0.6 s** fade, **0.3 s** victim cooldown and **9 m/s** reflection speed. Geometry
is capped at **192 sections / 4,096 strokes** in one batch, with no per-stroke
scene or physics nodes. Brush guard power is 60%. Its tuning resource is separate
from the Manuscript, so balancing paint does not alter equation traces.

`tests/paintbrush.gd` covers real input, all six attacks, physical nib/IK agreement,
colors, live movement/Sky Jump, persistent hits, defenses, reflection and cleanup.
`tests/paintbrush_equipment.gd` covers real purchases, the catalog, previews,
inventory and checkpoint restoration. `tests/capture_paintbrush.gd` captures all
four arts and an eight-color palette in the native Compatibility renderer.
All 89 combat checks pass at 30/60/120 Hz; the equipment suite passes 47 checks.
The Manuscript's 55 tracing checks also pass at all three rates. Catalog,
Scribe equipment, weapons, combat input, shield shortcuts, vehicle/pyramid and
parry regressions pass. Native readback confirms all eight paint pigments.

The new content registry is `data/equipment/paintbrush_equipment.json`.
`paintbrush_moves.gd`, `paintbrush_patterns.gd`, `paintbrush_presentation.gd`
and `paint_trace.gd` provide brush handling, pen paths, mesh and trail adapter.
Integration extends the existing weapon rig/library/combat, body stance,
equipment registry/previews, inventory help and combat-intent routing.

Cosmetic shields (693 entries), talismans (eight), bows (twelve), and crossbows
(eight) are retired, for 721 historical IDs.
The cosmetic Shield slot and shop filter are removed. The starter Longsword +
Shield retains its functional shield. Exact historical IDs validate and migrate
old saves: retired items, assignments, drops and their markers are removed while
other ownership survives. Personal saves are untouched by test fixtures.

`tests/scribe_equipment.gd` covers the real player rig, equation assembly, bounded
pools, writing contacts, cancellation, movement, defense, save migration,
sheathing and previews. Run with `-- --hz=30`, `60` or `120`; add `--capture` on a
native display for outfit, overhead hat, conducting and hip-stow images under `captures/`.
The movement/visual pass recorded **101 checks with zero failures at 30/60/120 Hz**, including
a native 60 Hz capture run. Catalog, reference equipment quality, equipment
integration, inventory model/UI, starter weapons, charged sparring, parry/stagger,
Scribe robes and performance-budget regressions also pass at 60 Hz. The older
RT fixture now models bare-trigger release and menu-neutral rearming explicitly.
The subsequent damage tuning passes **103 Scribe checks at 60 Hz**, including
all reduced grounded/aerial values and an actual 30-damage heavy contact.
Controller feel and visual density still benefit from a normal gameplay session;
these checks do not establish a release-build performance guarantee.

## Pyramid dungeon exterior

The first dungeon's overworld landmark is centred at **LAT 047N / LON 005W**
(`-80, 0, -752`). Its square base is **128 metres** wide and its apex rises
**82 metres** above the base: a full-scale monument in the existing dark-surface,
neon-edge style, with warm gold contours and staggered masonry courses.

The four sloping faces are one convex solid. A foundation meets a levelled
terrain pad, and procedural scenery lots under and immediately around the
base are reserved so houses, trees and farm props cannot intersect it. The main
country road, ravine bridge and Kyren's neighbouring home retain their routes
and elevations. A shallow approach from the road leads into a recessed,
human-scale entrance with pillars, a stone gable and a sealed door.

`scripts/pyramid_exterior.gd` provides `DungeonEntrance` and `ExteriorArrival`
markers. The landmark adds two immutable mesh surfaces, ten collision volumes
and no processing loop, imported assets or realtime lights. Its exterior mesh,
terrain fit and collision are unchanged by the Phase 1 interior below.

`tests/pyramid_exterior.gd` checks exact site/scale, surface and door collision,
terrain fit, reserved plots, road and Kyren clearance, a real walk to/from the
vestibule, jumping, Sky Jump and phase-dodge collision. Add `-- --capture` for
`captures/pyramid_exterior.png` and `captures/pyramid_entrance.png`; `--hz=120`
selects the alternate simulation rate.

All 22 pyramid checks pass at 60/120 Hz and in a native 60 Hz capture run.
The existing outer-world traversal suite passes 18 checks and Kyren's homestead
passes 17 checks at 60 Hz after the site is added.

## Pyramid dungeon foundation — Phase 1

Walk into the existing recessed doorway and press **G / tap RT** to enter.
Approaching alone does not activate it. Inside, the front-door portal uses the
same interaction to leave; its short cooldown prevents the activating press
from immediately returning. Bare RT retains its existing release-to-interact
behavior, including RT combat combinations. Nearby loot keeps pickup priority.

The fixed labyrinth has eight-metre passages, seven-metre ceilings, branching
routes, dead ends and papyrus-like pillars. Ankh, Eye of Horus, lotus, water,
feather and scarab motifs form turquoise and gold wall bands. Architecture and
symbols share four static geometry batches; symbols add no individual nodes or
per-frame generation. This phase contains no guardians, bosses, traps, treasure,
activated checkpoints or procedural reshuffling.

`scripts/dungeon_travel.gd` prepares the bounded interior once during world
construction. The outdoor scene and `pyramid/<owner_id>` interior each retain
their own `World3D`, beneath non-rendering SubViewports. The main viewport
switches between them while the same player, controller, equipment, camera and
UI stay in place. Inactive scenery is hidden and its scripts stop processing;
static support remains available for saved-drop validation in that location.
Only the main viewport renders. Menus continue to leave the scene tree running.

The transition adapts the staged floor/structure manifestation in Infinite
Library's `scripts/library_room_manifestation.gd`: coarse geometric cells and
height bands disappear, then new outlines assemble around the intact character.
`environment_manifest.gd` temporarily applies a shared shader to environment
meshes and restores their original materials afterwards. It never dissolves
the player or scales physics. Movement, attacks and damage are gated for the
brief transition, with no loading splash or progress bar.

Combat body/arm posing also observes this transition lock. Entering clears its
additive overlay and stance anchors; ready poses resume on the fresh locomotion
pose after arrival. This keeps drawn Manuscripts and Paintbrushes upright during
both doorway phases instead of stacking their ready lean while gait is frozen.
Weapon selection, drawn/sheathed state, health and equipment are preserved.
`tests/dungeon_drawn_weapons.gd` samples the actual joints through entry and exit.

`scripts/respawn_context.gd` resolves the existing death pipeline's destination.
Without placed glyphs, outdoor deaths use `TemporaryHomeSpawn` at the original
city spawn and dungeon deaths use `DungeonFrontDoorSpawn`. Placed Respawn Glyphs
add a choice of destinations to this same death/equipment-drop pipeline, as
described below.

All unclaimed drops keep their original identities and location across travel,
multiple deaths and checkpoint reloads. The bottom-screen recovery guide follows
the latest outstanding loss, advances to the preceding one after recovery, and
names the other location when it requires doorway travel. Cross-world pickup
and targeting are rejected. Version-one saves add optional `location_context`
and per-drop `location_id` fields; legacy outdoor saves retain their defaults.

Solo instances are prepared locally. Networked/live sessions gate doorway travel
until party-aware authority and replication exist. Future integration belongs
at `DungeonTravel.interact`, the location-to-scene registry and
`LootAuthority.location_roots`: the host must authorize party membership, select
an instance identity, route actors/replication to its World3D, and reset encounter
state after a party wipe while retaining drops. Full party instancing and wipes
are deliberately outside Phase 1.

`tests/dungeon_foundation.gd` exercises G entry, RT exit, character continuity,
transition input/damage safety, maze connectivity/collision, sprint, Sky Jump,
dodge, location-dependent death, repeated losses/recovery, checkpoint reload,
fresh startup and repeated cycles without growing node count. Run with
`-- --hz=120` for the alternate physics rate or `-- --capture` in a native run
for `captures/dungeon_deconstruction.png` and `captures/dungeon_interior.png`.

Phase 1 validation: all 92 dungeon checks pass at 60/120 Hz and in a native
60 Hz capture run on Intel HD 620 / ANGLE. Inventory loot (47), inventory
startup (21), lost-gear HUD (22), Tower Exchange (36), Start/recovery (29),
Kyren encounter (53), Greefer encounter (48), outer-world traversal (18) and
pyramid exterior (22) and defensive interaction (48) checks pass at 60 Hz.
Combat input and the isolated
baseline movement suite also pass. The original movement test's free-air
fixture disables the wider countryside because its old flight path now meets
solid country buildings; production movement is unchanged. Repeated-travel
checks establish stable node count and released transition materials, rather
than a release-build performance guarantee.

## Pyramid entry enemies and returning discs

The entrance labyrinth now contains six **Restless Skeletons**, two **Jackal
Guardians**, and an **Exalted Jackal Guardian**, using original procedural
models inspired by the supplied gold/cyan concepts. The arrival corridor stays
clear. Skeletons approach in small groups; guardians carry hooked khopeshes and
use the shared guard/parry system. Maze-cell paths keep pursuit out of walls,
only two enemies commit attacks simultaneously, and distant/other-floor actors
sleep. Leaving the instance stops its simulation; menus keep active combat live.
Player death or leaving the dungeon resets the entire encounter: defeated
enemies return, and survivors return home at full health without hostility.
Death cancels enemy attacks immediately while the live respawn-choice menu is
open; rosters repopulate after reconstruction, including at a dungeon glyph.
Changing floors keeps the current run's clears. Checkpoints saved inside retain
that run's progress; outdoor saves omit clears, and older outdoor checkpoints
discard their stale defeat records. Dropped loot remains available after resets.

Defeated monsters lose collision immediately, erode into light fragments and
leave **gear copies plus a remnant glyph**. Skeleton glyphs are smaller cyan
Common materials; guardian glyphs are larger violet Uncommon materials; the
exalted guardian leaves a large gold Rare glyph. Skeletons also drop Bone
Shards. These collectibles and gear use normal pickup, ownership, drop and
save/load rules in the correct dungeon World3D. The upper temples and B1-B7
now have their own floor-owned rosters; B8 uses its dedicated Ahkmet/Lorai encounter.

**Vector Disc** and **Twin Vector Discs** are available in the Tower Exchange /
Equipment Archive. RB/LB use rapid dagger-style cuts; the existing four weapon
art inputs throw spinning discs roughly **seven meters**, then return them to
the moving bearer along broad circular arcs. Ready discs point downward with
their faces turned sideways to clear the character; stowed
discs sit between the shoulder blades, with the single disc centered. RT+X and
RT+Y (V+Q / V+R) use a cartwheel and a turning vault with scissoring legs and
different release angles. Their curved outbound paths converge on a locked
target. Full-body poses remain cosmetic and preserve running/air movement.
Real swept flight contacts honor walls, block, dodge and
parry. Charge strengthens a single flight. Switching, sheathing, dodge/animation
cancellation and defeat remove the flight hitboxes and restore held models.
Whips now use a curved, tapered flexible lash instead of the rigid segmented
rod, and collision follows the actual visible cord.

Implementation: `pyramid_encounters.gd`, `pyramid_enemy.gd`,
`pyramid_enemy_brain.gd`, `pyramid_enemy_visual.gd`, `monster_dissolve.gd`,
`whip_presentation.gd`, `disc_moves.gd`, `returning_disc.gd`, plus equipment,
loot, checkpoint and travel integration. Focused fixtures are
`tests/whip_discs.gd` and `tests/pyramid_enemies.gd`; native procedural design
captures come from `tests/capture_pyramid_arsenal.gd`.

## B2 Falcon Sentinels

The two courts on **B2** contain two **Falcon Sentinels**, one **Exalted Falcon
Sentinel**, three **Winged Skeletons**, and two **Skeletal Archers**. This roster
is created on the first visit to B2. Each enemy belongs to its floor's scene;
other-floor AI sleeps, and pursuit routes through the real central portal.

Sentinels wear hooked falcon masks, cyan eyes, feather mantles and layered
tassets. Their wings fold at rest and unfold during aerial approach and wing
slashes. Shared feather meshes use six surfaces per pair, animated through two
wing roots; garment panels are also batched once during construction.

The aerial guard uses the player's actual jumping, Sky Jump impulses and
collision movement to pursue observed targets. Air Step Combo, the feathered
Wing Slash and the telegraphed Sunfall Dive use normal timed strike volumes.
Archers draw enemy-only bows and release visible, non-homing swept arrows.
Architecture stops projectiles; weapon guard, dodge invulnerability and the
existing zero-damage parry/one-second attacker stun remain intact. Player bows
and crossbows remain retired. Movement and menus retain their existing rules.

Falcons can drop **Horuswing Blades**, **Sentinel Spear**, **Falcon Sentinel
Mantle**, **Skyguard Tassets**, or **Eye of Horus Seal**. These original items
also appear in Tower Exchange / Equipment Archive. Their wearable copies share
the NPC geometry; tassets include closed greaves that hide the original feet.
The seal remains a cosmetic accessory, consistent with existing ring behavior.
Defeated flyers dissolve and leave equipment plus a difficulty-sized remnant
glyph on supported ground. The elite leaves a Rare glyph; ordinary Sentinels
leave Uncommon glyphs. B2 follows the same death/exit reset rules as the hub.
Current-run clears persist in checkpoints saved inside, while pickups remain
persistent both inside and outside the pyramid.

`tests/dungeon_enemy_respawn.gd` covers both floor rosters, lethal damage with
and without respawn glyphs, B2/Home reconstruction, direct fall recovery,
projectile/dissolve cleanup, full health/home resets, repeated exits and re-entry,
retained loot without duplicate rewards, and inside/legacy-outside checkpoints.
All 32 checks pass at 30, 60 and 120 Hz.

`tests/pyramid_b2.gd` checks actual flight and strikes, arrow defense, floor
isolation, loot ownership and checkpoint restoration. Native visual captures
come from `tests/capture_falcon_sentinels.gd`; sideways disc views use
`tests/disc_refinement.gd -- --capture --poses-only`.

Validation: B2's **38 checks** and the sideways-disc fixture's **22 checks** pass
at **30/60/120 Hz**. Existing entry enemies (28), equipment integration (54),
catalog (14) and motion/garment quality (15) checks pass. Native captures reviewed
the three enemy designs, folded/deployed Sentinel wings, wearable copies and
sideways discs. These checks cover behavior and bounded geometry, not a release
performance benchmark for the full dungeon.

## Furnished pyramid and the deeper encounters

All 17 storeys now have floor-owned temple dressing: gold/cyan inscriptions,
processional columns, braziers, animal reliefs, statues, archive lecterns and
burial furniture. B3 has animated shallow-water channels and fountains; B7 has
soft purple mist over clearly marked venom areas. Static furnishings use a
two-surface batch per floor. Existing columns receive glyph inlays, while new
solid props avoid stair apertures, their approach lanes and safe arrival points.
The original physical stairs and unrestricted movement remain available.

The complete roster contains **100 enemies across 16 populated storeys**:
the entry hub has nine, B1 has six, B2 has eight, U1-U7 have three each and U8
has one. **B8 hosts Ahkmet the Vile and Lorai**, a separate two-phase boss
encounter described below. The supplied deeper-floor
references are implemented as these encounters:

| Floor | Population and identity | Combat and environment |
| --- | --- | --- |
| B3 | 10 Crocodile Wardens, Drowned/Riverbound Skeletons and Tomb Scorpions | Deliberate cleaves, shield charges, accepted-hit tosses, tail sweeps and telegraphed flood surges around shallow channels |
| B4 | 10 Ibis Scribes, Acolytes, Glyph Constructs, Skeletal Scribes and guard remnants | Swept glyph volleys, warned pulse fields, brief bind strikes, temporary wards and nearby ally chants in an archive |
| B5 | 16 Tomb Walkers, Fighters, Burial Guards, spear-wielding Mummies and Cursed Wardens | Burial ambushes, shield support, close-range draining strikes and one vulnerable reassembly attempt per Cursed Warden |
| B6 | Renu the Huntress, Tefet the Dancer and Sakhra the Warden | Pounce, multi-hit blade dance and spear control; two pressure while one flanks, with periodic warned convergence fields and stronger survivors |
| B7 | 16 Snake Charmers, Asps, Cobras, Horned Vipers, Burial Serpents and destructible Charm Obelisks | Bites, physical venom spits, poison clouds, bounded serpent revival waves and nearby support |

Enemy techniques use the shared damage, block, dodge, parry and one-second
attacker-recoil systems. Ordinary light attacks still cannot stun. Glyph fields
show their actual footprint before becoming active; opaque architecture stops
projectiles and field contacts. Venom refreshes a four-second status rather than
stacking indefinitely, and mist permits a brief exposure before poisoning.
Cursed Wardens remain vulnerable at one HP during their two-second reassembly;
finishing them prevents their recovery and produces the final drop once.

The three champions each drop their own gear and a Rare remnant. Defeating all
three grants one additional **Sekhmet's Sigil** and Rare glyph at their reliquary.
Charmers and obelisks can each revive at most two defeated serpents once per run.
These budgets, reassembly flags and defeated IDs survive inside checkpoints;
death or leaving resets them with the rest of the encounter. Existing loot stays
available. The checkpoint limit now accommodates the full roster.

Only the hub and two recent encounter floors retain full enemy rigs. Other
floors keep primitive health/position snapshots until revisited; support and
reassembly timers account for time spent away. AI sleeps off-floor. Temporary
glyph fields are capped, and floor ambience uses at most 96 batched motes.

**22 original equipment copies** join the catalog and Tower Exchange: six
weapons, eleven clothing pieces and five cosmetic keepsakes. NPCs and player
copies share the same native geometry, including closed greaves. **Venom Fang**
is a stackable material. The established player Scribe remains available; the
reference sheet's class-unlock proposal does not replace its mathematical
Grimoire/quill combat. Enemy bulwarks do not restore retired player shield slots.

Implementation is in `pyramid_furnishings.gd`, `pyramid_bestiary.gd`,
`pyramid_depth_brain.gd`, `pyramid_depth_combat.gd`, `pyramid_depth_moves.gd`,
`pyramid_field.gd`, `pyramid_depth_visual.gd` and `pyramid_regalia.gd`, integrated
with the existing encounter, equipment, loot, preview and checkpoint services.
`tools/build_pyramid_depth_equipment.py` rebuilds the authored loot definitions.

`tests/pyramid_depths.gd` exercises all floor rosters and safe spawn volumes,
actual AI attacks, shared parries, glyph projectiles and fields, support,
ambush/reassembly, champion rewards, bounded revival, venom, streaming,
expanded checkpoints and every new wearable/weapon preview. Its **66 checks**
pass at **30/60/120 Hz**. The full architecture traversal passes **129 checks**
at 60 Hz, walking **6,023.5 metres** through both branches and back. Native views
come from `tests/capture_pyramid_depths.gd`, including the B8 chamber.

## B8 — Ahkmet the Vile & Lorai

The **Throne of the Vile Pharaoh** contains a royal platform, inscribed 22-metre
columns, serpent carvings and a gold/violet ceremonial battle circle. Its boundary
is visual: movement, Sky Jump and the existing stair route remain available.
Approaching within 38 metres or landing a hit begins the encounter. Its health
bar renders in the player's viewport, while the boss stays in the dungeon's
isolated World3D. The existing collision-aware camera widens during combat and
uses an upper-body lock focus; the saved follow distance and collision mask are
restored on completion, floor departure, death and exit.

Ahkmet stands directly on Lorai's animated head. The same serpent, health pool,
head and golden staff persist through both phases. The default health is 2,400;
`lorai.gd` exposes the union threshold (default 52%). A large Phase 1 hit stops at
that threshold and begins an 8.4-second, non-damaging ceremony. Ahkmet lowers the
staff, opens his arms, steps willingly into Lorai's waiting jaws, and disappears
as union glyphs illuminate. Lorai rises, grows two muscular arms and receives
Ahkmet's original staff. There is no second health refill, transition kill or
transition loot. Player movement and inputs remain available throughout.

| Phase | Techniques |
| --- | --- |
| The Serpent Throne | Serpent Lunge, Venom Spit, Serpent Sweep, Radiant Judgment, Pharaoh's Command |
| The Serpent Ascendant | Cataclysmic Coil, Venom Storm, Serpent Grasp, Radiant Annihilation, Judgment Bite, Inherited Pharaoh's Command |

One controller selects techniques from observed distance/elevation and commits
to the observed aim point. It does not read player inputs. Distinct windups,
active contacts, cooldowns and recoveries use the established combat resolver.
Animated mouth, arm and staff volumes produce actual damage; shared projectiles
and warned venom fields handle ranged pressure. Cataclysmic Coil creates an
expanding ground annulus which airborne feet can clear. Blocks, dodges, weapon
art stagger and the existing one-second parry recoil all apply. Basic light
attacks still cannot stunlock the boss. A grasp toss requires an accepted hit
and uses the existing Warden convention without locking controls.

The first victory drops **Ahkmet's Scepter**, **Lorai's Fangblade**, four
**Pharaoh of the Vile** cosmetic pieces, **Serpent Crown of Union**, an
**Apep–Lorai Catalyst** and a Rare remnant glyph. Later victories drop one fresh
gear copy, a catalyst and a Rare glyph. The first-clear bundle commits atomically
through the loot authority; a failed factory cannot leave a partial bundle or
claim the entitlement. The owner inventory stores the first-clear claim with the
checkpoint and world drops. Cosmetic equipment grants no new stats. The scepter
uses the existing **staff** class; it does not replace the Grimoire/quill Scribe.
The catalyst is a collectible material with no unimplemented crafting power.

Death or leaving resets the fight while preserving earned loot and the
first-clear entitlement. Moving between floors retains primitive health/phase
state. Inside checkpoints resume the same remaining health; saving during the
union resumes in stable Phase 2. A completed fight stays cleared for that run.
The boss uses 26 cached body links, 27 compound hurtboxes, bounded contact
samples, at most eight projectiles and four fields, and no unrestricted serpent
physics. No unrelated enemy floor is loaded for the fight.

`ahkmet_encounter.gd` owns lifecycle, rewards and UI; `lorai.gd` owns the shared
actor and AI. `lorai_combat.gd`, `lorai_moves.gd`, `lorai_visual.gd` and
`lorai_wave.gd` provide the combat adapter, timed techniques, procedural rig and
expanding annulus. `ahkmet_regalia.gd` shares royal clothing with player copies.

`tests/ahkmet_boss.gd -- --hz=30|60|120` runs **58 checks**, covering live AI,
real attacks, defenses, aerial
avoidance, mounted attachment, willing union, streaming, checkpoints, reset,
reward failure rollback, repeat clears and equipment previews. Native reviews
use `tests/capture_ahkmet.gd` and `tests/ahkmet_boss.gd -- --capture` for the
actual player camera and HUD. Captures/logs are ignored local QA artifacts;
these are bounded-runtime checks, not a release performance benchmark.

## Reusable respawn glyphs

**Respawn Glyph** and **Home Respawn Glyph** are available in Tower Exchange's
Items department. Select one in Inventory and choose **PLACE RESPAWN GLYPH HERE**
while standing on clear, solid ground. Placement uses one inventory item and
binds a reusable marker. Each player can keep one personal marker and one Home
marker; placing another of the same kind replaces only that destination.

On death, choose the personal glyph, Home, or the current area's default spawn.
Both placed glyphs remain reusable after every death. Use D-pad/left stick and
A on controller, or W/S/arrow keys and Enter/Space on keyboard; mouse selection
also works. The menu keeps the world running and closes other local menus.
Without any placed glyph, the existing immediate default respawn remains.

Markers retain their location, facing and camera view in version-one saves.
Personal and Home choices can cross between the city and the player's pyramid
instance, restoring the correct floor. Unsafe or obstructed anchors are omitted
from the choices. Older checkpoints load with no glyph destinations.
`tests/respawn_glyphs.gd`, `tests/disc_refinement.gd` and
`tests/doorway_heading.gd` cover ownership, repeated deaths, checkpoint recovery,
cross-world travel, flight arcs, gymnastic movement and doorway-relative facing.

Validation for this pass: respawn glyphs **24 checks**, refined discs **19 checks**
and doorway heading **11 checks**, each passing at **30/60/120 Hz**. At 60 Hz the
existing theft combat (27), hostility reset (22), whip/disc combat (24), equipment
integration (54), Kyren (56), Greefer (48), dungeon foundation (92) and gameplay
tweaks (53) suites also pass. Native captures reviewed both glyph markers, the
death-choice menu, single/twin ready and stowed discs, and both gymnastic throws.
Godot's headless editor import reports no script errors. The full native disc
simulation exceeded its first capture run's time budget; the dedicated native
pose capture completed, and timed combat checks passed headlessly.

## Pyramid architecture — sixteen floors

The existing entrance maze is the **unnumbered entry hub**. Facing into the
pyramid from its door, its **back-left** dead end now opens to the B1–B8
descending stairwell, and the **back-right** opens to U1–U8. The exterior,
RT/G entry/exit and environment manifestation use the existing Phase 1 systems.

This is one pyramid, extending the same outward slope below ground. Every
sloping structural panel follows `half_width(y) = 64 * (1 - y / 82)`, centred
on the same interior axis. Upper floors stand at Y=8, 16, …, 64 m; their widths
decrease from about 115.5 m at U1 to 28.1 m at U8. The interior closes beneath
the existing 82 m apex. B1–B7 stand at Y=-16, -32, …, -112 m. B8 stands at
Y=-144 m, providing a roughly 352.8 m base and 32 m of arena headroom.
Basement widths increase with depth; there is no second or inverted pyramid.

`scripts/pyramid_interior.gd` assembles the seventeen storey containers
(sixteen numbered floors plus hub) from deterministic definitions.
`scripts/pyramid_floor.gd` reuses slab, sloping-wall, portal, pillar, ledge
and glyph components. Upper galleries include protected shafts and ledges;
lower halls vary between colonnades, divided courts, hypostyle galleries and
the open B8 arena. U8 contains an empty summit dais. B8's monumental supports
sit around the perimeter, leaving its centre clear for Ahkmet and Lorai.
The entry hub and the populated numbered floors are described above.

`scripts/pyramid_stair.gd` joins every adjacent pair with a two-flight stair:
visible treads, smooth ramp collision, a turning landing, full-width arrival
landings and protective rails. Flights have a 1:2 rise/run ratio. Upper
connectors move inward as the pyramid narrows. Floor and ceiling openings are
cut from the same stair footprints; room partitions also respect those openings
so they cannot cross a flight. Return routes require no jumping or teleporting.
The original hub corridors remain eight metres wide.

Successive stairwells now alternate between opposing corners, so reaching the
next flight requires crossing the floor. The hub retains back-left descent and
back-right ascent. A full-height wall joins the central maze wall to the sloping
rear perimeter, dividing the former shared vestibule: crossing between the two
hub stairs now requires returning through the labyrinth. Pillars and ledges
clear relocated stair footprints; the summit dais stands opposite its landing.

Each floor has a `FutureContent` container with `CentralSpace`,
`WestGallery` and `EastGallery` marker sockets. These are empty attachment
points for later content, not a new encounter framework or navigation system.
Future NPC content will need its own navigation and encounter authoring.

All static geometry is prepared once before entry. Each new floor and stair
uses a batched mesh, reusing the existing dark and wire materials. Only the
current storey and its immediate neighbors render, with adjacent stairs.
Collision remains loaded for Sky Jump, dodge, save validation and recovery.
Dropped items inherit their floor's visibility. Hidden floors are omitted from
manifestation material capture; no floor geometry is rebuilt during travel.

Version-one checkpoints gain optional `location_state` containing floor ID,
position and camera yaw. Restarts restore a supported position on the saved
floor. A position without a floor ID is inferred from its elevation and real
collision. Invalid/outdated positions use a safe anchor on that floor; older
Phase 1 saves without position data fall back to the hub. Dungeon death still
respawns at the front door, while outdoor death returns home. The existing
equipment transaction and loss-ordering system is retained; recovery guidance
now includes U/B floor labels. The void-respawn limit is location-aware so
legitimate basement movement is never mistaken for falling out of the world.

`tests/pyramid_architecture.gd` walks both branches and their return routes
using the real player controller, verifies profile/collision and safe anchors,
checks floor culling and solid-floor Sky Jump containment, and exercises deep
save/restart, invalid-position fallback, cross-floor deaths, drops and recovery.
Use `-- --hz=120` for the alternate physics rate. For a native visual pass,
use `-- --geometry-only --capture`; it skips the long walking tour and writes
`captures/pyramid_upper_gallery.png`, `pyramid_summit.png` and
`pyramid_deep_arena.png`, plus `pyramid_hub_divider.png`. Native capture checks are separate from the full
headless controller traversal. Neither run is a release-build FPS benchmark.

The architecture suite verifies opposing stair footprints, the sealed rear
shortcut, and safe restoration of older saves inside the new divider. The
complete tour covers approximately 6 km through every connection in both
directions, including the hub labyrinth between its two stair approaches.

Changed files:

- New: `scripts/pyramid_floor.gd`, `scripts/pyramid_stair.gd` and
  `tests/pyramid_architecture.gd`, with Godot UID sidecars. Railing updates add
  `scripts/rail_barrier.gd` and `tests/railing_traversal.gd`.
- Assembly/rendering: `scripts/pyramid_interior.gd`, `dungeon_glyphs.gd`,
  `dungeon_travel.gd`, `environment_manifest.gd` and this README.
- Existing state integration: `scripts/inventory_store.gd`,
  `inventory_session.gd`, `loot_authority.gd`, `respawn_context.gd`,
  `player.gd` and `combat_hud.gd`.

Manual review:

1. Enter with G / tap RT, find the rear signs, and walk up right/down left.
2. Cross each floor to the next flight, reach the summit and arena, then return.
   Check that the rear hub wall requires the maze route between stairs.
3. Save on an upper or lower floor, quit and restart; verify floor, position
   and equipment. Try Sky Jump and dodge near ceilings, rails and stair turns.
4. Die on two floors, recover the newest item and follow guidance to the older
   loss; exit and verify outdoor death still uses home.

### Railing collision

City skyways and countryside bridges keep their open posts and bars visually,
but use continuous, bevel-ended collision panels instead of separate post and
midrail colliders. This removes the gaps that could catch the player capsule.
City staircase stringers are visual details rather than obstacles inside the
walking lane. Dungeon stair, shaft, approach and lookout rails use the same
continuous panel geometry, including vertical sides on sloping stair flights.
The rails still guard drops and can be jumped over normally.

`scripts/rail_barrier.gd` builds the shared convex geometry at construction
time. `tests/railing_traversal.gd` probes guard spans at low, middle and top
heights, presses the real controller along city/bridge/dungeon rails in both
directions, releases away from contact, and checks connected curved joints.
It supports `-- --hz=60` and `-- --hz=120`. The existing skyway route suite
also checks full flights, junctions and exposed-edge coverage.

Validation after the structural changes: the full dungeon walking tour passes
at 60 and 120 Hz (about 6 km each), including save/load and death/drop recovery.
All 39 railing checks pass at both rates, including 7,260 guard probes per run.
The native Compatibility/ANGLE visual pass passes 95 non-tour checks and captures
the gallery, summit, arena and hub divider. The 33-check skyway route suite,
13-check city collision audit, 92-check dungeon foundation suite, 29-check
menu/recovery suite and baseline movement tests also pass.

## Kyren's home

Kyren rests beneath a cherry blossom tree at **LAT 047N / LON 003E**, centered
on world X=48, Z=-752 beside the northern country road. The small house has an
open front doorway, walkable porch, bare interior and solid pitched roof. Its
clearing blends into the existing terrain; the country road stays in place.

Kyren uses the ordinary resident body at twice its size, colored gold, in a
breathing cross-legged rest pose. His named katana rests visibly in its crimson
saya at his left hip, transferring to his combat skeleton when he stands. His
deep red woven conical hat uses the Eturnull silhouette and sheds falling orange
embers. The hat contains no mathematical symbols. His dark red scarf stays
attached at the neck and continually curls through changing wind directions
while stationary. During movement it smoothly streams behind his actual world
velocity, including strafing, reversals and aerial travel, preserving three
metres of cloth. The player's scarf copy uses the same behavior and follows
vehicle velocity while riding. Teleport displacement never becomes false wind.
The tree has pink five-petal blossoms and
drifting, tumbling fallen petals. **G / tap RT** opens an optional challenge;
attacking him also starts the encounter. Controller A accepts and B declines.
Start/Settings offers **Leave Kyren encounter** during a fight. The world stays
live in every menu. His fight has no arena boundary; leaving sight and pursuit
range ends the confrontation after twelve seconds. Once combat ends through a
win, loss or disengagement, he teleports directly beneath his tree with gold
phase effects and a full combat/movement reset. After losing, he recovers at home
for three seconds before accepting another challenge. There is no walk-home AI
or return path to get stuck on; an active encounter cannot trigger this reset.

His fighting form uses the existing player skeleton, input contract, physics,
Sky Jump, phase dodge, guard, parry, exhaustion and hit resolver. His named
**Kyren's Katana** derives its ten techniques from the existing Uchigatana-based
Luminous Contour Longcurve motions: two three-cut chains and four broad arts.
**Silent Contour** drives a 28 m/s draw strike through ordinary capsule collision,
then finishes with a sheathing gesture. Charged release aligns its contact and
dash windows. His three items also appear in Tower Exchange and Equipment Archive.

Every Kyren defeat drops **one fresh copy**, selected uniformly from **Kyren's
Straw Hat**, **Kyren's Scarf** and **Kyren's Katana**. The normal world pickup
stays where he was defeated while he teleports home; if the defeat has no safe
ground, the reward falls back to his clearing. Collect it with **G / RT**.
Duplicate defeat callbacks cannot produce another reward, and his victories or
disengagements award nothing. Copies have independent item identities; Kyren
keeps his original gear. Unclaimed pickups and collected copies use the existing
inventory/world-drop save system, with normal trading and dropping rules.

The hat equips in **Head**, with the same crimson weave and 36 falling embers.
The scarf equips in **Body**, replacing that slot's current cosmetic, with the
same three-metre wind-driven cloth. Both use Kyren's original geometry/effect
implementations and player-size skeleton attachments. The copies hide during
phase dodge and return cleanly afterward. Their previews show the real costume,
and the scarf preview frames the full tail. Neither cosmetic grants combat stats.

`scripts/kyren_salt.gd` exposes the event gains, cooldown, decay and thresholds.
Salt starts at 10%, stays between 0–100%, and advances through smug, annoyed,
salty and meltdown. Actual resolved hits, vulnerable dodge hits, parries, charged
interruptions, aerial momentum and HP thresholds drive it. Duplicate contacts
and repeated bonuses are guarded. Pressure and technique preferences change
between actions; defense keeps a real reaction delay and reads visible actions,
never buffered player input. Defeats leave a small persistent frustration floor.

The 153 editable entries in `data/dialogue/kyren.json` preserve the supplied
dialogue and add contextual state/counter reactions. Weighted selection uses
per-line cooldowns, a 3.8-second global cooldown, priorities, occasional silence
and a single subtitle channel. Long lines wait for openings. House/tree lines
require actual collision-ray contact; mailbox lines remain dormant because the
site has no mailbox. Rare reactions use genuine perfect/starter wins, parry
streaks, three consecutive defeats and a later Kyren victory. The third-defeat
exchange is remembered once per owner, with a pause between its two lines.

Kyren's challenge count, player wins/losses, previous tactics, salt and rare-line
history share `user://encounters_v1.json` with Greefer. Writes merge the latest
journal and preserve its existing owner, backup and atomic replacement policy.
Test runs use isolated profiles and disable automatic persistence. In a debug
build, explicitly add `-- --kyren-debug` or enable `World.kyren_debug_enabled`
for the developer panel: salt/state, HP, history, combat event, subtitle cooldown,
selected line and AI state, with set-salt, event, preview and history-reset tools.

Static house/branches/crowns use the existing opaque world batches and matching
collision. Blossoms share one 240-instance mesh; falling petals and hat embers
use fixed pools of 96 and 36. The scarf uses 24 cloth sections and 48 trim
segments, with nearby animation limited to 30 Hz and distant effects skipped.
No imported assets, rigs, external libraries or additional realtime lights are
required. The original Greefer progression and road gates remain in force.

`tests/kyren_homestead.gd` checks the exact grid location, ordinary NPC proportions,
resting state, terrain support, roof/walls, real player entry through the door,
constant scarf length and all wind quadrants, attachment stability and effect
pool limits. Native rendering additionally verifies the actual doubled head and
falling petal/ember transforms. Add `-- --capture` for
`captures/kyren_home.png`, `kyren_resting.png` and `kyren_wind.png`; `--hz=30`
or `--hz=120` selects an alternate physics rate. The wider-world regression also
checks existing terrain, roads, collision and gate progression.

`tests/kyren_scarf_movement.gd` checks both actual wearers, world-space trailing
despite chest turns/leans, walking/sprinting and aerial directions, eased
reversals, stationary wind, neck attachment, constant cloth length, teleport
stability, fixed mesh pools and mounted vehicle velocity.

Verification: 17 logic checks pass at 30/120 Hz; the native 60 Hz run passes
20 checks including rendered head and particle buffers. The existing wider-world
suite passes 18 checks and Scribe equipment passes 103 at 60 Hz. The shared
cancellation cleanup now checks for a weapon rig before accessing its selected
equipment, so Greefer's natural-weapon visual remains compatible.

`tests/kyren_salt.gd` covers event calculations, thresholds, deduplication,
dialogue priority/cooldowns, rare sequences and journal validation.
`tests/kyren_encounter.gd` exercises real controller invitations, shared guard,
parry/stun, iframe dodge, named techniques, dash/wall collision, Sky Jump,
100%-salt AI, post-fight home teleports, defeat cleanup and merged persistence. Use
`-- --hz=30` or `--hz=120` for simulation-rate checks; a native run with
`-- --capture` writes `captures/kyren_master_stance.png`, `kyren_draw_strike.png`
and `kyren_sheathing.png`. Balance remains configurable and needs playtesting
against different player loadouts; automated checks establish mechanics rather
than subjective boss difficulty.

`tests/kyren_loot.gd` checks each of the three actual defeat drops, exactly-once
awarding, independent identity, original NPC gear retention, ownership/pickup,
unclaimed and equipped save/load, hat/cloth attachments and pools, phase cleanup,
real previews, host authority, failed spawning and void-defeat fallback. Its 53
checks pass at 60/120 Hz, including collection beside Kyren after his rematch
prompt returns. A native 60 Hz visual run also passed its 50 checks. Add
`-- --capture` to review the player wearing the copies
in `captures/kyren_loot_equipped.png`. Loot, catalog, exchange and encounter
regressions also remain covered by their existing fixtures.

Kyren implementation files are `scripts/kyren.gd`, `kyren_combat.gd`,
`kyren_brain.gd`, `kyren_encounter.gd`, `kyren_salt.gd`, `kyren_dialogue.gd`,
`kyren_progress.gd` and `kyren_debug.gd`, with authored equipment/dialogue in
`data/equipment/kyren_equipment.json` and `data/dialogue/kyren.json`.
`kyren_hat.gd` shares the hat with the NPC; `kyren_cosmetic.gd` attaches wearable
copies, while `loot_authority.gd` creates host-authored fresh world rewards.
Shared combat emits resolved contact and action events; normal player/weapon
behavior still uses the original resolver. Limb reach, phase presentation and
two-handed grips now preserve a fighter's configured visual scale.

Verification: 53 encounter checks, including actual lethal-hit and post-fight
teleport/reset cases, pass at 30, 60 and 120 Hz. The earlier native 60 Hz visual
capture passed 47 checks; 44 salt/dialogue/journal checks also pass. Regression
results: catalog 14, equipment quality 15, equipment integration 52, parry 36,
responsive dodge 68, Scribe 103, Greefer 48, named-motion rig 46, leg integrity 17
and Start/Settings/recovery 29 checks, all passing. Native review ran through the
Compatibility renderer on Intel HD Graphics 620; this is functional verification
and does not establish a release-build FPS or difficulty guarantee.

## Canonical narrative reference

The [Canonical World Lore & Narrative Design Profile](docs/canonical_world_lore.txt)
is the foundation for future NPCs, bosses, dialogue, environmental storytelling
and progression. The supplied profile is preserved verbatim. Its unresolved
questions remain open for explicit design decisions. Project implementation
guidance is in [AGENTS.md](AGENTS.md).

## Greefer: Griffin of Central Tower

Follow the north boulevard toward Central Tower. Greefer visibly rests on its
solid crown roof and detects the player on the tower approach (within 25 metres
of `(0,0,-44)`, including roofs/open air) when either eye has a clear sight line.
He alerts, speaks, launches and descends using continuous collision movement.
The existing district is the arena; no arena walls, separate level, movement
costs or cinematics have been added. His cyan faceted body, violet feathers,
hooked eagle beak, four taloned legs, wings and tail are articulated engine meshes.

Greefer has 1,800 HP and five committed, parryable techniques: Raking Talons,
Twin Rebuff, Crownless Wing, Territorial Rush and Falling Verdict. Windups last
0.48-0.80 seconds with short authored contact windows and recovery. He uses the
same impact-speed damage, guard chip, timed parries, one-second punish window,
fortitude, exhaustion thresholds and 25% defender strain as the player/Ember.
The creature adapter sweeps capsules along the rendered talons, wing feathers
or charging breast, then uses the shared hit resolver. It does not use the
player's generic reach sphere. Each target resolves once per legitimate pulse;
Twin Rebuff independently animates and resolves its left/right swipes. Opaque
terrain still stops hits. A dive commits to a world
position, allowing evasive movement after its tell. His defense reacts to
visible attack windups after a reaction interval, never queued player inputs.
Lock-on follows the active encounter's valid opponent. Unrelated residents,
sentries and Ember cannot be hit by Greefer's attack query.

Flight uses the real CharacterBody collision sweeps, bounded obstacle steering,
stall recovery and supported landing probes with full body clearance. Greefer
can land on existing rooftops and take off again to pursue Sky Jumps. Sight
updates every 0.18 seconds. Occlusion preserves only the last observed position;
after 12 seconds without sight, or leaving the supported district, he disengages
and flies home. Leaving does not clear the mandatory introduction. No position
warp is used for arrival, pursuit or return. Normal player defeat retains the
existing respawn transition.

Winning **or losing** the first confrontation records completion. A first-attempt
victory is preserved separately; no scripted loss or boss invulnerability forces
the result. Falling before any combat participation cannot skip the introduction.
The encounter's `can_progress()` opens the four outward road gates; the
original hub stays freely explorable before the confrontation.
After the fight, Greefer physically returns to his tower. Approach the violet
challenge sigil labeled **GREEFER / REMATCH** at `(5,0,-40)` and press **G / RT**.
Choose **Yes - challenge** in the live Ember-style confirmation for a
full-strength rematch. Left/right or controller D-pad chooses, Enter/A confirms,
Escape/B cancels. A returning Greefer can accept immediately; a victory's brief
defeat reaction finishes first. Inventory and Start cannot stack over the confirmation.
Later outcomes never erase the original first-encounter result. The latest
rematch result is saved separately and changes his next challenge dialogue.

Single-player outcomes are stored per inventory owner in
`user://encounters_v1.json`, with an atomic replacement and previous-save backup.
This journal is separate from inventory item ownership and cannot overwrite it.
Combat decisions, incoming/outgoing boss damage, completion and save writes are
host-only when a multiplayer peer exists. `snapshot()` exposes the encounter
state for a future host transport; this is not a complete multiplayer framework.
Menus continue running the encounter and world. NPC flee/watch reactions remain
future polish, and all existing resident routines continue unchanged.

The supplied [Greefer brief](docs/greefer_design_brief.txt) is preserved verbatim.
Editable dialogue lives in `scripts/territorial_encounter.gd`; move timings,
damage and recovery live in `scripts/greefer_moves.gd`. Normal launches enable
automatic approach detection. Isolated `--script` tests opt in with
`-- --boss-encounters` or set `boss_encounter.auto_trigger` explicitly; the
perched creature and roof still exist in the default test world.

The griffin presentation uses a sharp hooked eagle bill, swept crown/neck
plumage, narrow magenta eyes, feline haunches, independent wing wrists and a
segmented curved tail. Procedural shoulder/leg IK holds support feet during
grounded attacks, with distinct loading, striking and settling poses. Idle
breathing, gait, banking, flap/fold transitions, landing compression and shared
stagger reactions remain visual: they do not move the collision body or change
navigation. Set `Greefer.debug_combat = true` in the remote inspector or test
harness for attack/phase labels and the exact active capsule outlines. This is
off by default and allocates no debug geometry during normal play.

The supplied [animation/readability request](docs/greefer_readability_brief.txt)
is preserved alongside the original boss specification. Attack feel, the
silhouette from your normal camera distance and dodge/parry timing still need
your controller playtest; automated checks do not judge those subjective parts.

## Controls

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Move / walk | WASD | Left stick, partial deflection |
| Run | Hold Shift | Left stick, full deflection |
| Fast run | Press Ctrl | Click L3 / left stick |
| Driving boost | Press Ctrl while driving | Click L3 while driving |
| Vehicle light wall on/off | Press Tab while driving | Click R3 while driving |
| Look | Mouse | Right stick |
| Lock / unlock opponent | Press Tab | Click R3 / right stick |
| Switch locked opponent | I / J / K / L (up / left / down / right) | Flick right stick up / left / down / right |
| Jump / repeatable sky step | Press Space | Press A / bottom face button |
| Phase dodge | Press E | Press B / right face button |
| Use Health Glyph | Press H (or tap V+H) | Hold RT, tap B |
| Use strongest Shield Glyph | Hold V+H for 0.45 s | Hold RT+B for 0.45 s |
| Left-side attack | Left mouse button | LB |
| Right-side attack | Right mouse button | RB |
| Block / timed parry | Hold F / press just before impact | Hold LT / press just before impact |
| Special X / Y | Tap Q / R, attack on release | Tap X / Y, attack on release |
| Modified special X / Y | Hold V, tap Q / R | Hold RT, tap X / Y |
| Charged special (including modified) | Hold Q / R, then release | Hold X / Y, then release |
| Inventory / equipment | Tap B | Tap View / Back / Select |
| Dismiss lost-gear guide; start five-minute pickup expiry | Hold B for 0.7 s | Hold View / Back / Select for 0.7 s |
| Talk / collect nearby loot / shop / challenge Greefer | Press G | Tap RT nearby |
| Live system menu | Escape | Press Start |
| Yield in a duel | Press G | Start menu: Yield sparring duel |
| Draw / select weapon | Tap Down / Left / Right / Up arrows | Tap D-pad Down / Left / Right / Up |
| Sheathe / draw current weapon | Hold Down for 0.45 seconds | Hold D-pad Down for 0.45 seconds |
| Release / capture cursor | Open / close a menu | — |

Start in the central plaza facing north along the brighter grid boulevard.
The civic tower at `(0,0,-64)` has terraced foundations, a solid crystal monument,
six elevated ring walks and a large supported crown. Curved skyways sweep in
from the west/east, continue north along the avenue and join at an inclined
crossing. The west route rises to a common 16 m promenade around the civic tower;
both avenues join this complete loop. The southern curve ends widen into guarded
lookouts. Walk up the west stairs near `(-15,0,13.5)` to the 12 m route, or the
east stairs near `(15,0,16.3)` to the 16 m route. These are open-riser stairs with
physical treads, stringers and handrails. Sky steps can reach the higher rings.

The south-facing tower steps begin near `(0,0,-48)` and climb to the civic
platform at 3.12 m. Their visible boxes and collision now use thirteen 24 cm
risers: the former first step was 37 cm high, beyond the player's existing
29 cm step sweep. Movement speeds, controls and the controller are unchanged.
Walk up to the crystal pedestal and press **G / tap RT** for the **Tower
Exchange**. It offers Longsword + Shield, Spear, Katana, Twin Blades, Health
Glyphs and Eternal Scribe Robes, one per selection, all currently free. Purchases enter the existing
inventory without replacing equipped weapons; equip weapons from inventory.
Use A / Enter to acquire and B (controller) / Escape to leave. View opens
inventory and Start opens the system menu. The world continues running.

Authoritative prices are configurable in `scripts/tower_shop.gd`; paid offers
remain unavailable until a currency settlement is implemented. The loot service
validates registered offers, ownership, proximity, line of sight and living
combat state, and guards purchase notifications against reentrant grants.
Purchases use normal stack limits, Health Glyph counts and inventory saves.
`tests/tower_shop.gd` checks real walking/running/descent, keyboard/controller
menus, RT+B priority, host validation, reentrancy and checkpoint restoration.
All 35 checks pass at 30/60/120 Hz and in a native Compatibility window at
60 Hz. Another 222 inventory/model/loot/UI, Start-menu and metropolis checks
pass; the native exchange and stair views were also inspected visually.

Infinity banners, sixteen geometric trees, illuminated benches and ten additional
tall towers establish the denser metropolis seen in the supplied visual reference.
Lantern courts at `(east/west 68.7,0.16,38)`, north garden courts at `(east/west 43,0.16,-71.5)`,
and the south arrival court at `(0,0.16,77)` finish the outer avenues. Flush grid
inlays connect these destinations, with solid furniture, planting and gateways.
The original north-east rooftop stair route and Ember's east-side sparring area
remain in place. There are 46 ordinary city/skyline buildings plus the civic
landmark. The 224 m foundation and outer perimeter remain physical.

Every architectural volume has matching box or convex collision, including
skyway decks/undersides, railing beams, stair treads, tree branches, banner panels,
crystal, halo and roofs. Painted facade seams and short-lived light effects are
surface decoration. Falling below the world returns the character to the plaza.
Skyway guards follow the exposed boundary of the connected deck surfaces. Stair
portals are the exact stair width; shared bridge, curve and promenade junctions
remain open, with top rails, midrails and posts along the remaining edges.

## City residents

One hundred named artificial residents share the streets, lantern courts, gardens
and south arrival court: fifty use the original male silhouette and fifty use a
female silhouette with broader hips and a narrow-waisted torso outline. Body
profiles stay with each identity through indoor visits and are distributed
across all jobs and colors. Both use the same gait, collision and two mesh
batches; the female outline adds four instanced rods.

Forty-four start distributed over city routes: 32 occupy eight outer-city
neighborhoods and 12 begin around the hub. The remaining residents begin indoors
with staggered departures. The total outdoor cap remains 64, leaving at most
32 hub walkers while the outer groups remain present. Outer residents follow
local routes and rest outdoors rather than crossing locked progression gates
to reach a hub lobby. Hub errands favor quieter perimeter streets. After
several errands or pauses, hub residents walk into one of 22 building lobbies and
spend time indoors before returning. A rotating scheduler, doorway leases, local
destination limits and varied routes prevent synchronized departures or a single
plaza crowd. Identities, acquaintances, colors and conversation memory survive
these indoor/outdoor cycles.

The original eighteen characters retain their individual voices; additional
residents have unique names, roles and connected acquaintances. Acquaintances
greet one another, exchange short conversations, then resume their own routines.
These are local character sketches, without establishing new factions or answers
to the canon's unresolved history.

Approach a resident and press **G / RT** to talk. Their individual outlook may be
curious, friendly, pragmatic, dismissive or indifferent toward a human visitor.
Repeat interactions remember the meeting and refer to real acquaintances and
destinations. A readable dialogue panel appears on the left; walking away ends
the exchange naturally. Pickup collection and Ember's sparring invitation retain
interaction priority. Conversation, inventory and the system menu leave all
resident routines running.

Pedestrians use a shared graph with hub and outer-neighborhood street links,
validated against actual ground, curb heights and full capsule clearance. They
avoid neighbours, yield personal space to the player, and make room when they
observe nearby fighting with unobstructed sight. They use their own collision
layer, separate from architecture queries and combat hurtboxes. The current
populace is civilian ambient simulation; combat targets remain the sentries and
Ember. Roles do not yet introduce a trading economy or quest system. Conversation
memory and routines currently last for the running session.

Occupied waypoints no longer leave pedestrians walking endless circles. The
recovery check measures decreasing distance to the current waypoint, including
cases where avoidance cancels movement entirely. After 2.5 seconds without
progress, a pedestrian can bypass an intermediate point only over physically
validated ground, finish a public errand on nearby clear footing, or retry the
route. Doorway passages still require their complete entry path. Personal
stopping offsets replace the shared final marker, and passing bias is bounded
once per pedestrian instead of accumulating for every neighbour. Walking speed,
physical collision, identities and the existing simulation budgets are retained.

Rounded curb contacts also suppress downward floor snap until the heel clears
the edge, preventing premature snapping into the side of the raised paving.

`tests/resident_progress.gd` passes ten checks at 30/60/120 Hz and in a native
Compatibility window: occupied intermediate points, an eight-person crowded
stop, subsequent dispersal, curb descent, solid-wall clearance, walking speed,
seated hip placement and safe standing. Native bench views are saved as
`captures/routing_bench_side.png` and `captures/routing_bench_front.png`.
The 300-second flow run circulated all 100 identities, with 124 entries and 141
exits across all 22 buildings, no unsupported falls or contact-tolerance failures,
and at most six pedestrians in a six-metre cell (seed 1893, 60 Hz).

Body colors are randomized from violet, cyan, blue, purple, gold, orange, red,
green, mint, pink and white, with small brightness variations. Every color family
appears in the roster; color does not determine attitude or affiliation. Orange
residents emit a small, shadowless local light near the player, retaining the
orange-means-light convention without adding distant light overhead.

Lobbies have actual open doorways, colliding floors, jambs, privacy screens and
roofs. Residents walk the full passage; activation/deactivation happens behind
the screen only when the active camera cannot see their body. A player watching
inside prevents that handoff. The rest of a building's interior is represented
by a logical indoor stay, not a fully furnished interior. Rooftop outlines and
collision heights remain intact. Lobby faces are batched into two draws per
building while every structural box remains separately auditable.

Two instanced mesh batches per resident share simple geometry. Distant animation
updates at 15/30 Hz, local neighbour lists refresh at 5 Hz, and navigation probes
are staggered while physical travel remains active. Indoor bodies disable
rendering and collision. No per-resident motion-retrieval requests are made.

## Inventory, equipment and loot

**Eternal Scribe Robes** are the first wearable clothing. Buy them free from the
bipyramid's **Tower Exchange** (G / tap RT), then open Inventory (B / View),
choose **Armor / Cosmetics**, select the robes and **Wear in Body**. The
Equipment tab also supports Body -> Change clothing / Unequip. Clothing
coexists with all four weapons and persists in the existing inventory save;
older saves without a Body assignment still load without a migration grant.

The robes adapt the code-native Eternal Scribe garment from the sibling Infinite
Library project into a fitted open jacket: a wrapped torso, narrow scholar's hood
and collar, articulated sleeves, a belt and a small hip tome. Four separate,
angular coat tails follow the hips and legs through running, Sky Jump, sitting
and mounted poses. Silver edges, the geometric back sigil, six front and six back
tail inscriptions, twenty falling inscriptions across the torso and articulated
sleeves, twelve pooled specks and nine trailing symbols retain the
Scribe's identity. Their +Z-facing fit follows this game's existing character
rig. Motion drives visual flow only; there is no cloth physics, armor bonus,
movement cost or additional collision. Symbol meshes are cached, and stable
mesh instances preserve phase fades. The upper inscriptions follow the wrapped
jacket and sleeve surfaces, using the lower panels' mathematical/geometric
symbol pool, colors, descent, pulse and regeneration cycle. Their paths leave
the open front, central back sigil, shoulder caps, cuffs and hands clear.
Unequipped clothing hides every sleeve and stops its process callback. Geometry
is built only after the first equip, and the game has no runtime dependency on
Infinite Library files, commands or saves.

The Body slot uses normal owned item identities, host-validated equipment,
transferable gear drop/death rules and checkpoint persistence. Inventory and
store menus keep the world live. `tests/scribe_robes.gd` covers the complete
purchase/wear/unequip/save/drop loop, old-save compatibility, articulated sleeves,
two-handed combat grips, jumping/Sky Jump and phase restoration. Native front,
back, inventory and store previews are available through its `--capture` option.
All 31 clothing checks pass at 30/60/120 Hz and in a native Compatibility
window at 60 Hz. Another 411 inventory, store, combat-motion, grip and menu
regression checks pass. Front/back clothing and both UI previews were reviewed.

The fitted adaptation adds **21 checks at each of 30/60/120 Hz**, plus a native
Compatibility run and nine reviewed front/back/side, upper-body close-ups,
running, Sky Jump, seated and motorcycle captures
(`tests/fitted_robes.gd -- --capture`). It measures the
actual wrapped fabric and limb attachments, independent tail motion and fixed
mesh pools. The outfit uses 117 mesh instances and 942 fabric vertices; it adds
no colliders and keeps the existing owned Body item.

Press **View / Back / Select** (Godot `JOY_BUTTON_BACK`, button 4) or keyboard
**B** to open the field kit. Inventory has six categories and eight rows per page;
Equipment shows the four D-pad assignments, Body, Head, Hands, Legs and two rings. Left stick/D-pad or arrows navigate,
**A / Enter** opens item actions, **B / Escape** backs out, **LB/RB** changes tabs,
and **LT/RT** or Left/Right changes categories. Use the Equip action to assign an
owned weapon to any direction; use Drop to choose a stack quantity or drop one
specific weapon. Mouse buttons work too. **F5 / Save** writes a checkpoint.

The owned-item list also uses the Tower Exchange's weapon groups: Daggers,
Swords, Heavy, Polearms, Paired, Other, Scribe, Discs and Paintbrushes. Armour can
be filtered by Body, Head, Hands, Legs or stored patterns; consumables by Health,
Shield or Respawn Glyphs; Miscellaneous by Rings or Other. Choose a type from the
dropdown, press controller **Y**, or use **F / Shift+F** to cycle forward/backward.
The Exchange and inventory share the weapon-group definitions, including the
original longsword/shield under Swords.

Click the search box or press **/** to search owned names and readable item types.
Search intersects the selected category and type. **Enter / Escape** leaves text
editing; **Reset** clears both filters. Filters remain when closing/reopening or
visiting Equipment; changing category starts at All with an empty search. Exact
item selection clears restrictive filters to reveal that instance. Every result
still represents an owned instance, with its normal equip, use, drop and host
validation rules. Empty results cannot act on a previous item, and removing an
item while its actions are open closes those actions. Rows remain bounded to
eight per page. `tests/inventory_filters.gd` and `tests/inventory_search_input.gd`
cover filtering, live ownership changes and actual text/controller routing.

Inventory keeps the world running in both solo and network play and suppresses
local gameplay inputs only. Opening cancels
held attacks; closing cannot leak a dodge, jump or weapon selection. Triggers
must return to neutral before gameplay resumes. View replaces its old talk/yield
binding: **G / RT** still interact. **Start** opens the live system menu, which
includes a Yield option during a sparring round.

On a fresh local save, four demo pickups are on the east sidewalk around
`(13,0.2,18)` through `(13,0.2,25.2)`: Light Shards, a Signal Tonic, a protected
Civic Access Glyph and a separate upgraded katana. Approach and press **G / RT**.
A pickup notification confirms successful collection. Materials/consumables
stack when type, upgrade and custom properties match. The Signal Tonic, Cyan
Mantle Pattern and material items remain collectible data; no crafting/armor-stat or
upgrade mechanic is added here. Existing weapon damage and movesets stay intact.

Item definitions are native `Resource` data in `item_definition.gd`, built by
`ItemCatalog` in `item_catalog.gd`. Definitions hold `item_type_id`, display name,
description, category, optional icon, stack limit, equip/drop/trade flags and
static properties. `ItemInstance` holds its unique `instance_id`, type, quantity,
upgrade level, custom properties and current `owner_id`. Instance IDs survive
equipment transfers and full-item drops. A partial stack receives a new identity.
Upgrades/custom data persist; they do not silently change combat tuning.

To add an item, add a catalog definition in `ItemCatalog._prepare()`, for example:

```gdscript
_add(&"azure_shard","Azure Shard","A cold fragment of stable light.",&"materials",99)
```

A weapon definition links to an existing moveset with
`custom_properties["weapon_slot"]` (`down`, `left`, `right`, `up` are canonical
longsword/shield, spear, katana, twin blades). Inventory D-pad assignments resolve
to those existing profiles in `CombatIntent`/`WeaponCombat`; there is no second
combat weapon manager. Empty slots show empty hands and cannot create attacks.
One instance occupies at most one direction. Voluntary equipment changes obey
the same forced-reaction permission as combat weapon switching.

Place `scenes/item_pickup.tscn` in a level and set `item_type_id`, quantity,
upgrade level and custom properties in the inspector. The authority adopts it
through the same transaction path as manual drops. Pickups use simple static
geometry, with no rigid-body simulation or continuous inventory polling. Manual
drops require nearby supported, visible clear space; failed placement leaves
the original item and equipment assignments intact. Nontransferable definitions
set `is_droppable` or `is_tradeable` false; protection never depends on a name.

Actual deaths have a **15%** default chance to lose one eligible equipped weapon.
Set `world.death_drop_probability` in the main scene inspector, or set the loot
authority's exported `death_drop_probability` directly. Zero disables losses;
one guarantees a loss when eligible gear exists. Stored unequipped items are not
eligible. Death tokens and the player death gate prevent repeated rolls; respawn
does not remint lost gear. Nonlethal Ember rounds never apply this penalty.

`LostItemMarkers.for_owner(owner_id)` supplies marker dictionaries with pickup ID,
item identity and world position for a future map. A persistent bottom-screen
readout locates the latest undismissed loss using the same grid as the main HUD;
a brief notice also reports new losses. Markers disappear when anyone collects the
item or it is legitimately removed. Trading drops create no loss marker; acquired
items belong to their new possessor and are not permanently tracked.
Dismissed death drops retain their item identity and marker metadata until
recovery or expiry. `dismissed` / `expires_at` marker fields hide their HUD guide;
`loss_dismissed` / `loss_expires_at` checkpoint fields preserve the absolute
deadline. The host owns disappearance even while that item's area is inactive.
`loot_authority.dismissed_loss_lifetime` configures the default 300-second grace
period. `tests/lost_gear_expiration.gd` checks the lifecycle and host boundaries;
`tests/lost_gear_dismiss_input.gd` checks real Select/keyboard input, interruptions,
checkpoint restoration and the first press after a death-choice screen.

Normal local play automatically saves a versioned **whole checkpoint** at
`user://inventory_v1.json`: owned instances, assignments and unclaimed world drops
are committed together, after transfers finish. F5 saves explicitly. Loading
validates all identities before mutation, restores both sides or rolls back, and
derives markers from actual unclaimed drops. Failed loads do not mint replacement
starter weapons. A temporary file/backup protects interrupted writes; shutdown
cleanup cannot overwrite the checkpoint with disappearing world pickups.
Command-line `--script` test/capture tools isolate ownership by disabling automatic
local save/load; they may test explicit checkpoints at temporary paths.

`LootAuthority.request_pickup`, `request_drop`, `request_equip`, `request_unequip`
and `resolve_death` are the host-validation boundary. `host_enabled` and a validator
callable gate mutations; synchronous claim/transaction guards reject rapid and
reentrant transfers. Future peer sessions must forward requests to their host and
derive inventory ownership from authenticated peers. Local checkpoints cannot
restore or save authoritative multiplayer ownership. Actual networking, full map
UI and additional item-use systems remain future work.

Created: `item_definition.gd`, `item_instance.gd`, `item_catalog.gd`, `inventory.gd`,
`inventory_store.gd`, `item_pickup.gd`, `loot_authority.gd`, `lost_item_markers.gd`,
`inventory_ui.gd`, `inventory_session.gd`, the pickup scene, and five inventory
test/capture scripts. Modified: world/player/input setup, combat intent/resolution,
weapon rig/HUD, fall-reaction weapon identification, sparring integration, the input
map and its old View-to-talk regression fixture. The only new project InputMap
action for inventory is `inventory_toggle`; menu navigation uses UI events.

## Live system menu and recovery

**Start / Escape** opens a black/cyan system overlay with Resume, Settings,
Unstick and Quit Game. It never pauses the world; local movement/combat/menu
button presses are suppressed while it is open, but gravity, opponents and world
timers continue. B/Escape backs out of Settings or closes the overlay. Opening
Start from the inventory switches between the two live overlays;
Escape inside inventory retains its existing Back behavior. Sparring adds a
Yield button, and keyboard G still yields directly.

Settings change mouse/controller look sensitivity, camera distance, field of view, master volume,
camera impact shake, streetlight shadows, neon glow and 3D resolution immediately.
Camera distance defaults to a closer **4.2 m**, adjustable from **2.4 to 9.0 m**.
Vehicle views use 1.45 times that distance, with a minimum that clears the
vehicle body, and restore the same on-foot preference on exit. The collision-aware
spring arm, free orbit and lock-on framing still apply; changing distance does
not change field of view.
Normal play saves these values in
`user://settings_v1.cfg` when leaving settings/the menu or quitting. Script tools
use explicit temporary setting paths so they do not alter normal user settings.
Quit Game saves the local inventory/world checkpoint and settings before exit.

An existing inventory checkpoint loads after the outer world has been built and
its collision data has synchronized. Startup briefly gates local actions and
saving while this transaction is pending; world time continues. A dropped item
in the outer city consequently cannot make valid owned inventory fail to load
merely because its supporting terrain was not built yet. Item identities,
ownership, world-drop clearance and corrupt-file checks remain strict.
`tests/inventory_startup.gd` verifies valid distant drops, owned clothing/glyphs,
resumed autosave and unchanged corrupt sources with **20 checks at 30/60/120 Hz**.

Unstick checks the actual full-height capsule and several supporting floor rays.
It searches nearby clear ground, rejects narrow rail/post tops and low headroom,
and falls back to previously verified stable footing when embedded in a large
solid. It preserves health, equipment, ownership, exhaustion and forced combat
recovery. It clears unsafe carried velocity and stale landing/pose anchors after
relocation, without using respawn or triggering equipment loss. Clear ordinary
ground and unobstructed freefall do not trigger relocation. Floor history is
sampled four times per second while grounded, rather than searching every frame.

`scripts/start_menu.gd` owns the overlay/settings; `scripts/unstuck.gd` owns physical
recovery. `system_menu_toggle` is the new Start/Escape InputMap action.

## Weapons, guards and specials

These are the default assignments; the Equipment menu can move each owned weapon
to any D-pad direction while keeping its authored moveset.

| Direction | Loadout | X / Q | Y / R | RT+X / V+Q | RT+Y / V+R |
|---|---|---|---|---|---|
| Down | Longsword + Shield | Citadel Wheel | Glyphbreaker | Aegis Bloom | Sky Bastion |
| Left | Spear | Helix Lance | Orbit Reaper | Prism Skewer | Constellation Rain |
| Right | Katana | Neon Crescent | Crossed Horizon | Afterimage Waltz | Zero-Line Sever |
| Up | Twin Blades | Binary Cyclone | Mirror Fang | Shatterstep Lattice | Twin Comets |

The longsword has a right-hand cleave and left-hand shield strike, broad circular
cuts, a ground glyph, a defensive shield bloom and rising glyph pillars. The spear
has long thrusts and reverse haft swings, a three-hit spiral, a full orbit, a narrow
seven-metre skewer and a descending spear constellation. The katana has precise
returning cuts, a crescent, crossed cuts, three afterimage strikes and a charged
long-range sever. Twin blades alternate hands, with a three-hit cyclone, crossed
fangs, a four-hit lattice and twin spiralling comets. The inventory lists each
weapon's arts. These are initial tuning values for playtesting.

All sixteen specials now support **hold to charge, release to attack**. A quick
release before 0.4 seconds executes the existing move with its existing timing
and damage. Holds from 0.4 to 1.2 seconds build an extended version; at 1.2 seconds
the charge is full. Holding longer never auto-fires. Whole-body windup and a brief full-charge glyph give feedback. Movement, jumping
and target-facing locomotion remain responsive while holding.

An extended special keeps its weapon's animation/effect profile, adds one finishing
damage pulse, increases per-hit damage by up to **65%**, reach by up to **30%**, and
duration by at least **35%** at full charge. Release begins with a short 0.1-second
contact delay. Partial charges scale between the threshold and full charge. The
normal per-impact momentum multiplier applies to every charged contact as well.
Weapon switching, sheathing, block, dodge, a basic attack, focus loss and controller
disconnect can cancel a held charge; releasing a cancelled hold cannot cast it
later. Starting another special replaces the earlier hold. The RT/V choice is
captured on the initial press and remains fixed through release.

Each attack has a windup, one or more explicit damage windows and a recovery.
Weapon reach and directional arcs select physical hurt volumes; a terrain ray
blocks damage through walls. Radial specials can hit behind the player. Visual
glyphs and blade trails expire automatically and do not create platforms.
Unlocked attacks aim along camera yaw, fixed at activation; guard follows the
current camera yaw. While locked, both track the current opponent. Vertical
camera pitch does not tilt the player's capsule.

R3/Tab toggles lock-on to a living, visible opponent within 32 metres, preferring
the centre of the screen. White/cyan brackets identify the target.
Forward input approaches, backward input backpedals, and sideways input strafes
around the opponent. Diagonals retain their normalized magnitude. The visual
root faces the target even at rest, during attacks, jumps and dodges; the collision
capsule remains upright. Existing acceleration, analog speeds and aerial momentum
are retained. Foot placement still follows actual travel; lean and arm swing
adapt to lateral/backward travel. The exaggerated sprint lean applies forward.

The camera smoothly tracks the opponent over the right shoulder using its existing
collision-aware spring arm. A lateral sphere sweep keeps the shoulder anchor clear
of adjacent walls. Right-stick flicks select an opponent in the corresponding
**screen direction**; I/J/K/L do the same on keyboard. The stick must return below
25% of filtered travel before another flick past 65% can switch. Empty directions retain the
current target. Only visible, living targets can be acquired/switched to. Walls
hide the brackets immediately and release lock after 0.35 seconds of continuous
obstruction. Defeat, removal, leaving range, focus loss and respawn release lock.
Unlocking restores free camera look and movement-facing locomotion. Spin skills
retain their existing hip/shoulder choreography around the target-facing root.

Every actual damage pulse samples the player's **current physics velocity**, with
horizontal and vertical speed contributing equally. Initial tuning is
`damage = weapon_base_damage * (1 + speed_m_per_second * 0.5 / 10.2)`.
Standing hits retain base damage; walking at 3.5 m/s adds about 17%, running at
7.5 m/s adds 37%, and full sprint at 10.2 m/s adds 50%. Accumulated sky-step/fall
speed keeps increasing the bonus without a cap. Each hit of a multihit skill
resamples speed; windup speed is never cached. Teleport displacement contributes
no artificial speed. The `momentum_damage_gain` export in `weapon_combat.gd`
controls the bonus without changing movement. Existing hit timing, reach, arcs,
terrain occlusion, health limits and guard/parry/dodge rules still apply.

Floating numbers show damage actually applied (including remaining-health limits).
The combat component records the last successful impact's damage, speed and
multiplier for inspection; these debug values do not occupy the gameplay HUD. Numbers expire after 0.85 seconds
and are limited to 24 at once.

Hand-held wireframe weapons follow the existing forearms. The katana uses a
shared two-handed grip. Its relaxed carry follows
[Waki-gamae](https://www.kendo-guide.com/kendo_kata_yonhon.html): hands beside the
right hip, blade trailing backward and slightly downward rather than in front.
The off hand follows a point 17 cm behind the primary grip throughout cuts,
specials, guards and traversal. The shared grip stays within both arms' reach.
Carry angle adapts to sprint lean and actual floor clearance without wrist flips.
Grip orientation changes only the local basis, preserving each wrist's fixed
attachment position. Reassigning a global basis used to round-trip its origin
through the parent transform each frame; floating-point error accumulated into
visible weapon drift in distant districts. Both ordinary grip orientation and
katana floor-clearance corrections now use the position-preserving path.
`tests/weapon_grip_drift.gd` verifies 24,000 changing poses at each of three
world locations (including both far corners), unchanged blade orientation and
all four weapon hit-segment anchors. The previous implementation failed the
attachment checks; the corrected path records zero local-position drift.
Verification passes 21 attachment checks, 146 combat-motion checks, 123 weapon
checks and 38 dodge/sky-step checks. Native Compatibility captures retain the
existing twin-blade grips and two-handed katana stance.
Sheathed longsword and twin-blade tips angle downward across the back. The katana
has a wireframe saya on the left hip, with the hilt forward and its tip angled
backward/downward. Its mount follows the pelvis rather than chest motion.

Combat poses now involve the whole body: knees load, the pelvis shifts onto a
supporting leg, hips lead the shoulder release, and the torso follows through
before settling. Thrusts brace into a staggered stance; heavier strikes compress
deeper; rotating skills use a full body turn with alternating step-and-plant
contacts. Foot targets are projected onto real collision surfaces. Supported
ankles stay anchored during the drive, with knee direction following the hip
pivot. Unsupported space at a roof edge cannot create a planted foot. Turning
a held guard replants the stance. Movement blends back into the existing gait;
jumping releases the floor anchors immediately and retains the aerial leg pose.

The design reference is [Everstone's Where Winds Meet combat-design breakdown
and embedded performance/gameplay clips](https://blog.playstation.com/2025/09/25/how-where-winds-meets-wuxia-inspired-combat-turns-the-umbrella-into-a-weapon/).
The staged load, coordinated hips/shoulders, planted support and follow-through
are our interpretation of that reference, implemented procedurally for this
stick-figure rig. No game animation data or assets are imported.

The underlying gait transforms are restored each tick before the combat pose is
applied. Combat adds no root movement or velocity changes; sprint, falling,
landing, sky steps, camera and dodge retain their existing physical behavior.
Weapon geometry follows the phase fade and restores its materials on exit.
Switching, sheathing, blocking or dodging cancels a move before future damage
windows. One late attack can buffer for up to 0.4 seconds; buttons do not repeat
automatically. This prototype has no stamina or special-resource restriction.

LT/F mitigates frontal damage within 70 degrees either side of camera forward
(toward the selected opponent while locked):
85% with sword/shield, 60% spear, 70% katana and 55% twin blades. Rear attacks
remain unguarded. Aegis Bloom grants 95% all-direction mitigation for its first
0.65 seconds. Sheathed unarmed guard mitigates 25%. The player and Ember have
**1,000 base/max HP**. Player depletion returns the character to the plaza and
restores that maximum; sparring follows its nonlethal round rules. HUD health and
duel resets use `weapon_combat.max_health` rather than a separate display value.

A fresh LT/F press opens a **0.18-second timed-parry window**. A positive-damage,
parryable frontal hit during that window is fully negated. A confirmed contact
resolves exactly one outcome: perfect parry, normal block, or clean hit. Hidden
teleport frames and invalid/non-damaging contacts produce no defensive impact.
Each authored hit pulse can resolve only once per target; later explicit pulses
in a multihit move remain distinct. Holding block or trigger noise cannot reopen
the parry window; release and press again. Aegis Bloom retains its automatic
mitigation without becoming an automatic perfect parry.

A perfect parry immediately cancels the **actual attacker's** current move,
remaining hit pulses, buffered follow-up and charged special. It opens a
**1.0-second** punish window.
The shoulders open, weapon recoils, and hips sink over supported feet. The katana
retains its shared two-hand grip. The reaction follows the incoming direction and
settles after the mechanical window. No outside animation assets are imported.
Parries bypass exhaustion and fortitude and do not damage the defender.
Gold contact sparks, a sharp synthesized metallic clash, seven reference frames
of visual hitstop, a small directional camera jolt and full-body stagger
make the initiative change readable.

Ordinary blocks preserve the existing weapon-specific reduction, including chip
damage, and preserve the attacker's move timing. A short additive weapon/body
recoil accompanies the dull impact. Striking a guard accumulates **exhaustion on
both participants**: the attacker receives the existing full contact penalty;
the basic-guard defender receives **25%** of that penalty. Tune the defender's
`combat_rules.defender_exhaustion_multiplier` independently of attacker balance.
The share uses the full penalty before either meter clamps at capacity. Default
capacity is 100; each contact adds to the attacker
`clamp(10 + move.damage * 0.4, 14, 40) *
(0.6 + defender.guard_strength() * 0.4)`. Six stationary Royal Cleaves against a
shield exhaust the attacker. Either participant reaching the threshold uses the
existing exhaustion consequences: offense is cancelled and the
character drops to one knee for **1.8 seconds**, taking **1.35? damage**. Recovery
returns the meter to 25%. After one second without another guarded impact,
reduced exertion recovers 14 points/second; attacks, held specials, teleporting
and boosted running pause recovery. The HUD shows the player's meter.

Holding block adds no strain and permits existing recovery. Misses, unguarded
hits and successful parries add no guard-related exhaustion; the attacker still
suffers the existing parry reaction. Each legitimate multihit pulse resolves its
own strain once per target, including when several body shapes overlap. Aegis
Bloom's automatic mitigation retains its previous behavior; defender strain
requires an active frontal basic guard. Player and Ember share this same hit
resolver and existing meter. Movement, attacks, sprinting, Sky Jumps and dodging
have no exhaustion cost. The thin exhaustion bar beneath HP displays this existing strain meter;
there is no stamina or MP resource.

Clean RB/LB light hits apply health damage without hit stun, including all combo
stages and aerial variants. They preserve the defender's attack, charge, buffered
input and movement, with only a brief visual impact response. Guard strain and
successful parries retain their existing rules and one-second attacker opening.
Weapon arts compare authored move strength with the defender's effective
fortitude. Weapon choice, attack phase, heavy techniques
and charging contribute to resistance. Meeting/exceeding fortitude interrupts
offense and produces directional hit stagger (about 0.2?0.65 seconds according to
move and charge). Resisted hits preserve attack/cancel continuity and add a small
impact response; hyper armor never negates health damage. Forced states expose
zero fortitude. State priority is defeat, parry, exhaustion, then hit stagger;
a lower-priority impact cannot replace or extend a higher-priority punish window.

During forced recovery, attacks, charging, blocking, weapon switching, sheathing,
dodging, steering and jumping are unavailable. Input permission is checked before
weapon/guard state changes. Ordinary defensive and weapon cancels remain intact
outside forced states. Existing carried momentum, gravity and capsule collision
continue. Player and Ember use the same resolver, meters, timing and permissions;
the AI still reacts only to visible attack windup, never hidden player input.
Focus loss, respawn and nonlethal round cleanup clear forced pose/hitstop state.
Legacy two-argument damage callers never infer an attacker from lock-on.

Confirmed health impacts now eject **neon red and orange sparks**, including
chip damage through a guard. Each spark flies independently away from the contact,
loses speed, arcs downward and fades on its own schedule. Tapered streaks and
bright moving heads replace the old expanding radial stamp. Launch velocities,
short emission delays and 0.26-0.58 second lifetimes vary across the flight.
Parries retain a distinct warm gold/orange palette. These are light fragments.

`spark_burst.gd` renders each active flight in one additive, camera-facing mesh.
Up to 28 sparks use a time-based flight equation and cached arrays. The central
`impact_feedback.gd` reuses 12 flight meshes and four spatial audio voices; no
particle physics bodies or runtime sound imports are needed. The actual confirmed
body hurtbox and incoming direction seed the presentation. The struck collision
shape is carried with each hit event. Because the movement capsule is wider than
the stick figure, damage contact is projected onto the defender's visible torso
at the registered hit height; it never uses a weapon grip transform. Guarded chip
sparks use that body point too. Sparks do not affect damage,
parry timing or hitstop. Cached audio still combines metallic/strike and bass layers
with headroom at the four-voice limit.

Hitstop holds only the involved characters' procedural visual progression.
Combat clocks, contact resolution, movement, gravity, collision and unrelated
world systems continue. Light/block pauses default to 2.5/60 seconds, heavy and
exhaustion to 6/60, and parry to 7/60, independent of frame rate. Cosmetic camera
offsets do not change camera yaw/pitch, lock-on direction or collision probes.

All thresholds, recovery values, punish duration, vulnerability, hitstop and
feedback toggles live in `scripts/combat_rules.gd`; each actor owns an independent
Resource instance with the same defaults. Set
`player.weapon_combat.rules.camera_shake_enabled = false` to disable shake, or
`impact_audio_enabled = false` on both duelists' rules for silent impacts. Move strength/stagger data and
charge scaling live in `weapon_library.gd`. Existing TED-RAG pose gains continue
to drive locomotion; confirmed reactions compose over the established pose/IK
system without a new retrieval service or physics framework.

Tap a direction to select and draw that weapon, including a previously sheathed
loadout. Down selects sword/shield on **release** after a short press. Holding
Down for 0.45 seconds toggles the **current** weapon between sheathed and drawn
without selecting sword first. Holding longer does not toggle repeatedly, and
releasing afterward does not change the selected slot. Its stowed model sits on
the back/hip. **Any attack input draws that same weapon**: LB/RB and mouse attacks
execute on press, while specials prepare on press and execute on release with
the accumulated charge. An attack while guarding draws the weapon
and retains guard; it does not override the held block. Another direction cancels
an unfinished Down gesture; focus loss and controller disconnect cancel it
without a false tap.

Three solid magenta practice sentries stand on the north avenue at
`(-5,0,-35)`, `(0,0,-38)` and `(5,0,-35)`. Each has 120 HP, flashes on contact and
reboots two seconds after depletion. They remain solid while rebooting. The
center sentry counters for 10 damage every 2.6 seconds while within 2.65 metres,
with a brighter 0.65-second warning. It respects walls and frontal guards. The
outer sentries are passive. They remain separate practice targets; their counter
is suspended during a sparring duel.

## Ember: sparring duels

**Ember**, an orange stick-figure partner, waits on the east sidewalk at
`(14,0.12,-35)`, beside the practice sentries. The partner has a solid capsule,
orange body material, katana sheath and a real orange point light. Approach
within 2.8 metres on the ground with clear line of sight and press **G / RT**.
Ember asks **"Do you want to fight?"** with Yes and Not now buttons. Use the mouse,
Left/Right or D-pad to choose, Enter/A to answer, or Escape/B to decline. Gameplay
input is suspended while the invitation is open. Combat starts only after Yes.

Both fighters begin a round with 1,000 HP and lock onto each other. Ember reuses
the player actor, articulated poses, four weapon loadouts and all 24 base attacks,
including all sixteen specials and their charged versions. Its input brain can
approach, strafe, backpedal, fast-run, jump, sky-step toward elevated opponents,
block/parry and teleport-dodge. Momentum damage, hurt volumes, terrain occlusion,
guard mitigation and the hidden dodge immunity window are shared with the player.
The brain cycles through the arsenal and reacts after a short telegraph delay;
it has no direct damage or movement shortcut. Pursuit uses local steering and
obstacle/jump checks, rather than a city-wide navigation mesh. Advanced AI route
planning and balance remain playtest areas.

Idle Ember cannot be locked onto or hurt by stray swings. During the duel, the
fighters damage each other rather than the practice sentries. The HUD shows
Ember's health; **G or Start menu > Yield** yields. Either knockout ends the nonlethal round,
restores the player's pre-duel health and returns Ember home, sheathed and ready
for another invitation. Leaving a 60-metre radius of the sidewalk position, losing
application focus or respawning also ends the round. Held charges, queued attacks,
guard state, phase immunity, targeting and duel hurt layers are cleaned up.

RT is contextual: a fresh trigger press talks to idle Ember when nearby. Outside
that interaction context and throughout a duel, RT remains the X/Y special
modifier. RT does not yield from a fight; G or the system menu does. Interaction uses the same
55% press / 40% release thresholds as other trigger input. Holding RT through a
declined invitation cannot reopen it until the trigger is released and pressed
again.

## Combat input contract

Combat inputs now reach `player.combat`, which emits
`action_requested(action, weapon_slot)`, `block_changed(held)` and
`weapon_slot_selected(slot)`. Available action identifiers are `attack_left`,
`attack_right`, `special_x`, `special_y`, `special_rt_x` and `special_rt_y`.
`player.weapon_combat` executes those commands using `weapon_library.gd`'s
authored timing, reach, arc, damage and visual profiles. The compact HUD displays current health, exhaustion and grid address; the weapon model
and inventory show the selected equipment.

LT/F is a held state. Analog triggers activate at 55% and release at 40% to avoid
jitter. RT/V is sampled when the special button is pressed; a modified special
emits only its modified command. Releasing RT before the physics tick does not
change that request. Holding a bumper or special button does not auto-repeat.
Special press/release requests carry a source token, so only the current hold's
release can execute it. `charge_started(action, slot)` prepares the visual windup;
`action_requested` fires on release, with `released_charge` available during that
callback. Timers advance on physics delta. AI controls use this same contract.

Arrows and the D-pad select the matching slot, independently of movement, with
the Down tap/hold distinction described above.
Requests retain their event order, so a slot selection followed by an attack in
the same physics tick uses the selected slot. Selection also remains responsive
during the phase dodge. Focus loss, respawn and controller disconnect clear held
combat input appropriately. A click used to recapture the mouse does not attack.

## Orange street lighting and solid structures

Orange wireframes identify actual light sources. Sixteen orange streetlights line
the crossing avenues; their bases, poles, arms, housings and emitting panels are
solid. Each fixture emits a downward orange spotlight; the configurable nearby
shadow budget selects its shadow casters. Cyan remains
the ordinary structural edge color. Opaque surfaces now receive lighting while
retaining a faint dark emission so silhouettes remain readable outside lit areas.

The old skyline's explicit non-collision flag was removed, and the shared box
builder no longer has a collision opt-out. The ground extends beneath those towers
and the perimeter encloses them. Structural meshes and full-volume physics shapes
use the same dimensions and transform; roof collision is part of each closed box.
Existing movement, animation, controls, stairs and central layout are unchanged.

The foundation uses 32 m surface tiles so no surface intersects more than eight
spotlights, respecting the Compatibility renderer's default
[per-object light limit](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html#light-number-limits)
without raising shader limits. Short-lived digital-glass jump effects remain
visual effects rather than permanent structures.

The metropolis adds 38 small orange architectural lights to the existing street
fixtures. Warm handrails, banner luminaires and bench strips have actual local
light sources. New lights do not cast additional shadows. Static solids/edges
are batched in 16 m spatial cells, including height; broad plazas and crossings
have separate batches so unrelated lights do not accumulate on one mesh.
All lit world meshes were checked against the eight-spot/eight-omni object limits.

Black paving uses a less rough material. A small Compatibility screen pass adds a
soft halo around bright 3D edges and moving sparks; it runs before the HUD. Set
`world.neon_glow_enabled = false` before scene readiness to omit this pass. It uses
Godot's documented [screen texture mipmap sampling](https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html).
The weapon panel has a dark backing, and the title/help have outlines to keep text
readable against the denser wirework. Controls and displayed attack names are unchanged.

## Fast run and digital sky steps

Press Ctrl or click L3 to toggle fast running. A second press toggles it off;
releasing movement also cancels it. Existing walking and running top speeds are
3.5 and 7.5 m/s; fast running reaches **10.2 m/s** with a deliberately exaggerated
forward lean, trailing arms, and a quicker stride. The collision capsule and
camera stay upright. Analog deflection still scales the requested speed.

Press jump again at any point in the air to sky-step. Every fresh press adds
an impulse to the existing velocity, with no jump allowance, stamina meter,
speed cap, cooldown or altitude limit. The default impulse is **9.2 m/s upward**
plus **3.4 m/s** in the camera-relative input direction, scaled by analog input
magnitude. The forward boost is 15% lower than the previous 4 m/s setting.
A step from zero vertical speed rises about **1.85 m**, one capsule height, at
the default 60 Hz physics rate. Chained steps retain additive momentum, so the
height gained varies with the vertical velocity already carried.
Repeated steps build momentum; opposing kicks cancel carried velocity before
accelerating in the other direction. Gravity continues between presses, so a
fast fall may require several kicks to reverse. A grounded jump retains its
established 7.5 m/s launch.
Holding jump does not auto-repeat. Air steps alternate the stamping leg and the
opposite forward-driving arm, without resetting the body pose. Kicks leave
a translucent digital-glass tile with cyan fracture edges and circuit etchings.
The glass normal follows the impulse direction; its size and fracture response
reflect impulse strength. Its facets fade in 0.62 seconds. These are visual footholds;
ceilings and other solid geometry still block the player. At most 12 tile effects
remain active, independently of the unlimited jump mechanic.

Horizontal momentum follows the **normal Traveler controller** in
`../infinite-library/scripts/traveler.gd`: each velocity component approaches its
camera-relative target at **9 m/s² normally** or **20 m/s² in fast-run mode**.
Grounded walking/running/sprinting retain that controller. In the air, directional
steering inherits any speed already carried above the nominal ground pace; it
does not pull accumulated sky-step momentum back to 3.5/7.5/10.2 m/s. Releasing
input retains the established gradual braking toward zero. Impulses are added
after steering/gravity, without normalizing or truncating physical velocity.
This builds on the Library's regular movement rule and sprint speed
with an independent local implementation. Guardian recovery/skid and the
three-jump limit remain separate Library systems.

## Phase dodge

Press **B** on the controller or **E** on the keyboard for a short phase teleport.
Movement input selects a camera-relative horizontal direction; neutral input
uses camera forward. Diagonals are normalized, and direction is fixed at the
moment of the press. Grounded dodges follow walkable slopes; airborne dodges
keep their existing height. Camera pitch has no effect on the chosen direction.

The dodge adapts `../infinite-library/scripts/traveler.gd`'s phase-dash range,
timing, central collapse and departure/arrival rings. Actual carried horizontal
speed sets the distance, from **3.2 m** at rest to **6.4 m** at sprint speed. The
phase lasts **0.34 s** and shifts at 43% of that cycle. There is **no cooldown**:
each fresh B/E press starts another dodge, including during an active phase.
Chaining safely sweeps and settles any unfinished displacement before beginning
the next phase, so rapid presses do not discard travel or bypass collision.
Position and gravity pause during the brief phase; both carried horizontal and
vertical velocity return on exit. A jump pressed during the phase is retained
once and fires on the next normal physics tick. Ground/air movement then
continues normally, including falling after a blink off a rooftop. Tapping RT+B
heals; holding it uses a shield. Menus continue running the world while gating
local gameplay input.

The middle **30–60%** of the phase is fully invisible and invincible to incoming
combat damage: **0.102 seconds** of the 0.34-second cycle, spanning the teleport
commit. The visible departure and rematerialization remain vulnerable. Damage
during the hidden interval is ignored, without consuming a parry or changing
carried momentum. The collision capsule remains enabled; invincibility cannot
bypass walls, posts or ceilings. Cancellation, completion, respawn and rejected
dodges cannot leave immunity active.

The upright capsule stays enabled throughout. Supported ground paths use short
full-volume sweeps along walkable floor planes, including terrain triangle seams,
so uphill ground cannot reject a valid B/E press. Leaving a roof or cliff ends
ground following. Full-volume sweeps shorten the blink before solid walls, posts
or low overhangs. A second sweep when committing
also catches blockers added during the fade. Less than 0.35 m of available travel
rejects the dodge. Camera angles and current drop-height history survive the
blink. A local alpha material makes the fade work in the Compatibility renderer;
it restores the original body material on exit. The Eturnull Hat and Scribe book/
quill keep their local poses during a phase: glyph inks cannot overwrite the
shared fade, and world-space attachment updates cannot undo the body's collapse.
Their animation resumes on arrival. Cyan
rings expire after 0.28 s. The Library's source files remain unchanged and are
not required to run this component.

`tests/responsive_dodge.gd` passes **68 checks at each of 30/60/120 Hz**. It routes
real B/E press/release events across varied intervals, same-frame bursts and
rapid chains with all four weapons and the fitted robe. It checks swept travel,
momentum, hidden-only immunity, late blockers, original material restoration,
RT+B healing and input cleanup through menus, focus changes and respawn.
`tests/dodge_terrain.gd` passes **35 checks at each of 30/60/120 Hz**, using real
countryside collision triangles and B events with the complete Scribe outfit.
It covers uphill/downhill travel, triangle seams, rapid sprint chains with
uphill momentum, late walls, low ceilings, quill bounds and the exact hidden
alpha interval. Native `--capture` images under `captures/dodge_terrain_*` verify
departure, full absence, arrival and the restored equipment without light streaks.
Existing dodge, defense, fall-damage, lock/momentum and limb-integrity fixtures
also pass at 60 Hz.

## Phase 002 brief review and tuning

Existing controls, analog filtering, ground paces, relaxed idle, walking/running
cycles and asynchronous TED-RAG architecture were retained. The missing pieces
were additive directional propulsion, opposite-arm aerial drive, impulse-aware
glass, explicit sprint/aerial retrieval profiles, and high-speed verification.

| Setting | Default | Role |
|---|---|---|
| `player.gd: sky_jump_lift` | 9.2 | Vertical velocity added; about one character-height of rise from zero vertical speed |
| `player.gd: sky_jump_push` | 3.4 | Horizontal velocity added at full directional input |
| `player.gd: gravity` | 22.0 | Downward acceleration between jumps |
| `player.gd: acceleration / boost_acceleration` | 9 / 20 | Existing steering and braking rates |
| `player.gd: boost_speed` | 10.2 | Nominal full-input grounded sprint pace |
| `character_visual.gd: trigger_air_step` | 0.25 s pose response | Counter-motion and directional kick recovery |
| `glass_step.gd: LIFETIME` | 0.62 s | Effect expiry; at most 12 tiles are retained |
| `phase_dodge.gd: DISTANCE / MAX_DISTANCE` | 3.2 / 6.4 m | Range based on actual horizontal momentum |
| `phase_dodge.gd: DURATION` | 0.34 s | Phase cycle; fresh presses can chain without a cooldown |
| `data/motion_constraints.json` | 18 profiles | Bounded pose weights and retrieval contexts |

Physical velocity has no gameplay cap. Pose gains, foot reach, effect size and
effect counts remain bounded for readable animation and rendering cost. The
camera's usual follow smoothing is retained, with follow lag bounded to 2 m at
extreme speeds so the player remains framed. Existing input bindings are retained;
B/E adds phase dodging.

Collision uses the existing Godot [CharacterBody3D move-and-slide path](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html#class-characterbody3d-method-move-and-slide),
with up to 12 slide contacts per tick. Regression fixtures verified 2000 m/s
against 0.1 m walls, ceilings and floors; this is a tested range rather than a
claim about every possible floating-point magnitude. Gravity uses the existing
semi-implicit Euler integration at the fixed physics tick rate. A one-second
30/120 Hz comparison matches final impulse velocity and allows 0.31 m positional
difference from first-order gravity integration. Render frame rate does not
drive the movement calculations.

## Structure

- `scenes/main.tscn`, `scripts/world.gd`: startup, district assembly, and HUD.
- `scripts/district.gd`: intentional layout in local district coordinates; add
  future districts as sibling nodes with their own transforms.
- `scripts/metropolis.gd`: batched civic tower, curved/straight skyways, stairs,
  connected north promenade, exposed-boundary guards, skyline, trees, banners,
  benches and matched box/convex collision.
- `scripts/outer_quarters.gd`: east/west lantern courts, north gardens, south
  arrival court, gateways and avenue inlays.
- `scripts/building.gd`: reusable buildings with floor bands and facade seams.
- `scripts/street_light.gd`: solid orange fixtures with shadow-casting spotlights.
- `scripts/neon.gd`: cached box meshes, shared materials, batched edge lines,
  and separate static collision shapes. Building surfaces occlude edges behind
  them. Colors and grid brightness are centralized here and in the district.
- `scripts/player.gd`: capsule movement, Library-style acceleration/braking,
  fast running, unlimited sky jumps, gravity and bounded stair stepping.
- `scripts/fall_damage.gd`, `scripts/fall_reaction.gd`: vertical impact damage,
  sky-step braking, landing tumble/brace and knockdown recovery.
- `scripts/glass_step.gd`: short-lived fractured glass foothold visuals.
- `scripts/phase_dodge.gd`, `scripts/phase_trace.gd`: collision-checked phase
  teleport, momentum-scaled range and short-lived cyan materialization rings.
- `scripts/player_input.gd`: keyboard, mouse and the first connected controller;
  radial stick deadzone, separate move/look intents, held triggers and ordered
  combat/weapon-slot requests.
- `scripts/combat_intent.gd`: ordered commands, guard, draw/sheathe state and
  four directional loadouts. `scripts/combat_hud.gd` displays HP, exhaustion and grid address.
- `scripts/weapon_library.gd`, `scripts/weapon_combat.gd`: four authored movesets,
  timed physics hit checks, impact-speed damage, terrain occlusion, health,
  guard and two-handed IK.
- `scripts/combat_rules.gd`: per-actor tuning for forced states, shared guard exhaustion,
  fortitude and feedback.
- `scripts/spark_burst.gd`: independent red/orange spark flights, drag, gravity,
  staggered lifetimes and additive moving streaks.
- `scripts/neon_glow.gdshader`: small screen-space neon halo before HUD rendering.
- `scripts/impact_feedback.gd`: pooled spark flights, cached two-layer
  spatial audio, visual-only hitstop and cosmetic camera impulses.
- `scripts/target_lock.gd`: visible target selection, screen-direction switching,
  target-relative movement frame, facing and lock brackets.
- `scripts/damage_number.gd`: bounded, expiring damage feedback.
- `scripts/sparring_partner.gd`, `scripts/sparring_brain.gd`: shared player actor
  with orange presentation and AI-issued combat/traversal inputs.
- `scripts/sparring_duel.gd`: nearby interaction, Yes/No invitation, round health,
  opponent-only combat, yielding and nonlethal reset.
- `scripts/combat_body.gd`: load/drive/follow-through timing, hip/shoulder springs,
  real-floor support contacts, turn steps and gait/airborne release.
- `scripts/weapon_rig.gd`: code-native solid/outlined hand and stowed models.
- `scripts/combat_effect.gd`, `scripts/blade_trail.gd`: bounded glyphs and trails.
- `scripts/practice_target.gd`: solid rebooting practice sentries and counterattack.
- `scripts/camera.gd`: smooth following, pitch limits and a sphere-shaped spring
  arm that excludes the player. Exported mouse/stick sensitivities are adjustable.
- `scripts/character_visual.gd`: articulated pelvis/chest, shoulder/elbow and
  hip/knee chains; support-foot weight transfer, acceleration/braking pitch,
  turn yaw and bank, ground-aware two-bone leg placement and landing compression.
- `scripts/pose_spring.gd`: critically damped pose blending; no input gating.
- `scripts/motion_retrieval.gd`, `tools/motion_retrieval.py`: optional asynchronous
  live TED-RAG pose-constraint adapter, with built-in local fallback.

The Compatibility renderer targets modest hardware. Emissive wirework, dark
light-receiving surfaces and one small screen pass establish the neon identity.
It needs no Forward+ renderer, external textures or imported city assets.
Facade seams retain the solid silhouette beneath the light. The Infinite Library's emissive line approach informed this implementation;
the projects share no files or runtime dependencies. Networking and broader enemy
AI remain future work. Weapon balance, precise hand placement, and clipping at
very close walls remain hands-on polish areas.

## Fluid motion and live TED-RAG

Unlocked locomotion remains movement-facing, with the rig's anatomical front at +Z;
locked locomotion faces the selected opponent.
Visual nodes lean and twist independently of the upright collision capsule and
camera. Movement follows the fast-run and sky-step rules above. Hips shift
toward the support foot while the chest counter-rotates. Ground rays and a small
two-bone solver guide the legs; this is visual weight transfer, not a simulation
of physical body mass. Extreme strides, sharp turns and stair edges may still
need foot-sliding and clipping polish during hands-on tuning.

At rest, the pelvis rises to a relaxed near-straight stance with a small knee
bend and recenters after either support foot. Low analog speeds use a walking
gait: speed-linked cadence, low foot clearance, relaxed arms and intervals with
both feet supported. It blends continuously into the existing faster running
gait; joystick deadzone, walk/run input threshold and physical speeds are unchanged.
Initial step placement follows actual travel while visual facing catches up.

During descent, both legs blend forward into a cradle in the rig's local +Z
direction; faster falls deepen the tuck. Airborne ankle blending follows the
body's transform, so carried speed and downward motion cannot drag the feet
behind or above the body. Sky-step propulsion retains its alternating kick and
opposite arm drive, then recovers into the cradle if the character is still falling.

Landing knee compression scales with the height descended since the current
arc's apex and the vertical speed immediately before contact. Renewed ascent
starts a new arc. Small drops have a soft bend; larger drops bend deeper and take
longer to recover. Compression is bounded even with maximum TED-RAG settling gain,
the feet remain supported, and a fresh jump starts releasing compression immediately.
`last_landing_height` and `last_landing_speed` on the visual expose the latest
measured drop for tuning. Leg IK writes local rotations only: fixed hip/knee
origins stay attached to their rods during long sessions. The previous repeated
world-basis assignments accumulated visible knee-position drift.

Uncontrolled landings also apply a gentle health penalty against the base 1000 HP:

| Effective uncontrolled drop | Damage | Recovery |
|---|---|---|
| 0-15 m | 0 HP | Existing soft landing |
| 15-25 m | 0-50 HP | Moving shoulder tumble or stationary tuck |
| 25-40 m | 50-180 HP | Heavy supported landing |
| 40-70 m | 180-600 HP | Knockdown, 0.85 s action recovery |
| 70+ m | 600-1000 HP | Severe landing; lethal from 100 m at full health |

Damage interpolates continuously within each band. Effective drop is the smaller
of the descent since the current apex and `downward_speed^2 / (2 * gravity)`;
the speed is sampled immediately before ground collision. Horizontal momentum
continues to benefit attacks without contributing to fall damage, and a brief
downward attack impulse close to the floor cannot invent a tall drop. Sky steps
reduce actual vertical speed; renewed ascent starts a fresh arc. One kick during
a very fast fall can still leave substantial downward danger.

Minor/heavy recovery remains responsive to jumping and attacks. Severe landings
briefly use the existing forced-reaction gate; the visual get-up lasts 1.35 s and
can release into a fresh jump when actions become available. Terrain damage
bypasses weapon defenses and uses red/orange sparks without weapon hitstop.
Rooftops use their own landing height; horizontal phase dodges preserve the fall
history, and respawn/duel cleanup clears it. `player.fall_damage.last_landing`
exposes height, pre-impact speed, effective height, damage and reaction kind.

Live retrieval is enabled by default. With Python 3 available (`py -3` on Windows,
`python3` elsewhere) and the existing sibling `../rag/context_builder.py`, a hidden
local helper retrieves from `data/motion_constraints.json` using speed,
acceleration/braking, turning, ground contact and landing context. Phase 002 adds
sprint launch/braking/cornering, ground-to-air transition, directional propulsion,
repeated kicks, midair reversals and high-impact landing contexts. It calls the
**existing TED-RAG `build_fractal_constraint`** to weight the top three constraints
and synthesize bounded pitch, yaw, bank, sway and settling gains. Godot queries at
most four times per second and smoothly blends returned gains at physics rate.
It never waits for Python to finish before moving or animating.

This is a lightweight TED-RAG adaptation for live numeric pose decisions. The
motion constraints are authored game heuristics; their source references and
weights remain available in `visual.retrieval.last_decision` in the remote
inspector. The TED seed context's weighted-component idea informs the blend;
its theoretical equations are not claimed to establish human biomechanics.
The adapter does not run Ollama, embed the general corpus, generate new animation
code, or replace the existing TED-RAG research tools. Original `rag/` files are
read only and unchanged. No additional Python packages are needed.

If Python or TED-RAG is missing, stops, or stops responding, local procedural
animation continues with default gains. Late/invalid parameter responses cannot
exceed the configured limits. `visual.retrieval.status` reports whether live
retrieval or local fallback is in use; no network calls are involved. The helper
is shut down when the scene exits and self-expires after four idle seconds.
Set `live_retrieval` to false in `character_visual.gd` to use local animation only.
Edit `data/motion_constraints.json` to tune the live recipes, then restart the game.

## Verification

`tests/world_regions.gd` audits the 2.3 km region, all 564 added building roofs,
leveled farm foundations, 2,184 ground-support probes, 1,610 road-clearance
probes, solid closed/open gates, a real first-fight defeat, existing save/load,
rematch persistence and a full controller sprint from the north hub gate to the
country lookout. The continuous main-road traversal passed at 30/60/120 Hz.
The hub's revised structural audit covers 376 boxes, 34 roofs, 16 lamp heads
and 2,256 faces. Greefer arrival/flight, live menus, HUD, skyways and resident
flow remain covered by their existing suites.
`tests/capture_world_regions.gd` renders closed/open gates, urban streets,
the city overview, suburbs, rural bridge, farmland, countryside and lookout
under `captures/world_*.png`; these images were visually reviewed.

`tests/hud.gd`: **29 checks** cover the bars and grid marker, full and partial values,
recovery/respawn, grid boundaries and all four directions, countryside positions,
height/facing independence, live menus and viewport bounds at 800x600,
1280x720 and 1920x1080. Run without `--headless` and add `-- --capture` for
the rendered full/partial HUD screenshots in `captures/hud_*.png`.

`tests/lost_gear_hud.gd`: **22 checks** cover real death/respawn, persistent
recovery locations, notice expiry, multiple losses, live distance/nearest-item
updates, dialogue and viewport layout, recovery/removal, owner filtering and
checkpoint restoration. Add `-- --capture` for `captures/lost_gear_*.png`.
`tests/inventory_startup.gd` also verifies the restored location for an outer-city
loss during deferred startup loading.

Greefer: **48 checks at 30/60/120 Hz** in `tests/greefer_encounter.gd` exercise the real boss/player resolver,
solid tower perch, automatic detection, continuous arrival/landing, shared chip,
parries, defender/attacker exhaustion, dodge immunity, explicit pulse
deduplication, encounter-aware lock-on, protected bystanders, genuine weapon-hit
victory and defeat callbacks, first/rematch progression, latest-outcome memory,
owner validation, interrupted-save fallback, occlusion/reacquisition, bounded
search and the non-host write/decision boundary. **21 checks at 60 Hz** in `tests/greefer_flight.gd`
exercises an existing 32-metre roof, full-body landing probes, actual player
Sky Jumps, aerial pursuit, committed dive aim, all five moves' readable timing,
continuous return/landing, damaging open-air engagement without a landing,
full-strength G/RT rematches and the live Start menu.
**44 checks at 30/60/120 Hz** in `tests/greefer_readability.gd` run the actual
animation/contact clock for all five moves, both double swipes, harmless windup
and recovery, lateral/vertical misses, late evasion, opaque cover, airborne
talons, planted hind feet, guard chip/strain, timed parry, hidden dodge immunity
and the opt-in debug display. **14 checks at 60 Hz** in `tests/greefer_rematch.gd`
exercise loss/victory retries during return, G/RT, default No, controller Yes,
live simulation, Start handoff, real Escape input routing and focus/range cleanup.
Run these with `--fixed-fps N -- --hz=N`. Native visual review images of the
perch, articulated griffin and live combat are generated by
`tests/capture_greefer.gd` under `captures/greefer_*.png`.
The existing weapon (123 checks), charge/sparring (146), lock/momentum (110),
defensive interactions (48), defender exhaustion (36), inventory integration
(36), Start/recovery (29), population flow (15), traversal and dodge suites also
passed at 60 Hz. The open-space dodge fixture excludes pedestrian collisions;
the actual game and the separate population collision tests retain them.
The lock/momentum fixture also excludes pedestrian collisions only for its
unobstructed travel cases, then restores the player's normal collision mask.
Native Compatibility/ANGLE captures were reviewed for the perched, airborne and
combat poses, violet/cyan silhouette and boss health/strain HUD.

City population: **27 checks at 60 Hz** cover all 4,900 waypoint pairs, the
hundred-person social graph, actual G/RT conversations, repeat-meeting memory,
dialogue readability, personal-space yielding, occluded sight, visible combat
reactions, Ember interaction priority and live menus. The 160-second interaction
soak completed 214 public stops with 87 residents reaching a destination.

`population_flow.gd` adds 15 checks for unique identities, every palette color,
startup distribution, the outdoor budget, broad roster circulation, real building
entries/exits, indoor pooling and continued simulation behind menus. Flow soaks
run for 180 simulated seconds at 30/60/120 Hz. Collision checks use actual capsule
contact pairs, allowing a 2 cm contact tolerance at curb edges. Navigation itself
uses a larger clearance capsule. `resident_entrances.gd` adds 13 checks for real
door openings, physical screens and camera-visible activation/deactivation
guards, including occupied handoffs, walking the passage and preserving memory.

Existing inventory, system-menu/Unstick, defensive combat, traversal and dodge
regressions passed with the hundred-person roster present. Native 1280x720 reviews
are in `captures/population_plaza.png`, `captures/population_greeting.png` and
`captures/population_lobby.png`.

System menu/recovery: **29 checks at 30/60/120 Hz** in `start_menu_unstuck.gd`
exercise Start/Escape, controller focus/settings, actual camera/audio values,
save/load, live timers/gravity, inventory handoff, collision-checked rail recovery,
embedded-body fallback, preserved health/gear/stagger and normal engine quit.
Native system-menu and Settings screenshots are in `captures/system_*.png`.

Inventory: **180 checks** across `inventory_model.gd` (55), `inventory_loot.gd`
(47), `inventory_ui.gd` (42) and `inventory_integration.gd` (36) cover identity,
stacking, repeated/reentrant transfers, equipment in all sixteen direction/profile
combinations, failed-spawn rollback, death eligibility/deduplication, loss markers,
actual G/RT pickup, View/keyboard opening, input isolation, controller navigation,
live solo/network simulation and whole-checkpoint restore. Tests also exercised
hundreds of instances with eight visible rows per page. Native menu captures were
reviewed at 1280x720. Three normal-main boots using isolated save data confirmed
that a dropped upgraded katana remained unowned in the world, retained its ID and
properties, left its old slot empty and did not duplicate or remint starter gear.

Existing weapon, combat motion/input, charged sparring, defensive interactions,
movement, dodge, fall damage and leg-integrity regressions passed at 60 Hz after
integration. Normal main startup has automatic persistence; script test tools
remain isolated. Actual network transport and physical gamepad hardware testing
remain separate from the synthesized input/host-boundary checks.

Leg integrity: **17 checks at 30/60/120 Hz**, including all weapon moves, lock-on
movement, interrupted/flattened teleport poses, falling and a ten-minute elevated
idle soak per rate. The soak reproduced a 3.43 cm knee gap before the fix; after
the fix its maximum rod/joint endpoint error was about 0.000002 m.

Fall damage: **85 checks at 30/60/120 Hz** in `tests/fall_damage.gd` exercise the real player and HP across all
bands, exact-once application, rooftop landings, fast horizontal/downward attack
approaches, late/repeated sky-step braking, renewed ascent, phase continuity,
defensive bypass, ceilings/walls, lethal respawn and responsive recovery/jump
cancellation. `tests/fall_reaction.gd`
passed **41 checks at 30/60/120 Hz** for supported full-body recovery, rigid limb
origins, attack/katana grip preservation, priority and cancellation. Native
reaction captures are under `captures/fall_reaction_*.png`.

Metropolis: **13 checks** in `tests/metropolis.gd` audit 3,273 added volumes and
19,860 faces against real collision, land the player on all 51 sampled city
routes, walk both complete new staircases, verify Ember's access/the open avenue,
and check renderer light limits. `tests/city.gd` also passed its independent audit
of all 376 hub/lobby boxes, 34 roofs, 16 lamps and 2,256 faces after opening the
outward roads and removing the two former north/south road-blocking towers.

`tests/skyway_routes.gd` passed **33 checks at 30, 60 and 120 Hz**. It checks
2,708 floor/body capsule samples, continuous support and three walking lanes
with the player's full capsule, forward/reverse sweeps through the junctions,
normal walking up and down both full stair flights and through the portals and
bridge, both full ring circuits, and 2,270 physical guard probes at 0.45 m
intervals. The real-controller routes supplement
the isolated landing samples so a rail cannot silently obstruct an entrance.

Sparks: **12 checks** in `tests/sparks.gd` cover both neon colors, independent
speeds/lifetimes, travel away from contact, downward arcs, identical flight at
30/60/120 Hz, pooled geometry, the 28-spark cap and cleanup. Native multi-frame
review images are produced by `tests/capture_metropolis.gd` under
`captures/metropolis_*.png`, alongside arrival, boulevard, skyway, tower,
open-junction, north-loop, court and district overview views. Native review used
the Intel HD Graphics 620 Compatibility renderer with glow enabled; the tower
view used 212 visible draw calls. Frame rate varies with view and background
work; this review does not establish a minimum-frame-rate guarantee.


Defender exhaustion: **36 checks** in `tests/defender_exhaustion.gd` passed at
**30, 60 and 120 Hz**. The real player/Ember resolver covers free held guard and
recovery, all four guard loadouts, configurable/zero defender share, unchanged
attacker penalties and chip, both actors' thresholds and recovery, parries in both
directions, unguarded/rear/invalid/evaded contacts, automatic Aegis mitigation,
legacy combat callers, overlapping hurtboxes, pulse deduplication and timed
multihits. It also exercises movement, sprinting, ground/Sky Jump, teleport and
normal attacks while strain is present, plus respawn/duel cleanup.
The existing weapon (123 checks), charge/sparring (146), parry/HP/RT (34),
defensive interactions (48), traversal and dodge suites also passed at 60 Hz
after this update.

Defensive interactions: **48 checks** in `tests/defensive_interactions.gd`
passed at **60 Hz** after the defender-strain update and cover exclusive outcomes, interruption, permissions, exhaustion,
vulnerability, fortitude/hyper armor, player/AI parity, explicit pulse deduplication,
visual-only hitstop, camera disable, red/orange/gold contact sparks, fixed pool bounds,
audio headroom, teleport immunity, body/hurtbox emission origins and cleanup. Run at 30/60/120 Hz with `-- --hz=N`;
`-- --capture` saves display review frames under `captures/defense_*.png`.
Native captures separately cover body-origin spark flights, supported kneeling,
recoil and HUD layout; these were visually inspected. A batch of 100 pooled feedback
requests was verified with fixed geometry/voice caps; this tests feedback dispatch
and cleanup rather than setting a full-frame performance guarantee. The existing weapon, charged
special/sparring, input, whole-body pose, lock/momentum, traversal, phase dodge,
integration and live TED-RAG motion suites also passed after this combat pass.

HP, configured parry stagger and RT interaction: **34 checks** in
`tests/parry_stagger.gd` passed at 30/60/120 Hz using the configured punish duration.
They cover 1,000 HP on spawn, respawn, duel start and HUD; contextual RT thresholds,
release rearming, invitation cancellation and retained RT-modified combat; actual
parries in both directions with attacker identity; interrupted multihit/buffered
attacks and charges; a configured control opening within one physics tick; disabled
guard/jump/dodge/steering during that opening; immediate post-window action; and
airborne momentum/gravity. AI recovery timers are cleared so they cannot extend
the opening. All four loadouts keep their capsule/root still during recoil,
supported feet stay planted and the katana retains both hands on its hilt.
Respawn/focus/round cleanup clears the effect and its status.

Display-capable recoil captures for all four loadouts passed and were visually
reviewed. Existing weapons, timed defense, charged-sparring, lock/momentum, input,
integration, facing, traversal, fall/landing, dodge, combat motion and gait suites
also passed. Editor import completed without script errors.

Charged specials and sparring: all **146 checks** in `tests/charge_sparring.gd`
passed at 30, 60 and 120 physics ticks per second. Each of the sixteen normal
specials preserves its timed damage on a tap; each extended version waits for
release, increases reach/duration/damage and adds one finishing pulse. Tests cover
partial/full/overheld charge, fixed modifiers, repeat suppression, all cancellation
paths, two-handed katana grip, responsive movement and charged momentum scaling.
Interaction checks exercise distance, G/RT, a default decline choice, controller
Yes selection, suspended game input and replayable nonlethal rounds. The real AI
executes all 24 weapon skills and demonstrates sprinting, elevated jump/sky-step
pursuit, a timed-block parry, hidden phase dodge and a charged modified special.
Lethal timed hits in both directions safely end rounds inside their hit callbacks.
Rendered body material is checked across resets; actual orange light, friendly
collision/hurt gating, restored player health and focus cleanup are also verified.

Display-capable charge/invitation/duel captures and native combat input checks
passed and were visually reviewed. The invitation has an opaque panel, and the
partner remains orange through phase restoration. Existing weapons, input, combat
motion, defense, lock/momentum, integration, facing, gait, traversal, fall/landing,
dodge, city and live TED-RAG/Phase 002 suites passed after these changes. Editor
import completed without script errors. Hardware controller feel and AI balance
remain hands-on playtest areas.

Lock-on and momentum damage: all 110 checks in `tests/lock_momentum.gd` passed at
30, 60 and 120 physics ticks per second. Coverage includes R3/Tab repeat handling,
four directional flicks and neutral rearming, keyboard switching, screen-space
selection, hidden/dead/off-screen/range/terrain rejection, target loss and cleanup,
idle/moving facing, 18 movement-direction/pace combinations, moving targets,
guard/attack aim, jump/sky-step/dodge continuity, shoulder framing and camera
collision on both the rear arm and lateral anchor. Impact tests cover standing,
walking, running, sprinting, vertical and combined velocities, uncapped scaling,
changed speed between windup/contact and each multihit pulse, miss feedback,
number limits/expiry and teleport immunity/velocity. An actual sprinting Royal
Cleave lands for 36 damage versus 24 standing. Lock and impact HUD labels fit the
viewport. Display-capable lock/sprint-impact captures and native combat input
checks passed and were visually reviewed. Physical controller feel remains a
hands-on check.

The complete existing weapons, input, combat motion, defense, facing, gait,
integration, traversal, fall/landing, dodge, live motion, Phase 002 and city suites
also passed after these changes. Combat motion additionally passed at 30/120 Hz;
editor import completed without script errors.

Draw/parry/phase defense: all 84 checks in `tests/defense_draw.gd` passed at
30, 60 and 120 physics ticks per second. They cover hold-to-toggle with keyboard
and D-pad, all 24 attack/loadout auto-draw combinations, input ordering, modifier
retention, one-request execution, keyboard dispatch, directional timed parries,
late/released/held blocks, multihit consumption, trigger hysteresis, mixed input
sources and focus cleanup. The real counter sentry exercises both a successful
parry and ordinary held-block chip damage. Phase tests inject lethal damage
during invisibility and normal hits in both visible tails, verify exact interval
boundaries, retained collision and momentum, and cleanup on exit/cancel/respawn.
`-- --capture` saves parry feedback and fully hidden dodge review frames.

Whole-body combat: all 146 checks in `tests/combat_motion.gd` passed at 30, 60
and 120 physics ticks per second. Every move loads the pelvis, rotates the hips,
plants a support foot and returns to the relaxed stance. The suite measures real
wrist/ankle endpoints: both katana hands remain on the hilt throughout all six
moves, stationary support drift stays below one centimetre, and the trailing
carry clears the floor during sprint launch without a wrist flip. The tests also
verify the resting right-hip grip, backward blade direction, downward sword
stowage and pelvis-mounted left-hip katana saya. The suite also exercises
moving quick swaps, guard-turn replants, unsupported roof edges, jumping,
sky steps, movement takeover, dodge and respawn. Rendered load/drive/follow-through/
recovery sequences and the relaxed katana pose were inspected.

Live retrieval: a real Windows file-lock regression verifies that the worker
survives exclusive locks on both request and response files, then resumes valid
pose responses. The adapter retries transient sharing errors rather than exiting.
All live TED-RAG profile, fallback and cleanup checks passed afterward.

Weapons: all 123 checks passed in `tests/weapons.gd`, exercising 24 timed moves,
all 16 named specials, windup/recovery, per-pulse damage, early/late buffering,
front/rear and range coverage, terrain occlusion, cancellation, actual damage
feedback, target reboot, weapon-specific guards and a real sentry counterattack.
Tap/hold selection, draw/stow visibility, focus/disconnect cancellation, material
restoration, run displacement, jump/sky-step responsiveness and health respawn
also passed. `tests/capture_weapons.gd` renders 28 ready/guard/sheathed/special
review poses plus two katana side views, checks HUD label bounds, and was
visually inspected. All existing
movement, city, dodge, input and live TED-RAG suites passed with the arsenal.

Combat input: display-capable checks passed for bumper side routing, all four
exclusive special variants, held block and trigger hysteresis, keyboard/mouse
equivalents, direct D-pad/arrow slots, same-tick swap/attack ordering, repeat
suppression, cursor recapture, focus/disconnect cleanup, live player dispatch
and selection during a phase dodge. The weapon HUD was rendered and inspected.
These checks validate input commands; the weapon suite covers combat execution.
Headless mode skips the native mouse capture check; the same
check passes in a display-capable run.

Dodge/sky-step tuning: neutral airborne steps rose 1.773/1.847/1.885 m at
30/60/120 Hz. Ground paces remain 3.5/7.5/10.2 m/s. Tests cover B/E routing,
one request per press, 24 direction/camera cases, momentum-scaled blink range,
carried velocity on exit, phase timing and rapid press chaining, thin walls,
narrow posts, diagonal contacts, low overhangs and blockers added before the shift. Queued
jumps, roof-edge falling, drop-history retention, respawn and effect cleanup
are also exercised. Use `-- --capture` for departure/shift/arrival review frames.

Fall/landing: all 24 stationary/moving pose cases passed across four facings,
including carried horizontal speeds up to 40 m/s. Drops of 0.5, 4 and 16 m produced
approximately 35, 61 and 89 degrees of knee flex at peak compression, respectively,
with local retrieval disabled for repeatable measurements. Rooftop-relative drop
height, foot support, smooth apex transitions, sky-step recovery, immediate
post-landing jumps and relaxed idle recovery passed. Side and oblique render
captures show the forward cradle and graded landing poses.

Original city lighting/collision: all 374 structural boxes matched their physics shapes;
all 2,244 faces blocked ray probes. The real player landed on all 36 roofs and all
16 lamp heads, and every roof also passed four corner support probes. Foundation
coverage and the eight-light-per-surface budget passed. All existing integration,
facing, gait, traversal, motion and Phase 002 suites passed after the city changes.
Rendered plaza, fixture and skyline views were visually inspected; an identical
lights-on/off comparison measured 122,334 pixels receiving orange illumination.

Phase 002: all 38 dedicated checks passed, together with the existing locomotion,
gait, facing, traversal and live-retrieval regressions. The 30/120 Hz test matched
final velocity and measured a 0.275 m displacement difference over one second.
Both alternating arm/leg pairings and the impulse-tilted glass were rendered for
visual review. Physical controller feel and long-session performance remain
hands-on checks.

Verified on Godot 4.7.2: editor import completed with no script errors, the main
scene rendered successfully, and all 14 integration checks passed. The rendered
plaza capture was visually inspected for character and environment readability.

From this directory (replace `godot` with your Godot executable if needed):

```powershell
godot --headless --path . --editor --import --quit
godot --headless --fixed-fps 60 --path . --script res://tests/city_population.gd
godot --headless --fixed-fps 60 --path . --script res://tests/population_flow.gd
godot --headless --fixed-fps 30 --path . --script res://tests/population_flow.gd -- --hz=30
godot --headless --fixed-fps 120 --path . --script res://tests/population_flow.gd -- --hz=120
godot --headless --fixed-fps 60 --path . --script res://tests/resident_entrances.gd
godot --path . --script res://tests/capture_population.gd
godot --path . --script res://tests/resident_facing.gd
godot --headless --fixed-fps 60 --path . --script res://tests/start_menu_unstuck.gd
godot --path . --script res://tests/start_menu_unstuck.gd -- --capture
godot --headless --fixed-fps 60 --path . --script res://tests/inventory_model.gd
godot --headless --fixed-fps 60 --path . --script res://tests/inventory_loot.gd
godot --headless --fixed-fps 60 --path . --script res://tests/inventory_ui.gd
godot --headless --fixed-fps 60 --path . --script res://tests/inventory_integration.gd
godot --path . --script res://tests/capture_inventory.gd
godot --headless --path . --script res://tests/integration.gd
godot --path . --script res://tests/capture.gd
godot --headless --fixed-fps 60 --path . --script res://tests/facing.gd
godot --headless --fixed-fps 60 --path . --script res://tests/motion.gd
godot --headless --fixed-fps 60 --path . --script res://tests/gait.gd
godot --headless --fixed-fps 60 --path . --script res://tests/traversal.gd
godot --headless --fixed-fps 120 --path . --script res://tests/phase002.gd
godot --headless --fixed-fps 120 --path . --script res://tests/dodge.gd
godot --headless --fixed-fps 60 --path . --script res://tests/combat_input.gd
godot --fixed-fps 60 --path . --script res://tests/combat_input.gd -- --capture
godot --headless --fixed-fps 60 --path . --script res://tests/weapons.gd
godot --headless --fixed-fps 60 --path . --script res://tests/defensive_interactions.gd
godot --headless --fixed-fps 60 --path . --script res://tests/parry_stagger.gd
godot --headless --fixed-fps 30 --path . --script res://tests/parry_stagger.gd -- --hz=30
godot --headless --fixed-fps 120 --path . --script res://tests/parry_stagger.gd -- --hz=120
godot --fixed-fps 60 --path . --script res://tests/parry_stagger.gd -- --capture
godot --headless --fixed-fps 60 --path . --script res://tests/charge_sparring.gd
godot --headless --fixed-fps 30 --path . --script res://tests/charge_sparring.gd -- --hz=30
godot --headless --fixed-fps 120 --path . --script res://tests/charge_sparring.gd -- --hz=120
godot --fixed-fps 60 --path . --script res://tests/charge_sparring.gd -- --capture
godot --headless --fixed-fps 60 --path . --script res://tests/lock_momentum.gd
godot --headless --fixed-fps 30 --path . --script res://tests/lock_momentum.gd -- --hz=30
godot --headless --fixed-fps 120 --path . --script res://tests/lock_momentum.gd -- --hz=120
godot --fixed-fps 60 --path . --script res://tests/lock_momentum.gd -- --capture
godot --headless --fixed-fps 60 --path . --script res://tests/defense_draw.gd
godot --headless --fixed-fps 30 --path . --script res://tests/defense_draw.gd -- --hz=30
godot --headless --fixed-fps 120 --path . --script res://tests/defense_draw.gd -- --hz=120
godot --fixed-fps 60 --path . --script res://tests/defense_draw.gd -- --capture
godot --fixed-fps 60 --path . --script res://tests/capture_weapons.gd
godot --headless --fixed-fps 60 --path . --script res://tests/combat_motion.gd
godot --headless --fixed-fps 30 --path . --script res://tests/combat_motion.gd -- --hz=30
godot --headless --fixed-fps 120 --path . --script res://tests/combat_motion.gd -- --hz=120
godot --fixed-fps 60 --path . --script res://tests/combat_motion.gd -- --capture
py -3 tests/motion_file_lock.py
godot --headless --fixed-fps 60 --path . --script res://tests/fall_landing.gd
godot --headless --fixed-fps 60 --path . --script res://tests/leg_integrity.gd
godot --headless --fixed-fps 60 --path . --script res://tests/fall_damage.gd
godot --headless --fixed-fps 60 --path . --script res://tests/fall_reaction.gd
godot --headless --fixed-fps 60 --path . --script res://tests/metropolis.gd
godot --headless --fixed-fps 60 --path . --script res://tests/skyway_routes.gd
godot --headless --fixed-fps 60 --path . --script res://tests/sparks.gd
godot --path . --script res://tests/capture_metropolis.gd
godot --headless --fixed-fps 60 --path . --script res://tests/city.gd
godot --path . --fixed-fps 60 --script res://tests/capture_city.gd
godot --path . --fixed-fps 60 --script res://tests/capture_motion.gd
```

The integration check runs the actual main scene and physics with synthesized
keyboard events. It checks ground contact, walking/running distances, jumping and
landing, tower collisions, stair/roof access, camera follow and collision retraction,
the articulated hierarchy, controller jump routing and analog deadzone behavior.
It exits nonzero on failure. The capture script renders a real frame to
`captures/plaza.png`; it requires a display and graphics driver.

The motion check exercises launch, walk/run blending, turning, braking, rest,
jumping and landing; spring consistency at 30/120 Hz; the real Python/TED-RAG
round trip and changing constraint selection; bounded parameter validation;
helper failure fallback; and process cleanup. Its live-connection checks require
Python; the necessary TED-RAG builder is included with the repository. Gameplay
itself does not require Python. The resident-facing check requires a display
because it inspects actual rendered mesh transforms rather than the headless
renderer stubs.
The capture script saves review frames for idle, launch, run, turn, braking,
jump and landing under `captures/motion_*.png`.

The gait check feeds filtered fractional stick intent through the real player
physics without altering a connected controller. It checks relaxed idle knees
before and after locomotion, low-speed cadence, double support, walking/running
clearance and arm differences, smooth transitions, unchanged analog speeds, and
ground contact. Add `-- --capture` to the gait command with a display-capable
Godot invocation (omit `--headless`) to render `captures/gait_*.png` review frames.

Traversal checks exercise L3/Ctrl routing and cancellation, Library acceleration
and sprint speed, exaggerated lean, 50 uninterrupted air jumps, horizontal carry,
alternating legs, ceiling collisions, effect caps and expiry, and camera-relative
diagonal fast running. Add `-- --capture` with a display-capable invocation to
render `captures/traversal_*.png`. The facing test now waits for the slower Library
acceleration to settle; its optional motion baseline is specific to this model.

The Phase 002 suite adds exact additive-impulse and camera-relative reversal
checks, contralateral arm drive for each leg, pose continuity, impulse-oriented
glass, 2000 m/s thin-geometry collisions, immediate movement after high-speed
landing, 30/120 Hz comparisons, all ten new live retrieval contexts, and identical
physics with TED-RAG enabled or unavailable/disabled. No runtime LLM is used.

The original city suite audits each original structural box against the physics world and tests
rooftop and lamp-head landings using the real player. The city capture saves plaza,
streetlight, lights-off baseline and skyline images to `captures/city_*.png`, and
checks pixel differences between identical lit/unlit views for orange illumination.

The fall/landing suite drives the real player through stationary and high-speed
falls and compares small/medium/high drops and an elevated landing surface. Add
`-- --capture` with a display-capable invocation to save `captures/fall_*.png`,
including a side view captured during an actual moving fall.

Physical gamepad feel, long-session performance, and other operating systems still
need hands-on testing. The automated controller check validates input routing;
it does not establish hardware compatibility. No performance target is claimed.

In the restricted development sandbox, set `APPDATA` to a writable directory
under `.godot` for verification so Godot can create its editor and user settings.
This machine reports a root certificate store error at engine startup and an
OpenGL driver warning before automatically using ANGLE. These are engine/environment
diagnostics; the game has no network functionality.
