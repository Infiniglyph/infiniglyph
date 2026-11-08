# First public recovery checkpoint

Tag: `checkpoint-2026-11-08`  
Engine: Godot 4.7.2, GL Compatibility renderer  
Date: November 8, 2026

This baseline contains the Phase 003 neon city, physical architecture and
skyways, momentum-based movement and combat, four weapon movesets, sparring,
inventory and loot, live menus and unstick recovery, fall damage, and 100
autonomous city residents. It includes the NPC shoulder and forward-knee fixes.

The TED-RAG constraint builder is included for standalone clones. An existing
sibling development copy remains preferred; local animation defaults continue
to work when Python is unavailable.

## Verification

The staged source was extracted to a separate project folder without a sibling
RAG directory, imported in Godot, and tested with isolated application data.
All of the following passed:

- `tests/integration.gd`: movement, collision, stairs, camera and controller input.
- `tests/motion.gd`: procedural pose behavior, live bundled TED-RAG round trips,
  bounded parameters, fallback and helper cleanup.
- `tests/inventory_integration.gd`: 36 checks.
- `tests/defensive_interactions.gd`: 48 checks at 60 Hz.
- `tests/city_population.gd`: 27 checks, including the 160-second routine soak.
- `tests/fall_damage.gd`: 85 checks at 60 Hz.
- `tests/start_menu_unstuck.gd`: 29 checks at 60 Hz with fresh user data.
- `tests/resident_facing.gd`: six checks using the real renderer, including
  slow/fast gait in eight headings and intact shoulder bars.
- `tests/motion_file_lock.py`: live worker recovery from Windows file locks.

These automated checks do not replace hands-on combat and controller feel
testing. See [RECOVERY.md](RECOVERY.md) for a restoration procedure that preserves
current uncommitted work.
