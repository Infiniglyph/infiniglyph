# World memory and visual attention

The city keeps authoritative geometry, collision, resident identities, routes,
inventories and meeting memories. Rendering reads a cached spatial presentation
of that state. TED-RAG chooses bounded visual-attention budgets; it does not
invent world state or generate geometry during a frame.

`WorldMemory` compiles the static district once into 16 m spatial cells, grouped
by material, primitive and shadow mode. Already-batched geometry is reused.
The current city goes from 677 source meshes to 511 retained/compiled batches.
World-space bounds, geometry elements, colors and near-field shadows remain
intact. Original scene references remain available to collision audits. Fixtures
keep their emissive outlines; distant light/shadow work fades with camera range.
Candidate merges that would exceed Compatibility's eight-light limit retain
their original partitions.

Resident records retain references to the original identity plus current route
and interaction summaries. Invisible, distant resident poses stop rebuilding;
the physical residents continue their journeys, doorway visits and conversations.
Turning the camera retrieves the current state and resumes animation. Residents
near the player always retain full-rate poses. Visible distant residents use
15–20 Hz or 8–10 Hz pose budgets depending on range. Camera movement refreshes
attention immediately, with periodic refreshes every 0.2 seconds otherwise.

## TED-RAG's contribution

The existing asynchronous motion worker also retrieves authored records from
`data/world_constraints.json`, using travel speed, local crowding and a live
sparring-duel flag. The real TED-RAG constraint builder blends the top two
records and returns a 24–32 m full-detail range plus bounded pose rates.
No extra Python worker, network request, model or vector index is started.
Unavailable, stale or disabled retrieval uses local defaults immediately.
Physics, combat permissions, health and menus never wait for retrieval.

This first layer reduces rendering and pose work. It does not unload collision
or replace distant physical simulation with abstract events. Those remain live,
including behind menus. Geometry currently stays cached in memory; spatial mesh
bounds let Godot cull invisible batches. This avoids disappearance on unlimited
sky steps and retains physical rooftops and rails everywhere.

The approach follows Godot's guidance on
[spatially grouped rendering](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html)
and [visibility/detail budgets](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html).

## Verification and profiling

```powershell
godot --headless --path . --fixed-fps 60 --script res://tests/world_memory.gd
godot --path . --script res://tests/world_performance.gd -- --label=memory
godot --path . --script res://tests/world_performance.gd -- --label=reference --disable-memory
godot --path . --script res://tests/world_performance.gd -- --label=paired --paired
```

The performance harness disables VSync and samples native frames in three views,
plus an isolated city-only view. Run it alone. Its logs include median/p95 frame
times, draw calls and diagnostic CPU counters; captures show each sampled view.
Crowd journeys remain live, so outdoor counts and positions vary across runs.
Frame times are hardware- and workload-dependent; draw-call reduction is the
more stable measure. An exported `world_memory_enabled` flag on the main world
supports the baseline comparison without changing gameplay code.

A paired native run at 1280×720 on Intel HD Graphics 620, with outdoor population
capped at 44, produced the following. Both halves share the same light-distance
policy and scene; the comparison isolates batching and pose attention. The
worker is disabled for repeatable local budgets, and live retrieval is tested
separately.

| View | Original draw calls | Cached draw calls | Median frame, original → cache | p95 frame, original → cache |
|---|---:|---:|---:|---:|
| Plaza | 498 | 409 | 27.8 → 21.9 ms | 47.6 → 29.0 ms |
| Boulevard | 248 | 227 | 16.1 → 15.4 ms | 18.5 → 19.1 ms |
| Skyline | 619 | 489 | 21.3 → 19.1 ms | 26.8 → 25.2 ms |

Independent runs varied substantially. The busy plaza still has CPU spikes;
this is an initial optimization layer, not a guarantee of steady 60 FPS.

The implementation is saved at `checkpoint-2026-11-08-world-memory` on the
`perf/world-memory` branch. The earlier `checkpoint-2026-11-08` remains fixed.

The memory suite verifies spatial queries, geometry conservation, live worker
policy changes, fallback, shared-worker use, continued offscreen journeys,
identity retention, full-detail restoration and non-pausing menu behavior.
