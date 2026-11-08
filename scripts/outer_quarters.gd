extends RefCounted
## Ground-level public spaces complete the avenues beyond the civic boulevard.
## Inlaid seams are paint; furniture, planting and wayfinding all have collision.

var destinations: Array[Dictionary] = []
var solid_count := 0

func build(city: Node3D) -> void:
	var before: int = city.solids.size()
	for side in [-1,1]:
		build_side_court(city,side)
		avenue_inlays(city,side)
		build_north_court(city,side)
	build_south_court(city)
	south_inlays(city)
	solid_count = city.solids.size()-before

func build_north_court(city: Node3D, side: int) -> void:
	# The northern corners have their own quiet garden pockets, between the
	# original office blocks and the solid outer row. Keep the civic spine free.
	city.block(Vector3(side*43.0,0.08,-72),Vector3(14.4,0.16,13),"NorthGardenCourt")
	city.tree(Vector3(side*47.0,0.16,-75))
	for z in [-70.0,-74.0]:
		seat(city,Vector3(side*39.2,0.16,z),-side)
	lamp(city,Vector3(side*48.5,0.16,-67.3),-side)
	wayfinder(city,Vector3(side*48.0,0.16,-70),side,false)
	for z in range(-78,-65,2):
		paint(city,Vector3(side*36.2,0.174,z),Vector3(side*49.8,0.174,z))
	for x in range(36,51,2):
		paint(city,Vector3(side*x,0.174,-78.1),Vector3(side*x,0.174,-65.9))
	# The clear cross street stitches the gardens to the side promenades. Its
	# north-side line passes behind every old block without cutting their walls.
	for z in [-61.0,-64.0]:
		paint(city,Vector3(side*33.0,0.018,z),Vector3(side*70.0,0.018,z))
	for x in range(34,71,3):
		paint(city,Vector3(side*x,0.018,-64),Vector3(side*x,0.018,-61))
	var point := Vector3(side*43.0,0.16,-71.5)
	var title := "North-East Garden" if side>0 else "North-West Garden"
	destinations.append({"name":title,"point":point})
	city.routes.append({"tag":title,"point":point})
	city.routes.append({"tag":"NorthGardenApproach","point":Vector3(side*43.0,0,-62.5)})
	city.routes.append({"tag":"NorthOuterStreet","point":Vector3(side*68.0,0,-62.5)})

func build_side_court(city: Node3D, side: int) -> void:
	var center := Vector3(side*69.0,0.08,38)
	# These pockets fit between the original block and the outer skyline. Their
	# low, flush-edged decks remain open on every side, with no entrance rail.
	city.block(center,Vector3(6.4,0.16,16),"QuarterCourt")
	for z in [32.0,44.0]:
		city.tree(Vector3(side*70.0,0.16,z))
	for z in [35.8,40.2]:
		seat(city,Vector3(side*67.1,0.16,z),-side)
	for z in [35.0,41.0]:
		lamp(city,Vector3(side*71.6,0.16,z),-side)
	wayfinder(city,Vector3(side*71.2,0.16,38),side)
	var point := Vector3(side*68.7,0.16,38)
	var title := "East Lantern Court" if side>0 else "West Lantern Court"
	destinations.append({"name":title,"point":point})
	city.routes.append({"tag":title,"point":point})
	# Distinct entrance tiles and a two-metre inlay rhythm make the small courts
	# read as finished destinations while keeping the central walking strip open.
	for z in range(31,46,2):
		paint(city,Vector3(side*66.1,0.174,z),Vector3(side*71.9,0.174,z))
	for x: float in [66.2,68.0,69.8,71.6]:
		paint(city,Vector3(side*x,0.174,30.3),Vector3(side*x,0.174,45.7))
	# The outer-side promenade is a continuous clear route to both courts.
	for z in range(14,66,4):
		paint(city,Vector3(side*67.0,0.018,z),Vector3(side*69.8,0.018,z))
	for x: float in [67.0,69.8]:
		paint(city,Vector3(side*x,0.018,14),Vector3(side*x,0.018,29.7))
		paint(city,Vector3(side*x,0.018,46.3),Vector3(side*x,0.018,65))
	city.routes.append({"tag":"OuterPromenade","point":Vector3(side*68.4,0,18)})
	city.routes.append({"tag":"OuterPromenade","point":Vector3(side*68.4,0,58)})

func build_south_court(city: Node3D) -> void:
	city.block(Vector3(0,0.08,77),Vector3(26,0.16,18),"SouthArrivalCourt")
	for side in [-1,1]:
		city.tree(Vector3(side*10.0,0.16,81))
		seat(city,Vector3(side*9.4,0.16,74.3),side)
		lamp(city,Vector3(side*11.3,0.16,70.3),-side)
		# Paired closed, solid steles frame the south arrival rather than obstruct
		# the main road. The broad opening is eight metres across at ground level.
		var at := Vector3(side*5.7,0.16,83.5)
		city.block(at+Vector3.UP*0.18,Vector3(1.7,0.36,1.7),"SouthGatePlinth")
		city.block(at+Vector3.UP*2.45,Vector3(0.38,4.5,0.5),"SouthGateStele")
		city.beam(at+Vector3(side*0.04,4.7,0),at+Vector3(side*1.5,5.4,0),0.14,"SouthGateCrown")
		var cell = city.cell_for(at)
		# An infinity motif is engraved on the actual stele face, not floating
		# scene geometry. It stays cyan because the steles are not luminaires.
		for i in range(24):
			var a := i*TAU/24.0
			var b := (i+1)*TAU/24.0
			cell.edges.append_array([at+Vector3(0.145*cos(a),3.3+0.2*sin(a*2),-0.258),at+Vector3(0.145*cos(b),3.3+0.2*sin(b*2),-0.258)])
	for z in range(69,86,2):
		paint(city,Vector3(-12.6,0.174,z),Vector3(12.6,0.174,z))
	for x in range(-12,13,2):
		paint(city,Vector3(x,0.174,68.4),Vector3(x,0.174,85.6))
	var point := Vector3(0,0.16,77)
	destinations.append({"name":"South Arrival Court","point":point})
	city.routes.append({"tag":"SouthArrivalCourt","point":point})
	for side in [-1,1]:
		city.routes.append({"tag":"SouthGardenSeat","point":Vector3(side*7.9,0.16,74.3)})

func seat(city: Node3D, at: Vector3, back_side: int) -> void:
	# Cyan seats deliberately have no orange trim: orange is reserved for the
	# neighbouring working fixtures, whose actual local lights are bounded.
	city.block(at+Vector3.UP*0.62,Vector3(0.75,0.16,1.9),"QuarterBenchSeat")
	city.block(at+Vector3(back_side*0.32,1.02,0),Vector3(0.10,0.72,1.9),"QuarterBenchBack")
	for z in [-0.65,0.65]:
		city.block(at+Vector3(0,0.28,z),Vector3(0.50,0.56,0.12),"QuarterBenchLeg")

func lamp(city: Node3D, at: Vector3, toward: int) -> void:
	city.block(at+Vector3.UP*0.12,Vector3(0.65,0.24,0.65),"QuarterLampFoot")
	city.block(at+Vector3.UP*2.65,Vector3(0.13,5.1,0.13),"QuarterLampPost")
	city.beam(at+Vector3.UP*5.2,at+Vector3(toward*1.6,5.65,0),0.11,"QuarterLuminaire",true)
	city.light_at(at+Vector3(toward*1.0,5.35,0),4.3,0.85)

func wayfinder(city: Node3D, at: Vector3, side: int, approach_arrow: bool = true) -> void:
	city.block(at+Vector3.UP*0.12,Vector3(0.65,0.24,0.65),"QuarterWayfinderFoot")
	city.block(at+Vector3.UP*1.50,Vector3(0.10,2.9,0.10),"QuarterWayfinderPost")
	city.block(at+Vector3(-side*0.3,2.2,0),Vector3(0.85,1.05,0.10),"QuarterWayfinderPanel")
	var face := at+Vector3(-side*0.3,2.2,-0.058)
	for y in [-0.23,0.0,0.23]:
		paint(city,face+Vector3(-0.26,y,0),face+Vector3(0.26,y,0))
	if not approach_arrow: return
	# Ground arrows turn pedestrians off the avenue into the outer promenade.
	var foot := Vector3(side*64.5,0.018,8)
	paint(city,foot+Vector3(0,0,-1),foot+Vector3(0,0,1.5))
	paint(city,foot+Vector3(0,0,1.5),foot+Vector3(-0.5,0,0.8))
	paint(city,foot+Vector3(0,0,1.5),foot+Vector3(0.5,0,0.8))

func avenue_inlays(city: Node3D, side: int) -> void:
	# Extend the same grid language around the full cross-shaped street. These
	# are flush painted seams and never introduce physical lips into the road.
	for along in range(14,71,2):
		paint(city,Vector3(side*along,0.018,-8.8 if along>=32 else 0),Vector3(side*along,0.018,8.8))
	for z in range(-8,9,2):
		paint(city,Vector3(side*(32.2 if z<0 else 12.2),0.018,z),Vector3(side*70.0,0.018,z))
	# Two narrow directional dashes identify the route to the civic centre.
	for along in [20,36,52,66]:
		var tip := Vector3(side*along,0.022,4)
		paint(city,tip,tip+Vector3(side*0.8,0,-0.55))
		paint(city,tip,tip+Vector3(side*0.8,0,0.55))
	city.routes.append({"tag":"EastWestAvenue","point":Vector3(side*40.0,0,0)})

func south_inlays(city: Node3D) -> void:
	for along in range(14,68,2):
		paint(city,Vector3(-9.6,0.018,along),Vector3(9.6,0.018,along))
	for x in range(-8,9,2):
		paint(city,Vector3(x,0.018,12.2),Vector3(x,0.018,67.7))
	# An outer cross street connects both side courts with the south garden.
	for x in range(-68,69,4):
		paint(city,Vector3(x,0.018,72.8),Vector3(x,0.018,76.4))
	for z in [72.8,76.4]:
		paint(city,Vector3(-70,0.018,z),Vector3(-13.3,0.018,z))
		paint(city,Vector3(13.3,0.018,z),Vector3(70,0.018,z))
	city.routes.append({"tag":"SouthAvenue","point":Vector3(0,0,42)})
	for side in [-1,1]:
		city.routes.append({"tag":"SouthCrossStreet","point":Vector3(side*44,0,74.6)})

func paint(city: Node3D, a: Vector3, b: Vector3) -> void:
	city.cell_for((a+b)*0.5).edges.append_array([a,b])
