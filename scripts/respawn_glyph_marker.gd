extends Node3D
## A small non-colliding bedroll-like destination, drawn as a flat light seal.
const Neon = preload("res://scripts/neon.gd")
var home := false

func _ready() -> void:
	name="HomeRespawnGlyph" if home else "RespawnGlyph"
	var color:=Color("ffd16a") if home else Color("85ffc8")
	var lines:=PackedVector3Array()
	for i in range(32):
		var a:=i*TAU/32
		var b:=(i+1)*TAU/32
		lines.append_array([Vector3(cos(a)*.65,.025,sin(a)*.65),Vector3(cos(b)*.65,.025,sin(b)*.65)])
		if i%4==0: lines.append_array([Vector3(cos(a)*.71,.025,sin(a)*.71),Vector3(cos(a)*.82,.025,sin(a)*.82)])
	var motif: Array=[Vector2(-.30,.10),Vector2(-.30,-.20),Vector2(0,-.43),Vector2(.30,-.20),Vector2(.30,.10),Vector2(-.30,.10)] if home else [Vector2(0,-.43),Vector2(.30,0),Vector2(0,.43),Vector2(-.30,0),Vector2(0,-.43)]
	for i in range(1,motif.size()): lines.append_array([Vector3(motif[i-1].x,.03,motif[i-1].y),Vector3(motif[i].x,.03,motif[i].y)])
	add_child(Neon.lines(lines,Neon.shared_material(color)))
	var caption:=Label3D.new()
	caption.text="HOME RESPAWN" if home else "RESPAWN"
	caption.position.y=.32
	caption.font_size=24
	caption.pixel_size=.003
	caption.modulate=color
	caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	add_child(caption)
