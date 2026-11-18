extends RefCounted
## Original scale apron and weathered split cloth, using the shared cloth rig.
## Built only on equip; both flexible halves carry their own batched scales.
const Surface = preload("res://scripts/garment_surface.gd")

static func build(garment: Node3D) -> void:
	var belt: Node3D=garment.node(garment.figure.pelvis,"VoidSoulGirdle")
	var b:=Surface.new()
	b.loft([Vector3(.249,-.015,.157),Vector3(.246,.052,.155)],0,Vector3.ZERO,8)
	b.quad(Vector3(-.036,.019,.163),Vector3(0,.062,.169),Vector3(.036,.019,.163),Vector3(0,-.025,.169),true)
	b.line([Vector3(0,.048,.172),Vector3(-.018,.019,.174),Vector3(0,-.01,.172),Vector3(.018,.019,.174),Vector3(0,.048,.172)],true)
	garment.finish(b,belt,"VoidClaspAndBelt")
	# Four long outer folds leave the front and back scale aprons visible.
	for i in range(4):
		var angle: float=[.95,2.3,3.983185,5.333185][i]
		garment.panel("VoidSoulOuterFold"+str(i),.78 if i in [0,3] else .84,angle,.56,.251,.159,true,false)
	for i in range(2):
		var angle: float=i*PI
		var length:=.62 if i==0 else .69
		garment.panel("VoidSoulScaleApron"+str(i),length,angle,.43,.247,.159,true,false)
		var tail: Node3D=garment.tails[-1]
		for lower in [false,true]: scales(garment,tail,angle,length,lower)

static func cloth_point(t: float, angle: float, length: float) -> Vector3:
	var flare:=1+t*.62
	return Vector3(sin(angle)*(.247*flare+.017),-t*length,cos(angle)*(.159*flare+.017))

static func scales(garment: Node3D, tail: Node3D, angle: float, length: float, lower: bool) -> void:
	var b:=Surface.new()
	var parent: Node3D=tail.get_meta("bend") if lower else tail
	var pivot: Vector3=tail.get_meta("seam")
	if lower: pivot+=parent.position
	var rows: Array=[.465,.635,.805] if lower else [.035,.205]
	for row in range(rows.size()):
		var t: float=rows[row]
		for column in range(3):
			var a:=angle+(column-1)*.235+(row%2)*.025
			var points: Array[Vector3]=[
				cloth_point(t,a-.10,length)-pivot,
				cloth_point(t,a+.10,length)-pivot,
				cloth_point(t+.075,a+.12,length)-pivot,
				cloth_point(t+.16,a,length)-pivot,
				cloth_point(t+.075,a-.12,length)-pivot]
			var ridge:=cloth_point(t+.07,a,length)-pivot+Vector3(sin(a),0,cos(a))*.012
			for edge in range(5): b.faces.append_array([ridge,points[edge],points[(edge+1)%5]])
			b.line([points[0],points[1],points[2],points[3],points[4],points[0]],true)
			b.line([(points[0]+points[1])*.5,ridge,points[3]])
	# A hint of the variant color inside the dark scales, with luminous edges.
	b.finish(parent,"VoidSoulLappedScales",garment.fabric.lerp(garment.ink,.055),garment.trim,garment.ink)
