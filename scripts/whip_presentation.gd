extends Node3D
## A tapered continuous lash. Twenty-four reusable links carry a traveling bend
## from wrist to tip; the same visible centerline supplies combat contacts.
const Neon = preload("res://scripts/neon.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
const LINKS := 24
var rig: Node3D
var points := PackedVector3Array()
var rope: MultiMesh
var geometry: Dictionary
var _clock := 0.0
var _capsule := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()

func configure(owner_rig: Node3D, definition: Dictionary) -> void:
	rig = owner_rig
	geometry = definition

func _ready() -> void:
	name = "FlexibleWhip"
	add_child(Geometry.model({"family":"sword","length":.12,"width":.045,"depth":.045,"tint":geometry.tint,"outline":[[-.027,-.22],[.027,-.22],[.035,.14],[-.035,.14]]}))
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1
	mesh.bottom_radius = 1
	mesh.height = 1
	mesh.radial_segments = 5
	rope = MultiMesh.new()
	rope.transform_format = MultiMesh.TRANSFORM_3D
	rope.mesh = mesh
	rope.instance_count = LINKS
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = rope
	instance.material_override = Neon.shared_material(Color(geometry.tint))
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	points.resize(LINKS+1)
	_capsule.radius = .11
	_query.shape = _capsule
	_query.collision_mask = 6

func update_lash(delta: float, move: Dictionary, elapsed: float, facing: Vector3) -> void:
	if not is_inside_tree(): return
	_clock += delta
	var actor: CharacterBody3D = rig.visual.get_parent()
	var start: Vector3 = rig.right_hand.to_global(Vector3(0,.14,0))
	var right := Vector3(facing.z,0,-facing.x)
	var reach := float(move.get("reach",3.0))
	var attacking: bool = not move.is_empty() and move.get("weapon_family")=="whip"
	var contact := float(move.get("hits",[.3])[0])
	# Wind back, roll the loop forward, crack, then let the cord fall slack.
	var snap := exp(-pow((elapsed-contact)/.105,2)) if attacking else 0.0
	for hit: float in move.get("hits",[]):
		if absf(elapsed-hit)<absf(elapsed-contact): contact=hit
	var phase := (elapsed-contact)*11.0
	var side := float(move.get("side",1))
	for i in range(LINKS+1):
		var t := i/float(LINKS)
		var rest := start+right*(.12*sin(t*TAU+_clock*1.4))*t+facing*(.10+.19*sin(t*PI))*t
		rest.y = maxf(actor.global_position.y+.12,start.y-t*1.45)
		var angle := side*(phase*(.40+.60*t)+sin(t*PI)*.28+sin(phase*2-t*TAU)*.22*(1-snap)*t)
		var direction := facing.rotated(Vector3.UP,angle)
		var lash := start+direction*reach*t+Vector3.UP*(sin(t*PI)*(.32+.35*sin(phase-t*3)))
		if int(move.get("combo_index",0))==2: lash += Vector3.UP*sin(phase)*t*.8
		var weight := clampf(snap+(.40 if attacking else 0.0),0,1)
		# Local coordinates preserve attachment during Sky Jump and phase dodges.
		points[i] = to_local(rest.lerp(lash,weight))
	for i in range(LINKS):
		var vector := points[i+1]-points[i]
		var radius := lerpf(.020,.006,i/float(LINKS))
		var basis := Basis(Quaternion(Vector3.UP,vector.normalized()))*Basis.from_scale(Vector3(radius,maxf(.001,vector.length()),radius))
		rope.set_instance_transform(i,Transform3D(basis,(points[i+1]+points[i])*.5))

func hit_candidates() -> Array:
	var actor: CharacterBody3D = rig.visual.get_parent()
	_query.exclude = [actor.get_rid()]
	var found: Dictionary = {}
	for i in range(LINKS):
		var a := to_global(points[i])
		var b := to_global(points[i+1])
		_capsule.height = maxf(.22,a.distance_to(b)+.22)
		_query.transform = Transform3D(Basis(Quaternion(Vector3.UP,(b-a).normalized())),(a+b)*.5)
		for hit: Dictionary in actor.get_world_3d().direct_space_state.intersect_shape(_query,16):
			hit.contact = (a+b)*.5
			found[hit.collider] = hit
	return found.values()
