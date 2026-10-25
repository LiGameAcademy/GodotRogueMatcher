shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(0.96, 0.78, 0.36, 1.0);
uniform float outline_width = 1.6;
uniform float energy = 0.0;

void fragment() {
	// Texture is the body only; threshold excludes faint source-alpha residue.
	float center = smoothstep(0.20, 0.45, texture(TEXTURE, UV).a);
	float nearby = 0.0;
	vec2 step_size = vec2((outline_width + energy * 0.4) / 64.0);
	for (int i = 0; i < 16; i++) {
		float angle = float(i) * 6.2831853 / 16.0;
		vec2 sample_uv = UV + vec2(cos(angle), sin(angle)) * step_size;
		nearby = max(nearby, smoothstep(0.20, 0.45, texture(TEXTURE, sample_uv).a));
	}
	COLOR = vec4(outline_color.rgb, max(nearby - center, 0.0) * (0.60 + energy * 0.32));
}
