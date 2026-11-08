extends Node3D
## NPC pose-update budgets only. City meshes, lights and collision are untouched.
## TED-RAG budgets visual attention; resident simulation stays live.
var population: Node3D
var player: CharacterBody3D
var retrieval: Node
var residents: Dictionary = {}
var visible_residents := 0
var full_detail_residents := 0
var policy_source := "local fallback"
var ready_for_queries := false
var _clock := 0.0
var _camera_position := Vector3.INF
var _camera_front := Vector3.ZERO

func _ready() -> void:
	name = "ResidentAttention"
	ready_for_queries = true

func set_attention_enabled(enabled: bool) -> void:
	set_process(enabled)
	_clock = 0
	if enabled: return
	retrieval.world_context = {}
	for resident: CharacterBody3D in population.residents:
		resident.render_relevant = true
		resident.animation_interval = -1

func refresh_attention(camera: Camera3D) -> void:
	var policy: Dictionary = retrieval.world_policy()
	policy_source = "TED-RAG live" if retrieval.status=="TED-RAG live" and not retrieval.last_world_decision.is_empty() else "local fallback"
	visible_residents = 0
	full_detail_residents = 0
	var crowd := 0
	for resident: CharacterBody3D in population.residents:
		var id: StringName = resident.profile.id
		if not residents.has(id): residents[id] = {"profile":resident.profile,"actor":weakref(resident)}
		# References remain stable; these summaries never replace authoritative state.
		residents[id].position = resident.global_position
		residents[id].goal = resident.goal
		residents[id].cursor = resident.cursor
		residents[id].visits = resident.visits
		residents[id].state = resident.state
		if not resident.active: continue
		var distance := camera.global_position.distance_to(resident.global_position)
		var near_player := player.global_position.distance_to(resident.global_position)<8
		var visible := camera.is_position_in_frustum(resident.global_position+Vector3.UP)
		resident.render_relevant = visible or near_player
		if visible: visible_residents += 1
		if distance<float(policy.near_range) or near_player:
			resident.animation_interval = 0
			if resident.render_relevant: full_detail_residents += 1
		else:
			resident.animation_interval = 1.0/float(policy.mid_hz if distance<55 else policy.far_hz)
		if distance<35: crowd += 1
	retrieval.world_context = {"speed":clampf(Vector2(player.velocity.x,player.velocity.z).length()/20,0,1),"crowd":clampf(crowd/20.0,0,1),"combat":1.0 if population.duel.active else 0.0}

func _process(delta: float) -> void:
	if not ready_for_queries or not population.ready_for_visitors: return
	var camera := get_viewport().get_camera_3d()
	if camera==null: return
	_clock -= delta
	if _clock>0 and camera.global_position.distance_squared_to(_camera_position)<1 and camera.global_basis.z.dot(_camera_front)>0.99: return
	_clock = 0.2
	_camera_position = camera.global_position
	_camera_front = camera.global_basis.z
	refresh_attention(camera)
