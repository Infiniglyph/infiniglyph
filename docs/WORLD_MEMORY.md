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
physics or floor/avoidance probes. Activation within 48 m checks supported,
unoccupied space; retirement beyond 64 m provides hysteresis. Three-dimensional
distance includes Sky Jump height; speed-dependent lead adds up to 32 m for fast approaches.
Identity, conversation history and building-entry/exit counters stay on the same
resident object. Nearby talking/reacting residents and combat participants retain full updates.

NPC rendering is independent of that physics tier. `code_form_presence.gd`
reconstructs bodies on approach at 96 m and hides them beyond 128 m (both receive
the same bounded speed lead). It applies the existing instance reconstruction
shader only to that resident's meshes, with 16 cm cells and a 0.55 second assembly.
An arrival inside 12 m completes immediately, preventing an invisible close-range
body after teleporting. Materials are restored and the effect callback stops on
completion. Far original residents have no rendering or per-body physics/pose
callbacks; regional residents retain only their existing route records after
their pooled bodies retire. Nearby virtual regional poses retain interpolation.
Guild/tavern staff share the same appearance effect and distance threshold.

The experimental predictive activity bubble has been reverted in full. It does
not control scenery, buildings, street lights, collision, vehicle residency or
the logical society scheduler. World visibility and the pre-bubble autonomous
simulation remain in place; this revision changes NPC presentation/body tiers.

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
48/64 m physical/virtual tiers for regional pedestrians. Visible virtual motion
interpolates between the five-Hz route records. Regional pose updates and seated
driver poses share the existing retrieved 24-32 m / 15-20 Hz / 8-10 Hz policy;
unavailable retrieval uses the same local defaults. No new worker is launched.
Uninstantiated regional residents and traffic continue lightweight journeys.

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

`tests/code_form_presence.gd` exercises actual city/regional actors, shader
restoration, draw/physics hysteresis, vertical and sudden close arrivals, persistent
identity, combat reservations and unchanged map visibility. Native visual QA is
available through `tests/capture_code_form_presence.gd`.

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
