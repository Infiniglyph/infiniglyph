extends Node3D
## Purpose-free physical shell. Exterior collision is always resident; only a
## five-storey window of simple interior batches is materialized near the player.
const Chunk=preload("res://scripts/world_chunk.gd")
const Neon=preload("res://scripts/neon.gd")
const WALL:=.30
const SLAB:=.20
const DOOR_WIDTH:=2.6
const DOOR_HEIGHT:=2.85
const STAIR_WIDTH:=3.2
const STAIR_DEPTH:=9.4
var building_id:=""
var dimensions:=Vector3.ZERO
var color:=Color(.025,.74,.85)
var floor_height:=3.5
var floor_count:=1
var possible_floors:=1
var manual_review:=false
var review_reason:=""
var porch_lift:=0.0
var _loaded: Dictionary={}
var _contents: Node3D
var _access_gate: Node3D
var _gate_shape: CollisionShape3D
var _stair_min:=Vector2.ZERO
var _stair_max:=Vector2.ZERO

static func stable_id(point: Vector3,context: String="regions") -> String:
	return "building/"+context+"/%d/%d" % [roundi(point.x*100),roundi(point.z*100)]

func configure(id: String,size: Vector3,ink: Color=Color(.025,.74,.85),porch: float=0.0) -> void:
	building_id=id; dimensions=size; color=ink; porch_lift=porch
	name="BuildingShell"
	manual_review=not size.is_finite() or size.x<6 or size.z<6 or size.y<3.2 or size.y>1024
	if manual_review:
		review_reason="The footprint or clear ceiling cannot safely fit the standard shell."
		return
	possible_floors=maxi(1,floori((size.y+.0001)/3.2))
	floor_count=possible_floors if size.x>=10 and size.z>=10 else 1
	floor_height=size.y/possible_floors
	if floor_count==1 and possible_floors>1: review_reason="Ground floor usable; upper storeys need a custom stair layout."
	if floor_count>1:
		_stair_max=Vector2(size.x*.5-WALL,-size.z*.5+WALL+STAIR_DEPTH)
		_stair_min=Vector2(_stair_max.x-STAIR_WIDTH,_stair_max.y-STAIR_DEPTH)

func placement_layout() -> Dictionary:
	return {"width":dimensions.x,"depth":dimensions.z,"floor_height":floor_height,"floor_count":floor_count,"ceiling_height":floor_height-SLAB,
		"wall":WALL,"aisle_width":2.2,"stair_min":[_stair_min.x-.12,_stair_min.y],"stair_max":[_stair_max.x,_stair_max.y],"upper_manual_review":possible_floors>floor_count}

func descriptor(point: Vector3,region: String,reported_size: Vector3=Vector3.ZERO) -> Dictionary:
	return {"id":building_id,"point":point,"size":dimensions if reported_size.is_zero_approx() else reported_size,"region":region,"shell":self,
		"layout":placement_layout(),"manual_review":manual_review,"review_reason":review_reason,
		"entry":point+Vector3(0,.04,dimensions.z*.5-.9),"exit":point+Vector3(0,.04+porch_lift,dimensions.z*.5+1.1)}

func bake_exterior(batch: Node3D,at: Vector3) -> void:
	if manual_review:
		batch.box(at+Vector3.UP*dimensions.y*.5,dimensions,"BuildingManualReview",color)
		return
	var w:=dimensions.x; var h:=dimensions.y; var d:=dimensions.z
	# The actual solid mass is hollowed, including the front render surface.
	# A decorative door drawn over the former monolithic collider would not work.
	batch.box(at+Vector3(0,-SLAB*.5,0),Vector3(w,SLAB,d),"ShellGroundFloor",color)
	batch.box(at+Vector3(0,h-SLAB*.5,0),Vector3(w,SLAB,d),"ShellRoof",color)
	batch.box(at+Vector3(0,h*.5,-d*.5+WALL*.5),Vector3(w,h,WALL),"ShellBackWall",color)
	for side in [-1,1]:
		batch.box(at+Vector3(side*(w-WALL)*.5,h*.5,0),Vector3(WALL,h,d),"ShellSideWall",color)
		batch.box(at+Vector3(side*(w+DOOR_WIDTH)*.25,h*.5,(d-WALL)*.5),Vector3((w-DOOR_WIDTH)*.5,h,WALL),"ShellDoorJamb",color)
	batch.box(at+Vector3(0,(h+DOOR_HEIGHT)*.5,(d-WALL)*.5),Vector3(DOOR_WIDTH,h-DOOR_HEIGHT,WALL),"ShellDoorLintel",color)
	for side in [-1,1]: batch.line(at+Vector3(side*DOOR_WIDTH*.5,0,d*.5+.012),at+Vector3(side*DOOR_WIDTH*.5,DOOR_HEIGHT,d*.5+.012),color)
	batch.line(at+Vector3(-DOOR_WIDTH*.5,DOOR_HEIGHT,d*.5+.012),at+Vector3(DOOR_WIDTH*.5,DOOR_HEIGHT,d*.5+.012),color)

func furniture_parent() -> Node3D:
	if not is_instance_valid(_contents):
		_contents=Node3D.new(); _contents.name="InstalledContents"; add_child(_contents)
	return _contents

func set_accessible(accessible: bool) -> void:
	# The authority supplies true for a body already inside, preserving egress.
	# Permission checks never depend on the colour/visibility of a fake doorway.
	if manual_review: return
	if not accessible and not is_instance_valid(_access_gate):
		_access_gate=Neon.block(self,Vector3(0,DOOR_HEIGHT*.5,(dimensions.z-WALL)*.5),Vector3(DOOR_WIDTH,DOOR_HEIGHT,WALL),Neon.shared_material(color*.7))
		_access_gate.name="AccessControlledDoor"
		_gate_shape=_access_gate.get_node("Collision").get_child(0)
	if is_instance_valid(_access_gate):
		_access_gate.visible=not accessible
		_gate_shape.disabled=accessible

func entry_position() -> Vector3: return to_global(Vector3(0,.04,dimensions.z*.5-.9))
func exit_position() -> Vector3: return to_global(Vector3(0,.04+porch_lift,dimensions.z*.5+1.1))

func ensure_local_contents_loaded(floor: int=0) -> bool:
	if manual_review or floor<0 or floor>=floor_count: return false
	set_nearby(true,floor*floor_height)
	return true

func set_nearby(nearby: bool,local_y: float=0.0) -> void:
	var wanted: Dictionary={}
	if nearby and not manual_review:
		var center:=clampi(floori((local_y+.2)/floor_height),0,floor_count-1)
		for level in range(maxi(0,center-2),mini(floor_count,center+3)): wanted[level]=true
	for level: int in _loaded.keys():
		if not wanted.has(level): _loaded[level].free(); _loaded.erase(level)
	for level: int in wanted:
		if not _loaded.has(level): _load_floor(level)

func _tile(batch: Node3D,x0: float,x1: float,z0: float,z1: float,y: float) -> void:
	if x1-x0<.01 or z1-z0<.01: return
	batch.box(Vector3((x0+x1)*.5,y-SLAB*.5,(z0+z1)*.5),Vector3(x1-x0,SLAB,z1-z0),"InteriorFloor",color*.65)

func _load_floor(level: int) -> void:
	var batch:=Chunk.new()
	batch.name="InteriorFloor_%03d" % level
	add_child(batch); _loaded[level]=batch
	var y:=level*floor_height
	var x0:=-dimensions.x*.5+WALL; var x1:=dimensions.x*.5-WALL
	var z0:=-dimensions.z*.5+WALL; var z1:=dimensions.z*.5-WALL
	if level>0:
		var back:=_stair_min.y+1.5; var front:=_stair_max.y-1.5
		_tile(batch,x0,_stair_min.x,z0,z1,y)
		_tile(batch,_stair_min.x,x1,z0,back,y)
		_tile(batch,_stair_min.x,x1,front,z1,y)
		batch.rail(Vector3(_stair_min.x,y,back),Vector3(_stair_min.x,y,front),1.08,"StairwellGuard",color*.8,.12)
		# Each landing joins the two alternating lanes. Its opposite end is
		# guarded, so a floor never exposes an unprotected empty stair opening.
		var connected_front:=level%2==1
		var closed_z:=back if connected_front else front
		batch.rail(Vector3(_stair_min.x,y,closed_z),Vector3(x1,y,closed_z),1.08,"LandingGuard",color*.8,.12)
		if level==floor_count-1:
			var empty_min:=_stair_min.x+STAIR_WIDTH*.5 if (level-1)%2==0 else _stair_min.x
			var end_z:=front if connected_front else back
			batch.rail(Vector3(empty_min,y,end_z),Vector3(empty_min+STAIR_WIDTH*.5,y,end_z),1.08,"TopLandingGuard",color*.8,.12)
	if level<floor_count-1: _stair(batch,level,y)
	# Flush seams and one real warm luminaire; no per-frame interior simulations.
	for z in range(ceili(z0/2),floori(z1/2)+1): batch.line(Vector3(x0,y+.012,z*2),Vector3(_stair_min.x if floor_count>1 else x1,y+.012,z*2),color*.35)
	for x in range(ceili(x0/2),floori((_stair_min.x if floor_count>1 else x1)/2)+1): batch.line(Vector3(x*2,y+.012,z0),Vector3(x*2,y+.012,z1),color*.35)
	var fixture:=Vector3(minf(-1.8,dimensions.x*-.2),y+floor_height-.28,0)
	batch.box(fixture,Vector3(1.2,.06,.12),"InteriorLuminaire",Neon.ORANGE,Basis.IDENTITY,false)
	batch.commit()
	var light:=OmniLight3D.new()
	light.name="InteriorLight"; light.position=fixture-Vector3.UP*.15
	light.light_color=Neon.ORANGE; light.light_energy=.7; light.omni_range=minf(12,dimensions.x*.8)
	light.shadow_enabled=false; batch.add_child(light)

func _stair(batch: Node3D,level: int,y: float) -> void:
	var forward:=level%2==0
	var cx:=_stair_min.x+(.8 if forward else 2.4)
	var start:=_stair_min.y+1.5 if forward else _stair_max.y-1.5
	var finish:=_stair_max.y-1.5 if forward else _stair_min.y+1.5
	var vertices:=PackedVector3Array()
	for lift in [-.18,0.0]:
		vertices.append_array([Vector3(cx-.7,y+lift,start),Vector3(cx+.7,y+lift,start),Vector3(cx+.7,y+floor_height+lift,finish),Vector3(cx-.7,y+floor_height+lift,finish)])
	var faces: Array=[[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]
	if forward:
		for face: Array in faces: face.reverse()
	batch.convex(vertices,faces,Vector3.ZERO,"InteriorStairRamp",color*.65)
	# Tread markings preserve a stair silhouette over the continuous walkable
	# collision plane, avoiding a lip or a tiny riser trapping a fast capsule.
	var steps:=ceili(floor_height/.2)
	for i in range(steps+1):
		var t:=float(i)/steps
		var p:=Vector3(cx,y+floor_height*t+.008,lerpf(start,finish,t))
		batch.line(p+Vector3.LEFT*.7,p+Vector3.RIGHT*.7,color)
	for side in [-1,1]: batch.rail(Vector3(cx+side*.7,y,start),Vector3(cx+side*.7,y+floor_height,finish),1.08,"StairFlightGuard",color*.8,.10)
