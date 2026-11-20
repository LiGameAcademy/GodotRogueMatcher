shader_type canvas_item;
render_mode unshaded;

uniform vec4 shadow_color : source_color = vec4(0.0, 0.0, 0.0, 0.25);

varying vec4 shadow_modulate;

void vertex() {
	shadow_modulate = COLOR;
}

void fragment() {
	// Only the body alpha is used; baked body colors and separate faces are excluded.
	float coverage = smoothstep(0.20, 0.45, texture(TEXTURE, UV).a);
	COLOR = vec4(shadow_color.rgb, shadow_color.a * coverage) * shadow_modulate;
}
