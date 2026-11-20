# Economic XP and provenance

Economic XP applies to active civilian Code Forms. Humans, monsters, dungeon
creatures and bosses receive none. A witnessed illegal sale and a lawful sale
use the same amount-based calculation; legal evidence and wanted pressure live
in `civilian_law.gd` and never decide whether economic XP is valid.

## Authoritative economic activity

`CivilianEconomy` commits real inventory and coin transfers before emitting
`transaction_committed`. `commerce_committed` is the civilian-only subset with a
positive circulated amount. Both signals run while the economy transaction is
locked, and each observer receives a separate value copy.

Every receipt has a stable owner/ledger-sequence identity, clock timestamp,
financial sender/receiver accounts, participating civilian IDs, economic
substance, legal classification, related event, and actual source/delivered
asset IDs where applicable. Asset owner fields use raw civilian IDs, the real
human inventory owner, or `guild`; financial account fields retain their
`resident:`, `player:`, `business:` and `faction:` prefixes.

Generic transfers, blessings, founder donations, storage moves, theft itself,
and consumption do not award commerce XP. `Civilization.record_event` rejects
both economic event aliases; its economic adapter accepts only the economy's
currently committed financial sequence and exact amount/accounts. NPC theft
moves an existing owned item with stolen provenance before the subsequent
sale can earn anything. There is no generated substitute merchandise.

Contract publication transfers the promised reward from an existing account
into `contracts:escrow`. Settlement pays once for a completed obligation;
cancellation refunds once. A generic transfer cannot access escrow. Separate
faction treasuries begin at zero and require real founder transfers.
Reservations and goods survive reload. Terminal `quest_N` records can be
pruned, retaining the highest serial as a persistent replay watermark; custom
keys keep bounded terminal records rather than forgetting their deduplication.

## Progression configuration

`EconomicXPAudit.DEFAULT_CONFIG` is separate from the Registry's existing
progression and calendar configuration:

| Setting | Default |
| --- | --- |
| XP per square root of circulated coins | 8 |
| Maximum XP per participant per transaction | 128 |
| Retrospective review window | 7 game days |
| Maximum time for a repeated asset cycle | 1 game hour |
| Minimum suspicious sales | 4 |
| Artificial price threshold | 4 times the existing retail reference |

The award is `min(cap, round(sqrt(coins) * factor))`. The receipt stores the
actual XP delta accepted by the Registry, including zero when already capped.
Ordinary recurring work, meals and business are eligible without novelty-based
penalties. Changing these defaults is a progression/data migration decision;
existing provenance stores its validated configuration.

## Bounded retrospective review

The auditor retains at most 2,048 transaction rows and indexes at most the last
16 sales per asset. A scheduled review visits at most 16 transaction rows.
Currently it confirms a conservative pattern: the same unchanged asset moves
through the same two-to-four owners for at least two complete cycles, at an
identical artificial price, quantity and sale context, within the configured
time. A one-way thief/fence/customer resale chain, fair-price repurchases,
different merchandise, wages and meals do not satisfy that pattern. A later
genuine resale does not conceal an earlier detected cycle.

Confirmed artificial awards are marked `reversed` with a reason and timestamp.
Correction subtracts only their recorded actual XP, recalculates levels through
`Registry.reconcile_xp`, and removes only corresponding lifetime entitlement.
It never rewinds money or item transfers, changes birth time, or restores elapsed
age. Regaining a level grants that milestone's lifetime once again.

If corrected entitlement has already expired, normal retirement creates exactly
one successor now. The historical record keeps its original birth and corrected
entitlement expiry plus the actual retirement time. Historical wallets and goods
remain in their original accounts; the successor starts without copied wealth.
Registry, economy and audit changes roll back together if retirement/admission
fails. Physical body changes occur only after the financial batch commits.

## Persistence and validation

Economy schema 3 adds funded faction/contract state and migrates old schema 1/2
without new issuance. Civilization schema 2 adds economic provenance. Legacy
civilization XP is retained as an untraceable baseline; old transactions cannot
be replayed because the new audit starts at the restored financial highwater.

Audit validation is value-only and safe for the existing checkpoint worker.
It rejects malformed awards, foreign participants, invalid chronology and
replayed IDs. Whole-checkpoint validation also matches owner/highwater and every
provenance row still covered by the financial journal to its exact real
amount/accounts. Detail beyond the bounded window is intentionally unavailable
for new retrospective findings; the persistent highwater still prevents
re-awarding an old transaction after its detailed row has been pruned.

Targeted fixtures are `economic_provenance.gd`, `economic_corrections.gd`,
`economic_audit_scale.gd`, `civic_autonomy.gd` and `civilian_law.gd` under `tests/`.
