shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 signal_color : source_color = vec4(0.25, 0.85, 0.7, 1.0);
uniform float scan_strength = 0.03;
uniform float rim_strength = 0.2;
uniform float sweep_strength = 0.08;
uniform float phase = 0.0;
uniform float response = 0.0;

float chroma(vec3 c) {
	return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b));
}

void fragment() {
	vec4 source = textureLod(screen_texture, SCREEN_UV, 0.0);
	vec2 pixel = SCREEN_PIXEL_SIZE;
	float nearby = max(max(chroma(textureLod(screen_texture, SCREEN_UV + vec2(pixel.x, 0.0), 0.0).rgb),
		chroma(textureLod(screen_texture, SCREEN_UV - vec2(pixel.x, 0.0), 0.0).rgb)),
		max(chroma(textureLod(screen_texture, SCREEN_UV + vec2(0.0, pixel.y), 0.0).rgb),
		chroma(textureLod(screen_texture, SCREEN_UV - vec2(0.0, pixel.y), 0.0).rgb)));
	float rim = clamp(nearby - chroma(source.rgb), 0.0, 1.0) * rim_strength;
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 1.5707963);
	float band = exp(-abs(UV.y - phase) * 160.0);
	vec3 color = source.rgb * (1.0 - scan * scan_strength);
	color = mix(color, signal_color.rgb, rim + band * (sweep_strength + response));
	COLOR = vec4(color, source.a);
}
