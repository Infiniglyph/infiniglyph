extends Node3D
## B8 uses the pyramid's ownership/reset authority, not an outdoor challenge teleport.
const Boss = preload("res://scripts/lorai.gd")
const Dissolve = preload("res://scripts/monster_dissolve.gd")
const FIRST_CLEAR := [&"ahkmets_scepter",&"lorais_fangblade",&"pharaoh_vile_nemes",&"pharaoh_vile_mantle",&"pharaoh_vile_bracers",&"pharaoh_vile_greaves",&"serpent_crown_union",&"apep_lorai_catalyst",&"monster_glyph_rare"]
var manager: Node3D
var player: CharacterBody3D
var boss: CharacterBody3D
var hud: CanvasLayer
var title: Label
var caption: Label
var bar: ProgressBar
var shade: ColorRect
var finished:=false
var pending_rewards: Array=[]
var reward_origin:=Vector3.ZERO
var _retry:=0.0
var _framed:=false

func _ready() -> void:
	name="AhkmetEncounter"
	player=manager.player
	boss=Boss.new()
	boss.encounter=self
	boss.opponent=player
	manager.interior.floors[&"B8"].add_child(boss)
	var saved: Dictionary=manager.boss_state
	if not saved.is_empty():
		boss.weapon_combat.health=clampf(float(saved.hp),1,boss.base_health)
		boss.phase=int(saved.phase)
		boss.visual.pose({},0,boss.phase,0)
	hud=CanvasLayer.new()
	hud.layer=6
	# The instance's 2x2 SubViewport owns physics only. HUD belongs to the
	# actual rendering viewport, while this controller owns its lifecycle.
	manager.world.add_child(hud)
	shade=ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color=Color(0,0,0,0)
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_child(shade)
	var panel:=VBoxContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left=-310
	panel.offset_right=310
	panel.offset_top=-140
	panel.offset_bottom=-55
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_child(panel)
	title=Label.new()
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color",Color("ffcf69"))
	title.add_theme_color_override("font_outline_color",Color("040304"))
	title.add_theme_constant_override("outline_size",5)
	title.add_theme_font_size_override("font_size",20)
	panel.add_child(title)
	bar=ProgressBar.new()
	bar.max_value=boss.base_health
	bar.show_percentage=false
	bar.custom_minimum_size=Vector2(620,12)
	var fill:=StyleBoxFlat.new()
	fill.bg_color=Color("ffc943")
	var background:=StyleBoxFlat.new()
	background.bg_color=Color("211b16")
	bar.add_theme_stylebox_override("fill",fill)
	bar.add_theme_stylebox_override("background",background)
	panel.add_child(bar)
	caption=Label.new()
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color",Color("7cffff"))
	caption.add_theme_color_override("font_outline_color",Color("040304"))
	caption.add_theme_constant_override("outline_size",4)
	panel.add_child(caption)
	hud.hide()

func can_fight() -> bool: return manager.can_fight() and not finished
func same_floor(_actor: CharacterBody3D, target: CharacterBody3D) -> bool: return manager.interior.floor_at(target.global_position)==&"B8"

func union_started() -> void:
	manager.world.inventory_session._dirty()
func union_finished() -> void:
	manager.world.inventory_session._dirty()

func snapshot() -> Dictionary:
	if not is_instance_valid(boss) or boss.dead or finished: return {}
	# A checkpoint during the ceremony resumes in stable Phase 2 with the same
	# remaining HP. It never replays a swallow or grants a second health pool.
	return {"hp":boss.health,"phase":2 if boss.phase==0 else boss.phase}

func _process(delta: float) -> void:
	var present: bool=is_instance_valid(boss) and manager.active and manager.can_fight() and same_floor(boss,player)
	var show_boss: bool=present and boss.engaged and not finished
	hud.visible=show_boss
	if _framed!=show_boss:
		_framed=show_boss
		if player.camera_rig.has_method("set_encounter_scale"): player.camera_rig.set_encounter_scale(1.8 if _framed else 1.0)
	if show_boss:
		title.text=boss.combat_name()
		bar.value=boss.health
		var t: float=boss.union_time
		if boss.phase==0:
			caption.text="The Final Union" if t<1.5 else "A trust freely given" if t<4.6 else "Two wills. One form."
			shade.color.a=sin(clampf((t-4.3)/1.6,0,1)*PI)*.33
		else:
			shade.color.a=0
			caption.text=boss.weapon_combat.active_move.get("name","The Serpent Throne" if boss.phase==1 else "The Serpent Ascendant")
	if not present and is_instance_valid(boss): boss.weapon_combat.cancel()
	if finished and not pending_rewards.is_empty():
		_retry-=delta
		if _retry<=0:
			_retry=1
			complete_rewards()

func finish() -> void:
	if finished: return
	finished=true # Close the lethal callback before any reentrant impact.
	reward_origin=Vector3(boss.visual.head.global_position.x,boss.floor_y+.10,boss.visual.head.global_position.z)
	pending_rewards=FIRST_CLEAR.duplicate() if not player.inventory.boss_reward_claims.get("ahkmet_lorai",false) else [FIRST_CLEAR[randi()%7],&"apep_lorai_catalyst",&"monster_glyph_rare"]
	var dissolve:=Dissolve.new()
	dissolve.victim=boss
	add_child(dissolve)
	call_deferred("complete_rewards")

func complete_rewards() -> void:
	if pending_rewards.is_empty() or is_queued_for_deletion(): return
	var loot: Node=manager.world.inventory_session.loot
	var drops: Array=loot.spawn_reward_bundle(pending_rewards,reward_origin,manager.travel.pyramid_id)
	if drops.size()!=pending_rewards.size(): return # No claim/partial reward on failure.
	pending_rewards.clear()
	player.inventory.boss_reward_claims["ahkmet_lorai"]=true
	manager.defeated_ids["ahkmet_lorai"]=true
	manager.boss_state={}
	player.inventory.changed.emit()
	manager.world.inventory_session.show_notice("Ahkmet & Lorai defeated — their union leaves its keepsakes.",6)
	manager.world.inventory_session._dirty()

func retire() -> void:
	if _framed and is_instance_valid(player) and player.camera_rig.has_method("set_encounter_scale"): player.camera_rig.set_encounter_scale(1)
	_framed=false
	if is_instance_valid(hud):
		hud.hide()
		hud.queue_free()
	if is_instance_valid(boss):
		boss.dead=true
		boss.weapon_combat.cancel()
		boss.remove_from_group("combat_targets")
		boss.set_deferred("collision_layer",0)
		boss.set_physics_process(false)
		boss.weapon_combat.set_physics_process(false)
		boss.hide()
		boss.queue_free()
	hide()
	queue_free()

func _exit_tree() -> void:
	if is_instance_valid(hud) and not hud.is_queued_for_deletion(): hud.queue_free()
	if _framed and is_instance_valid(player) and is_instance_valid(player.camera_rig) and player.camera_rig.has_method("set_encounter_scale"): player.camera_rig.set_encounter_scale(1)
