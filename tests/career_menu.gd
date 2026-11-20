extends SceneTree
const Career=preload('res://scripts/career_system.gd')
const CareerMenu=preload('res://scripts/career_menu.gd')
class Flag extends Node:
	var is_open:=false
class Session extends Node:
	var _loading:=false
	var _checkpoint_pending:=false
	var ui:=Flag.new()
	var shop:=Flag.new()
	var captured:=false
	func _init() -> void: add_child(ui); add_child(shop)
	func _opened() -> void: captured=true
	func _closed() -> void: captured=false
class Actor extends Node3D:
	var health:=1000.0
	var transition_locked:=false
class Civic extends Node:
	var close_enough:=true
	var active:=true
	func identity(id: String) -> Dictionary:
		if id=='native': return {'id':id,'name':'The Cook','kind':'code_form','active':active,'motivations':{'knowledge':.8,'security':.8}}
		return {'id':id,'kind':'player' if id=='player' else 'unique','active':true}
	func _recipient_near(_a: String,_b: String) -> bool: return close_enough
class Communication extends Flag:
	var speaker_id:='player'
	var listener_id:='native'
	func close_conversation(_reason: String) -> void: is_open=false
class WorldStub extends Node3D:
	var inventory_session: Node
	var civic_interactions: Node
	var careers: Node
	var player: Node3D
	var start_menu: Node
	var civilian_services: Node
	var glyphic_wonders: Node
	var building_civilization: Node
	var communication: Node
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred('run')
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print('PASS: ',label)
	else: failures+=1; push_error('FAIL: '+label)
func run() -> void:
	var world:=WorldStub.new(); root.add_child(world)
	world.inventory_session=Session.new(); world.add_child(world.inventory_session)
	world.player=Actor.new(); world.add_child(world.player)
	world.civic_interactions=Civic.new(); world.add_child(world.civic_interactions)
	world.start_menu=Flag.new(); world.add_child(world.start_menu)
	world.communication=Communication.new(); world.add_child(world.communication)
	world.careers=Career.new(); world.add_child(world.careers)
	world.careers.configure({'identity':world.civic_interactions.identity,'authorize':func(_o: String,_p: Dictionary): return true,'premises':func(_id: String,_place: String,_types: Array): return true})
	var job: String=world.careers.select_career('native','chef','kitchen')
	var business: String=world.careers.register_business('native','Electron Kitchen','kitchen','restaurant')
	check(not job.is_empty() and not business.is_empty(),'The career view reads actual native employment and business records')
	var before: Dictionary=world.careers.serialize()
	var panel:=CareerMenu.new(); panel.world=world; world.add_child(panel)
	check(not panel.open('player') and not panel.open('avat_ar'),'Player visitors and Avat Ar are excluded from native career inspection')
	check(panel.open('native') and panel.menu.is_open and world.inventory_session.captured and not paused,'Nearby native career dialogue captures inputs while the world stays live')
	check('Chef' in panel.menu._body.text and 'kitchen' in panel.menu._body.text,'Career summary displays the real primary occupation and workplace')
	panel._jobs(); check(panel.menu._choices.size()==1,'Employment history uses bounded CivilianMenu rows')
	panel._job(job); check('The Cook' in panel.menu._body.text and 'Chef' in panel.menu._body.text,'Employment inspection shows the actual employee and career definition')
	panel._businesses(); check(panel.menu._choices.size()==1,'Business inspection lists actual related registrations')
	panel._business(business); check('Electron Kitchen' in panel.menu._body.text and "The Cook's wallet" in panel.menu._body.text,'Business details preserve the recorded owner treasury and premises')
	panel._agreements(); check('self employed' in panel.menu._body.text.to_lower() and 'contract reward' in panel.menu._body.text,'Compensation inspection distinguishes recorded terms from completed payment')
	panel._sectors(); check(panel.menu._choices.size()==8,'The career catalogue provides a bounded sector menu')
	panel._definitions('hospitality'); check(not panel.menu._choices.is_empty() and panel.menu._active_buttons.size()<=11,'Career definitions paginate through the shared dialogue controls')
	panel._definition('chef','hospitality'); check('Food Preparation' in panel.menu._body.text,'Career profile reads the canonical capabilities instead of inventing privileges')
	panel._plans(); check('My main work is Chef' in panel.menu._body.text,'Native plans reflect the existing autonomous primary role')
	check(world.careers.serialize()==before,'Inspecting every career and hiring page cannot assign jobs, move coins, or alter authoritative records')
	if '--capture' in OS.get_cmdline_user_args() and DisplayServer.get_name()!='headless':
		panel._home()
		for i in range(5): await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute('res://captures')
		root.get_texture().get_image().save_png('res://captures/career_livelihood.png')
	panel.close_menu(); world.start_menu.is_open=true
	check(not panel.open('native'),'Start menu cannot be covered by a stale career request')
	world.start_menu.is_open=false; world.inventory_session._loading=true
	check(not panel.open('native'),'Partial checkpoint loading blocks career dialogue')
	world.inventory_session._loading=false; world.civic_interactions.close_enough=false
	check(not panel.open('native'),'Remote career inspection cannot bypass physical conversation distance')
	world.civic_interactions.close_enough=true; world.communication.is_open=true
	check(panel.open('native') and not world.communication.is_open,'The same native conversation hands over cleanly to career inspection')
	world.civic_interactions.active=false; panel._process(1)
	check(not panel.menu.is_open and not world.inventory_session.captured,'Retiring or losing the subject closes the career panel and releases local controls')
	world.free()
	print('Career menu: %d checks, %d failures' % [checks,failures])
	quit(0 if failures==0 else 1)
