# Code Form civilization foundation

The civilian society uses the existing city movement, regional population,
TheftReactions combat/respawn, inventory, civilian economy and checkpoint systems.
It does not classify entities from their combat base class: an explicit civilian
identity connects a body to the logical registry. In particular, a hostile
ResidentFighter remains the same civilian, even though it extends Player.

## Scope and migration

The default world registers 1,122 civilians: the 100 original city residents,
780 regional pedestrians, 238 vehicle drivers and four establishment residents.
Pedestrian and vehicle display profiles previously repeated the original names
and profile IDs; they now have separate persistent identities. Ejecting a driver
changes that person's physical representation while retaining their identity.

The stable population slot identifies a physical role, such as `hub/aven`,
`region/17`, `driver/4` or `service/guild_receptionist`. The individual occupying
that slot has a separate identity. A lifetime replacement changes the individual,
name, personality and motivations without allocating another population slot.

Player characters, bosses, dungeon enemies, monsters and temporary summons are
excluded. No player XP, leveling or lifetime system is introduced. Existing
damage, movement, weapon animations and dungeon enemy respawns remain unchanged.

Economy checkpoints from versions one through four migrate to the audited
version-six ledger.
Existing wallets, treasuries, rentals, room storage and guild crystal stock retain
their values. Newly identified civilians receive their opening 100-coin blessing
once; old residents do not receive another opening payment. A legacy checkpoint
without a civilian clock starts at its latest paid blessing boundary, with fresh
100-year civilian lifetimes. Rental and lost-item deadlines retain their existing
real-world Unix timing.

### One-time starter capital

The current native population receives an additional, host-issued coin influx
once governance and checkpoint restoration are complete. It applies to existing
saves as well as new worlds. The amount uses the person's current occupation,
active employment, business ownership and actual elected/appointed offices:

| Position | Additional coins |
| --- | ---: |
| Ordinary resident | 500 |
| Routine worker / active employment | 800 |
| Merchant / establishment keeper | 1,200 |
| Active business owner | 1,800 |
| Active guild leader | 2,400 |
| Faction leader | 3,200 |

Use the highest applicable tier, plus 50 per level above one, capped at a 500-coin
experience bonus. Positions do not stack payments. Ended jobs, closed businesses
and dissolved guilds do not qualify. `code_form_starter_capital.gd` owns the policy
and builds position indexes once, rather than scanning every job per citizen.

The influx adds to existing wallets; it does not set balances to a target or pay
repeatedly when they run low. A single audited `starter_influx` event records the
complete active census and exact payouts. Its boolean receipt folds into the
audit base when journal history is compacted, preventing repeats after reload,
death, travel, changing jobs or leadership succession. New individuals born after
the rollout retain the ordinary empty-wallet and equal-blessing rules. Players,
bosses, monsters and Avat Ar receive none. Grants generate no commerce XP.

Only this explicitly requested influx increases `issued_total`; ordinary trade,
wages and organizational funding still transfer existing coins. Strict replay
validation rejects partial censuses, outsiders, fractional amounts, over-cap
issuance and duplicate receipts before committing any wallet mutation.
The isolated fresh-world fixture issued 853,100 additional coins to 1,122 people;
existing saves vary with their current offices, careers and experience.

`tests/code_form_starter_capital.gd` covers tiering, atomic issuance, migration,
guards, JSON restore, compaction, duplicate rejection and later blessings.
`tests/starter_capital_integration.gd` exercises the production civic loop and
complete checkpoint save/load with all 1,122 citizens.

## Clock, life and progression

`code_form_civilization.gd`, attached directly to World, owns the authoritative
clock. The clock continues when the outdoor scene is disabled inside a pyramid
or rented room, and while menus are open. It updates once per real second.

Defaults live in `CodeFormRegistry.DEFAULT_CONFIG` and are persisted with the
society:

| Setting | Default |
| --- | --- |
| Real seconds per game day | 3,600 |
| Logical seconds per game day | 86,400 |
| Days per year | 365 |
| Starting lifetime | 100 years |
| Additional lifetime per level | 100 years |
| Maximum level | 100 |
| Blessing interval / amount | 30 days / 100 coins |
| Offline catch-up cap | 21,600 real seconds (six game days) |
| XP cost for the next level | 100 × current level |

The stored expiry time is independent of level. Leveling adds lifetime to it;
it does not reset elapsed time. Level 100 has received a total of 10,000 years,
less the time already lived. Combat death retains XP, level, remaining lifetime,
memories, relationships, wallet and identity, and uses that civilian's persisted
overworld respawn descriptor. Driver respawns use nearby pedestrian ground rather
than the center of their vehicle collider.

Permanent expiry marks the old identity inactive and creates exactly one new
Level 1 individual. The old wallet and goods remain in the economic history;
the new wallet begins empty. Active combat proxies, doorway reservations and
scheduled actions of the old person are released before the slot is reused.
Important old memories and relationships remain archived.

## Events and economic integrity

Only successful, meaningful events earn civilian XP. The reusable interface is:

```gdscript
world.civilization.record_event({
    "event_type": "discovery",
    "actor_id": civilian_id,
    "target_id": "location/example",
    "rarity": "rare",
    "significance": 0.8,
    "event_id": "unique-authoritative-event-receipt"
})
```

Common/uncommon/rare/epic/legendary/unique rewards are 8/24/80/240/800/2,400 before
significance and novelty adjustments. Categories include combat, exploration,
discovery, crafting, economic, social, guild, construction and organization.
The event API is host-owned; an arbitrary client or dialogue string cannot
mint XP or currency. Repeating an idle animation or training routine earns none.

A persistent bounded receipt Bloom filter rejects duplicate event IDs, including
after reload. Semantic repetition pays 100%, 50%, 25%, then zero. When older
non-economic semantic counters leave the working set, a persistent semantic
filter prevents those achievements being farmed again with new receipts.
Bloom filters may conservatively deny a genuinely novel event after sufficient
history; they never grant an extra reward because of a false positive.

Economic XP comes from the existing ledger's committed commerce receipts.
Buying an actual meal, selling an owned crystal, paying rent or completing paid
work is eligible. Rewards scale with the square root of the coin amount, capped
at an amount of 10,000, and diminish by context/counterparty within a game day.
Founder transfers, blessings, generic transfers and consuming an already purchased
meal generate no circulation XP. Shared contract proofs prevent replaying
the same paid work. A human purchase can reward the civilian merchant; it does
not create a player progression record.

NPC inventories hold actual ordinary item instances. A tavern meal transfers
existing coins to the tavern; crystal sales and funded work require real institutional
funds. Finite treasuries can run out, which influences future civilian goals.
Glyphic Wonders currently offers an NPC cyan-mantle pattern purchase for five
coins: the item is delivered and the payment is destroyed. This does not change
the existing player's Tower Exchange or add an unlimited merchant treasury.

The audit invariant is `sum(all balances) + destroyed_total == issued_total`.
Blessings mint separately from transfers and destruction. Retired identities
are excluded from future blessings. Checkpoints reject disagreement between the
registry's current/historical identities, ledger eligibility, and paid clock cycle.

## Decisions, memories and relationships

Each civilian has weighted survival, security, wealth, social, knowledge, mastery,
novelty and loyalty motivations. Selection accounts for personality, hunger,
finances, remaining lifetime, recent combat, previous failed work, friendships
and discoveries. Available goals are work, trade, eat, socialize, explore, rest,
train, guild and wonder.

Nearby city bodies choose validated destinations on their existing neighborhood
route graph. Discoveries come from completed arrivals, rather than merely
selecting a route. New friends influence future social destinations; known places
lose their novelty. Existing talking, fleeing, doorway transit and combat take
precedence. Regional journeys retain their existing road/path collision checks.

Unloaded or distant civilians perform coarse logical actions: funded services,
actual purchases/consumption, owned-crystal sales, social encounters and guild
membership. Visible civilians complete suitable local work at real arrivals.
The current city graph does not connect every neighborhood to the new guild and
tavern, so background commerce does not invent paths or teleport bodies to shops.
Crafting, contracts and construction have event hooks but no new content system.

Each active person keeps at most 24 meaningful memories, 24 relationships and
128 semantic working counters. Friendly player conversations improve trust at
most once per game day; repeated button presses cannot erase a remembered assault.
Combat memories change dialogue and safety preferences. Existing anger still
resets after NPC/player death; a bad relationship does not automatically restart
hostility. Service staff offer a conversation about their current plans.

## Persistence and performance bounds

Logical decisions process 12 civilians per once-per-second batch. The clock and
lifetimes cover the complete population without running a full brain or physics
body per person. Civilian inventory nodes have processing disabled. Offline
catch-up advances at most six real hours and performs one bounded coarse census
pass, not a replay of thousands of movement/combat frames.

Society, schedules, clock timestamp, inventory ownership and the audited economy
join the existing atomic checkpoint. Startup catch-up runs once after a coherent
load; manual reload restores the saved world rather than awarding another offline
payment. Lifetime/blessing batches roll back together on rejected ledger actions.
Physical replacements occur only after a successful model/financial commit.

Background transaction notifications are coalesced with the periodic civilian
checkpoint; ordinary player inventory/economic actions retain immediate save
requests. Autosaves capture ownership on the main thread, then validate civilian
value data and encode JSON on one private worker. The main thread atomically
commits completed bytes. Changes during encoding queue a newer capture; manual
load/save joins and discards an older pending encoding before proceeding. No
scene objects or live mutable model containers are operated on by the worker.
The current capture uses detached inventory values and immutable warmed copies
of changed model rows, described below. Complete validation runs in the private
worker before any bytes are committed.
The checkpoint byte limit is 128 MiB, expanded from the former item-only 8 MiB.
Normal early-population saves remain far smaller; saturated memory/novelty states
can legitimately exceed the old ceiling.

Measured isolated scale fixtures produced these checkpoint sizes:

| Civilian count | Early state | Full working sets | Maximum-length memories |
| --- | --- | --- | --- |
| 1,122 | 2.04 MiB | 19.01 MiB | 33.10 MiB |
| 2,048 | 3.80 MiB | 34.68 MiB | 60.37 MiB |

An earlier isolated 1,122-person model fixture, without the later civic/career
adapters, averaged about 8 ms per batch. Economy membership optimizations reduced
median encoder dispatch from 217 ms to 96 ms in its separate local fixture.
These are wall-clock observations, not whole-game FPS guarantees. Capturing and
committing a large state still costs main-thread time; explicit save/load and
very large historical worlds can take longer. Background encoding removes the
largest JSON/registry work from ordinary gameplay frames.

Bounds are 2,048 active civilians, 16,384 retained historical records and one
active-census generation of replacements per advance. An excessive configured
advance or full historical capacity returns an explicit error and leaves the
batch unchanged. This foundation does not silently discard old wallets or mint
unbounded replacements. Long-running worlds approaching the historical cap will
need a future archival policy. This is deterministic local simulation and needs
no external language-model API.

### Shared weighted components and indexes

The existing TED-RAG worker already blends authored constraints using
`C(x) = sum(w_i * C_i(x))`. Code Form goal selection now reuses equivalent
weighted components: every affordable item in a shopping category has the same
motivation terms, so four category minimum prices replace repeated per-item
evaluation. The current offered subset is summarized once within a twelve-person
batch. Rotation or stock restoration invalidates it immediately; an unknown
stock provider stays uncached. Standalone decisions read fresh offers, and the
transaction authority still revalidates each real purchase independently.

Sorted active identities are reused until admission, lifetime replacement or
restore. A property index replaces repeated whole-city ownership/tenancy scans,
with model revisions invalidating it. Both indexes preserve the previous order
and return caller-owned arrays. These caches are transient and bounded; save
schemas, clock rate, decision cadence, identities, memories and economic rules
retain their existing behavior. TED-RAG keeps its existing single asynchronous
motion worker and bounded pose policy.

The production-world CPU fixture includes all 1,122 citizens and the current
career, guild, property and shop adapters. On the local i5-7200U with Godot 4.7.2
debug, after 96 warm-up ticks and across 256 sampled one-second advances. Both
versions include the same starter-capital policy and current founding governance:

| Society clock and autonomy | Before | After |
| --- | ---: | ---: |
| Mean CPU time | 45.75 ms | 28.56 ms |
| Median CPU time | 38.32 ms | 22.94 ms |
| 95th percentile | 82.94 ms | 60.64 ms |

The mean reduction is about 38%. Both runs retained 1,122 citizens and produced
4,224 decisions, 1,300 completed actions, 885 employment records and 184 contracts,
with conserved finite coin supply. This diagnostic freezes rendered bodies and
times direct production simulation/service calls. It measures logical CPU cost;
it is not a frame-rate comparison. Rendering and other desktop activity remain
separate sources of variability.

Run `tests/code_form_simulation_profile.gd -- --label=local` with an isolated
application-data profile to write the component timings under `.godot/`.
`--diagnostic` additionally times nested autonomy and authority callbacks.
`tests/code_form_constraint_cache.gd` compares 560 weighted utility cases with
the original scan and exercises admission, replacement, tenancy, rotation and
checkpoint invalidation. `tests/weighted_constraint_integration.gd` checks the
real asynchronous TED-RAG builder, worker reuse, normalized weights and fallback.

## Verification

Contract employment now reconciles at quest completion and before the civic
board publishes/prunes more contracts. A transient index visits only active
contract jobs; it is rebuilt from authoritative employment records after load.
An expired/pruned quest cannot leave a job marked active until that NPC's next
AI turn, which previously caused checkpoint validation to fail. Cleanup does not
pay wages, change rewards or relax the linked-save validators.

Autosaves coalesce changes for 0.75 s, wait at least 15 s between completed jobs,
and retain dirty live state across failures. Retries back off from 15 to 120 s;
the initial failure is shown once and the validation/commit stage is logged.
Changes during encoding still schedule a newer checkpoint. Manual saves and
loads discard older jobs before their existing atomic authority boundaries.
`tests/autosave_recovery.gd` covers contract churn, repeated strict disk round
trips, coalescing, updates during encoding, a real disk failure and recovery with
the newest inventory. `tests/career_system.gd` covers restored/pruned job cleanup.

Dedicated fixtures cover registry identity/lifetimes/events, economic ownership
and migration, bounded autonomy, whole-world checkpoints/instances, physical
combat/driver lifecycle, background checkpoint encoding and logical scale/save
size. Existing civilian services,
input, menu, establishment, persistence and theft-combat fixtures are also rerun.

| Fixture group | Checks |
| --- | ---: |
| Registry / lifetimes / events | 46 |
| Civilian economy version two | 52 |
| Autonomy | 29 |
| Physical combat / driver / expiry lifecycle | 19 |
| Whole-world society / checkpoint / instance integration | 51 |
| Scale / saturated checkpoint size | 28 |
| Background checkpoint encoder | 43 |
| Existing economy, services, menus, input, architecture, persistence, theft, startup and inventory integration | 288 |
| Total | 556 |

Run an individual fixture with the project's Godot executable:

```powershell
& $GodotPath --headless --path . --fixed-fps 60 --script res://tests/code_form_civilization.gd
```

The existing Windows certificate-store warning may appear in headless stderr.
It is separate from fixture failures, which are explicitly counted and exit
nonzero. Test artifacts use isolated application-data profiles and do not touch
the player's ordinary save.


## Visible civilian life, survival and status

Civilian Code Forms now have separate food and water meters. These are not
player resources. Zero need debt is full; at 80% debt (20% remaining), the meter
turns red and begins costing HP. A full food meter lasts 3,600 real simulation
seconds; water lasts 1,800. Red food costs 1 HP/second and red water 2 HP/second.
The analytic calculation charges only time actually spent in red, including
coarse updates. A paid, owned meal restores food and its ordinary healing;
a drink restores water independently. Existing combat reconstruction retains
identity, memories, money and possessions and resets the survivor's needs.
There is no survival assault, wanted report or free combat XP.

Within ten metres in the same World3D, pedestrians show food, water and clothing
Drip. These small indicators yield to a speaking bubble. Identity conversations
and establishment conversations expose the same data. No distant translation,
per-frame census scan or player survival bar is introduced.

The first physical loop uses nearby regional street routes connected to the
Electron Tavern. At most six residents have tavern visits at once. A visitor
must start within 96 metres and pass the existing capsule sweep, ground and
route-length checks. Their actual walker enters the public door, reaches the
counter, pays existing coins for actual inventory items, reserves a free chair,
sits, consumes those items and walks back out along the validated route. An
unaffordable order can lead to a fifteen-second tavern shift, paying twenty coins
from the finite tavern account. The existing service proof prevents the same
half-day shift being paid twice. A broke business declines work; it cannot mint
wages. This is a local connected demonstration, not global navigation through
unconnected walls or teleporting residents to a shop.

Up to three pairs of reciprocal friends can arrange local meetings within
64 metres. One takes a validated walk while the other waits; only actual
arrival creates their in-person exchange. The appointment is remembered and
cannot repeat with the same person on the same day. Nearby rivals reduce the
appeal of city destinations. Conversations and rumor sharing can mention recent
work, purchases, appointments, shortages and deliveries.

Couriers display a parcel only while an active delivery has actual owned goods.
Completed station work gives a brief working pose and a factual caption.
Existing material shortages post funded delivery contracts; nearby witnesses
remember the request and successful arrivals. Registered businesses and guild
reception can display the received item type's actual owned stock count. Displays
are bounded to eight and hidden beyond 32 metres. These are views of authority
receipts and inventory, never substitutes for a successful delivery.

Each native receives real, equipped Civic starter clothing once: Lattice
Vestment, Lantern Crown, Margin Grips and Circuit Greaves. The original owner's
remaining issued Braided starter pieces exchange one-for-one for Civic pieces
in older saves. Purchased clothes, worn upgrades, sold pieces and other owners'
items are preserved; the exchange cannot repeat after reload. Dark Box issues a
shared uniform of Braided Circuit Vestment, Transit Crown, Accord Grips and
Recursion Greaves. Both issue receipts live in the version-two autonomy state;
loading, defeat or selling a piece does not resupply it. Officers, ordinary
pedestrians and seated native drivers show their actual owned clothing. The
lightweight civilian view batches eight articulated mounts into two skinned
surfaces, shares outfit meshes and uses the existing throttled pose updates.
Combat bodies continue using the full existing equipment renderer.

The player's existing wanted level appears as up to five gold triangle glyphs
with cyan centers in the top-right HUD. Only active glyphs are drawn; cleared
levels fade away over 0.35 seconds, and zero wanted status hides the display.
The HUD listens to the existing law ledger's changes and restore signal. It
does not change witness requirements, investigation, resolution or patrol logic,
and its animation processing stops when a fade completes.

Clothing Drip is a bounded 0-100 score derived from four equipped items' rarity,
value, complexity and quality. Status labels progress from Everyday to Well
dressed, Distinguished and Celebrated; this does not automatically confer a
guild office or change combat stats. Desired Drip rises with level and office.
Shopping can seek upgrades or a different look while retaining forty coins for
necessities. Home Drip uses the same item scoring for actually installed
furnishings, appears in building inspection and encourages further furnishing.

## Institutional starter capital and checkpoint preparation

The earlier role-based influx paid individual wallets only. A separate audited,
one-time institutional rollout now adds 20,000 coins to guild reception and
10,000 to the tavern, plus 5,000 + 50/member to each active guild and
15,000 + 100/distinct member to each faction (100,000 per-account cap). It applies
to old saves as well as new worlds. A version-six `institution_influx` journal
receipt folds into the audit base on compaction, so loading or running low cannot
repeat the grant. Neither rollout awards circulation XP or funds human wallets.
Normal purchases, wages, escrow, rentals and trade continue transferring existing
coins. Version-one through version-five ledgers migrate without losing balances.

Autosaves now transfer detached/frozen value captures directly to one private
worker. That worker performs the complete normal checkpoint validation, including
all inventory, economy, civic, building, career and officer links, and emits bytes
only after success. Its temporary inventory Nodes never enter the active tree;
shared catalog content is initialized on the main thread and read without edits.
This follows Godot's [off-tree threading rules](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html).
Loads/manual saves still join older jobs; the main thread owns the atomic disk
commit. No safety checks or cross-system validation have been disabled.

Changed registry and audit rows and native inventories are copied in small
bounded warming batches between saves. Frozen copies are replaced, never edited,
and inventory transaction signals invalidate their cached values. A first capture
fills any remaining tail rather than writing an incomplete checkpoint. Strict
serializers used by transactions and loading remain available. Inactive-world
physical scenes remain disabled; indoor play also reduces civilian decision
batches to four and civic polls to three seconds, while shell-render polling
sleeps. The authoritative society clock and financial deadlines continue.

On the isolated 15.5 MB copied save, warmed main-thread capture plus worker start
measured roughly 67-88 ms in the overworld and pyramid, compared with the previous
multi-second save-start stall. This is a preparation measurement, not an FPS
promise; first captures and disk commits still have work to do.

`civilian_needs.gd` tests separate depletion, red damage, equipment issuance,
institutional replay/migration and frozen captures. `civilian_errands.gd` covers
both distant route records and a real moving physics body entering the tavern,
sitting, eating and returning. It exercises work, purchasing, seated consumption,
safe egress and an actual friend appointment. The existing checkpoint, patrol, economy,
career and wand fixtures cover the shared boundaries. Native visual captures
are available through `capture_civilian_life.gd` and `capture_wand_effects.gd`.
