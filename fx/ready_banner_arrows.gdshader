shader_type canvas_item;
render_mode unshaded, blend_mix;

// 箭头贴图峰值 Alpha 只有约 0.212，直接按原透明度绘制会灰暗发黑。
// 这里把源 Alpha 重新归一化，并映射为淡紫色高光箭头。
uniform vec4 arrow_color : source_color = vec4(0.68, 0.37, 0.75, 1.0);
uniform vec4 arrow_highlight : source_color = vec4(0.86, 0.62, 0.91, 1.0);
uniform float source_alpha_max : hint_range(0.05, 0.40) = 0.212;
uniform float opacity : hint_range(0.0, 1.0) = 0.92;

void fragment() {
	vec4 modulation = COLOR;
	vec4 tex = texture(TEXTURE, UV);
	float coverage = smoothstep(0.0, source_alpha_max, tex.a);
	float brightness = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
	vec3 arrow = mix(arrow_color.rgb, arrow_highlight.rgb,
		smoothstep(0.20, 0.85, brightness));
	COLOR = vec4(arrow * modulation.rgb, coverage * opacity * modulation.a);
}
