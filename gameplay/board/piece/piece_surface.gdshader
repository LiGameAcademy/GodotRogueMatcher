shader_type canvas_item;
render_mode unshaded;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
varying vec2 surface_position;

void vertex() {
	surface_position = VERTEX;
}

void fragment() {
	float lighting = clamp(1.0 - surface_position.y * 0.011, 0.72, 1.18);
	float shine = max(0.0, 1.0 - length(surface_position - vec2(-6.0, -9.0)) / 22.0);
	vec3 surface = mix(COLOR.rgb * lighting, vec3(1.0), shine * 0.18);
	COLOR = vec4(mix(surface, vec3(1.0), flash * 0.55), COLOR.a);
}
