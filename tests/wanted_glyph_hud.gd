extends SceneTree
const Law=preload("res://scripts/civilian_law.gd")
const WantedHUD=preload("res://scripts/wanted_glyph_hud.gd")
var checks:=0
var failures:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if ok: print("PASS: ",label)
	else: failures+=1; push_error("FAIL: "+label)
func crime(id: String,offender: String="player",witnesses: Array=["witness"]) -> Dictionary:
	return {"event_id":id,"kind":"assault","offender":offender,"victim":"witness","witnesses":witnesses}
func shot(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://captures")
	root.get_texture().get_image().save_png("res://captures/wanted_"+label+".png")
func run() -> void:
	var law:=Law.new(); root.add_child(law)
	law.identity_provider=func(id: String): return {"kind":"player" if id=="player" else "code_form","active":true} if id in ["player","witness","other","guard"] else {}
	var canvas:=CanvasLayer.new(); root.add_child(canvas)
	var hud:=WantedHUD.new(); hud.law=law; canvas.add_child(hud)
	check(not hud.visible and hud.wanted_level==0,"A clear record shows no empty wanted glyphs")
	law.record_crime(crime("unseen","player",[]))
	check(not hud.visible,"Unwitnessed actions cannot light a wanted glyph")
	law.record_crime(crime("other","other"))
	check(not hud.visible,"Another Code Form's wanted status does not appear on the player's HUD")
	var cases: Array[Dictionary]=[]
	for i in range(6): cases.append(law.record_crime(crime("witnessed/"+str(i))))
	check(hud.wanted_level==5 and hud.glyph_alpha==PackedFloat32Array([1,1,1,1,1]),"Witnessed cases immediately light up to five triangle glyphs")
	for resolution: Vector2i in [Vector2i(800,600),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size=resolution
		await process_frame; await process_frame
		var rect: Rect2=hud.get_global_rect()
		var viewport: Rect2=root.get_visible_rect()
		check(viewport.encloses(rect) and is_equal_approx(rect.end.x,viewport.end.x-24) and rect.position.y==24,"Wanted glyphs stay in the top-right safe margin at "+str(resolution))
	await shot("five")
	law.investigate(cases[0].id,"guard"); law.resolve(cases[0].id,"guard")
	check(hud.wanted_level==5,"Resolving one excess case preserves the five-glyph cap while evidence remains")
	law.investigate(cases[1].id,"guard"); law.resolve(cases[1].id,"guard")
	hud.set_process(false); hud._process(WantedHUD.FADE_SECONDS*.5)
	check(hud.wanted_level==4 and hud.glyph_alpha[4]>0 and hud.glyph_alpha[4]<1 and hud.glyph_alpha[3]==1,"A lowered wanted level fades only the removed triangle")
	hud._process(WantedHUD.FADE_SECONDS)
	check(hud.glyph_alpha[4]==0 and hud.visible,"The removed triangle disappears while active glyphs remain")
	for i in range(2,6): law.investigate(cases[i].id,"guard"); law.resolve(cases[i].id,"guard")
	hud._process(WantedHUD.FADE_SECONDS)
	check(hud.wanted_level==0 and not hud.visible and not hud.is_processing(),"Cleared wanted status removes the whole display and stops animation processing")
	check(hud.mouse_filter==Control.MOUSE_FILTER_IGNORE,"The wanted display never captures gameplay input")
	var saved:=law.serialize(); saved.cases[cases[0].id].status="open"; saved.cases[cases[0].id].investigator=""; saved.cases[cases[0].id].resolved_at=0.0
	check(law.restore(saved) and hud.wanted_level==1 and hud.visible,"Restoring the existing law ledger refreshes the same HUD")
	await shot("one")
	canvas.free(); law.free()
	print("WANTED GLYPH HUD: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
