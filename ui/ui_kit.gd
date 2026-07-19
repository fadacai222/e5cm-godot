class_name UiKit
extends RefCounted
## 共享 UI 构建工具：全部场景用代码建 UI，统一风格。


static func label(parent: Node, text: String, size: int, pos: Vector2,
		color := Color.WHITE, outline := 4) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_constant_override("outline_size", outline)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	parent.add_child(l)
	return l


static func center_label(parent: Node, text: String, size: int, y: float,
		color := Color.WHITE) -> Label:
	var l := label(parent, text, size, Vector2.ZERO, color)
	l.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	l.offset_top = y
	l.offset_bottom = y + float(size) + 16.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func button(parent: Node, text: String, size: int, pos: Vector2,
		min_size: Vector2, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


## 贴图按钮（原版 UI 图），点击回调；带悬停/选中高亮
static func tex_button(parent: Node, texture: Texture2D, pos: Vector2,
		target_w: float, on_pressed: Callable) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = texture
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
	var ratio := 1.0
	if texture != null and texture.get_width() > 0:
		ratio = float(texture.get_height()) / float(texture.get_width())
	b.custom_minimum_size = Vector2(target_w, target_w * ratio)
	b.size = b.custom_minimum_size
	b.position = pos
	b.pressed.connect(on_pressed)
	parent.add_child(b)
	return b


static func full_bg(parent: Node, texture: Texture2D, dim := 0.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	parent.add_child(t)
	if dim > 0.0:
		var d := ColorRect.new()
		d.color = Color(0, 0, 0, dim)
		d.set_anchors_preset(Control.PRESET_FULL_RECT)
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(d)
	return t


static func toast(parent: Control, text: String, sec := 1.6) -> void:
	var l := center_label(parent, text, 40, 500, Color(1.0, 0.85, 0.3))
	l.z_index = 50
	var tw := parent.create_tween()
	tw.tween_interval(sec)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


## 选中高亮框
static func highlight(target: Control, on: bool) -> void:
	target.modulate = Color(1.25, 1.25, 1.0) if on else Color.WHITE
	target.scale = Vector2(1.06, 1.06) if on else Vector2.ONE
	target.pivot_offset = target.size * 0.5


## 原版街机 HUD 共享入口。新菜单不要再直接使用 Godot 默认皮肤。
static func hud_frame(parent: Control, rect: Rect2, node_name: String,
		primary := E5OriginalTheme.CYAN, secondary := E5OriginalTheme.MAGENTA,
		header := 0.0, scanlines := true, cut := 18.0) -> E5HudFrame:
	return E5OriginalTheme.add_frame(parent, rect, node_name, primary, secondary,
		header, scanlines, cut)


static func skin_arcade_button(button: Button, selected := false,
		danger := false, font_size := 20, accent := E5OriginalTheme.CYAN) -> void:
	E5OriginalTheme.apply_button(button, selected, danger, font_size, accent)


static func skin_arcade_input(input: LineEdit, font_size := 24) -> void:
	E5OriginalTheme.apply_line_edit(input, font_size)


static func skin_arcade_progress(progress: ProgressBar,
		accent := E5OriginalTheme.CYAN, secondary := E5OriginalTheme.MAGENTA) -> void:
	E5OriginalTheme.apply_progress(progress, accent, secondary)


static func animate_arcade_in(panel: Control, offset := Vector2(0, 18),
		duration := 0.18) -> Tween:
	return E5OriginalTheme.animate_in(panel, offset, duration)
