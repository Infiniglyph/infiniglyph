extends Node3D
## Authored home at the screenshot's LAT 047N / LON 003E, off the country road.
const Chunk = preload("res://scripts/world_chunk.gd")
const BlossomTree = preload("res://scripts/cherry_blossom_tree.gd")
const Kyren = preload("res://scripts/kyren.gd")
const Encounter = preload("res://scripts/kyren_encounter.gd")
const CENTER := Vector3(48,0,-752)
const HOUSE_CENTER := Vector3(-4,0,-4)
const TREE_POSITION := Vector3(6,0,5)
const WOOD := Color(.46,.32,.17)
const ROOF := Color(.48,.065,.045)
var structure: Node3D
var tree: Node3D
var kyren: CharacterBody3D
var doorway := HOUSE_CENTER+Vector3(0,.2,4.6)

func configure_encounter(player: CharacterBody3D, persistent: bool, debug: bool = false, ui_parent: Node = null) -> CanvasLayer:
	var encounter := Encounter.new()
	encounter.player=player
	encounter.boss=kyren
	encounter.home=self
	encounter.persistence_enabled=persistent
	encounter.debug_enabled=debug
	(ui_parent if is_instance_valid(ui_parent) else self).add_child(encounter)
	return encounter

static func pad_blend(x: float, z: float) -> float:
	return 1-smoothstep(16,32,maxf(absf(x-CENTER.x),absf(z-CENTER.z)))

static func reserves_plot(at: Vector3) -> bool:
	# Reserve the existing 64m scenery lot, retaining all roads and neighbors.
	return absf(at.x-CENTER.x)<32 and absf(at.z-CENTER.z)<32

func _ready() -> void:
	name = "KyrenHomestead"
	structure = Chunk.new()
	structure.name = "House"
	add_child(structure)
	_build_house()
	structure.commit()
	tree = BlossomTree.new()
	tree.position = TREE_POSITION
	add_child(tree)
	kyren = Kyren.new()
	kyren.position = TREE_POSITION+Vector3(0,0,1.8)
	add_child(kyren)

func box(offset: Vector3, size: Vector3, kind: String, color: Color = WOOD) -> void:
	structure.box(HOUSE_CENTER+offset,size,kind,color)

func _build_house() -> void:
	box(Vector3(0,.1,0),Vector3(10.4,.2,9.4),"HouseFoundation")
	box(Vector3(0,2.4,-4.5),Vector3(10,4.4,.18),"HouseBackWall")
	for side in [-1,1]:
		box(Vector3(side*5,2.4,0),Vector3(.18,4.4,9),"HouseSideWall")
		box(Vector3(side*3.1,2.4,4.5),Vector3(3.8,4.4,.18),"HouseFrontWall")
	box(Vector3(0,4.4,4.5),Vector3(2.4,.4,.18),"DoorLintel")
	# A real, open 2.4m-wide entrance; the sparse interior is ready for later work.
	box(Vector3(0,.1,6),Vector3(7,.2,3),"Porch")
	box(Vector3(0,.05,8),Vector3(3,.1,1),"PorchStep")
	for side in [-1,1]: box(Vector3(side*3.4,2.4,5.6),Vector3(.14,4.4,.14),"PorchPost")
	var roof := PackedVector3Array([Vector3(-5.5,0,-5.8),Vector3(5.5,0,-5.8),Vector3(0,1.8,-5.8),Vector3(-5.5,0,5.8),Vector3(5.5,0,5.8),Vector3(0,1.8,5.8)])
	structure.convex(roof,[[0,2,1],[3,4,5],[0,1,4,3],[0,3,5,2],[1,2,5,4]],HOUSE_CENTER+Vector3.UP*4.6,"HouseRoof",ROOF)
	for side in [-1,1]:
		var center := HOUSE_CENTER+Vector3(side*3.1,2.6,4.602)
		for x in [-.7,.7]: structure.line(center+Vector3(x,-.65,0),center+Vector3(x,.65,0),WOOD)
		for y in [-.65,0,.65]: structure.line(center+Vector3(-.7,y,0),center+Vector3(.7,y,0),WOOD)
		structure.line(center+Vector3(0,-.65,0),center+Vector3(0,.65,0),WOOD)
	# Low stepping stones keep the approach walkable from the surrounding ground.
	for i in range(5):
		structure.box(Vector3(-4+i*1.4,.035,5.5+i*.18),Vector3(.95,.07,.7),"GardenStone",WOOD*.8)
