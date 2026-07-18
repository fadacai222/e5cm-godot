shader_type canvas_item;
render_mode unshaded;

uniform float fx_time = 0.0;
uniform float fx_strength : hint_range(0.0, 3.5) = 1.15;
uniform float outline_pixels : hint_range(0.5, 8.0) = 2.8;
uniform float gold_fill : hint_range(0.0, 1.0) = 0.12;
uniform float spark_density : hint_range(0.0, 1.0) = 0.30;
uniform vec4 gold_dark : source_color = vec4(0.48, 0.20, 0.003, 1.0);
uniform vec4 gold_core : source_color = vec4(1.0, 0.62, 0.012, 1.0);
uniform vec4 gold_hot : source_color = vec4(1.0, 0.995, 0.74, 1.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec4 tint = COLOR;
	vec4 base = texture(TEXTURE, UV);
	vec2 texel = TEXTURE_PIXEL_SIZE * outline_pixels;
	vec2 half_texel = texel * 0.55;
	float near_alpha = 0.0;
	float wide_alpha = 0.0;

	near_alpha = max(near_alpha, texture(TEXTURE, UV + vec2(half_texel.x, 0.0)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV - vec2(half_texel.x, 0.0)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV + vec2(0.0, half_texel.y)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV - vec2(0.0, half_texel.y)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV + half_texel).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV - half_texel).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV + vec2(half_texel.x, -half_texel.y)).a);
	near_alpha = max(near_alpha, texture(TEXTURE, UV + vec2(-half_texel.x, half_texel.y)).a);

	wide_alpha = max(wide_alpha, texture(TEXTURE, UV + vec2(texel.x, 0.0)).a);
	wide_alpha = max(wide_alpha, texture(TEXTURE, UV - vec2(texel.x, 0.0)).a);
	wide_alpha = max(wide_alpha, texture(TEXTURE, UV + vec2(0.0, texel.y)).a);
	wide_alpha = max(wide_alpha, texture(TEXTURE, UV - vec2(0.0, texel.y)).a);
	wide_alpha = max(wide_alpha, texture(TEXTURE, UV + texel).a);
	wide_alpha = max(wide_alpha, texture(TEXTURE, UV - texel).a);
	wide_alpha = max(wide_alpha, texture(TEXTURE, UV + vec2(texel.x, -texel.y)).a);
	wide_alpha = max(wide_alpha, texture(TEXTURE, UV + vec2(-texel.x, texel.y)).a);

	float inner_edge = clamp(near_alpha - base.a, 0.0, 1.0);
	float outer_edge = clamp(wide_alpha - max(base.a, near_alpha * 0.72), 0.0, 1.0);
	float pulse = 0.5 + 0.5 * sin(fx_time * 14.0 + UV.y * 17.0 + UV.x * 8.0);
	float slow_pulse = 0.5 + 0.5 * sin(fx_time * 5.2);
	float vertical_gradient = clamp(0.06 + UV.y * 0.94, 0.0, 1.0);
	vec3 gold = mix(gold_dark.rgb, gold_core.rgb, vertical_gradient);
	gold = mix(gold, gold_hot.rgb, pulse * 0.58);

	vec2 pixel = floor(UV / max(TEXTURE_PIXEL_SIZE, vec2(0.00001)) / 3.0);
	float noise = hash12(pixel + floor(fx_time * 22.0));
	float edge_threshold = mix(0.92, 0.66, spark_density);
	float surface_threshold = mix(0.995, 0.91, spark_density);
	float edge_spark = step(edge_threshold, noise) * max(inner_edge, outer_edge);
	float surface_spark = step(surface_threshold, noise) * smoothstep(0.08, 0.92, base.a);
	float diagonal = pow(max(0.0, sin((UV.x + UV.y * 0.58 - fx_time * 1.8) * 24.0)), 12.0);
	float inner_rim = smoothstep(0.03, 0.92, base.a) * (0.22 + pulse * 0.30);

	float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	vec3 metallic_gold = mix(gold_dark.rgb, gold_hot.rgb,
		clamp(luma * 0.78 + vertical_gradient * 0.38 + pulse * 0.16, 0.0, 1.0));
	metallic_gold *= 0.82 + luma * 0.72;

	vec3 rgb = base.rgb * (1.03 + slow_pulse * 0.10);
	// 每 100 Combo 增加 gold_fill；到第 7 级时原贴图颜色完全转为金属金色。
	rgb = mix(rgb, metallic_gold, gold_fill * base.a);
	rgb += gold * inner_rim * fx_strength * (0.55 + gold_fill * 0.45);
	rgb += gold_hot.rgb * diagonal * base.a * (0.15 + pulse * 0.32) * fx_strength;
	rgb += gold * inner_edge * (1.05 + pulse * 0.74) * fx_strength;
	rgb += gold_core.rgb * outer_edge * (0.58 + pulse * 0.42) * fx_strength;
	rgb = mix(rgb, gold_hot.rgb * 1.32, edge_spark * 0.84 * fx_strength);
	rgb = mix(rgb, gold_hot.rgb * 1.48, surface_spark * (0.42 + gold_fill * 0.36) * fx_strength);

	float alpha = max(base.a, inner_edge * 0.98);
	alpha = max(alpha, outer_edge * (0.50 + pulse * 0.24));
	COLOR = vec4(rgb, alpha) * tint;
}
