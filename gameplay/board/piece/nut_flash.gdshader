shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
 vec4 color = texture(TEXTURE, UV) * COLOR;
 vec2 step_uv = TEXTURE_PIXEL_SIZE * 2.0;
 float inner_alpha = min(min(texture(TEXTURE, UV + vec2(step_uv.x, 0.0)).a, texture(TEXTURE, UV - vec2(step_uv.x, 0.0)).a), min(texture(TEXTURE, UV + vec2(0.0, step_uv.y)).a, texture(TEXTURE, UV - vec2(0.0, step_uv.y)).a));
 vec3 outlined = mix(color.rgb, vec3(1.0, 0.87, 0.55), hover_amount * (1.0 - inner_alpha) * 0.85);
 COLOR = vec4(mix(outlined, vec3(1.0), flash_amount), color.a);
}
