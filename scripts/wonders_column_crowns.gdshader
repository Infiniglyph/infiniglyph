shader_type spatial;
render_mode unshaded, cull_disabled;
void vertex() {
	float a=TIME*0.22+INSTANCE_CUSTOM.x;
	float c=cos(a); float s=sin(a);
	VERTEX=mat3(vec3(c,0.0,-s),vec3(0.0,1.0,0.0),vec3(s,0.0,c))*VERTEX;
}
void fragment() { ALBEDO=COLOR.rgb; EMISSION=COLOR.rgb*2.2; }
