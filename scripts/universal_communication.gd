extends CanvasLayer
## Shared intent transport plus one local presentation channel. World adapters
## supply contextual choices and authoritative outcomes; this UI never trades,
## grants quests, changes membership or manufactures knowledge on its own.
const Intents = preload("res://scripts/universal_intent.gd")
const Message = preload("res://scripts/intent_message.gd")
const Profiles = preload("res://scripts/communication_profiles.gd")
const Protocol = preload("res://scripts/intent_protocol.gd")
const Translator = preload("res://scripts/intent_translator.gd")
const Voice = preload("res://scripts/communication_voice.gd")
const BUTTONS := [JOY_BUTTON_X,JOY_BUTTON_Y,JOY_BUTTON_B,JOY_BUTTON_A,JOY_BUTTON_LEFT_SHOULDER,JOY_BUTTON_RIGHT_SHOULDER]
const KEYS := [KEY_Q,KEY_R,KEY_E,KEY_SPACE]
const PROMPTS := ["X / Q","Y / R","B / E","A / SPACE","LB / LEFT MOUSE","RB / RIGHT MOUSE"]
signal opened
signal closed
signal message_processed(message: Dictionary,outcome: Dictionary)
var world: Node
var identity_provider: Callable
var context_provider: Callable
var outcome_handler: Callable
var interrupt_guard: Callable
var profiles := Profiles.new()
var protocol := Protocol.new()
var translator := Translator.new()
var is_open := false
var ambient := false
@export_range(.25,3,.05) var text_speed := 1.0
@export var voice_enabled := true
var nodes: Array[Dictionary] = []
var speaker_id := ""
var listener_id := ""
var conversation_id := ""
var latest_text: String:
	get: return _subtitle.text if is_instance_valid(_subtitle) else ""
var branch := "greeting"
var _context: Dictionary = {}
var _screen: Control
var _panel: PanelContainer
var _speaker: Label
var _subtitle: RichTextLabel
var _grid: GridContainer
var _labels: Array[Label] = []
var _hint: Label
var _voice: AudioStreamPlayer
var _queue: Array[Dictionary] = []
var _line: Dictionary = {}
var _line_profile: Dictionary = {}
var _elapsed := 0.0
var _characters_per_second := 35.0
var _last_syllable := -1
var _complete_wait := 0.0
var _close_after := false
var _pressed: Dictionary = {}

func _ready() -> void:
	name="UniversalCommunication"
	layer=26
	_build()
	_screen.hide()
	set_process(false)

func _identity(id: String) -> Dictionary:
	var value: Variant=identity_provider.call(id) if identity_provider.is_valid() else {}
	return value if value is Dictionary else {}

func _known_participant(id: String) -> bool:
	if not identity_provider.is_valid(): return true
	var identity:=_identity(id)
	return not identity.is_empty() and identity.get("active",true)==true and identity.get("kind","") in ["player","civilian","code_form","unique","institution"]

func _now() -> float:
	var society=world.get("civilization") if is_instance_valid(world) else null
	return float(society.world_seconds) if is_instance_valid(society) else float(_context.get("world_timestamp",0))

func transaction_active() -> bool: return protocol.busy

func begin(speaker: String,listener: String,context: Dictionary = {},initial_nodes: Array = []) -> bool:
	if not Message.text(speaker) or not Message.text(listener) or speaker==listener or protocol.busy: return false
	if not _known_participant(speaker) or not _known_participant(listener): return false
	if not is_node_ready(): return false
	if is_open: close_conversation("replaced")
	_stop_presentation()
	var listener_is_player: bool=listener=="player" or listener.begins_with("player:") or _identity(listener).get("kind")=="player"
	speaker_id=listener if listener_is_player else speaker
	listener_id=speaker if listener_is_player else listener
	_context=context.duplicate(true)
	branch=String(context.get("branch","greeting"))
	conversation_id=protocol.channel_id+"/conversation/"+str(protocol.serial+1)
	is_open=true; ambient=false; _close_after=false
	_pressed.clear()
	_refresh_nodes(initial_nodes)
	_layout(false)
	_screen.show()
	set_process(true)
	opened.emit()
	# Both sides enter through the same protocol and authored translation path.
	send(listener_id,speaker_id,"greet",{},_context,true,conversation_id)
	return is_open

func _refresh_nodes(override_nodes: Array = []) -> void:
	var choices: Variant=override_nodes
	if override_nodes.is_empty():
		choices=context_provider.call(speaker_id,listener_id,branch,_context.duplicate(true)) if context_provider.is_valid() else Intents.nodes(_context.merged({"branch":branch},true))
	nodes=Intents.clean_nodes(choices if choices is Array else [])
	for index in range(6):
		_labels[index].text=PROMPTS[index]+"   "+nodes[index].label if index<nodes.size() else ""
		_labels[index].modulate=Color.WHITE if index<nodes.size() and nodes[index].enabled else Color(.35,.45,.48)
		_labels[index].get_parent().visible=index<nodes.size()
	_hint.text="Select an intention  |  ENTER: finish translation  |  ESC: leave  |  Move to interrupt"

func send(speaker: String,listener: String,intent: String,parameters: Dictionary = {},context: Dictionary = {},present: bool = false,conversation: String = "",event_id: String = "") -> Dictionary:
	var subject:=String(context.get("subject_id",parameters.get("subject_id",parameters.get("item_id",""))))
	var message:=protocol.make_message(speaker,listener,intent,subject,parameters,String(context.get("emotion","neutral")),conversation,_now(),event_id)
	return receive(message,present,context)

func receive(message: Dictionary,present: bool = false,context: Dictionary = {}) -> Dictionary:
	var validated:=Message.validate(message)
	if validated.is_empty(): return {"accepted":false,"reason":"invalid"}
	# Invalid live participants must not enter persistent recent messages or
	# profiles: checkpoint crosschecks correctly reject foreign/boss identities.
	if not _known_participant(validated.speaker_id) or not _known_participant(validated.listener_id): return {"accepted":false,"reason":"identity"}
	var society=world.get("civilization") if is_instance_valid(world) else null
	if is_instance_valid(society) and validated.world_timestamp>_now(): return {"accepted":false,"reason":"future"}
	var outcome:=protocol.receive(message,outcome_handler)
	if not outcome.has("message"): return outcome
	var canonical: Dictionary=outcome.message
	profiles.profile(canonical.speaker_id,_identity(canonical.speaker_id))
	profiles.remember_phrase(canonical.speaker_id,"",canonical)
	message_processed.emit(canonical.duplicate(true),outcome.duplicate(true))
	if present and is_node_ready():
		if is_open and canonical.conversation_id==conversation_id:
			_queue_line(canonical,context)
		elif not is_open and not ambient:
			ambient=true
			_layout(true)
			_screen.show()
			set_process(true)
			_queue_line(canonical,context)
	return outcome

func choose_autonomous(speaker: Dictionary,listener: Dictionary,context: Dictionary = {},turn: int = 0) -> Dictionary:
	return protocol.select_autonomous(speaker,listener,context,turn)

func select(index: int) -> void:
	if not is_open: return
	if not _line.is_empty() and _subtitle.visible_characters<_subtitle.text.length():
		_finish_line()
		return
	if not _queue.is_empty(): _start_next(); return
	if _close_after: close_conversation("finished"); return
	if index<0 or index>=nodes.size() or not nodes[index].enabled: return
	var selected: Dictionary=nodes[index].duplicate(true)
	var context:=_context.duplicate(true)
	context.subject_id=selected.subject_id if not selected.subject_id.is_empty() else String(context.get("subject_id",""))
	context.emotion=selected.emotion
	var outcome:=send(speaker_id,listener_id,selected.intent,selected.parameters,context,true,conversation_id)
	if not is_open: return # Authority can hand off to a service menu immediately.
	if outcome.get("context") is Dictionary: _context.merge(outcome.context,true)
	if outcome.has("branch"): branch=String(outcome.branch)
	elif not selected.branch.is_empty(): branch=selected.branch
	if outcome.get("reply") is Dictionary:
		var reply: Dictionary=outcome.reply
		var reply_context:=_context.duplicate(true)
		reply_context.emotion=String(reply.get("emotion","neutral"))
		reply_context.subject_id=String(reply.get("subject_id",context.subject_id))
		send(String(reply.get("speaker_id",listener_id)),String(reply.get("listener_id",speaker_id)),String(reply.get("intent","acknowledge")),reply.get("parameters",{}),reply_context,true,conversation_id)
	_close_after=bool(outcome.get("close",false)) or selected.intent=="farewell"
	_refresh_nodes(outcome.get("nodes",[]) if outcome.get("nodes") is Array else [])
	if not outcome.get("accepted",false): _hint.text=String(outcome.get("reason","That intention could not be acted on.")).left(180)

func _queue_line(message: Dictionary,context: Dictionary) -> void:
	if _queue.size()>=8: return
	_queue.append({"message":message.duplicate(true),"context":context.duplicate(true)})
	if _line.is_empty(): _start_next()

func _start_next() -> void:
	_voice.stop()
	if _queue.is_empty(): return
	var next: Dictionary=_queue.pop_front()
	_line=next.message
	_line_profile=profiles.profile(_line.speaker_id,_identity(_line.speaker_id))
	var context: Dictionary=next.context
	var identity:=_identity(_line.speaker_id)
	context.speaker_name=String(identity.get("name",_line.speaker_id))
	context.listener_name=String(_identity(_line.listener_id).get("name",_line.listener_id))
	var translated:=translator.translate(_line,_line_profile,context)
	profiles.remember_phrase(_line.speaker_id,translated.phrase_id,_line)
	_speaker.text=context.speaker_name
	_subtitle.text=translated.text
	_subtitle.visible_characters=0
	_characters_per_second=float(_line_profile.voice.speed)*float(_line_profile.voice.rhythm)*text_speed
	if _line.emotion in ["excited","happy"]: _characters_per_second*=1.2
	elif _line.emotion in ["sad","thoughtful"]: _characters_per_second*=.8
	_elapsed=0; _last_syllable=-1; _complete_wait=0

func _finish_line() -> void:
	_subtitle.visible_characters=_subtitle.text.length()
	_voice.stop()
	_complete_wait=.05

func finish_line() -> void: _finish_line()

func advance() -> void:
	if _line.is_empty(): return
	if _subtitle.visible_characters<_subtitle.text.length(): _finish_line()
	elif not _queue.is_empty(): _start_next()
	elif _close_after: close_conversation("finished")

func _process(delta: float) -> void:
	if is_open and interrupt_guard.is_valid() and interrupt_guard.call(): close_conversation("interrupted"); return
	if _line.is_empty(): return
	_elapsed+=delta
	# Plain text length is immediately authoritative, even before RichTextLabel's
	# first deferred layout updates its cached character count.
	var total:=_subtitle.text.length()
	var shown:=mini(total,int(_elapsed*_characters_per_second))
	if _complete_wait<=0 and shown>_subtitle.visible_characters:
		_subtitle.visible_characters=shown
		var syllable:=shown/3
		if syllable!=_last_syllable and shown>0 and not _subtitle.text.substr(shown-1,1).strip_edges().is_empty():
			_last_syllable=syllable
			if voice_enabled:
				_voice.stream=Voice.syllable(_line_profile,syllable)
				var rise:=1.0+.22*shown/maxf(1,total) if Intents.DEFINITIONS[_line.intent].get("question",false) else 1.0
				var inflection:=1.0+sin(syllable*1.71)*float(_line_profile.voice.jitter)*.2
				_voice.pitch_scale=rise*inflection*(1.12 if _line.emotion=="excited" else .85 if _line.emotion=="angry" else 1.0)
				_voice.volume_db=-29 if _line.emotion=="sad" else -21 if _line.emotion=="angry" else -24
				_voice.play()
	if _subtitle.visible_characters>=total:
		_complete_wait+=delta
		if not _queue.is_empty() and _complete_wait>.45: _start_next()
		elif _close_after and _complete_wait>.9: close_conversation("finished")
		elif ambient and _complete_wait>1.8: _stop_presentation()

func _stop_presentation() -> void:
	if is_instance_valid(_voice): _voice.stop()
	_queue.clear(); _line={}; _line_profile={}
	ambient=false
	if is_instance_valid(_screen): _screen.hide()
	set_process(false)

func close_conversation(_reason: String = "closed") -> void:
	var was_open:=is_open
	is_open=false
	_stop_presentation()
	nodes.clear(); _pressed.clear()
	if was_open: closed.emit()

func _input(event: InputEvent) -> void:
	if not is_open: return
	var index := -1
	var token := ""
	var pressed := false
	if event is InputEventKey:
		var code: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if code in [KEY_W,KEY_A,KEY_S,KEY_D] and event.pressed:
			get_viewport().set_input_as_handled(); close_conversation("movement"); return
		if code==KEY_ESCAPE and event.pressed:
			get_viewport().set_input_as_handled(); close_conversation("escape"); return
		if code==KEY_ENTER and event.pressed:
			get_viewport().set_input_as_handled()
			if not event.echo: advance()
			return
		if event.echo: get_viewport().set_input_as_handled(); return
		index=KEYS.find(code); token="key/"+str(code); pressed=event.pressed
	elif event is InputEventJoypadButton:
		index=BUTTONS.find(event.button_index); token="pad/"+str(event.device)+"/"+str(event.button_index); pressed=event.pressed
	elif event is InputEventMouseButton:
		index=4 if event.button_index==MOUSE_BUTTON_LEFT else 5 if event.button_index==MOUSE_BUTTON_RIGHT else -1
		token="mouse/"+str(event.button_index); pressed=event.pressed
	elif event is InputEventJoypadMotion and event.axis in [JOY_AXIS_LEFT_X,JOY_AXIS_LEFT_Y] and absf(event.axis_value)>.55:
		get_viewport().set_input_as_handled(); close_conversation("movement"); return
	if index<0: return
	get_viewport().set_input_as_handled()
	if not pressed: _pressed.erase(token); return
	if _pressed.has(token): return
	_pressed[token]=true
	select(index)

func _build() -> void:
	_screen=Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_screen)
	_panel=PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(.004,.016,.026,.97)
	style.border_color=Color(.12,.8,.9)
	style.set_border_width_all(1); style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel",style)
	_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_screen.add_child(_panel)
	var box:=VBoxContainer.new()
	box.mouse_filter=Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation",8)
	_panel.add_child(box)
	_speaker=Label.new()
	_speaker.add_theme_font_size_override("font_size",20)
	_speaker.add_theme_color_override("font_color",Color(.3,.95,1))
	box.add_child(_speaker)
	_subtitle=RichTextLabel.new()
	_subtitle.bbcode_enabled=false
	_subtitle.custom_minimum_size.y=74
	_subtitle.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_subtitle.add_theme_font_size_override("normal_font_size",18)
	_subtitle.add_theme_color_override("default_color",Color(.88,.97,1))
	_subtitle.scroll_following=true
	_subtitle.mouse_filter=Control.MOUSE_FILTER_IGNORE
	box.add_child(_subtitle)
	_grid=GridContainer.new()
	_grid.columns=3
	_grid.add_theme_constant_override("h_separation",12)
	_grid.add_theme_constant_override("v_separation",8)
	_grid.mouse_filter=Control.MOUSE_FILTER_IGNORE
	box.add_child(_grid)
	for i in range(6):
		var panel:=PanelContainer.new()
		var border:=style.duplicate()
		border.bg_color=Color(.012,.05,.075)
		border.border_color=Color(.08,.4,.5)
		border.set_content_margin_all(7)
		panel.add_theme_stylebox_override("panel",border)
		panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_grid.add_child(panel)
		var label:=Label.new()
		label.custom_minimum_size=Vector2(260,38)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size",14)
		label.mouse_filter=Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)
		_labels.append(label)
	_hint=Label.new()
	_hint.add_theme_font_size_override("font_size",12)
	_hint.add_theme_color_override("font_color",Color(.4,.75,.8))
	box.add_child(_hint)
	_voice=AudioStreamPlayer.new()
	_voice.volume_db=-24
	add_child(_voice)

func _layout(is_ambient: bool) -> void:
	_panel.anchor_left=.07; _panel.anchor_right=.93
	_panel.anchor_top=.76 if is_ambient else .53
	_panel.anchor_bottom=.97
	_grid.visible=not is_ambient
	_hint.visible=not is_ambient
	_panel.offset_left=0; _panel.offset_right=0; _panel.offset_top=0; _panel.offset_bottom=0

func serialize() -> Dictionary:
	return {"version":1,"profiles":profiles.serialize(),"protocol":protocol.serialize()}

static func validate(input: Variant) -> Dictionary:
	if not input is Dictionary or input.size()!=3 or input.get("version")!=1: return {}
	var p:=Profiles.validate(input.get("profiles"))
	var state:=Protocol.validate(input.get("protocol"))
	if p.is_empty() or state.is_empty(): return {}
	return {"version":1,"profiles":p,"protocol":state}

func restore(input: Variant) -> bool:
	if protocol.busy: return false
	if input==null:
		close_conversation("restore")
		profiles=Profiles.new(); protocol=Protocol.new()
		return true
	var decoded:=validate(input)
	if decoded.is_empty(): return false
	close_conversation("restore")
	return profiles.restore(decoded.profiles) and protocol.restore(decoded.protocol)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_open: close_conversation("focus")

func _exit_tree() -> void:
	if is_instance_valid(_voice): _voice.stop()
