extends RefCounted
## Exact critically damped spring for a constant target over each timestep.
var value := Vector3.ZERO
var velocity := Vector3.ZERO

func step(target: Vector3, frequency: float, delta: float) -> Vector3:
	var offset := value-target
	var decay := exp(-frequency*delta)
	var change := (velocity+offset*frequency)*delta
	value = target+(offset+change)*decay
	velocity = (velocity-change*frequency)*decay
	return value
