extends Node3D
## Scribe-derived fitted garments: shaped torso, joint sleeves, layered plate,
## split hems and mount-aware cloth. All geometry is built only on equip.
const Surface = preload("res://scripts/garment_surface.gd")
var figure: Node3D
var external: Array[Node3D] = []
var tails: Array[Node3D] = []
var profile: Dictionary
var ink := Color("75eaff")
var trim := Color("bcd8e1")
var fabric := Color("0b111b")
var _time := 0.0
var _flow := 0.0
var _turn := 0.0
var _inertia := Vector3.ZERO
var _previous_velocity := Vector3.ZERO
var _previous_yaw := 0.0
var _motion_initialized := false
var _mounted_kind := ""

func node(parent: Node3D,label: String) -> Node3D:
	var piece := Node3D.new()
	piece.name = label
	parent.add_child(piece)
	external.append(piece)
	return piece

func finish(builder: RefCounted,parent: Node3D,label: String,plate: bool = false) -> void:
	builder.finish(parent,label,fabric.lightened(.045) if plate else fabric,trim,ink)

func configure(visual: Node3D, entry: Dictionary) -> void:
	figure = visual
	profile = entry.geometry.tailoring
	ink = Color(entry.geometry.tint)
	fabric = Color(String(profile.get("fabric","0b111b")))
	name = "Tailored_"+String(entry.id)
	match String(entry.family):
		"body": body()
		"head": head()
		"hands": hands()
		"legs": legs()
	process_priority = 41
	set_process(not tails.is_empty())

func body() -> void:
	var root := node(figure.chest,"FittedChestAndLappedWaist")
	var b := Surface.new()
	var waist := float(profile.waist)
	var chest := float(profile.chest)
	var depth := float(profile.depth)
	var cloth: bool = profile.cut=="cloth"
	var rows: Array = [Vector3(waist,.0,depth*.80),Vector3(waist*.96,.13,depth*.87),Vector3(chest*.91,.32,depth),Vector3(chest,.46,depth*.91),Vector3(.15,.53,.105)]
	var contour: Array = profile.get("contour",[1,1,1,1,1])
	for i in range(1,4): rows[i].x *= lerpf(1.0,float(contour[i]),.30)
	if profile.bare: rows = [Vector3(chest*.9,.33,depth*.9),Vector3(chest,.44,depth),Vector3(.17,.50,.11)]
	b.loft(rows,.22 if cloth else .0,Vector3.ZERO,6)
	if not cloth:
		# A convex breastplate, overlapping abdominal lames and a raised gorget.
		for i in range(int(profile.layers)):
			var y := .04+i*.065
			var radius := lerpf(waist,chest*.85,i/float(profile.layers))+.012
			b.loft([Vector3(radius,y,depth*.92),Vector3(radius*.98,y+.045,depth*.91)],0,Vector3.ZERO,2)
		if profile.ridge:
			for side: float in [-1,1]:
				b.line([Vector3(side*chest*.72,.43,depth*.6),Vector3(side*.075,.29,depth*1.08),Vector3(0,.18,depth)],true)
	# High split collar is the same fitted construction as the Scribe lapels.
	b.loft([Vector3(.115,.49,.105),Vector3(.13,.59,.115)],.62,Vector3.ZERO,2)
	if profile.get("scarf",false):
		b.loft([Vector3(.16,.43,.14),Vector3(.145,.56,.125)],.35,Vector3.ZERO,5)
	if profile.mantle:
		b.loft([Vector3(.13,.55,.11),Vector3(chest*1.28,.37,depth*1.3)],.38,Vector3.ZERO,6)
	# Belt and articulated tassets, with a bright central clasp rather than a slab.
	b.loft([Vector3(waist+.014,-.025,depth*.84),Vector3(waist+.014,.018,depth*.84)],0,Vector3.ZERO,0)
	b.line([Vector3(-.035,-.015,depth*.85+.004),Vector3(-.035,.02,depth*.85+.004),Vector3(.035,.02,depth*.85+.004),Vector3(.035,-.015,depth*.85+.004),Vector3(-.035,-.015,depth*.85+.004)],true)
	if profile.ornate:
		for side: float in [-1,1]:
			b.line([Vector3(side*.14,.41,depth*.92),Vector3(side*.07,.32,depth*1.02),Vector3(side*.1,.23,depth*.98)],true)
	finish(b,root,"TailoredTorso",not cloth)
	for side: String in ["Left","Right"]:
		if profile.bare: continue
		var arm: Node3D = figure.joints[side+"Arm"]
		for part in range(2):
			var sleeve := node(arm if part==0 else arm.get_node("Hinge"),side+"ArticulatedSleeve"+str(part))
			b = Surface.new()
			var radius := .07 if cloth else .079
			b.loft([Vector3(radius,.0,radius*.93),Vector3(radius*1.08,-.12,radius),Vector3(radius*.78,-.265,radius*.78)],0,Vector3.ZERO,2)
			if part==0:
				var shoulder := float(profile.shoulder)*(1.12 if profile.asymmetric and side=="Left" else 1.0)
				b.loft([Vector3(.04,.06,.06),Vector3(shoulder,.0,shoulder*.9),Vector3(shoulder*.96,-.105,shoulder*.82)],.6,Vector3.ZERO,4)
				if not cloth:
					for i in range(2): b.loft([Vector3(shoulder*.9,-.10-i*.04,shoulder*.78),Vector3(shoulder*.84,-.13-i*.04,shoulder*.74)],.6,Vector3.ZERO,1)
			finish(b,sleeve,"ShapedSleeveAndPauldron",not cloth)
	# Individual panels have curved depth, seams, pleats and independently
	# moving roots. Their layout follows the reference cut, never a front board.
	for i in range(6):
		var angle := .34+(TAU-.68)*(i+.5)/6.0
		panel("SplitHem"+str(i),float(profile.hem),angle,.42,waist+.008,depth*.84,bool(profile.ragged),false)
	if float(profile.cape)>0:
		for i in range(3): panel("ShoulderCape"+str(i),float(profile.cape),PI+(i-1)*.5,.34,.22,.16,bool(profile.ragged),true)
	if float(profile.get("tabard",0))>0:
		for angle: float in [.0,PI]: panel("LappedTabard"+str(angle),float(profile.tabard),angle,.31,waist+.016,depth*.91,false,false)

func panel(label: String,length: float,angle: float,half_width: float,rx: float,rz: float,ragged: bool,cape: bool) -> void:
	var tail := node(self,label)
	tails.append(tail)
	tail.set_meta("cape",cape)
	tail.set_meta("angle",angle)
	tail.set_meta("length",length)
	var seam := Vector3(sin(angle)*rx,0,cos(angle)*rz)
	tail.set_meta("seam",seam)
	# A cape remains flexible over a plated cuirass. Short metal tassets follow
	# the legs as articulated pieces, without the extra fabric bend or flutter.
	var flexible: bool = cape or String(profile.cut)=="cloth" or label.begins_with("LappedTabard") or (ragged and length>.4)
	tail.set_meta("flexible",flexible)
	tail.set_meta("cloth_angles",Vector3.ZERO)
	if flexible:
		var bend := Node3D.new()
		bend.name = "FreeHemBend"
		tail.add_child(bend)
		var bend_seam := _panel_point(.45,angle,rx,rz,length)-seam
		bend.position = bend_seam
		tail.set_meta("bend",bend)
		tail.set_meta("bend_angles",Vector3.ZERO)
		_panel_band(tail,label+"UpperFabric",0,.45,angle,half_width,rx,rz,length,ragged,seam)
		_panel_band(bend,label+"FreeFabric",.45,1,angle,half_width,rx,rz,length,ragged,seam+bend_seam)
	else:
		_panel_band(tail,label+"Fabric",0,1,angle,half_width,rx,rz,length,ragged,seam)

func _panel_point(t: float,angle: float,rx: float,rz: float,length: float) -> Vector3:
	return Vector3(sin(angle)*rx*(1+t*.62),-t*length,cos(angle)*rz*(1+t*.62))

func _panel_band(parent: Node3D,label: String,start: float,end: float,angle: float,half_width: float,rx: float,rz: float,length: float,ragged: bool,pivot: Vector3) -> void:
	var b := Surface.new()
	var grid: Array = []
	for row in range(3):
		var t := lerpf(start,end,row/2.0)
		for column in range(5):
			var a := angle+(column/4.0-.5)*half_width*2
			var flare := 1+t*.62
			var pleat := sin(column*PI)*.008+cos(column*PI)*.007*t
			var y: float = -t*length+(0.045 if ragged and is_equal_approx(t,1) and column%2==1 else 0)
			grid.append(Vector3(sin(a)*(rx*flare+pleat),y,cos(a)*(rz*flare+pleat))-pivot)
	for row in range(2):
		for column in range(4):
			var j := row*5+column
			b.quad(grid[j],grid[j+1],grid[j+6],grid[j+5])
	b.line([grid[0],grid[4],grid[9],grid[14],grid[13],grid[12],grid[11],grid[10],grid[5],grid[0]])
	b.line([grid[2],grid[7],grid[12]],true)
	if profile.ornate:
		b.line([grid[11],(grid[11]+grid[13])*.5+Vector3(0,-.04,.003),grid[13]],true)
	finish(b,parent,label)

func head() -> void:
	var root := node(figure.chest,"FittedHeadpiece")
	var b := Surface.new()
	var hood: bool = profile.hood
	if profile.get("mimic",false):
		# A volumetric coffer headpiece with hinged-looking upper/lower jaws.
		for y: float in [.68,.86]:
			var a := Vector3(-.23,y,-.18)
			var c := Vector3(.23,y+.10,.19)
			b.quad(a,Vector3(c.x,a.y,a.z),Vector3(c.x,c.y,a.z),Vector3(a.x,c.y,a.z),true)
			b.quad(a,Vector3(a.x,a.y,c.z),Vector3(a.x,c.y,c.z),Vector3(a.x,c.y,a.z),true)
			b.quad(Vector3(c.x,a.y,a.z),Vector3(c.x,a.y,c.z),c,Vector3(c.x,c.y,a.z),true)
			b.quad(Vector3(a.x,c.y,a.z),Vector3(c.x,c.y,a.z),c,Vector3(a.x,c.y,c.z),true)
		for i in range(7):
			var x := -.18+i*.06
			b.quad(Vector3(x-.02,.86,.195),Vector3(x+.02,.86,.195),Vector3(x,.80,.19),Vector3(x-.02,.86,.195),true)
	elif profile.crown:
		b.loft([Vector3(.167,.79,.163),Vector3(.17,.84,.165)],0,Vector3.ZERO,0)
		for i in range(8):
			var a := i*TAU/8
			b.quad(b.point(Vector3(.17,.83,.165),a-.12),b.point(Vector3(.17,.83,.165),a+.12),b.point(Vector3(.176,.92,.171),a),b.point(Vector3(.17,.83,.165),a-.12),true)
	elif profile.mask:
		b.loft([Vector3(.14,.71,.145),Vector3(.16,.83,.165)],PI*.55,Vector3.ZERO,2)
		root.rotation.y = PI
	else:
		var width := .20 if hood else .175
		b.loft([Vector3(width*.9,.63,.155),Vector3(width,.79,.18),Vector3(width*.85,.94,.145),Vector3(.025,.99,.025)],.92 if hood else .16,Vector3.ZERO,5)
		if profile.visor and not hood:
			for y: float in [.75,.80]: b.line([Vector3(-.11,y,.15),Vector3(0,y-.008,.185),Vector3(.11,y,.15)])
			b.line([Vector3(0,.68,.16),Vector3(0,.76,.188)],true)
		if profile.hat:
			b.loft([Vector3(.31,.91,.28),Vector3(.30,.925,.27)],0,Vector3.ZERO,1)
			b.loft([Vector3(.17,.92,.16),Vector3(.13,1.10,.12),Vector3(.012,1.27,.015)],0,Vector3(.04,0,-.03),3)
		if profile.crest:
			b.quad(Vector3(0,.93,-.16),Vector3(0,.98,.10),Vector3(0,1.13,-.04),Vector3(0,1.07,-.18),true)
		if profile.horns:
			for side: float in [-1,1]:
				b.quad(Vector3(side*.14,.87,0),Vector3(side*.21,.90,.04),Vector3(side*.28,1.10,-.08),Vector3(side*.18,.98,-.05),true)
	finish(b,root,"ContouredHoodOrHelm",not hood)

func hands() -> void:
	for side: String in ["Left","Right"]:
		var root := node(figure.joints[side+"Arm"].get_node("Hinge"),side+"LayeredGauntlet")
		var b := Surface.new()
		b.loft([Vector3(.09,-.055,.085),Vector3(.075,-.13,.073),Vector3(.057,-.27,.063)],0,Vector3.ZERO,4)
		for i in range(int(profile.layers)):
			var y := -.14-i*.045
			b.loft([Vector3(.071,y,.076),Vector3(.065,y-.032,.068)],.5,Vector3.ZERO,1)
		finish(b,root,"FittedCuffAndWrist",profile.cut!="cloth")

func legs() -> void:
	for side: String in ["Left","Right"]:
		for part in range(2):
			var joint: Node3D = figure.joints[side+"Leg"]
			if part==1: joint=joint.get_node("Hinge")
			var root := node(joint,side+"ArticulatedGreave"+str(part))
			var b := Surface.new()
			b.loft([Vector3(.10,0,.105),Vector3(.105,-.15,.10),Vector3(.075,-.40,.085)],0,Vector3.ZERO,4)
			if part==1:
				b.loft([Vector3(.09,.025,.095),Vector3(.115,-.04,.13),Vector3(.095,-.11,.105)],.7,Vector3.ZERO,2)
				# Fitted sabot, raised toe and ankle; it ends above the floor.
				b.loft([Vector3(.07,-.32,.08),Vector3(.075,-.405,.16),Vector3(.07,-.43,.17)],0,Vector3(0,0,.055),3)
			finish(b,root,"ContouredLegPlate",profile.cut!="cloth")

func _process(delta: float) -> void:
	if not is_instance_valid(figure): return
	_time += delta
	var actor: Node = figure.get_parent()
	var actions: Node = actor.get("world_actions")
	var vehicle: Node = actions.vehicle if is_instance_valid(actions) else null
	var mounted_kind: String = vehicle.kind if is_instance_valid(vehicle) else ""
	var motion: Vector3 = vehicle.velocity if is_instance_valid(vehicle) else actor.velocity if actor is CharacterBody3D else Vector3.ZERO
	var changed_mount := mounted_kind!=_mounted_kind
	_mounted_kind = mounted_kind
	var figure_basis: Basis = figure.global_basis.orthonormalized()
	var yaw := figure.global_rotation.y
	if not _motion_initialized or changed_mount:
		_previous_velocity = motion
		_previous_yaw = yaw
		_inertia = Vector3.ZERO
		_turn = 0
		_motion_initialized = true
	var local_motion := figure_basis.inverse()*motion
	var acceleration := Vector3.ZERO
	var angular_speed := 0.0
	if delta>0:
		acceleration = (figure_basis.inverse()*(motion-_previous_velocity)/delta/28.0).limit_length(1)
		angular_speed = clampf(wrapf(yaw-_previous_yaw,-PI,PI)/delta*.10,-.45,.45)
	_previous_velocity = motion
	_previous_yaw = yaw
	var speed := Vector2(motion.x,motion.z).length()
	var target_flow := clampf(speed/14.0+absf(motion.y)*.006,0,1)
	_flow = lerpf(_flow,target_flow,1-exp(-6*delta))
	_inertia = _inertia.lerp(acceleration,1-exp(-6*delta))
	_turn = lerpf(_turn,angular_speed,1-exp(-8*delta))
	# Flow opposes travel, including backpedaling and strafing. The mounted
	# saddle fold below intentionally remains rearward even while reversing.
	var trail_forward := _flow*clampf(local_motion.z/maxf(speed,.1),-1,1)
	var trail_side := _flow*clampf(local_motion.x/maxf(speed,.1),-1,1)
	for i in range(tails.size()):
		var tail := tails[i]
		var cape: bool = tail.get_meta("cape")
		var flexible: bool = tail.get_meta("flexible")
		tail.visible = mounted_kind in ["","motorcycle"]
		var origin: Node3D = figure.chest if cape else figure.pelvis
		var relative_basis := global_basis.inverse()*origin.global_basis
		var orientation_basis := relative_basis
		var anchor := to_local(origin.global_position)
		if cape: anchor += relative_basis*Vector3(0,.43,0)
		var seam: Vector3 = tail.get_meta("seam")
		# The sewn edge stays on its own hip/shoulder seam. Geometry was built
		# relative to this pivot, so leaning never sweeps the attachment inward.
		tail.position = anchor+relative_basis*seam
		var leg_pitch := 0.0
		var leg_roll := 0.0
		if not cape:
			var leg: Node3D = figure.joints.RightLeg if seam.x>0 else figure.joints.LeftLeg
			var thigh: Vector3 = origin.global_basis.inverse()*(leg.global_basis*Vector3.DOWN)
			var pitch := atan2(-thigh.z,-thigh.y)
			var front: bool = cos(float(tail.get_meta("angle")))>=0
			leg_pitch = (minf(pitch,0)*.82 if front else maxf(pitch,0)*.72)
			leg_roll = atan2(thigh.x,-thigh.y)*.40
		var flutter := sin(_time*(3.3+_flow*5)+i*1.7)*_flow*.045 if flexible else 0.0
		var flexibility := 1.0 if flexible else .12
		var angles_target := Vector3(
			leg_pitch+(trail_forward*(.34 if cape else .22)+_inertia.z*.09+flutter)*flexibility,
			-_turn*(.65 if cape else .38)*flexibility,
			leg_roll+(-trail_side*.14-_inertia.x*.09+flutter*.5)*flexibility)
		if mounted_kind=="motorcycle":
			# Match the Scribe treatment: fold over the belt, then stream behind
			# the saddle above the rear wheel, even when the bike is stationary.
			angles_target = Vector3(1.50+_flow*.08+flutter*.3,-_turn*.15,flutter*.15)
			tail.position += relative_basis*Vector3(0,.065,0)
			# The shoulder seam follows the leaned chest, but its free fabric
			# streams in the hip frame. Adding the chest lean again would turn a
			# horizontal cape into a vertical flag behind the rider's head.
			if cape: orientation_basis=global_basis.inverse()*figure.pelvis.global_basis
		var previous: Vector3 = tail.get_meta("cloth_angles")
		var angles := angles_target if changed_mount else previous.lerp(angles_target,1-exp(-(10 if flexible else 20)*delta))
		tail.set_meta("cloth_angles",angles)
		var hem := float(tail.get_meta("length"))
		var clearance := 1.0
		if mounted_kind.is_empty() and actor is CharacterBody3D and actor.is_on_floor():
			clearance=clampf((to_global(anchor).y-actor.global_position.y-.08)/maxf(.1,hem),.4,1)
		tail.basis = orientation_basis*Basis.from_euler(angles).scaled(Vector3(1,clearance,1))
		if flexible:
			var bend: Node3D = tail.get_meta("bend")
			var tip_target := Vector3(trail_forward*.25+_inertia.z*.16+flutter*1.7,-_turn*.4,-trail_side*.11-_inertia.x*.13+flutter*.7)
			if mounted_kind=="motorcycle": tip_target.x = .06+_flow*.04+flutter*.3
			var bend_previous: Vector3 = tail.get_meta("bend_angles")
			var bend_angles := tip_target if changed_mount else bend_previous.lerp(tip_target,1-exp(-7*delta))
			tail.set_meta("bend_angles",bend_angles)
			bend.basis = Basis.from_euler(bend_angles)

func _exit_tree() -> void:
	for piece in external:
		if is_instance_valid(piece) and piece.get_parent()!=self: piece.queue_free()
