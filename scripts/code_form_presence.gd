extends Node
## NPC presentation only. Never traverses, hides or disables the surrounding map.
const Manifest=preload("res://scripts/environment_manifest.gd")
const DRAW_DISTANCE:=96.0
const DRAW_MARGIN:=32.0
const PHYSICS_DISTANCE:=48.0
const PHYSICS_MARGIN:=16.0
const ASSEMBLY_SECONDS:=.55
var actor: Node3D
var viewer: CharacterBody3D
var figure: Node3D
var present:=false
var assembling:=false
var reconstructions:=0
var _clock:=0.0
var _effect:=Manifest.new()

static func lead(viewer_velocity: Vector3) -> float:
	return minf(32,viewer_velocity.length()*.6)

static func draw_range(viewer_velocity: Vector3) -> float:
	return DRAW_DISTANCE+lead(viewer_velocity)

static func physics_range(viewer_velocity: Vector3) -> float:
	return PHYSICS_DISTANCE+lead(viewer_velocity)

func _ready() -> void:
	name="CodeFormPresence"
	set_process(false)

func refresh(available: bool=true, protected: bool=false) -> void:
	var same_space:=is_instance_valid(viewer) and viewer.get_world_3d()==actor.get_world_3d()
	var distance:=actor.global_position.distance_to(viewer.global_position) if same_space else INF
	var radius:=draw_range(viewer.velocity) if same_space else DRAW_DISTANCE
	var wanted:=available and same_space and (protected or distance<radius+(DRAW_MARGIN if present else 0.0))
	if not wanted:
		conceal()
		return
	actor.show()
	if present: return
	present=true
	# Capture just this small body, using the instance reconstruction shader at
	# human-scale cell sizes. No scene scan, particles or permanent frame callback.
	_effect.capture(figure,actor.global_position,Vector3(.16,.16,.16),2.2)
	_effect.advance(0)
	assembling=true
	_clock=0
	reconstructions+=1
	set_process(true)
	# A teleport/respawn must never leave an invisible collider beside the player.
	if distance<12: finish_assembly()

func conceal() -> void:
	finish_assembly()
	present=false
	actor.hide()

func finish_assembly() -> void:
	_effect.restore()
	assembling=false
	set_process(false)

func _process(delta: float) -> void:
	# Instance travel temporarily borrows these same material overrides. Leave
	# its reconstruction in control until it restores the captured NPC materials.
	if is_instance_valid(viewer) and viewer.get("transition_locked")==true: return
	_clock+=delta
	_effect.advance(_clock/ASSEMBLY_SECONDS)
	if _clock>=ASSEMBLY_SECONDS: finish_assembly()

func _exit_tree() -> void:
	_effect.restore()
