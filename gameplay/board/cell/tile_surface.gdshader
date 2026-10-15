shader_type canvas_item;
render_mode unshaded;
uniform vec4 edge_color : source_color = vec4(0.16, 0.23, 0.31, 1.0);
uniform float rounding : hint_range(0.0, 0.2) = 0.065;

void fragment() {
	vec2 q = abs(UV - vec2(0.5)) - vec2(0.47 - rounding);
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - rounding;
	float mask = 1.0 - smoothstep(-0.004, 0.004, distance);
	float edge = smoothstep(-0.018, -0.006, distance);
	COLOR = vec4(mix(COLOR.rgb, edge_color.rgb, edge), COLOR.a * mask);
}
