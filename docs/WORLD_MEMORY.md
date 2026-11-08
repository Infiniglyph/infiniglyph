# NPC visual attention

TED-RAG supplies bounded NPC pose-update budgets. The attention manager keeps
resident identity and interaction summaries and changes only resident animation
scheduling. The map uses its original geometry, materials, visibility, lights,
shadows and collision. No city render cache, mesh replacement or light-distance
fade is applied by this manager.

Offscreen, distant resident poses stop rebuilding while their physical bodies
continue journeys, doorway visits and conversations. Turning the camera resumes
poses from current state. Residents near the player retain full-rate poses.
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
