# Founding guilds, functional premises and autonomous careers

This expands the existing civilian authorities. Identity, finite Glyph Coins,
inventory ownership, receipt-based economic XP, witnessed crime and shared quests
remain authoritative. Menus keep the world running. Existing saves migrate without
reissuing blessings, funded rewards or merchant stock.

## Institutions and headquarters

| Faction | Generalist guild | Specialist guilds |
| --- | --- | --- |
| Exploration | Adventurers Guild | The Cartographers; Relic Seekers |
| Underworld | Lit Mob | The Veil; Black Ledger |
| Security | Dark Box | Iron Wardens; The Inquest |
| Commerce | Trade United | The Artificers; Wayfarer Logistics |

The original Adventurers Guild stays at `(-32, 0, -160)`,
`LAT 010N / LON 002W`. Its public boards and the Tavern retain their locations.
The other eleven guilds and four faction headquarters occupy distinct existing
Outer City shells. Each public headquarters has an exterior inscription. Private
Underworld offices have discreet signs and require the existing earned
introduction for affiliation and contract access. Enter and use **G / tap RT**
for the local institution's membership and work. The Adventurers Guild's boards
also provide access to the complete public guild directory.

Initial headquarters addresses (latitude / longitude):

| Institution | Grid address |
| --- | --- |
| Adventurers Guild | 010N / 002W |
| The Cartographers | 010N / 014W |
| Relic Seekers | 018N / 023W |
| Lit Mob | 014S / 018E |
| The Veil | 006S / 022E |
| Black Ledger | 022S / 014E |
| Dark Box | 018N / 009E |
| Iron Wardens | 014N / 022E |
| The Inquest | 022N / 017E |
| Trade United | 010S / 014W |
| The Artificers | 018S / 022W |
| Wayfarer Logistics | 022S / 006W |
| Exploration faction | 022N / 010W |
| Security faction | 010N / 013E |
| Commerce faction | 014S / 018W |
| Underworld faction | 022S / 022E |

These are starting locations; saved institutional ownership and later mergers
remain authoritative.

Faction leadership is separate from guild leadership. Generalists have broader
work scope, not superior rank. Each guild stores its own roster, treasury account,
specialty, governance, headquarters, assets, reputation, relationships and compact
history. Elections, appointments, merit and challenges share native eligibility
checks. Retirement can trigger succession. Supported residents can found or split
an institution with real founding funds; compatible leaders can merge small guilds.
Empty guilds can decline and dissolve. Historical identities and obligations remain.

Member work uses the existing quest system and escrow. Joining one guild does not
join its siblings. Native members may make small voluntary contributions from
their own wallets. Refunds to a closed guild are subsequently swept into its
surviving institution or faction treasury. Mergers also transfer owned buildings.

## Entering and furnishing a shell

The generated manifest contains 600 buildings. Of these, 555 suitable outer
buildings now have actual open doorways, hollow collision, floors, walls, roofs,
lighting and protected stairs. The 44 legacy central structures and the scenery
lot replaced by Glyphic Wonders are explicitly marked for manual review. Their
existing exteriors and specialized entrances are preserved.

1. Walk into an available shell and use **G / tap RT** to occupy it.
2. Obtain real furniture from a shop or the player's free development Tower.
3. In the property menu choose **Install owned furniture or equipment**, or use
   **Place in owned building** from the item's inventory inspection.
4. Move the proposed placement in half-metre increments and quarter turns. The
   menu reports support, wall, overlap, doorway, stair and exit-aisle conflicts.
5. Inspect installed objects to use a seat/bed/storage/terminal or reclaim an
   owned item. Tables cannot be removed from beneath supported objects.

Placement transfers one actual item; removal transfers it back. It does not copy
equipment or purchase another item. Floor, wall, supported-surface and ceiling
mounts use the catalogue's dimensions. Storage preserves identity and properties.
Owners can change use and public/private access independently of physical identity.
Access restrictions always permit the player to leave a building already entered.

There are 56 placeables: 12 residential, 12 commercial, 12 equipment and 20
decorative objects. Furniture is a separate inventory category with filters. The
same definitions and procedural models appear in previews and the Tower. Eligible
items join Glyphic Wonders on its normal seven-day rotation; Health, Shield,
Respawn and Home Respawn Glyphs remain permanent stock. Code Forms never use
the development Tower.

Only nearby interiors instantiate their local five-floor window and furnishings.
Ownership, placed items and storage survive unloading. Native residents consider
nearby vacant premises, install actually purchased goods and can repurpose their
own homes into businesses. Safe regional workplace detours use existing walkers,
physical doorways and verified ground-floor station approaches.

## Food and shield recovery

The 24 added cuisine items comprise eight basic foods, eight prepared dishes,
five drinks and three desserts. Existing Electron Meals and Draughts remain.
Meals/desserts restore HP; drinks restore shield. Restoration is:

`base × quality × (1 + 0.06 × (complexity − 1) + 0.12 × rarity rank)`

Quality is bounded to 0.5–2.0, with an overall multiplier cap of 4. HP recovery is
capped at 350 per serving. Drinks use the existing 250/500/1000 shield capacities
and preserve an already stronger shield. Recovery retains the existing timed
consumption cadence. The default Electron Meal restores 60 HP over two seconds;
the default Draught restores 120 shield over three seconds. Consuming removes an
owned item, and eating alone grants no XP. Loading cancels an old recovery effect.

## Careers, work and businesses

`data/careers.json` registers 74 careers across eight sectors. Two leadership
careers derive from actual institutional positions. The other 72 can be considered
in a bounded daily decision using motives, occupation, resources, equipment,
qualifications, prior work, guild relationships and workplaces. A job title does
not grant coins, skills, guild membership, authority or XP.

Definitions are separate from employment records. Records retain employee,
employer, actual workplace, compensation source, contract, status and history.
Residents can change primary occupation, hold multiple jobs, become self-employed,
operate a business and retire. A paid hire must reference a real accepted, funded
shared quest. Work completion uses existing action proofs, not elapsed time.

Eight reusable templates currently perform real actions:

- Exploration: verified surveys and discoveries.
- Enforcement: patrol arrivals and actual witness investigations.
- Trade: semantic offers that transfer real owned goods and existing coins.
- Delivery: actual requested inventory transfers to a nearby recipient.
- Production: at an installed crafting station, two Light Shards and one Bone
  Shards unit become one Single Chair.
- Food preparation: at an installed cooking station, one Light Shard becomes
  one Electron Meal, using the world's digital material vocabulary.
- Theft: real stolen-item acquisition and independently witnessed criminal trade.
- Administration: trusted recruitment that changes an actual guild roster.

Owned businesses can post funded delivery needs for missing recipe inputs. Crafted
outputs retain provenance, including stolen inputs. There are no generated
ingredients or idle wages. Five distinct verified furnishing installations can
establish the bounded Interior Furnisher specialization through the same validated
capability registry. Unsupported new services remain candidates until an existing
safe capability can represent them.

Ask a nearby native about their identity, then choose **Career and employment** to
inspect their actual primary role, employer, workplace, businesses and history.
The view does not assign a resident's career. Players, monsters, summons, bosses
and Avat Ar stay outside the ordinary employment system.

This foundation supplies shared capabilities, not 74 bespoke production minigames.
Other equipment retains its inspectable interaction placeholder. Full repair,
industrial chains, upper-floor workplace navigation, rent markets and advanced
renovation tools can build on these authorities later.

## Persistence and verification

Optional `building_state` and `career_state` join the existing whole checkpoint.
Validation rejects duplicate item identities across installed furnishings,
property storage, civilian stock, player inventory and world drops. Headquarters,
workers, employers, office holders, contract compensation and clocks are checked
against their actual linked authorities. A failed load restores the prior state.
The background encoder handles private value snapshots; scene/inventory work
stays on the main thread.

Focused fixtures cover guild finance/governance and migration, all catalogue
recipes, food/shield limits, actual work actions, career selection and scale,
placement clearance and JSON round trips, physical stairs/doors, whole-map
registration, live menu input, and full-world synchronous/background checkpoints.
