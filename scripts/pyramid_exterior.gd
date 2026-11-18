extends Node3D
## Full-scale exterior at LAT 047N / LON 005W. The dungeon instance is separate.
const Chunk = preload("res://scripts/world_chunk.gd")
const CENTER := Vector3(-80,0,-752)
const BASE_WIDTH := 128.0
const HEIGHT := 82.0
const HALF_BASE := BASE_WIDTH*.5
const FLOOR_HEIGHT := .08
const COURSE_HEIGHT := 1.35
const GOLD := Color(.70,.49,.19)
const SEAM := Color(.29,.22,.11)
const ENTRANCE := Vector3(69.5,FLOOR_HEIGHT,0)
const ARRIVAL := Vector3(73,.15,0)
var structure: Node3D
var entrance_anchor: Marker3D
var arrival_anchor: Marker3D
var masonry_segments := 0

static func pad_blend(x: float, z: float) -> float:
	# End the blend at the road centre and before the ravine bridge approach.
	return 1-smoothstep(66,80,maxf(absf(x-CENTER.x),absf(z-CENTER.z)))

static func reserves_plot(at: Vector3) -> bool:
	# Include neighbouring prop overhangs, not just plot centres inside the base.
	return absf(at.x-CENTER.x)<96 and absf(at.z-CENTER.z)<96

func _ready() -> void:
	name="PyramidExterior"
	structure=Chunk.new()
	structure.name="PyramidStructure"
	add_child(structure)
	structure.box(Vector3(0,-.08,0),Vector3(132,.32,132),"PyramidFoundation",GOLD*.75)
	var corners:=PackedVector3Array([Vector3(-HALF_BASE,FLOOR_HEIGHT,-HALF_BASE),Vector3(HALF_BASE,FLOOR_HEIGHT,-HALF_BASE),Vector3(HALF_BASE,FLOOR_HEIGHT,HALF_BASE),Vector3(-HALF_BASE,FLOOR_HEIGHT,HALF_BASE),Vector3(0,HEIGHT+FLOOR_HEIGHT,0)])
	structure.convex(corners,[[0,1,2,3],[1,0,4],[2,1,4],[3,2,4],[0,3,4]],Vector3.ZERO,"PyramidMass",GOLD)
	_masonry()
	_entrance()
	structure.commit()
	var stone: StandardMaterial3D=Chunk.dark.duplicate()
	stone.albedo_color=Color(.055,.044,.027)
	stone.emission=Color(.008,.006,.003)
	structure.mesh_instance.set_surface_override_material(0,stone)
	entrance_anchor=Marker3D.new()
	entrance_anchor.name="DungeonEntrance"
	entrance_anchor.position=ENTRANCE
	entrance_anchor.rotation.y=PI*.5
	add_child(entrance_anchor)
	arrival_anchor=Marker3D.new()
	arrival_anchor.name="ExteriorArrival"
	arrival_anchor.position=ARRIVAL
	arrival_anchor.rotation.y=-PI*.5
	add_child(arrival_anchor)

func _face_point(face: int, u: float, height: float) -> Vector3:
	var radius:=HALF_BASE*(1-height/HEIGHT)
	var across:=lerpf(-radius,radius,u)
	var y:=height+FLOOR_HEIGHT+.012
	match face:
		0: return Vector3(across,y,-radius-.012)
		1: return Vector3(radius+.012,y,across)
		2: return Vector3(-across,y,radius+.012)
		_: return Vector3(-radius-.012,y,-across)

func _masonry() -> void:
	for course in range(ceili(HEIGHT/COURSE_HEIGHT)):
		var lower:=course*COURSE_HEIGHT
		var upper:=minf(HEIGHT,lower+COURSE_HEIGHT)
		var width:=BASE_WIDTH*(1-lower/HEIGHT)
		var joints:=maxi(1,ceili(width/5.5))
		for face in range(4):
			structure.line(_face_point(face,0,lower),_face_point(face,1,lower),GOLD*.60)
			for joint in range(joints):
				var u: float=(float(joint)+(.5 if course%2 else 0.0))/joints
				if u<=0 or u>=1: continue
				structure.line(_face_point(face,u,lower),_face_point(face,u,upper),SEAM)
				masonry_segments+=1

func _entrance() -> void:
	# A real recessed, sealed vestibule facing the existing north/south road.
	# Entrance/arrival markers allow a later instance transition without putting
	# rooms or enemies inside this overworld shell.
	structure.box(Vector3(62,.0,0),Vector3(14,.16,9.6),"PyramidPorch",GOLD)
	for side in [-1,1]:
		structure.box(Vector3(62,3.58,side*4.2),Vector3(12,7,1.2),"EntranceSideWall",GOLD*.8)
		structure.box(Vector3(68.3,3.58,side*3.9),Vector3(1.2,7,1.1),"EntrancePillar",GOLD)
	var gable:=PackedVector3Array([Vector3(56,7.08,-5),Vector3(56,7.08,5),Vector3(56,10.08,0),Vector3(69,7.08,-5),Vector3(69,7.08,5),Vector3(69,10.08,0)])
	structure.convex(gable,[[0,2,1],[3,4,5],[0,1,4,3],[0,3,5,2],[1,2,5,4]],Vector3.ZERO,"EntranceGable",GOLD)
	structure.box(Vector3(64.2,3.58,0),Vector3(.28,7,7.2),"SealedDungeonDoor",GOLD)
	for z: float in [-3.1,0,3.1]: structure.line(Vector3(64.35,.45,z),Vector3(64.35,6.65,z),GOLD)
	for y: float in [.45,6.65]: structure.line(Vector3(64.35,y,-3.1),Vector3(64.35,y,3.1),GOLD)
	for side in [-1,1]:
		structure.line(Vector3(64.36,3.5,side*1.35),Vector3(64.36,5.1,0),GOLD)
		structure.line(Vector3(64.36,3.5,side*1.35),Vector3(64.36,1.9,0),GOLD)
	# The shallow physical approach joins the road without a vertical step.
	var ramp:=PackedVector3Array([Vector3(69,-.12,-4.8),Vector3(69,-.12,4.8),Vector3(69,.08,-4.8),Vector3(69,.08,4.8),Vector3(78,-.12,-4.8),Vector3(78,-.12,4.8),Vector3(78,0,-4.8),Vector3(78,0,4.8)])
	structure.convex(ramp,[[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]],Vector3.ZERO,"EntranceApproach",GOLD*.7)
