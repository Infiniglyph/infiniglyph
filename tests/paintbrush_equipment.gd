extends SceneTree
const Catalog = preload("res://scripts/item_catalog.gd")
const Database = preload("res://scripts/equipment_database.gd")
const COLORS := ["cyan","violet","gold","mint","pink","blue","silver","ember"]
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func frames(count: int = 2) -> void:
	for i in range(count):
		await physics_frame
		await process_frame
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	world.inventory_persistence_enabled = false
	world.wider_world_enabled = false
	world.district_life_enabled = false
	world.world_memory_enabled = false
	world.boss_encounters_enabled = false
	root.add_child(world)
	var p: CharacterBody3D = world.player
	p.visual.retrieval.enabled = false
	var session: Node = world.inventory_session
	var shop: CanvasLayer = session.shop
	await frames(10)
	p.position = shop.anchor()+Vector3(0,.1,3.2)
	p.velocity = Vector3.ZERO
	await frames(10)
	p.set_physics_process(false)
	check(shop.can_use(p),"The real Tower Exchange is reachable for brush purchases")
	var ids: Array[String] = []
	for color: String in COLORS:
		var id := StringName("paintbrush_"+color)
		check(world.loot.request_shop_purchase(p.inventory,shop.SHOP_ID,id) and p.inventory.count_type(id)==1,"Host purchase grants one brush edition: "+color)
		for item: Resource in p.inventory.items.values():
			if item.item_type_id==id: ids.append(item.instance_id)
	world.loot.host_enabled = false
	check(not world.loot.request_shop_purchase(p.inventory,shop.SHOP_ID,&"paintbrush_cyan") and p.inventory.count_type(&"paintbrush_cyan")==1,"Brush purchases preserve host authority")
	world.loot.host_enabled = true
	var browser: PanelContainer = shop.browser
	browser.set_category("weapons")
	browser.filter.select(9)
	browser.refresh()
	check(browser.ids.size()==8 and browser.ids.all(func(id: StringName): return Database.get_item(id).family=="paintbrush"),"Paintbrushes have their own complete eight-color catalog filter")
	for i in range(COLORS.size()):
		var id := StringName("paintbrush_"+COLORS[i])
		check(world.loot.request_equip(p.inventory,&"down",ids[i]),"Brush uses normal equipment slots: "+COLORS[i])
		browser.show_item(id)
		await frames(2)
		check(browser.model.find_child("Paintbrush",true,false)!=null and browser.model.find_child("OpenGrimoire",true,false)==null and browser.details.text.contains("squares; Y/R: triangles"),"Archive previews the actual brush/empty offhand and explains its arts: "+COLORS[i])
		session.ui.selected_iid = ids[i]
		session.ui._inspect()
		check(session.ui._meta_label.text.contains("PAINTBRUSH") and session.ui._arts.text.contains("Hold to paint / 30 damage / 3.0 s trail") and not session.ui._arts.text.contains("Hold to write"),"Inventory shows brush type and persistent paint arts: "+COLORS[i])
	check(session.save_checkpoint("user://tests/paintbrush.json",true),"Equipped brush and all colors save through the normal checkpoint")
	check(world.loot.request_unequip(p.inventory,&"down") and p.inventory.equipped_item(&"down")==null,"The brush unequips through normal authority before checkpoint restoration")
	check(session.load_checkpoint("user://tests/paintbrush.json") and p.inventory.equipped_item(&"down").item_type_id==&"paintbrush_ember" and COLORS.all(func(color: String): return p.inventory.count_type(StringName("paintbrush_"+color))==1),"Checkpoint reload restores all ownership and the exact equipped brush color")
	check(not paused,"Shop, previews and inventory never pause world simulation")
	world.queue_free()
	await process_frame
	print("PAINTBRUSH EQUIPMENT: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
