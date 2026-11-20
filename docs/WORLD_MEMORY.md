# NPC visual attention

TED-RAG supplies bounded NPC pose-update budgets. The attention manager keeps
resident identity and interaction summaries and changes only resident animation
scheduling. This manager does not change map geometry, materials, visibility,
lighting or collision. Static prop batching and user graphics controls are
independent startup/rendering systems; attention never streams the map.

Offscreen resident poses stop rebuilding while their journeys, doorway visits
and conversations continue. Nearby residents use movement physics; distant
journeys use the separate population simulation levels described below.
Turning the camera resumes poses from current state. Nearby residents retain full-rate poses.
Visible distant residents use 15-20 Hz or 8-10 Hz budgets depending on range.
Camera movement refreshes attention immediately; otherwise it refreshes every
0.2 seconds. World time continues behind all menus.

## TED-RAG's contribution

The existing asynchronous motion worker retrieves authored records from
`data/world_constraints.json`, using travel speed, local crowding and a live
sparring-duel flag. The TED-RAG constraint builder blends the top two records
and returns a 24-32 m full-detail range plus bounded pose rates.
No additional worker, model or network request is started. Unavailable, stale,
disabled or out-of-range retrieval uses local defaults. Physics and combat
never wait for retrieval.

The retained `world_memory_enabled` startup flag enables this NPC-only manager.
Its `set_attention_enabled()` method switches pose scheduling for paired tests
and restores original resident update rates when disabled.

## Civilian simulation levels

`city_population.gd` separately manages distant original residents: outdoor
journeys and door leases progress at quarter-second intervals, without movement
physics or floor/avoidance probes. `code_form_activity.gd` supplies a shared
three-dimensional activity bubble: pedestrians activate within 128 m and retire
beyond 160 m. A velocity-directed look-ahead of up to 96 m anticipates driving,
Sky Jump and falling. Activation checks supported, unoccupied space. Height now
matters: distant street physics can retire while the player is high above it.
Identity, conversation history and building-entry/exit counters stay on the same
resident object. Talking, reacting and combat participants retain full updates.

The original hundred residents now occupy the wider city as well as the hub.
Thirty-two retain their identities in eight existing outer-city block circuits;
their outdoor errands and breaks stay within their own connected neighborhood.
Those streets have no open resident lobbies, so these residents rest outdoors
instead of returning through a locked progression gate to a tutorial lobby.
The remaining sixty-eight still use all twenty-two original physical lobbies.
Startup places thirty-two residents around those outer blocks and twelve on
hub streets; the shared sixty-four outdoor-slot limit is unchanged. Quieter
perimeter streets inside the hub also provide actual walking destinations.
Ember, practice targets, shops and progression gates retain their placements.

Neighborhood-aware destination selection prevents personal errands from
gathering the whole original roster back at the central plaza. Distant residents
continue their existing lightweight journeys, then regain physical bodies and
the same contextual interaction when approached. `tests/city_distribution.gd`
measures fixed-seed tutorial-area density over time and checks route support,
solid contacts, identity, real lobby visits and closed progression gates.
Eligible lobby residents with fewer outdoor turns have priority when a slot
opens, with rotating ties. Concealment and doorway occupancy remain mandatory;
pending outer street placements keep their own reserved capacity.
With seed 1893 over 120 seconds, original-resident density within 48 m of the
tutorial center averaged 34.32 before redistribution and 13.07 afterward
(peaks 42 and 19). Active movement-physics bodies averaged 61.13 and 28.68.
These counts measure the same hundred identities, with regional pedestrians
disabled in both runs; they are not a frame-rate benchmark. Both runs found
zero unsupported positions or solid penetrations beyond the 2 cm tolerance.

`district_life.gd` retains the existing bounded physical neighborhoods and adds
65/90 m physical/virtual tiers for regional pedestrians. Visible virtual motion
interpolates between the five-Hz route records. Regional pose updates and seated
driver poses share the existing retrieved 24-32 m / 15-20 Hz / 8-10 Hz policy;
unavailable retrieval uses the same local defaults. No new worker is launched.
Uninstantiated regional residents and traffic continue lightweight journeys.

Regional vehicles use the same predictive bubble with 192/240 m activation and
retirement radii. Existing body/construction budgets remain in force. Active
combatants, conversations, the player's vehicle and deployed patrols keep their
existing ownership/protection rules. Outdoor and instanced coordinates never
share an activity set.

Frequent logical AI is also local: a one-second query of 128 m 3D cells builds
the nearby identity set, refreshed earlier on a 16 m move, replacement or
instance change. The cell index rebuilds at most every five seconds during
ordinary movement. A 40 m journey margin covers unloaded seven-metre-per-second
traffic between rebuilds; candidate positions are rechecked live. Bounded live
body pools are always included for fast driving, pushes and respawns. It uses
current bodies, journey records and driver records, with real home/doorway
positions for dormant indoor nodes and persisted respawn descriptors as fallback.
Nearby residents receive up to twelve AI turns
per clock tick; distant residents share two round-robin turns. Distant arrivals
still record real visits and progress eligible events, but routine waypoints do
not invoke extra full career/renovation actions outside this budget. A verified
workplace-station arrival retains its existing work-completion callback.
Offline catch-up retains its
explicit bounded complete-census pass. Persistent clocks, blessings, lifetimes,
inventories and identity are independent of the bubble. Full distant decisions
are intentionally less frequent rather than identical to local activity.

City, regional, driveway and window render batches use engine-side 3D visibility
ranges: 384 m plus each batch's bounding radius, with 32 m hysteresis. The engine
culls these batches without a GDScript scene traversal every frame. Landmark
scenes keep their existing visibility. Building interiors use adjacent 128 m
cells and clear the previously active shells on departure. Geometry and static
landing/road collision stay in memory; this change reduces active processing
and drawing, and does not claim to stream all map assets out of RAM.

`World.activity_bubble_enabled` restores the previous scheduler and unlimited
batch draw ranges for diagnostic comparisons. `tests/code_form_activity.gd`
checks 3D look-ahead, fairness, instance isolation and offline behavior;
`tests/activity_bubble_integration.gd` checks real body retirement/reactivation,
landing collision, menus, spatial interiors and full checkpoint restoration.
`tests/activity_bubble_performance.gd` measures uncapped native frame/draw costs
at street and Sky Jump height, with screenshots under `.godot/`.

Native samples on the local Intel HD 620 / ANGLE renderer at 1280x720, with
VSync disabled and 96 measured frames after 60 settling frames:

| Fixed-census view | Median frame ms, before / bubble | p95 ms, before / bubble | Draw calls, before / bubble |
| --- | --- | --- | --- |
| Street | 28.80 / 35.64 | 92.48 / 63.10 | 651 / 532 |
| Sky Jump | 25.81 / 21.10 | 40.93 / 29.49 | 699 / 620 |

This mode freezes the civilian clock and indoor exits/errands while retaining
normal body physics and rendering. It isolates pooling/draw-distance behavior;
the logical scheduler is measured separately. Both street halves retained twelve
physical city residents. Airborne city physics dropped from twelve to zero.
Draw counts and p95 improved in both views, but street median did not; these
results do not establish a universal FPS improvement. A live-census pass also
improved airborne median from 69.77 to 28.00 ms; its street comparison was
confounded by crowd growth from sixteen to twenty-seven physical residents.
Run native comparisons alone; desktop load, warm-up and evolving actors affect
timings. Nearby character movement/collision remains substantial work.

Construction and route checking are incremental; vehicle obstacle probes reuse
their shape/query at approximately ten Hz. All nearby character/vehicle sweeps,
player actions and combat resolution retain their normal physics rate. No map
collider is retired with a civilian. Gameplay menus never disable simulation.

## Verification and profiling

The current focused helper regression is
`tests/weighted_constraint_integration.gd`: it checks live retrieval, normalized
constraint weights, the shared worker, authored limits and local fallback.
The historical `tests/world_memory.gd` scene/capture fixture below still names
the former `CentralDistrict` node and needs migration to the current metropolis
before it can serve as a full-world regression gate.

```powershell
godot --headless --path . --fixed-fps 60 --script res://tests/world_memory.gd
godot --path . --fixed-fps 60 --script res://tests/world_memory.gd -- --capture
godot --path . --script res://tests/world_performance.gd -- --label=npc --paired
```

The regression compares the entire original district with attention disabled
and enabled, including mesh arrays, transforms, visibility, materials, shadow
settings and light parameters. It repeats the comparison while moving the
camera around the plaza, boulevard, skyways and civic tower. Other checks cover
live retrieval, bounded policy changes, worker reuse, fallback, continued
offscreen journeys, retained identity, animation restoration and live menus.

The native performance harness compares original NPC pose updates with NPC
attention in the same scene. Both halves use identical map rendering. VSync is
disabled; diagnostic output includes median/p95 frame time and draw calls.
Run it alone. The older mesh-batching performance numbers do not describe this
NPC-only revision.

The NPC-only recovery point is `checkpoint-2026-11-08-npc-only`. The original
`checkpoint-2026-11-08` remains unchanged.
