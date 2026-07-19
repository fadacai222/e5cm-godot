class_name E5OriginalTheme
extends RefCounted
## E5CM 原版街机 UI 主题工具。所有菜单共用同一组颜色、按钮、输入框与进度条。

const VOID := Color(0.012, 0.035, 0.090, 0.96)
const PANEL := Color(0.020, 0.090, 0.185, 0.94)
const PANEL_DEEP := Color(0.010, 0.050, 0.120, 0.96)
const CYAN := Color(0.16, 0.91, 1.0, 1.0)
const CYAN_SOFT := Color(0.56, 0.92, 1.0, 1.0)
const MAGENTA := Color(1.0, 0.23, 0.78, 1.0)
const GOLD := Color(1.0, 0.84, 0.29, 1.0)
const TEXT := Color(0.96, 0.99, 1.0, 1.0)
const MUTED := Color(0.53, 0.66, 0.78, 1.0)
const DANGER := Color(1.0, 0.31, 0.41, 1.0)


static func panel_style(fill := PANEL, border := CYAN, width := 1,
		shadow_alpha := 0.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(2)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	if shadow_alpha > 0.0:
		style.shadow_color = Color(border.r, border.g, border.b, shadow_alpha)
		style.shadow_size = 8
	return style


static func button_style(accent := CYAN, selected := false, danger := false,
		hover := false, pressed := false, focus := false) -> StyleBoxFlat:
	var line := DANGER if danger else (GOLD if selected else accent)
	var fill := PANEL_DEEP
	if selected:
		fill = Color(0.18, 0.16, 0.045, 0.96)
	elif danger:
		fill = Color(0.16, 0.035, 0.065, 0.94)
	elif hover:
		fill = Color(0.035, 0.18, 0.28, 0.97)
	elif pressed:
		fill = Color(0.02, 0.10, 0.18, 0.98)
	if focus:
		line = MAGENTA if not danger else DANGER
	var style := panel_style(fill, Color(line.r, line.g, line.b,
		1.0 if selected or hover or focus else 0.72), 2 if selected or focus else 1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 7.0
	style.content_margin_bottom = 7.0
	return style


static func apply_button(button: Button, selected := false, danger := false,
		font_size := 20, accent := CYAN) -> void:
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", GOLD if selected else TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", CYAN_SOFT)
	button.add_theme_color_override("font_focus_color", GOLD)
	button.add_theme_color_override("font_disabled_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.45))
	button.add_theme_stylebox_override("normal", button_style(accent, selected, danger))
	button.add_theme_stylebox_override("hover", button_style(accent, selected, danger, true))
	button.add_theme_stylebox_override("pressed", button_style(accent, selected, danger, false, true))
	button.add_theme_stylebox_override("focus", button_style(accent, selected, danger, false, false, true))
	var disabled := button_style(accent, false, danger)
	disabled.bg_color.a = 0.42
	disabled.border_color.a = 0.30
	button.add_theme_stylebox_override("disabled", disabled)


static func apply_line_edit(input: LineEdit, font_size := 24) -> void:
	input.add_theme_font_size_override("font_size", font_size)
	input.add_theme_color_override("font_color", TEXT)
	input.add_theme_color_override("font_placeholder_color", Color(MUTED.r, MUTED.g, MUTED.b, 0.72))
	input.add_theme_color_override("caret_color", GOLD)
	input.add_theme_color_override("selection_color", Color(0.10, 0.68, 0.90, 0.46))
	var normal := panel_style(Color(0.006, 0.036, 0.095, 0.98), Color(CYAN.r, CYAN.g, CYAN.b, 0.74), 2)
	normal.content_margin_left = 18.0
	normal.content_margin_right = 18.0
	normal.content_margin_top = 10.0
	normal.content_margin_bottom = 10.0
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = GOLD
	focus.set_border_width_all(3)
	var readonly := normal.duplicate() as StyleBoxFlat
	readonly.bg_color.a = 0.56
	readonly.border_color.a = 0.34
	input.add_theme_stylebox_override("normal", normal)
	input.add_theme_stylebox_override("focus", focus)
	input.add_theme_stylebox_override("read_only", readonly)


static func apply_progress(progress: ProgressBar, accent := CYAN,
		secondary := MAGENTA) -> void:
	progress.show_percentage = false
	var background := panel_style(Color(0.004, 0.025, 0.075, 0.98),
		Color(accent.r, accent.g, accent.b, 0.42), 1)
	background.set_corner_radius_all(1)
	var fill := panel_style(Color(accent.r, accent.g, accent.b, 0.88),
		Color(secondary.r, secondary.g, secondary.b, 0.94), 1)
	fill.set_corner_radius_all(1)
	fill.shadow_color = Color(accent.r, accent.g, accent.b, 0.34)
	fill.shadow_size = 5
	progress.add_theme_stylebox_override("background", background)
	progress.add_theme_stylebox_override("fill", fill)


static func apply_primary_label(label: Label, font_size := 32) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.03, 0.10, 0.96))
	label.add_theme_constant_override("outline_size", 4)


static func apply_secondary_label(label: Label, font_size := 16,
		color := MUTED) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)


static func add_frame(parent: Control, rect: Rect2, node_name: String,
		primary := CYAN, secondary := MAGENTA, header := 0.0,
		scanlines := true, cut := 18.0) -> E5HudFrame:
	var frame := E5HudFrame.new()
	frame.name = node_name
	frame.position = rect.position
	frame.size = rect.size
	frame.border_color = primary
	frame.secondary_color = secondary
	frame.header_height = header
	frame.cut_size = cut
	frame.show_scanlines = scanlines
	parent.add_child(frame)
	parent.move_child(frame, 0)
	return frame


static func add_rule(parent: Control, rect: Rect2, color := CYAN,
		secondary := MAGENTA) -> Control:
	var holder := Control.new()
	holder.name = "HudRule"
	holder.position = rect.position
	holder.size = rect.size
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := ColorRect.new()
	left.position = Vector2.ZERO
	left.size = Vector2(rect.size.x * 0.68, rect.size.y)
	left.color = Color(color.r, color.g, color.b, 0.72)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(left)
	var right := ColorRect.new()
	right.position = Vector2(rect.size.x * 0.72, 0)
	right.size = Vector2(rect.size.x * 0.28, rect.size.y)
	right.color = Color(secondary.r, secondary.g, secondary.b, 0.78)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(right)
	parent.add_child(holder)
	return holder


static func animate_in(panel: Control, offset := Vector2(0, 18),
		duration := 0.18) -> Tween:
	# 快速关开时不能把动画中的临时位置误当成新布局，否则面板会逐次漂移。
	const REST_POSITION_META := "_e5_arcade_rest_position"
	const ACTIVE_TWEEN_META := "_e5_arcade_active_tween"
	var target_position := panel.position
	if panel.has_meta(REST_POSITION_META):
		target_position = panel.get_meta(REST_POSITION_META) as Vector2
	else:
		panel.set_meta(REST_POSITION_META, target_position)
	var previous = panel.get_meta(ACTIVE_TWEEN_META) \
		if panel.has_meta(ACTIVE_TWEEN_META) else null
	if previous is Tween:
		(previous as Tween).kill()
	panel.pivot_offset = panel.size * 0.5
	panel.position = target_position + offset
	panel.scale = Vector2(0.97, 0.97)
	panel.modulate.a = 0.0
	var tween := panel.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "position", target_position, duration)
	tween.tween_property(panel, "scale", Vector2.ONE, duration)
	tween.tween_property(panel, "modulate:a", 1.0, duration * 0.82)
	panel.set_meta(ACTIVE_TWEEN_META, tween)
	return tween
