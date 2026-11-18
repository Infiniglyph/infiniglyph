extends Node3D
## One continuous, physically connected pyramid: entry hub, U1-U8 and B1-B8.
const Floor = preload("res://scripts/pyramid_floor.gd")
const Stair = preload("res://scripts/pyramid_stair.gd")
const Furnishings = preload("res://scripts/pyramid_furnishings.gd")
const CELL := 8.0
const WALL_HEIGHT := 7.0
const LAYOUT = Floor.HUB_LAYOUT
const GOLD := Floor.GOLD
const INK := Floor.INK
var spawn_anchor: Marker3D
var exit_anchor: Marker3D
# Compatibility references describe the preserved entry maze.
var chunks: Array[Node3D] = []
var open_cells: Array[Vector2i] = []
var glyph_count := 0
var floors: Dictionary = {}
var definitions: Array[Dictionary] = []
var stairs: Array[Node3D] = []
var current_floor: StringName = &"hub"
var visible_floors: Array[StringName] = []

static func open_at(x: int, row: int) -> bool: return Floor.hub_open(x,row)
static func cell_position(x: int, row: int) -> Vector3: return Vector3((x-4)*CELL,0,-row*CELL)
static func half_at(y: float) -> float: return Floor.half_at(y)

func _ready() -> void:
	name="PyramidInterior"
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color(.001,.002,.004)
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color(.14,.12,.08)
	settings.ambient_light_energy=.35
	environment.environment=settings
	add_child(environment)
	var upper_titles:=["Colonnade","Cross Hall","Shaft Gallery","Divided Court","Bent Galleries","Upper Ledges","Processional Hall","Summit Chamber"]
	var lower_titles:=["Lower Forehall","Twin Courts","Hypostyle Hall","Monument Court","Deep Galleries","Great Cross Hall","Arena Antechamber","Throne of the Vile Pharaoh"]
	for n in range(8,0,-1):
		definitions.append({"id":StringName("B"+str(n)),"branch":"lower","number":n,"y":-144.0 if n==8 else -16.0*n,"ceiling":-16.0*(n-1),"title":lower_titles[n-1]})
	definitions.append({"id":&"hub","branch":"hub","number":0,"y":0.0,"ceiling":8.0,"title":"Inner Labyrinth"})
	for n in range(1,9):
		definitions.append({"id":StringName("U"+str(n)),"branch":"upper","number":n,"y":8.0*n,"ceiling":80.0 if n==8 else 8.0*(n+1),"title":upper_titles[n-1]})
	# Each connector is physical geometry, with an explicit traversal route.
	for i in range(definitions.size()-1):
		var lower: Dictionary=definitions[i]
		var upper: Dictionary=definitions[i+1]
		var stair:=Stair.new()
		stair.lower_id=lower.id
		stair.upper_id=upper.id
		stair.lower_y=lower.y
		stair.upper_y=upper.y
		stair.center_x=-26.0
		stair.front_z=-63.0
		if upper.branch=="upper":
			var margin:=half_at(upper.y+2.4)-2
			var side:=1.0 if upper.number%2==1 else -1.0
			stair.center_x=side*minf(26,maxf(0,margin-5))
			stair.direction=side
			stair.front_z=Floor.CENTER.z-side*minf(35,maxf(0,margin-12))
		elif upper.branch=="lower":
			# Successive flights occupy opposing corners, not a continuous shaft.
			var margin:=half_at(upper.y+2.4)-2
			var side:=-1.0 if upper.number%2==1 else 1.0
			stair.center_x=-side*margin*.65
			stair.direction=side
			stair.front_z=Floor.CENTER.z-side*(margin*.52-(upper.y-lower.y)*.5)
		stairs.append(stair)
	# All storeys are prepared before entry. Only neighboring storeys render.
	for data in definitions:
		var storey:=Floor.new()
		storey.definition=data
		for stair in stairs:
			if stair.upper_id==data.id: storey.floor_holes.append(stair.footprint())
			if stair.lower_id==data.id: storey.ceiling_holes.append(stair.footprint())
			if stair.upper_id==data.id or stair.lower_id==data.id:
				var approach: Vector3=(stair.top() if stair.upper_id==data.id else stair.bottom())+Vector3(0,0,2*stair.direction)
				storey.traversal_lanes.append(Rect2(minf(0,approach.x)-1.4,approach.z-1.4,absf(approach.x)+2.8,2.8))
		var above_index:=definitions.find(data)+1
		if above_index<definitions.size():
			var shaft:=Floor.shaft_for(definitions[above_index])
			if shaft.has_area(): storey.ceiling_holes.append(shaft)
		add_child(storey)
		floors[data.id]=storey
		storey.dressing=Furnishings.new()
		storey.dressing.storey=storey
		storey.add_child(storey.dressing)
		glyph_count+=storey.glyph_count
	for stair in stairs: add_child(stair)
	chunks.assign(floors[&"hub"].maze_chunks)
	open_cells.assign(floors[&"hub"].open_cells)
	spawn_anchor=floors[&"hub"].spawn_anchor
	spawn_anchor.name="DungeonFrontDoorSpawn"
	exit_anchor=Marker3D.new()
	exit_anchor.name="DungeonExit"
	exit_anchor.position=Vector3(0,.05,3)
	add_child(exit_anchor)
	var sign:=Label3D.new()
	sign.name="ExitInscription"
	sign.text="PYRAMID  /  EXIT"
	sign.position=Vector3(0,6.4,3.65)
	sign.rotation.y=PI
	sign.font_size=40
	sign.pixel_size=.012
	sign.modulate=INK
	floors[&"hub"].add_child(sign)
	for entry: Dictionary in [{"x":-24,"text":"B1–B8  /  DESCENT"},{"x":24,"text":"U1–U8  /  ASCENT"}]:
		var label:=Label3D.new()
		label.text=entry.text
		label.position=Vector3(entry.x,4.5,-59.7)
		label.modulate=INK
		label.font_size=34
		label.pixel_size=.018
		floors[&"hub"].add_child(label)
	update_visibility(spawn_anchor.position,true)

func floor_at(point: Vector3) -> StringName:
	var id: StringName=definitions[0].id
	for data in definitions:
		if point.y>=float(data.y)-.4: id=data.id
	return id

func update_visibility(point: Vector3, force: bool = false) -> bool:
	var id:=floor_at(point)
	if not force and current_floor==id: return false
	current_floor=id
	var index: int=floors.keys().find(id)
	visible_floors.clear()
	for i in range(definitions.size()):
		var visible_now:=absi(i-index)<=1
		floors[definitions[i].id].visible=visible_now
		if visible_now: visible_floors.append(definitions[i].id)
	for stair in stairs: stair.visible=stair.lower_id in visible_floors or stair.upper_id in visible_floors
	return true

func pickup_parent_for(point: Vector3) -> Node3D:
	return floors[floor_at(point)].content

func floor_label(point: Vector3) -> String:
	var id:=floor_at(point)
	return "ENTRY HUB" if id==&"hub" else String(id)

func saved_state(actor: CharacterBody3D, yaw: float) -> Dictionary:
	var point:=actor.global_position
	return {"floor_id":String(floor_at(point)),"position":[point.x,point.y,point.z],"yaw":yaw}

func resolve_saved_position(state: Dictionary, actor: CharacterBody3D) -> Vector3:
	var id:=StringName(state.get("floor_id","hub"))
	var fallback: Node3D=floors.get(id,floors[&"hub"])
	var values: Variant=state.get("position",[])
	if values is Array and values.size()==3:
		var point:=Vector3(float(values[0]),float(values[1]),float(values[2]))
		if point.is_finite() and point.y>=definitions[0].y and point.y<80:
			var inferred:=floor_at(point)
			if not floors.has(id): fallback=floors[inferred]
			var half:=half_at(point.y)-1
			if absf(point.x)<half and absf(point.z-Floor.CENTER.z)<half:
				var space:=get_world_3d().direct_space_state
				var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.2,point-Vector3.UP*.65,1,[actor.get_rid()])
				var hit:=space.intersect_ray(ray)
				if not hit.is_empty() and hit.normal.y>.65:
					var safe: Vector3=hit.position+Vector3.UP*.05
					var shape:=CapsuleShape3D.new()
					shape.radius=.28
					shape.height=1.85
					var query:=PhysicsShapeQueryParameters3D.new()
					query.shape=shape
					query.transform.origin=safe+Vector3.UP*.95
					query.collision_mask=1
					query.exclude=[actor.get_rid()]
					if space.intersect_shape(query,1).is_empty(): return safe
	return fallback.spawn_anchor.global_position
