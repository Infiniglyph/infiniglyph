extends PanelContainer
## Six rows and one on-demand preview, independent of catalog size.
const Database = preload("res://scripts/equipment_database.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
const PAGE_SIZE := 6
var shop: CanvasLayer
var buttons: Array[Button] = []
var query: LineEdit
var filter: OptionButton
var page := 0
var ids: Array[StringName] = []
var _ordered: Array[StringName] = []
var selected: StringName = &""
var rows: VBoxContainer
var heading: Label
var description: Label
var details: Label
var paging: Label
var preview: SubViewport
var stage: Node3D
var camera: Camera3D
var model: Node3D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor_left = .08
	anchor_right = .92
	anchor_top = .06
	anchor_bottom = .94
	add_theme_stylebox_override("panel",shop._style())
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",8)
	add_child(layout)
	layout.add_child(shop._label("EQUIPMENT ARCHIVE",24))
	var bar := HBoxContainer.new()
	layout.add_child(bar)
	query = LineEdit.new()
	query.placeholder_text = "Search name or weapon family..."
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query.text_changed.connect(func(_text: String): page=0; refresh())
	bar.add_child(query)
	filter = OptionButton.new()
	for name: String in ["ALL","NAMED","WEAPONS","ARMOR / SHIELDS","RINGS"]: filter.add_item(name)
	filter.item_selected.connect(func(_index: int): page=0; refresh())
	bar.add_child(filter)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation",18)
	layout.add_child(columns)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(rows)
	var inspect := VBoxContainer.new()
	inspect.custom_minimum_size.x = 400
	inspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(inspect)
	heading = shop._label("",21)
	inspect.add_child(heading)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(400,190)
	container.stretch = true
	inspect.add_child(container)
	preview = SubViewport.new()
	preview.size = Vector2i(400,190)
	preview.own_world_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(preview)
	stage = Node3D.new()
	preview.add_child(stage)
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	description = shop._label("",15)
	inspect.add_child(description)
	details = shop._label("",14)
	inspect.add_child(details)
	paging = shop._label("",14)
	layout.add_child(paging)
	hide()

func cycle_filter() -> void:
	filter.select((filter.selected+1)%filter.item_count)
	page = 0
	refresh()

func refresh() -> void:
	var had_focus := get_viewport().gui_get_focus_owner() in buttons
	if _ordered.is_empty():
		for entry: Dictionary in Database.all(): _ordered.append(StringName(entry.id))
		_ordered.sort_custom(func(a: StringName,b: StringName):
			var first := Database.get_item(a)
			var second := Database.get_item(b)
			if (first.kind=="named")!=(second.kind=="named"): return first.kind=="named"
			return String(first.name).naturalnocasecmp_to(second.name)<0)
	ids.clear()
	var search := query.text.strip_edges().to_lower()
	for id: StringName in _ordered:
		var entry := Database.get_item(id)
		if not search.is_empty() and not (String(entry.name)+" "+String(entry.family)).to_lower().contains(search): continue
		if filter.selected==1 and entry.kind!="named": continue
		if filter.selected==2 and entry.category!="weapons": continue
		if filter.selected==3 and entry.category!="cosmetics": continue
		if filter.selected==4 and entry.kind!="ring": continue
		ids.append(StringName(entry.id))
	page = clampi(page,0,maxi(0,ceili(ids.size()/float(PAGE_SIZE))-1))
	buttons.clear()
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	for index in range(page*PAGE_SIZE,mini((page+1)*PAGE_SIZE,ids.size())):
		var id: StringName = ids[index]
		var entry := Database.get_item(id)
		var price: int = int(shop.offer(id).get("price",-1))
		var price_text := "FREE" if price==0 else str(price)+" COINS / UNAVAILABLE"
		var button := add_button(String(entry.name)+"\n"+price_text+"  |  "+String(entry.family).replace("_"," ")+"  |  Owned "+str(shop.session.actor.inventory.count_type(id)),func(): shop.buy(id))
		button.disabled = price!=0
		button.focus_entered.connect(show_item.bind(id))
		button.mouse_entered.connect(show_item.bind(id))
	add_button("< PREVIOUS PAGE",func(): change_page(-1)).disabled = page==0
	add_button("NEXT PAGE >",func(): change_page(1)).disabled = (page+1)*PAGE_SIZE>=ids.size()
	add_button("BACK TO TOWER EXCHANGE",shop.close_browser)
	paging.text = "%d items  |  Page %d / %d  |  Left / Right: pages  |  RB: filter" % [ids.size(),page+1,maxi(1,ceili(ids.size()/float(PAGE_SIZE)))]
	if selected not in ids: selected=ids[page*PAGE_SIZE] if not ids.is_empty() else &""
	show_item(selected)
	if had_focus and not buttons.is_empty():
		var index := ids.find(selected)-page*PAGE_SIZE
		buttons[clampi(index,0,mini(PAGE_SIZE-1,buttons.size()-1))].grab_focus()

func add_button(title: String,action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size",14)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var normal: StyleBoxFlat = shop._style()
	var focus: StyleBoxFlat = shop._style(true)
	normal.set_content_margin_all(6)
	focus.set_content_margin_all(6)
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("focus",focus)
	button.pressed.connect(action)
	rows.add_child(button)
	buttons.append(button)
	return button

func change_page(direction: int) -> void:
	page += direction
	selected = &""
	refresh()
	if not buttons.is_empty(): buttons[0].grab_focus()

func show_item(id: StringName) -> void:
	var reuse := selected==id and is_instance_valid(model)
	var entry := Database.get_item(id)
	if entry.is_empty():
		heading.text = "No matching items"
		description.text = "Try another name or family."
		details.text = ""
		if is_instance_valid(model): model.hide()
		preview.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	selected = id
	heading.text = entry.name
	description.text = entry.description
	details.text = "%s / %s\n%s\nCatalog value: %d Glyph Coins. Currently free.\n%s" % [entry.rarity,entry.family,entry.acquisition,entry.value,"Unique grounded / aerial combo sequences." if entry.kind=="named" else ("No active ring effects." if entry.kind=="ring" else "Cosmetic appearance." if entry.category=="cosmetics" else "Shared family moveset.")]
	if reuse:
		model.show()
		preview.render_target_update_mode = SubViewport.UPDATE_ONCE
		return
	if is_instance_valid(model):
		stage.remove_child(model)
		model.queue_free()
	model = Geometry.model(entry.geometry)
	stage.add_child(model)
	model.rotation.y = .5
	var length := float(entry.geometry.length)
	var center := Vector3(0,length*.28,0) if entry.category=="weapons" else Vector3(0,.1,0)
	camera.position = center+Vector3(0,0,maxf(1.3,length*1.6))
	camera.look_at(center)
	preview.render_target_update_mode = SubViewport.UPDATE_ONCE
