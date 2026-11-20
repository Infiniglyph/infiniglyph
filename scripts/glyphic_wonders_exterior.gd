extends Node3D
## A deliberately small city shop. Commerce and phase travel own its interactions.
const Chunk = preload("res://scripts/world_chunk.gd")
const Furnish = preload("res://scripts/civilian_establishments.gd")
const CENTER := Vector3(-112,0,-608)
const SIZE := Vector3(12,6,10)
const GROUND := .12
const CYAN := Color(.035,.9,1)
const MAGENTA := Color(1,.055,.66)
var entrance_anchor: Marker3D
var arrival_anchor: Marker3D
var frontage_ground := GROUND
var structure: Node3D

func _init() -> void: position=CENTER

static func reserves_plot(at: Vector3) -> bool:
	# Reserve the surrounding scenery lot before its original tower is built.
	return absf(at.x-CENTER.x)<32 and absf(at.z-CENTER.z)<32

func _ready() -> void:
	name="GlyphicWondersStorefront"
	structure=Chunk.new()
	structure.name="StorefrontBatch"
	add_child(structure)
	var b := structure
	# Recess the ground-level shell behind the existing x=-118 sidewalk.
	# The twelve-meter roof keeps the small shop silhouette without obstructing
	# the region's longstanding civilian route along the west side of this lot.
	b.box(Vector3.ZERO,Vector3(10.8,.24,10),"ShopFoundation",CYAN)
	b.box(Vector3(0,0,8),Vector3(10.8,.24,6),"ShopFrontage",MAGENTA)
	b.box(Vector3(0,6.12,0),Vector3(12.4,.24,10.4),"ShopRoof",MAGENTA)
	b.box(Vector3(0,3.12,-5),Vector3(10.8,6,.22),"ShopRearWall",CYAN)
	for side in [-1,1]:
		b.box(Vector3(side*5.4,3.12,0),Vector3(.22,6,10),"ShopSideWall",CYAN)
		b.box(Vector3(side*3.5,3.12,5),Vector3(3.8,6,.22),"ShopFrontWall",CYAN)
		b.box(Vector3(side*1.7,1.92,5.16),Vector3(.16,3.6,.16),"ShopDoorTrim",MAGENTA,Basis.IDENTITY,false)
		b.box(Vector3(side*4,2.72,5.15),Vector3(2.1,1.8,.055),"ShopWindow",MAGENTA,Basis.IDENTITY,false)
		for level in range(3): b.line(Vector3(side*5,2.1+level*.55,5.2),Vector3(side*3,2.1+level*.55,5.2),CYAN*.6)
	b.box(Vector3(0,4.92,5),Vector3(3.2,2.4,.22),"ShopDoorLintel",CYAN)
	b.line(Vector3(-1.7,3.72,5.18),Vector3(1.7,3.72,5.18),MAGENTA)
	# A dark recess and two parallel light strips make the open door unmistakable.
	for x in [-1.35,1.35]: b.line(Vector3(x,.14,4.7),Vector3(x,.14,9.8),CYAN)
	_frontage_ramp(b)
	b.box(Vector3(0,6.72,5.2),Vector3(16.6,2.05,.24),"LargeShopSign",MAGENTA,Basis.IDENTITY,false)
	Furnish.inscription(self,"GLYPHIC WONDERS",Vector3(0,6.75,5.36),88,CYAN).pixel_size=.012
	Furnish.inscription(self,"OPEN",Vector3(0,3.25,5.2),25,MAGENTA)
	Furnish.inscription(self,"WONDERS WITHIN",Vector3(0,1.1,-4.84),25,CYAN)
	entrance_anchor=Furnish.marker(self,"ShopEntrance",Vector3(0,1.25,6))
	arrival_anchor=Furnish.marker(self,"ShopOutsideArrival",Vector3(0,GROUND+.05,8))
	arrival_anchor.rotation.y=PI
	b.commit()

func _frontage_ramp(b: Node3D) -> void:
	var a := Vector3(0,0,13)
	var z := Vector3(0,GROUND,10.8)
	var side := Vector3.RIGHT*3
	var drop := Vector3.DOWN*.18
	b.convex(PackedVector3Array([a-side+drop,a+side+drop,z-side+drop,z+side+drop,a-side,a+side,z-side,z+side]),[[0,2,3,1],[4,5,7,6],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]],Vector3.ZERO,"ShopFrontageRamp",CYAN)
