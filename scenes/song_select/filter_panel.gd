class_name FilterPanel
extends Control
## 玩法/星级筛选页：功能沿用原版，视觉统一为 E5CM 街机切角 HUD。

signal filter_changed(style: String, star: int)

const PANEL_W := 980.0
const PANEL_H := 720.0
const PAD := 34.0
const TITLE_ZONE := 154.0

var _style := ""
var _star := 0
var _styles: Array = []
var _stars_provider: Callable   # func(style: String) -> Array[int]

var _mask: ColorRect
var _panel: Panel
var _lbl_summary: Label
var _content: Control
var _frame: E5HudFrame


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 22

	_mask = ColorRect.new()
	_mask.name = "InputBlocker"
	_mask.color = Color(0.0, 0.012, 0.055, 0.82)
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_STOP
	_mask.gui_input.connect(_on_mask_input)
	add_child(_mask)

	_panel = Panel.new()
	_panel.name = "ContentPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.position = Vector2((1920.0 - PANEL_W) * 0.5, (1080.0 - PANEL_H) * 0.5)
	_panel.size = Vector2(PANEL_W, PANEL_H)
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color(0, 0, 0, 0)
	transparent.set_border_width_all(0)
	_panel.add_theme_stylebox_override("panel", transparent)
	add_child(_panel)

	_frame = UiKit.hud_frame(_panel, Rect2(Vector2.ZERO, _panel.size),
		"OriginalHudFrame", E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA,
		132.0, true, 24.0)
	_frame.fill_color = Color(0.012, 0.060, 0.145, 0.975)
	_frame.header_color = Color(0.035, 0.20, 0.34, 0.72)
	_frame.scanline_color = Color(0.18, 0.72, 1.0, 0.045)

	var mode_tag := UiKit.label(_panel, "FILTER  /  SELECT", 15, Vector2(46, 18),
		E5OriginalTheme.CYAN_SOFT, 0)
	mode_tag.name = "FilterModeTag"
	mode_tag.size = Vector2(300, 26)
	var title := UiKit.label(_panel, "玩法 / 星级筛选", 36, Vector2(44, 45),
		E5OriginalTheme.TEXT, 4)
	title.name = "FilterTitle"
	title.size = Vector2(460, 56)
	var hint := UiKit.label(_panel,
		"先选择玩法，再选择星级；再次点击已选项可取消", 17,
		Vector2(47, 98), E5OriginalTheme.MUTED, 0)
	hint.name = "FilterHint"
	hint.size = Vector2(580, 30)

	_lbl_summary = UiKit.label(_panel, "", 18, Vector2(636, 49),
		E5OriginalTheme.GOLD, 0)
	_lbl_summary.name = "FilterSummary"
	_lbl_summary.size = Vector2(292, 38)
	_lbl_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var close_hint := UiKit.label(_panel, "ESC / 点击空白关闭    ALL 清空", 14,
		Vector2(620, 94), E5OriginalTheme.CYAN_SOFT, 0)
	close_hint.size = Vector2(310, 28)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	E5OriginalTheme.add_rule(_panel, Rect2(44, 135, PANEL_W - 88, 2))


func is_open() -> bool:
	return visible


## styles=当前列表出现的玩法集合；stars_provider(style)->Array 星级集合
func open(styles: Array, stars_provider: Callable, style: String, star: int) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_styles = styles
	_stars_provider = stars_provider
	_style = style
	_star = star
	_rebuild()
	visible = true
	UiKit.animate_arcade_in(_panel, Vector2(-24, 0), 0.17)


func close() -> void:
	visible = false


func _rebuild() -> void:
	if _content != null:
		if _content.get_parent() == _panel:
			_panel.remove_child(_content)
		_content.queue_free()
	_content = Control.new()
	_content.name = "FilterContent"
	_content.position = Vector2.ZERO
	_content.size = _panel.size
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_content)

	var summary := _summary_text()
	_lbl_summary.text = "CURRENT  %s" % (summary if not summary.is_empty() else "ALL SONGS")
	_lbl_summary.add_theme_color_override("font_color",
		E5OriginalTheme.GOLD if not summary.is_empty() else E5OriginalTheme.CYAN_SOFT)

	var zone_w := PANEL_W - PAD * 2.0
	var y := PAD + TITLE_ZONE + 24.0

	var style_title := UiKit.label(_content, "01  玩法筛选  /  PLAY STYLE", 17,
		Vector2(PAD + 18.0, y - 34.0), E5OriginalTheme.CYAN_SOFT, 0)
	style_title.size = Vector2(430, 28)
	var style_values: Array = [""]
	style_values.append_array(_styles)
	var bw := maxf(132.0, minf(196.0, zone_w * 0.18))
	var bh := maxf(52.0, bw * 0.34)
	var gap := maxf(10.0, bh * 0.22)
	y = _grid(style_values, y, bw, bh, gap, zone_w,
		func(v): return "ALL  全部玩法" if str(v).is_empty() else str(v),
		func(v): return str(v) == _style,
		_on_style_pressed)

	y += 54.0
	var star_title := UiKit.label(_content, "02  星级筛选  /  DIFFICULTY", 17,
		Vector2(PAD + 18.0, y - 36.0), E5OriginalTheme.CYAN_SOFT, 0)
	star_title.size = Vector2(430, 28)
	var stars: Array = _stars_provider.call(_style) if _stars_provider.is_valid() else []
	var sw := maxf(88.0, minf(144.0, zone_w * 0.145))
	var sh := maxf(60.0, sw * 0.56)
	var sgap := maxf(8.0, sw * 0.07)
	_grid(stars, y, sw, sh, sgap, zone_w,
		func(v): return "★  %02d" % int(v),
		func(v): return int(v) == _star and _star > 0,
		_on_star_pressed)


## 居中网格布局，返回网格底部 y。
func _grid(values: Array, start_y: float, bw: float, bh: float, gap: float,
		zone_w: float, text_of: Callable, is_selected: Callable, on_press: Callable) -> float:
	if values.is_empty():
		var empty := UiKit.label(_content, "当前曲库没有可用项目", 17,
			Vector2(PANEL_W * 0.5 - 160.0, start_y + 12.0), E5OriginalTheme.MUTED, 0)
		empty.size = Vector2(320, 34)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return start_y + 54.0
	var cols := maxi(1, mini(int((zone_w + gap) / (bw + gap)), values.size()))
	var rows := int(ceilf(float(values.size()) / cols))
	var idx := 0
	for row in rows:
		var n := mini(cols, values.size() - idx)
		var row_w := n * bw + (n - 1) * gap
		var x0 := PANEL_W * 0.5 - row_w * 0.5
		for col in n:
			var v = values[idx]
			_filter_button(str(text_of.call(v)), bool(is_selected.call(v)),
				Vector2(x0 + col * (bw + gap), start_y + row * (bh + gap)),
				Vector2(bw, bh), on_press.bind(v))
			idx += 1
	return start_y + rows * bh + (rows - 1) * gap


func _filter_button(text: String, selected: bool, pos: Vector2, sz: Vector2,
		on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.custom_minimum_size = sz
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.skin_arcade_button(b, selected, false, 20,
		E5OriginalTheme.MAGENTA if text.begins_with("★") else E5OriginalTheme.CYAN)
	b.pressed.connect(on_press)
	_content.add_child(b)


func _summary_text() -> String:
	var parts := []
	if not _style.is_empty():
		parts.append("%s" % _style)
	if _star > 0:
		parts.append("%d★" % _star)
	return "  /  ".join(parts)


func _on_style_pressed(v) -> void:
	var s := str(v)
	_style = "" if _style == s else s
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	_rebuild()
	filter_changed.emit(_style, _star)


func _on_star_pressed(v) -> void:
	var n := int(v)
	_star = 0 if _star == n else n
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	_rebuild()
	filter_changed.emit(_style, _star)


func _on_mask_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		accept_event()
		get_viewport().set_input_as_handled()
		call_deferred("close")
