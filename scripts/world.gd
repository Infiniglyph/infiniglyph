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
const TerritorialBoss = preload("res://scripts/territorial_boss.gd")
const TerritorialEncounter = preload("res://scripts/territorial_encounter.gd")
const WorldRegions = preload("res://scripts/world_regions.gd")
const WorldActions = preload("res://scripts/world_actions.gd")
const DistrictLife = preload("res://scripts/district_life.gd")
const TheftReactions = preload("res://scripts/theft_reactions.gd")
var theft_reactions: Node3D
var world_actions: Node3D
var district_life: Node3D
@export var district_life_enabled := true
var wider_world: Node3D
var greefer: CharacterBody3D
var boss_encounter: CanvasLayer
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
@export var boss_encounters_enabled := true
@export var wider_world_enabled := true
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
	combat_hud.weapons = player.weapon_combat
	hud.add_child(combat_hud)
	start_menu = StartMenu.new()
	start_menu.actor = player
	start_menu.session = inventory_session
	add_child(start_menu)
	if world_memory_enabled:
		world_memory = WorldMemory.new()
		world_memory.population = population
		world_memory.player = player
		world_memory.retrieval = player.visual.retrieval
		add_child(world_memory)
	if boss_encounters_enabled:
		boss_encounter = TerritorialEncounter.new()
		boss_encounter.player = player
		boss_encounter.persistence_enabled = inventory_persistence_enabled
		greefer = TerritorialBoss.new()
		greefer.encounter = boss_encounter
		boss_encounter.boss = greefer
		add_child(greefer)
		player.boss_encounter = boss_encounter
		inventory_session.boss_encounter = boss_encounter
		add_child(boss_encounter)
	if wider_world_enabled:
		wider_world = WorldRegions.new()
		wider_world.encounter = boss_encounter
		add_child(wider_world)
		camera_rig.camera.far = 1800 # Keep the larger skyline/hills visible from Sky Jump height.
	world_actions = WorldActions.new()
	world_actions.actor = player
	world_actions.session = inventory_session
	add_child(world_actions)
	if district_life_enabled and is_instance_valid(wider_world) and not inventory_session.networked():
		district_life = DistrictLife.new()
		district_life.actor = player
		district_life.regions = wider_world
		district_life.session = inventory_session
		add_child(district_life)
		world_actions.life = district_life
		theft_reactions = TheftReactions.new()
		theft_reactions.actor = player
		theft_reactions.life = district_life
		theft_reactions.population = population
		add_child(theft_reactions)
