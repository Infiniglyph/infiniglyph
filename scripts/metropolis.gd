extends Node3D
## Static city additions. Render by spatial cell; every volume has real collision.
const Neon = preload("res://scripts/neon.gd")
const CELL_SIZE := 16.0
const TOWER := Vector3(0,0,-64)
class Cell extends RefCounted:
	var faces := PackedVector3Array()
	var edges := PackedVector3Array()
	var warm_faces := PackedVector3Array()
	var warm_edges := PackedVector3Array()
	var body: StaticBody3D
var cells: Dictionary = {}
var shapes: Dictionary = {}
var solids: Array[Dictionary] = []
var routes: Array[Dictionary] = []
var light_sources: Array[OmniLight3D] = []
var tree_count := 0
var banner_count := 0
var skyline_count := 0
var render_batches := 0
var walk_surfaces: Array[Dictionary] = []
var guard_spans: Array[Dictionary] = []
var outer_quarters = preload("res://scripts/outer_quarters.gd").new()

func _ready() -> void:
	name = "Metropolis"
	Neon.prepare()
	build_tower()
	build_skyway(-1,12.12)
	build_skyway(1,16.12)
	build_crossing()
	build_north_loop()
	build_guards()
	build_boulevard()
	build_skyline()
	outer_quarters.build(self)
	finish_batches()

func cell_for(point: Vector3, partition: String = "") -> Cell:
	var key := "%d_%d_%d_%s" % [floori(point.x/CELL_SIZE),floori(point.y/CELL_SIZE),floori(point.z/CELL_SIZE),partition]
	if not cells.has(key):
		var cell := Cell.new()
		cell.body = StaticBody3D.new()
		cell.body.name = "CityCollision_"+key
		add_child(cell.body)
		cells[key] = cell
	return cells[key]

func solid(vertices: PackedVector3Array, faces: Array, transform: Transform3D, shape: Shape3D, tag: String, warm: bool = false) -> void:
	# Keep broad low plazas and sloping bridges out of tall facade light lists.
	var partition := tag if tag in ["TowerDais","CivicCrystal","SkywayCrossing","CrossingHandrail"] else ""
	var cell := cell_for(transform.origin,partition)
	var triangles := PackedVector3Array()
	var edges := PackedVector3Array()
	var seen: Dictionary = {}
	for face: Array in faces:
		for i in range(1,face.size()-1):
			for index: int in [face[0],face[i],face[i+1]]: triangles.append(transform*vertices[index])
		for i in range(face.size()):
			var a: int = face[i]
			var b: int = face[(i+1)%face.size()]
			var pair := Vector2i(mini(a,b),maxi(a,b))
			if seen.has(pair): continue
			seen[pair] = true
			edges.append_array([transform*vertices[a],transform*vertices[b]])
	if warm:
		cell.warm_faces.append_array(triangles)
		cell.warm_edges.append_array(edges)
	else:
		cell.faces.append_array(triangles)
		cell.edges.append_array(edges)
	var collider := CollisionShape3D.new()
	collider.name = tag
	collider.shape = shape
	cell.body.add_child(collider)
	collider.transform = transform
	solids.append({"tag":tag,"collider":collider,"transform":transform,"vertices":vertices,"faces":faces,"warm":warm})

func block(at: Vector3, size: Vector3, tag: String, basis: Basis = Basis.IDENTITY, warm: bool = false) -> void:
	var vertices := PackedVector3Array()
	for x in [-1,1]:
		for y in [-1,1]:
			for z in [-1,1]: vertices.append(Vector3(x,y,z)*size*0.5)
	if not shapes.has(size):
		var shape := BoxShape3D.new()
		shape.size = size
		shapes[size] = shape
	solid(vertices,[[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]],Transform3D(basis,at),shapes[size],tag,warm)

func prism(at: Vector3, polygon: Array[Vector2], height: float, tag: String) -> void:
	var vertices := PackedVector3Array()
	var center := Vector2.ZERO
	for point in polygon: center += point
	center /= float(polygon.size())
	for y in [-height*0.5,height*0.5]:
		for point in polygon: vertices.append(Vector3(point.x-center.x,y,point.y-center.y))
	var count := polygon.size()
	var bottom: Array = []
	var top: Array = []
	var faces: Array = []
	for i in range(count):
		bottom.append(count-1-i)
		top.append(count+i)
		var next := (i+1)%count
		faces.append([i,next,next+count,i+count])
	faces.append(bottom)
	faces.append(top)
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	solid(vertices,faces,Transform3D(Basis.IDENTITY,at+Vector3(center.x,0,center.y)),shape,tag)

func beam(a: Vector3, b: Vector3, width: float, tag: String, warm: bool = false) -> void:
	var direction := b-a
	block((a+b)*0.5,Vector3(width,direction.length(),width),tag,Basis(Quaternion(Vector3.UP,direction.normalized())),warm)

func circle(at: Vector3, radius: float, width: float, thickness: float, segments: int, tag: String) -> void:
	for i in range(segments):
		var a := i*TAU/segments
		var b := (i+1)*TAU/segments
		var polygon: Array[Vector2] = [Vector2(sin(a),cos(a))*(radius-width*0.5),Vector2(sin(a),cos(a))*(radius+width*0.5),Vector2(sin(b),cos(b))*(radius+width*0.5),Vector2(sin(b),cos(b))*(radius-width*0.5)]
		prism(at,polygon,thickness,tag)

func disk(at: Vector3, radius: float, thickness: float, tag: String) -> void:
	var polygon: Array[Vector2] = []
	for i in range(16): polygon.append(Vector2(sin(i*TAU/16),cos(i*TAU/16))*radius)
	prism(at,polygon,thickness,tag)

func walk_deck(at: Vector3, polygon: Array[Vector2], thickness: float, tag: String) -> void:
	prism(at,polygon,thickness,tag)
	var top := PackedVector3Array()
	for point in polygon: top.append(at+Vector3(point.x,thickness*0.5,point.y))
	register_walk(top,tag)

func register_walk(points: PackedVector3Array, tag: String, portal: bool = false) -> void:
	var outline := PackedVector2Array()
	for point in points: outline.append(Vector2(point.x,point.z))
	var normal := (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	walk_surfaces.append({"points":points,"outline":outline,"normal":normal,"tag":tag,"portal":portal})

func walk_span(a: Vector3, b: Vector3, width: float, tag: String) -> void:
	# Top endpoints are exact: ramps meet flat junctions without tilted-box lips.
	var side := Vector3.UP.cross((b-a).normalized()).normalized()*width*0.5
	var points := PackedVector3Array([a-side,a+side,b+side,b-side])
	var center := (a+b)*0.5-Vector3.UP*0.14
	var vertices := PackedVector3Array()
	for point in points: vertices.append(point-center-Vector3.UP*0.28)
	for point in points: vertices.append(point-center)
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	solid(vertices,[[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]],Transform3D(Basis.IDENTITY,center),shape,tag)
	register_walk(points,tag)

func walk_box(at: Vector3, size: Vector2, tag: String) -> void:
	var polygon: Array[Vector2] = [Vector2(-size.x,-size.y)*0.5,Vector2(size.x,-size.y)*0.5,Vector2(size.x,size.y)*0.5,Vector2(-size.x,size.y)*0.5]
	walk_deck(at,polygon,0.28,tag)

func floor_height(surface: Dictionary, point: Vector2) -> float:
	var first: Vector3 = surface.points[0]
	var normal: Vector3 = surface.normal
	return first.y-(normal.x*(point.x-first.x)+normal.z*(point.y-first.z))/normal.y

func build_guards() -> void:
	# Fence the exposed boundary of the connected floor union. Overlaps are
	# genuine openings, including stair portals, rather than guessed angle gaps.
	for surface: Dictionary in walk_surfaces:
		if surface.portal: continue
		var outline: PackedVector2Array = surface.outline
		var area := 0.0
		for i in range(outline.size()): area += outline[i].cross(outline[(i+1)%outline.size()])
		for i in range(outline.size()):
			var a: Vector3 = surface.points[i]
			var b: Vector3 = surface.points[(i+1)%outline.size()]
			var start := Vector2(a.x,a.z)
			var direction := Vector2(b.x-a.x,b.z-a.z)
			var outward := Vector2(direction.y,-direction.x).normalized()*(1 if area>0 else -1)
			var cuts: Array[float] = [0.0,1.0]
			var neighbours: Array[Dictionary] = []
			for other: Dictionary in walk_surfaces:
				if other == surface: continue
				# A floor on another storey cannot remove this storey's railing.
				if absf(floor_height(other,start+direction*0.5)-(a.y+b.y)*0.5)>4.5: continue
				var near := false
				for point: Vector2 in other.outline:
					if Geometry2D.get_closest_point_to_segment(point,start,start+direction).distance_to(point)<32:
						near = true
						break
				if not near: continue
				neighbours.append(other)
				var poly: PackedVector2Array = other.outline
				for j in range(poly.size()):
					var c := poly[j]
					var edge := poly[(j+1)%poly.size()]-c
					var denominator := direction.cross(edge)
					if absf(denominator)>0.00001:
						var t := (c-start).cross(edge)/denominator
						var u := (c-start).cross(direction)/denominator
						if t>0.00001 and t<0.99999 and u>=-0.00001 and u<=1.00001: cuts.append(t)
					elif absf((c-start).cross(direction))<0.0001:
						for point in [c,c+edge]:
							var t: float = (point-start).dot(direction)/direction.length_squared()
							if t>0.00001 and t<0.99999: cuts.append(t)
			cuts.sort()
			var exposed_start := -1.0
			for j in range(cuts.size()-1):
				if cuts[j+1]-cuts[j]<0.00001: continue
				var mid := (cuts[j]+cuts[j+1])*0.5
				var probe := start+direction*mid+outward*0.025
				var covered := false
				for other: Dictionary in neighbours:
					if absf(floor_height(other,probe)-lerpf(a.y,b.y,mid))<0.31 and Geometry2D.is_point_in_polygon(probe,other.outline):
						covered = true
						break
				if not covered and exposed_start<0: exposed_start = cuts[j]
				if covered and exposed_start>=0:
					guard(a.lerp(b,exposed_start),a.lerp(b,cuts[j]),surface.tag)
					exposed_start = -1.0
			if exposed_start>=0: guard(a.lerp(b,exposed_start),b,surface.tag)

func guard(a: Vector3, b: Vector3, tag: String) -> void:
	if a.distance_to(b)<0.02: return
	guard_spans.append({"a":a,"b":b,"tag":tag})
	# Orange caps are working low-power luminaires; existing local skyway lights
	# illuminate them without adding a light object to each individual segment.
	var warm := tag in ["SkywayDeck","SkywayStraight","NorthPromenade"] and (a+b).x*0.5>0
	beam(a+Vector3.UP,b+Vector3.UP,0.075,"SkywayHandrail",warm)
	beam(a+Vector3.UP*0.5,b+Vector3.UP*0.5,0.045,"SkywayMidrail")
	var count := maxi(1,ceili(a.distance_to(b)/2.0))
	for i in range(count+1):
		var foot := a.lerp(b,float(i)/count)
		beam(foot,foot+Vector3.UP,0.065,"SkywayBaluster")

func light_at(at: Vector3, range_value: float = 5.8, energy: float = 1.0) -> void:
	var light := OmniLight3D.new()
	light.name = "ArchitecturalOrangeLight"
	light.position = at
	light.light_color = Neon.ORANGE
	light.light_energy = energy
	light.omni_range = range_value
	light.light_specular = 0.45
	light.shadow_enabled = false
	add_child(light)
	light_sources.append(light)

func build_tower() -> void:
	# Terraced civic dais, approached from the existing north avenue.
	for tier in range(5): disk(TOWER+Vector3(0,0.42+tier*0.6,0),11-tier*0.4,0.6,"TowerDais")
	for step in range(12):
		var h := (step+1)*0.25
		block(TOWER+Vector3(0,0.12+h*0.5,15.25-step*0.5),Vector3(4,h,0.5),"TowerStair")
	block(TOWER+Vector3(0,4.62,0),Vector3(2.5,3,2.5),"CrystalPedestal")
	for x in [-6.5,6.5]:
		for z in [-6.5,6.5]:
			block(TOWER+Vector3(x,20,z),Vector3(0.32,34,0.32),"TowerColumn")
			beam(TOWER+Vector3(x,37,z),TOWER+Vector3(x*0.35,42,z*0.35),0.2,"TowerBrace")
	# A solid geometric light-being monument, not a non-colliding hologram.
	var crystal := PackedVector3Array([Vector3(0,6,0),Vector3(0,-6,0),Vector3(4.8,0,0),Vector3(0,0,4.8),Vector3(-4.8,0,0),Vector3(0,0,-4.8)])
	var shape := ConvexPolygonShape3D.new()
	shape.points = crystal
	solid(crystal,[[0,2,3],[0,3,4],[0,4,5],[0,5,2],[1,3,2],[1,4,3],[1,5,4],[1,2,5]],Transform3D(Basis.IDENTITY,TOWER+Vector3.UP*14),shape,"CivicCrystal")
	for spec in [Vector3(5,16,28),Vector3(3.2,18,45),Vector3(1.35,24,66),Vector3(0.18,8,82)]:
		block(TOWER+Vector3.UP*spec.z,Vector3(spec.x,spec.y,spec.x),"TowerSpire")
	for spec in [Vector2(9,9.5),Vector2(8,18),Vector2(7,30),Vector2(5.2,42),Vector2(4,58),Vector2(2.8,72)]:
		for i in range(24):
			var a := i*TAU/24
			var b := (i+1)*TAU/24
			var polygon: Array[Vector2] = [Vector2(sin(a),cos(a))*(spec.x-0.9),Vector2(sin(a),cos(a))*(spec.x+0.9),Vector2(sin(b),cos(b))*(spec.x+0.9),Vector2(sin(b),cos(b))*(spec.x-0.9)]
			walk_deck(TOWER+Vector3.UP*spec.y,polygon,0.24,"TowerRing")
		routes.append({"point":TOWER+Vector3(cos(PI/24)*spec.x,spec.y+0.12,sin(PI/24)*spec.x),"tag":"TowerRing"})
	# The crown is a real narrow ring with radial structural supports.
	circle(TOWER+Vector3.UP*64,17.5,0.45,0.18,48,"CrownHalo")
	for i in range(8):
		var direction := Vector3(sin(i*TAU/8),0,cos(i*TAU/8))
		beam(TOWER+direction*3+Vector3.UP*58,TOWER+direction*17.5+Vector3.UP*64,0.12,"HaloSpoke")

func build_skyway(side: int, height: float) -> void:
	var center := Vector3(side*36,height,-28 if side<0 else -30)
	var radius := 25.0
	var segments := 16
	for i in range(segments):
		var a := i*PI*0.5/segments*(1 if side<0 else -1)
		var b := (i+1)*PI*0.5/segments*(1 if side<0 else -1)
		var polygon: Array[Vector2] = [Vector2(sin(a),cos(a))*(radius-1.5),Vector2(sin(a),cos(a))*(radius+1.5),Vector2(sin(b),cos(b))*(radius+1.5),Vector2(sin(b),cos(b))*(radius-1.5)]
		walk_deck(center,polygon,0.28,"SkywayDeck")
		var mid := (a+b)*0.5
		var sample := center+Vector3(sin(mid)*radius,0.14,cos(mid)*radius)
		if i%4 == 0: routes.append({"point":sample,"tag":"SkywayDeck"})
		if i%3 == 1:
			light_at(center+Vector3(sin(mid)*(radius-1.35),1.2,cos(mid)*(radius-1.35)),5.8,0.7)
		if i%8 == 3:
			block(Vector3(sample.x,height*0.5,sample.z),Vector3(0.38,height,0.38),"SkywaySupport")
	# Both new routes are reachable on foot from outside the original plaza.
	var steps := 48 if side<0 else 64
	var start_z := 12.5 if side<0 else 15.3
	var tread := 0.5 if side<0 else 0.45
	var x := side*15.0
	block(Vector3(x,0.06,start_z+0.6),Vector3(3.4,0.12,1.4),"SkywayStairFoot")
	for step in range(steps):
		var h := (step+1)*0.25
		block(Vector3(x,0.12+h-0.09,start_z-(step+0.5)*tread),Vector3(3.2,0.18,tread+0.005),"SkywayStair")
		if step%4 == 3:
			for sign_value in [-1,1]:
				var foot := Vector3(x+sign_value*1.6,0.12+h,start_z-(step+0.5)*tread)
				beam(foot,foot+Vector3.UP*1.05,0.07,"StairBaluster")
	var end_z := start_z-steps*tread
	walk_box(Vector3(x,height,end_z-1.6),Vector2(4.8,3.2),"SkywayLanding")
	# The stair mouth is an explicit open portal, exactly the staircase width.
	register_walk(PackedVector3Array([Vector3(x-1.6,height+0.14,end_z-0.05),Vector3(x+1.6,height+0.14,end_z-0.05),Vector3(x+1.6,height+0.14,end_z+0.5),Vector3(x-1.6,height+0.14,end_z+0.5)]),"StairPortal",true)
	for sign_value in [-1,1]:
		beam(Vector3(x+sign_value*1.6,1.42,start_z),Vector3(x+sign_value*1.6,height+1.05,end_z),0.07,"StairHandrail")
		beam(Vector3(x+sign_value*1.35,0.05,start_z),Vector3(x+sign_value*1.35,height-0.18,end_z),0.16,"StairStringer")
	routes.append({"point":Vector3(x,height+0.14,end_z-1.6),"tag":"SkywayLanding"})
	# Continue along the open avenue, outside the existing building footprints.
	var north_start := center.z
	var north_end := -46.5
	for i in range(5):
		var za := lerpf(north_start,north_end,i/5.0)
		var zb := lerpf(north_start,north_end,(i+1)/5.0)
		walk_span(Vector3(side*11,height+0.14,za),Vector3(side*11,height+0.14,zb),3,"SkywayStraight")
		if i%2 == 0:
			light_at(Vector3(side*9.65,height+1.2,(za+zb)*0.5),5.0,0.7)
			routes.append({"point":Vector3(side*11,height+0.14,(za+zb)*0.5),"tag":"SkywayStraight"})
	# Complete the former exposed arc ends as deliberate, guarded overlooks.
	var lookout := center+Vector3(-side,0,25)
	walk_box(lookout,Vector2(6,6),"SkywayLookout")
	routes.append({"point":lookout+Vector3.UP*0.14,"tag":"SkywayLookout"})
	# Painted compass/infinity inlay gives each endpoint a finished destination.
	var cell := cell_for(lookout)
	for i in range(32):
		var a := i*TAU/32
		var b := (i+1)*TAU/32
		cell.edges.append_array([lookout+Vector3(cos(a),0.147,sin(a*2)*0.5),lookout+Vector3(cos(b),0.147,sin(b*2)*0.5)])

func build_crossing() -> void:
	var a := Vector3(-9.5,12.26,-45)
	var b := Vector3(9.5,16.26,-45)
	walk_span(a,b,3,"SkywayCrossing")
	for endpoint in [Vector3(-11,12.12,-45),Vector3(11,16.12,-45)]:
		block(Vector3(endpoint.x,endpoint.y*0.5,endpoint.z),Vector3(0.35,endpoint.y,0.35),"CrossingSupport")
	routes.append({"point":(a+b)*0.5,"tag":"SkywayCrossing"})

func build_north_loop() -> void:
	# A gradual west ramp joins the east route at a common public terrace.
	for side in [-1,1]:
		var low := 12.26 if side<0 else 16.26
		walk_span(Vector3(side*11,low,-46.5),Vector3(side*11,16.26,-55.5),3,"NorthApproach")
		walk_span(Vector3(side*11,16.26,-55.5),Vector3(side*11,16.26,-64),3,"NorthApproach")
		routes.append({"point":Vector3(side*11,(low+16.26)*0.5,-51),"tag":"NorthApproach"})
	for i in range(48):
		var a := i*TAU/48
		var b := (i+1)*TAU/48
		var polygon: Array[Vector2] = [Vector2(sin(a),cos(a))*9.5,Vector2(sin(a),cos(a))*12.5,Vector2(sin(b),cos(b))*12.5,Vector2(sin(b),cos(b))*9.5]
		walk_deck(TOWER+Vector3.UP*16.12,polygon,0.28,"NorthPromenade")
		if i%12 == 6:
			var mid := (a+b)*0.5
			routes.append({"point":TOWER+Vector3(sin(mid)*11,16.26,cos(mid)*11),"tag":"NorthPromenade"})
	for side in [-1,1]:
		light_at(TOWER+Vector3(side*11.9,17.32,0),4.5,0.7)
		block(TOWER+Vector3(side*11,8,0),Vector3(0.35,16,0.35),"PromenadeSupport")
	# The north avenue also ends at a finished, solid civic gateway.
	for side in [-1,1]:
		block(Vector3(side*7.5,2.5,-82),Vector3(0.35,5,0.5),"NorthGatePillar")
		beam(Vector3(side*7.5,5,-82),Vector3(side*4.5,6.2,-82),0.16,"NorthGateCrown")

func build_boulevard() -> void:
	for side in [-1,1]:
		for z in [-14,-44,-60]:
			banner(Vector3(side*9.7,0.12,z))
		for z in [-18,-54]: tree(Vector3(side*8.6,0.0,z))
		for z in [-12,-51,-62]: bench(Vector3(side*7.8,0.0,z),side)
		for z in [8,48]: tree(Vector3(side*34,0.12,z))

func banner(at: Vector3) -> void:
	banner_count += 1
	block(at+Vector3(0,2.9,0),Vector3(0.12,5.8,0.12),"BannerPost")
	block(at+Vector3(0.7,3.6,0),Vector3(1.25,2.65,0.06),"BannerPanel")
	beam(at+Vector3(0,5.72,0),at+Vector3(1.5,5.72,0),0.10,"BannerLuminaire",true)
	light_at(at+Vector3(0.7,5.6,0.15),6.3,1.2)
	var cell := cell_for(at)
	for i in range(40):
		var a := i*TAU/40
		var b := (i+1)*TAU/40
		cell.edges.append_array([at+Vector3(0.7+cos(a)*0.43,3.65+sin(a*2)*0.23,0.042),at+Vector3(0.7+cos(b)*0.43,3.65+sin(b*2)*0.23,0.042)])
	# Identical back face decoration remains visible when circling the block.
	for i in range(40):
		var a := i*TAU/40
		var b := (i+1)*TAU/40
		cell.edges.append_array([at+Vector3(0.7+cos(a)*0.43,3.65+sin(a*2)*0.23,-0.042),at+Vector3(0.7+cos(b)*0.43,3.65+sin(b*2)*0.23,-0.042)])

func tree(at: Vector3) -> void:
	tree_count += 1
	block(at+Vector3.UP*0.18,Vector3(1.7,0.36,1.7),"TreePlanter")
	beam(at+Vector3.UP*0.35,at+Vector3.UP*3.7,0.16,"TreeTrunk")
	for i in range(5):
		var angle := i*TAU/5
		var direction := Vector3(sin(angle),0,cos(angle))
		var joint := at+direction*0.95+Vector3.UP*(3.3+float(i%2)*0.45)
		beam(at+Vector3.UP*2.25,joint,0.09,"TreeBranch")
		for turn in [-0.4,0.4]:
			var tip := joint+direction.rotated(Vector3.UP,turn)*0.7+Vector3.UP*0.9
			beam(joint,tip,0.055,"TreeTwig")
			var leaf: Array[Vector2] = []
			for n in range(5): leaf.append(Vector2(sin(n*TAU/5),cos(n*TAU/5))*0.32)
			prism(tip,leaf,0.45,"GeometricFoliage")

func bench(at: Vector3, side: int) -> void:
	block(at+Vector3.UP*0.62,Vector3(0.65,0.16,1.8),"BenchSeat")
	block(at+Vector3(side*0.28,1.02,0),Vector3(0.10,0.72,1.8),"BenchBack")
	for z in [-0.6,0.6]: block(at+Vector3(0,0.28,z),Vector3(0.45,0.56,0.12),"BenchLeg")
	block(at+Vector3(-side*0.32,0.7,0),Vector3(0.05,0.05,1.65),"BenchLuminaire",Basis.IDENTITY,true)
	light_at(at+Vector3(-side*0.4,0.72,0),3.4,0.65)

func build_skyline() -> void:
	for side in [-1,1]:
		for i in range(5):
			var at := Vector3(side*(78+float(i%2)*6),0,-62+i*32)
			var height := 48.0+float((i*19+(11 if side>0 else 0))%45)
			var width := 10.0+float(i%3)*2
			block(at+Vector3.UP*height*0.5,Vector3(width,height,width),"SkylineTower")
			skyline_count += 1
			block(at+Vector3.UP*(height+2),Vector3(width*0.65,4,width*0.65),"SkylineCrown")
			beam(at+Vector3.UP*(height+4),at+Vector3.UP*(height+11),0.15,"SkylineAntenna")
			var cell := cell_for(at)
			for level in range(3,int(height),3):
				var h := width*0.5+0.008
				for sign_value in [-1,1]:
					cell.edges.append_array([at+Vector3(-h,level,sign_value*h),at+Vector3(h,level,sign_value*h),at+Vector3(sign_value*h,level,-h),at+Vector3(sign_value*h,level,h)])

func finish_batches() -> void:
	var dark := Neon.dark.duplicate()
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cyan := Neon.material(Color(0.02,0.9,1))
	var orange := Neon.material(Neon.ORANGE)
	for cell: Cell in cells.values():
		for spec in [[cell.faces,Mesh.PRIMITIVE_TRIANGLES,dark],[cell.edges,Mesh.PRIMITIVE_LINES,cyan],[cell.warm_faces,Mesh.PRIMITIVE_TRIANGLES,orange],[cell.warm_edges,Mesh.PRIMITIVE_LINES,orange]]:
			var vertices: PackedVector3Array = spec[0]
			if vertices.is_empty(): continue
			var geometry := ImmediateMesh.new()
			geometry.surface_begin(spec[1],spec[2])
			for vertex in vertices: geometry.surface_add_vertex(vertex)
			geometry.surface_end()
			var visual := MeshInstance3D.new()
			visual.name = "CityBatch"
			visual.mesh = geometry
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(visual)
			render_batches += 1
