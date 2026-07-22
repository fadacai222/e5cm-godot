class_name SongDetail
extends Control
## 选歌详情大图页 —— 原版布局（config/layout/选歌布局.json 详情大图/缩略图大框/卡片槽位.大图）：
## 内容框=中间区域高0.8×比例1.5×框缩放(1.1,1.15)居中；装饰贴图=缩略图大.png×(1.07,1.02)；
## 封面(0.05,0.02,0.95)+信息条0.35h（大星星行居中、歌名自适应缩字、分割线、游玩次数+BPM）；
## 左右切歌按钮=下一首.png(高0.28框高、外间距58)；收藏按钮(高0.13框高)；热门角标右下；
## 入场500ms淡入+上移37px（对应旧 绘制详情浮层/进入详情_原始索引）。

signal prev_requested
signal next_requested
signal start_requested
signal favorite_toggled
signal close_requested

const CENTER_AREA := Rect2(0, 96, 1920, 880)
const TARGET_RATIO := 1.5
const AVAIL_H_RATIO := 0.8
const FRAME_SCALE := Vector2(1.1, 1.15)      # 缩略图大框 宽/高缩放
const ORNAMENT_SCALE := Vector2(1.07, 1.02)  # 详情大框贴图 宽/高缩放
const MASK_ALPHA := 150.0 / 255.0

# 卡片槽位.大图（选歌布局.json）
const COVER_L := 0.05
const COVER_T := 0.02
const COVER_W := 0.95
const INFO_H := 0.35
const INFO_PAD := 0.04
const STAR_H := 0.3
const TEXT_PAD := 0.05
const BOTTOM_H := 0.245
const BOTTOM_PAD := 0.1

var _mask: ColorRect
var _mover: Control
var _panel: Control
var _btn_prev: TextureButton
var _btn_next: TextureButton
var _btn_fav: TextureButton
var _panel_rect := Rect2()


func _ready() -> void:
	# 该节点由代码动态加入场景；仅设置 anchors 不会可靠地产生尺寸，必须显式铺满 Viewport。
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = false
	# 弹层打开期间根节点自身就是完整输入边界；隐藏节点不会参与命中。
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_mask_input)
	z_index = 20

	_mask = ColorRect.new()
	_mask.name = "InputBlocker"
	_mask.color = Color(0, 0, 0, MASK_ALPHA)
	_mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_STOP
	_mask.gui_input.connect(_on_mask_input)
	add_child(_mask)

	_mover = Control.new()
	_mover.name = "AnimationLayer"
	_mover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# PASS 让内容子控件优先命中，同时让剩余空白由本层消费并关闭。
	_mover.mouse_filter = Control.MOUSE_FILTER_PASS
	_mover.gui_input.connect(_on_mask_input)
	add_child(_mover)

	_panel_rect = _compute_panel_rect()
	_build_side_buttons()


func _compute_panel_rect() -> Rect2:
	var avail_w := CENTER_AREA.size.x
	var avail_h := CENTER_AREA.size.y * AVAIL_H_RATIO
	var base_w := minf(avail_w, avail_h * TARGET_RATIO)
	var content := Vector2(base_w, base_w / TARGET_RATIO) * FRAME_SCALE
	var panel_size := content * ORNAMENT_SCALE
	return Rect2(CENTER_AREA.get_center() - panel_size * 0.5, panel_size)


func _build_side_buttons() -> void:
	var next_tex := AssetLoader.tex("UI-img/选歌界面资源/下一首.png")
	var btn_h := maxf(80.0, _panel_rect.size.y * 0.28)
	var ratio := 150.0 / 74.0
	if next_tex != null and next_tex.get_height() > 0:
		ratio = float(next_tex.get_width()) / float(next_tex.get_height())
	var btn_w := maxf(36.0, btn_h * ratio)
	var btn_y := _panel_rect.get_center().y - btn_h * 0.5

	_btn_prev = _tex_button(next_tex, Vector2(maxf(10.0, _panel_rect.position.x - 58.0 - btn_w), btn_y),
		Vector2(btn_w, btn_h), func(): prev_requested.emit())
	_btn_prev.flip_h = true
	_btn_next = _tex_button(next_tex, Vector2(minf(1920.0 - 10.0 - btn_w, _panel_rect.end.x + 58.0), btn_y),
		Vector2(btn_w, btn_h), func(): next_requested.emit())

	var fav_h := maxf(48.0, _panel_rect.size.y * 0.13)
	var fav_y := clampf(_panel_rect.position.y + _panel_rect.size.y * 0.17, 12.0, 1080.0 - fav_h - 12.0)
	_btn_fav = _tex_button(null, Vector2(0, fav_y), Vector2(fav_h, fav_h), func(): favorite_toggled.emit())


func _tex_button(tex: Texture2D, pos: Vector2, sz: Vector2, on_pressed: Callable) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = tex
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
	b.position = pos
	b.custom_minimum_size = sz
	b.size = sz
	b.pressed.connect(on_pressed)
	_mover.add_child(b)
	return b


func is_open() -> bool:
	return visible


## 打开（animate=入场动画）或刷新（切歌时 animate=false）
func show_song(song: Dictionary, record: Dictionary, is_fav: bool, animate: bool,
		favorite_action_visible := true) -> void:
	_rebuild_panel(song, record)
	_btn_fav.visible = favorite_action_visible
	_btn_fav.disabled = not favorite_action_visible
	if favorite_action_visible:
		_update_fav_button(is_fav)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not visible:
		visible = true
		if animate:
			_play_entrance()
	elif animate:
		_play_entrance()


func close() -> void:
	visible = false
	close_requested.emit()


func _play_entrance() -> void:
	var rise := 37.8  # max(18, min(48, 1080*0.035))
	_mover.modulate.a = 0.0
	_mover.position = Vector2(0, rise)
	_mask.color.a = 0.0
	var tw := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(_mover, "modulate:a", 1.0, 0.5)
	tw.tween_property(_mover, "position:y", 0.0, 0.5)
	tw.tween_property(_mask, "color:a", MASK_ALPHA, 0.5)


func _update_fav_button(is_fav: bool) -> void:
	var rel := "UI-img/选歌界面资源/移除收藏.png" if is_fav else "UI-img/选歌界面资源/添加收藏.png"
	var tex := AssetLoader.tex(rel)
	_btn_fav.texture_normal = tex
	var fav_h := maxf(48.0, _panel_rect.size.y * 0.13)
	var ratio := 220.0 / 96.0
	if tex != null and tex.get_height() > 0:
		ratio = float(tex.get_width()) / float(tex.get_height())
	var fav_w := maxf(90.0, fav_h * ratio)
	_btn_fav.custom_minimum_size = Vector2(fav_w, fav_h)
	_btn_fav.size = _btn_fav.custom_minimum_size
	_btn_fav.position.x = minf(1920.0 - fav_w - 12.0, _panel_rect.end.x + maxf(16.0, 1920.0 * 0.012))


func _rebuild_panel(song: Dictionary, record: Dictionary) -> void:
	if _panel != null:
		_panel.queue_free()
	_panel = Control.new()
	_panel.name = "ContentPanel"
	_panel.position = _panel_rect.position
	_panel.size = _panel_rect.size
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	_mover.add_child(_panel)
	_mover.move_child(_panel, 0)

	# 内容矩形（框缩放后）居中于装饰贴图
	var content_size := _panel_rect.size / ORNAMENT_SCALE
	var content_pos := (_panel_rect.size - content_size) * 0.5

	# 槽位布局（对应旧 compute_frame_slot_layout 是否大图=True）
	var cover := Rect2(content_pos + Vector2(content_size.x * COVER_L, content_size.y * COVER_T),
		Vector2(content_size.x * COVER_W, content_size.y * (1.0 - COVER_T)))
	var info_h := maxf(14.0, cover.size.y * INFO_H)
	var info := Rect2(Vector2(cover.position.x, cover.end.y - info_h), Vector2(cover.size.x, info_h))
	var info_pad := maxf(4.0, info.size.x * INFO_PAD)
	var star_rect := Rect2(Vector2(info.position.x + info_pad, info.position.y + 1.0),
		Vector2(maxf(10.0, info.size.x - info_pad * 2.0), maxf(6.0, info.size.y * STAR_H)))
	var text_pad := maxf(4.0, info.size.x * TEXT_PAD)
	var bottom_h := maxf(10.0, info.size.y * BOTTOM_H)
	var bottom_pad := maxf(1.0, info.size.y * BOTTOM_PAD)
	var bottom := Rect2(Vector2(info.position.x + text_pad, info.end.y - bottom_h - bottom_pad),
		Vector2(maxf(10.0, info.size.x - text_pad * 2.0), bottom_h))

	# 封面（拉伸填满，原版 stretch 模式）
	var cover_tr := TextureRect.new()
	cover_tr.texture = AssetLoader.tex(str(song.get("cover", "")))
	cover_tr.position = cover.position
	cover_tr.custom_minimum_size = cover.size
	cover_tr.size = cover.size
	cover_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover_tr.stretch_mode = TextureRect.STRETCH_SCALE
	cover_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(cover_tr)
	if cover_tr.texture == null:
		var ph := ColorRect.new()
		ph.color = Color(18.0 / 255.0, 18.0 / 255.0, 24.0 / 255.0)
		ph.position = cover.position
		ph.size = cover.size
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(ph)

	# 信息条半透明底
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 155.0 / 255.0)
	bar.position = info.position
	bar.size = info.size
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(bar)

	_add_star_rows(star_rect, int(song.get("star", 0)))

	# 歌名（居中，超宽自动缩字号）+ 分割线
	var name_text := _display_name(str(song.get("name", "")))
	var name_lbl := UiKit.label(_panel, name_text, 16, Vector2.ZERO, Color.WHITE, 0)
	var font := name_lbl.get_theme_font("font")
	var fsize := maxi(16, int(info.size.y * 0.22))
	var max_w := maxf(80.0, info.size.x * 0.84)
	while fsize > 16 and font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > max_w:
		fsize -= 1
	name_lbl.add_theme_font_size_override("font_size", fsize)
	var name_w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var name_h := font.get_height(fsize)
	var gap := maxf(4.0, info.size.y * 0.03)
	name_lbl.position = Vector2(info.position.x + (info.size.x - name_w) * 0.5, star_rect.end.y + gap)

	var line := ColorRect.new()
	line.color = Color(165.0 / 255.0, 165.0 / 255.0, 165.0 / 255.0)
	var line_inset := maxf(12.0, info.size.x * 0.06)
	line.position = Vector2(info.position.x + line_inset, name_lbl.position.y + name_h + gap)
	line.size = Vector2(info.size.x - line_inset * 2.0, maxf(1.0, info.size.y * 0.012))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(line)

	# 底栏：游玩次数（按次数着色）+ BPM
	var play_count := int(record.get("游玩次数", 0))
	var bfsize := maxi(12, int(info.size.y * 0.13))
	var bh := font.get_height(bfsize)
	var play_lbl := UiKit.label(_panel, "游玩次数:%d" % play_count, bfsize,
		Vector2(bottom.position.x, bottom.get_center().y - bh * 0.5), _play_count_color(play_count), 0)
	play_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bpm: float = float(song.get("bpm", 0.0))
	var bpm_text := "BPM:?"
	if bpm > 0.0:
		bpm_text = "BPM:%d" % int(roundf(bpm)) if absf(bpm - roundf(bpm)) < 0.05 else "BPM:%.1f" % bpm
	var bpm_w := font.get_string_size(bpm_text, HORIZONTAL_ALIGNMENT_LEFT, -1, bfsize).x
	var bpm_lbl := UiKit.label(_panel, bpm_text, bfsize,
		Vector2(bottom.end.x - bpm_w, bottom.get_center().y - bh * 0.5),
		Color(230.0 / 255.0, 230.0 / 255.0, 230.0 / 255.0), 0)
	bpm_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 装饰大框贴图（盖在内容上层，拉伸铺满面板）
	var frame := TextureRect.new()
	frame.texture = AssetLoader.tex("UI-img/选歌界面资源/缩略图大.png")
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(frame)

	# 角标（NEW 左上沿用卡片规则；热门 右下，对应旧 渲染详情角标模块）
	if bool(song.get("is_new", false)):
		_corner_badge("UI-img/选歌界面资源/NEW绿色.png", 0.3, true)
	if play_count >= 10:
		_corner_badge("UI-img/选歌界面资源/热门.png", 0.34, false)


## 星级行：≤10 单排居中；>10 上排放超出数、下排固定10；超宽自动缩小（对应旧 绘制星星行_图片）
func _add_star_rows(region: Rect2, star: int) -> void:
	if star <= 0:
		return
	var tex := AssetLoader.tex("UI-img/选歌界面资源/小星星/大星星.png")
	if tex == null:
		return
	var ratio := float(tex.get_width()) / float(maxf(1.0, tex.get_height()))
	var star_h := maxf(6.0, region.size.y * 0.34) * 1.65
	var top_n := star if star <= 10 else star - 10
	var bottom_n := 0 if star <= 10 else 10
	var rows := 1 if bottom_n == 0 else 2

	for i in 18:
		var w := star_h * ratio
		var spacing := maxf(1.0, w * 0.10)
		var row_gap := star_h * 0.02
		var max_row_w := maxf(top_n * w + maxf(0, top_n - 1) * spacing,
			bottom_n * w + maxf(0, bottom_n - 1) * spacing)
		var total_h := star_h if rows == 1 else star_h * 2.0 + row_gap
		if total_h <= region.size.y and max_row_w <= region.size.x:
			break
		star_h = maxf(3.0, star_h * 0.92)

	var w := star_h * ratio
	var spacing := maxf(1.0, w * 0.10)
	var row_gap := star_h * 0.02
	var total_h := star_h if rows == 1 else star_h * 2.0 + row_gap
	var y := region.position.y + (region.size.y - total_h) * 0.5
	for row in rows:
		var n := top_n if row == 0 else bottom_n
		var row_w := n * w + maxf(0, n - 1) * spacing
		var x := region.get_center().x - row_w * 0.5
		for k in n:
			var st := TextureRect.new()
			st.texture = tex
			st.position = Vector2(x + k * (w + spacing), y + row * (star_h + row_gap))
			st.custom_minimum_size = Vector2(w, star_h)
			st.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			st.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			st.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_panel.add_child(st)


func _corner_badge(rel: String, h_ratio: float, top_left: bool) -> void:
	var tex := AssetLoader.tex(rel)
	if tex == null:
		return
	var h := maxf(14.0, _panel_rect.size.y * h_ratio)
	var w := h * float(tex.get_width()) / float(maxf(1.0, tex.get_height()))
	var t := TextureRect.new()
	t.texture = tex
	if top_left:
		t.position = Vector2(-w * 0.15, -h * 0.15)
	else:
		var pad := maxf(6.0, h * 0.10)
		t.position = Vector2(_panel_rect.size.x - w - pad + w * 0.5,
			_panel_rect.size.y - h - pad + h * 0.10)
	t.custom_minimum_size = Vector2(w, h)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(t)


## 去掉尾部 "#123" 序号、下划线转空格（对应旧 _format_song_display_name）
static func _display_name(raw: String) -> String:
	var text := raw.strip_edges().replace("_", " ")
	var re := RegEx.create_from_string("\\s*[#＃]\\s*\\d+\\s*$")
	return re.sub(text, "").strip_edges()


static func _play_count_color(n: int) -> Color:
	if n >= 5:
		return Color(1.0, 96.0 / 255.0, 96.0 / 255.0)
	if n >= 3:
		return Color(1.0, 214.0 / 255.0, 72.0 / 255.0)
	if n >= 1:
		return Color(96.0 / 255.0, 232.0 / 255.0, 128.0 / 255.0)
	return Color(235.0 / 255.0, 235.0 / 255.0, 235.0 / 255.0)


func _consume_gui_event() -> void:
	accept_event()
	get_viewport().set_input_as_handled()


func _on_panel_input(event: InputEvent) -> void:
	if _handle_wheel(event):
		_consume_gui_event()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_consume_gui_event()
		start_requested.emit()


func _on_mask_input(event: InputEvent) -> void:
	if _handle_wheel(event):
		_consume_gui_event()
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		# 当前按下事件必须先被弹层完整消费；下一空闲帧再隐藏，杜绝同一点击落到底层卡片。
		_consume_gui_event()
		call_deferred("close")


func _handle_wheel(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			prev_requested.emit()
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			next_requested.emit()
			return true
	return false
