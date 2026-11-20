shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D binary_atlas : filter_nearest, repeat_enable;
uniform vec4 ink : source_color = vec4(0.08, 0.95, 1.0, 1.0);
uniform vec4 second_ink : source_color = vec4(0.82, 0.18, 1.0, 1.0);
uniform vec2 density = vec2(1.0, 1.0);
uniform float flow_time = 0.0;
uniform float flow_speed = 0.045;
uniform float brightness = 1.0;

void fragment() {
	vec2 grid_uv = UV * density;
	// Independent column speeds make the digits flow through the body rather
	// than looking like a single rigid sign moving behind the merchant.
	float column = floor(grid_uv.x * 16.0);
	float rate = 0.72 + fract(sin(column * 17.71) * 137.3) * 0.64;
	grid_uv.y += flow_time * flow_speed * rate;
	float glyph = texture(binary_atlas, grid_uv).r;
	float tide = 0.67 + 0.33 * sin(UV.y * 12.0 - flow_time * 1.7 + column);
	vec3 color = mix(ink.rgb, second_ink.rgb, smoothstep(0.12, 0.92, UV.y) * 0.65);
	ALBEDO = vec3(0.003, 0.002, 0.012) + color * glyph * tide * brightness;
	EMISSION = color * glyph * tide * brightness * 1.25;
	ROUGHNESS = 1.0;
}
