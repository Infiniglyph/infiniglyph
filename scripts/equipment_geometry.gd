extends RefCounted
## Bounded shared meshes: solid volumes and emissive edges, never billboards.
const Neon = preload("res://scripts/neon.gd")
const CACHE_LIMIT := 64
static var cache: Dictionary = {}
static var builds := 0
var faces := PackedVector3Array()
var edges := PackedVector3Array()

func triangle(a: Vector3,b: Vector3,c: Vector3) -> void:
	faces.append_array([a,b,c])

func prism(points: Array, depth: float) -> void:
	var polygon := PackedVector2Array()
	for point: Variant in points: polygon.append(Vector2(point[0],point[1]) if point is Array else point)
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for index in range(0,triangles.size(),3):
		var a := polygon[triangles[index]]
		var b := polygon[triangles[index+1]]
		var c := polygon[triangles[index+2]]
		triangle(Vector3(a.x,a.y,depth*.5),Vector3(b.x,b.y,depth*.5),Vector3(c.x,c.y,depth*.5))
		triangle(Vector3(a.x,a.y,-depth*.5),Vector3(c.x,c.y,-depth*.5),Vector3(b.x,b.y,-depth*.5))
	for index in range(polygon.size()):
		var a := polygon[index]
		var b := polygon[(index+1)%polygon.size()]
		var p := Vector3(a.x,a.y,depth*.5)
		var q := Vector3(b.x,b.y,depth*.5)
		var r := Vector3(a.x,a.y,-depth*.5)
		var s := Vector3(b.x,b.y,-depth*.5)
		triangle(p,r,q)
		triangle(q,r,s)
		edges.append_array([p,q,r,s,p,r])

func box(x: float,y: float,w: float,h: float,d: float) -> void:
	prism([Vector2(x-w*.5,y),Vector2(x+w*.5,y),Vector2(x+w*.5,y+h),Vector2(x-w*.5,y+h)],d)

func ring(center: Vector2,radius: float,width: float,depth: float) -> void:
	for index in range(12):
		var a := Vector2.from_angle(index*TAU/12)
		var b := Vector2.from_angle((index+1)*TAU/12)
		prism([center+a*radius,center+b*radius,center+b*(radius-width),center+a*(radius-width)],depth)

func shell(rx: float,rz: float,height: float,taper: float,open_front: bool = false) -> void:
	for index in range(8):
		if open_front and index in [1,2]: continue
		var a := index*TAU/8
		var b := (index+1)*TAU/8
		var p := Vector3(cos(a)*rx,0,sin(a)*rz)
		var q := Vector3(cos(b)*rx,0,sin(b)*rz)
		var r := Vector3(p.x*taper,height,p.z*taper)
		var s := Vector3(q.x*taper,height,q.z*taper)
		triangle(p,q,r)
		triangle(q,s,r)
		edges.append_array([p,q,r,s,p,r])

func build(g: Dictionary) -> void:
	var family: String = g.family
	var length := float(g.get("length",1.2))
	var width := float(g.get("width",.10))
	var depth := float(g.get("depth",.05))
	var bulk := clampf(float(g.get("bulk",.8)),.5,1.2)
	var cloth: bool = g.get("style")=="cloth"
	if g.has("outline"):
		prism(g.outline,depth)
		return
	match family:
		"head":
			var form: String = g.get("head_form","hood" if cloth else "helmet")
			if form=="crown":
				shell(.17,.15,.06,1.15)
				for i in range(faces.size()): faces[i].y+=.22
				for i in range(edges.size()): edges[i].y+=.22
			elif form in ["mask","blindfold"]:
				box(0,.12,.28,.12 if form=="mask" else .05,.035)
				for i in range(faces.size()): faces[i].z+=.15
				for i in range(edges.size()): edges[i].z+=.15
			elif form=="hat":
				shell(.27,.24,.025,1.0)
				shell(.17,.16,.31,.3)
			else:
				shell(.15+bulk*.03,.16,.29 if form=="hood" else .24,.45 if form=="hood" else .85,true)
				if form!="hood": box(0,.20,.27,.025,.3)
				if form!="hood" and int(g.get("detail",0))%2==0: box(0,.24,.035,.10,.19)
		"body": shell(.23+bulk*.04,.16,.48,.85 if cloth else 1.02,true)
		"coat_panel": shell(.145,.13,-.52,1.4,true)
		"hands": shell(.075,.075,-.23,.84)
		"legs": shell(.095,.10,-.40,.74)
		"shield":
			var p: Array = []
			for i in range(10): p.append(Vector2(cos(i*TAU/10)*.34,sin(i*TAU/10)*.46))
			prism(p,.09)
			ring(Vector2.ZERO,.16,.025,.11)
		"ring":
			ring(Vector2.ZERO,.09,.022,.035)
			prism([Vector2(-.035,.065),Vector2(0,.13),Vector2(.035,.065),Vector2(0,.04)],.06)
		"bow","crossbow":
			for side in [-1,1]:
				prism([Vector2(0,-.1),Vector2(side*length*.45,length*.22),Vector2(side*length*.5,length*.34),Vector2(side*.05,.04)],.07)
			edges.append_array([Vector3(-length*.5,length*.34,0),Vector3(length*.5,length*.34,0)])
			box(0,-.2,.07,.35 if family=="bow" else .75,.08)
		"spear","halberd","scythe","staff":
			box(0,-.65,.055,length,.06)
			if family=="staff": ring(Vector2(0,length-.53),.18,.035,.06)
			elif family=="scythe": prism([Vector2(0,length-.8),Vector2(.70,length-.66),Vector2(.42,length-.42),Vector2(0,length-.45)],.045)
			elif family=="halberd": prism([Vector2(-.04,length-.95),Vector2(-.38,length-.7),Vector2(-.31,length-.35),Vector2(.07,length-.5)],.07)
			else: prism([Vector2(-.13,length-.7),Vector2(0,length),Vector2(.13,length-.7)],.045)
			if g.get("ring_head",false): ring(Vector2(0,length-.57),.22,.028,.06)
		"axe","hammer":
			box(0,-.24,.065,length-.08,.07)
			if family=="axe": prism([Vector2(-.04,length-.45),Vector2(-.39,length-.52),Vector2(-.40,length-.06),Vector2(0,length-.2)],.12)
			else: box(0,length-.4,.45,.35,.3)
		"fist":
			box(0,-.1,.30,.16,.1)
			for i in range(3): box((i-1)*.09,.06,.025,.22,.03)
		"chime","talisman":
			shell(.12,.12,.3,.5)
			ring(Vector2(0,.4),.09,.023,.04)
		"whip":
			box(0,-.22,.06,.4,.06)
			for i in range(10):
				var y := .18+i*length/10
				box(sin(i*.6)*.12,y,.025,length/10*.88,.025)
		_:
			box(0,-.24,.055,.36,.055)
			box(0,.08,float(g.get("guard",.3)),.04,.09)
			var curve := float(g.get("curve",0))
			for i in range(6):
				var a := i/6.0
				var b := (i+1)/6.0
				var gap := .015 if g.get("segmented",false) else 0.0
				var wa := width*(1-a*.65)
				var wb := width*(1-b*.65) if i<5 else 0.0
				prism([Vector2(curve*a*a-wa,.14+a*(length-.14)+gap),Vector2(curve*a*a+wa,.14+a*(length-.14)+gap),Vector2(curve*b*b+wb,.14+b*(length-.14)),Vector2(curve*b*b-wb,.14+b*(length-.14))],depth)
	# New inlays use simple mathematical geometry rather than copied textures.
	if family not in ["head","body","hands","legs","ring"]:
		edges.append_array([Vector3(0,.2,depth*.6),Vector3(width,.3,depth*.6),Vector3(width,.3,depth*.6),Vector3(0,.4,depth*.6)])

static func model(g: Dictionary) -> Node3D:
	Neon.prepare()
	var key := JSON.stringify(g)
	if not cache.has(key):
		var builder := new()
		builder.build(g)
		var mesh := ArrayMesh.new()
		if not builder.faces.is_empty():
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = builder.faces
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var wire := ArrayMesh.new()
		if not builder.edges.is_empty():
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = builder.edges
			wire.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
		if cache.size()>=CACHE_LIMIT: cache.erase(cache.keys()[0])
		cache[key] = [mesh,wire]
		builds += 1
	var root := Node3D.new()
	for index in range(2):
		var instance := MeshInstance3D.new()
		instance.mesh = cache[key][index]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.material_override = Neon.dark if index==0 else Neon.shared_material(Color(String(g.get("tint","75eaff"))))
		root.add_child(instance)
	return root
