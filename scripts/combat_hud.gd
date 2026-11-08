extends Control
## Assigned weapons, actual move names, health and guard state.
const Library = preload("res://scripts/weapon_library.gd")
var intent: Node
var weapons: Node
var slots: Dictionary = {}
var guard: Label
var action: Label
var health: Label
var lock_status: Label
var impact: Label
var exhaustion: Label
var special_labels: Array[Label] = []

func label_at(text_value: String, at: Vector2) -> Label:
	var result := Label.new()
	result.text = text_value
	result.position = at
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result

func _ready() -> void:
	name = "CombatHUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -338
	offset_right = -26
	offset_top = 24
	offset_bottom = 520
	# Opaque enough for text to stay readable against the denser city wirework.
	var backing := Panel.new()
	backing.position = Vector2(-14,-12)
	backing.size = Vector2(340,540)
	backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.002,0.012,0.018,0.91)
	frame.border_color = Color(0.04,0.78,0.94,0.75)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(8)
	backing.add_theme_stylebox_override("panel",frame)
	add_child(backing)
	label_at("WEAPON SLOTS",Vector2.ZERO).modulate = Color(0.16,0.85,0.93)
	var row := 0
	for slot: StringName in [&"up",&"left",&"right",&"down"]:
		slots[slot] = label_at("",Vector2(0,28+row*24))
		row += 1
	health = label_at("",Vector2(0,128))
	guard = label_at("",Vector2(0,146))
	action = label_at("",Vector2(0,172))
	for i in range(4): special_labels.append(label_at("",Vector2(0,210+i*23)))
	label_at("Hold special: charge / release\nHold DOWN: sheathe / draw\nEmber: east sidewalk by sentries",Vector2(0,316)).modulate = Color(0.42,0.64,0.69)
	lock_status = label_at("",Vector2(0,390))
	impact = label_at("",Vector2(0,442))
	exhaustion = label_at("",Vector2(0,492))
	intent.changed.connect(refresh)
	weapons.changed.connect(refresh)
	refresh()

func refresh() -> void:
	for slot: StringName in slots:
		slots[slot].text = ("> " if slot == intent.selected_slot else "  ")+String(slot).to_upper()+"  "+weapons.loadout(slot).short
		slots[slot].modulate = Color(0.15,1,1) if slot == intent.selected_slot else Color(0.35,0.55,0.6)
	health.text = "HP %d / %d  ·  %s" % [ceili(weapons.health),ceili(weapons.max_health),"SHEATHED" if intent.sheathed else "DRAWN"]
	health.modulate = Color(0.6,0.9,0.95)
	guard.text = ("BLOCK HELD  ·  %d%% front guard" % int(weapons.guard_strength()*100)) if intent.blocking else "Guard ready"
	guard.modulate = Color(0.15,1,1) if intent.blocking else Color(0.35,0.55,0.6)
	if weapons.parry_feedback>0:
		guard.text = "PARRY!"
		guard.modulate = Color(1,0.82,0.18)
	elif intent.blocking and weapons.parry_remaining>0:
		guard.text = "PARRY READY"
	action.text = weapons.status+("  %.1fs" % weapons.stagger_remaining if weapons.is_staggered() else "")
	action.modulate = Color(1,0.82,0.18) if weapons.is_staggered() else Color(0.42,0.64,0.69)
	exhaustion.text = "Exhaustion %d / %d" % [ceili(weapons.psi_meter),ceili(weapons.rules.max_psi)]
	exhaustion.modulate = Color(1,0.4,0.45) if weapons.psi_meter>weapons.rules.max_psi*0.7 else Color(0.42,0.64,0.69)
	var lock_on: Node3D = weapons.actor.target_lock
	lock_status.modulate = Color(0.75,1,1)
	if lock_on.is_locked():
		var target: Node3D = lock_on.opponent
		var hp = target.get("health")
		lock_status.text = "LOCK: "+("COUNTER SENTRY" if target.get("counterattacks") == true else "OPPONENT")
		if target.has_method("combat_name"): lock_status.text = "LOCK: "+target.combat_name()
		if hp != null: lock_status.text += "\nTarget HP: %d" % ceili(float(hp))
		if target.get("weapon_combat") != null and target.weapon_combat.is_staggered():
			lock_status.text += "  OPEN %.1fs" % target.weapon_combat.stagger_remaining
	else: lock_status.text = "R3 / TAB: lock on\nI J K L / right stick: switch target"
	impact.text = "Hit %.1f  |  x%.2f\nImpact speed: %.1f m/s" % [weapons.last_hit_amount,weapons.last_strike_multiplier,weapons.last_strike_speed] if weapons.impact_feedback>0 else "Momentum increases strike damage"
	impact.modulate = Color(0.75,1,1) if weapons.impact_feedback>0 else Color(0.42,0.64,0.69)
	var bindings := ["X / Q","Y / R","RT+X / V+Q","RT+Y / V+R"]
	var actions := [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]
	for i in range(4):
		special_labels[i].text = bindings[i]+"  "+weapons.move_for(intent.selected_slot,actions[i]).get("name","--")
		special_labels[i].modulate = weapons.loadout(intent.selected_slot).color
