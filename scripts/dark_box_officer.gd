extends "res://scripts/resident_fighter.gd"
## An ordinary Code Form combat body using the individual's real owned gear.
func _ready() -> void:
	code_form_id=identity
	super._ready()
	set_meta("code_form_slot",String(profile.get("code_form_slot","")))
	combat.selected_slot=&"up"
	combat.sheathed=false
	combat.refresh_equipment()
	weapon_combat.sync_rig()
	label.modulate=Color("75eaff")

func _process(delta: float) -> void:
	super._process(delta)
	label.text=profile.name+"\nDARK BOX  %d / %d" % [ceili(health),ceili(weapon_combat.max_health)]
