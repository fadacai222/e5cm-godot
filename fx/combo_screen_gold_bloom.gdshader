shader_type canvas_item;
render_mode unshaded, blend_add;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float fx_time = 0.0;
uniform float fx_visibility : hint_range(0.0, 1.0) = 0.0;
uniform float fx_intensity : hint_range(0.0, 3.0) = 1.75;
uniform float fx_impact : hint_range(0.0, 1.0) = 0.0;
uniform float reduced_motion : hint_range(0.0, 1.0) = 0.0;
uniform vec4 gold_dark : source_color = vec4(0.58, 0.27, 0.01, 1.0);
uniform vec4 gold_core : source_color = vec4(1.0, 0.66, 0.025, 1.0);
uniform vec4 gold_hot : source_color = vec4(1.0, 0.985, 0.72, 1.0);

float luminance(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 1.0 / vec2(textureSize(screen_texture, 0));
	vec3 center = texture(screen_texture, uv).rgb;
	float center_luma = luminance(center);

	float edge = 0.0;
	edge = max(edge, abs(center_luma - luminance(texture(screen_texture, uv + vec2(texel.x * 2.0, 0.0)).rgb)));
	edge = max(edge, abs(center_luma - luminance(texture(screen_texture, uv - vec2(texel.x * 2.0, 0.0)).rgb)));
	edge = max(edge, abs(center_luma - luminance(texture(screen_texture, uv + vec2(0.0, texel.y * 2.0)).rgb)));
	edge = max(edge, abs(center_luma - luminance(texture(screen_texture, uv - vec2(0.0, texel.y * 2.0)).rgb)));
	edge = max(edge, abs(center_luma - luminance(texture(screen_texture, uv + texel * 3.5).rgb)));
	edge = max(edge, abs(center_luma - luminance(texture(screen_texture, uv - texel * 3.5).rgb)));
	edge = smoothstep(0.022, 0.22, edge);

	float bright = smoothstep(0.48, 1.05, center_luma);
	float pulse = 0.5 + 0.5 * sin(fx_time * 12.0);
	float slow_pulse = 0.5 + 0.5 * sin(fx_time * 4.8);
	float diagonal = pow(max(0.0, sin((uv.x * 1.45 + uv.y * 0.72 - fx_time * 1.15) * 34.0)), 18.0);
	diagonal *= mix(1.0, 0.18, reduced_motion);

	vec2 spark_cell = floor(uv * vec2(150.0, 84.0));
	float spark_noise = hash21(spark_cell + floor(fx_time * 18.0));
	float spark = step(0.988, spark_noise) * (0.32 + edge * 0.68);
	spark *= mix(1.0, 0.24, reduced_motion);

	float border_distance = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	float border = 1.0 - smoothstep(0.0, 0.055, border_distance);
	float center_vignette = 1.0 - smoothstep(0.24, 0.76, distance(uv, vec2(0.5)));

	float energy = edge * (0.80 + pulse * 0.48);
	energy += bright * (0.10 + slow_pulse * 0.11);
	energy += diagonal * (0.07 + edge * 0.30);
	energy += spark * 1.25;
	energy += border * (0.045 + fx_impact * 0.16);
	energy += center_vignette * fx_impact * 0.055;
	energy *= fx_visibility * fx_intensity;

	vec3 gold = mix(gold_dark.rgb, gold_core.rgb, clamp(edge + bright * 0.42, 0.0, 1.0));
	gold = mix(gold, gold_hot.rgb, clamp(pulse * 0.34 + spark * 0.92 + fx_impact * 0.30, 0.0, 1.0));
	float alpha = clamp(energy, 0.0, 0.82);
	COLOR = vec4(gold * energy, alpha);
}
