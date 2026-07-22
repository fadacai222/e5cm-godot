class_name FeatureQuickAccessRail
extends Control
## 大模式与选歌场景共用的功能快捷入口。
## 使用窄型原版街机 HUD 卡片，不再把普通 Godot Button 贴在主画面上。

signal training_requested
signal challenge_requested

const CARD_SIZE := Vector2(382, 52)
const CARD_GAP := 8.0

var _training_button: Button
var _challenge_button: Button
var _training_frame: E5HudFrame
var _challenge_frame: E5HudFrame
var _training_state: Label
var _training_subtitle: Label
var _challenge_state: Label
var _challenge_subtitle: Label
var _challenge_segments: Array[ColorRect] = []


func _ready() -> void:
	name = "FeatureQuickAccessRail"
	size = Vector2(CARD_SIZE.x, CARD_SIZE.y * 2.0 + CARD_GAP)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_cards()
	if not TrainingSession.session_changed.is_connected(refresh):
		TrainingSession.session_changed.connect(refresh)
	if not ChallengeService.challenges_changed.is_connected(refresh):
		ChallengeService.challenges_changed.connect(refresh)
	refresh()


func _build_cards() -> void:
	_training_button = _build_card(
		"TrainingEntry", 0.0, "训练室", "PRACTICE", "片段练习 / 判定分析",
		E5OriginalTheme.CYAN, _on_training_pressed)
	_training_frame = _training_button.get_node("HudFrame") as E5HudFrame
	_training_state = _training_button.get_node("State") as Label
	_training_subtitle = _training_button.get_node("Subtitle") as Label

	_challenge_button = _build_card(
		"ChallengeEntry", CARD_SIZE.y + CARD_GAP, "今日挑战", "CHALLENGE", "每日与周常目标",
		E5OriginalTheme.MAGENTA, _on_challenge_pressed)
	_challenge_frame = _challenge_button.get_node("HudFrame") as E5HudFrame
	_challenge_state = _challenge_button.get_node("State") as Label
	_challenge_subtitle = _challenge_button.get_node("Subtitle") as Label
	for i in 3:
		var segment := ColorRect.new()
		segment.name = "ChallengeSegment%d" % i
		segment.position = Vector2(302 + i * 20, 39)
		segment.size = Vector2(14, 3)
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_challenge_button.add_child(segment)
		_challenge_segments.append(segment)


func _build_card(node_name: String, y: float, title_text: String, english_text: String,
		subtitle_text: String, accent: Color, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.position = Vector2(0, y)
	button.size = CARD_SIZE
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.text = ""
	button.flat = true
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(callback)
	button.mouse_entered.connect(_set_hover.bind(button, true))
	button.mouse_exited.connect(_set_hover.bind(button, false))
	button.focus_entered.connect(_set_hover.bind(button, true))
	button.focus_exited.connect(_set_hover.bind(button, false))
	add_child(button)

	var frame := UiKit.hud_frame(button, Rect2(Vector2.ZERO, CARD_SIZE), "HudFrame",
		accent, E5OriginalTheme.MAGENTA if accent == E5OriginalTheme.CYAN else E5OriginalTheme.CYAN,
		0.0, true, 10.0)
	frame.fill_color = Color(0.006, 0.043, 0.10, 0.95)
	frame.inner_color = Color(accent.r, accent.g, accent.b, 0.22)
	frame.scanline_gap = 6.0
	frame.show_side_ticks = false
	frame.border_width = 1.5

	var icon := Label.new()
	icon.name = "ModuleIcon"
	icon.text = "◆" if node_name == "TrainingEntry" else "◇"
	icon.position = Vector2(14, 7)
	icon.size = Vector2(30, 36)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 23)
	icon.add_theme_color_override("font_color", accent)
	icon.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	icon.add_theme_constant_override("outline_size", 3)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)

	var title := Label.new()
	title.name = "Title"
	title.text = "%s  /  %s" % [title_text, english_text]
	title.position = Vector2(52, 4)
	title.size = Vector2(235, 25)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.92, 0.98, 1.0))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	title.add_theme_constant_override("outline_size", 2)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = subtitle_text
	subtitle.position = Vector2(53, 27)
	subtitle.size = Vector2(235, 18)
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.50, 0.68, 0.82))
	subtitle.add_theme_constant_override("outline_size", 0)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(subtitle)

	var state := Label.new()
	state.name = "State"
	state.position = Vector2(292, 7)
	state.size = Vector2(74, 28)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 15)
	state.add_theme_color_override("font_color", accent)
	state.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	state.add_theme_constant_override("outline_size", 2)
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(state)
	return button


func refresh() -> void:
	if _training_button == null or _challenge_button == null:
		return
	var armed := TrainingSession.is_entry_armed()
	_training_state.text = "ACTIVE" if armed else "READY"
	_training_subtitle.text = "已开启：选歌后进入训练设置" if armed else "片段练习 / 判定分析"
	_training_state.add_theme_color_override("font_color",
		E5OriginalTheme.MAGENTA if armed else E5OriginalTheme.CYAN)
	_training_frame.border_color = E5OriginalTheme.MAGENTA if armed else E5OriginalTheme.CYAN
	_training_frame.fill_color = Color(0.055, 0.018, 0.080, 0.96) if armed else \
		Color(0.006, 0.043, 0.10, 0.95)
	_training_frame.queue_redraw()

	var summary: Dictionary = ChallengeService.summary()
	var daily_done := int(summary.get("daily_completed", 0))
	var daily_total := maxi(1, int(summary.get("daily_total", 3)))
	var weekly_done := int(summary.get("weekly_completed", 0))
	var weekly_total := maxi(1, int(summary.get("weekly_total", 5)))
	_challenge_state.text = "%d/%d" % [daily_done, daily_total]
	_challenge_subtitle.text = "每日 %d/%d  ·  周常 %d/%d" % [
		daily_done, daily_total, weekly_done, weekly_total]
	var complete := daily_done >= daily_total
	_challenge_frame.border_color = E5OriginalTheme.GOLD if complete else E5OriginalTheme.MAGENTA
	_challenge_frame.fill_color = Color(0.060, 0.044, 0.012, 0.96) if complete else \
		Color(0.035, 0.018, 0.075, 0.95)
	_challenge_frame.queue_redraw()
	for i in _challenge_segments.size():
		_challenge_segments[i].color = E5OriginalTheme.GOLD if i < daily_done else \
			Color(0.25, 0.13, 0.30, 0.86)


func _set_hover(button: Button, hovered: bool) -> void:
	if button == null or not is_instance_valid(button):
		return
	var target_scale := Vector2(1.015, 1.015) if hovered else Vector2.ONE
	var target_x := 4.0 if hovered else 0.0
	button.pivot_offset = button.size * 0.5
	var tween := create_tween().set_parallel(true)
	tween.tween_property(button, "scale", target_scale, 0.10)
	tween.tween_property(button, "position:x", target_x, 0.10)


func _on_training_pressed() -> void:
	training_requested.emit()


func _on_challenge_pressed() -> void:
	challenge_requested.emit()


func emit_training_for_test() -> void:
	training_requested.emit()


func emit_challenge_for_test() -> void:
	challenge_requested.emit()
