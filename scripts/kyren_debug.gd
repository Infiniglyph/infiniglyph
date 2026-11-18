extends PanelContainer
## Constructed only in a debug build with an explicit developer opt-in.
var encounter: Node
var readout: Label
var clock := 0.0
var sample_serial := 0
func _ready() -> void:
	position=Vector2(18,180)
	var box := VBoxContainer.new()
	add_child(box)
	readout=Label.new()
	box.add_child(readout)
	var slider := HSlider.new()
	slider.min_value=0
	slider.max_value=100
	slider.step=1
	slider.custom_minimum_size.x=320
	slider.value=encounter.salt.value
	slider.value_changed.connect(func(value: float): set_salt(value))
	box.add_child(slider)
	for state in [0,25,50,75,100]:
		var button := Button.new()
		button.text="Salt %d%%" % state
		button.pressed.connect(set_salt.bind(float(state)))
		box.add_child(button)
	var sample := Button.new()
	sample.text="Sample clean hit (active fight)"
	sample.pressed.connect(trigger_sample)
	box.add_child(sample)
	var preview := Button.new()
	preview.text="Preview three-defeats exchange"
	preview.pressed.connect(func(): preview_dialogue("three_defeats_first"))
	box.add_child(preview)
	var reset := Button.new()
	reset.text="Reset Kyren history (outside combat)"
	reset.pressed.connect(reset_history)
	box.add_child(reset)

func set_salt(value: float) -> void:
	if encounter.debug_enabled: encounter.salt.set_value(value)
func trigger_sample() -> void:
	if not encounter.debug_enabled: return
	sample_serial+=1
	encounter.salt.contact({"event_id":"debug:"+str(sample_serial),"damage":1,"health_ratio":1},true)
func preview_dialogue(id: String) -> void:
	if encounter.debug_enabled: encounter.dialogue.preview(id)
func reset_history() -> void:
	if not encounter.debug_enabled or encounter.active: return
	encounter.progress=encounter.Progress.fresh()
	encounter.salt.lingering_floor=10
	encounter.salt.set_value(10)
	encounter.boss.controls.observed.clear()
	encounter.boss.controls.favored=""
	if encounter.persistence_enabled: encounter.save_checkpoint()
func _process(delta: float) -> void:
	clock+=delta
	if clock<.2: return
	clock=0
	readout.text="KYREN DEVELOPER\nSalt: %.1f%% / %s\nHP: %.1f / %.1f\nPlayer wins/losses: %d / %d\nConsecutive Kyren defeats: %d\nEvent: %s\nDialogue cooldown: %.1fs\nLine: %s\nAI: %s / %s" % [encounter.salt.value,encounter.salt.state(),encounter.boss.health,encounter.boss.weapon_combat.max_health,encounter.progress.wins,encounter.progress.losses,encounter.progress.kyren.consecutive_defeats,encounter.salt.last_event,encounter.dialogue.cooldown_remaining,encounter.dialogue.last_selected,encounter.boss.state,encounter.boss.controls.behavior]
