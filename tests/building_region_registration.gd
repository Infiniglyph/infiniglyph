extends SceneTree
## Whole-map geometry/registration audit without running the civilization AI.
const Regions=preload("res://scripts/world_regions.gd")
const District=preload("res://scripts/district.gd")
const Registry=preload("res://scripts/building_registry.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func run() -> void:
	var world:=Node3D.new(); root.add_child(world)
	var district:=District.new(); district.visual_batching_enabled=false; world.add_child(district)
	var regions:=Regions.new(); world.add_child(regions)
	for i in range(3): await physics_frame; await process_frame
	var records: Array=regions.building_records()
	check(records.size()==regions.buildings.size()+44 and regions.shell_records.size()==regions.buildings.size(),"Every legacy outer building and all 44 central façades have independent physical records")
	check(get_nodes_in_group("resident_entrances").size()==22,"Original leased resident entrances and their hidden transit screens remain intact")
	var ids: Dictionary={}; var duplicate:=false; var rejected:=0
	var model:=Registry.new()
	var active:=0; var unopened:=0; var safe:=0; var doors:=0; var roofs:=0; var reviewed:=0
	var space:=world.get_world_3d().direct_space_state
	for record: Dictionary in records:
		if ids.has(record.id): duplicate=true
		ids[record.id]=true
		if not model.register(record): rejected+=1
		if record.manual_review:
			if not String(record.review_reason).is_empty(): reviewed+=1
			continue
		active+=1
		var shell: Node3D=record.shell
		if shell._loaded.is_empty() and not is_instance_valid(shell._contents): unopened+=1
		if record.layout.floor_count==shell.floor_count and record.layout.ceiling_height>=3 and (shell.floor_count==1 or record.layout.stair_min[0]>1.1): safe+=1
		var at: Vector3=record.point
		var depth: float=shell.dimensions.z
		var door:=PhysicsRayQueryParameters3D.create(at+Vector3(0,1.2,depth*.5+1),at+Vector3(0,1.2,depth*.5-1),1)
		if space.intersect_ray(door).is_empty(): doors+=1
		var top: Vector3=record.point+Vector3.UP*record.size.y
		var roof:=space.intersect_ray(PhysicsRayQueryParameters3D.create(top+Vector3.UP*2,top-Vector3.UP*2,1))
		if not roof.is_empty() and roof.position.y>=top.y-.15: roofs+=1
	check(not duplicate and rejected==0,"Stable shell IDs are unique and every descriptor registers with the persistent building authority")
	check(active>500 and active==unopened,"Hundreds of physical shells keep all detailed interior batches and furniture roots unloaded at a distance")
	check(safe==active,"All generated rooms retain at least three metres of clear ceiling and protect the central exit aisle")
	check(doors==active,"Every converted outer building has a genuinely clear, physically cut doorway (%d)" % doors)
	check(roofs==active,"All converted urban crowns and gabled homes retain solid original-height roofs (%d)" % roofs)
	check(reviewed==records.size()-active and reviewed>=44,"Unsuitable or reserved original scenery has explicit manual-review reasons")
	var full_mass:=0; var crowns:=0; var gables:=0
	for chunk: Node3D in regions.chunks.values():
		for volume: Dictionary in chunk.volumes:
			if volume.kind in ["UrbanBuilding","Home","FarmBuilding"]: full_mass+=1
			if volume.kind=="UrbanCrown": crowns+=1
			if volume.kind=="GabledRoof": gables+=1
	check(full_mass==0 and crowns>150 and gables>250,"Original crowns and pitched roofs stay in the exterior batches while obsolete solid building masses are removed")
	print("BUILDING RECORDS total=",records.size()," converted=",active," manual=",reviewed," crowns=",crowns," gables=",gables)
	world.queue_free(); await process_frame; await physics_frame
	print("Building region verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
