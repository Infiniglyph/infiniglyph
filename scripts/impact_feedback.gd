extends Node3D
## One event-driven controller per arena: 12 reused bursts and 4 bounded voices.
## No global time scale, physics pause, particle physics or runtime asset IO.
const SparkBurst = preload("res://scripts/spark_burst.gd")
const POOL_SIZE := 12
const VOICES := 4
var bursts: Array[Dictionary] = []
var voices: Array[AudioStreamPlayer3D] = []
var sounds: Dictionary = {}
var cursor := 0
var voice_cursor := 0
var last_event: Dictionary = {}
var serial := 0

static func obtain(actor: Node) -> Node3D:
	var arena := actor.get_parent()
	var controller := arena.get_node_or_null("CombatImpactFeedback")
	if controller == null:
		controller = load("res://scripts/impact_feedback.gd").new()
		controller.name = "CombatImpactFeedback"
		arena.add_child(controller)
	return controller

func _ready() -> void:
	for i in range(POOL_SIZE):
		var sparks := SparkBurst.new()
		add_child(sparks)
		bursts.append({"mesh":sparks,"age":1.0,"duration":0.6,"primary_color":Color.WHITE,"secondary_color":Color.WHITE})
	for kind in ["hit","block","heavy","parry","exhaustion"]:
		sounds[kind] = synthesize(kind)
	for i in range(VOICES):
		var voice := AudioStreamPlayer3D.new()
		voice.unit_size = 5
		voice.max_distance = 24
		# Four coincident two-layer sounds remain below full scale even at origin.
		voice.volume_db = -10
		voice.max_db = -10
		add_child(voice)
		voices.append(voice)

static func synthesize(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var duration := 0.24 if kind in ["parry","heavy","exhaustion"] else 0.13
	var count := int(duration*rate)
	var data := PackedByteArray()
	data.resize(count*2)
	var metal := 2450.0 if kind == "parry" else (720.0 if kind == "block" else 1550.0)
	if kind == "exhaustion": metal = 380.0
	var bass := 48.0 if kind == "exhaustion" else (65.0 if kind == "heavy" else 100.0)
	for i in range(count):
		var t := float(i)/rate
		var attack := minf(1,t/0.002)
		var high := (sin(TAU*metal*t)+sin(TAU*metal*1.47*t)*0.35)*exp(-t*(22 if kind == "parry" else 45))
		var low := sin(TAU*bass*t-20*t*t)*exp(-t*23)
		var sample := (high*0.28+low*0.35)*attack*(1-smoothstep(duration*0.7,duration,t))
		data.encode_s16(i*2,int(clampf(sample,-0.8,0.8)*32767))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = rate
	sound.data = data
	return sound

func confirm(kind: String, point: Vector3, direction: Vector3, attacker: Node, defender: Node, damaged: bool = false, hurtbox_shape: int = -1, hitstop: bool = true) -> void:
	var heavy := kind in ["parry","heavy","exhaustion"]
	var color := Color(1,0.82,0.18) if kind == "parry" else (Color(1,0.28,0.015) if kind in ["block","exhaustion"] else Color(1,0.025,0.065))
	var secondary := Color(1,0.38,0.015)
	var forward := direction.normalized() if direction.length_squared()>0.00001 else Vector3.FORWARD
	var body_point := point
	if damaged and is_instance_valid(defender) and defender.has_method("body_impact_point"):
		body_point = defender.body_impact_point(point)
	var origin := body_point if damaged and kind in ["hit","heavy"] else point
	emit_burst(origin,forward,color,1.15 if heavy else 0.85,28 if heavy else (12 if kind == "block" else 18),secondary)
	if damaged and kind in ["block","exhaustion"]:
		emit_burst(body_point,forward,Color(1,0.025,0.065),0.7,10,secondary)
	last_event = {"kind":kind,"point":origin,"contact":point,"body_point":body_point,"hurtbox_shape":hurtbox_shape,"defender_id":defender.get_instance_id() if is_instance_valid(defender) else 0,"direction":forward,"damaged":damaged}
	var audible := false
	for participant in [attacker,defender]:
		if not is_instance_valid(participant) or participant.get("weapon_combat") == null: continue
		var combat: Node = participant.weapon_combat
		var rules: Resource = combat.rules
		var duration: float = rules.light_hitstop
		if kind == "parry": duration = rules.parry_hitstop
		elif kind == "exhaustion": duration = rules.exhaustion_hitstop
		elif heavy: duration = rules.heavy_hitstop
		if hitstop: combat.freeze_visuals(duration)
		audible = audible or rules.impact_audio_enabled
		var camera: Node = participant.camera_rig
		if camera.has_method("impact_impulse") and rules.camera_shake_enabled:
			camera.impact_impulse(forward,(0.065 if heavy else 0.018)*rules.camera_intensity)
	if audible:
		var voice := voices[voice_cursor]
		voice_cursor = (voice_cursor+1)%VOICES
		voice.stop()
		voice.global_position = origin
		voice.stream = sounds[kind]
		voice.play()

func emit_burst(point: Vector3, forward: Vector3, primary: Color, strength: float, count: int, secondary: Color = Color(1,0.38,0.015)) -> void:
	var burst := bursts[cursor]
	cursor = (cursor+1)%POOL_SIZE
	serial += 1
	burst.age = 0.0
	burst.primary_color = primary
	burst.secondary_color = secondary
	burst.mesh.global_transform = Transform3D(Basis.IDENTITY,point)
	burst.mesh.ignite(forward,primary,secondary,strength,count,serial*7919)
	burst.duration = burst.mesh.duration

func _process(delta: float) -> void:
	for burst in bursts:
		if burst.age>=burst.duration: continue
		burst.age += delta
		burst.mesh.redraw(burst.age)
