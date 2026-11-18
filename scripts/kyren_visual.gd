extends "res://scripts/resident_visual.gd"
## The ordinary resident's shared body primitives, doubled and resting cross-legged.
const Hat = preload("res://scripts/kyren_hat.gd")
const GOLD := Color(1,.68,.12)
var head_anchor := Node3D.new()
var scarf_anchor := Node3D.new()
var sword_anchor := Node3D.new()
var hat: Node3D
var embers: MultiMeshInstance3D

func _ready() -> void:
	tint = GOLD
	stature = 2.0
	super._ready()
	head_anchor.name = "HeadAnchor"
	scarf_anchor.name = "ScarfAnchor"
	add_child(head_anchor)
	add_child(scarf_anchor)
	sword_anchor.name = "SwordAnchor"
	add_child(sword_anchor)
	_build_hat()
	var wrap := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = .075
	torus.outer_radius = .16
	torus.rings = 20
	torus.ring_segments = 6
	wrap.mesh = torus
	wrap.material_override = Neon.shared_material(Color(.27,.008,.016))
	scarf_anchor.add_child(wrap)
	animate(0,0,false)

func _build_hat() -> void:
	hat = Hat.new()
	head_anchor.add_child(hat)
	embers = hat.embers

func animate(delta: float, _speed: float, _gesturing: bool) -> void:
	clock += delta
	var breath := sin(clock*1.3)*.004
	var pelvis := Vector3(0,.40,-.04)
	# The same equipped sword transfers here while the combat skeleton is hidden.
	sword_anchor.position = pelvis
	var chest := Vector3(0,.90+breath,-.08)
	var head := chest+Vector3(0,.26,-.025)
	segment(0,pelvis,chest,.037)
	segment(1,pelvis+Vector3(-.125,0,0),pelvis+Vector3(.125,0,0))
	segment(2,chest+Vector3(-.23,0,0),chest+Vector3(.23,0,0))
	dot_at(0,head,.128)
	dot_at(1,pelvis,.05)
	for i in range(2):
		var side := -1.0 if i==0 else 1.0
		var hip := pelvis+Vector3(side*.125,0,0)
		var knee := Vector3(side*.36,.14,.22)
		var foot := Vector3(-side*.10,.055,.34+(i*.055))
		segment(3+i*2,hip,knee)
		segment(4+i*2,knee,foot)
		dot_at(2+i*3,hip)
		dot_at(3+i*3,knee)
		dot_at(4+i*3,foot,.04)
		var shoulder := chest+Vector3(side*.23,0,0)
		var elbow := Vector3(side*.32,.60+breath,.06)
		var hand := Vector3(side*.35,.29,.22)
		segment(7+i*2,shoulder,elbow)
		segment(8+i*2,elbow,hand)
		dot_at(8+i*2,elbow)
		dot_at(9+i*2,hand,.04)
	head_anchor.position = head
	scarf_anchor.position = chest+Vector3(0,.105,0)
