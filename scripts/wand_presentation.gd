extends RefCounted
## Shared, low-poly Arc Wand geometry. +Y runs from the grip to its emitter.
const TIP := Vector3(0,.65,0)
const Lines = preload("res://scripts/robe_lines.gd")
const CACHE_LIMIT := 16
static var _cache: Dictionary = {}

static func _material(color: Color, energy: float = 0) -> StandardMaterial3D:
	var material := Lines.make_material(color,energy)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

static func _triangles(points: PackedVector3Array, material: Material) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES,material)
	for point in points: mesh.surface_add_vertex(point)
	mesh.surface_end()
	return mesh

static func _beam(faces: PackedVector3Array, edges: PackedVector3Array, y0: float, y1: float, r0: float, r1: float) -> void:
	# A hexagonal barrel reads as a deliberate geometric tool, not a staff.
	for i in range(6):
		var a := i*TAU/6
		var b := (i+1)*TAU/6
		var p := Vector3(cos(a)*r0,y0,sin(a)*r0)
		var q := Vector3(cos(b)*r0,y0,sin(b)*r0)
		var r := Vector3(cos(a)*r1,y1,sin(a)*r1)
		var s := Vector3(cos(b)*r1,y1,sin(b)*r1)
		faces.append_array([p,q,r,q,s,r,Vector3(0,y0,0),q,p,Vector3(0,y1,0),r,s])
		edges.append_array([p,q,r,s,p,r])

static func _build(tint: Color) -> Array:
	var faces := PackedVector3Array()
	var edges := PackedVector3Array()
	var energy := PackedVector3Array()
	_beam(faces,edges,-.15,-.10,.009,.025)
	_beam(faces,edges,-.10,.10,.025,.023)
	_beam(faces,edges,.10,.14,.032,.031)
	_beam(faces,edges,.14,.18,.031,.015)
	_beam(faces,edges,.18,.46,.015,.012)
	_beam(faces,edges,.46,.49,.012,.031)
	# Restrained silver grip wraps and two luminous barrel rails.
	for i in range(7):
		var y := -.09+i*.028
		edges.append_array([Vector3(-.022,y,.015),Vector3(.022,y+.019,.015),Vector3(-.022,y,-.015),Vector3(.022,y+.019,-.015)])
	for side in [-1.0,1.0]:
		energy.append_array([Vector3(side*.012,.18,.010),Vector3(side*.010,.46,.010)])
	# Four angular jaws frame the focus diamond and leave its center visible.
	var core := PackedVector3Array()
	for i in range(4):
		var a := i*TAU/4+PI*.25
		var b := (i+1)*TAU/4+PI*.25
		var lower := Vector3(0,.49,0)
		var shoulder := Vector3(cos(a)*.049,.565,sin(a)*.049)
		var upper := Vector3(0,.65,0)
		edges.append_array([lower,shoulder,shoulder,upper])
		energy.append_array([lower,shoulder,shoulder,upper])
		var p := Vector3(cos(a)*.026,.58,sin(a)*.026)
		var q := Vector3(cos(b)*.026,.58,sin(b)*.026)
		core.append_array([Vector3(0,.53,0),q,p,Vector3(0,.625,0),p,q])
	var outline := Lines.segments(edges,Color("758699"),.25)
	var inlays := Lines.segments(energy,tint,2.2)
	var meshes := [_triangles(faces,_material(Color("090e17"))),outline.mesh,inlays.mesh,_triangles(core,_material(tint,2.6))]
	outline.free()
	inlays.free()
	return meshes

static func model(tint: Color, length: float = .62, motif: String="") -> Node3D:
	var key := tint.to_html()
	if not _cache.has(key):
		if _cache.size()>=CACHE_LIMIT: _cache.erase(_cache.keys()[0])
		_cache[key] = _build(tint)
	var root := Node3D.new()
	root.name = "ArcWand"
	root.scale = Vector3.ONE*clampf(length/.62,.7,1.4)
	for mesh: Mesh in _cache[key]:
		var surface := MeshInstance3D.new()
		surface.mesh = mesh
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(surface)
	var emitter := Marker3D.new()
	emitter.name = "WandEmitter"
	emitter.position = TIP
	root.add_child(emitter)
	if not motif.is_empty():
		var points:=PackedVector3Array()
		if motif=="eye":
			for point: Vector3 in preload("res://scripts/dungeon_glyphs.gd").strokes(1): points.append(Vector3(0,.57,.04)+point*.12)
		else:
			for i in range(14):
				for j in [i,i+1]:
					var t: float=j/14.0
					points.append(Vector3(sin(t*TAU)*.045,.47+t*.21,.035))
		var emblem:=Lines.segments(points,tint,2.5)
		emblem.name="TempleFocusEmblem"
		root.add_child(emblem)
	return root
