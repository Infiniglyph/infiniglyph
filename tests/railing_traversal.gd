extends SceneTree
## Actual controller motion while pressing into rails, then reversing/escaping.
class Intent extends "res://scripts/player_input.gd":
	func sample() -> void: pass
var world: Node3D
var actor: CharacterBody3D
var controls: Intent
var checks:=0
var failures:=0
var hz:=60

func check(ok: bool, message: String) -> void:
	checks+=1
	if ok: print("PASS: ",message)
	else:
		failures+=1
		push_error("FAIL: "+message)

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz=int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second=hz
	call_deferred("run")

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func rail_walk(a: Vector3, b: Vector3, inward: Vector3, label: String, boost: bool = false) -> void:
	controls.move=Vector2.ZERO
	actor.global_position=a+inward*.38+Vector3.UP*.05
	actor.velocity=Vector3.ZERO
	actor.fall_damage.reset()
	actor.unstuck.reset_history()
	await frames(8)
	var along:=Vector3(b.x-a.x,0,b.z-a.z).normalized()
	var length:=Vector2(b.x-a.x,b.z-a.z).length()
	var reached:=false
	controls.sprint=true
	controls.boost=boost
	# Diagonal pressure keeps the actual capsule touching the barrier.
	for i in range(ceili((length/3.0+3)*hz)):
		var progress: float=(actor.global_position-a).dot(along)
		if progress>=length-.3:
			reached=true
			break
		var move:=along-inward*.55
		controls.move=Vector2(move.x,move.z).normalized()
		await frames(1)
	var position: Vector3=actor.global_position
	var safe: bool=(position-a).dot(inward)>.22 and actor.is_on_floor()
	controls.move=Vector2(inward.x,inward.z)
	await frames(ceili(hz*.9))
	var escaped: bool=(actor.global_position-position).dot(inward)>.6
	controls.move=Vector2.ZERO
	controls.boost=false
	check(reached and safe and escaped,label+" slides under side pressure and releases without jumping or Unstick")
	if not reached or not safe or not escaped: print("RAIL BLOCKED ",label," at ",position," expected end ",b," inward ",inward," escaped ",escaped," escape delta ",actor.global_position-position," velocity ",actor.velocity)

func curve_walk(reverse: bool) -> void:
	var center:=Vector3(-36,12.26,-28)
	# Use the uninterrupted arc, clear of the stair-landing merge, where the
	# floor union's exposed boundary legitimately changes from circle to square.
	var start:=.8 if reverse else .3
	var end:=.3 if reverse else .8
	var sign_value: float=-1 if reverse else 1
	controls.move=Vector2.ZERO
	actor.global_position=center+Vector3(sin(start)*26.1,.05,cos(start)*26.1)
	actor.velocity=Vector3.ZERO
	actor.fall_damage.reset()
	await frames(8)
	controls.boost=true
	var reached:=false
	for i in range(hz*8):
		var relative: Vector3=actor.global_position-center
		var angle:=atan2(relative.x,relative.z)
		if (angle-end)*sign_value>=-.01:
			reached=true
			break
		var outward:=Vector3(sin(angle),0,cos(angle))
		var move:=Vector3(cos(angle),0,-sin(angle))*sign_value+outward*.5
		controls.move=Vector2(move.x,move.z).normalized()
		await frames(1)
	controls.move=Vector2.ZERO
	controls.boost=false
	check(reached and actor.is_on_floor() and absf(actor.position.y-12.26)<.12,"Connected curved rail joints stay smooth at sprint speed "+("reverse" if reverse else "forward"))
	if not reached or not actor.is_on_floor() or absf(actor.position.y-12.26)>=.12:
		print("CURVE BLOCKED at ",actor.position," velocity ",actor.velocity," angle ",atan2(actor.position.x-center.x,actor.position.z-center.z))
		for i in range(actor.get_slide_collision_count()):
			var hit:=actor.get_slide_collision(i)
			print("CURVE CONTACT ",hit.get_collider_shape().name," normal ",hit.get_normal())

func run() -> void:
	world=load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled=false
	world.world_memory_enabled=false
	world.district_life_enabled=false
	world.boss_encounters_enabled=false
	root.add_child(world)
	actor=world.player
	actor.visual.retrieval.enabled=false
	controls=Intent.new()
	root.add_child(controls)
	actor.controls=controls
	world.camera_rig.controls=controls
	world.inventory_session.controls=controls
	world.camera_rig.yaw=0
	await frames(12)
	if "--curves-only" in OS.get_cmdline_user_args():
		await curve_walk(false)
		await curve_walk(true)
		world.queue_free()
		controls.queue_free()
		quit(1 if failures else 0)
		return
	var city: Node3D=world.dungeon_travel.outside_root.get_node("CentralDistrict/Metropolis")
	var space:=actor.get_world_3d().direct_space_state
	var gaps:=0
	var probes:=0
	for span: Dictionary in city.guard_spans:
		var side:=Vector3(-(span.b-span.a).z,0,(span.b-span.a).x).normalized()
		for t: float in [.1,.3,.5,.7,.9]:
			for height: float in [.2,.5,.95]:
				var point: Vector3=span.a.lerp(span.b,t)+Vector3.UP*height
				if space.intersect_ray(PhysicsRayQueryParameters3D.create(point-side*.18,point+side*.18,1,[actor.get_rid()])).is_empty(): gaps+=1
				probes+=1
	check(probes>1000 and gaps==0,"City guards have continuous low/middle/top collision across "+str(probes)+" probes")
	var tested:=0
	var tags: Dictionary={}
	for span: Dictionary in city.guard_spans:
		if span.a.distance_to(span.b)<3 or tags.get(span.tag,0)>=3: continue
		var a: Vector3=span.a.lerp(span.b,.15)
		var b: Vector3=span.a.lerp(span.b,.85)
		if a.distance_to(b)>8: b=a+(b-a).normalized()*8
		var side:=Vector3(-(b-a).z,0,(b-a).x).normalized()
		var inward:=Vector3.ZERO
		for sign_value in [-1,1]:
			var probe: Vector3=a+side*sign_value*.65+Vector3.UP*.08
			if actor.unstuck.broad_support(probe): inward=side*sign_value
		if inward.is_zero_approx(): continue
		await rail_walk(a,b,inward,String(span.tag)+" forward",tested%2==0)
		await rail_walk(b,a,inward,String(span.tag)+" reverse")
		tested+=1
		tags[span.tag]=tags.get(span.tag,0)+1
	check(tested>=6,"Actual traversal covers multiple city deck, curve, landing and ramp guards")
	await curve_walk(false)
	await curve_walk(true)
	for side in [-1,1]:
		var a:=Vector3(side*5.8,.15,-880)
		var b:=Vector3(side*5.8,.15,-864)
		await rail_walk(a,b,Vector3(-side,0,0),"Countryside bridge "+str(side),true)
		await rail_walk(b,a,Vector3(-side,0,0),"Countryside bridge reverse "+str(side))
	controls.move=Vector2.ZERO
	actor.global_position=world.wider_world.pyramid.to_global(Vector3(65.5,.15,0))
	actor.velocity=Vector3.ZERO
	await frames(8)
	check(world.dungeon_travel.interact(),"Dungeon railing test enters through the normal doorway")
	while world.dungeon_travel.busy: await frames(1)
	for index in [8,9]:
		var stair: Node3D=world.dungeon_travel.interior.stairs[index]
		var a: Vector3=stair.route[2]+Vector3.LEFT*1.6-Vector3.UP*.05
		var b: Vector3=stair.route[3]+Vector3.LEFT*1.6-Vector3.UP*.05
		await rail_walk(a,b,Vector3.RIGHT,"Dungeon flight "+str(index),true)
		await rail_walk(b,a,Vector3.RIGHT,"Dungeon flight reverse "+str(index))
	world.queue_free()
	controls.queue_free()
	print("Railing traversal: ",checks," checks @",hz," Hz, ",failures," failures")
	quit(1 if failures else 0)
