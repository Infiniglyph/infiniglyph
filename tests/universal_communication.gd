extends SceneTree
const UIC = preload("res://scripts/universal_communication.gd")
const Protocol = preload("res://scripts/intent_protocol.gd")
const Message = preload("res://scripts/intent_message.gd")
const Profiles = preload("res://scripts/communication_profiles.gd")
const Translator = preload("res://scripts/intent_translator.gd")
const Voice = preload("res://scripts/communication_voice.gd")
const Intents = preload("res://scripts/universal_intent.gd")
class Clock extends Node:
	var world_seconds:=10.0
class ClockWorld extends Node:
	var civilization:=Clock.new()
var checks := 0
var failures := 0
var calls := 0
var ui: CanvasLayer
var ticks := 0
var opened_count := 0
var closed_count := 0

func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool: ticks+=1; return false
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)

func identity(id: String) -> Dictionary:
	return {"name":"Avat Ar" if id=="avat_ar" else "You" if id=="player" else "Nera","personality":"friendly","kind":"unique" if id=="avat_ar" else "player" if id=="player" else "civilian","special":"avat_ar" if id=="avat_ar" else ""}

func outcomes(message: Dictionary) -> Dictionary:
	calls+=1
	if message.intent=="request_trade":
		return {"accepted":true,"branch":"trade","reply":{"intent":"acknowledge"},"facts":[{"kind":"trade_discussion","offer_id":"offer/42"}]}
	return {"accepted":true}

func push(button: JoyButton,down: bool = true) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index=button; event.pressed=down
	root.push_input(event)

func key(code: Key,down: bool = true) -> void:
	var event:=InputEventKey.new()
	event.keycode=code; event.physical_keycode=code; event.pressed=down
	root.push_input(event)

func mouse(button: MouseButton,down: bool = true) -> void:
	var event:=InputEventMouseButton.new()
	event.button_index=button; event.pressed=down
	root.push_input(event)

func run() -> void:
	create_timer(60).timeout.connect(func(): push_error("UIC watchdog"); quit(2))
	root.content_scale_size=Vector2i(1280,720)
	root.size=Vector2i(1280,720)
	var protocol := Protocol.new()
	var message:=protocol.make_message("civilian1","player","offer_trade","iron_sword",{"offered_price":120},"hopeful","trade/1",80)
	check(not message.is_empty() and message.event_id==message.message_id and message.parameters.offered_price==120,"A shared canonical intent preserves participants, exact amount, subject, conversation and event ID")
	check(protocol.make_message("a","b","offer_trade","iron_sword",{}).is_empty(),"A concrete offer cannot omit its amount")
	check(protocol.make_message("a","b","offer_trade","iron_sword",{"price":30,"offered_price":120}).is_empty(),"Conflicting financial meanings cannot be translated or processed")
	check(protocol.make_message("a","b","invented_intent").is_empty() and protocol.make_message("a","a","greet").is_empty(),"Unknown intentions and self-addressed transactions are rejected")
	var object := Node.new()
	check(protocol.make_message("a","b","greet","",{"hidden":object}).is_empty(),"Only bounded values enter semantic messages")
	object.free()
	var results:=protocol.receive(message,func(_m: Dictionary): calls+=1; return {"accepted":true,"facts":[{"offer_id":"offer/42","price":120}]})
	check(results.accepted and calls==1 and protocol.facts.size()==1,"One authority callback commits structured facts without storing wording")
	check(protocol.receive(message,func(_m): calls+=1).get("duplicate",false) and calls==1,"Replaying a message cannot repeat its action")
	var event_replay:=message.duplicate(true)
	event_replay.message_id="different_message"
	check(protocol.receive(event_replay).get("duplicate",false),"A stable event ID also rejects a renamed message replay")
	results.message.parameters.offered_price=999
	check(protocol.recent[0].parameters.offered_price==120,"Caller mutation cannot change already recorded message meaning")
	var reentrant:=protocol.make_message("civilian1","player","greet")
	var nested:=protocol.make_message("civilian2","player","greet")
	protocol.receive(reentrant,func(_m): return {"accepted":protocol.receive(nested).reason=="busy"})
	check(protocol.recent.size()==2,"Authority callbacks cannot reenter communication processing")
	var saved:=protocol.serialize()
	var copy:=Protocol.new()
	check(copy.restore(JSON.parse_string(JSON.stringify(saved))) and copy.serialize()==saved,"Dedup keys and structured facts survive a real JSON checkpoint")
	var profiles:=Profiles.new()
	var profile:=profiles.profile("civilian1",identity("civilian1"))
	var repeated:=Profiles.new().profile("civilian1",identity("civilian1"))
	check(profile.voice==repeated.voice and profile.voice!=profiles.profile("civilian2").voice,"Each electronic voice is deterministic and recognizable across conversations")
	var merchant:=profiles.profile("avat_ar",identity("avat_ar"))
	check(merchant.special=="avat_ar" and merchant.tone=="cheerful" and merchant.voice.pitch!=profile.voice.pitch,"Avat Ar has a cheerful specialized voice without ordinary civilian progression")
	var translator:=Translator.new()
	translator.rng.seed=4812
	var variants: Dictionary={}
	var truthful:=true
	for i in range(40):
		var translated:=translator.translate(message,profile,{"price":1})
		variants[translated.text]=true
		truthful=truthful and "120" in translated.text and "iron sword" in translated.text and not "999" in translated.text
	check(variants.size()>1 and truthful,"Weighted translations vary while preserving exact offered prices and item identity")
	var rumor:=protocol.make_message("civilian1","player","share_rumor","",{"information":"Fabricated secret"})
	check(not translator.translate(rumor,profile).text.contains("Fabricated"),"Translation cannot turn unreferenced text into claimed knowledge")
	rumor=protocol.make_message("civilian1","player","share_rumor","",{"fact_id":"known/1","information":"The eastern road is open."})
	var known:=false
	for i in range(15): known=known or translator.translate(rumor,profile).text.contains("eastern road")
	check(known,"Referenced actual information can be voiced without inventing other facts")
	rumor=protocol.make_message("civilian1","player","share_rumor","",{"fact_id":"known/2","detail":"A caravan reached the northern gate."})
	var known_detail:=true
	for i in range(20):
		var text: String=translator.translate(rumor,profile).text
		known_detail=known_detail and "caravan reached" in text and not "no confirmed" in text
	check(known_detail,"Authority detail with a known fact always remains visible and avoids contradictory ignorance")
	rumor=protocol.make_message("civilian1","player","share_rumor","",{"detail":"Fabricated second secret"})
	check(not "Fabricated" in translator.translate(rumor,profile).text,"Unreferenced rumor detail cannot bypass the knowledge gate")
	var work:=protocol.make_message("civilian1","player","offer_work","",{"detail":"Deliver three crystals to the tavern.","reason":"Paid after delivery.","name":"Nera","role":"Courier","goal":"Restock tavern","faction":"guild/cyan","treasury":214,"reward":37,"quest_id":"quest/81","status":"offered"})
	var instructions: String=translator.translate(work,profile).text
	check("Deliver three crystals" in instructions and "Paid after delivery" in instructions and "Reward: 37" in instructions and "Treasury: 214" in instructions and "Name: Nera" in instructions and "Role: Courier" in instructions and "Goal: Restock tavern" in instructions and "Faction: guild/cyan" in instructions and "Quest: quest/81" in instructions and "Status: offered" in instructions,"Authored voices retain authoritative work, identity, membership and exact economic details")
	var greeting:=protocol.make_message("civilian1","player","greet","",{"goal":"Arbitrary unrelated AI goal"})
	check(not "Arbitrary" in translator.translate(greeting,profile).text,"An internal AI goal never replaces the personality's opening greeting")
	for i in range(20): profiles.remember_phrase("civilian1","favorite_"+str(i),message)
	check(profile.habits.size()==8 and profile.context.size()==8 and not Profiles.validate(profiles.serialize()).is_empty(),"Learned phrasing and recent context remain compact and persistent")
	var voice: AudioStreamWAV=Voice.syllable(profile,2)
	check(voice==Voice.syllable(profile,2) and voice.data.size()>1000 and voice.mix_rate==16000,"Procedural electronic syllables reuse a bounded short WAV cache")
	var options:=protocol.select_autonomous({"id":"civilian1","motivations":{"social":1.0}}, {"id":"civilian2"},{"nodes":[{"intent":"share_rumor","label":"Unsupported rumor"},{"intent":"greet","label":"Hello"}]})
	check(options.intent=="greet","Autonomous speakers use the same nodes while excluding unknown rumors")
	ui=UIC.new()
	ui.identity_provider=identity
	ui.outcome_handler=outcomes
	root.add_child(ui)
	ui.opened.connect(func(): opened_count+=1)
	ui.closed.connect(func(): closed_count+=1)
	calls=0
	var initial: Dictionary=ui.send("civilian1","civilian2","greet",{}, {},false)
	check(initial.accepted and calls==1 and not ui.is_open and not ui.ambient and not ui._screen.visible and not ui._voice.playing,"Offscreen communication processes meaning with zero UI or sound")
	var clean: Dictionary=ui.serialize()
	ui.identity_provider=func(id: String): return {} if id=="unknown" else {"kind":"boss","active":true} if id=="boss" else {"kind":"code_form","active":false} if id=="historical" else identity(id)
	check(not ui.send("unknown","player","greet").accepted and not ui.send("boss","player","greet").accepted and not ui.send("historical","player","greet").accepted and ui.protocol.recent==clean.protocol.recent and ui.profiles.serialize()==clean.profiles and not ui.begin("unknown","player"),"Foreign, boss and inactive speakers cannot poison persistent history or open a conversation")
	ui.identity_provider=identity
	var clock_world:=ClockWorld.new()
	root.add_child(clock_world)
	clock_world.add_child(clock_world.civilization)
	ui.world=clock_world
	var future: Dictionary=ui.protocol.make_message("civilian1","player","greet","",{},"neutral","",11)
	check(not ui.receive(future).accepted and ui.protocol.recent==clean.protocol.recent,"An incoming future timestamp cannot poison a live-world checkpoint")
	ui.world=null
	clock_world.free()
	ui.send("civilian1","civilian2","greet",{}, {},true)
	check(not ui.is_open and ui.ambient and opened_count==0,"Nearby autonomous speech uses an ambient subtitle without taking gameplay input")
	check(ui.begin("avat_ar","player",{"merchant":true}),"The player can begin through either participant ordering")
	check(ui.speaker_id=="player" and ui.listener_id=="avat_ar" and ui.nodes.size()==6 and opened_count==1,"Player and merchant share six contextual intents and one input context")
	ui._process(.03); ui._process(.07); ui._process(.08)
	check(ui._subtitle.visible_characters>0 and ui._voice.stream!=null,"Electronic syllables accompany progressive subtitle reveal")
	var before:=calls
	push(JOY_BUTTON_A)
	check(calls==before and ui._subtitle.visible_characters==ui._subtitle.text.length(),"The first A during translation only finishes that line")
	push(JOY_BUTTON_A)
	check(calls==before,"A held or repeated button cannot choose a second intention")
	push(JOY_BUTTON_A,false)
	push(JOY_BUTTON_X)
	push(JOY_BUTTON_X,false)
	check(calls>=before+1 and ui.branch=="trade" and ui.nodes[0].intent=="ask_price" and ui.protocol.facts.size()==1,"A fresh X selects its current intent and authority outcome changes the branch")
	ui.finish_line()
	ui.advance()
	ui.finish_line()
	var start:=ticks
	for i in range(5): await process_frame
	check(ticks>start and not paused,"Communication presentation leaves world processing live")
	var checkpoint: Dictionary=ui.serialize()
	ui.close_conversation()
	check(not ui.is_open and not ui._voice.playing and closed_count==1 and not UIC.validate(checkpoint).is_empty(),"Interruption stops audio and preserves valid semantic/profile state")
	check(ui.restore(JSON.parse_string(JSON.stringify(checkpoint))) and not ui.is_open and not ui.ambient,"Restore changes only persistent models and does not reopen UI or play sound")
	var previous: int=ui.protocol.serial
	ui.send("civilian1","civilian2","greet",{},{},false)
	check(ui.protocol.serial>previous,"Restored message serials cannot collide with earlier actions")
	check(ui.restore(null) and ui.profiles.records.is_empty() and ui.protocol.seen.is_empty(),"Legacy absent state clears optional communication safely")
	ui.begin("player","civilian1")
	ui.interrupt_guard=func(): return true
	ui._process(.02)
	check(not ui.is_open and not ui._voice.playing,"External damage, death, distance or menu guards can interrupt cleanly")
	ui.interrupt_guard=Callable()
	var direct: Array=[]
	var meanings:= ["greet","ask_work","refuse","thank","request_help","ask_identity"]
	for meaning: String in meanings: direct.append({"intent":meaning,"label":meaning})
	for index in range(6):
		ui.begin("player","civilian1",{},direct)
		ui.finish_line()
		push(UIC.BUTTONS[index]); push(UIC.BUTTONS[index],false)
		check(ui.protocol.recent[-1].intent==meanings[index],"Controller "+UIC.PROMPTS[index]+" selects its current contextual slot")
	for index in range(6):
		ui.begin("player","civilian1",{},direct)
		ui.finish_line()
		if index<4: key(UIC.KEYS[index]); key(UIC.KEYS[index],false)
		else: mouse(MOUSE_BUTTON_LEFT if index==4 else MOUSE_BUTTON_RIGHT); mouse(MOUSE_BUTTON_LEFT if index==4 else MOUSE_BUTTON_RIGHT,false)
		check(ui.protocol.recent[-1].intent==meanings[index],"Keyboard/mouse "+UIC.PROMPTS[index]+" shares the same semantic slot")
	ui.begin("player","civilian1",{},direct)
	ui.finish_line()
	before=calls
	key(KEY_ENTER); key(KEY_ENTER,false)
	check(calls==before,"Enter can advance text without silently accepting an intention")
	key(KEY_W)
	check(not ui.is_open and not ui._voice.playing,"A movement attempt interrupts the interface cleanly")
	key(KEY_W,false)
	if "--capture" in OS.get_cmdline_user_args():
		ui.interrupt_guard=Callable()
		ui.begin("avat_ar","player",{"merchant":true})
		ui.finish_line()
		for i in range(30): await process_frame; await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/universal_communication.png")
	ui.free()
	print("Universal communication verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
