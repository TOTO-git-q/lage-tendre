// song-select background: the current cover, blurred, desaturated and dimmed
shader_type canvas_item;
render_mode unshaded;
uniform float radius = 14.0;
uniform float dim = 0.38;
uniform float desat = 0.5;
void fragment() {
	vec4 acc = vec4(0.0);
	float ws = 0.0;
	for (int x = -4; x <= 4; x++) {
		for (int y = -4; y <= 4; y++) {
			float w = exp(-float(x * x + y * y) / 18.0);
			acc += texture(TEXTURE, UV + vec2(float(x), float(y)) * radius * TEXTURE_PIXEL_SIZE) * w;
			ws += w;
		}
	}
	vec3 c = acc.rgb / ws;
	float g = dot(c, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(c, vec3(g), desat) * dim, 1.0);
}
