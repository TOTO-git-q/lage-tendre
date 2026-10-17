shader_type canvas_item;
render_mode blend_add;

// The existing repository texture supplies UV coordinates only. All visible
// ring geometry is procedural; vertex color carries the declared note opacity.
varying vec4 ring_color;
void vertex() {
    ring_color = COLOR;
}
void fragment() {
    float radius = length(UV - vec2(0.5));
    float core = exp(-pow((radius - 0.37) / 0.018, 2.0));
    float halo = 0.25 * exp(-pow((radius - 0.37) / 0.075, 2.0));
    COLOR = vec4(ring_color.rgb, ring_color.a * (core + halo));
}
