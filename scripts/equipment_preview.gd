extends RefCounted
## The store uses the same garment renderer and joint anchors as gameplay.
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Garment = preload("res://scripts/equipment_garment.gd")
const Visual = preload("res://scripts/character_visual.gd")
const Scribe = preload("res://scripts/eternal_scribe_robe.gd")
const Lines = preload("res://scripts/robe_lines.gd")
const Hat = preload("res://scripts/eturnull_hat.gd")
const Rig = preload("res://scripts/weapon_rig.gd")
const ScribeMoves = preload("res://scripts/scribe_moves.gd")
const KyrenCosmetic = preload("res://scripts/kyren_cosmetic.gd")
const FalconRegalia = preload("res://scripts/falcon_regalia.gd")
const TempleRegalia = preload("res://scripts/pyramid_regalia.gd")
const RoyalRegalia = preload("res://scripts/ahkmet_regalia.gd")

static func model(entry: Dictionary) -> Node3D:
	if entry.id in ["respawn_glyph","home_respawn_glyph"]:
		var root:=Node3D.new()
		var home: bool=entry.id=="home_respawn_glyph"
		var ink:=Color("ffd16a") if home else Color("85ffc8")
		var circle:=PackedVector3Array()
		for i in range(33): circle.append(Vector3(cos(i*TAU/32)*.38,sin(i*TAU/32)*.38,0))
		root.add_child(Lines.polyline(circle,ink))
		var motif:=PackedVector3Array([Vector3(-.2,0,0),Vector3(0,.25,0),Vector3(.2,0,0),Vector3(0,-.25,0)])
		if home: motif=PackedVector3Array([Vector3(-.2,-.18,0),Vector3(-.2,.08,0),Vector3(0,.28,0),Vector3(.2,.08,0),Vector3(.2,-.18,0)])
		root.add_child(Lines.polyline(motif,ink,true))
		return root
	if String(entry.id).begins_with("shield_glyph_"):
		var glyph:=Node3D.new()
		var ink:=Color("598dff")
		for i in range({"shield_glyph_light":1,"shield_glyph_medium":2,"shield_glyph_heavy":3}[String(entry.id)]):
			var r: float=.25-i*.045
			glyph.add_child(Lines.polyline(PackedVector3Array([Vector3(-r,r*.7,0),Vector3(r,r*.7,0),Vector3(r*.8,-r*.35,0),Vector3(0,-r,0),Vector3(-r*.8,-r*.35,0)]),ink,true))
		return glyph
	if entry.id=="health_glyph":
		var glyph := Node3D.new()
		var ink := Color("66ffb8")
		glyph.add_child(Lines.box(Vector3(.25,.25,.25),ink))
		glyph.add_child(Lines.polyline(PackedVector3Array([Vector3(-.18,0,.14),Vector3(0,.24,.14),Vector3(.18,0,.14),Vector3(0,-.24,.14)]),ink,true))
		glyph.add_child(Lines.segments(PackedVector3Array([Vector3(-.07,0,.15),Vector3(.07,0,.15),Vector3(0,-.07,.15),Vector3(0,.07,.15)]),ink))
		return glyph
	if not entry.geometry.has("tailoring") and not entry.geometry.has("renderer") and entry.id!="eternal_scribe_robes": return Geometry.model(entry.geometry)
	var actor := CharacterBody3D.new()
	var figure := Visual.new()
	figure.live_retrieval = false
	actor.add_child(figure)
	# _ready builds the mannequin after the model enters the preview viewport.
	actor.tree_entered.connect(func(): figure.ready.connect(func():
		if entry.family=="scribe":
			var rig := Rig.new()
			rig.visual = figure
			figure.add_child(rig)
			rig.equip_item(StringName(entry.id),false)
			ScribeMoves.preview_ready(figure,rig)
		elif entry.family=="paintbrush":
			var rig := Rig.new()
			rig.visual = figure
			figure.add_child(rig)
			rig.equip_item(StringName(entry.id),false)
			preload("res://scripts/paintbrush_moves.gd").ready_pose(figure,rig)
		elif String(entry.geometry.get("renderer","")).begins_with("ahkmet_") or entry.geometry.get("renderer")=="union_crown":
			var copy:=RoyalRegalia.new()
			copy.configure(figure,entry.geometry.renderer)
		elif String(entry.geometry.get("renderer","")).begins_with("temple_"):
			var copy:=TempleRegalia.new()
			copy.configure(figure,entry.geometry.renderer)
		elif String(entry.geometry.get("renderer","")).begins_with("falcon_"):
			var copy:=FalconRegalia.new()
			copy.configure(figure,entry.geometry.renderer)
		elif entry.geometry.get("renderer") in ["kyren_hat","kyren_scarf"]:
			var copy := KyrenCosmetic.new()
			copy.configure(figure,entry.geometry.renderer)
		elif entry.geometry.get("renderer")=="eturnull_hat":
			var hat := Hat.new()
			hat.configure(figure)
		elif entry.id=="eternal_scribe_robes":
			var robe := Scribe.new()
			figure.chest.add_child(robe)
			robe.position.y = -figure.REST_HIP_HEIGHT
			robe.rotation.y = PI
			robe.configure(actor,figure,figure.chest,figure.joints.LeftArm,figure.joints.RightArm)
			robe.set_equipped(true)
			robe.set_process(false)
		else:
			var garment := Garment.new()
			figure.add_child(garment)
			garment.configure(figure,entry)
			garment._process(0)
			garment.set_process(false)
	))
	return actor
