extends SceneTree
const Catalog=preload('res://scripts/item_catalog.gd')
const Entry=preload('res://scripts/equipment_entry.gd')
const Preview=preload('res://scripts/equipment_preview.gd')
const Browser=preload('res://scripts/equipment_browser.gd')
const Tower=preload('res://scripts/tower_shop.gd')
const Inventory=preload('res://scripts/inventory.gd')
class Actor extends Node3D:
	var inventory: Node
class Session extends Node:
	var actor: Node3D
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred('run')
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print('PASS: ',label)
	else: failures+=1; push_error('FAIL: '+label)
func frames(count: int=3) -> void:
	for i in range(count): await process_frame
func run() -> void:
	root.size=Vector2i(1280,900)
	var actor:=Actor.new(); root.add_child(actor)
	actor.inventory=Inventory.new(); actor.inventory.owner_id='visitor'; actor.add_child(actor.inventory)
	var session:=Session.new(); session.actor=actor; root.add_child(session)
	var shop:=Tower.new(); shop.session=session
	var browser:=Browser.new(); browser.shop=shop; root.add_child(browser)
	browser.show()
	for group: String in Catalog.CIVIC_GROUPS:
		browser.set_category(group); browser.refresh()
		var valid:=not browser.ids.is_empty()
		for id: StringName in browser.ids: valid=valid and Catalog.get_definition(id).custom_properties.catalog_group==group
		check(valid and browser.buttons.size()<=9,group+' is browsable using bounded rows and shared item models')
	browser.set_category('commercial_furniture'); browser.refresh()
	browser.query.text='meeting'; browser.refresh()
	check(browser.ids==[&'guild_meeting_table'],'Search and category intersection locate a unique owned-catalogue object')
	browser.set_category('residential_furniture'); browser.refresh()
	browser.show_item(&'basic_bed')
	check(browser.model.get_class()=='Node3D' and browser.model.name=='CivicItemModel','The Tower uses a native item preview rather than an equipped mannequin')
	if '--capture' in OS.get_cmdline_user_args() and DisplayServer.get_name()!='headless':
		await frames(5); await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute('res://captures')
		root.get_texture().get_image().save_png('res://captures/civilization_tower_furniture.png')
	browser.queue_free(); await frames()
	if '--capture' in OS.get_cmdline_user_args() and DisplayServer.get_name()!='headless': await gallery()
	shop.free(); actor.free(); session.free()
	print('Civilization catalogue UI: %d checks, %d failures' % [checks,failures])
	quit(0 if failures==0 else 1)
func gallery() -> void:
	var ids: Array[StringName]=Catalog.civilization_ids()
	for page in range(7):
		var canvas:=ColorRect.new(); canvas.color=Color('030b12'); canvas.size=Vector2(1280,900); root.add_child(canvas)
		var heading:=Label.new(); heading.text='INFINIGLYPH / CIVILIZATION CATALOGUE / '+str(page+1)+' of7'; heading.position=Vector2(25,12); heading.add_theme_font_size_override('font_size',24); canvas.add_child(heading)
		for index in range(page*12,mini((page+1)*12,ids.size())):
			var slot:=index%12
			var entry:=Entry.for_id(ids[index])
			var box:=VBoxContainer.new(); box.position=Vector2(15+(slot%4)*316,55+(slot/4)*207); box.size=Vector2(306,195); canvas.add_child(box)
			var container:=SubViewportContainer.new(); container.stretch=true; container.custom_minimum_size=Vector2(306,168); box.add_child(container)
			var vp:=SubViewport.new(); vp.size=Vector2i(306,168); vp.own_world_3d=true; vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS; container.add_child(vp)
			var stage:=Node3D.new(); vp.add_child(stage)
			var model:=Preview.model(entry); stage.add_child(model)
			var size: Array=entry.geometry.size
			var center:=Vector3(0,float(size[1])*.5,0)
			var camera:=Camera3D.new(); stage.add_child(camera); camera.fov=48
			camera.position=center+Vector3(.7,.45,1.1).normalized()*maxf(1.3,float(entry.geometry.length)*2.0)
			camera.look_at(center); camera.current=true
			var label:=Label.new(); label.text=entry.name; label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; label.add_theme_font_size_override('font_size',17); box.add_child(label)
		await frames(8); await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png('res://captures/civilization_catalogue_'+str(page+1)+'.png')
		canvas.queue_free(); await frames()
