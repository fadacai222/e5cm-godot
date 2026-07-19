shader_type canvas_item;
render_mode unshaded, blend_mix;

// 原底板贴图是固定 60% Alpha 的深紫色纯色块。
// 直接把源 Alpha 拉满会得到发黑的 #482A53，因此这里仅使用贴图轮廓，
// 用接近原版观感的中亮紫色渐变重建实心底板。
uniform vec4 top_color : source_color = vec4(0.51, 0.31, 0.56, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.39, 0.20, 0.44, 1.0);
uniform float center_lift : hint_range(0.0, 0.15) = 0.045;

void fragment() {
	vec4 modulation = COLOR;
	vec4 tex = texture(TEXTURE, UV);
	float coverage = step(0.001, tex.a);
	float vertical = smoothstep(0.0, 1.0, UV.y);
	vec3 base = mix(top_color.rgb, bottom_color.rgb, vertical);
	float center_band = 1.0 - smoothstep(0.0, 0.50, abs(UV.y - 0.5));
	base += vec3(center_lift * center_band);
	COLOR = vec4(base * modulation.rgb, modulation.a * coverage);
}
