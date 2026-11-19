extends SceneTree
## Bounded native service pages, input ownership and a continuously live world.
const Menu = preload("res://scripts/civilian_menu.gd")
class LiveClock extends Node:
	var frames := 0
	func _process(_delta: float) -> void: frames += 1
var menu: CanvasLayer
var calls: Array[int] = []
var opened_count := 0
var closed_count := 0
var back_count := 0
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ",label)
	else:
		failures += 1
		push_error("FAIL: "+label)

func frames(count: int = 2) -> void:
	for index in range(count):
		await physics_frame
		await process_frame

func picked(index: int) -> void: calls.append(index)

func parent_page() -> void:
	back_count += 1
	menu.show_page("RECEPTION","Choose a service.",[{"text":"Rent a room","call":picked.bind(900)}])

func key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event)

func pad(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	root.push_input(event)

func run() -> void:
	create_timer(30).timeout.connect(func(): push_error("Civilian menu test timed out"); quit(1))
	root.size = Vector2i(1280,720)
	var clock := LiveClock.new()
	root.add_child(clock)
	menu = Menu.new()
	root.add_child(menu)
	menu.opened.connect(func(): opened_count += 1)
	menu.closed.connect(func(): closed_count += 1)
	var choices: Array = []
	for index in range(68): choices.append({"text":"Owned item %02d" % index,"call":picked.bind(index),"enabled":index!=1})
	menu.show_page("GUILD STORAGE","Stored items remain owned by this room.\n".repeat(25),choices,parent_page)
	await frames()
	check(menu.is_open and opened_count==1 and not paused,"Opening service pages signals once and leaves the world running")
	check(menu._rows.size()==8 and menu._rows.filter(func(row: Button): return row.visible).size()==8,"Sixty-eight choices use only eight reusable choice buttons")
	check(menu._rows[1].disabled,"Unavailable actions remain visibly disabled")
	key(KEY_ENTER)
	await frames()
	check(calls==[0],"One native Enter press invokes the selected action exactly once")
	key(KEY_ENTER,true)
	check(calls==[0],"Keyboard echo cannot repeat a service transaction")
	pad(JOY_BUTTON_DPAD_DOWN)
	pad(JOY_BUTTON_A)
	check(calls==[0,2],"Controller navigation skips the disabled action before accepting")
	var stable: int = menu._rows[0].get_instance_id()
	for index in range(8): key(KEY_RIGHT)
	await frames()
	check(menu._page==8 and menu._rows.filter(func(row: Button): return row.visible).size()==4,"Page navigation reaches the final four choices without excess controls")
	check(menu._rows[0].get_instance_id()==stable,"Changing pages reuses controls without deferred focus deletion")
	pad(JOY_BUTTON_A)
	check(calls==[0,2,64],"The final page activates its actual choice rather than a stale earlier row")
	key(KEY_RIGHT)
	check(menu._page==8,"Page boundaries do not wrap or expose invalid choices")
	key(KEY_LEFT)
	check(menu._page==7,"Keyboard Left returns to the previous service page")
	key(KEY_ESCAPE)
	await frames()
	check(back_count==1 and menu.is_open and opened_count==1 and closed_count==0,"Back callbacks replace a page without duplicate open or close signals")
	pad(JOY_BUTTON_B)
	check(not menu.is_open and closed_count==1,"Back without a parent callback closes the service menu once")
	menu.show_page("TAVERN","Meal service remains available while the city moves.",[{"text":"Unavailable","call":picked.bind(901),"enabled":false}])
	menu._run_choice(0)
	check(calls==[0,2,64],"Disabled service actions cannot be invoked through the row callback")
	menu.set_status("Treasury is insufficient.",true)
	await frames()
	check(menu._status.text=="Treasury is insufficient." and menu._status.modulate.a>0,"Status feedback is visible without closing the menu")
	var saved := clock.frames
	await frames(5)
	check(clock.frames>saved and not paused,"World processing continues while a service page remains open")
	menu.show_page("EIGHT CHOICES","Long service information.\n".repeat(50),choices.slice(0,8))
	await frames()
	var viewport := root.get_visible_rect()
	check(viewport.encloses(menu._rows[-1].get_global_rect()) and viewport.encloses(menu._back.get_global_rect()) and viewport.encloses(menu._status.get_global_rect()),"Eight choices, navigation and status fit fully within 1280 by 720")
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_BACK
	event.pressed = true
	menu._input(event)
	check(menu.is_open,"Select/View is left to the existing inventory session")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://captures")
		root.get_texture().get_image().save_png("res://captures/civilian_menu.png")
	menu.close_menu()
	menu.close_menu()
	check(closed_count==2,"Repeated close requests remain idempotent")
	menu.queue_free()
	clock.queue_free()
	await frames()
	print("Civilian menu verification: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
