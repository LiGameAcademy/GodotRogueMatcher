shader_type canvas_item;
render_mode blend_mix;

uniform vec2 canvas_size = vec2(600.0, 22.0);
uniform float edge = 0.0;
uniform float intensity = 0.0;
uniform vec4 glow_color : source_color = vec4(0.65, 1.0, 0.9, 1.0);

void fragment() {
	vec2 offset = (UV - vec2(edge, 0.5)) * canvas_size;
	float core = exp(-dot(offset / vec2(4.0, 8.0), offset / vec2(4.0, 8.0)));
	float halo = exp(-dot(offset / vec2(20.0, 12.0), offset / vec2(20.0, 12.0)));
	COLOR = vec4(glow_color.rgb, (core + halo * 0.5) * intensity);
}
