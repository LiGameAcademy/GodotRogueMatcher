shader_type canvas_item;
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
 vec4 color = texture(TEXTURE, UV) * COLOR;
 COLOR = vec4(mix(color.rgb, vec3(1.0), flash_amount), color.a);
}
