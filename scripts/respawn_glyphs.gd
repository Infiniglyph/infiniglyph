extends Node
## Inventory-owned anchors and a live death choice. Never pauses the world.
const Data = preload("res://scripts/respawn_glyph_data.gd")
const Marker = preload("res://scripts/respawn_glyph_marker.gd")
const Context = preload("res://scripts/respawn_context.gd")
var world: Node3D
var actor: CharacterBody3D
var loot: Node3D
var waiting := false
var markers: Dictionary={}
var _signature := ""
var _selection := ""
var _screen: Control
var _rows: VBoxContainer
var _buttons: Array[Button]=[]
var _keys: Array[String]=[]
var _cursor := 0
var _stick_delay := 0.0
var _previous_mouse: int

func _ready() -> void:
	name="RespawnGlyphs"
	actor=world.player
	loot=world.loot
	loot.respawn_glyphs=self
	actor.respawn_selector=self
	if not is_instance_valid(actor.respawn_context):
		var context:=Context.new()
		add_child(context)
		actor.respawn_context=context
	actor.respawn_context.glyphs=self
	actor.inventory.changed.connect(sync_markers)
	_build_menu()
	set_process_input(false)
	sync_markers()

func roots() -> Dictionary:
	return world.dungeon_travel.contexts if is_instance_valid(world.dungeon_travel) else {&"overworld":world}

func record_safe(record: Dictionary) -> bool:
	var location:=StringName(record.location)
	if not roots().has(location): return false
	var point:=Data.point(record)
	var supported: Dictionary=loot.supported_position(point,location)
	if supported.is_empty() or point.distance_to(supported.point)>.18: return false
	var shape:=CapsuleShape3D.new()
	shape.height=1.85
	shape.radius=.28
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.transform.origin=point+Vector3.UP*.95
	query.collision_mask=9
	query.exclude=loot.solid_exclusions()
	return loot._space(location).intersect_shape(query,1).is_empty()

func placement(item_type: StringName) -> Dictionary:
	if not Data.TYPES.has(item_type) or waiting or actor.health<=0 or actor.transition_locked or not actor.is_on_floor() or actor.dodge.active: return {}
	if is_instance_valid(actor.world_actions) and actor.world_actions.attached(): return {}
	if actor.weapon_combat.is_staggered() or not actor.weapon_combat.active_move.is_empty(): return {}
	var location: StringName=loot.location_for(actor)
	# Rented lodgings can expire; they are not permanent reconstruction points.
	if is_instance_valid(world.dungeon_travel) and world.dungeon_travel.is_rental(location): return {}
	var floor: Dictionary=loot.supported_position(actor.global_position,location)
	if floor.is_empty() or absf(actor.global_position.y-float(floor.point.y))>.22: return {}
	var point: Vector3=floor.point+Vector3.UP*.025
	var record: Dictionary={"location":String(location),"position":[point.x,point.y,point.z],"yaw":wrapf(actor.visual.global_rotation.y,-PI,PI),"camera_yaw":wrapf(actor.camera_rig.yaw,-PI,PI),"camera_pitch":actor.camera_rig.pitch}
	return record if record_safe(record) else {}

func sync_markers() -> void:
	var points: Dictionary=actor.inventory.respawn_points
	var signature:=JSON.stringify(points)
	if signature==_signature: return
	_signature=signature
	for marker: Node in markers.values():
		if is_instance_valid(marker): marker.queue_free()
	markers.clear()
	for key: String in points:
		var record: Dictionary=points[key]
		var root: Node3D=roots().get(StringName(record.location))
		if not is_instance_valid(root): continue
		var point:=Data.point(record)
		var marker:=Marker.new()
		marker.home=key=="home"
		var parent: Node3D=root.pickup_parent_for(point) if root.has_method("pickup_parent_for") else root
		parent.add_child(marker)
		marker.global_position=point
		marker.global_rotation.y=float(record.yaw)
		markers[key]=marker

func begin_choice() -> bool:
	if waiting: return true
	if actor.inventory.respawn_points.is_empty(): return false
	world.inventory_session.ui.close_menu()
	world.inventory_session.shop.close_menu()
	world.start_menu.close_menu()
	actor.weapon_combat.cancel()
	actor.target_lock.clear()
	actor.velocity=Vector3.ZERO
	actor.transition_locked=true
	actor.controls.set_gameplay_enabled(false)
	actor.visual.hide()
	waiting=true
	_previous_mouse=Input.mouse_mode
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_buttons.clear()
	_keys.clear()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for key: String in ["respawn","home"]:
		if not actor.inventory.respawn_points.has(key): continue
		var record: Dictionary=actor.inventory.respawn_points[key]
		if not record_safe(record): continue
		var place: String="Open world" if record.location=="overworld" else "Pyramid / "+world.dungeon_travel.interior.floor_label(Data.point(record))
		_add_choice(key,("Home Respawn Glyph" if key=="home" else "Respawn Glyph")+"  |  "+place)
	var default_label := "Open world"
	if is_instance_valid(world.dungeon_travel):
		if world.dungeon_travel.is_rental(): default_label="Guild hallway"
		elif world.dungeon_travel.is_pyramid(): default_label="Pyramid entrance"
	_add_choice("default","Default spawn  |  "+default_label)
	_cursor=0
	_stick_delay=0
	_screen.show()
	_buttons[0].grab_focus()
	set_process_input(true)
	return true

func choose(key: String) -> void:
	if not waiting or key not in _keys: return
	_selection=key
	waiting=false
	_screen.hide()
	set_process_input(false)
	actor.transition_locked=false
	actor.visual.show()
	actor.respawn()
	_selection=""
	actor.controls.set_gameplay_enabled(true)
	Input.mouse_mode=_previous_mouse

func resolve_spawn() -> Variant:
	if _selection not in ["respawn","home"]: return null
	var record: Dictionary=actor.inventory.respawn_points.get(_selection,{})
	if record.is_empty() or not record_safe(record): return null
	var location:=StringName(record.location)
	if is_instance_valid(world.dungeon_travel):
		var travel: Node=world.dungeon_travel
		if travel.active_location!=location: travel._set_location(location)
		if location!=&"overworld":
			travel.interior.update_visibility(Data.point(record),true)
			travel.respawns.floor_label=travel.interior.floor_label(Data.point(record))
	actor.visual.global_rotation.y=float(record.yaw)
	actor.camera_rig.yaw=float(record.camera_yaw)
	actor.camera_rig.pitch=float(record.camera_pitch)
	return Data.point(record)

func _add_choice(key: String, title: String) -> void:
	var button:=Button.new()
	button.text=title
	button.custom_minimum_size=Vector2(570,54)
	button.add_theme_color_override("font_color",Color(.78,1,1))
	for state: String in ["normal","hover","focus","pressed"]:
		var style:=StyleBoxFlat.new()
		style.bg_color=Color(.012,.055,.065)
		style.border_color=Color(.35,1,.8) if state in ["focus","hover"] else Color(.10,.42,.5)
		style.set_border_width_all(2 if state in ["focus","hover"] else 1)
		style.set_content_margin_all(10)
		button.add_theme_stylebox_override(state,style)
	button.pressed.connect(choose.bind(key))
	_rows.add_child(button)
	_buttons.append(button)
	_keys.append(key)

func _build_menu() -> void:
	var layer:=CanvasLayer.new()
	layer.layer=40
	add_child(layer)
	_screen=Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_screen)
	var shade:=ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color=Color(0,.008,.015,.70)
	_screen.add_child(shade)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(center)
	var panel:=PanelContainer.new()
	var backing:=StyleBoxFlat.new()
	backing.bg_color=Color(.004,.025,.035,.97)
	backing.border_color=Color(.12,.85,.92)
	backing.set_border_width_all(2)
	backing.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel",backing)
	center.add_child(panel)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	panel.add_child(box)
	var title:=Label.new()
	title.text="CHOOSE WHERE TO RECONSTRUCT"
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",25)
	title.add_theme_color_override("font_color",Color(.55,1,.85))
	box.add_child(title)
	_rows=VBoxContainer.new()
	_rows.add_theme_constant_override("separation",8)
	box.add_child(_rows)
	var hint:=Label.new()
	hint.text="A / Enter: choose    |    Both placed glyphs remain reusable"
	hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size",14)
	hint.add_theme_color_override("font_color",Color(.55,.75,.8))
	box.add_child(hint)
	_screen.hide()

func _input(event: InputEvent) -> void:
	if not waiting: return
	var step:=0
	var accept:=false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_UP,KEY_W]: step=-1
		elif event.keycode in [KEY_DOWN,KEY_S]: step=1
		accept=event.keycode in [KEY_ENTER,KEY_KP_ENTER,KEY_SPACE]
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index==JOY_BUTTON_DPAD_UP: step=-1
		elif event.button_index==JOY_BUTTON_DPAD_DOWN: step=1
		accept=event.button_index==JOY_BUTTON_A
	elif event is InputEventJoypadMotion and event.axis==JOY_AXIS_LEFT_Y:
		if absf(event.axis_value)>.55 and Time.get_ticks_msec()/1000.0>_stick_delay:
			step=signi(int(signf(event.axis_value)))
			_stick_delay=Time.get_ticks_msec()/1000.0+.2
	if step!=0:
		_cursor=posmod(_cursor+step,_buttons.size())
		_buttons[_cursor].grab_focus()
	if accept: choose(_keys[_cursor])
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion: get_viewport().set_input_as_handled()
