extends SceneTree
## Real input, physics hurt volumes, terrain occlusion, guards and locomotion.
const Library = preload("res://scripts/weapon_library.gd")
const Target = preload("res://scripts/practice_target.gd")
class Intent extends Node:
	var move := Vector2.ZERO
	var sprint := false
	var boost := false
	var jump := false
	var guard := false
	func sample() -> void: pass
	func is_blocking() -> bool: return guard
	func consume_jump() -> bool:
		var result := jump
		jump = false
		return result
var failures := 0
var checks := 0
var world: Node3D
var p: CharacterBody3D
var w: Node
var controls: Node
var dummy: StaticBody3D
var intent: Intent

func check(condition: bool, label: String) -> void:
	checks += 1
	if condition: print("PASS: ",label)
	else:
		push_error("FAIL: "+label)
		failures += 1

func frames(count: int) -> void:
	for i in range(count):
		await physics_frame
		await process_frame

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	controls._unhandled_input(event)

func equip(slot: StringName) -> void:
	controls._request(&"weapon",slot)
	p.combat.poll(controls)

func cast(action: StringName) -> void:
	controls._request(&"action",action)
	p.combat.poll(controls)

func reset_actor() -> void:
	p.respawn()
	p.position = Vector3.ZERO
	p.camera_rig.yaw = 0
	p.velocity = Vector3.ZERO
	p.controls = intent
	intent.move = Vector2.ZERO
	intent.sprint = false
	intent.boost = false
	intent.guard = false
	await frames(30)

func block(held: bool) -> void:
	intent.guard = held
	key(KEY_F,held)
	p.combat.poll(controls)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	p = world.player
	w = p.weapon_combat
	controls = world.controls
	p.visual.retrieval.enabled = false
	intent = Intent.new()
	root.add_child(intent)
	p.controls = intent
	for sentry in get_nodes_in_group("combat_targets"): sentry.counterattacks = false
	await reset_actor()
	# Down resolves on release for taps, and never switches the current weapon on hold.
	equip(&"right")
	key(KEY_DOWN)
	controls.update_combat_hold(0.25)
	p.combat.poll(controls)
	check(p.combat.selected_slot == &"right" and not p.combat.sheathed,"Beginning Down leaves the current katana drawn")
	key(KEY_DOWN,false)
	p.combat.poll(controls)
	check(p.combat.selected_slot == &"down" and not p.combat.sheathed,"Short Down release draws longsword and shield")
	equip(&"left")
	key(KEY_DOWN)
	controls.update_combat_hold(0.46)
	p.combat.poll(controls)
	check(p.combat.sheathed and p.combat.selected_slot == &"left" and w.rig.models.left.stowed.visible,"Held Down sheathes the existing spear on the body")
	key(KEY_DOWN,false)
	p.combat.poll(controls)
	check(p.combat.sheathed and p.combat.selected_slot == &"left","Releasing a sheathe hold does not select sword or redraw")
	cast(&"special_x")
	check(not p.combat.sheathed and not w.active_move.is_empty() and w.rig.selected==&"left","An attack draws the current spear and starts its requested special")
	equip(&"left")
	check(not p.combat.sheathed and w.rig.models.left.right.visible and not w.rig.models.left.stowed.visible,"Selecting the same slot draws its stowed weapon")
	key(KEY_DOWN)
	key(KEY_UP)
	key(KEY_UP,false)
	controls.update_combat_hold(0.6)
	key(KEY_DOWN,false)
	p.combat.poll(controls)
	check(p.combat.selected_slot == &"up" and not p.combat.sheathed,"Another direction cancels an unfinished Down gesture")
	key(KEY_DOWN)
	controls.update_combat_hold(0.3)
	controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	controls.update_combat_hold(1)
	key(KEY_DOWN,false)
	p.combat.poll(controls)
	check(p.combat.selected_slot == &"up" and not p.combat.sheathed,"Focus loss cancels a pending sheathe without a false tap")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_DOWN
	pad.device = Input.get_connected_joypads()[0] if not Input.get_connected_joypads().is_empty() else 0
	pad.pressed = true
	controls._unhandled_input(pad)
	controls.update_combat_hold(0.46)
	p.combat.poll(controls)
	check(p.combat.sheathed,"D-pad Down uses the same hold-to-sheathe gesture")
	controls._on_joy_connection_changed(pad.device,false)
	controls.update_combat_hold(1)
	p.combat.poll(controls)
	check(p.combat.selected_slot == &"up","Disconnecting a held D-pad does not create a selection tap")

	dummy = Target.new()
	dummy.max_health = 10000
	dummy.health = 10000
	world.add_child(dummy)
	dummy.position = Vector3(0,0,-1.25)
	await frames(2)
	# Every authored move is exercised through the real command and timed hit path.
	var names: Dictionary = {}
	for slot: StringName in Library.LOADOUTS:
		equip(slot)
		var visible_count := 0
		for model: Dictionary in w.rig.models.values():
			if model.right.visible: visible_count += 1
		check(visible_count == 1 and w.rig.models[slot].right.visible,"Only the equipped hand model is drawn: "+String(slot))
		for action: StringName in [&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]:
			var spec := Library.move(slot,action)
			var previous_damage: float = dummy.total_damage
			var previous_hits: int = dummy.hit_count
			cast(action)
			await frames(maxi(1,int(float(spec.hits[0])*60)-2))
			check(dummy.hit_count == previous_hits,"No damage before the authored contact: "+spec.name)
			await frames(ceili(float(spec.duration)*60)+3)
			var expected: float = float(spec.damage)*spec.hits.size()
			check(is_equal_approx(dummy.total_damage-previous_damage,expected) and dummy.hit_count-previous_hits == spec.hits.size(),"Timed damage pulses, one hit per target per pulse: "+spec.name)
			check(w.active_move.is_empty() and p.velocity.length()<0.01 and p.global_position.distance_to(Vector3.ZERO)<0.04,"Move recovers without changing root movement: "+spec.name)
			if String(action).begins_with("special"): names[spec.name] = true
	check(names.size() == 16,"All sixteen weapon specials have distinct names")
	await frames(40)
	check(get_nodes_in_group("weapon_effects").is_empty() and w.trail.samples.is_empty(),"Glyph effects and blade trails expire after recovery")
	# Late input queues once; a held/early input does not become automatic repeats.
	equip(&"down")
	before_queue_check()
	cast(&"attack_right")
	await frames(22)
	cast(&"attack_left")
	await frames(45)
	check(dummy.hit_count-_queue_hits == 2 and w.active_move.is_empty(),"One late attack buffers into the next move without repeating")
	before_queue_check()
	cast(&"special_y")
	cast(&"attack_right")
	await frames(95)
	check(dummy.hit_count-_queue_hits == 1 and w.active_move.is_empty(),"An early buffered command expires instead of firing much later")
	# Hit cones, reach and actual world geometry, not cosmetic-only attacks.
	equip(&"left")
	dummy.position = Vector3(0,0,1.4)
	var before: float = dummy.total_damage
	cast(&"attack_right")
	await frames(36)
	check(dummy.total_damage == before,"A forward spear thrust does not hit behind the player")
	cast(&"special_y")
	await frames(60)
	check(dummy.total_damage > before,"Spear's full orbit hits a target behind the player")
	dummy.position = Vector3(0,0,-9)
	before = dummy.total_damage
	cast(&"special_rt_x")
	await frames(66)
	check(dummy.total_damage == before,"Long-range Prism Skewer respects its seven-metre reach")
	dummy.position = Vector3(0,0,-4)
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,3,0.15)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = Vector3(0,1.5,-2)
	await frames(2)
	cast(&"special_rt_x")
	await frames(66)
	check(dummy.total_damage == before,"Even a long-range special cannot deal damage through a wall")
	wall.queue_free()
	await frames(2)
	cast(&"special_rt_x")
	await frames(66)
	check(is_equal_approx(dummy.total_damage-before,58),"Removing the obstruction restores the long-range hit")
	dummy.position = Vector3(0,0,-1.25)
	before = dummy.total_damage
	cast(&"special_rt_x")
	await frames(5)
	w.cancel()
	await frames(65)
	check(dummy.total_damage == before,"Cancelling a charged special prevents its future hit window")
	# Feedback reports applied damage, and defeated targets retain solid collision.
	dummy.health = 5
	var reported: Array[float] = []
	var on_hit := func(_target: Node, amount: float, _move: String): reported.append(amount)
	w.hit_landed.connect(on_hit)
	cast(&"attack_right")
	await frames(36)
	check(dummy.health == 0 and reported.size()==1 and is_equal_approx(reported[0],5),"Hit feedback reports only the damage a target actually receives")
	check(dummy.collision_layer==3 and dummy.get_child(0).disabled==false,"A rebooting practice target remains a physical structure")
	await frames(125)
	check(dummy.health == dummy.max_health,"Defeated practice targets reboot for repeatable testing")
	w.hit_landed.disconnect(on_hit)
	dummy.position = Vector3(20,0,0)
	# Guard values and camera-relative front coverage; rear attacks remain dangerous.
	for slot: StringName in Library.LOADOUTS:
		equip(slot)
		w.health = 100
		block(true)
		await frames(ceili(w.PARRY_WINDOW*60)+1)
		var damage: float = w.receive_hit(20,Vector3(0,1,-2))
		check(is_equal_approx(damage,20*(1-float(Library.loadout(slot).guard))) and w.last_blocked,"Weapon-specific front guard mitigation: "+String(slot))
		damage = w.receive_hit(10,Vector3(0,1,2))
		check(is_equal_approx(damage,10) and not w.last_blocked,"Guard leaves the rear exposed: "+String(slot))
		block(false)
	p.camera_rig.yaw = PI/2
	block(true)
	check(w.receive_hit(10,Vector3(-2,1,0))<10 and (w.last_blocked or w.last_parried),"Guard direction follows camera rotation")
	block(false)
	p.camera_rig.yaw = 0
	equip(&"down")
	cast(&"special_rt_x")
	check(is_equal_approx(w.receive_hit(20,Vector3(0,1,2)),1),"Aegis Bloom protects all directions during its defensive window")
	w.cancel()
	cast(&"special_y")
	block(true)
	check(w.active_move.is_empty(),"Starting a guard cancels a pending attack")
	block(false)
	cast(&"special_y")
	equip(&"right")
	check(w.active_move.is_empty() and w.rig.selected == &"right","Weapon switching cancels the previous move")
	cast(&"special_y")
	key(KEY_DOWN)
	controls.update_combat_hold(0.5)
	p.combat.poll(controls)
	key(KEY_DOWN,false)
	check(w.active_move.is_empty() and p.combat.sheathed,"Sheathing cancels an attack immediately")
	equip(&"down")
	cast(&"special_y")
	check(p.dodge.start(Vector3.RIGHT) and w.active_move.is_empty(),"Phase dodge cancels an attack and remains available")
	p.dodge.advance(0.12)
	var faded := true
	for node in p.visual.find_children("*","GeometryInstance3D",true,false):
		if node.material_override == null: faded = false
	check(faded,"New weapon geometry participates in the existing phase fade")
	p.dodge.advance(1)
	var restored := true
	for node in p.visual.find_children("*","GeometryInstance3D",true,false):
		if node.material_override != null: restored = false
	check(restored,"Weapon and body materials restore after phase dodge")
	await reset_actor()
	# The actual counter sentry, rather than a direct function call, exercises guard.
	equip(&"down")
	p.controls = controls
	dummy.position = Vector3(0,0,-1.8)
	dummy.actor = p
	dummy.counterattacks = true
	block(true)
	await frames(162)
	check(is_equal_approx(w.health,w.max_health-1.5) and w.last_blocked,"A real sentry counterattack is reduced by the held shield guard")
	block(false)
	dummy.counterattacks = false
	dummy.position = Vector3(20,0,0)
	# Movement distances with drawn attacks versus sheathed/no attacks.
	var distances: Array[float] = []
	for attacking in [false,true]:
		await reset_actor()
		equip(&"up")
		intent.move = Vector2(1,0)
		intent.sprint = true
		for i in range(90):
			if attacking and i % 18 == 0: cast(&"attack_right")
			await frames(1)
		distances.append(p.position.x)
		check(is_equal_approx(p.velocity.x,p.run_speed),"Running pace remains unchanged with attacks="+str(attacking))
	check(is_equal_approx(distances[0],distances[1]),"Combat animations do not alter run acceleration or displacement")
	await reset_actor()
	intent.jump = true
	cast(&"special_x")
	await frames(1)
	check(p.velocity.y>7 and not w.active_move.is_empty(),"A ground jump remains responsive during a special")
	await frames(8)
	intent.jump = true
	var old_velocity: float = p.velocity.y
	await frames(1)
	check(p.velocity.y>old_velocity+8 and p.air_step_count==1,"Unlimited sky-step impulse remains available during a special")
	var lethal_damage: float = w.receive_hit(w.max_health*2,p.position+Vector3.BACK)
	check(w.health == w.max_health and p.position.distance_to(p.spawn)<0.01 and w.active_move.is_empty(),"Depleted health respawns cleanly and resets combat state")
	check(lethal_damage>0,"A respawning hit still returns its damage to the caller")
	world.queue_free()
	intent.queue_free()
	await process_frame
	print("Weapon verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)

var _queue_hits := 0
func before_queue_check() -> void:
	_queue_hits = dummy.hit_count
