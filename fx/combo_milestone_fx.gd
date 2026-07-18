class_name ComboMilestoneFx
extends Control
## 每 100 Combo 强化一次的持续轻量金色里程碑演出。
## 左右空旷区域的导向带、扫描栅格和侧边粒子已按实机反馈彻底删除。
## 当前只保留全局金色 Bloom、左上角里程碑数字和 NoteField 箭头逐级金化；
## 效果不按时间结束，只在 Combo 断掉、重开、退出或结算时停止。

const GOLD := Color(1.0, 0.66, 0.025, 1.0)
const GOLD_HOT := Color(1.0, 0.995, 0.76, 1.0)
const BASE_GLOBAL_GOLD_INTENSITY := 0.82
const GLOBAL_GOLD_PER_LEVEL := 0.16
const MAX_GLOBAL_GOLD_INTENSITY := 1.68

var _elapsed := 0.0
var _impact_elapsed := 0.0
var _combo := 0
var _level := 0
var _active := false
var _paused := false
var _reduced_motion := false
var _track_rect := Rect2(583, 110, 754, 840)
var _number: Label
var _caption: Label
var _back_buffer: BackBufferCopy
var _fullscreen_gold: ColorRect
var _screen_gold_material: ShaderMaterial
var _global_gold_intensity := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 高于 Gameplay HUD/Combo，低于 ESC 菜单。
	z_index = 1200
	visible = false
	_build_fullscreen_gold_bloom()
	_build_corner_badge()


func _build_fullscreen_gold_bloom() -> void:
	_back_buffer = BackBufferCopy.new()
	_back_buffer.name = "MilestoneBackBuffer"
	_back_buffer.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(_back_buffer)

	_fullscreen_gold = ColorRect.new()
	_fullscreen_gold.name = "FullscreenGoldBloom"
	_fullscreen_gold.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fullscreen_gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fullscreen_gold.color = Color.WHITE
	_fullscreen_gold.z_index = 1
	var shader := load("res://fx/combo_screen_gold_bloom.gdshader") as Shader
	if shader != null:
		_screen_gold_material = ShaderMaterial.new()
		_screen_gold_material.shader = shader
		_screen_gold_material.set_shader_parameter("fx_time", 0.0)
		_screen_gold_material.set_shader_parameter("fx_visibility", 0.0)
		_screen_gold_material.set_shader_parameter("fx_intensity", 0.0)
		_screen_gold_material.set_shader_parameter("fx_impact", 0.0)
		_screen_gold_material.set_shader_parameter("reduced_motion", 0.0)
		_fullscreen_gold.material = _screen_gold_material
	add_child(_fullscreen_gold)


func _build_corner_badge() -> void:
	_number = Label.new()
	_number.name = "MilestoneNumberGold"
	_number.position = Vector2(6, 10)
	_number.size = Vector2(184, 88)
	_number.pivot_offset = Vector2(0, 39)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number.add_theme_font_size_override("font_size", 76)
	_number.add_theme_color_override("font_color", GOLD_HOT)
	_number.add_theme_color_override("font_outline_color", Color(0.20, 0.10, 0.0, 0.98))
	_number.add_theme_constant_override("outline_size", 10)
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_number)

	_caption = Label.new()
	_caption.name = "MilestoneCaption"
	_caption.position = Vector2(12, 100)
	_caption.size = Vector2(162, 38)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.text = "COMBO"
	_caption.add_theme_font_size_override("font_size", 28)
	_caption.add_theme_color_override("font_color", GOLD)
	_caption.add_theme_color_override("font_outline_color", Color(0.18, 0.08, 0.0, 0.96))
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)


## 保留接口兼容 Gameplay，但侧边区域不再参与任何绘制。
func configure_track_rect(rect: Rect2) -> void:
	if rect.size.x >= 100.0 and rect.size.y >= 100.0:
		_track_rect = rect


func play_milestone(combo: int, reduced_motion := false) -> void:
	if combo < 100 or combo % 100 != 0:
		return
	var was_active := _active
	_combo = combo
	_level = maxi(1, combo / 100)
	_reduced_motion = reduced_motion
	_global_gold_intensity = _intensity_for_level(_level)
	if not was_active:
		_elapsed = 0.0
	_impact_elapsed = 0.0
	_active = true
	visible = true
	_number.text = str(combo)
	_number.scale = Vector2(1.42, 1.42)
	_number.modulate.a = 0.0
	_caption.modulate.a = 0.0
	if _screen_gold_material != null:
		_screen_gold_material.set_shader_parameter("fx_time", _elapsed)
		_screen_gold_material.set_shader_parameter("fx_visibility", 0.0)
		_screen_gold_material.set_shader_parameter("fx_intensity", _global_gold_intensity)
		_screen_gold_material.set_shader_parameter("fx_impact", 1.0)
		_screen_gold_material.set_shader_parameter("reduced_motion", 1.0 if reduced_motion else 0.0)


func set_paused(value: bool) -> void:
	_paused = value


func stop_effect() -> void:
	_active = false
	_level = 0
	_combo = 0
	_global_gold_intensity = 0.0
	if _screen_gold_material != null:
		_screen_gold_material.set_shader_parameter("fx_visibility", 0.0)
		_screen_gold_material.set_shader_parameter("fx_intensity", 0.0)
		_screen_gold_material.set_shader_parameter("fx_impact", 0.0)
	visible = false


func is_active() -> bool:
	return _active


func track_rect_for_test() -> Rect2:
	return _track_rect


func uses_fullscreen_flash_for_test() -> bool:
	return false


func uses_fullscreen_gold_bloom_for_test() -> bool:
	return _fullscreen_gold != null and _screen_gold_material != null


func uses_side_guides_for_test() -> bool:
	return false


func global_gold_intensity_for_test() -> float:
	return _global_gold_intensity


func milestone_level_for_test() -> int:
	return _level


## 兼容旧测试/调用：侧边粒子已删除，固定返回 0。
func gold_particle_count_for_test() -> int:
	return 0


static func milestone_for_combo(combo: int) -> int:
	return (combo / 100) * 100 if combo >= 100 else 0


func _intensity_for_level(level: int) -> float:
	var value := minf(MAX_GLOBAL_GOLD_INTENSITY,
		BASE_GLOBAL_GOLD_INTENSITY + float(maxi(0, level - 1)) * GLOBAL_GOLD_PER_LEVEL)
	return value * (0.58 if _reduced_motion else 1.0)


func _process(delta: float) -> void:
	if not _active or _paused:
		return
	_elapsed += delta
	_impact_elapsed += delta
	var visibility := clampf(_elapsed / 0.24, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(_elapsed * TAU * (1.45 + minf(0.55, float(_level) * 0.06)))
	var impact := exp(-_impact_elapsed * 4.8)
	_number.scale = Vector2.ONE * (1.0 + impact * 0.40 + pulse * (0.020 + float(_level) * 0.0025))
	_number.modulate.a = visibility * (0.78 + pulse * 0.22)
	_caption.modulate.a = visibility * (0.70 + pulse * 0.30)
	_caption.position.x = 12.0 + sin(_elapsed * 4.0) * (1.0 if _reduced_motion else 4.0)
	if _screen_gold_material != null:
		_screen_gold_material.set_shader_parameter("fx_time", _elapsed)
		_screen_gold_material.set_shader_parameter("fx_visibility", visibility)
		_screen_gold_material.set_shader_parameter("fx_intensity", _global_gold_intensity)
		_screen_gold_material.set_shader_parameter("fx_impact", impact)
