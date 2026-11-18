shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.04, 0.7, 0.85, 1.0);
uniform vec3 anchor = vec3(0.0);
varying vec3 world_point;
void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 cell = floor((world_point-anchor) / vec3(2.6, 1.25, 2.6));
	float seed = fract(sin(dot(cell, vec3(12.9898, 78.233, 39.425))) * 43758.5453);
	float height_stage = clamp(abs(world_point.y-anchor.y) / 18.0, 0.0, 1.0);
	float threshold = 0.02 + seed * 0.48 + height_stage * 0.48;
	if (progress < threshold) { discard; }
	float colored = step(0.01, length(COLOR.rgb-vec3(1.0)));
	vec3 base = mix(tint.rgb, COLOR.rgb, colored);
	float edge = 1.0-smoothstep(0.0, 0.12, progress-threshold);
	ALBEDO = mix(base, vec3(0.12, 0.95, 1.0), edge*0.8);
	EMISSION = vec3(0.02, 0.35, 0.45)*edge;
}
