class_name AchievementAnim
extends Control
## 结算前成就动画（ALL COMBO / ALL PERFECT）。
## 六阶段时间轴、布局和部件运动取自旧版 config/animation/结算前成就动画_设置.json。

signal finished

const STAGE1_BAR_IN := 0.67
const STAGE2_MAIN_IN := 0.30
const STAGE3_LABEL_IN := 2.0033
const STAGE4_HOLD := 1.0
const STAGE5_CONTENT_OUT := 0.6967
const STAGE6_HUD_OUT := 0.4967

const STAGE2_START := STAGE1_BAR_IN
const STAGE3_START := STAGE2_START + STAGE2_MAIN_IN
const STAGE4_START := STAGE3_START + STAGE3_LABEL_IN
const STAGE5_START := STAGE4_START + STAGE4_HOLD
const STAGE6_START := STAGE5_START + STAGE5_CONTENT_OUT
const TOTAL_DURATION := STAGE6_START + STAGE6_HUD_OUT

const BAR_START_OFFSET := Vector2(-1730.0, 115.0)
const BAR_ROTATION_DEG := 4.5
const BAR_GROUP_SCALE := 1.22
const BAR_ARROW_SPEED := 600.0
const BAR_ARROW_HEIGHT_RATIO := 0.79
const BOARD_GROUP_SCALE := 0.95
const BOARD_START_ALPHA := 45.0 / 255.0
const BOARD_ROTATE_SPEED_DEG := 57.0
const RING_ROTATE_SPEED_DEG := 28.0
const WIND_ROTATE_SPEED_DEG := -96.0
const SPECTRUM_SCALE := 2.69
const LABEL_ROTATION_DEG := 5.0
const GLOBAL_DIM_ALPHA := 136.0 / 255.0
const FLASH_SEQUENCE := [0.20, 0.30, 0.50, 0.45, 0.30, 0.05, 0.0]

const BAR_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D arrow_tex : source_color, filter_linear;
uniform float arrow_width_ratio = 1.0;
uniform float arrow_height_ratio = 0.79;
uniform float phase_ratio = 0.0;
uniform float slant_ratio = 0.02;
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float safe_width = max(arrow_width_ratio, 0.0001);
	float safe_height = max(arrow_height_ratio, 0.0001);
	float arrow_y = (UV.y - (1.0 - safe_height) * 0.5) / safe_height;
	float arrow_x = fract((UV.x + phase_ratio) / safe_width);
	vec4 arrow = texture(arrow_tex, vec2(arrow_x, clamp(arrow_y, 0.0, 1.0)));
	float vertical_mask = step(0.0, arrow_y) * step(arrow_y, 1.0);
	float right_edge = 1.0 - slant_ratio * (1.0 - UV.y);
	float shape_mask = step(UV.x, right_edge);
	float arrow_alpha = arrow.a * base.a * vertical_mask * shape_mask;
	vec3 rgb = mix(base.rgb, arrow.rgb, arrow_alpha);
	COLOR = vec4(rgb, base.a * shape_mask) * COLOR;
}
"""

const PIXELATE_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D group_buffer : hint_screen_texture, repeat_disable, filter_nearest;
uniform float pixel_scale = 1.0;
void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	float block = max(1.0, pixel_scale);
	vec2 pixel_uv = (floor(SCREEN_UV * screen_size / block) + vec2(0.5)) * block / screen_size;
	vec4 grouped = textureLod(group_buffer, pixel_uv, 0.0);
	// CanvasGroup 缓冲使用预乘 Alpha；恢复直通颜色后再乘节点调制色。
	if (grouped.a > 0.0001) {
		grouped.rgb /= grouped.a;
	}
	COLOR *= grouped;
}
"""

var _t := 0.0
var _running := false
var _normal_completion := false
var _kind := ""
var _viewport_size := Vector2(1920.0, 1080.0)
var _center := Vector2(960.0, 604.8)

var _dim: ColorRect
var _flash: ColorRect
var _content: CanvasGroup
var _content_material: ShaderMaterial
var _bar: TextureRect
var _bar_material: ShaderMaterial
var _main_group: Control
var _board: TextureRect
var _ring: TextureRect
var _wind: TextureRect
var _label: TextureRect
var _spectrum: AchievementSpectrum

var _bar_target_center := Vector2.ZERO
var _bar_target_width := 0.0
var _board_target_width := 0.0
var _label_target_width := 0.0
var _label_target_height := 0.0
var _arrow_width_pixels := 1.0
var _main_color := Color8(233, 146, 32)
var _stage6_started := false

var _top_hud: Control
var _judgement_node: Node2D
var _top_hud_state := {}
var _judgement_state := {}
var _judgement_pivot := Vector2(960.0, 210.0)


func play(kind: String, top_hud: Control = null, judgement_node: Node2D = null) -> bool:
	if kind not in ["full_combo", "full_perfect"]:
		return false
	_kind = kind
	_top_hud = top_hud
	_judgement_node = judgement_node
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1000
	_viewport_size = get_viewport_rect().size
	if _viewport_size.x <= 1.0 or _viewport_size.y <= 1.0:
		_viewport_size = Vector2(1920.0, 1080.0)
	size = _viewport_size
	_center = Vector2(_viewport_size.x * 0.5, _viewport_size.y * 0.56)
	_capture_stage_node_states()
	if not _build_nodes(kind):
		_restore_stage_nodes()
		return false
	_t = 0.0
	_stage6_started = false
	_normal_completion = false
	_running = true
	_apply_visual_state()
	return true


func _build_nodes(kind: String) -> bool:
	var base := "UI-img/游戏界面/%s" % kind
	var bar_texture := AssetLoader.tex(base + "/bar.png")
	var arrow_texture := AssetLoader.tex(base + "/arrow.png")
	var board_texture := AssetLoader.tex(base + "/board.png")
	var ring_texture := AssetLoader.tex(base + "/ring_light.png")
	var wind_texture := AssetLoader.tex(base + "/wind.png")
	var label_texture := AssetLoader.tex(base + "/label.png")
	if bar_texture == null or arrow_texture == null or board_texture == null \
			or ring_texture == null or wind_texture == null or label_texture == null:
		push_warning("AchievementAnim: 成就动画素材不完整 -> %s" % kind)
		return false

	_dim = ColorRect.new()
	_dim.name = "AchievementDim"
	_dim.color = Color(0.0, 0.0, 0.0, GLOBAL_DIM_ALPHA)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.z_index = 0
	add_child(_dim)

	_content = CanvasGroup.new()
	_content.name = "AchievementContent"
	_content.z_index = 1
	_content_material = ShaderMaterial.new()
	var pixel_shader := Shader.new()
	pixel_shader.code = PIXELATE_SHADER
	_content_material.shader = pixel_shader
	_content_material.set_shader_parameter("pixel_scale", 1.0)
	_content.material = _content_material
	add_child(_content)

	_flash = ColorRect.new()
	_flash.name = "AchievementFlash"
	_flash.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.z_index = 2
	add_child(_flash)

	_main_color = Color8(233, 146, 32) if kind == "full_perfect" else \
		_estimate_main_color(board_texture, label_texture)
	_calculate_layout(bar_texture, arrow_texture, board_texture, ring_texture,
		wind_texture, label_texture)
	_build_bar(bar_texture, arrow_texture)
	_build_main_group(board_texture, ring_texture, wind_texture)
	_build_label(label_texture)
	return true


func _calculate_layout(bar_texture: Texture2D, arrow_texture: Texture2D,
		board_texture: Texture2D, ring_texture: Texture2D, wind_texture: Texture2D,
		label_texture: Texture2D) -> void:
	var bar_base_width := minf(float(bar_texture.get_width()) * 0.82,
		maxf(720.0, _viewport_size.x * 0.86))
	var board_base_width := minf(float(board_texture.get_width()) * 0.86,
		maxf(188.0, minf(_viewport_size.x, _viewport_size.y) * 0.38))
	var label_base_width := minf(float(label_texture.get_width()) * 0.90,
		maxf(420.0, bar_base_width * BAR_GROUP_SCALE * 0.68))
	_bar_target_width = maxf(400.0, bar_base_width * BAR_GROUP_SCALE)
	_board_target_width = maxf(140.0, board_base_width * BOARD_GROUP_SCALE)
	_label_target_width = maxf(240.0, label_base_width)
	_label_target_height = float(label_texture.get_height()) * (
		_label_target_width / maxf(1.0, float(label_texture.get_width())))
	_bar_target_center = _center
	var bar_height := _bar_target_width * float(bar_texture.get_height()) / \
		maxf(1.0, float(bar_texture.get_width()))
	var arrow_height := bar_height * BAR_ARROW_HEIGHT_RATIO
	_arrow_width_pixels = arrow_height * float(arrow_texture.get_width()) / \
		maxf(1.0, float(arrow_texture.get_height()))


func _build_bar(bar_texture: Texture2D, arrow_texture: Texture2D) -> void:
	_bar = TextureRect.new()
	_bar.name = "AchievementBar"
	_bar.texture = bar_texture
	_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bar.stretch_mode = TextureRect.STRETCH_SCALE
	var bar_height := _bar_target_width * float(bar_texture.get_height()) / \
		maxf(1.0, float(bar_texture.get_width()))
	_bar.size = Vector2(_bar_target_width, bar_height)
	_bar.pivot_offset = _bar.size * 0.5
	_bar.rotation_degrees = BAR_ROTATION_DEG
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.z_index = 0
	_bar_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = BAR_SHADER
	_bar_material.shader = shader
	_bar_material.set_shader_parameter("arrow_tex", arrow_texture)
	_bar_material.set_shader_parameter("arrow_width_ratio",
		_arrow_width_pixels / maxf(1.0, _bar.size.x))
	_bar_material.set_shader_parameter("arrow_height_ratio", BAR_ARROW_HEIGHT_RATIO)
	_bar_material.set_shader_parameter("slant_ratio",
		minf(0.98, _bar.size.y * tan(deg_to_rad(absf(BAR_ROTATION_DEG))) /
			maxf(1.0, _bar.size.x)))
	_bar_material.set_shader_parameter("phase_ratio", 0.0)
	_bar.material = _bar_material
	_content.add_child(_bar)


func _build_main_group(board_texture: Texture2D, ring_texture: Texture2D,
		wind_texture: Texture2D) -> void:
	var ring_target_width := _board_target_width * float(ring_texture.get_width()) / \
		maxf(1.0, float(board_texture.get_width()))
	var wind_target_width := _board_target_width * 1.08
	var spectrum_inner_radius := maxf(18.0, _board_target_width * 0.18 * SPECTRUM_SCALE)
	var spectrum_extension := maxf(20.0, _board_target_width * 0.11 * SPECTRUM_SCALE)
	var spectrum_outer_diameter := (spectrum_inner_radius + spectrum_extension) * 2.0 + \
		maxf(12.0, _board_target_width * 0.04)
	var group_size := maxf(maxf(_board_target_width, ring_target_width),
		maxf(wind_target_width, spectrum_outer_diameter)) + 96.0

	_main_group = Control.new()
	_main_group.name = "AchievementMainGroup"
	_main_group.size = Vector2.ONE * group_size
	_main_group.position = _center - _main_group.size * 0.5
	_main_group.pivot_offset = _main_group.size * 0.5
	_main_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_group.modulate.a = 0.0
	_main_group.visible = false
	_main_group.z_index = 1
	_content.add_child(_main_group)
	var local_center := _main_group.size * 0.5

	_spectrum = AchievementSpectrum.new()
	_spectrum.name = "AchievementSpectrum"
	_spectrum.position = local_center
	_spectrum.z_index = 0
	_spectrum.configure(_main_color, spectrum_inner_radius, spectrum_extension,
		maxf(2.0, _board_target_width * 0.0105),
		maxf(1.0, _board_target_width * 0.010))
	_main_group.add_child(_spectrum)

	_board = _make_texture_node("AchievementBoard", board_texture,
		Vector2.ONE * _board_target_width, local_center, 1)
	_main_group.add_child(_board)
	_ring = _make_texture_node("AchievementRingLight", ring_texture,
		Vector2.ONE * ring_target_width, local_center, 2)
	_ring.modulate.a = 196.0 / 255.0
	_main_group.add_child(_ring)
	_wind = _make_texture_node("AchievementWind", wind_texture,
		Vector2.ONE * wind_target_width, local_center, 3)
	_main_group.add_child(_wind)


func _build_label(label_texture: Texture2D) -> void:
	_label = TextureRect.new()
	_label.name = "AchievementLabel"
	_label.texture = label_texture
	_label.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_label.stretch_mode = TextureRect.STRETCH_SCALE
	_label.rotation_degrees = LABEL_ROTATION_DEG
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	_label.modulate.a = 0.0
	_label.z_index = 2
	_content.add_child(_label)


func _make_texture_node(node_name: String, texture: Texture2D, target_size: Vector2,
		local_center: Vector2, target_z: int) -> TextureRect:
	var node := TextureRect.new()
	node.name = node_name
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.size = target_size
	node.position = local_center - target_size * 0.5
	node.pivot_offset = target_size * 0.5
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.z_index = target_z
	return node


func _process(delta: float) -> void:
	if not _running:
		return
	_t += maxf(0.0, delta)
	_apply_visual_state()
	if _t >= TOTAL_DURATION:
		_complete()


func _apply_visual_state() -> void:
	_update_bar()
	_update_main_group()
	_update_label()
	_update_flash()
	_update_content_out()
	_update_stage6()


func _update_bar() -> void:
	var progress := clampf(_t / STAGE1_BAR_IN, 0.0, 1.0)
	var enter := _back_out(progress)
	var center := _bar_target_center + BAR_START_OFFSET.lerp(Vector2.ZERO, enter)
	_bar.position = center - _bar.size * 0.5
	_bar.rotation_degrees = BAR_ROTATION_DEG
	_bar.visible = true
	_bar.modulate.a = 1.0
	if _bar_material != null:
		var offset := fposmod(_t * BAR_ARROW_SPEED, maxf(1.0, _arrow_width_pixels))
		_bar_material.set_shader_parameter("phase_ratio", offset / maxf(1.0, _bar.size.x))


func _update_main_group() -> void:
	var progress := clampf((_t - STAGE2_START) / STAGE2_MAIN_IN, 0.0, 1.0)
	_main_group.visible = progress > 0.0
	if not _main_group.visible:
		return
	var enter := _back_out(progress)
	var group_scale := lerpf(1.28, 1.0, enter)
	_main_group.scale = Vector2.ONE * group_scale
	_main_group.modulate.a = lerpf(BOARD_START_ALPHA, 1.0, _smoothstep(progress))
	_board.rotation_degrees = _t * BOARD_ROTATE_SPEED_DEG
	_ring.rotation_degrees = _t * RING_ROTATE_SPEED_DEG
	_ring.modulate.a = 196.0 / 255.0
	_wind.rotation_degrees = _t * WIND_ROTATE_SPEED_DEG
	_wind.modulate.a = lerpf(82.0, 156.0, 0.5 + 0.5 * sin(_t * 6.2)) / 255.0
	_spectrum.set_animation_time(_t)


func _update_label() -> void:
	var progress := clampf((_t - STAGE3_START) / STAGE3_LABEL_IN, 0.0, 1.0)
	_label.visible = progress > 0.0
	if not _label.visible:
		return
	var stage5_progress := clampf((_t - STAGE5_START) / STAGE5_CONTENT_OUT, 0.0, 1.0)
	var out_scale := lerpf(1.0, 1.20, _smoothstep(stage5_progress))
	var width := _label_target_width * lerpf(0.60, 1.10, _ease_out_cubic(progress)) * out_scale
	var height := _label_target_height * out_scale
	_label.size = Vector2(maxf(64.0, width), maxf(8.0, height))
	_label.pivot_offset = _label.size * 0.5
	_label.position = _center - _label.size * 0.5
	_label.rotation_degrees = LABEL_ROTATION_DEG
	_label.modulate.a = lerpf(178.0, 255.0, _smoothstep(progress)) / 255.0


func _update_flash() -> void:
	var local_seconds := _t - STAGE2_START
	if local_seconds < 0.0 or local_seconds > STAGE2_MAIN_IN:
		_flash.color.a = 0.0
		return
	var position := clampf(local_seconds / STAGE2_MAIN_IN, 0.0, 1.0) * \
		float(FLASH_SEQUENCE.size() - 1)
	var left := clampi(int(floor(position)), 0, FLASH_SEQUENCE.size() - 2)
	var right := mini(FLASH_SEQUENCE.size() - 1, left + 1)
	_flash.color.a = lerpf(float(FLASH_SEQUENCE[left]), float(FLASH_SEQUENCE[right]),
		position - floor(position))


func _update_content_out() -> void:
	var progress := clampf((_t - STAGE5_START) / STAGE5_CONTENT_OUT, 0.0, 1.0)
	var eased := _smoothstep(progress)
	_content.modulate.a = 1.0 - eased
	if _content_material != null:
		_content_material.set_shader_parameter("pixel_scale", 1.0 + progress * 5.0)


func _update_stage6() -> void:
	if _t < STAGE6_START:
		return
	if not _stage6_started:
		_begin_stage6()
	var progress := clampf((_t - STAGE6_START) / STAGE6_HUD_OUT, 0.0, 1.0)
	var eased := _smoothstep(progress)
	if is_instance_valid(_top_hud):
		_top_hud.position = Vector2(_top_hud_state.get("position", Vector2.ZERO)) + \
			Vector2(0.0, lerpf(0.0, -96.0, eased))
		var base_scale: Vector2 = _top_hud_state.get("scale", Vector2.ONE)
		_top_hud.scale = base_scale * lerpf(1.0, 0.96, eased)
		var color: Color = _top_hud_state.get("modulate", Color.WHITE)
		color.a *= 1.0 - eased
		_top_hud.modulate = color
	if is_instance_valid(_judgement_node):
		var scale_value := lerpf(1.0, 0.82, eased)
		var base_position: Vector2 = _judgement_state.get("position", Vector2.ZERO)
		var base_judge_scale: Vector2 = _judgement_state.get("scale", Vector2.ONE)
		_judgement_node.scale = base_judge_scale * scale_value
		_judgement_node.position = base_position + _judgement_pivot * (1.0 - scale_value) + \
			Vector2(0.0, lerpf(0.0, 36.0, eased))
		var judge_color: Color = _judgement_state.get("modulate", Color.WHITE)
		judge_color.a *= 1.0 - eased
		_judgement_node.modulate = judge_color


func _begin_stage6() -> void:
	_stage6_started = true
	_content.modulate.a = 0.0
	if is_instance_valid(_top_hud):
		_top_hud.visible = bool(_top_hud_state.get("visible", true))
		_top_hud.z_index = z_index + 2
		_top_hud.pivot_offset = Vector2(_viewport_size.x * 0.5, 90.0)
	if is_instance_valid(_judgement_node):
		_judgement_node.visible = bool(_judgement_state.get("visible", true))
		_judgement_node.z_index = z_index + 2


func _capture_stage_node_states() -> void:
	if is_instance_valid(_top_hud):
		_top_hud_state = {
			"position": _top_hud.position,
			"scale": _top_hud.scale,
			"modulate": _top_hud.modulate,
			"pivot_offset": _top_hud.pivot_offset,
			"z_index": _top_hud.z_index,
			"visible": _top_hud.visible,
		}
	if is_instance_valid(_judgement_node):
		_judgement_state = {
			"position": _judgement_node.position,
			"scale": _judgement_node.scale,
			"modulate": _judgement_node.modulate,
			"z_index": _judgement_node.z_index,
			"visible": _judgement_node.visible,
		}
		var receptor_y := 210.0
		if _judgement_node.has_method("receptor_y_for_test"):
			receptor_y = float(_judgement_node.call("receptor_y_for_test"))
		var center_x := _viewport_size.x * 0.5
		if _has_property(_judgement_node, "field_center_x"):
			center_x = float(_judgement_node.get("field_center_x"))
		_judgement_pivot = Vector2(center_x, receptor_y)


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _restore_stage_nodes() -> void:
	if is_instance_valid(_top_hud) and not _top_hud_state.is_empty():
		_top_hud.position = _top_hud_state.get("position", Vector2.ZERO)
		_top_hud.scale = _top_hud_state.get("scale", Vector2.ONE)
		_top_hud.modulate = _top_hud_state.get("modulate", Color.WHITE)
		_top_hud.pivot_offset = _top_hud_state.get("pivot_offset", Vector2.ZERO)
		_top_hud.z_index = int(_top_hud_state.get("z_index", 0))
		_top_hud.visible = bool(_top_hud_state.get("visible", true))
	if is_instance_valid(_judgement_node) and not _judgement_state.is_empty():
		_judgement_node.position = _judgement_state.get("position", Vector2.ZERO)
		_judgement_node.scale = _judgement_state.get("scale", Vector2.ONE)
		_judgement_node.modulate = _judgement_state.get("modulate", Color.WHITE)
		_judgement_node.z_index = int(_judgement_state.get("z_index", 0))
		_judgement_node.visible = bool(_judgement_state.get("visible", true))


func abort_and_restore() -> void:
	_running = false
	_normal_completion = false
	_restore_stage_nodes()
	queue_free()


func _complete() -> void:
	if not _running:
		return
	_running = false
	_normal_completion = true
	finished.emit()
	queue_free()


func _exit_tree() -> void:
	if not _normal_completion:
		_restore_stage_nodes()


func _estimate_main_color(primary: Texture2D, fallback: Texture2D) -> Color:
	for texture in [primary, fallback]:
		if texture == null:
			continue
		var image: Image = texture.get_image()
		if image == null or image.is_empty():
			continue
		var step_x := maxi(1, image.get_width() / 48)
		var step_y := maxi(1, image.get_height() / 48)
		var sum := Vector3.ZERO
		var count := 0
		for x in range(0, image.get_width(), step_x):
			for y in range(0, image.get_height(), step_y):
				var color: Color = image.get_pixel(x, y)
				if color.a < 24.0 / 255.0:
					continue
				sum += Vector3(color.r, color.g, color.b)
				count += 1
		if count > 0:
			return Color(sum.x / float(count), sum.y / float(count),
				sum.z / float(count), 1.0)
	return Color8(233, 146, 32)


func _ease_out_cubic(value: float) -> float:
	var x := 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - x * x * x


func _smoothstep(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _back_out(value: float) -> float:
	var x := clampf(value, 0.0, 1.0) - 1.0
	const C1 := 1.70158
	const C3 := C1 + 1.0
	return 1.0 + C3 * x * x * x + C1 * x * x


func seek_for_test(seconds: float) -> void:
	_t = clampf(seconds, 0.0, TOTAL_DURATION)
	_apply_visual_state()


func state_for_test() -> Dictionary:
	return {
		"kind": _kind,
		"time": _t,
		"phase": phase_name_for_test(),
		"total_duration": TOTAL_DURATION,
		"bar_width": _bar_target_width,
		"board_width": _board_target_width,
		"label_width": _label.size.x if is_instance_valid(_label) else 0.0,
		"main_color": _main_color,
		"stage6_started": _stage6_started,
		"content_alpha": _content.modulate.a if is_instance_valid(_content) else 0.0,
		"pixel_scale": float(_content_material.get_shader_parameter("pixel_scale")) \
			if _content_material != null else 1.0,
		"arrow_phase": float(_bar_material.get_shader_parameter("phase_ratio")) \
			if _bar_material != null else 0.0,
		"spectrum": _spectrum.state_for_test() if is_instance_valid(_spectrum) else {},
	}


func phase_name_for_test() -> String:
	if _t < STAGE2_START:
		return "阶段1 底板入场"
	if _t < STAGE3_START:
		return "阶段2 Board入场"
	if _t < STAGE4_START:
		return "阶段3 Label入场"
	if _t < STAGE5_START:
		return "阶段4 停留"
	if _t < STAGE6_START:
		return "阶段5 整体收尾"
	return "阶段6 HUD回收"
