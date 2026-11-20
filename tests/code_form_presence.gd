extends SceneTree
const Presence=preload("res://scripts/code_form_presence.gd")
var world: Node3D
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func frames(count: int=1) -> void:
	for i in range(count): await physics_frame; await process_frame
func run() -> void:
	create_timer(240).timeout.connect(func(): push_error("NPC presence watchdog"); quit(2))
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false; world.world_memory_enabled=false
	world.boss_encounters_enabled=false; world.dungeon_enemies_enabled=false
	root.add_child(world)
	world.civilization.simulation_enabled=false
	world.player.visual.retrieval.enabled=false; world.sparring_partner.visual.retrieval.enabled=false
	for i in range(600):
		await frames()
		if world.civic_interactions.initialized and world.building_civilization._guild_premises_ready: break
	check(world.population.ready_for_visitors and world.district_life._built,"Original and regional populations initialize in the complete map")
	world.process_mode=Node.PROCESS_MODE_DISABLED
	var actor: CharacterBody3D=world.player
	var population: Node3D=world.population
	var resident: CharacterBody3D=population.active_residents[0]
	var at: Vector3=resident.global_position
	var identity: String=resident.code_form_id
	actor.velocity=Vector3.ZERO
	actor.global_position=at+Vector3(180,0,0)
	population.advance_simulation_lod(0)
	check(not resident.visible and resident.virtualized and not resident.is_physics_processing(),"Distant NPC has no rendering, body physics or collision")
	check(resident.collision_layer==0 and not resident.presence.is_processing(),"Hidden NPC has no reconstruction frame callback")
	actor.global_position=at+Vector3(90,0,0)
	population.advance_simulation_lod(0)
	check(resident.visible and resident.presence.assembling and resident.virtualized,"NPC reconstructs at 90 metres before expensive body physics activates")
	var mesh: GeometryInstance3D=resident.visual.get_child(0)
	check(mesh.material_override is ShaderMaterial and mesh.material_override.shader==preload("res://scripts/environment_manifest.gdshader"),"Appearance uses the actual instance reconstruction shader on just the NPC")
	actor.transition_locked=true
	resident.presence._process(.3)
	check(resident.presence._clock==0 and resident.presence.assembling,"Instance travel retains control of borrowed reconstruction materials")
	actor.transition_locked=false
	resident.presence._process(.3)
	check(is_equal_approx(float(mesh.material_override.get_shader_parameter("progress")),.3/Presence.ASSEMBLY_SECONDS),"Reconstruction progresses across the body rather than popping on instantly")
	resident.presence._process(.3)
	check(not resident.presence.assembling and not resident.presence.is_processing() and not mesh.material_override is ShaderMaterial,"Completed appearance restores original materials and stops its callback")
	var appearances: int=resident.presence.reconstructions
	actor.global_position=at+Vector3(110,0,0)
	population.advance_simulation_lod(0)
	check(resident.visible and resident.presence.reconstructions==appearances,"Distance hysteresis keeps the same body without repeated reconstruction")
	actor.global_position=at+Vector3(140,0,0)
	population.advance_simulation_lod(0)
	check(not resident.visible,"A departing NPC retires beyond the 128 metre boundary")
	actor.global_position=at+Vector3(0,80,0)
	population.advance_simulation_lod(0)
	check(resident.visible and resident.virtualized,"Sky Jump can see people below while their distant physics stays asleep")
	actor.global_position=at+Vector3(0,160,0)
	population.advance_simulation_lod(0)
	check(not resident.visible,"NPC draw distance includes vertical separation")
	actor.global_position=at+Vector3(0,0,8)
	population.advance_simulation_lod(0)
	check(resident.visible and not resident.virtualized and resident.collision_layer==4 and not resident.presence.assembling,"A sudden close arrival immediately restores a solid, fully visible NPC")
	check(resident.code_form_id==identity and world.civilization.registry.records.has(identity),"Visibility never replaces the resident's persistent identity")
	actor.global_position=at+Vector3(140,0,0)
	population.advance_simulation_lod(1)
	check(resident.active and resident.code_form_id==identity,"Far residents retain their logical journeys and citizenship")
	check(Presence.draw_range(Vector3(100,0,0))==128 and Presence.physics_range(Vector3(100,0,0))==80,"Fast travel adds bounded NPC draw/physics headroom")
	resident.deactivate()
	resident.activate(at)
	check(not resident.visible and resident.virtualized,"Far indoor exits/startup spawns cannot flash or run a physics body")
	var geometry:=0; var changed:=0
	for root_name: String in ["District","Metropolis","WiderWorld"]:
		var place: Node=world.dungeon_travel.outside_root.get_node_or_null(root_name)
		if place==null: continue
		for node: GeometryInstance3D in place.find_children("*","GeometryInstance3D",true,false):
			geometry+=1
			# Existing cherry blossoms/scarves and building labels retain their
			# authored limits. The reverted bubble imposed a new 384 m map cutoff.
			if is_equal_approx(node.visibility_range_end,384): changed+=1
	check(geometry>100 and changed==0,"World architecture retains its original visibility, with no new scenery culling")
	var life: Node3D=world.district_life
	var record: Dictionary=life.resident_records[0]
	actor.global_position=record.point+Vector3(90,0,0)
	life.refresh_active()
	check(life._people_queue.any(func(row: Dictionary): return row.id==record.id),"Regional NPCs are queued at a visible approach distance")
	var regional: CharacterBody3D=life.people.get(record.id)
	if regional==null: regional=life.spawn_person(record)
	check(regional.presence.present and regional.virtualized and regional.presence.assembling,"Regional bodies use the same reconstruction and close physics range")
	actor.global_position=regional.global_position+Vector3(200,0,0)
	regional.record.combat=true
	life.refresh_active()
	check(life.people.has(record.id),"Distance retirement cannot remove a resident reserved for combat")
	regional.record.combat=false
	life.refresh_active()
	check(not life.people.has(record.id) and life.resident_records.has(record),"Far regional body is released while the authoritative route record remains")
	print("NPC PRESENCE COUNTS ",JSON.stringify({"logical_citizens":world.civilization.registry.slots.size(),"original_bodies":population.residents.size(),"rendered_originals":population.active_residents.filter(func(r): return r.visible).size(),"physical_originals":population.active_residents.filter(func(r): return not r.virtualized).size(),"world_geometry_checked":geometry}))
	world.queue_free(); await frames(3)
	print("Code Form presence: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
