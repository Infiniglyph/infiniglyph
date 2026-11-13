extends Node3D
## Joint-mounted cosmetic shells. No collision, stat modifiers or process loop.
const Database = preload("res://scripts/equipment_database.gd")
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Garment = preload("res://scripts/equipment_garment.gd")
var visual: Node3D
var worn: Dictionary = {}
var pieces: Dictionary = {}

func sync(inventory: Node) -> void:
	for slot: StringName in [&"head",&"body",&"hands",&"legs",&"shield",&"ring1",&"ring2"]:
		var instance: Resource = inventory.equipped_item(slot)
		var id: StringName = instance.item_type_id if instance!=null else &""
		if worn.get(slot,&"")==id: continue
		for piece: Node3D in pieces.get(slot,[]):
			piece.get_parent().remove_child(piece)
			piece.queue_free()
		pieces[slot] = []
		worn[slot] = id
		var item := Database.get_item(id)
		if item.is_empty(): continue
		var g: Dictionary = item.geometry
		if g.has("tailoring"):
			var garment := Garment.new()
			add_child(garment)
			garment.configure(visual,item)
			pieces[slot].append(garment)
			continue
		match String(slot):
			"head": attach(slot,visual.chest,g,Vector3(0,.65,0))
			"body":
				attach(slot,visual.chest,g,Vector3(0,.08,0))
				# Articulated sleeves follow each upper/lower arm independently.
				for side: String in ["Left","Right"]:
					var sleeve := g.duplicate(true)
					sleeve.family = "hands"
					attach(slot,visual.joints[side+"Arm"],sleeve,Vector3.ZERO)
					if g.get("style")=="cloth":
						var panel := g.duplicate(true)
						panel.family = "coat_panel"
						attach(slot,visual.joints[side+"Leg"],panel,Vector3.ZERO)
			"hands":
				for side: String in ["Left","Right"]: attach(slot,visual.joints[side+"Arm"].get_node("Hinge"),g,Vector3(0,-.02,0))
			"legs":
				for side: String in ["Left","Right"]:
					attach(slot,visual.joints[side+"Leg"],g,Vector3.ZERO)
					attach(slot,visual.joints[side+"Leg"].get_node("Hinge"),g,Vector3.ZERO)
			"shield": attach(slot,visual.joints.LeftArm.get_node("Hinge"),g,Vector3(0,-.2,.1))
			"ring1","ring2": attach(slot,visual.joints[("Left" if slot==&"ring1" else "Right")+"Arm"].get_node("Hinge"),g,Vector3(0,-.28,0))
	# A helmet occupies the hood space while the existing robe keeps its collar,
	# fitted torso and animated inscriptions. Removing it restores the hood.
	if is_instance_valid(visual.robe):
		var hood: Node3D = visual.robe.get_node_or_null("OpenScholarHood")
		if hood!=null: hood.visible = inventory.equipped_item(&"head")==null

func attach(slot: StringName,parent: Node3D,g: Dictionary,at: Vector3) -> void:
	var model := Geometry.model(g)
	parent.add_child(model)
	model.position = at
	pieces[slot].append(model)

func _exit_tree() -> void:
	for list: Array in pieces.values():
		for piece: Node3D in list:
			if is_instance_valid(piece): piece.queue_free()
