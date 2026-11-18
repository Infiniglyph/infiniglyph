extends Node3D
## Editor-placeable static world loot. No automatic collection or polling loop.
const Catalog = preload("res://scripts/item_catalog.gd")
const Neon = preload("res://scripts/neon.gd")
@export var item_type_id: StringName = &"katana"
@export_range(1,9999,1) var quantity := 1
@export_range(0,99,1) var upgrade_level := 0
@export var custom_properties: Dictionary = {}
var item_instance: Resource
var pickup_id := ""
var death_owner_id := ""
var location_id: StringName = &"overworld"
var claimed := false
var pending := false
var _glyph: Node3D
var _glyph_clock := 0.0
var solid: StaticBody3D

static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

func _ready() -> void:
	if pickup_id.is_empty(): pickup_id = new_id()
	if item_instance == null:
		item_instance = Catalog.create(item_type_id,quantity)
		if item_instance != null:
			item_instance.upgrade_level = upgrade_level
			for key in custom_properties: item_instance.custom_properties[key] = custom_properties[key]
	Neon.prepare()
	name = "ItemPickup_"+pickup_id.left(8)
	add_to_group("item_pickups")
	# A small, solid plinth and faceted crystal share a single static body.
	solid = StaticBody3D.new()
	solid.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	solid.name = "LootSolid"
	solid.collision_layer = 0 if pending else 1
	solid.collision_mask = 0
	add_child(solid)
	var base_shape := BoxShape3D.new()
	base_shape.size = Vector3(0.42,0.10,0.42)
	var base_collision := CollisionShape3D.new()
	base_collision.shape = base_shape
	base_collision.position.y = 0.05
	solid.add_child(base_collision)
	var definition: Resource = Catalog.get_definition(item_instance.item_type_id) if item_instance!=null else null
	if definition!=null and definition.custom_properties.get("monster_glyph",false):
		_build_remnant(definition.custom_properties)
		visible=not pending
		return
	var points := PackedVector3Array([Vector3(0,0.77,0),Vector3(0,0.19,0),Vector3(0.19,0.46,0),Vector3(0,0.46,0.19),Vector3(-0.19,0.46,0),Vector3(0,0.46,-0.19)])
	var crystal_shape := ConvexPolygonShape3D.new()
	crystal_shape.points = points
	var crystal_collision := CollisionShape3D.new()
	crystal_collision.shape = crystal_shape
	solid.add_child(crystal_collision)
	var faces := [[0,2,3],[0,3,4],[0,4,5],[0,5,2],[1,3,2],[1,4,3],[1,5,4],[1,2,5]]
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,Neon.dark)
	for face: Array in faces:
		for index: int in face: mesh.surface_add_vertex(points[index])
	mesh.surface_end()
	var surface := MeshInstance3D.new()
	surface.mesh = mesh
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	var lines := PackedVector3Array()
	var seen: Dictionary = {}
	for face: Array in faces:
		for i in range(3):
			var a: int = face[i]
			var b: int = face[(i+1)%3]
			var edge := Vector2i(mini(a,b),maxi(a,b))
			if not seen.has(edge):
				seen[edge] = true
				lines.append_array([points[a],points[b]])
	for s in [-1,1]:
		lines.append_array([Vector3(-0.21,0.103,s*0.21),Vector3(0.21,0.103,s*0.21),Vector3(s*0.21,0.103,-0.21),Vector3(s*0.21,0.103,0.21)])
	add_child(Neon.lines(lines,Neon.material(Color(0.25,1,0.6) if item_type_id==&"health_glyph" or item_instance!=null and item_instance.item_type_id==&"health_glyph" else Color(0.04,0.95,1.0))))
	visible = not pending

func activate() -> void:
	pending = false
	visible = true
	if is_instance_valid(solid): solid.collision_layer = 1

func interaction_name() -> String:
	if item_instance == null: return "Unconfigured item"
	var definition = Catalog.get_definition(item_instance.item_type_id)
	return str(definition.display_name) if definition != null else "Unknown item"

func _build_remnant(properties: Dictionary) -> void:
	_glyph=Node3D.new()
	_glyph.name="RemnantGlyph"
	add_child(_glyph)
	var size := float(properties.glyph_scale)
	_glyph.scale=Vector3.ONE*size
	_glyph.position.y=.3+size*.6
	var paths:=PackedVector3Array()
	for i in range(32):
		var a:=i*TAU/32
		var b:=(i+1)*TAU/32
		paths.append_array([Vector3(cos(a)*.43,sin(a)*.43,0),Vector3(cos(b)*.43,sin(b)*.43,0)])
		if i%4==0: paths.append_array([Vector3(cos(a)*.46,sin(a)*.46,0),Vector3(cos(a)*.56,sin(a)*.56,0)])
	for side in [-1,1]:
		paths.append_array([Vector3(0,.38,0),Vector3(side*.26,0,0),Vector3(side*.26,0,0),Vector3(0,-.38,0),Vector3(-.17,.04,0),Vector3(.17,.04,0)])
	paths.append_array([Vector3(0,-.28,0),Vector3(0,.28,0)])
	_glyph.add_child(Neon.lines(paths,Neon.shared_material(Color(properties.glyph_color))))

func _process(delta: float) -> void:
	if not is_instance_valid(_glyph): return
	_glyph_clock+=delta
	_glyph.rotation.y+=delta*.65
	_glyph.position.y=.3+_glyph.scale.y*.6+sin(_glyph_clock*2)*.055
