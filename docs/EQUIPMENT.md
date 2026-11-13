# Equipment library

The Tower Exchange now has **Browse equipment archive**. Search by original
Infiniglyph name or family, use the category filter, and acquire items for free.
Controller navigation uses Up/Down or the left stick, Left/Right for pages,
RB for the filter, A to acquire, and B to return. Menus keep world time running.
Equip owned items in the existing inventory. Four directions remain weapon
shortcuts; Body, Head, Hands, Legs and Shield hold cosmetics; two rings hold
inert accessories. Scribe robes still occupy Body. Helmets hide the robe hood
while retaining its collar, fitted torso, inscriptions and animated hems.

## Content and reference coverage

There are **2,906 counterparts**: 1,713 standard weapons, 1,064 cosmetic pieces
(including 693 shield appearances), and 129 rings. Three additional named
weapons bring the new library to **2,909 definitions**, alongside the 11 original
catalog entries. Source infusion/ring variants keep separate identities; these
counts do not imply thousands of independent base designs or bespoke movesets.

The three demonstrations are:

| Weapon | Geometry and handling |
| --- | --- |
| The Fractured Moon | Segmented curved blade; circular cuts, reversals and aerial turns |
| Event Horizon | Long spear with a ring around its point; extended thrusts and lunging body poses |
| The Last Argument | Unequal paired blades; alternating angles, rapid combos and crossing exchanges |

Every counterpart has an original name, short lore description, stable type ID,
family, appearance parameters, acquisition record, rarity and future Glyph Coin
value. The named weapons have individually authored grounded and aerial basic
sequences and four arts. Their damage remains an input to the existing
velocity-based impact calculation; named rarity grants no automatic bonus.

`tools/build_equipment_catalog.py --references <directory>` reads the three CSVs
and five supplied ZIPs in place. It preserves every one of the **2,887 unique CSV
IDs**, resolves abbreviated names and internal infusion labels, and adds 19
portrait-only items. All **770 portrait files**, including alternate portraits
of the same armor, are represented in the private crosswalk. Coarse principal-axis
and cross-section measurements guide new solid geometry for weapons/shields.
Armor uses fitted joint-mounted shells, articulated sleeves/greaves and split
cloth panels. Names, descriptions and decorative inlays are original.

The detailed reference crosswalk and animation inventory live in
`.godot/equipment-references/crosswalk.json`, excluded from Git. The 2,344 HKX
clips and 202 text records are inventoried for animation families and conditions;
no foreign-rig clip is imported, converted or executed. Source archives, portraits,
CSV names and animation binaries are not copied into runtime content. Generation
requires Python, Pillow and NumPy; playing the game does not require those image
analysis packages. The generator preserves an existing authored named-weapon file.

## Architecture

| File | Responsibility |
| --- | --- |
| `data/equipment/catalog.json` | Generated counterpart content; no external reference paths |
| `data/equipment/named_weapons.json` | Authored named geometry, lore, timings, combos and joint curves |
| `data/equipment/summary.json` | Reference counts and family totals |
| `scripts/equipment_database.gd` | Loads and validates content once; independent of ownership/input |
| `scripts/item_catalog.gd`, `inventory.gd` | Existing definitions, instances, equipment ownership and version-one saves |
| `scripts/weapon_library.gd` | Resolves item data, family handling and charged variants |
| `scripts/weapon_motion.gd`, `combat_body.gd` | Samples authored hand/hip/chest curves; retains existing planted-foot logic |
| `scripts/weapon_combat.gd` | Item identity, combo progression and existing authoritative hit/guard resolution |
| `scripts/equipment_geometry.gd`, `weapon_rig.gd` | Procedural meshes, stable wrist grips and class-based stow attachments |
| `scripts/equipment_cosmetics.gd` | Appearance-only joint attachments; no colliders or stat modifiers |
| `scripts/equipment_browser.gd`, `tower_shop.gd`, `inventory_ui.gd` | Bounded catalog pages, previews, trusted acquisition and equipment UI |

Geometry has two meshes per piece and a shared **64-entry FIFO cache**. Each
weapon rig retains the four legacy sets plus at most one custom set. The browser
has six item rows and one on-demand preview; its name ordering is prepared once.
Ordinary combat never scans the full catalog or loads reference files. TED-RAG
continues to supply the existing bounded locomotion/pose parameters; physics,
guard, parry, collision, Sky Jump and momentum remain locally authoritative.

## Authoring the next named weapon

1. Copy an entry in `data/equipment/named_weapons.json`. Give it a unique `id`,
   original `name` and `description`. Keep `kind` as `named` and `category` as
   `weapons`. Set the existing handling class in `combat_kind` and the recommended
   canonical `slot`: down/sword_shield, left/spear, right/katana or up/twin_blades.
   Players may assign the item to any of their four directions.
2. Edit `geometry`: supported families, length, width, depth, curvature, guard,
   color, segmented blade, ring head and asymmetric pairing. An optional coarse
   `outline` polygon gives a different solid silhouette. Models extend along
   local +Y; the wrist is the origin. Attachment metadata describes the right
   primary grip, shared support hand or paired left grip, and left-hip/back stow.
3. Author all six action keys (`attack_left`, `attack_right`, `special_x`,
   `special_y`, `special_rt_x`, `special_rt_y`) and their `_air` counterparts.
   Each key contains a sequence. Basic requests advance through that sequence
   during the existing combo buffer; cancellation resets the sequence.
4. Each move supplies name, duration, windup, hit times, reach, arc, base damage,
   side, effect profile and optional five-value body profile. `motion` contains
   normalized `t` keyframes with three-component `right`, `left`,
   `right_rotation`, `left_rotation`, `hip`, and `chest` values. Hand targets are
   in the existing character pose space; rotations are radians. Test the actual
   rig's reach and shared katana hilt rather than authoring unreachable hands.
   Keep hit times after windup and before duration. Existing special charging
   extends hits/damage while preserving the authored contact phase.
5. Restart the game. The registry, archive, ownership, equipment and persistence
   discover the entry automatically; no new weapon ID switch belongs in combat.
   Run `equipment_catalog.gd`, then add focused actor/impact checks for the new
   design to `equipment_integration.gd`. Preserve unique names/IDs and original
   lore; do not establish unresolved canonical factions or creator history.

## Validation and current limits

The catalog fixture validates all definitions, **777 distinct geometry profiles**,
all three named designs, bounded caches and a full 2,909-item ownership checkpoint.
Actor tests cover combos, aerial selection, real hip motion, actual hurtbox
impacts and velocity damage, cancellation, clothing/ring slots, robe compatibility,
save round trips, browser paging/search, trusted acquisition and menu bounds.
The legacy weapon, inventory, shop, combat-motion, charged-sparring and
lock/momentum suites also pass. Native captures review the three named poses,
combined cosmetics, archive and inventory at 1280x720.
`tests/capture_equipment_gallery.gd` renders an additional standalone gallery
of 18 equipment families using their actual runtime meshes.

| Verification | Result |
| --- | --- |
| Catalog, geometry and full-library saves | 14 checks passed |
| Actual equipment/combat/UI integration | 46 checks passed at each of 30/60/120 Hz, plus native 60 Hz |
| Reference classification regressions | 3 Python tests passed |
| Existing weapons / combat motion / charged sparring / lock and momentum | 123 / 146 / 146 / 110 checks passed at 60 Hz |
| Existing model / inventory UI / ownership integration / Tower shop | 55 / 42 / 36 / 35 checks passed |
| Existing performance budgets | 29 checks passed at 60 Hz |

Latest observed headless timings on this machine: roughly **0.29 seconds** to load
the entire catalog, and **0.27 seconds** to construct/validate all 777
profiles in sequence. These are content-load measurements, not rendering FPS or
a full-world performance claim. The existing 29 performance-budget checks pass.

This is a procedural reconstruction from 2D portraits, not finished sculpted
models for every reference. Sixteen CSV entries have no matching portrait and
use family proportions. Standard variants share handling; only the three named
demonstrations have bespoke full movesets. Bow/crossbow and catalyst counterparts
currently use melee handling; ammunition, projectiles and casting systems are
not added. Shield appearances do not alter the existing defensive shield rules.
Rings, infusion-named weaves and cosmetics add no effects, stats or costs.
Acquisition is the free Tower archive; loot can already use these type IDs, but
no new enemy loot tables or currency settlement are introduced.

When configuring a packaged export, include `data/equipment/*.json` and the
existing game data required by its other systems. Keep reference archives,
`.godot`, captures, tests and reference-analysis tools outside the distributable.
