shader_type canvas_item;
render_mode unshaded;

uniform vec4 base_color : source_color = vec4(0.04, 0.06, 0.08, 1.0);
uniform vec4 flow_color : source_color = vec4(0.25, 0.6, 0.6, 1.0);
uniform vec4 second_color : source_color = vec4(0.4, 0.3, 0.5, 1.0);
uniform float phase = 0.0;
uniform float strength = 0.08;
uniform float response = 0.0;
uniform float aspect = 1.7778;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float bend = sin(p.y * 3.0 + phase * 0.7) * 1.3;
	float ribbon = smoothstep(-0.25, 0.9, sin(p.x * 4.0 + bend + phase));
	float crossing = 0.5 + 0.5 * sin(p.y * 3.5 - p.x * 1.7 - phase * 0.6);
	float outside = smoothstep(0.12, 0.65, length(UV - vec2(0.5)));
	float amount = (strength + response) * ribbon * outside;
	vec3 tint = mix(flow_color.rgb, second_color.rgb, crossing * 0.5);
	COLOR = vec4(mix(base_color.rgb, tint, amount), base_color.a);
}
