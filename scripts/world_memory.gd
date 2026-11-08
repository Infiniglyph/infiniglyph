extends Node3D
## Cached, spatial presentation of authoritative scene data. No generated world facts.
## TED-RAG budgets visual attention; collisions and resident simulation stay live.
const CELL_SIZE := 16.0
var district: Node3D
var population: Node3D
var player: CharacterBody3D
var retrieval: Node
var cells: Dictionary = {}
var residents: Dictionary = {}
var source_count := 0
var batch_count := 0
var visible_residents := 0
var full_detail_residents := 0
var policy_source := "local fallback"
var ready_for_queries := false
var light_limited_groups := 0
var _spot_bounds: Array[AABB] = []
var _omni_bounds: Array[AABB] = []
var _clock := 0.0
var _camera_position := Vector3.INF
var _camera_front := Vector3.ZERO

func _ready() -> void:
	name = "WorldMemory"
	for light: Node3D in get_parent().find_children("*","Light3D",true,false):
		if light is SpotLight3D: _spot_bounds.append(light.global_transform*light.get_aabb())
		elif light is OmniLight3D: _omni_bounds.append(light.global_transform*light.get_aabb())
	build_render_cache()
	for node: Node in district.find_children("*","Light3D",true,false):
		# Emissive fixtures stay visible; spend shadow-map work near the viewer.
		node.distance_fade_enabled = true
		node.distance_fade_begin = 38.0
		node.distance_fade_shadow = 24.0
		node.distance_fade_length = 12.0
	ready_for_queries = true

func fits_light_budget(mesh: Mesh) -> bool:
	var material := mesh.surface_get_material(0)
	if not material is StandardMaterial3D or material.shading_mode!=BaseMaterial3D.SHADING_MODE_PER_PIXEL: return true
	var bounds := global_transform*mesh.get_aabb()
	for lights: Array[AABB] in [_spot_bounds,_omni_bounds]:
		var count := 0
		for light: AABB in lights:
			if bounds.intersects(light): count += 1
		if count>8: return false
	return true

func build_render_cache() -> void:
	var groups: Dictionary = {}
	for source: MeshInstance3D in district.find_children("*","MeshInstance3D",true,false):
		if not source.is_visible_in_tree() or source.mesh==null: continue
		var at: Vector3 = source.to_global(source.get_aabb().get_center())
		var cell := Vector3i(floori(at.x/CELL_SIZE),floori(at.y/CELL_SIZE),floori(at.z/CELL_SIZE))
		if not cells.has(cell): cells[cell] = {"batches":[],"sources":[],"bounds":AABB(at,Vector3.ZERO)}
		cells[cell].sources.append(source)
		cells[cell].bounds = cells[cell].bounds.merge(source.global_transform*source.get_aabb())
		for surface in range(source.mesh.get_surface_count()):
			var reader := SurfaceTool.new()
			reader.create_from(source.mesh,surface)
			var primitive := reader.get_primitive_type()
			var material := source.get_active_material(surface)
			var key := "%s_%s_%s_%s" % [cell,primitive,material.get_instance_id() if material!=null else 0,source.cast_shadow]
			if not groups.has(key):
				var tool := SurfaceTool.new()
				tool.begin(primitive)
				tool.set_material(material)
				groups[key] = {"tool":tool,"cell":cell,"sources":[],"shadow":source.cast_shadow}
			groups[key].tool.append_from(source.mesh,surface,global_transform.affine_inverse()*source.global_transform)
			groups[key].sources.append(source)
		source_count += 1
	for group: Dictionary in groups.values():
		if group.sources.size()==1 and group.sources[0].mesh.get_surface_count()==1:
			# Already-batched city cells can be used directly without another mesh copy.
			cells[group.cell].batches.append(group.sources[0])
			batch_count += 1
			continue
		var mesh: ArrayMesh = group.tool.commit()
		if mesh==null: continue # Keep the original visible if compilation fails.
		if not fits_light_budget(mesh):
			# A larger bounding box can overflow Compatibility's per-object lights.
			# Retain the authored partition rather than dropping any illumination.
			for source: MeshInstance3D in group.sources: cells[group.cell].batches.append(source)
			batch_count += group.sources.size()
			light_limited_groups += 1
			continue
		var visual := MeshInstance3D.new()
		visual.name = "RememberedCell"
		visual.mesh = mesh
		visual.cast_shadow = group.shadow
		add_child(visual)
		cells[group.cell].batches.append(visual)
		for source: MeshInstance3D in group.sources: source.hide()
		batch_count += 1

func retrieve(at: Vector3, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell: Dictionary in cells.values():
		var bounds: AABB = cell.bounds
		var closest := at.clamp(bounds.position,bounds.end)
		if closest.distance_squared_to(at)<=radius*radius: result.append(cell)
	return result

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
