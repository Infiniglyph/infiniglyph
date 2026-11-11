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
physics or floor/avoidance probes. Activation within 140 m checks supported,
unoccupied space; retirement beyond 180 m provides hysteresis. Planar distance
and speed-dependent lead range protect Sky Jump landings and fast approaches.
Identity, conversation history and building-entry/exit counters stay on the same
resident object. Talking, reacting and combat participants retain full updates.

`district_life.gd` retains the existing bounded physical neighborhoods and adds
65/90 m physical/virtual tiers for regional pedestrians. Visible virtual motion
interpolates between the five-Hz route records. Regional pose updates and seated
driver poses share the existing retrieved 24-32 m / 15-20 Hz / 8-10 Hz policy;
unavailable retrieval uses the same local defaults. No new worker is launched.
Uninstantiated regional residents and traffic continue lightweight journeys.

Construction and route checking are incremental; vehicle obstacle probes reuse
their shape/query at approximately ten Hz. All nearby character/vehicle sweeps,
player actions and combat resolution retain their normal physics rate. No map
collider is retired with a civilian. Gameplay menus never disable simulation.

## Verification and profiling

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
