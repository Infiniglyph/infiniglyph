extends StaticBody3D
## Solid, stationary practice sentry. The center sentry telegraphs a light
## counterattack so held guards can be tested without a full enemy AI system.
const Neon = preload("res://scripts/neon.gd")
const DamageNumber = preload("res://scripts/damage_number.gd")
var actor: CharacterBody3D
var counterattacks := false
var health := 120.0
var max_health := 120.0
var total_damage := 0.0
var hit_count := 0
var _reset_time := 0.0
var _counter_time := 2.6
var _flash := 0.0
var ink: StandardMaterial3D
var label: Label3D

func _ready() -> void:
	name = "CounterSentry" if counterattacks else "PracticeSentry"
	add_to_group("combat_targets")
	collision_layer = 3
	collision_mask = 1
	Neon.prepare()
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.34
	capsule.height = 1.7
	collider.shape = capsule
	collider.position.y = 0.95
	add_child(collider)
	var body := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = capsule.radius
	mesh.height = capsule.height
	mesh.material = Neon.dark
	body.mesh = mesh
	body.position = collider.position
	add_child(body)
	Neon.block(self,Vector3(0,0.08,0),Vector3(1,0.16,1))
	ink = Neon.material(Color(0.9,0.3,0.7))
	var points := PackedVector3Array()
	for level in [0.2,0.65,1.15,1.7]:
		var radius := 0.25 if level in [0.2,1.7] else 0.345
		for i in range(24):
			var a := i*TAU/24
			var b := (i+1)*TAU/24
			points.append_array([Vector3(cos(a)*radius,level,sin(a)*radius),Vector3(cos(b)*radius,level,sin(b)*radius)])
	for i in range(4):
		var angle := i*TAU/4
		points.append_array([Vector3(cos(angle)*0.345,0.45,sin(angle)*0.345),Vector3(cos(angle)*0.345,1.45,sin(angle)*0.345)])
	add_child(Neon.lines(points,ink))
	label = Label3D.new()
	label.position.y = 2.12
	label.font_size = 32
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.9,0.5,0.8)
	add_child(label)
	update_label()

func combat_point() -> Vector3:
	return global_position+Vector3.UP*0.95

func receive_hit(amount: float, _source: Vector3) -> float:
	if health <= 0: return 0
	var applied := minf(maxf(amount,0),health)
	health -= applied
	total_damage += applied
	hit_count += 1
	_flash = 0.18
	if health <= 0: _reset_time = 2.0
	update_label()
	if applied>0:
		DamageNumber.make_room(get_tree())
		var number := DamageNumber.new()
		number.text = "%.1f" % applied
		get_parent().add_child(number)
		number.global_position = combat_point()+Vector3((hit_count%3-1)*0.24,1.75,0)
	return applied

func update_label() -> void:
	var title := "COUNTER SENTRY" if counterattacks else "PRACTICE SENTRY"
	label.text = title+"\n"+("REBOOTING" if health <= 0 else "%d / %d" % [ceili(health),ceili(max_health)])

func _physics_process(delta: float) -> void:
	_flash = maxf(0,_flash-delta)
	if health <= 0:
		_reset_time -= delta
		if _reset_time <= 0:
			health = max_health
			update_label()
	var warning := false
	var in_duel: bool = is_instance_valid(actor) and is_instance_valid(actor.sparring_duel) and actor.sparring_duel.active
	if counterattacks and health > 0 and is_instance_valid(actor) and not in_duel:
		var offset := actor.global_position-global_position
		if Vector2(offset.x,offset.z).length()<2.65 and absf(offset.y)<1.6:
			_counter_time -= delta
			warning = _counter_time < 0.65
			if _counter_time <= 0:
				var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(combat_point(),actor.global_position+Vector3.UP*0.95,1,[get_rid()]))
				if hit.is_empty() or hit.collider == actor:
					actor.weapon_combat.receive_hit(10,combat_point())
				_counter_time = 2.6
		else: _counter_time = 2.6
	var color := Color(1,1,1) if _flash > 0 else (Color(1,0.4,0.9) if warning else Color(0.9,0.3,0.7))
	ink.albedo_color = color
	ink.emission = color
