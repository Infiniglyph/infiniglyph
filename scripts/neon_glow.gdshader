shader_type canvas_item;
render_mode blend_add;

// One Compatibility-friendly screen pass, before the HUD. No Forward+ switch.
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float glow_strength : hint_range(0.0, 1.5) = 0.8;

void fragment() {
	vec3 near_light = textureLod(scene_color, SCREEN_UV, 1.5).rgb;
	vec3 far_light = textureLod(scene_color, SCREEN_UV, 3.0).rgb;
	vec3 light = near_light * 0.7 + far_light * 0.3;
	float intensity = max(light.r, max(light.g, light.b));
	COLOR = vec4(light * smoothstep(0.025, 0.24, intensity) * glow_strength, 1.0);
}
