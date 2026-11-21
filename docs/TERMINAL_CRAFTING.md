# Terminal crafting and Civic Access

The existing rental-room storage computer now includes **Craft and recycle**.
Installed storage/crafting equipment uses the same pages in the property menu.
Controller A / Enter selects; B / Escape returns; left/right changes pages.
World time continues while these menus are open.

The terminal lists cuisine, equipment, accessories, recycling and materials.
Recipe details show exact ingredient requirements and quantities from the actor's
inventory plus the accessible terminal storage. Missing ingredients disable Craft.
Output enters the actor's inventory, or terminal storage when that inventory is
full. Equipped gear must be unequipped before recycling.

`data/crafting_materials.json` registers 13 materials. `tomb_bone_shards` is a
stable recipe identifier referring to the existing `bone_shards` inventory item;
existing skeleton drops and saved quantities are preserved. Its dungeon is the
existing Pyramid. The registry can add other dungeon materials without engine
changes. Material items share normal stacks, ownership, drops and save/load.
The new materials are available in the player-only Tower Exchange for testing.

`data/crafting_recipes.json` contains 32 initial recipes: all existing cuisine,
Signal Tonic, the starter sword/shield, Civic Lattice Vestment, Tomb Blade and two
Civic rings. The brief's Basic Sword and Basic Armor map to those actual existing
equipment items; no duplicate example items were introduced. Every registered
Electron Meal requires Electrons. Dungeon requirements use exact material IDs.

`terminal_crafting.gd` stages both inventories off-tree and verifies capacity
before publishing a synchronous commit. Failed operations leave both inventories
unchanged. Snapshot caches are invalidated before property-storage observers run,
and reentrant crafting is denied until final signals finish. Recycling consumes
one unequipped eligible weapon/armor and returns reduced Melted Ore. Known recipes
recover less ore than their input; dungeon fragments/crystals are not refunded.
No coin or XP transactions are created by this crafting foundation.

Code Forms can call `building_civilization.crafting_options_for_native`,
`craft_for_native` and `recycle_for_native`. These require a registered living
identity, property ownership and physical proximity to an installed terminal.
They use the same recipes and owned inventories as player crafting. Existing
career schedules and autonomous production behavior are unchanged by this pass.

Rings now grant passive maximum HP, damage or incoming-damage reduction. Names
choose affinities and rarity determines the budget; the existing item identity
determines a stable roll, including for older items. Save/load, trade and equip
cannot reroll it. Inventory inspection shows the exact bonuses. Only equipped
rings apply; armor remains cosmetic. Raising maximum HP does not heal the wearer.
Signal Tonic uses the existing drink/recovery flow to replenish shields.

Completing Greefer's first confrontation grants the bound **Civic Access Glyph**,
using the existing introduction milestone (either outcome). The pass reveals the
existing outer city and opens its gates/clearance boundary. It cannot be dropped,
sold or recycled. Existing completed journals grant a missing pass on load; a
full inventory defers issuance until space is available. The former demo pickup
no longer supplies this progression item. Script fixtures opt into the exterior
visibility boundary with `--civic-access` or instantiate its controller explicitly.

Ordinary civilian combat bodies now borrow the real owned wardrobe even when no
weapon is equipped. Their previous basic combat fallback remains available.
Every Glyphic Wonders grand column also carries a large rotating hollow geometric
crown, rendered in one shared GPU batch without collision or per-column updates.

Validation: `terminal_crafting.gd`, `crafting_integration.gd`,
`civilian_services_integration.gd`, and the existing economy, equipment, combat,
Greefer and Glyphic Wonders fixtures under `tests/`. The integration fixture's
`--capture` option records native screenshots for clothing, menus and column art.
