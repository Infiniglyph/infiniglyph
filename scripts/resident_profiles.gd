extends RefCounted
## Local character sketches, not new factions, world history or hidden-boss lore.
const PEOPLE := [
	["Ilex","courier","curious","plaza_w","north_e","south_e"],
	["Mica","lamp tender","pragmatic","plaza_e","north_w","east_court"],
	["Venn","resident","dismissive","north_w","plaza_w","west_avenue"],
	["Tess","gardener","friendly","north_e","east_garden","plaza_e"],
	["Rill","courier","dismissive","west_avenue","plaza_w","west_court"],
	["Oriel","resident","indifferent","east_avenue","plaza_e","east_court"],
	["Kest","lamp tender","dismissive","boulevard_w","west_garden","north_w"],
	["Sable","resident","curious","boulevard_e","north_e","east_garden"],
	["Pell","gardener","pragmatic","south_w","west_court","plaza_w"],
	["Neri","resident","friendly","south_e","plaza_e","east_avenue"],
	["Cairn","courier","dismissive","west_court","west_avenue","south_w"],
	["Lilt","resident","curious","east_court","east_avenue","south_e"],
	["Aven","gardener","dismissive","west_garden","boulevard_w","west_court"],
	["Veil","lamp tender","pragmatic","east_garden","boulevard_e","east_court"],
	["Quill","resident","dismissive","west_crossing","plaza_w","north_w"],
	["Senn","courier","dismissive","east_crossing","plaza_e","north_e"],
	["Beryl","resident","indifferent","south_crossing_w","south_w","west_avenue"],
	["Fenn","resident","dismissive","south_crossing_e","south_e","east_avenue"],
]
const GREETINGS := {
	"curious":"A human. Does this place feel different to you? I only know it from inside.",
	"friendly":"You're visiting? There's room to walk with us. Mind the crossings.",
	"pragmatic":"Human or otherwise, please leave the walkway clear. I've work to finish.",
	"dismissive":"Another human wandering through. Some of us actually live here.",
	"indifferent":"Yes, I know you're human. Was there something you needed?"
}
const AGAIN := {
	"curious":"You came back. I'm still curious what you notice that I don't.",
	"friendly":"Good to see you again. Getting your bearings?",
	"pragmatic":"You again. All right, a moment. Then I need to get back to work.",
	"dismissive":"I remember you, human. Persistence isn't the same as belonging.",
	"indifferent":"We spoke earlier. I'm still going about my day."
}
const VOICES := {
	&"ilex":"A human. Does this place feel different to you? I only know it from inside.",
	&"mica":"Human or otherwise, please leave the walkway clear. I've work to finish.",
	&"venn":"Try not to make the plaza your training ground, human. We have somewhere to be.",
	&"tess":"Mind the planters. They aren't obstacles; someone looks after them. You're welcome to walk with me.",
	&"rill":"Humans always stand in the middle. I have a route to finish.",
	&"oriel":"I'm meeting someone. Your being human isn't the most interesting thing in my day.",
	&"kest":"You admire the lights. I keep them working. Leave room, human.",
	&"sable":"You know this is a simulation too. What does that knowledge change for you?",
	&"pell":"The gardens need attention whether humans visit or not. Step around the beds, please.",
	&"neri":"If you're lost, follow the south avenue to the arrival court. I go there often.",
	&"cairn":"Another visitor expecting us to stop our day for them. Keep moving.",
	&"lilt":"Cairn says humans are a nuisance. I'd rather make up my own mind.",
	&"aven":"Not every patch of this place is here for you to jump across, human.",
	&"veil":"I check the lamps between the garden and the avenue. I can talk for a moment.",
	&"quill":"You're passing through. Remember that before claiming the street.",
	&"senn":"Quill is too polite to say it: this city doesn't need human supervision.",
	&"beryl":"I'm waiting for Fenn. You can wait too, if you keep the way clear.",
	&"fenn":"Beryl has patience for visitors. I have a walk to finish."
}
const PALETTE := {
	"violet":Color(0.52,0.2,1),"cyan":Color(0.05,0.9,1),"blue":Color(0.12,0.32,1),
	"purple":Color(0.76,0.12,0.94),"gold":Color(1,0.72,0.1),"orange":Color(1,0.28,0.035),
	"red":Color(1,0.07,0.16),"green":Color(0.1,1,0.3),"mint":Color(0.36,1,0.74),
	"pink":Color(1,0.25,0.72),"white":Color(0.94,1,1)
}

static func all(count: int = 100) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var people: Array = PEOPLE.duplicate(true)
	var given := ["Aster","Nacre","Echo","Coda","Nova","Prism","Rune","Lumen","Cinder","Vela","Opal","Lyra","Reed","Sol","Vale","Kite","Arden","Wren","Lace","Haze","Brin","Tern","Gale","Lux","Onyx","Lark","Ash","Iris"]
	var family := ["Arc","Trace","Fold","Thread"]
	var stops := ["north_w","north_e","west_avenue","east_avenue","west_court","east_court","west_garden","east_garden","south_w","south_e","boulevard_w","boulevard_e"]
	var attitudes := ["dismissive","curious","pragmatic","friendly","dismissive","indifferent","dismissive"]
	while people.size()<count:
		var n := people.size()-PEOPLE.size()
		people.append([given[n%given.size()]+" "+family[n/given.size()], ["resident","courier","lamp tender","gardener"][n%4],attitudes[n%attitudes.size()],stops[n%stops.size()],stops[(n+3)%stops.size()],stops[(n+7)%stops.size()]])
	people.resize(count)
	# Balanced pairs keep existing identities stable when the roster grows.
	# Use a separate seed so appearance never consumes gameplay/population RNG.
	var body_rng := RandomNumberGenerator.new()
	body_rng.seed = 731942
	var female_first := false
	for i in range(people.size()):
		var row: Array = people[i]
		if i%2==0: female_first = body_rng.randi_range(0,1)==1
		var female := female_first if i%2==0 else not female_first
		# Reciprocal pairs meet; the next pair links every pair into one social graph.
		var partner := i+1 if i%2==0 else i-1
		result.append({"id":StringName(row[0].to_lower()),"name":row[0],"role":row[1],"attitude":row[2],"body_profile":&"female" if female else &"male",
			"home":StringName(row[3]),"routine":[StringName(row[4]),StringName(row[5]),StringName(row[3])],
			"contacts":[StringName(people[partner%people.size()][0].to_lower()),StringName(people[(i+2)%people.size()][0].to_lower())],
			"meeting":StringName(people[(i/2)*2][3])})
	return result
