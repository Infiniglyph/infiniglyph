extends Control
## Health, accumulated strain and the player's local world-grid address.
const Regions = preload("res://scripts/world_regions.gd")
var actor: Node3D
var weapons: Node
var health_bar: ProgressBar
var shield_bar: ProgressBar
var shield_label: Label
var exhaustion_bar: ProgressBar
var grid_marker: Label
var _grid_cell: Vector2i
var _grid_ready := false

func _ready() -> void:
	name = "CombatHUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(24,24)
	size = Vector2(260,68)
	health_bar = _bar("HPBar",0,18,Color(0.12,0.92,0.98))
	shield_bar = _bar("ShieldBar",22,8,Color(.30,.55,1.0))
	shield_label=Label.new()
	shield_label.name="ShieldPoints"
	shield_label.position=Vector2(0,19)
	shield_label.size=Vector2(260,14)
	shield_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	shield_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shield_label.add_theme_font_size_override("font_size",10)
	add_child(shield_label)
	exhaustion_bar = _bar("ExhaustionBar",36,6,Color(1,0.40,0.10))
	grid_marker = Label.new()
	grid_marker.name = "GridMarker"
	grid_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_marker.position = Vector2(20,46)
	grid_marker.size = Vector2(240,20)
	grid_marker.clip_text = true
	grid_marker.add_theme_font_size_override("font_size",12)
	grid_marker.add_theme_color_override("font_color",Color(0.57,0.80,0.83))
	grid_marker.add_theme_color_override("font_shadow_color",Color(0,0.015,0.02,0.95))
	grid_marker.add_theme_constant_override("shadow_offset_x",1)
	grid_marker.add_theme_constant_override("shadow_offset_y",1)
	add_child(grid_marker)
	weapons.changed.connect(refresh)
	actor.inventory.changed.connect(refresh)
	refresh()

func _draw() -> void:
	var ink := Color(0.28,0.57,0.62)
	draw_rect(Rect2(0,50,12,12),ink,false,1)
	for offset in [4,8]:
		draw_line(Vector2(offset,50),Vector2(offset,62),ink,1)
		draw_line(Vector2(0,50+offset),Vector2(12,50+offset),ink,1)
	draw_rect(Rect2(4,54,4,4),Color(0.12,0.92,0.98))

func _refresh_grid() -> void:
	if not is_instance_valid(actor): return
	var context: Node=actor.get("respawn_context")
	if is_instance_valid(context) and context.active_location!=&"overworld":
		var travel: Node=actor.get_parent().get("dungeon_travel")
		grid_marker.text=travel.location_label(context.active_location,actor.global_position) if is_instance_valid(travel) else "PYRAMID  /  "+context.floor_label
		_grid_ready=false
		return
	var cell := Regions.grid_at(actor.global_position)
	if _grid_ready and cell==_grid_cell: return
	_grid_ready = true
	_grid_cell = cell
	grid_marker.text = Regions.grid_label(cell)

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
	shield_bar.max_value=maxf(1,weapons.shield_capacity)
	shield_bar.value=weapons.shield_points
	shield_bar.visible=weapons.shield_capacity>0
	shield_label.text="SHIELD  %d / %d" % [weapons.shield_points,weapons.shield_capacity] if shield_bar.visible else ""
	exhaustion_bar.max_value = maxf(1,weapons.rules.max_psi)
	exhaustion_bar.value = weapons.psi_meter
	_refresh_grid()

func _process(_delta: float) -> void:
	# Recovery is continuous between combat notifications. Read the existing
	# resource directly; exhaustion fills with strain rather than draining stamina.
	exhaustion_bar.value = weapons.psi_meter
	_refresh_grid()
