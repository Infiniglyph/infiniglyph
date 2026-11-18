extends RefCounted
## Stable silhouettes from item identity; previews and worn pieces share them.
static func for_item(entry: Dictionary) -> Dictionary:
	var seed_value: int=absi(String(entry.id).hash())
	var style:=seed_value%8
	var a:=float((seed_value/8)%101)/100.0
	var b:=float((seed_value/808)%97)/96.0
	return {"design":style,"design_a":a,"design_b":b,
		"cuff_length":lerpf(.15,.27,a),"cuff_width":lerpf(.076,.112,b),
		"thigh_width":lerpf(.087,.125,a),"calf_width":lerpf(.078,.108,b),
		"toe_length":lerpf(.15,.22,a),"boot_width":lerpf(.075,.105,b),
		"bands":2+int(seed_value/78376)%4}
