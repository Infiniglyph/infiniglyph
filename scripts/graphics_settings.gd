extends Node
## Graphics quality only. Geometry, collisions and world time are independent.
var world: Node3D
var actor: CharacterBody3D
var shadow_budget := 4
var glow_quality := 2 # Off / Soft (one sample) / Full (two samples).
var resolution_percent := 100
var _clock := 0.0
var _glow: CanvasLayer
var _fixtures: Array[Node] = []

func _ready() -> void:
	name = "GraphicsSettings"
	_glow = world.get_node_or_null("NeonGlow")
	_fixtures = get_tree().get_nodes_in_group("street_lights")
	apply_quality()

func apply_quality() -> void:
	shadow_budget = clampi(shadow_budget,0,16)
	glow_quality = clampi(glow_quality,0,2)
	resolution_percent = clampi(resolution_percent,50,100)
	get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	get_viewport().scaling_3d_scale = resolution_percent/100.0
	if is_instance_valid(_glow):
		_glow.visible = glow_quality>0
		var material: ShaderMaterial = _glow.get_child(0).material
		material.set_shader_parameter("cheap_glow",glow_quality==1)
	refresh_shadows()

func refresh_shadows() -> void:
	# Stable ordering plus a small preference for current casters avoids
	# swapping lights repeatedly while standing at an equal-distance boundary.
	var nearby: Array[Node] = _fixtures.duplicate()
	nearby.sort_custom(func(a: Node,b: Node):
		var ad: float = a.light.global_position.distance_squared_to(actor.global_position)*(0.9 if a.light.shadow_enabled else 1.0)
		var bd: float = b.light.global_position.distance_squared_to(actor.global_position)*(0.9 if b.light.shadow_enabled else 1.0)
		return ad<bd)
	for i in range(nearby.size()):
		var light: SpotLight3D = nearby[i].light
		light.shadow_enabled = i<shadow_budget and (shadow_budget==16 or light.global_position.distance_squared_to(actor.global_position)<4096)

func _process(delta: float) -> void:
	_clock -= delta
	if _clock>0: return
	_clock = 0.2
	refresh_shadows()

func _exit_tree() -> void:
	get_viewport().scaling_3d_scale = 1.0
