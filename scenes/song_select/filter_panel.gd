class_name FilterPanel
extends Control
## 玩法/星级筛选页 —— 对应旧 绘制星级筛选页/_重算星级筛选页布局：
## 遮罩170 + 面板980×720（底色10,20,40,220、圆角18、边框3 180,220,255）；
## 标题"玩法 / 星级筛选" + 说明行 + 当前筛选摘要；
## 玩法按钮行=全部玩法+当前列表出现的玩法标记（疯狂/表演/混音/双踏板/情侣，居中网格）；
## 星级按钮网格=当前玩法筛选下出现的星级；点已选项=取消该项；ESC/点空白=关闭。

signal filter_changed(style: String, star: int)

const PANEL_W := 980.0
const PANEL_H := 720.0
const PAD := 26.0
const TITLE_ZONE := 148.0

var _style := ""
var _star := 0
var _styles: Array = []
var _stars_provider: Callable   # func(style: String) -> Array[int]

var _mask: ColorRect
var _panel: Panel
var _lbl_summary: Label
var _content: Control


func _ready() -> void:
	# 动态节点只设 anchors 时可能保持 0×0；显式铺满 Viewport 才能真正拦截鼠标。
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = false
	# 弹层打开时根节点完整接管鼠标；隐藏节点不会参与命中。
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 22

	_mask = ColorRect.new()
	_mask.name = "InputBlocker"
	_mask.color = Color(0, 0, 0, 170.0 / 255.0)
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_STOP
	_mask.gui_input.connect(_on_mask_input)
	add_child(_mask)

	_panel = Panel.new()
	_panel.name = "ContentPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(10.0 / 255.0, 20.0 / 255.0, 40.0 / 255.0, 220.0 / 255.0)
	sb.border_color = Color(180.0 / 255.0, 220.0 / 255.0, 1.0)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(18)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2((1920.0 - PANEL_W) * 0.5, (1080.0 - PANEL_H) * 0.5)
	_panel.size = Vector2(PANEL_W, PANEL_H)
	add_child(_panel)

	UiKit.center_label(_panel, "玩法 / 星级筛选", 36, 18).offset_left = 0
	var hint := UiKit.center_label(_panel,
		"先点玩法，再点星级完成组合筛选；ESC / 点空白关闭，ALL 清空全部筛选", 18,
		66, Color(210.0 / 255.0, 235.0 / 255.0, 1.0))
	hint.add_theme_constant_override("outline_size", 0)
	_lbl_summary = UiKit.center_label(_panel, "", 18, 96)
	_lbl_summary.add_theme_constant_override("outline_size", 0)


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


func close() -> void:
	visible = false


func _rebuild() -> void:
	if _content != null:
		_content.queue_free()
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_content)

	var summary := _summary_text()
	_lbl_summary.text = "当前：%s" % (summary if not summary.is_empty() else "全部歌曲")
	_lbl_summary.add_theme_color_override("font_color",
		Color(1.0, 223.0 / 255.0, 135.0 / 255.0) if not summary.is_empty()
		else Color(182.0 / 255.0, 210.0 / 255.0, 234.0 / 255.0))

	var zone_w := PANEL_W - PAD * 2.0
	var y := PAD + TITLE_ZONE + 28.0

	# 玩法按钮行（"" = 全部玩法）
	var style_values: Array = [""]
	style_values.append_array(_styles)
	var bw := maxf(132.0, minf(196.0, zone_w * 0.18))
	var bh := maxf(52.0, bw * 0.34)
	var gap := maxf(10.0, bh * 0.22)
	UiKit.label(_content, "玩法筛选", 18, Vector2(PAD + 30.0, y - 28.0),
		Color(196.0 / 255.0, 226.0 / 255.0, 1.0), 0)
	y = _grid(style_values, y, bw, bh, gap, zone_w,
		func(v): return "全部玩法" if str(v).is_empty() else str(v),
		func(v): return str(v) == _style,
		_on_style_pressed)

	y += 42.0
	# 星级按钮网格（受当前玩法筛选影响）
	var stars: Array = _stars_provider.call(_style) if _stars_provider.is_valid() else []
	var sw := maxf(88.0, minf(144.0, zone_w * 0.145))
	var sh := maxf(60.0, sw * 0.56)
	var sgap := maxf(8.0, sw * 0.07)
	UiKit.label(_content, "星级筛选", 18, Vector2(PAD + 30.0, y - 28.0),
		Color(196.0 / 255.0, 226.0 / 255.0, 1.0), 0)
	_grid(stars, y, sw, sh, sgap, zone_w,
		func(v): return "%d ★" % int(v),
		func(v): return int(v) == _star and _star > 0,
		_on_star_pressed)


## 居中网格布局（对应旧 _布局中心网格），返回网格底部 y
func _grid(values: Array, start_y: float, bw: float, bh: float, gap: float,
		zone_w: float, text_of: Callable, is_selected: Callable, on_press: Callable) -> float:
	if values.is_empty():
		return start_y
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
	b.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(10)
	if selected:
		sb.bg_color = Color(1.0, 214.0 / 255.0, 72.0 / 255.0, 0.92)
		b.add_theme_color_override("font_color", Color(20.0 / 255.0, 24.0 / 255.0, 40.0 / 255.0))
		b.add_theme_color_override("font_hover_color", Color(20.0 / 255.0, 24.0 / 255.0, 40.0 / 255.0))
		b.add_theme_color_override("font_pressed_color", Color(20.0 / 255.0, 24.0 / 255.0, 40.0 / 255.0))
	else:
		sb.bg_color = Color(30.0 / 255.0, 50.0 / 255.0, 90.0 / 255.0, 0.9)
		sb.border_color = Color(120.0 / 255.0, 160.0 / 255.0, 210.0 / 255.0, 0.8)
		sb.set_border_width_all(1)
	b.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = sb.bg_color.lightened(0.15)
	b.add_theme_stylebox_override("hover", sb_hover)
	b.add_theme_stylebox_override("pressed", sb_hover)
	b.pressed.connect(on_press)
	_content.add_child(b)


func _summary_text() -> String:
	var parts := []
	if not _style.is_empty():
		parts.append("玩法·%s" % _style)
	if _star > 0:
		parts.append("星级·%d★" % _star)
	return "  ".join(parts)


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
		# 先消费当前事件，下一空闲帧再隐藏，避免同一次点击继续命中缩略图。
		call_deferred("close")
