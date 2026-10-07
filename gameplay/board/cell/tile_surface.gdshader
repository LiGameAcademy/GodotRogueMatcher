shader_type canvas_item;
render_mode unshaded;
uniform vec4 edge_color : source_color = vec4(0.16, 0.23, 0.31, 1.0);

void fragment() {
	vec2 q = abs(UV - vec2(0.5)) - vec2(0.405);
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - 0.065;
	float mask = 1.0 - smoothstep(-0.004, 0.004, distance);
	float edge = smoothstep(-0.018, -0.006, distance);
	vec3 fill = COLOR.rgb * mix(1.16, 0.82, UV.y);
	COLOR = vec4(mix(fill, edge_color.rgb, edge), COLOR.a * mask);
}
