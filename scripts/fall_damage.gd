extends Node
## Only uncontrolled vertical descent hurts. Planar combat momentum is unrelated.
const Reaction = preload("res://scripts/fall_reaction.gd")
signal landed(result: Dictionary)
var actor: CharacterBody3D
var reaction = Reaction.new()
var last_landing: Dictionary = {}
var _tracking := false
var _peak_y := 0.0
var _last_position := Vector3.ZERO
var _position_valid := false

func _ready() -> void:
	name = "FallDamage"
	reaction.actor = actor
	reset()

func reset() -> void:
	_tracking = false
	_peak_y = actor.global_position.y
	_last_position = actor.global_position
	_position_valid = true
	last_landing = {}
	reaction.cancel()

func rebase_after_phase() -> void:
	# A horizontal phase is not vertical braking or a fresh descent.
	_last_position = actor.global_position
	_position_valid = true

func on_dodge_started(_origin: Vector3, _destination: Vector3) -> void:
	reaction.cancel()

func advance(delta: float) -> void:
	reaction.advance(delta)

func evaluate(height: float, down_speed: float) -> Dictionary:
	var descent := maxf(0,height)
	var speed := maxf(0,down_speed)
	# The energy cap rewards actual braking; the height cap also prevents a
	# short movement/attack impulse from behaving like a hundred-metre drop.
	var effective := minf(descent,speed*speed/(2*maxf(0.001,actor.gravity)))
	for boundary in [15.0,25.0,40.0,70.0,100.0]:
		if absf(effective-boundary)<0.00001:
			effective = boundary
			break
	var damage := 0.0
	var kind := &"safe"
	if effective>70:
		kind = &"critical"
		damage = minf(1000,600+(effective-70)*400/30)
	elif effective>40:
		kind = &"severe"
		damage = lerpf(180,600,(effective-40)/30)
	elif effective>25:
		kind = &"heavy"
		damage = lerpf(50,180,(effective-25)/15)
	elif effective>15:
		kind = &"minor"
		damage = (effective-15)*5
	return {"height":descent,"speed":speed,"effective_height":effective,"damage":damage,"kind":kind}

func prepare(grounded: bool) -> void:
	var position := actor.global_position
	if not _position_valid or position.distance_to(_last_position)>2:
		# Respawn/editor repositioning must not inherit a previous fall. Normal
		# motion is already recorded after each sweep; phase rebases separately.
		_tracking = true
		_peak_y = position.y
		reaction.cancel()
	if not grounded or actor.velocity.y>0:
		if not _tracking or actor.velocity.y>0: _peak_y = position.y
		else: _peak_y = maxf(_peak_y,position.y)
		_tracking = true
		if actor.velocity.y>0: reaction.cancel()
	_last_position = position
	_position_valid = true

func finish(preimpact_velocity: Vector3) -> void:
	var position := actor.global_position
	if not actor.is_on_floor():
		if not _tracking: _peak_y = maxf(_last_position.y,position.y)
		_tracking = true
		_peak_y = maxf(_peak_y,position.y)
	elif _tracking and preimpact_velocity.y<=0:
		# Sample BEFORE move_and_slide removes the impact's vertical velocity.
		var result := evaluate(_peak_y-position.y,-preimpact_velocity.y)
		result.position = position
		_tracking = false # A contact can apply damage only once.
		last_landing = result
		if result.damage>0:
			if result.kind in [&"severe",&"critical"]:
				actor.weapon_combat.enter_forced(&"fallen",0.85,position+Vector3.FORWARD)
			reaction.begin(result.kind,result.effective_height)
		landed.emit(result.duplicate()) # Observable even when defeat respawns us.
		if result.damage>0: actor.weapon_combat.receive_environment_damage(result.damage)
	_last_position = actor.global_position

func apply_pose(delta: float) -> void:
	if reaction.active() and reaction.kind in [&"severe",&"critical"] and actor.weapon_combat.can_act():
		# The short action gate ends before the cosmetic get-up tail. Once an
		# attack/guard is accepted, its authored whole-body motion takes over.
		if not actor.weapon_combat.active_move.is_empty() or actor.combat.charge_action != &"" or actor.combat.blocking: reaction.cancel()
	if reaction.active() and not actor.weapon_combat.visual_frozen() and not actor.dodge.active: reaction.apply(delta)
