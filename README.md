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

The permanent HUD contains a cyan HP bar in the top left, a thin orange
exhaustion bar directly beneath it, and the Health Glyph count at bottom left.
Both bars use the actual combat maximum/current
values; exhaustion fills as strain accumulates and empties during recovery.
The phase title, weapon/debug panel, control sheet, move/guard text, momentum
readout and permanent objective text are removed. Controls and weapon arts
remain documented here; equipment and item arts remain available in inventory.

Nearby interaction prompts, short notices/dialogue and encounter health appear
only in their relevant context. Lost gear produces a short notice rather than
persistent world coordinates; its physical pickup and ownership markers remain.
Start, Settings and inventory continue to run the world without pausing.

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

Added geometry includes **209 urban buildings, 322 homes, 33 farm buildings,
673 geometric trees, 34 rock outcrops and three solid ravine bridges**. The
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
while moving are used. The 107 new orange fixtures have real local spotlights
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
the movement input to slow down; exit with **RT / G** once stopped. A moving
vehicle or blocked exit refuses unsafe dismounts. Entering and leaving keeps
the camera attached and restores the player's original capsule settings.

Mounted limbs use vehicle-local hand and foot contacts. Motorcycles have a
forward-leaning sport riding pose with rear-set pegs behind the hips, bent knees
and hands on the handlebars. Cars and trucks keep both feet in the pedal well.
Traffic drivers use the same contacts in their existing mesh batches. Bike
headlight lenses connect to a front fairing instead of floating ahead of the
frame. None of these pose changes alter driving controls, speed or collision.
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

Stealing an occupied vehicle provokes its displaced driver. Up to six nearby,
visible residents can also witness theft (including original hub residents).
They use varied anti-human remarks and individual temperament-based **anger**;
calmer residents can complain without immediately fighting. A brief overhead
anger readout accompanies their remarks. Further thefts can build on existing
anger, which cools after the incident. Reentering the same stolen vehicle does
not generate another theft, and residents cannot perceive theft through walls.

At **100 anger**, a resident shouts before starting normal combat. Up to **three**
street opponents fight simultaneously using the same 1000 HP, weapon arts,
momentum damage, chip, parries, one-second parry stagger, exhaustion, dodges and
Sky Jumps as the player/Ember. Their existing identity, color and body silhouette
remain. Once hostile, they can damage the player and be killed. Red/orange damage
sparks and normal damage numbers come from the shared hit pipeline. Physical
vehicles stop weapon hits. There is no new player stamina cost or global police
system. Street fights yield to Ember/Greefer encounters; distant pursuers give
up after a short grace period.

A defeated resident reappears at its own spawn after **six seconds**, with anger
reset and the same identity/memories. A blocked spawn waits for safe clearance.
Hub building schedules reserve the fighter's civilian slot so combat and respawn
cannot duplicate an NPC. These reactions/respawns are current-session state.
Balance values are exported on `TheftReactions`: `enrage_threshold`,
`anger_recovery`, `respawn_delay` and `max_fighters`.

Nearby activity is bounded to **28 regional pedestrians and 22 vehicles**,
in addition to the original hub population. Distant traffic retains lightweight
route/driver records rather than full physics and animated meshes. Neighborhood
identities, colors, conversation counts, abandoned vehicles and takeovers persist
through distance changes in the current session. Physical driveways use spatial
batches. World terrain/building meshes and collision are never toggled or
unloaded by this system. Vehicle journeys/positions are session state, not a
new disk-save or multiplayer replication system. Regional traffic currently
runs in offline play; the existing host inventory validation governs healing.

**Hold RT and press B**, or press **H**, to use one owned **Health Glyph** and
restore up to **350 HP**. Healing works while moving and has no stamina cost or
new animation lock. Full HP, no glyphs, or a defeated actor consumes nothing.
The small bottom-left count reads the actual inventory; glyphs also appear in
the inventory's Consumables category. New and existing valid saves receive
**three once**; a persisted migration flag prevents launch/load refills. A
collectible three-glyph stack is available near the arrival court. Consumption,
ownership and quantities use the existing checkpoint/loot transaction pipeline.
Invalid checkpoints still fail closed without a starter regrant.

Bare **RT interactions resolve on release**. RT+B exclusively heals, B alone
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

`tests/vehicle_controls.gd` checks vehicle-relative directions at four headings,
camera orbit, analog throttle, reverse and live menus for all three vehicle
types, plus measured tight left/right turns, stationary steering and bounded
high-speed/partial-stick response. `tests/theft_combat.gd` checks actual theft,
witness visibility, escalation, shared defenses/strain/momentum, real AI damage,
death/blocked-spawn recovery,
fighter limits, encounter isolation and hub identity reservations. Both accept
`-- --hz=30` or `-- --hz=120` with a matching engine `--fixed-fps` value. The
theft test accepts `-- --capture` for native reaction and combat screenshots.

`tests/mounted_pose.gd` passes **93 checks at each of 30/60/120 Hz**, measuring
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
also pass. The older civilian routine soak still detects a 5 cm curb overlap
near `(40.78,-62.16)`. The identical contact reproduces with the previous
`checkpoint-2026-11-10-city-life` game and the same test fixture; it remains a
known civilian pathing issue.

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
| Look | Mouse | Right stick |
| Lock / unlock opponent | Press Tab | Click R3 / right stick |
| Switch locked opponent | I / J / K / L (up / left / down / right) | Flick right stick up / left / down / right |
| Jump / repeatable sky step | Press Space | Press A / bottom face button |
| Phase dodge | Press E | Press B / right face button |
| Left-side attack | Left mouse button | LB |
| Right-side attack | Right mouse button | RB |
| Block / timed parry | Hold F / press just before impact | Hold LT / press just before impact |
| Special X / Y | Tap Q / R, attack on release | Tap X / Y, attack on release |
| Modified special X / Y | Hold V, tap Q / R | Hold RT, tap X / Y |
| Charged special (including modified) | Hold Q / R, then release | Hold X / Y, then release |
| Inventory / equipment | Press B | Press View / Back / Select |
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

Forty-four start distributed over city routes; others
begin indoors with staggered departures. Up to 64 can be outdoors at once. After
several errands or pauses, residents walk into one of 22 building lobbies and
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

Pedestrians use a shared graph of **70 waypoints and 110 physical street links**,
validated against actual ground, curb heights and full capsule clearance. They
avoid neighbours, yield personal space to the player, and make room when they
observe nearby fighting with unobstructed sight. They use their own collision
layer, separate from architecture queries and combat hurtboxes. The current
populace is civilian ambient simulation; combat targets remain the sentries and
Ember. Roles do not yet introduce a trading economy or quest system. Conversation
memory and routines currently last for the running session.

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
living inscriptions, twelve pooled specks and nine trailing symbols retain the
Scribe's identity. Their +Z-facing fit follows this game's existing character
rig. Motion drives visual flow only; there is no cloth physics, armor bonus,
movement cost or additional collision. Symbol meshes are cached, and stable
mesh instances preserve phase fades.
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
Compatibility run and seven reviewed front/back/side, running, Sky Jump, seated
and motorcycle captures (`tests/fitted_robes.gd -- --capture`). It measures the
actual wrapped fabric and limb attachments, independent tail motion and fixed
mesh pools. The outfit uses 97 mesh instances and 942 fabric vertices; it adds
no colliders and keeps the existing owned Body item.

Press **View / Back / Select** (Godot `JOY_BUTTON_BACK`, button 4) or keyboard
**B** to open the field kit. Inventory has six categories and eight rows per page;
Equipment shows the four D-pad assignments and a Body clothing slot. Left stick/D-pad or arrows navigate,
**A / Enter** opens item actions, **B / Escape** backs out, **LB/RB** changes tabs,
and **LT/RT** or Left/Right changes categories. Use the Equip action to assign an
owned weapon to any direction; use Drop to choose a stack quantity or drop one
specific weapon. Mouse buttons work too. **F5 / Save** writes a checkpoint.

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
item identity and world position for a future map. A brief notice reports newly unclaimed
gear; its physical pickup remains in the city. Markers disappear when anyone collects the
item or it is legitimately removed. Trading drops create no loss marker; acquired
items belong to their new possessor and are not permanently tracked.

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

Clean hits always apply health damage. Authored move strength is compared with
the defender's effective fortitude. Weapon choice, attack phase, heavy techniques
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
authored timing, reach, arc, damage and visual profiles. The compact HUD displays current health and exhaustion; the weapon model
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
uses camera forward. Diagonals are normalized, and camera pitch does not change
the blink's height. Direction is fixed at the moment of the press.

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
continues normally, including falling after a blink off a rooftop. RT+B retains
its Health Glyph mapping, and menus continue running the world while gating
local gameplay input.

The middle **30–60%** of the phase is fully invisible and invincible to incoming
combat damage: **0.102 seconds** of the 0.34-second cycle, spanning the teleport
commit. The visible departure and rematerialization remain vulnerable. Damage
during the hidden interval is ignored, without consuming a parry or changing
carried momentum. The collision capsule remains enabled; invincibility cannot
bypass walls, posts or ceilings. Cancellation, completion, respawn and rejected
dodges cannot leave immunity active.

The upright capsule stays enabled throughout. Full-volume sweeps shorten the
blink before solid walls, posts or low overhangs. A second sweep when committing
also catches blockers added during the fade. Less than 0.35 m of available travel
rejects the dodge. Camera angles and current drop-height history survive the
blink. A local alpha material makes the fade work in the Compatibility renderer;
it restores the original body material on exit. Cyan
rings expire after 0.28 s. The Library's source files remain unchanged and are
not required to run this component.

`tests/responsive_dodge.gd` passes **68 checks at each of 30/60/120 Hz**. It routes
real B/E press/release events across varied intervals, same-frame bursts and
rapid chains with all four weapons and the fitted robe. It checks swept travel,
momentum, hidden-only immunity, late blockers, original material restoration,
RT+B healing and input cleanup through menus, focus changes and respawn.
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
  four directional loadouts. `scripts/combat_hud.gd` displays HP and exhaustion.
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

`tests/hud.gd`: 14 layout/state checks cover the two permanent bars, full and
partial values, recovery/respawn, live menus and viewport bounds at 800x600,
1280x720 and 1920x1080. Run without `--headless` and add `-- --capture` for
the rendered full/partial HUD screenshots in `captures/hud_*.png`.

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
