shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(1.0, 0.89, 0.55, 1.0);
uniform vec4 rim_color : source_color = vec4(0.25, 0.20, 0.31, 1.0);
uniform float outline_width = 1.8;
uniform float rim_width = 2.3;
uniform float phase = 0.0;
uniform bool fuse_mark = false;
uniform bool steady = false;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	// Sample the body alone so the face stays clean. Keep the width fixed through the pulse.
	float center = smoothstep(0.20, 0.45, texture(TEXTURE, UV).a);
	float nearby = 0.0;
	float outer = 0.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 6.2831853 / 8.0;
		vec2 direction = vec2(cos(angle), sin(angle)) / 64.0;
		nearby = max(nearby, smoothstep(0.20, 0.45, texture(TEXTURE, UV + direction * outline_width).a));
		outer = max(outer, smoothstep(0.20, 0.45, texture(TEXTURE, UV + direction * (outline_width + rim_width)).a));
	}
	// Core has a continuous band; a fuse has gaps, independent of hue or animation.
	float band = 1.0;
	if (fuse_mark) {
		// Rotate by exactly one dash per cycle, keeping the loop seam invisible.
		float segment = fract((atan(UV.y - 0.5, UV.x - 0.5) / 6.2831853 + 0.5) * 4.0 - phase);
		band = smoothstep(0.0, 0.05, segment) * (1.0 - smoothstep(0.44, 0.51, segment));
	}
	// The dark inner band separates the pale mark from the peanut's natural gold edge.
	float inner_alpha = max(nearby - center, 0.0) * rim_color.a;
	float rim_alpha = max(outer - nearby, 0.0) * outline_color.a;
	float breath = steady ? 0.5 : 0.5 - 0.5 * cos(phase * 6.2831853);
	vec3 highlight = mix(outline_color.rgb * 0.88, outline_color.rgb, breath);
	float alpha = clamp(inner_alpha + rim_alpha, 0.0, 1.0);
	vec3 rgb = mix(rim_color.rgb, highlight, rim_alpha / max(alpha, 0.001));
	COLOR = vec4(rgb, alpha * band) * tint;
}
