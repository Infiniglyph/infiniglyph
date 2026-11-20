# Avat Ar and Glyphic Wonders

The small storefront is centered at world `(-112, 0, -608)`, grid
`LAT 038N / LON 007W`. Its original generated scenery lot is replaced before
geometry is committed. The logical building census remains in its original
order, preserving the existing regional pedestrian, driver and civilian IDs.

## Visiting and purchasing

Use **G / tap RT** at the entrance. The existing deconstruction/reconstruction
transition moves the same player, camera, inventory and wallet into a separate
`World3D`. The hall is 100 by 140 meters and 45 meters high. Its central walkway,
arches, columns, suspended rings and infinity ornaments surround twelve widely
spaced displays. All movement abilities remain available.

Approach a display and use **G / tap RT** to inspect its catalogue name,
description, rarity, family, owned count and price. **A / Enter** confirms the
purchase; **B / Escape** returns. These are individual physical display
interactions. The counter offers permanent glyphs, shop information and Avat
Ar's public history. The menus gate local input while the world stays live.

The counter always sells the existing items:

| Item | Glyph Coins |
| --- | ---: |
| Health Glyph | 20 |
| Light Shield Glyph | 25 |
| Medium Shield Glyph | 45 |
| Heavy Shield Glyph | 75 |
| Respawn Glyph | 15 |
| Home Respawn Glyph | 15 |

Other merchandise uses a positive existing `price` or `glyph_coin_value` from
the shared catalogue. Entries without a positive retail value use explicit
defaults: weapons 80, cosmetics 40, materials 12, consumables 15, miscellaneous
20, and furniture 60. These defaults do not change the item definitions or the
development Tower Exchange's prices. Retired, nontradeable, nondroppable,
developer-only and explicitly excluded entries cannot enter the selection.

## Stock and transaction authority

`GlyphicWondersStock` owns a deterministic seed, saved eligible pool, cycle,
selected IDs and next rotation. The default interval is seven game days, using
the existing civilian clock of one real hour per game day. A configurable
subset defaults to twelve items. Reentry never rerolls the selection; a later
scheduled rotation uses the current catalogue. Display models are presentation
only and never create owned item instances.

Respawn Glyphs and Home Respawn Glyphs are permanent counter stock. Existing
checkpoints that included them in a rotating selection remain valid: they move
to the counter immediately, while the other saved merchandise and rotation
deadline stay unchanged. The next scheduled rotation fills the showcase from
the current eligible catalogue without either permanent respawn item.

Player quotes are bound to the buyer and an actual current display or counter,
then rechecked for proximity, line of sight, stock, price, cycle and expiry at
confirmation. A rotation rejects the old quote without taking coins. Delivery
and coin destruction commit together through the existing economy authority;
inventory or settlement rejection rolls back. Consumed quote tokens and the
authority's reentry guard prevent duplicate delivery. Avat Ar has no wallet or
treasury. Every paid coin is audited as destroyed.
The conservation invariant is circulating balances plus destroyed coins equals
total issued coins; circulating balances alone can now decrease.

## Merchant and civilians

Avat Ar is a unique hovering entity outside the civilian registry and combat
systems. He has no ordinary legs. His pointed hood, layered robes, simplified
glowing hands, expressive face, infinity ornaments and multicolor paintbrush
use original procedural geometry. Two scrolling shader surfaces share one
128-by-256 binary atlas. Animations reuse their meshes and smoothly face nearby
customers; no digit text nodes or per-frame geometry generation are needed.

Public dialogue covers his welcome, merchandise, and role in the beginning of
trade after the Great Blessings. The merchant and store use abstract rings,
arches and infinity ornaments. Future encounter information remains outside
ordinary shop content.

Autonomous civilians assess currently affordable offerings using their needs
and motivations. Two existing nearby pedestrians have a clear route to the
actual frontage; physical arrivals can inspect and shop. Distant or unloaded
residents use bounded model purchases without rendering the hall. Purchases
use their real balances, deliver real inventory items, and create memories.
Only the existing commerce receipt awards eligible civilian experience.
Avat Ar receives no civilian aging, lifetime, blessings, levels or replacement.
Civilians cannot use the player-only Tower Exchange.

## Instances, saves and performance

The `glyphic_wonders/<owner>` context retains collision-only support when
dormant so saved drops still validate on the floor or a pedestal. Entering
builds the hall, merchant and current display models; exiting removes those
rendered objects. Loaded and dormant collision share one recipe. The
architecture is one immutable two-surface mesh batch, with no extra dynamic
lights or particle emitters. Item models reuse the established equipment
preview renderer and are bounded to the current display count.

Shop stock is included in the same atomic checkpoint as inventory, civilian
accounts and world time. Stock validity and clock consistency are checked on
load and in asynchronous save preparation. Older saves without shop state
initialize deterministically from their restored world clock. Offline time
uses the existing capped civilian catch-up before checking for a rotation.
Death in the shop returns to its exterior arrival. The shop is not a permanent
Respawn Glyph placement area. Dropped gear retains its shop location and
doorway guidance outside the instance.

## Verification

Dedicated fixtures cover stock schedules and eligibility, paid transaction
rollback and duplicate guards, checkpoint and worker clock checks, real
architecture/capsule clearance, merchant animation and geometry budgets,
physical and model civilian purchases, and full-world door travel with cold
checkpoint restoration. The travel fixture also verifies drawn Manuscript
transitions, facing, unrestricted Sky Jump/dodge, display-top drops, unloads
and default death reconstruction. Native captures exercise the complete shop,
counter, merchant, display models and inspection menu.
Stock and checkpoint fixtures retain older rotations containing either respawn
item. The purchase fixture buys both permanent glyphs and checks nearby merchant
speech plus the outer counter's shop-menu fallback beyond the speech radius.

Run a fixture using the project's Godot executable, for example:

```powershell
& $GodotPath --headless --path . --fixed-fps 60 --script res://tests/glyphic_wonders_travel.gd
```

Tests use isolated application-data profiles. The existing Windows
certificate-store warning is independent of counted fixture failures.
