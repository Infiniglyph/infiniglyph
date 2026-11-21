# Wands and Dark Box patrols

Wands are ordinary owned weapons available to the player and native Code Forms.
The Tower Exchange and inventory list them under **Weapons → Wands**. Equip one
to any weapon direction; switching, stowing, trading, dropping, and saving use
the existing item identities and equipment rules.

Eight focus colors are available: **Cyan, Violet, Gold, Mint, Pink, Blue, Silver,
and Ember**. Emitters and every laser effect match the equipped color. Cyan is
Dark Box's Standard Arc Wand (`dark_box_arc_wand`); the other IDs are
`arc_wand_<color>`.

Thothic Scepter and Ahkmet's Scepter also use this class, with compact golden
eye/serpent focuses. Their original item IDs, rarity, ownership and drop sources
are retained, so existing copies automatically gain wand handling.

Ready carry turns the body slightly right, plants the right foot ahead and the
left foot behind, and keeps the upper casting arm down with its forearm raised
45 degrees. The empty rear hand hangs relaxed. Blocking presents a glowing
frontal circle in the current wand color, using the normal guard/parry state.
The circle adds no collision, damage or separate defensive resource.

| Controller | Keyboard / mouse | Cast |
| --- | --- | --- |
| LB / RB | Left / right mouse | Short-range laser flicks |
| X | Q | Slither Shot |
| Y | R | Three-bolt laser volley |
| RT + X | V + Q | Ground Cast |
| RT + Y | V + R | Underhand Laser Wheel |

Arts use the existing press, prepare, and release input contract. Holding an art
preserves a single launch. Dodge, guard, switching, and recovery remain
responsive. Flicks deal 22 base damage over 4 m, Slither Shot 30 over 12 m, the
volley 18 per bolt over 14 m, Ground Cast 36, and Laser Wheel 34 over 12 m.
Existing momentum scaling applies. Bumper flicks do not inflict hit stun.

Slither Shot acquires once in a forward cone and has a limited steering budget.
It expires after missing instead of circling back. Ground Cast telegraphs on
walkable ground before its low field activates; jumping clear and dodge
invulnerability both avoid it.

All casts use the shared hit, guard, dodge, terrain, and parry resolver. A parry
cancels the entire cast, including remaining volley bolts or the ground field,
and applies the normal parry stagger to its original caster at any distance.
Remaining energy scatters as brief random visual sparks without an active
hitbox or target acquisition. Dark Box officers have the same vulnerability.
At most 32 wand casts remain active at once.

Dark Box patrols use existing native driver identities and actual owned gear.
Cars carry two officers and bikes one, with red and blue emergency lights.
Dispatch responds to existing witnessed crime cases and the five-Glyph wanted
scale. Officers dismount and use the shared Code Form combat brain, locomotion,
wand moves, and parry recovery. Saved issuance provenance prevents lost or sold
standard wands from generating replacements on encounter reentry.

Native drivers can use shared boost and full top speed on clear straight
routes. NPC light waves use the same vehicle-colored geometry, lifetime,
damage, and contact cooldown as player waves; contacts retain the actual native
driver identity. Patrols use boosted pursuit and light waves under the
applicable wanted encounter conditions.

Definitions live in `data/equipment/wand_equipment.json`, with common moves,
motion, geometry, and cast runtime in `scripts/wand_*.gd`. Future variants only
need an equipment definition using `family` / `combat_kind` = `wand` and their
desired `geometry.tint`.

Focused checks: `tests/wand_equipment.gd`, `tests/wand_projectiles.gd`,
`tests/wand_visuals.gd`, `tests/dark_box_patrols.gd`,
`tests/dark_box_lifecycle.gd`, and `tests/dark_box_checkpoint.gd`. The patrol
fixture also exercises deployed checkpoint loading and rollback through
`tests/dark_box_checkpoint_flow.gd`. Native review frames come from
`tests/capture_wand.gd` and `tests/capture_wand_effects.gd`.

Run a fixture with Godot 4.7.2, for example:

```powershell
godot --headless --fixed-fps 60 --path . --script tests/wand_equipment.gd
godot --headless --fixed-fps 60 --path . --script tests/dark_box_patrols.gd
```
