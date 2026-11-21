shader_type spatial;
render_mode unshaded, cull_disabled;
uniform bool outer_unlocked=true;
varying vec3 world_point;
void vertex() { world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	if (!outer_unlocked && max(abs(world_point.x),abs(world_point.z))>128.0) { discard; }
	ALBEDO=COLOR.rgb;
}
