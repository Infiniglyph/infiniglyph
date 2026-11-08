extends Node3D
const District = preload("res://scripts/district.gd")
const Player = preload("res://scripts/player.gd")
const Controls = preload("res://scripts/player_input.gd")
const CameraRig = preload("res://scripts/camera.gd")
const CombatHUD = preload("res://scripts/combat_hud.gd")
const PracticeTarget = preload("res://scripts/practice_target.gd")
const SparringPartner = preload("res://scripts/sparring_partner.gd")
const SparringDuel = preload("res://scripts/sparring_duel.gd")
const LootAuthority = preload("res://scripts/loot_authority.gd")
const InventorySession = preload("res://scripts/inventory_session.gd")
const StartMenu = preload("res://scripts/start_menu.gd")
const CityPopulation = preload("res://scripts/city_population.gd")
const WorldMemory = preload("res://scripts/world_memory.gd")
var sparring_partner: CharacterBody3D
var sparring_duel: CanvasLayer
var player: CharacterBody3D
var camera_rig: Node3D
var controls: Node
var loot: Node3D
var inventory_session: Node
var start_menu: CanvasLayer
var population: Node3D
var world_memory: Node3D
@export var world_memory_enabled := true
@export var neon_glow_enabled := true
@export var inventory_persistence_enabled := true
@export_range(0,1,0.01) var death_drop_probability := 0.15

func _ready() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.001,0.003,0.008)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color(0.12,0.25,0.3)
	settings.ambient_light_energy = 0.4
	environment.environment = settings
	add_child(environment)
	add_child(District.new())
	controls = Controls.new()
	add_child(controls)
	player = Player.new()
	player.inventory_owner_id = "local"
	player.controls = controls
	# Camera enters the tree after its target; player's physics starts next frame.
	camera_rig = CameraRig.new()
	player.camera_rig = camera_rig
	add_child(player)
	camera_rig.target = player
	camera_rig.controls = controls
	add_child(camera_rig)
	for index in range(3):
		var target := PracticeTarget.new()
		target.actor = player
		target.counterattacks = index == 1
		target.position = Vector3((index-1)*5,0,-35-(3 if index == 1 else 0))
		add_child(target)
	sparring_partner = SparringPartner.new()
	sparring_partner.opponent = player
	add_child(sparring_partner)
	sparring_duel = SparringDuel.new()
	sparring_duel.player = player
	sparring_duel.partner = sparring_partner
	add_child(sparring_duel)
	population = CityPopulation.new()
	population.player = player
	population.duel = sparring_duel
	add_child(population)
	loot = LootAuthority.new()
	loot.death_drop_probability = death_drop_probability
	add_child(loot)
	inventory_session = InventorySession.new()
	inventory_session.actor = player
	inventory_session.controls = controls
	inventory_session.duel = sparring_duel
	inventory_session.loot = loot
	inventory_session.population = population
	inventory_session.persistence_enabled = inventory_persistence_enabled
	add_child(inventory_session)
	if neon_glow_enabled:
		var glow := CanvasLayer.new()
		glow.name = "NeonGlow"
		glow.layer = 0
		var screen := ColorRect.new()
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = preload("res://scripts/neon_glow.gdshader")
		screen.material = material
		glow.add_child(screen)
		add_child(glow)
	var hud := CanvasLayer.new()
	add_child(hud)
	var combat_hud := CombatHUD.new()
	combat_hud.intent = player.combat
	combat_hud.weapons = player.weapon_combat
	hud.add_child(combat_hud)
	var title := Label.new()
	title.position = Vector2(30,24)
	title.text = "I N F I N I G L Y P H\nCENTRAL DISTRICT    /    PHASE 003"
	title.add_theme_color_override("font_color",Color(0.16,0.85,0.93))
	title.add_theme_font_size_override("font_size",20)
	title.add_theme_constant_override("outline_size",5)
	title.add_theme_color_override("font_outline_color",Color.BLACK)
	hud.add_child(title)
	var help := Label.new()
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(30,-130)
	help.text = "WASD move    SHIFT run    CTRL fast run    SPACE sky step    E dodge    TAB lock    G interact    B inventory    ESC menu\nCONTROLLER    Left stick move / run    L3 fast run    R3 lock    A jump    B dodge    RT talk / collect    VIEW inventory    START menu\nLMB/RMB left/right attack    F block / parry    Q/R specials    V + Q/R modified    Hold specials: charge, release: attack\nLB/RB left/right attack    LT block / parry    X/Y specials    RT + X/Y modified    Hold specials: charge, release: attack\nTap arrows / D-pad: draw weapon    Hold DOWN: sheathe / draw    I J K L: switch locked target"
	help.add_theme_color_override("font_color",Color(0.42,0.64,0.69))
	help.add_theme_constant_override("outline_size",3)
	help.add_theme_color_override("font_outline_color",Color.BLACK)
	hud.add_child(help)
	start_menu = StartMenu.new()
	start_menu.actor = player
	start_menu.session = inventory_session
	add_child(start_menu)
	if world_memory_enabled:
		world_memory = WorldMemory.new()
		world_memory.district = get_node("CentralDistrict")
		world_memory.population = population
		world_memory.player = player
		world_memory.retrieval = player.visual.retrieval
		add_child(world_memory)
