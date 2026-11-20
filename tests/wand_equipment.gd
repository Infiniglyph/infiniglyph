extends "res://tests/equation_tracing.gd"
## Real equipment and controller/keyboard routing through WeaponCombat.
const Database = preload("res://scripts/equipment_database.gd")
const Library = preload("res://scripts/weapon_library.gd")
const Filter = preload("res://scripts/equipment_filters.gd")
const ItemType = preload("res://scripts/inventory_item_type.gd")
const Tower = preload("res://scripts/tower_shop.gd")
const WandEffect = preload("res://scripts/wand_effect.gd")
const COLORS := ["cyan","violet","gold","mint","pink","blue","silver","ember"]
var launched: Array[Dictionary] = []
var exchange: CanvasLayer

func equip_wand(color: String) -> void:
	w.cancel()
	controls.reset_combat_input()
	var id := StringName("dark_box_arc_wand" if color=="cyan" else "arc_wand_"+color)
	var item: Resource = Catalog.create(id)
	p.inventory.add_item(item)
	p.inventory.assign(&"up",item.instance_id)
	p.combat.selected_slot=&"up"
	p.combat.sheathed=false
	w.sync_rig()

func run() -> void:
	create_timer(75).timeout.connect(func(): push_error("WAND EQUIPMENT WATCHDOG");quit(2))
	scene=Node3D.new()
	root.add_child(scene)
	view=Camera3D.new()
	scene.add_child(view)
	var floor_body:=StaticBody3D.new()
	var collider:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(60,1,60)
	collider.shape=box
	floor_body.add_child(collider)
	floor_body.position.y=-.5
	scene.add_child(floor_body)
	p=make_player(Vector3(0,.02,0))
	controls=p.controls
	w=p.weapon_combat
	exchange=Tower.new()
	p.camera_rig.yaw=PI
	scene.child_entered_tree.connect(func(node: Node):
		if node is WandEffect: launched.append({"attack":node.attack,"color":node.color,"origin":node._origin,"serial":node.move.attack_serial}))
	await frames(8)
	p.set_physics_process(false)
	var wand_count:=0
	for entry: Dictionary in Database.all():
		if entry.family=="wand": wand_count+=1
	check(wand_count==8,"Exactly eight Wand editions share the selectable weapon class")
	for color: String in COLORS:
		equip_wand(color)
		var id:=StringName("dark_box_arc_wand" if color=="cyan" else "arc_wand_"+color)
		var entry: Dictionary=Database.get_item(id)
		var definition: Resource=Catalog.get_definition(id)
		check(Database.valid(entry) and ItemType.label(definition)=="Wand" and Filter.matches(definition,Filter.WEAPON_NAMES.find("WANDS")) and not exchange.offer(id).is_empty(),"Wand edition appears in inventory and Tower WANDS filter: "+color)
		pad(JOY_BUTTON_RIGHT_SHOULDER)
		pad(JOY_BUTTON_RIGHT_SHOULDER,false)
		await frames(ceili(hz*.16),true)
		check(not launched.is_empty() and launched[-1].color.is_equal_approx(Color(entry.geometry.tint)),"Physical wand emits matching laser pigment: "+color)
		await frames(ceili(hz*.24),true)
	var saved: Dictionary=p.inventory.serialize()
	check(p.inventory.restore(saved) and p.inventory.equipped_item(&"up").item_type_id==&"arc_wand_ember","Inventory round trip preserves equipped wand and exact color")
	w.sync_rig()
	check(w.rig.models[&"arc_wand_ember"].right.get_parent()==w.rig.left_hand,"Wand and emitter use anatomical right hand, leaving offhand free")
	# Real press/release contract: RT selects arts; it never steals A or B.
	var actions: Array[StringName]=[&"attack_left",&"attack_right",&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"]
	for index in range(actions.size()):
		w.cancel()
		p.combat.cancel_charge()
		var count:=launched.size()
		if index<2:
			pad(JOY_BUTTON_LEFT_SHOULDER if index==0 else JOY_BUTTON_RIGHT_SHOULDER)
			pad(JOY_BUTTON_LEFT_SHOULDER if index==0 else JOY_BUTTON_RIGHT_SHOULDER,false)
		else:
			if index>=4: rt(1)
			var button: JoyButton=JOY_BUTTON_X if index%2==0 else JOY_BUTTON_Y
			pad(button)
			await frames(ceili(hz*.5),true)
			check(launched.size()==count and p.combat.trace_action==&"","Holding wand art prepares one responsive cast without generating traces")
			pad(button,false)
			if index>=4: rt(0)
		check(w.active_move.get("wand_attack","")==["flick","flick","slither","volley","ground","wheel"][index],"Controller selects correct wand attack: "+String(actions[index]))
		await frames(ceili(hz*.7),true)
		check(launched.size()==count+1 and w.active_move.is_empty(),"One release launches one complete cast without charged duplicate pulses")
	var before:=launched.size()
	key(KEY_Q)
	key(KEY_Q,false)
	await frames(ceili(hz*.7),true)
	check(launched.size()==before+1 and launched[-1].attack=="slither","Existing keyboard Q casts the same Slither Shot")
	w.cancel()
	pad(JOY_BUTTON_RIGHT_SHOULDER)
	pad(JOY_BUTTON_RIGHT_SHOULDER,false)
	p.dodge.start(Vector3.RIGHT)
	w.cancel()
	before=launched.size()
	await frames(ceili(hz*.2),true)
	check(launched.size()==before and w.active_move.is_empty(),"Dodge cancellation before release produces no late invisible hit")
	p.dodge.cancel()
	p.inventory.assign(&"up",&"")
	p.combat.selected_slot=&"down"
	w.sync_rig()
	check(w.loadout(&"down").id==&"sword_shield" and not Library.move(&"down",&"attack_right").has("wand_attack"),"Switching back restores the original sword class")
	for effect in get_nodes_in_group("wand_effects"): effect.expire()
	exchange.free()
	scene.queue_free()
	await frames(2)
	print("Wand equipment: ",checks-failures,"/",checks," at ",hz,"Hz")
	quit(1 if failures else 0)
