# Infiniglyph · Phase 003

A small, genuine 3D neon city and third-person movement foundation for a future
skill-based martial arts game. Open `project.godot` in Godot 4.3 or newer and
press **F6** on `scenes/main.tscn`, or **F5** to run the project. Development and
verification use Godot 4.7.2; earlier 4.x versions have not been tested.

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

## NPC visual attention

TED-RAG-guided attention budgets NPC pose updates. Offscreen NPC poses skip
rebuilds and visible distant poses update less often, while nearby residents
retain full-rate poses. Identities, journeys and meeting memories remain live.
The existing asynchronous TED-RAG worker supplies bounded detail budgets, with
local fallback. Map meshes, lights, shadows and collision use their original
rendering and are independent of this optimization.
See [WORLD_MEMORY.md](docs/WORLD_MEMORY.md) for behavior, limits and profiling.

## Canonical narrative reference

The [Canonical World Lore & Narrative Design Profile](docs/canonical_world_lore.txt)
is the foundation for future NPCs, bosses, dialogue, environmental storytelling
and progression. The supplied profile is preserved verbatim. Its unresolved
questions remain open for explicit design decisions. Project implementation
guidance is in [AGENTS.md](AGENTS.md).

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
| Talk / collect nearby loot | Press G | Press RT nearby |
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

Press **View / Back / Select** (Godot `JOY_BUTTON_BACK`, button 4) or keyboard
**B** to open the field kit. Inventory has six categories and eight rows per page;
Equipment shows the four D-pad assignments. Left stick/D-pad or arrows navigate,
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
stack when type, upgrade and custom properties match. The prototype consumable,
cosmetic and material items are collectible data; no use/crafting/armor-stat or
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
item identity and world position for a future map. The current HUD shows unclaimed
loss count, distance and coordinates. Markers disappear when anyone collects the
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
UI, cosmetic equipment slots and additional item-use systems remain future work.

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

Settings change mouse/controller look sensitivity, field of view, master volume
and camera impact shake immediately. Normal play saves these values in
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
fangs, a four-hit lattice and twin spiralling comets. The HUD lists the equipped
weapon's four specials. These are initial tuning values for playtesting.

All sixteen specials now support **hold to charge, release to attack**. A quick
release before 0.4 seconds executes the existing move with its existing timing
and damage. Holds from 0.4 to 1.2 seconds build an extended version; at 1.2 seconds
the charge is full. Holding longer never auto-fires. A percentage in the HUD,
whole-body windup and a brief full-charge glyph give feedback. Movement, jumping
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
the centre of the screen. White/cyan brackets and the HUD identify the target.
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
The HUD briefly shows the last successful impact's damage, speed and multiplier;
a later miss does not overwrite that feedback. Numbers expire after 0.85 seconds
and are limited to 24 at once.

Hand-held wireframe weapons follow the existing forearms. The katana uses a
shared two-handed grip. Its relaxed carry follows
[Waki-gamae](https://www.kendo-guide.com/kendo_kata_yonhon.html): hands beside the
right hip, blade trailing backward and slightly downward rather than in front.
The off hand follows a point 17 cm behind the primary grip throughout cuts,
specials, guards and traversal. The shared grip stays within both arms' reach.
Carry angle adapts to sprint lean and actual floor clearance without wrist flips.
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
of visual hitstop, a small directional camera jolt and a target **OPEN** countdown
make the initiative change readable.

Ordinary blocks preserve the existing weapon-specific reduction, including chip
damage, and preserve the attacker's move timing. A short additive weapon/body
recoil accompanies the dull impact. Striking a guard accumulates **offensive
exhaustion on the attacker**, never on the defender. Default capacity is 100;
each contact adds `clamp(10 + move.damage * 0.4, 14, 40) *
(0.6 + defender.guard_strength() * 0.4)`. Six stationary Royal Cleaves against a
shield exhaust the attacker. At the threshold, offense is cancelled and the
character drops to one knee for **1.8 seconds**, taking **1.35? damage**. Recovery
returns the meter to 25%. After one second without another defended strike,
reduced exertion recovers 14 points/second; attacks, held specials, teleporting
and boosted running pause recovery. The HUD shows the player's meter.

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
authored timing, reach, arc, damage and visual profiles. The HUD highlights the
selected loadout and shows health, drawn/sheathed state, guard and move name.

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
solid. Each fixture casts a downward orange spotlight with shadows. Cyan remains
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
phase lasts **0.34 s**, shifts at 43% of that cycle, and has a **0.62 s cooldown**
from activation. Position and gravity pause during the brief phase; both carried
horizontal and vertical velocity return on exit. A jump pressed during the phase
is retained once and fires on the next normal physics tick. Ground/air movement
then continues normally, including falling after a blink off a rooftop.

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
rejects the dodge without using the cooldown. Camera angles and current drop-height
history survive the blink. A local alpha material makes the fade work in the
Compatibility renderer; it restores the original body material on exit. Cyan
rings expire after 0.28 s. The Library's source files remain unchanged and are
not required to run this component.

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
| `phase_dodge.gd: DURATION / COOLDOWN` | 0.34 / 0.62 s | Phase cycle / interval between accepted dodges |
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
- `scripts/combat_intent.gd`, `scripts/combat_hud.gd`: ordered commands, guard,
  draw/sheathe state and four directional loadouts with contextual move names.
- `scripts/weapon_library.gd`, `scripts/weapon_combat.gd`: four authored movesets,
  timed physics hit checks, impact-speed damage, terrain occlusion, health,
  guard and two-handed IK.
- `scripts/combat_rules.gd`: per-actor tuning for forced states, attacker exhaustion,
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
of all 374 original/lobby boxes, 36 roofs, 16 lamps and 2,244 faces.

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


Defensive interactions: **48 checks** in `tests/defensive_interactions.gd`
passed at **30, 60 and 120 Hz** and cover exclusive outcomes, interruption, permissions, exhaustion,
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
carried velocity on exit, phase/cooldown timing, thin walls, narrow posts,
diagonal contacts, low overhangs and blockers added before the shift. Queued
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
