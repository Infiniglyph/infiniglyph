# Equipment library and motion tailoring

The central bipyramid's Tower Exchange has three separate departments:
**Weapons**, **Items**, and **Armour**. Every offer remains free. Weapons includes
all 1,704 named weapons and the four starters; Items holds Health, Shield and
Respawn Glyphs alongside 136 rings; Armour holds the Scribe robe and 402 cosmetic pieces, including
the Eturnull Hat and Kyren's hat/scarf copies. Search and family/slot filters stay within a department.
There are six offer rows per page, one preview viewport, and no world pause.
Up/Down or the left stick navigates; Left/Right changes pages, RB changes the
filter, A/Enter acquires one item, and B/Escape returns to the exchange lobby.

Equip purchases in the existing inventory. Four directions remain weapon
shortcuts. Body, Head, Hands and Legs are cosmetic slots; two ring slots
hold inert accessories. Health Glyph controls and healing remain unchanged.
Inventory rows, equipment assignments and the inspector now show the item's
weapon family or wearable construction and slot, such as Scythe, Cloth Robe /
Body, Plate Gauntlets / Hands or Hood / Head. The original starter equipment,
Health Glyphs and inert rings also have readable types. Lore and weapon arts
scroll within the inspector using the mouse wheel, Page Up/Down or right stick;
the selected type, assignment and menu controls remain visible.

## Named weapons and actual reference motion

The 1,685 active reference weapon counterparts are named weapons with original names,
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

Sampled hand paths and wrist frames are converted from the motion bank's -Z
forward convention into the figure's +Z front at playback. Extreme windups ease
into a small rear shoulder workspace instead of reaching an arm's length behind
the back. Retargeted elbows use an outward, slightly forward bend relative to
the animated chest, with a stable fallback for a degenerate pole direction.
Existing contact schedules, charged/multi-hit retiming and recovery blending
continue to control the sequence; this adjustment changes the presented pose.
The return to ready blends shoulder-relative hand endpoints over 0.16 seconds.
Named-arm IK blends the bend direction and reachable endpoints together, avoiding
independent joint-rotation flips during airborne recovery. Low pose influence
returns to the existing animated arm endpoints. A fresh attack, guard, dodge,
reaction, weapon change or sheathe can take over immediately; this adds no
combat recovery time or action lock.
Raised shared grips follow a small forward arc during that return, avoiding
the shoulder's near-zero reach while preserving the exact resting stance.

Each named entry specifies its own basic and art clip order, leverage, support
grip, tempo, stance width and loading weight. Three-stage basics work from either
attack button, with separate compact airborne curves. Four arts use their own
reference gestures. Infusion counterparts retain related visual identities and
share a motion vocabulary, while their recipes and compiled motion/timing
signatures differ. These are **not 1,688 independently hand-keyed performances**.
The quality fixture checks all 1,695 compiled signatures, including Kyren's
authored katana recipe, for duplication.

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

Greatswords retain their downward carry, with the back mount raised to fit the
actual outlined blade. Every registered greatsword has at least 40 cm of tip
clearance at rest, leaving room for crouching without shortening its model.
Leg cosmetics enclose the ankles with closed boot soles and hide the underlying
glowing feet while equipped. Removing them restores the bare feet; catalog
previews use the same fitted boots.

All RB/LB light attacks deal damage without hit stun, including named combos and
aerial variants. Weapon arts retain fortitude-based interruption, and light
attacks still obey normal blocking, guard strain, dodging and parry rules.

The supplied DAR archive contains 2,344 clips in total. The selected pass skips
209 category candidates with unsupported track counts or durations. The archive's
whip category has no clips; filament handling adapts the curved-weapon vocabulary.
Conduit counterparts still use melee gestures. Bows, crossbows and talismans are
retired; projectile and spell systems are outside this change.

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

**Void Soul Greaves** are original Legs cosmetics inspired by a layered
waistcloth silhouette. Cyan, violet, gold, mint, pink, blue, silver and ember
editions share a single cut: four weathered outer folds, front and back scale
aprons, a clasped belt, wrapped greaves and closed boots. Their description
recalls a gift from the void to a weary traveler. All eight are available through
Tower Exchange / Equipment Archive and use normal ownership and checkpoint
persistence. Cloth uses the existing movement and vehicle folding system;
there are no new defensive bonuses or movement restrictions.

## Flexible whips and returning discs

All existing whip definitions use a tapered 24-link lash on the hand rig.
Windup, a traveling bend, the crack and slack recovery use the named filament
motions. Hurt volumes follow the rendered centerline during short contact
windows; sword fans and rigid segmented-rod visuals are removed for whips.
The stowed/catalog model is coiled. Light attacks retain the shared no-stun rule.

**Vector Disc** and **Twin Vector Discs** are single/dual weapon families. RB/LB
(and the existing mouse attack buttons) use quick knife-style cuts. All four
weapon arts (X/Y/RT+X/RT+Y; Q/R/V+Q/V+R) launch real spinning discs approximately
seven meters. Ready discs point down with their faces turned sideways to clear
the body, and back-mounted circles sit between the
shoulder blades, with the single disc centered. RT+X/RT+Y use cartwheel/vault
motions with authored hip turns and scissoring legs. Different release points
feed curved outbound paths that converge on a locked target. Discs return to
the moving hand along broad circular arcs, hit at most once per target on
each flight leg, and deal 55% damage on return. Charge increases damage without
adding extra projectiles or range. Normal block, dodge, parry and the one-second
attacker stun apply. Cancellation, switching, sheathing and death reclaim flight
geometry and hitboxes. No new resource, input mapping or movement restriction
is introduced. Search by name or use the Discs family filter.

**Respawn Glyph** and **Home Respawn Glyph** appear in the Items department and
consumable filter. Inventory placement consumes one item to bind a reusable
marker on clear solid ground. Each owner keeps one marker of each kind;
replacement affects only that kind. Death offers personal, Home and default
destinations using controller, keyboard or mouse without pausing simulation.
Neither marker is consumed by death. Both destinations, facing and camera view
persist through checkpoints, including placements in the owner's dungeon.

The pyramid entry encounter also registers **Khopesh of the Warden**, **Tomb
Blade**, **Warden's Wraps**, **Linen Bindings**, and the inert **Jackal Pendant**.
Gear copies and collectible remnant glyphs use the existing loot authority and
checkpoint format. Glyph rarity and visible size follow enemy difficulty:
cyan/Common for skeletons, violet/Uncommon for guardians, gold/Rare for the
exalted guardian. Bone Shards are collectible materials; no crafting system or
unrequested stat bonuses are activated.

B2 adds **Horuswing Blades** (curved twin blades), **Sentinel Spear**, **Falcon
Sentinel Mantle**, **Skyguard Tassets**, and **Eye of Horus Seal**. All use owned
equipment slots, catalog previews, Tower Exchange offers and existing save
validation. The cloak, tassets and wrist seal use the same batched procedural
geometry worn by the aerial guard. Closed greaves hide the underlying feet.
The accessory follows existing cosmetic ring rules. Falcon defeats choose a
gear copy from all five items, plus an Uncommon or elite Rare remnant glyph;
airborne rewards settle on supported ground in their own dungeon World3D.
Dungeon enemies reset after player death or exiting the instance, including
defeated enemies. These resets preserve dropped equipment and remnant glyphs;
moving between floors keeps current-run clears.

## Content and bounded runtime architecture

The library contains 2,185 active counterparts, three early named designs,
the Eturnull Hat and Manuscript, Kyren's katana, straw hat and scarf, and eight
Void Soul Greaves editions, plus twelve pyramid/disc designs, 22 B3-B7 designs
and seven B8 boss designs, for **2,242 additional definitions** and
**2,264 total catalog entries**, including six remnant/material definitions and
two placeable respawn glyphs. The original 693 cosmetic shields, eight
talismans, twelve bows and eight crossbows are retired. All 721 exact IDs in
`retired.json` support validated save migration, including ownership, equipment,
world drops and loss markers. Retired weapons cannot be purchased or minted.
The starter weapon's functional shield remains. Source infusion
and ring variants retain separate stable IDs. The original crosswalk covers all
2,887 unique CSV IDs and 770 portrait files, adding 19 portrait-only counterparts.
Sixteen source rows lack a matching portrait and use construction defaults.

| Files | Responsibility |
| --- | --- |
| `data/equipment/catalog.json` | Names, lore, geometry, tailoring and per-item motion recipes |
| `data/equipment/scribe_equipment.json` | Original Eturnull Hat and Manuscript definitions, stats and moves |
| `data/equipment/pyramid_equipment.json` | Single/twin discs, five entry-floor drops and five B2 drops |
| `data/equipment/pyramid_depth_equipment.json` | Six B3-B7 weapons, eleven clothing pieces and five cosmetic keepsakes |
| `tools/build_pyramid_depth_equipment.py` | Reproducible authored depth equipment definitions using native motion recipes |
| `scripts/pyramid_regalia.gd`, `scripts/pyramid_depth_visual.gd` | Shared temple clothing, animal masks, lionesses, serpents, scorpions and constructs |
| `scripts/falcon_regalia.gd`, `scripts/pyramid_wings.gd` | Batched shared feathers, clothing, greaves and two-root wing animation |
| `scripts/falcon_brain.gd`, `scripts/falcon_combat.gd`, `scripts/falcon_moves.gd`, `scripts/pyramid_arrow.gd` | Observable aerial pursuit, timed shared attacks and enemy-only swept arrows |
| `scripts/whip_presentation.gd`, `scripts/returning_disc.gd` | Flexible cord contacts and swept returning weapon flight |
| `scripts/disc_moves.gd`, `scripts/combat_body.gd` | Dagger-style rim cuts and movement-compatible full-body throws |
| `scripts/respawn_glyphs.gd`, `scripts/respawn_glyph_marker.gd`, `scripts/respawn_glyph_data.gd` | Safe owned placement, reusable markers, death choice and checkpoint validation |
| `data/equipment/void_soul_equipment.json` | Eight original Void Soul Greaves color editions |
| `scripts/void_soul_weave.gd` | Batched scale aprons and split cloth on the shared garment rig |
| `data/equipment/kyren_equipment.json` | Kyren's named katana, ember hat and flowing scarf; equal-chance copies awarded through boss defeat loot |
| `scripts/kyren_hat.gd`, `scripts/kyren_cosmetic.gd` | Shared NPC hat geometry and wearable Head/Body copies with actual pooled effects |
| `scripts/eturnull_hat.gd` | Head-mounted geometry and pooled symbol-to-equation rain |
| `scripts/scribe_moves.gd`, `scribe_presentation.gd` | Conducting, shared writing/contact paths, open book, pages, quill and hip stow |
| `scripts/equation_trace.gd`, `equation_trace_settings.gd` | Held-quill RT X/circle tracing, world-space mathematical contacts, single reflection and bounded tuning |
| `scripts/persistent_trail.gd` | Bounded segment storage and lifetime fading shared by vehicle and equation trails |
| `data/equipment/retired.json` | Exact historical IDs used only to validate and retire old save entries |
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

`equipment_fit_and_light_hits.gd` passes 43 checks at 60 Hz. It checks all 223
greatsword mounts, 98 tailored leg cosmetics and seven custom temple/royal leg
sets, closed soles, foot restoration, inventory/preview coverage, grounded/aerial
light combos, repeated hits against both duelists, immediate dodge access,
preserved attacks/charges, and unchanged parry and weapon-art stun. Use
`-- --capture` for `captures/equipment_fit_greatsword.png` and
`captures/equipment_fit_boots.png`.

`natural_weapon_arms.gd` follows actual shoulder, elbow and wrist chains over
all fifteen handling cuts, grounded and airborne combos, modified and charged
arts, and multiple headings. It checks hand workspace, shared grips, anatomical
lengths, unchanged move data and physics, and the half-second return to rest.
Continuity is measured relative to the chest so a coherent torso turn is not
mistaken for an independent elbow flip; world speeds remain diagnostic. Fresh
attacks, timed guards, dodge and sheathing also interrupt that visual return.
Close native captures inspect windup, contact, recovery and ready poses.

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

## Eturnull equipment

See the [current Eturnull gameplay notes](../README.md#eturnull-equipment-and-scribe-combat)
for controls, acquisition, active hit geometry and the save migration. New Scribe
weapons use `family` and `combat_kind` set to `scribe`, `geometry.renderer` set to
`scribe`, their own `guard`, and authored `moves` with `equation`, `scribe_shape`,
`stroke_radius`, timing, reach and damage. Their strokes supply both rendering and
collision contacts through the existing combat resolver. The Manuscript's
continuous RT arts are a deliberate item-specific extension; other Scribe
weapons keep their own authored arts. The hat uses `geometry.renderer = eturnull_hat`.

The Scribe tuning pass adapts nine distinct existing named-weapon gestures into
the conducting arm while keeping the book arm supported. Anatomical sides are
explicitly corrected for the figure's historical arm-node names. Light stages
use the starter twin-blade timing; writing and corresponding contact capsules
reach the spear's seven-metre art range (9.1 m at full charge). The Manuscript's
base heavy damage is 30; light stages are 13/16/18/17 and the two unmodified arts
are 28/24 per pulse, with matching aerial values and the existing charge/momentum
bonuses. Ordinary equations follow camera yaw and pitch. Holding RT/V takes the
quill into the right hand; RT+X/V+Q and RT+Y/V+R trace persistent X/circular
mathematics, with tiny taps, 3 s lifetime and the vehicle trail's 750 damage /
0.5 s contact cooldown. A/Space jumps during an active trace; RT+A/V+Space uses
a Shield Glyph otherwise. A normal parry redirects intercepted sections once,
preserving the one-second attacker stun; redirected ink can hit its author and
cannot be parried again. `equation_trace_settings.gd` exposes tracing, appearance,
contact, lifetime, reflection and bounded-geometry tuning. Vehicle appearance
and gameplay remain unchanged.
Ready stance is
weighted over the rear left foot, with the right arm relaxed and nearly straight.
The quill has its own shoulder-high hover a metre to the right, with a smoothed
world-velocity trail capped at 30 cm. Attack writing and the book entry/exit
transitions still take over its tip. The hat
now sits 13 cm lower and uses the robe's five-color mathematical palette.
Its crown reuses 16 flat glyph instances: they emerge at the central tip, flow
radially across the conical surface, fade near the brim and cycle cached shapes.
Their tangent planes sit above the opaque fabric and follow the hat's motion;
the existing 44-glyph brim rain retains its independent equation formation.
During phase dodge, the hat and Scribe attachments retain their local poses and
resume animation on arrival. Their render updates cannot overwrite the shared
phase material or counteract the character's temporary compression.
The closed Manuscript and the robe's belt tome orient their page fore-edges
forward and their broad covers sideways against the hip. The Manuscript's
stow orientation accounts for the leaf hinges rotating during closure.

## B8 keepsakes

`tools/build_ahkmet_equipment.py` builds seven original equipment definitions in
`data/equipment/ahkmet_equipment.json`. Ahkmet's Scepter uses the existing staff
motion family and a solid golden-light shaft with a double halo/serpent focus.
Lorai's Fangblade uses the existing sword family with an original curved outline.
The Nemes, Mantle, Bracers and Greaves occupy Head, Body, Hands and Legs;
Serpent Crown of Union is an alternative Head cosmetic. `ahkmet_regalia.gd`
shares their joint-mounted geometry with Ahkmet and equipment previews. None of
the cosmetic pieces changes stats. The Apep–Lorai Catalyst is a stackable rare
material, not a new power or resource system.

The first B8 clear grants all seven copies plus one catalyst and a Rare remnant;
repeat clears grant a random fresh gear copy, catalyst and Rare remnant. All
copies receive fresh item identities through the existing loot service. The
inventory's validated `boss_reward_claims` stores the first-clear entitlement in
the same atomic checkpoint as ownership and unclaimed drops. Death/exit resets
the encounter, rather than the already earned entitlement. Tower Exchange and
Equipment Archive list the new equipment through the normal registry.
