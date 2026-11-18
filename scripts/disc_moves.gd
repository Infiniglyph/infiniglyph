extends RefCounted
## Close cuts borrow the existing knife/paired motion banks; throws have their
## own release and catch window. Flight distance stays seven meters when charged.
const Named = preload("res://scripts/equipment_moves.gd")

static func move(item: Dictionary, action: StringName, combo: int, aerial: bool) -> Dictionary:
	var result := Named.move(item,action,combo,aerial)
	if result.is_empty(): return result
	result.weapon_family = item.family
	var basic := action in [&"attack_left",&"attack_right"]
	if basic:
		var previous := float(result.duration)
		result.duration = .34+posmod(combo,3)*.025
		result.windup = float(result.windup)*float(result.duration)/previous
		for i in range(result.hits.size()): result.hits[i] = float(result.hits[i])*float(result.duration)/previous
		result.reach = 1.75
		result.damage = 16.0 if item.family=="dual_disc" else 19.0
		result.name = item.name+" / "+["Rim Cut","Reverse Edge","Closing Orbit"][posmod(combo,3)]
	else:
		var index := [&"special_x",&"special_y",&"special_rt_x",&"special_rt_y"].find(action)
		result.merge({"name":item.name+" / "+["Return Vector","Rising Orbit","Split Horizon","Final Orbit"][index],"disc_throw":true,"throw_range":7.0,"reach":7.0,"duration":1.3,"windup":.16,"hits":[.23],"damage":32.0+index*5.0,"arc":60.0,"motion_contact":.23/1.3,"hit_stun_level":.9,"hit_stagger":.16},true)
		result.retargeted = false
		result.motion_contact = .25
		result.motion = throw_motion(index,item.family=="dual_disc",aerial)
		result.disc_flight = index
		if index>=2:
			result.disc_gym = true
			result.name=item.name+" / "+("Cartwheel Orbit" if index==2 else "Vaulting Helix")
			result.duration=1.65
			result.windup=.30
			result.hits=[.48]
			result.motion_contact=.42
			result.motion=gym_motion(index,item.family=="dual_disc")
	return result

static func throw_motion(index: int, dual: bool, aerial: bool) -> Array:
	var raised := index==1
	var crossed := index==2
	var result: Array = []
	var hands: Array = [[.30,1.02,.20],[(-.30 if crossed else .52),1.58 if raised else 1.32,-.07],[.20,1.63 if raised else 1.27,.65],[.40,1.05,.30],[.30,1.02,.20]]
	for i in range(5):
		var right: Array = hands[i]
		var left: Array = [-float(right[0]),float(right[1]),float(right[2])] if dual else [-.30,1.03,.10]
		var turn: float = [0.0,-.38,.25,.10,0.0][i]*(-1 if crossed else 1)
		result.append({"t":[0.0,.13,.25,.68,1.0][i],"right":right,"left":left,"right_rotation":[1.45,turn,.3 if raised else -.25],"left_rotation":[1.45,-turn,.25],"hip":[0,turn*.4,0],"chest":[-.04 if aerial else .04,turn,0],"hip_offset":[0,0,0],"left_foot":[-.15,-.87,.10],"right_foot":[.15,-.87,-.10]})
	return result


static func gym_motion(index: int, dual: bool) -> Array:
	var cartwheel:=index==2
	var result: Array=[]
	for i in range(5):
		var spin: float=[0.0,-.60,-2.3,-4.8,-TAU][i]
		var right: Array=[[.30,1.02,.20],[.50,1.55,-.03],[.48,1.52 if cartwheel else 1.65,.50],[.15,1.18,.42],[.30,1.02,.20]][i]
		var left: Array=[-float(right[0]),float(right[1]),float(right[2])] if dual else [[-.30,1.03,.10],[-.30,1.43,-.05],[-.28,1.6,.18],[-.44,1.22,.10],[-.30,1.03,.10]][i]
		var drive: float=[0.0,.18,.44,.24,0.0][i]
		result.append({"t":[0.0,.20,.42,.72,1.0][i],"right":right,"left":left,"right_rotation":[1.5,.20,-.2],"left_rotation":[1.5,-.20,.2],"hip":[.08,0 if cartwheel else spin,spin if cartwheel else .12*sin(spin)],"chest":[-.12,.12*sin(spin),0],"hip_offset":[0,drive,0],"left_leg":[.2,-.1,sin(i/4.0*PI)*.9],"right_leg":[-.3,.1,-sin(i/4.0*PI)*.8],"left_knee":[-.25*sin(i/4.0*PI),0,0],"right_knee":[-.7*sin(i/4.0*PI),0,0]})
	return result
