// soft edge darkening (as the web version's radial-gradient #vig)
shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec2 d = (UV - vec2(0.5, 0.48)) / vec2(0.5, 0.52);
	float r = length(d);
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(0.55, 1.0, r) * 0.5);
}
