// matte film grain (additive, very faint), re-seeded ~14x per second
shader_type canvas_item;
render_mode blend_add, unshaded;
uniform float seed = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.13) * 43758.5453); }
void fragment() {
	// finer grain, and it fades out in the bright beams (grain on bright light read as dirt)
	float n = pow(hash(floor(FRAGCOORD.xy)), 1.6);
	float lum = dot(texture(screen_tex, SCREEN_UV).rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(vec3(n * 0.012 * (1.0 - smoothstep(0.08, 0.45, lum))), 1.0);
}
