extends RefCounted
## Original Egyptian-inspired calligraphy, baked into the wall's line batch.
static var _stroke_cache: Dictionary={}
static var _mesh_cache: Dictionary={}

static func strokes(kind: int) -> PackedVector3Array:
	var key:=posmod(kind,6)
	if not _stroke_cache.has(key):
		var points:=PackedVector3Array()
		for path: Array in paths(key):
			for i in range(1,path.size()):
				for point: Vector2 in [path[i-1],path[i]]: points.append(Vector3(point.x,point.y,0))
		_stroke_cache[key]=points
	return _stroke_cache[key]

static func mesh(kind: int) -> Mesh:
	var key:=posmod(kind,6)
	if not _mesh_cache.has(key):
		var result:=ArrayMesh.new()
		var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=strokes(key)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
		_mesh_cache[key]=result
	return _mesh_cache[key]

static func paths(kind: int) -> Array:
	match kind%6:
		0: # Ankh: loop, crossbar and stem.
			return [[Vector2(0,.12),Vector2(-.22,.38),Vector2(-.18,.65),Vector2(0,.76),Vector2(.18,.65),Vector2(.22,.38),Vector2(0,.12)],[Vector2(-.38,.08),Vector2(.38,.08)],[Vector2(0,.12),Vector2(0,-.66)]]
		1: # Eye, brow and descending falcon marking.
			return [[Vector2(-.48,.12),Vector2(-.15,.36),Vector2(.22,.32),Vector2(.48,.12),Vector2(.15,-.03),Vector2(-.18,-.02),Vector2(-.48,.12)],[Vector2(-.45,.43),Vector2(-.12,.57),Vector2(.3,.5)],[Vector2(0,.28),Vector2(0,.02)],[Vector2(-.22,0),Vector2(-.15,-.45),Vector2(.13,-.64),Vector2(.31,-.4)]]
		2: # Lotus opening above its stem.
			return [[Vector2(-.5,.18),Vector2(-.34,-.05),Vector2(0,-.22),Vector2(.34,-.05),Vector2(.5,.18)],[Vector2(-.5,.18),Vector2(-.24,.12),Vector2(-.3,.62),Vector2(0,.27),Vector2(.3,.62),Vector2(.24,.12),Vector2(.5,.18)],[Vector2(0,-.22),Vector2(0,-.7)],[Vector2(-.27,-.65),Vector2(.27,-.65)]]
		3: # Three ordered water ripples.
			return [[Vector2(-.5,.5),Vector2(-.25,.66),Vector2(0,.5),Vector2(.25,.66),Vector2(.5,.5)],[Vector2(-.5,.03),Vector2(-.25,.19),Vector2(0,.03),Vector2(.25,.19),Vector2(.5,.03)],[Vector2(-.5,-.45),Vector2(-.25,-.29),Vector2(0,-.45),Vector2(.25,-.29),Vector2(.5,-.45)]]
		4: # Feather/reed.
			return [[Vector2(-.3,-.65),Vector2(.3,.7),Vector2(.35,.23),Vector2(.14,-.22),Vector2(-.3,-.65)],[Vector2(-.3,-.65),Vector2(-.35,.14),Vector2(.3,.7)],[Vector2(-.24,-.35),Vector2(.13,-.2)],[Vector2(-.27,-.02),Vector2(.24,.1)],[Vector2(-.1,.31),Vector2(.3,.4)]]
		_: # Scarab with wing casings and six legs.
			return [[Vector2(0,.65),Vector2(-.23,.43),Vector2(-.3,-.1),Vector2(-.15,-.48),Vector2(.15,-.48),Vector2(.3,-.1),Vector2(.23,.43),Vector2(0,.65)],[Vector2(0,.4),Vector2(0,-.42)],[Vector2(-.3,.25),Vector2(-.48,.42),Vector2(-.52,.65)],[Vector2(.3,.25),Vector2(.48,.42),Vector2(.52,.65)],[Vector2(-.3,0),Vector2(-.55,-.06)],[Vector2(.3,0),Vector2(.55,-.06)],[Vector2(-.2,-.3),Vector2(-.46,-.52)],[Vector2(.2,-.3),Vector2(.46,-.52)]]

static func draw(batch: Node3D, kind: int, origin: Vector3, right: Vector3, scale: float, color: Color, up: Vector3 = Vector3.UP) -> void:
	for path: Array in paths(kind):
		for i in range(1,path.size()):
			var a: Vector2=path[i-1]
			var b: Vector2=path[i]
			batch.line(origin+(right*a.x+up*a.y)*scale,origin+(right*b.x+up*b.y)*scale,color)
