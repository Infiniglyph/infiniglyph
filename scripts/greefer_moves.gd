extends RefCounted
## Shared spec format: real windups, one registered contact per authored pulse.
const Library = preload("res://scripts/weapon_library.gd")

static func move(style: StringName) -> Dictionary:
	var result: Dictionary
	match style:
		&"rake": result = Library.spec("Raking Talons",1.28,0.48,112,3.6,100,"sweep",[0.60])
		&"sweep": result = Library.spec("Crownless Wing",1.8,0.72,148,5.0,240,"orbit",[0.86])
		&"lunge": result = Library.spec("Territorial Rush",1.65,0.65,170,3.8,85,"thrust",[0.91])
		&"double": result = Library.spec("Twin Rebuff",1.95,0.52,92,3.8,120,"cross",[0.64,1.12],-1)
		_: result = Library.spec("Falling Verdict",2.05,0.80,205,3.9,110,"slam",[1.14])
	result.beast_style = style
	result.contact_before = 0.12 if style == &"sweep" else 0.08
	result.contact_after = 0.16 if style in [&"sweep",&"lunge"] else 0.10
	# Boss strength comes from spacing/commitment, not bypassing shared defense.
	result.hit_stun_level = 1.6 if style in [&"rake",&"double"] else 2.4
	result.hit_stagger = 0.30 if style in [&"rake",&"double"] else 0.44
	return result

static func window(move: Dictionary, pulse: int) -> Vector2:
	return Vector2(float(move.hits[pulse])-float(move.get("contact_before",0.08)),float(move.hits[pulse])+float(move.get("contact_after",0.10)))
