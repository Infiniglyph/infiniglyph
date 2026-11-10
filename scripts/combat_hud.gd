extends Control
## The permanent gameplay HUD: health, with accumulated strain underneath.
var weapons: Node
var health_bar: ProgressBar
var exhaustion_bar: ProgressBar

func _ready() -> void:
	name = "CombatHUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(24,24)
	size = Vector2(260,30)
	health_bar = _bar("HPBar",0,18,Color(0.12,0.92,0.98))
	exhaustion_bar = _bar("ExhaustionBar",24,6,Color(1,0.40,0.10))
	weapons.changed.connect(refresh)
	refresh()

func _bar(label: String, top: float, height: float, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.name = label
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.step = 0
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_top = top
	bar.offset_bottom = top+height
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.004,0.018,0.024,0.96)
	background.border_color = Color(0.10,0.25,0.28)
	background.set_border_width_all(1)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background",background)
	bar.add_theme_stylebox_override("fill",fill)
	return bar

func refresh() -> void:
	health_bar.max_value = maxf(1,weapons.max_health)
	health_bar.value = weapons.health
	exhaustion_bar.max_value = maxf(1,weapons.rules.max_psi)
	exhaustion_bar.value = weapons.psi_meter

func _process(_delta: float) -> void:
	# Recovery is continuous between combat notifications. Read the existing
	# resource directly; exhaustion fills with strain rather than draining stamina.
	exhaustion_bar.value = weapons.psi_meter
