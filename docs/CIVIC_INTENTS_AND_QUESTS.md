# Civic intents, factions and shared work

The civilian civilization now uses a shared semantic communication protocol and
one quest authority. This extends the existing residents, business inventories,
coin ledger and persistent civilian identities. It does not pause the world or
grant civilian progression to the player, bosses or dungeon monsters.

## Playing

Use **G / tap RT** near a resident, guild board, keeper or Avat Ar's counter.
Contextual choices use **X, Y, B, A, LB, RB**. Keyboard equivalents in the same
order are **Q, R, E, Space, left mouse, right mouse**. The first selection while
a translation is appearing finishes that line; release and press again to
choose. **Enter** finishes/advances translation. **Escape** or movement ends a
conversation. Start and inventory replace it, stopping the electronic voice.
No attacks or jumps are performed by conversation selections.

Settings includes translation/voice speed and an electronic-voice toggle. Voices
are generated syllables, not recorded English or text-to-speech. Nearby civilian
conversations can use the same subtitle/voice channel without taking player
controls. Offscreen communication has no UI or audio.

Ordinary residents can offer items they actually own, and the player can offer
owned goods back to them. Inspect a price, accept, decline, or use an available
relationship-based counteroffer. Quotes bind the actual parties, item, quantity,
price and expiry; changed stock, missing coins and expired quotes fail without a
partial exchange. Offers are temporary and are cleared on closing or loading.

The Adventurers Guild contains separate **Security**, **Commerce** and
**Exploration Guild** boards. Anyone can browse public contracts; joining the
relevant guild is required before accepting one. Each faction has its own
treasury, initially funded by transfers from residents' existing coins. Rewards
are reserved in escrow before a job can be advertised. There are no fabricated
coins when a board, instance or checkpoint is reopened.

Security patrols and exploration surveys complete at the stated world waypoint.
Delivery contracts transfer the requested owned item to its recipient. Purchase
meal supplies at the tavern, bring them to the named recipient, and report the
work. The progress branch gives the objective, coordinates where applicable,
and the actual completion state. A stationary patrol/survey poll counts as one
visit per destination and game day, rather than repeated paid work every frame.

**Underworld** work has no public board. Help the resting tavern contact with an
actual requested delivery to earn trust, then ask for a private introduction.
This unlocks private affiliation and funded contracts. Residents can also request
personal favors for missing supplies. Their goods, funding and relationships are
real model state; repeating a question does not invent another unmet need.

## Authorities and continuity

`universal_intent.gd`, `intent_message.gd` and `intent_protocol.gd` define the
shared vocabulary, bounded messages and persistent replay guard. English is a
translation of an intent and its verified parameters. It never authorizes an
item transfer, changes a price or manufactures knowledge. Phrase templates are
in `data/communication_phrases.json`; voices and speaking habits are lazy,
bounded profiles. Avat Ar has a distinctive profile without revealing hidden
lore.

`universal_quests.gd` separates templates from instances. It supports delivery,
discovery, service and recovery objectives through verified host events.
Definitions live in `data/factions.json` and `data/quest_templates.json`. Events
can progress multiple independent obligations, but cannot be replayed for a
second payment. Cancellation, expiry and civilian retirement return reserved
funds to their original account, including preserved historical wallets.

`civilization_interactions.gd` connects conversations and bounded NPC decisions
to the existing authorities. Real inventory receipts verify deliveries; actual
positions verify arrivals. NPCs choose supported work, affiliations, favors,
social interactions and risky trade according to their goals, resources,
relationships and motivations. Existing connected pedestrian routes remain the
movement authority; contracts do not teleport civilians across buildings.

`civilian_law.gd` keeps witnessed evidence, investigators and wanted levels
separate from economic XP. Actual assaults, vehicle theft witnesses, stolen
goods and observed illicit sales can create cases. Security investigations use
recorded witnesses and funded service contracts. Criminality is not itself an
XP exploit. See [Economic XP](ECONOMIC_XP.md) for the independent provenance and
correction rules.

`intent_trade.gd` is the shared semantic trade adapter. It issues bounded,
ephemeral offers and asks `civilian_economy.gd` to perform atomic owned-item and
coin transfers. The same intent path serves civilian-to-civilian resale,
including genuinely acquired stolen goods; their provenance stays attached.

Whole checkpoints atomically include `quest_state`, `communication_state` and
`law_state`, alongside inventory, finite currency, civilian history and economic
provenance. Main-thread and worker encoding validate their shared IDs, clocks,
escrow amounts, payees and statuses. Old checkpoints with no civic obligations
migrate once; incomplete current saves cannot silently discard reserved debts.
Loading current state does not publish new jobs or duplicate capital.

## Validation

Focused fixtures cover the semantic protocol, all six choices, electronic voice
and settings, quest membership and event verification, finite escrow and replay,
archive bounds, law evidence, civilian lifetime corrections and legacy saves.
`tests/civic_integration.gd` exercises the production world from joining a guild
through paid patrol, a purchased/delivered favor, private introduction and atomic
save/load. Existing shop, inventory, establishment and checkpoint regressions
remain part of the verification set. Capture fixtures use isolated user data.

This is the functional shared foundation. It does not add nonexistent crafting,
construction or escort systems, a universal city pathfinder, police arrest AI,
an external language model, or unlimited economic-history retention. New
objectives and world actions should supply verified events through these same
authorities.
