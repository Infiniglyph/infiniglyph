extends SceneTree
## Historical panels must never acquire a different driver as their attacker.
const Wave = preload("res://scripts/vehicle_light_wave.gd")
class Vehicle:
	extends CharacterBody3D
	var record := {"color":Color.CYAN,"driver":{"code_form_id":"native_a"}}
	var health := 1000.0
	var wave_enabled := true
	var dimensions := Vector3(1.85,1.8,4.1)
	var player_driver: Node
	func driving_actor() -> Node:
		if is_instance_valid(player_driver): return player_driver
		set_meta("code_form_id",String(record.driver.code_form_id))
		return self
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)
func panel(wave: Node) -> void:
	wave.segments.append({"a":Vector3.ZERO,"b":Vector3(2,0,0),"born":wave.now()})
	wave._previous[99] = Transform3D.IDENTITY
	wave._hit_until[99] = wave.now()+1
func run() -> void:
	var vehicle := Vehicle.new()
	root.add_child(vehicle)
	var wave := Wave.new()
	wave.vehicle = vehicle
	vehicle.add_child(wave)
	wave.set_enabled(true)
	wave.set_physics_process(false)
	check(wave.owner_actor.get_ref()==vehicle,"Native wave damage uses its mounted Code Form representation")
	panel(wave)
	wave.set_enabled(false)
	wave.set_enabled(true)
	wave.set_physics_process(false)
	check(wave.segments.size()==1,"Toggling for the same driver preserves that driver's existing panels")
	var player := Node3D.new()
	root.add_child(player)
	vehicle.player_driver = player
	wave.set_enabled(false)
	wave.set_enabled(true)
	wave.set_physics_process(false)
	check(wave.segments.is_empty() and wave._previous.is_empty() and wave._hit_until.is_empty() and wave.owner_actor.get_ref()==player,"Changing from native to player clears historical panels and contact history")
	panel(wave)
	vehicle.player_driver = null
	wave.set_enabled(false)
	wave.set_enabled(true)
	wave.set_physics_process(false)
	check(wave.segments.is_empty() and wave.owner_actor.get_ref()==vehicle,"Returning to a native driver never inherits the player's laser panels")
	panel(wave)
	vehicle.record.driver.code_form_id = "native_b"
	wave.set_enabled(false)
	wave.set_enabled(true)
	wave.set_physics_process(false)
	check(wave.segments.is_empty(),"A replacement native identity cannot inherit panels through the same vehicle Node")
	panel(wave)
	vehicle.record.driver.code_form_id = "native_c"
	wave._physics_process(1.0/60)
	check(wave.segments.is_empty() and not wave.enabled,"An identity handoff during emission also cancels historical damage before contact resolution")
	vehicle.free()
	player.free()
	print("VEHICLE WAVE ATTRIBUTION: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
