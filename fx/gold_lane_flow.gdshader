shader_type canvas_item;
render_mode unshaded, blend_add;

// 此材质只挂在描边上的短流光 Line2D，不允许用于轨道面填充。
uniform float fx_time = 0.0;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
uniform float lane_phase : hint_range(0.0, 1.0) = 0.0;
uniform vec4 gold_deep : source_color = vec4(1.0, 0.42, 0.004, 1.0);
uniform vec4 gold_core : source_color = vec4(1.0, 0.92, 0.16, 1.0);
uniform vec4 gold_hot : source_color = vec4(1.0, 1.0, 0.94, 1.0);

void fragment() {
	vec4 line_color = COLOR;
	float pulse = 0.5 + 0.5 * sin(fx_time * 15.0 + lane_phase * 6.2831853);
	float flash = pow(max(0.0, sin(fx_time * 7.6 + lane_phase * 9.0)), 12.0);
	float white_heat = clamp(0.54 + pulse * 0.34 + flash * 0.48, 0.0, 1.0);

	vec3 gold = mix(gold_deep.rgb, gold_core.rgb, 0.76 + pulse * 0.20);
	gold = mix(gold, gold_hot.rgb, white_heat);
	vec3 emission = gold * (1.35 + pulse * 0.72 + flash * 1.35) * intensity;
	float alpha = line_color.a * (0.78 + pulse * 0.22);

	COLOR = vec4(emission * max(line_color.rgb, vec3(0.72)), alpha);
}
