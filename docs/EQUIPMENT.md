# Equipment library and motion tailoring

The central bipyramid's Tower Exchange has three separate departments:
**Weapons**, **Items**, and **Armour**. Every offer remains free. Weapons includes
all 1,716 new named weapons and the four starters; Items holds Health Glyphs and
129 rings; Armour holds the Scribe robe and 1,064 cosmetic pieces, including
693 shield appearances. Search and family/slot filters stay within a department.
There are six offer rows per page, one preview viewport, and no world pause.
Up/Down or the left stick navigates; Left/Right changes pages, RB changes the
filter, A/Enter acquires one item, and B/Escape returns to the exchange lobby.

Equip purchases in the existing inventory. Four directions remain weapon
shortcuts. Body, Head, Hands, Legs and Shield are cosmetic slots; two ring slots
hold inert accessories. Health Glyph controls and healing remain unchanged.
Inventory rows, equipment assignments and the inspector now show the item's
weapon family or wearable construction and slot, such as Scythe, Cloth Robe /
Body, Plate Gauntlets / Hands or Hood / Head. The original starter equipment,
Health Glyphs and inert rings also have readable types. Lore and weapon arts
scroll within the inspector using the mouse wheel, Page Up/Down or right stick;
the selected type, assignment and menu controls remain visible.

## Named weapons and actual reference motion

The former 1,713 standard counterparts are now named weapons with original names,
individual descriptions and per-item motion recipes. The Fractured Moon, Event
Horizon and The Last Argument also receive the sampled-motion upgrade while
retaining their authored geometry, lore, attack values and art names. Stable
item IDs and ownership serialization are preserved.

The offline retarget pass decodes **383 distinct source HKX clips**, assigned
512 times across 15 motion vocabularies. These cover knives, straight edges,
rapiers, cleavers, greatblades, mauls, longcurves, lances, crescents, glaives,
reapers, paired weapons, knuckles, filaments and conduits. Clips contain up to
60 sampled frames, replacing the previous five-key analytic demonstration curves.

The supplied archive has anonymous animation tracks and no skeleton. An explicit
97/99-track anatomical adapter reconstructs shoulder/elbow/wrist and leg chains,
then maps their directions onto our existing proportions. It retains hand paths,
wrist orientation, hip/chest turns, visual weight displacement and sole contacts.
Root translation is stripped; initial body heading is removed. The CharacterBody,
camera, input vectors and locomotor velocity never receive reference root motion.
Extreme source turns and lifts are bounded to the existing visual rig's reach.
This is a practical reconstruction on our skeleton, rather than a verified
bone-for-bone source-skeleton retarget.

Retargeted swings use a supported forward hip hinge and a forward torso lean
measured in the character's facing frame. This corrects source bends that read
backward on the +Z figure, including strikes with substantial yaw. The adjustment
belongs to the visual pose; movement vectors, facing, authored turns, hand paths
and collision authority retain their existing roles. Starter animation handling
is unchanged.

Each named entry specifies its own basic and art clip order, leverage, support
grip, tempo, stance width and loading weight. Three-stage basics work from either
attack button, with separate compact airborne curves. Four arts use their own
reference gestures. Infusion counterparts retain related visual identities and
share a motion vocabulary, while their recipes and compiled motion/timing
signatures differ. These are **not 1,716 independently hand-keyed performances**.
The quality fixture checks all 1,716 compiled signatures for duplication.

Contact timing is inferred from sampled motion because the selected clips lack
usable hit annotations. The three original named designs retain their existing
hit schedules, retimed against the sampled contact phase. Each existing multi-hit
or charged pulse repeats a visible drive, with a blended recovery between pulses;
this changes animation only, adding no damage events. Heavy and pole weapons use
the existing reachable shared-hilt solver. Damage, momentum, guard strain, chip
damage, parry, iframe, cancellation and stagger resolution remain in the existing
combat pipeline. Named rarity gives no automatic damage bonus or stamina cost.

Sheathed scythes now carry their heads upward in the existing spear back mount.
Custom spears, halberds and staves share that upright long-pole carry. Sword and
paired-blade tips retain their downward angles, and katanas retain their left-hip
mount. These changes affect only the stowed model, preserving drawn grips and
attack geometry.

The supplied DAR archive contains 2,344 clips in total. The selected pass skips
209 category candidates with unsupported track counts or durations. The archive's
whip category has no clips; filament handling adapts the curved-weapon vocabulary.
Conduit/bow/crossbow counterparts still use melee gestures. Projectile and spell
systems are outside this change.

## Wearable construction

All **371 wearable armor pieces** use the Scribe robe's fitted-surface approach,
with a shared `garment_surface.gd` builder also used by the original robe.
Rounded elliptical torso sections fit the waist, chest and collar. Separate
upper/lower sleeves follow the existing shoulders and elbows; layered pauldrons,
abdominal lames, cuffs, knee plates and sabots follow their own joints. Split
curved hems, asymmetric shoulder capes, mantles and tabards have independent
roots and real depth. They are not portrait billboards or a single front panel.

Reference portraits supply central silhouette measurements and dark fabric hue;
curated construction profiles distinguish heavy armor, fitted plate, long robes,
scarves, asymmetry, ragged hems, ridges, crowns, masks, hats, hoods, crests and horns.
There are 359 distinct tailoring profiles. Examples include the broad layered
Lattice vestment, narrow-waisted Horizon plate, long Hearth robe, ragged Parallax
coat and ridged Interval plate. These remain stylized procedural reconstructions
from 2D references, with no claim to sculpted DS3 mesh or texture fidelity.

Split hems follow the corresponding thigh: a front panel clears a forward step,
and a rear panel follows the backward leg. Each panel rotates about its own sewn
hip seam; capes stay attached to their shoulder seams. Flexible robes, tabards,
capes and long ragged skirts have a second free-hem bend with smoothed speed,
acceleration and turning response. Motion trails behind movement and settles
after stopping, including opposite travel while backpedaling or strafing. Plate
tassets articulate with the legs while retaining a firmer
shape; breastplates and joint sleeves do not flutter.

Mounted handling follows the Scribe treatment. On motorcycles, hems fold over
the belt and trail behind the saddle above the rear wheel, even at rest. A cape
keeps its leaned chest attachment while trailing in the hip frame, avoiding an
upright flag behind the head. Enclosed cars and trucks hide long hems and capes
inside the cabin; dismount restores their foot-bound pose immediately. Grounded
compression shortens hems above the floor. Armor adds no collision, defensive
stats, movement restrictions or resource costs.
The existing Scribe robe keeps its hood, inscriptions, tome and pooled trails;
a separately equipped headpiece hides its overlapping hood.

Six previously misclassified labels now occupy their actual head/hand/leg slots.
A narrow version-one save migration recognizes only those six IDs. It preserves
ownership and moves the worn piece to its corrected slot if available; when that
slot is already occupied, the corrected item remains owned and unequipped. All
other invalid equipment assignments still fail validation. Personal save files
are never edited by reference generation or test fixtures.

The Armour department renders pieces on the actual character hierarchy. Head,
hand and leg previews focus the relevant region. Changing department/page/item
rebuilds a mismatched preview; repeated inspection of the same item reuses it.
Long descriptions scroll within the inspector without pushing page controls off
screen. Health Glyphs have their own green geometric preview.

## Content and bounded runtime architecture

The library still contains 2,906 counterparts plus the three early named designs,
for **2,909 new definitions** and **2,920 total catalog entries**. Source infusion
and ring variants retain separate stable IDs. The original crosswalk covers all
2,887 unique CSV IDs and 770 portrait files, adding 19 portrait-only counterparts.
Sixteen source rows lack a matching portrait and use construction defaults.

| Files | Responsibility |
| --- | --- |
| `data/equipment/catalog.json` | Names, lore, geometry, tailoring and per-item motion recipes |
| `data/equipment/named_weapons.json` | Three early named designs, schedules and sampled curves |
| `data/equipment/motions/*.json` | Runtime joint samples and style manifest; no source paths/binaries |
| `scripts/equipment_database.gd`, `item_catalog.gd` | Validated definitions and existing item metadata |
| `scripts/equipment_moves.gd`, `weapon_library.gd` | Lazy per-item combos, arts, charged variants and legacy starters |
| `scripts/weapon_motion.gd`, `combat_body.gd` | Sampled hands, hips, chest and supported feet |
| `scripts/weapon_combat.gd`, `weapon_rig.gd` | Existing hit authority, stable wrist anchors and shared grips |
| `scripts/garment_surface.gd`, `equipment_garment.gd` | Fitted mesh construction and mount-aware cloth |
| `scripts/equipment_cosmetics.gd` | Cosmetic slot lifecycle and joint attachments |
| `scripts/equipment_browser.gd`, `equipment_preview.gd`, `tower_shop.gd` | Separate departments, bounded rows and real-rig previews |
| `scripts/inventory_item_type.gd`, `inventory_ui.gd` | Readable weapon/armor types and scrolling item inspection |
| `scripts/inventory.gd` | Existing ownership plus six explicit slot corrections |

Motion banks load on demand with a **four-bank limit**; compiled moves have a
**24-entry limit**. Weapon/shield geometry retains its 64-entry cache. A weapon
rig holds the four starter sets plus at most one custom model set. Garment
meshes are built only on equip or preview; cloth updates existing transforms.
Flexible panels use two fixed mesh bands instead of rebuilding vertices. An
eleven-panel stress outfit, including its torso and sleeves, uses 81 fixed mesh
nodes and 4,176 vertices. This trades some extra draw submissions for articulated
cloth, with no per-frame geometry allocation or clothing collision simulation.
Normal combat never scans the full item catalog or opens reference archives.
TED-RAG retains its bounded locomotion/pose role, independent of hit authority.

## Rebuilding reference content

The game has no PyNifly, Pillow, NumPy or HKX runtime dependency. The generated
JSON is included in Git. Local source archives, private crosswalks, decoded
analysis, captures and third-party decoder source remain outside public Git.

1. Run `python tools/build_equipment_catalog.py --references <directory>` for
   the base crosswalk/geometry catalog. It preserves an existing named-design
   file, but regenerates the counterpart catalog.
2. Run `python tools/retarget_equipment.py --decoder <private decoder directory>
   --references <directory>` to decode and adapt the selected reference motions,
   then apply named recipes, descriptions and reference-guided tailoring.
   `--reuse-motion` reuses generated banks for recipe/tailoring edits.
3. The offline decoder is PyNifly's `anim_skyrim` module, documented in its
   [primary HKX documentation](https://github.com/BadDogSkyrim/PyNifly/blob/main/docs/hkx_animation_format.md).
   It reads data only; no mod conditions or scripts are executed. Our adapter
   and private provenance audit record the source chain assumptions explicitly.
4. To author a new item, give it a stable unique ID and original lore/geometry.
   A `motion_set` selects six basic clips, four art clips and handling parameters;
   alternatively author all six action keys and their `_air` sequences in `moves`.
   Each motion frame supplies normalized `t`, `right`, `left`, `right_rotation`,
   `left_rotation`, `hip`, `chest`, and optionally `hip_offset`/sole targets.
   No weapon-ID branches belong in the controller. Verify actual hands and
   contact timing using `named_motion_rig.gd` and native captures.

For a packaged export, include the existing game data and
`data/equipment/*.json` **and** `data/equipment/motions/*.json`. A packaged-export
smoke test is still required when an export preset is introduced.

## Verification

All engine fixtures isolate application data and disable game-save persistence.
The quality fixture resolves every weapon's grounded/aerial/charged data, checks
unique compiled motion/timing signatures, constructs all 371 worn pieces on the
actual joints and verifies all six slot migrations. The real-rig fixture samples
every combo/art across all 15 cuts, checking finite joints, sole clearance,
shared grips, stable wrist anchors and unchanged controller state.

`forward_weapon_lean.gd` audits source contact bends and exercises presented
torso lean while standing, advancing, backpedaling and facing different headings.
`weapon_stow.gd` checks registered scythes and representative long poles against
the actual back mount, plus sword/katana/paired carry, unchanged drawn transforms
and repeated equip/draw cycles.

`equipment_cloth_flow.gd` checks thigh support, pinned seams, flexible versus
firm pieces, acceleration/turn response, stopping settlement, vehicle transitions,
stable meshes/joint origins and a store mannequin without gameplay state. Its
17 headless checks run at 30/60/120 Hz. With `--capture`, 20 checks include the
actual sport-bike rider anchors, cloth height above the wheel, triangle
intersection checks against both thighs/shins and horizontal cape trailing on a
leaned rider. Native captures cover walking, motorcycle, car and dismount poses.
Inventory UI regression coverage checks readable types and bounded, scrollable
inspection alongside equipment assignment and existing live-menu behavior.

The integration fixture checks actual authoritative purchases, combos, hurtbox
hits and velocity damage, cancel behavior, equipment slots, version-one saves,
department separation, exactly-once confirms, matched previews and live menus.
Native captures inspect named attack poses, garments, inventory and departments.
`capture_tailored_gallery.gd` renders eight representative reference-guided body
cuts with their runtime geometry. The four starter movesets and existing combat,
parry/exhaustion, dodge, robe, mounted-pose, inventory and performance suites
remain regression coverage. Detailed current results are recorded with this
checkpoint in the repository README.
