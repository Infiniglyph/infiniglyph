extends SceneTree
## Verify actual collisions and health, in addition to the height/energy tuning.
class Intent extends Node:
	var move := Vector2.ZERO
	var sprint := false
	var boost := false
	var jump := false
	var blocking := false
	var requests: Array[Dictionary] = []
	func sample() -> void: pass
	func consume_jump() -> bool:
		var requested := jump
		jump = false
		return requested
	func consume_dodge() -> bool: return false
	func is_blocking() -> bool: return blocking
	func consume_combat_requests() -> Array[Dictionary]:
		var result := requests
		requests = []
		return result

var world: Node3D
var p: CharacterBody3D
var fall: Node
var input: Intent
var hz := 60
var checks := 0
var failures := 0
var events: Array[Dictionary] = []
const CLEAR := Vector3(0,0,-106)

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func tick() -> void:
	await physics_frame
	await process_frame

func seconds(duration: float) -> void:
	for i in range(ceili(duration*hz)): await tick()

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hz="): hz = int(arg.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	call_deferred("run")

func on_landed(result: Dictionary) -> void:
	# Capture before a lethal landing may immediately respawn/reset the actor.
	events.append(result.duplicate(true))

func prepare(height: float, base := CLEAR, velocity := Vector3.ZERO) -> void:
	input.move = Vector2.ZERO
	input.sprint = false
	input.boost = false
	input.jump = false
	input.blocking = false
	input.requests.clear()
	p.respawn()
	await seconds(0.1)
	p.global_position = base+Vector3.UP*height
	p.velocity = Vector3.ZERO
	fall.reset()
	events.clear()
	await tick() # Refresh CharacterBody's floor flag after the test teleport.
	p.velocity = velocity

func wait_landing(label: String) -> Dictionary:
	for i in range(ceili(12.0*hz)):
		if not events.is_empty():
			var result: Dictionary = events[0]
			print("LAND ",label," @",hz,"Hz: ",result)
			return result
		await tick()
	check(false,label+" produces a real floor landing")
	return {"height":0.0,"speed":0.0,"effective_height":0.0,"damage":0.0,"kind":&"safe"}

func drop(height: float, label: String, base := CLEAR, velocity := Vector3.ZERO) -> Dictionary:
	await prepare(height,base,velocity)
	var result := await wait_landing(label)
	var expected: Dictionary = fall.evaluate(float(result.height),float(result.speed))
	check(absf(float(result.damage)-float(expected.damage))<0.001,label+" uses the documented height/vertical-energy calculation")
	if float(result.damage)<1000:
		check(absf(p.health-(1000-float(result.damage)))<0.01,label+" applies health damage exactly once")
	return result

func add_box(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.global_position = at
	return body

func run() -> void:
	world = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	p = world.player
	input = Intent.new()
	world.add_child(input)
	p.controls = input
	p.visual.retrieval.enabled = false
	world.sparring_partner.visual.retrieval.enabled = false
	fall = p.fall_damage
	fall.landed.connect(on_landed)
	await seconds(0.15)
	# The four brackets meet without damage jumps; only vertical impact energy
	# and actual uninterrupted descent are relevant, never attack/planar speed.
	var previous := -1.0
	for sample in [[0.0,0.0,&"safe"],[15.0,0.0,&"safe"],[20.0,25.0,&"minor"],[25.0,50.0,&"minor"],[32.5,115.0,&"heavy"],[40.0,180.0,&"heavy"],[55.0,390.0,&"severe"],[70.0,600.0,&"severe"],[85.0,800.0,&"critical"],[100.0,1000.0,&"critical"]]:
		var height := float(sample[0])
		var result: Dictionary = fall.evaluate(height,sqrt(2*p.gravity*height))
		check(absf(float(result.damage)-float(sample[1]))<0.001 and result.kind==sample[2],"%.1fm has continuous %.1f HP damage and %s response" % [height,float(sample[1]),sample[2]])
		check(float(result.damage)>=previous,"Damage never decreases as uncontrolled impact height increases (%.1fm)" % height)
		previous = float(result.damage)
	var fast_low: Dictionary = fall.evaluate(2,150)
	var slow_high: Dictionary = fall.evaluate(100,sqrt(2*p.gravity*10))
	var ascending: Dictionary = fall.evaluate(100,-30)
	check(float(ascending.damage)==0 and float(ascending.effective_height)==0,"Upward velocity cannot produce an environmental impact")
	check(float(fast_low.damage)==0 and float(fast_low.effective_height)<=2,"A fast strike close to the floor cannot invent a lethal drop")
	check(float(slow_high.damage)==0 and absf(float(slow_high.effective_height)-10)<0.001,"Braking a tall fall to safe vertical impact energy prevents damage")
	var residual: Dictionary = fall.evaluate(100,60-p.sky_jump_lift)
	check(float(residual.damage)>180,"One sky-step impulse cannot erase a still-fast uncontrolled fall")
	var safe := await drop(1.3,"ordinary jump-height drop")
	check(float(safe.damage)==0,"Ordinary jumping remains harmless")
	var threshold := await drop(14.5,"safe threshold")
	check(float(threshold.damage)==0,"An uncontrolled drop below 15m remains harmless")
	var minor := await drop(20,"minor")
	check(minor.kind==&"minor" and float(minor.damage)>0 and float(minor.damage)<50,"A 20m fall causes minor damage and selects a landing roll")
	check(not p.weapon_combat.visual_frozen() and p.weapon_combat.hitstop_remaining<=0,"Environmental damage never arms weapon-animation hitstop")
	input.jump = true
	await tick()
	check(not p.is_on_floor() and p.velocity.y>7,"A minor landing accepts jump input on its first grounded tick")
	await seconds(0.22)
	check(not fall.reaction.active() and p.visual._landing<0.001 and not p.weapon_combat.visual_frozen(),"Jumping after a damaged landing promptly clears its reaction and knee compression")
	var heavy := await drop(32.5,"moderate")
	check(heavy.kind==&"heavy" and float(heavy.damage)>50 and float(heavy.damage)<180,"A moderate fall selects a heavy landing")
	var severe := await drop(55,"severe")
	check(severe.kind==&"severe" and float(severe.damage)>180 and float(severe.damage)<600,"A severe fall selects knockdown without killing a full-health player")
	var landed_health: float = p.health
	var event_count := events.size()
	await seconds(2.0)
	check(absf(p.health-landed_health)<0.001 and events.size()==event_count,"Standing after impact cannot apply the same fall damage again")
	# Knockdown temporarily gates the same input contract as other forced
	# reactions. Its longer visual recovery must release on a fresh accepted jump.
	await prepare(55)
	await wait_landing("knockdown recovery")
	check(p.weapon_combat.forced_state==&"fallen" and absf(p.weapon_combat.stagger_remaining-0.85)<0.001,"Severe impact starts the configured 0.85-second knockdown")
	input.move = Vector2.RIGHT
	input.boost = true
	input.jump = true
	input.requests.append({"kind":&"action","value":&"attack_right"})
	await tick()
	check(p.is_on_floor() and p.velocity.length()<0.01 and not p.boost_active,"Knockdown denies movement, sprint and jump while grounded")
	check(not p.weapon_combat.can_act() and p.weapon_combat.active_move.is_empty() and p.combat.last_action==&"","Knockdown denies weapon attacks through the existing combat permission contract")
	check(not p.dodge.start(Vector3.RIGHT),"Knockdown denies a phase dodge until recovery")
	await seconds(0.75-1.0/hz)
	check(p.weapon_combat.is_staggered() and p.velocity.length()<0.01,"Severe landing remains gated through the first 0.75 seconds")
	await seconds(0.14)
	check(p.weapon_combat.can_act() and p.velocity.x>0.1 and p.boost_active,"Movement and sprint recover normally after the 0.85-second knockdown")
	check(fall.reaction.active(),"Knockdown's visual recovery can continue briefly after input unlocks")
	input.requests.append({"kind":&"action","value":&"attack_right"})
	await tick()
	check(not p.weapon_combat.active_move.is_empty() and p.is_on_floor() and not fall.reaction.active(),"An accepted grounded attack cancels the knockdown visual tail and restores its authored pose")
	input.jump = true
	await tick()
	check(not p.weapon_combat.active_move.is_empty() and not p.is_on_floor() and p.velocity.y>7,"Recovered attack and jump inputs respond immediately")
	await seconds(0.22)
	check(not fall.reaction.active() and p.visual._landing<0.001,"A fresh jump after knockdown recovery never leaves a persistent knee crouch")
	var rooftop := await drop(20,"rooftop",Vector3(23,3.12,-24))
	check(absf(float(rooftop.height)-20)<0.2 and absf(float(rooftop.damage)-float(minor.damage))<1,"A rooftop uses the drop to its own surface, independent of world elevation")
	var horizontal := await drop(2,"fast horizontal attack approach",CLEAR,Vector3(120,-2,0))
	check(float(horizontal.damage)==0 and p.health==1000,"High carried horizontal momentum never causes ground-touch damage")
	check(p.weapon_combat.damage_multiplier(120)>p.weapon_combat.damage_multiplier(10.2),"The existing high-speed attack damage benefit is preserved")
	var near_ground := await drop(2,"fast downward attack close to floor",CLEAR,Vector3(0,-80,0))
	check(float(near_ground.damage)==0 and p.health==1000,"A short actual descent stays safe even with large existing downward momentum")
	# Fresh block/parry frames cannot absorb terrain damage or generate combat
	# fortitude/exhaustion outcomes. Use the real physics landing, not a mock hit.
	await prepare(20)
	input.blocking = true
	var guarded := await wait_landing("guarded")
	check(absf(p.health-(1000-float(guarded.damage)))<0.01 and float(guarded.damage)>0,"Blocking cannot reduce fall damage")
	check(p.weapon_combat.total_parries==0 and p.weapon_combat.psi_meter==0,"A fall does not count as a parry or inflict combat exhaustion")
	var history_height: float = fall.last_landing.height
	check(p.dodge.start(Vector3.RIGHT),"A minor landing allows the existing phase dodge immediately")
	check(not fall.reaction.active() and absf(float(fall.last_landing.height)-history_height)<0.001,"Dodging cancels only the landing pose and preserves the recorded fall history")
	await prepare(3)
	check(p.dodge.start(Vector3.RIGHT),"Environmental defense check enters the existing phase dodge")
	p.dodge.advance(p.dodge.DURATION*0.45)
	p.combat.blocking = true
	p.weapon_combat.parry_remaining = p.weapon_combat.PARRY_WINDOW
	var terrain_damage: float = p.weapon_combat.receive_environment_damage(25)
	check(p.dodge.is_invulnerable() and absf(terrain_damage-25)<0.001 and p.health==975,"Even active dodge invulnerability and a fresh parry cannot absorb terrain damage")
	check(not p.weapon_combat.last_parried and not p.weapon_combat.last_blocked and not p.weapon_combat.last_evaded,"Terrain damage stays separate from all combat defensive outcomes")
	# Brake just before contact: one step reduces residual energy but does not
	# become a blanket immunity flag; several timed steps make a safe landing.
	await prepare(55)
	for i in range(ceili(5.0*hz)):
		if p.global_position.y<7 and p.velocity.y<0: break
		await tick()
	input.jump = true
	await tick()
	var one_step := await wait_landing("one late sky step")
	check(float(one_step.damage)>0 and float(one_step.damage)<float(severe.damage),"One late sky step reduces damage while preserving residual fall risk")
	await prepare(55)
	for i in range(ceili(5.0*hz)):
		if p.global_position.y<7 and p.velocity.y<0: break
		await tick()
	for i in range(4):
		input.jump = true
		await tick()
	var controlled := await wait_landing("repeated sky-step braking")
	check(float(controlled.damage)==0 and p.health==1000,"Repeated sky steps control the landing and avoid tall-fall damage")
	check(float(controlled.speed)<float(one_step.speed),"Repeated sky steps reduce actual downward impact speed")
	await prepare(55)
	for i in range(ceili(5.0*hz)):
		if p.global_position.y<10 and p.velocity.y<0: break
		await tick()
	for i in range(6):
		input.jump = true
		await tick()
	var renewed_ascent := p.velocity.y>0
	var renewed := await wait_landing("renewed ascent after sky steps")
	check(renewed_ascent and float(renewed.height)<15 and float(renewed.damage)==0,"Renewed upward motion starts a fresh descent instead of retaining the old high fall")
	await prepare(55)
	for i in range(ceili(5.0*hz)):
		if p.global_position.y<7 and p.velocity.y<0: break
		await tick()
	check(p.dodge.start(Vector3.RIGHT),"A falling player can still perform the existing phase dodge")
	await seconds(p.dodge.DURATION+0.05)
	var phased := await wait_landing("airborne phase dodge")
	check(float(phased.damage)>180 and absf(float(phased.damage)-float(severe.damage))<2,"A horizontal phase preserves downward danger instead of acting as a fall reset")
	# A ceiling or wall collision must not masquerade as a grounded impact.
	await prepare(35,CLEAR,Vector3(0,30,0))
	var ceiling := add_box(CLEAR+Vector3(0,38,0),Vector3(6,0.2,6))
	await seconds(0.25)
	check(events.is_empty() and p.health==1000 and not p.is_on_floor(),"A rising ceiling collision cannot trigger fall damage or a landing response")
	ceiling.queue_free()
	await prepare(35,CLEAR,Vector3(12,-1,0))
	var wall := add_box(CLEAR+Vector3(3,35,0),Vector3(0.2,12,6))
	input.move = Vector2.RIGHT
	await seconds(0.35)
	check(events.is_empty() and p.health==1000 and not p.is_on_floor(),"A vertical wall collision cannot trigger fall damage or a landing response")
	wall.queue_free()
	await prepare(100)
	await seconds(1.0)
	p.respawn()
	await seconds(0.5)
	check(p.health==1000 and float(fall.last_landing.get("damage",0))==0,"Respawn clears pending uncontrolled descent without delayed damage")
	var after_reset := await drop(1,"small fall after respawn")
	check(float(after_reset.damage)==0 and float(after_reset.height)<1.2,"A new fall does not inherit the pre-respawn descent height")
	var lethal := await drop(105,"potentially lethal")
	check(float(lethal.damage)>=1000 and lethal.kind==&"critical","A genuinely uncontrolled 100m-plus fall can be lethal")
	await seconds(0.1)
	check(p.health==1000 and p.global_position.distance_to(p.spawn)<0.2,"Lethal terrain damage follows the existing player respawn flow")
	world.queue_free()
	await process_frame
	print("Fall damage verification @",hz,"Hz: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
