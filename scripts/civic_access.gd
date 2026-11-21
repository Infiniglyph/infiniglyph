extends Node3D
## The first Greefer confrontation grants a bound pass. The existing world
## remains authoritative; its exterior views and exits require that credential.
var world: Node3D
var unlocked:=false
var boundary: StaticBody3D
var _initialized:=false
var _visibility: Dictionary={}
func _ready() -> void:
	name="CivicAccess"
	boundary=StaticBody3D.new(); boundary.name="StarterDistrictClearance"; add_child(boundary)
	for axis in range(2):
		for side: int in [-1,1]:
			var wall:=CollisionShape3D.new(); var shape:=BoxShape3D.new()
			shape.size=Vector3(258,1500,1) if axis==0 else Vector3(1,1500,258)
			wall.shape=shape; wall.position=Vector3(0,749,side*128) if axis==0 else Vector3(side*128,749,0); boundary.add_child(wall)
	world.player.inventory.changed.connect(refresh)
	if is_instance_valid(world.boss_encounter): world.boss_encounter.progression_changed.connect(refresh)
	refresh()
func refresh() -> void:
	var allowed: bool=not is_instance_valid(world.boss_encounter) or world.boss_encounter.can_progress()
	if _initialized and allowed==unlocked: return
	_initialized=true; unlocked=allowed
	set_physics_process(not unlocked)
	var panes:=world.find_child("WindowLights",true,false)
	if panes!=null: panes.set_civic_access(unlocked)
	for shape: CollisionShape3D in boundary.get_children(): shape.set_deferred("disabled",unlocked)
	if is_instance_valid(world.wider_world):
		for child: Node in world.wider_world.get_children():
			if child is Node3D and child not in world.wider_world.gates:
				if not _visibility.has(child): _visibility[child]=child.visible
				child.visible=bool(_visibility[child]) if unlocked else false
	for layer: Node in [world.get("district_life"),world.get("building_civilization")]:
		if layer is Node3D:
			if not _visibility.has(layer): _visibility[layer]=layer.visible
			layer.visible=bool(_visibility[layer]) if unlocked else false

func _physics_process(_delta: float) -> void:
	if unlocked or world.inventory_session.get("_loading")==true or world.player.get_world_3d()!=world.get_world_3d(): return
	var at: Vector3=world.player.global_position
	if maxf(absf(at.x),absf(at.z))<=128: return
	# Covers flight/vehicle bypasses and old checkpoints outside a locked city.
	world.player.global_position=Vector3(0,.05,10); world.player.velocity=Vector3.ZERO
	world.player.fall_damage.reset(); world.camera_rig.reset_follow()
	world.inventory_session.show_notice("Complete Greefer's first confrontation to receive your Civic Pass and enter the outer city.",8)
