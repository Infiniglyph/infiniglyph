extends RefCounted
## The store uses the same garment renderer and joint anchors as gameplay.
const Geometry = preload("res://scripts/equipment_geometry.gd")
const Garment = preload("res://scripts/equipment_garment.gd")
const Visual = preload("res://scripts/character_visual.gd")
const Scribe = preload("res://scripts/eternal_scribe_robe.gd")
const Lines = preload("res://scripts/robe_lines.gd")

static func model(entry: Dictionary) -> Node3D:
	if entry.id=="health_glyph":
		var glyph := Node3D.new()
		var ink := Color("66ffb8")
		glyph.add_child(Lines.box(Vector3(.25,.25,.25),ink))
		glyph.add_child(Lines.polyline(PackedVector3Array([Vector3(-.18,0,.14),Vector3(0,.24,.14),Vector3(.18,0,.14),Vector3(0,-.24,.14)]),ink,true))
		glyph.add_child(Lines.segments(PackedVector3Array([Vector3(-.07,0,.15),Vector3(.07,0,.15),Vector3(0,-.07,.15),Vector3(0,.07,.15)]),ink))
		return glyph
	if not entry.geometry.has("tailoring") and entry.id!="eternal_scribe_robes": return Geometry.model(entry.geometry)
	var actor := CharacterBody3D.new()
	var figure := Visual.new()
	figure.live_retrieval = false
	actor.add_child(figure)
	# _ready builds the mannequin after the model enters the preview viewport.
	actor.tree_entered.connect(func(): figure.ready.connect(func():
		if entry.id=="eternal_scribe_robes":
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
