extends RefCounted
## One semantic vocabulary for human input and autonomous inhabitants.
const DEFINITIONS := {
	"greet":{"label":"Say hello","question":false},"farewell":{"label":"Say goodbye"},
	"request_trade":{"label":"Discuss trading"},"browse_goods":{"label":"Browse goods"},
	"ask_price":{"label":"Ask the price","question":true},"quote_price":{"label":"State the price","priced":true},
	"offer_trade":{"label":"Make an offer","priced":true},"propose_price":{"label":"Propose a price","priced":true},
	"accept_trade":{"label":"Accept the offer"},"decline_trade":{"label":"Decline the offer"},
	"ask_discount":{"label":"Ask for a discount","question":true},"ask_quality":{"label":"Ask about quality","question":true},
	"offer_item":{"label":"Offer an item"},"ask_rumor":{"label":"Ask about news","question":true},
	"share_rumor":{"label":"Share known information"},"request_info":{"label":"Ask a question","question":true},
	"share_info":{"label":"Share information"},"ask_work":{"label":"Ask about work","question":true},
	"offer_work":{"label":"Offer work"},"accept_work":{"label":"Accept the work"},
	"request_help":{"label":"Ask for help","question":true},"offer_help":{"label":"Offer assistance"},
	"ask_quest":{"label":"Ask about opportunities","question":true},"accept_quest":{"label":"Accept the task"},
	"report_quest":{"label":"Report progress"},"ask_guild":{"label":"Discuss the guild","question":true},
	"invite_guild":{"label":"Invite to a guild"},"accept_guild":{"label":"Accept the invitation"},
	"decline":{"label":"Decline"},"refuse":{"label":"Refuse"},"agree":{"label":"Agree"},
	"thank":{"label":"Give thanks"},"apologize":{"label":"Apologize"},"affection":{"label":"Express affection"},
	"threaten":{"label":"Make a threat"},"hostility":{"label":"Express hostility"},
	"ask_identity":{"label":"Ask about them","question":true},"introduce":{"label":"Introduce yourself"},
	"ask_location":{"label":"Ask for directions","question":true},"make_promise":{"label":"Make a promise"},
	"return":{"label":"Return to previous options"},"confirm":{"label":"Confirm"},
	"inform":{"label":"Explain"},"acknowledge":{"label":"Acknowledge"}}
const EMOTIONS := ["neutral","friendly","happy","excited","hopeful","curious","thoughtful","serious","angry","sad","confident","afraid"]

static func exists(intent: String) -> bool: return DEFINITIONS.has(intent)
static func label(intent: String) -> String: return String(DEFINITIONS.get(intent,{}).get("label",intent.replace("_"," ").capitalize()))

static func nodes(context: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var branch := String(context.get("branch","greeting"))
	var intents: Array = ["greet","ask_work","farewell","ask_identity","ask_rumor","offer_help"]
	if branch=="trade": intents=["ask_price","ask_discount","decline_trade","browse_goods","ask_quality","return"]
	elif branch=="guild": intents=["ask_guild","invite_guild","decline","accept_guild","ask_work","return"]
	elif context.get("merchant",false): intents=["request_trade","ask_price","farewell","browse_goods","ask_rumor","offer_item"]
	for intent: String in intents: result.append({"intent":intent,"label":label(intent),"parameters":{},"enabled":true})
	return result

static func clean_nodes(input: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in input:
		if result.size()>=6: break
		if not value is Dictionary or not exists(String(value.get("intent",""))): continue
		var parameters: Variant=value.get("parameters",{})
		if not parameters is Dictionary: continue
		result.append({"intent":String(value.intent),"label":String(value.get("label",label(value.intent))).left(100),"subject_id":String(value.get("subject_id","")),"parameters":parameters.duplicate(true),"emotion":String(value.get("emotion","neutral")),"branch":String(value.get("branch","")),"enabled":bool(value.get("enabled",true))})
	return result
