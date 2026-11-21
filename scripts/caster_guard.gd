extends Node3D
## Cosmetic wards follow the existing block state. No hurtbox, shield points,
## attack pulses or independent parry window are introduced by their geometry.
const Lines=preload("res://scripts/robe_lines.gd")
const Library=preload("res://scripts/weapon_library.gd")
const Paint=preload("res://scripts/paintbrush_moves.gd")
var rig: Node3D
var actor: CharacterBody3D
var combat: Node
var _signature:=""
var _surfaces: Array[Node3D]=[]

func _ready() -> void:
	name="CasterGuard"
	actor=rig.visual.get_parent() as CharacterBody3D
	combat=actor.get("weapon_combat") if is_instance_valid(actor) else null
	process_priority=60
	hide()
	if not is_instance_valid(combat): set_process(false)

static func _ring(points: PackedVector3Array,radius: float,steps: int) -> void:
	for i in range(steps):
		for j in [i,i+1]: points.append(Vector3(cos(j*TAU/steps),sin(j*TAU/steps),0)*radius)

func _build(kind: StringName,tint: Color) -> void:
	for surface: Node3D in _surfaces: surface.free()
	_surfaces.clear()
	var points:=PackedVector3Array()
	var details:=PackedVector3Array()
	if kind==&"paintbrush":
		for radius: float in [.29,.21,.13]: _ring(points,radius,40)
	else:
		for radius: float in [.50,.44,.32]: _ring(points,radius,48)
		for i in range(8):
			var angle:=i*TAU/8
			var center:=Vector3(cos(angle),sin(angle),0)*.385
			var radial:=Vector3(cos(angle),sin(angle),0)*.035
			var tangent:=Vector3(-sin(angle),cos(angle),0)*.025
			details.append_array([center-radial,center+tangent,center+tangent,center+radial,center+radial,center-tangent,center-tangent,center-radial])
		for i in range(3):
			var a:=i*TAU/3; var b:=(i+1)*TAU/3
			details.append_array([Vector3(cos(a),sin(a),0)*.29,Vector3(cos(b),sin(b),0)*.29])
	for row: Array in [[points,tint],[details,tint.lerp(Color.WHITE,.6)]]:
		if row[0].is_empty(): continue
		var surface:=Lines.segments(row[0],row[1],3.2)
		add_child(surface); _surfaces.append(surface)

func _process(_delta: float) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(combat): hide(); return
	var kind: StringName=Library.loadout(rig.selected).id
	var guarding: bool=kind in [&"wand",&"paintbrush"] and not rig.sheathed and actor.combat.blocking and combat.can_act() and not actor.dodge.active and actor.get("transition_locked")!=true and actor.health>0 and rig.is_visible_in_tree()
	visible=guarding
	if not guarding: return
	var tint: Color=Library.loadout(rig.selected).color
	var signature:=String(kind)+tint.to_html()
	if signature!=_signature: _signature=signature; _build(kind,tint)
	var facing: Vector3=combat.aim_direction()
	if kind==&"paintbrush":
		global_transform=Paint.guard_frame(actor,facing)
		# The brush remains physically held. Center the concentric strokes on
		# its solved nib, including any bounded arm-reach correction.
		global_position=rig.left_hand.to_global(Paint.TIP)-global_basis*Paint.guard_pen(combat.guard_visual_time)
	else:
		var basis:=Basis(Vector3.UP,atan2(facing.x,facing.z))
		global_transform=Transform3D(basis,actor.combat_point()+basis*Vector3(0,.30,.72))
		scale*=1.08 if combat.parry_remaining>0 else 1.0
