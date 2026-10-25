shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(0.96, 0.78, 0.36, 1.0);
uniform vec4 rim_color : source_color = vec4(0.25, 0.20, 0.31, 1.0);
uniform float outline_width = 3.0;
uniform float rim_width = 1.0;
uniform float energy = 0.0;
uniform bool fuse_mark = false;

void fragment() {
	// Body alpha only: eyes/mouth never acquire a halo. Width is in the 64px piece space.
	float center = smoothstep(0.20, 0.45, texture(TEXTURE, UV).a);
	float nearby = 0.0;
	float outer = 0.0;
	float width = outline_width + energy * 0.4;
	for (int i = 0; i < 16; i++) {
		float angle = float(i) * 6.2831853 / 16.0;
		vec2 direction = vec2(cos(angle), sin(angle)) / 64.0;
		nearby = max(nearby, smoothstep(0.20, 0.45, texture(TEXTURE, UV + direction * width).a));
		outer = max(outer, smoothstep(0.20, 0.45, texture(TEXTURE, UV + direction * (width + rim_width)).a));
	}
	// Core has a continuous band; a fuse has gaps, independent of hue or animation.
	float band = 1.0;
	if (fuse_mark) {
		float phase = fract((atan(UV.y - 0.5, UV.x - 0.5) / 6.2831853 + 0.5) * 10.0);
		band = 1.0 - smoothstep(0.68, 0.78, phase);
	}
	float inner_alpha = max(nearby - center, 0.0) * outline_color.a;
	float rim_alpha = max(outer - center, 0.0) * rim_color.a;
	float alpha = max(inner_alpha, rim_alpha) * band * (0.92 + energy * 0.08);
	COLOR = vec4(mix(rim_color.rgb, outline_color.rgb, inner_alpha), alpha);
}
