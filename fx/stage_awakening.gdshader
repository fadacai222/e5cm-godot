shader_type canvas_item;
render_mode unshaded;

uniform float fx_time = 0.0;
uniform float fx_stage = 0.0;
uniform float fx_strength = 0.0;
uniform float fx_impact = 0.0;
uniform float music_energy = 0.0;
uniform float reduced_motion = 0.0;
uniform float low_cost = 0.0;

void fragment() {
	// 0 Combo 时节点本身会休眠；这里再留一道保险，避免透明全屏层白跑。
	if (fx_stage < 0.5 || fx_strength < 0.001) {
		discard;
	}

	vec2 uv = UV;
	vec2 p = uv - vec2(0.5);
	p.x *= 1.7777778;
	float radius = length(p);
	float motion = mix(1.0, 0.24, reduced_motion);
	float stage2 = step(1.5, fx_stage);
	float stage3 = step(2.5, fx_stage);
	float stage4 = step(3.5, fx_stage);
	float cheap_path = max(low_cost, reduced_motion);

	vec3 warm = vec3(0.12, 0.84, 1.00);
	vec3 burst = vec3(1.00, 0.58, 0.08);
	vec3 overdrive = vec3(1.00, 0.08, 0.58);
	vec3 divine = vec3(1.00, 0.94, 0.58);
	vec3 tone = mix(warm, burst, stage2 * 0.72);
	tone = mix(tone, overdrive, stage3 * 0.62);
	tone = mix(tone, divine, stage4 * 0.78);

	float edge_x = smoothstep(0.56, 0.88, abs(p.x));
	float edge_y = smoothstep(0.36, 0.55, abs(p.y));
	float edge = max(edge_x, edge_y * 0.42);
	float flow = 0.5 + 0.5 * sin(uv.y * 18.0 - fx_time * 2.2 * motion);
	float side_light = edge_x * (0.34 + flow * 0.66);
	float beat = clamp(music_energy * 1.15 + fx_impact * 0.78, 0.0, 1.45);

	float ring = 0.0;
	float center_pulse = 0.0;
	if (stage2 > 0.5) {
		float ring_wave = abs(fract(radius * 4.2 - fx_time * (0.34 + beat * 0.16) * motion) - 0.5);
		ring = smoothstep(0.085, 0.018, ring_wave) * smoothstep(0.98, 0.10, radius);
		center_pulse = smoothstep(0.72, 0.02, radius) * beat;
	}

	float storm = 0.0;
	if (stage3 > 0.5 && cheap_path < 0.5) {
		float line_a = abs(fract((p.x + p.y * 0.72) * 3.4 - fx_time * 0.42 * motion) - 0.5);
		float line_b = abs(fract((p.x - p.y * 0.58) * 4.1 + fx_time * 0.36 * motion) - 0.5);
		storm = (smoothstep(0.075, 0.018, line_a) + smoothstep(0.060, 0.014, line_b))
			* (0.18 + beat * 0.20);
	}

	float spark = 0.0;
	float horizon = 0.0;
	if (stage4 > 0.5 && cheap_path < 0.5) {
		vec2 cell = floor(uv * vec2(28.0, 16.0));
		vec2 local_uv = fract(uv * vec2(28.0, 16.0)) - vec2(0.5);
		float seed = fract(cell.x * 0.75487766 + cell.y * 0.56984029);
		float blink = 0.5 + 0.5 * sin(fx_time * (1.2 + seed * 2.4) * motion + seed * 19.0);
		spark = smoothstep(0.090, 0.018, length(local_uv)) * step(0.92, seed) * blink;
		horizon = smoothstep(0.13, 0.0, abs(p.y + 0.02));
	}

	float alpha = edge * 0.026 + side_light * 0.082;
	alpha += ring * 0.062 + center_pulse * 0.030;
	alpha += storm * 0.070 + spark * 0.14 + horizon * 0.030;
	alpha *= fx_strength;
	alpha = clamp(alpha, 0.0, 0.22);
	if (alpha < 0.002) {
		discard;
	}

	vec3 color = tone;
	color += warm * side_light * 0.26;
	color += burst * (ring + center_pulse) * 0.22;
	color += mix(overdrive, warm, clamp(storm, 0.0, 1.0)) * storm * 0.34;
	color += divine * (spark + horizon * 0.20);
	color = mix(color, vec3(1.0), clamp(fx_impact * 0.14 + spark * 0.24, 0.0, 0.34));
	COLOR = vec4(color, alpha);
}
