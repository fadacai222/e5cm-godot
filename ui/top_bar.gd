class_name TopBar
extends RefCounted
## 原版 top 栏：top栏背景.png（1918×161）缩放到 1920×150，标题居中于蓝色框。
## 标题图键：模式选择 / 玩法选择 / 歌曲选择 / 个人中心 / 收藏夹

const TOP_HEIGHT := 150.0
const TITLE_MAX_WIDTH := 960.0
const TITLE_HEIGHT := 75.0
const TITLE_CENTER := Vector2(960, 60)
const CREDIT_SCALE := 0.82
const ENTRY_START_OFFSET := 166.0
const ENTRY_DURATION_SECONDS := 0.24
const ENTRY_META := &"e5cm_top_bar_entry_played"


## 场景完成加载后统一播放公共 Top 栏入场。重复调用不会重复播放。
static func play_scene_entry(scene_root: Node) -> Tween:
	if scene_root == null:
		return null
	var holder := scene_root.get_node_or_null("TopBar") as Control
	if holder == null:
		holder = scene_root.find_child("TopBar", true, false) as Control
	return play_entry(holder)


## 从屏幕上方快速滑入。动画不参与场景路由等待，不改变透明度，不做回弹。
static func play_entry(holder: Control) -> Tween:
	if holder == null or not is_instance_valid(holder) or not holder.is_inside_tree():
		return null
	if bool(holder.get_meta(ENTRY_META, false)):
		return null
	holder.set_meta(ENTRY_META, true)

	var final_position := holder.position
	holder.position = final_position - Vector2(0.0, maxf(ENTRY_START_OFFSET, holder.size.y + 16.0))

	var tween := holder.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(holder, "position:y", final_position.y, ENTRY_DURATION_SECONDS) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween


static func add(parent: Control, title_key: String) -> Control:
	var holder := Control.new()
	holder.name = "TopBar"
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_bottom = TOP_HEIGHT
	holder.z_index = 80
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)

	var bg := TextureRect.new()
	bg.name = "TopBarBackground"
	bg.texture = AssetLoader.tex_key("top栏背景")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bg)

	var title := TextureRect.new()
	title.name = "TopBarTitle"
	title.texture = AssetLoader.tex_key("top标题_%s" % title_key)
	var title_width := 1.0
	if title.texture != null and title.texture.get_height() > 0:
		title_width = minf(TITLE_MAX_WIDTH,
			TITLE_HEIGHT * float(title.texture.get_width()) / float(title.texture.get_height()))
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(title)
	title.size = Vector2(title_width, TITLE_HEIGHT)
	title.position = TITLE_CENTER - title.size * 0.5
	return holder


## 底部联网图标 + CREDIT（对应旧 绘制底部联网与信用）
static func add_bottom_credit(parent: Control) -> Label:
	var center := CenterContainer.new()
	center.name = "BottomCreditCenter"
	center.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	center.offset_top = -89.0
	center.offset_bottom = -34.0
	center.z_index = 90
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)

	var row := HBoxContainer.new()
	row.name = "BottomCreditRow"
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)

	var icon := TextureRect.new()
	icon.name = "CreditOnlineIcon"
	icon.texture = AssetLoader.tex_key("投币_联网图标")
	icon.custom_minimum_size = Vector2(64, 55) * CREDIT_SCALE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var lbl := Label.new()
	lbl.name = "CreditLabel"
	lbl.text = _credit_text(GameState.credits)
	lbl.custom_minimum_size = Vector2(0, 55 * CREDIT_SCALE)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 23)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var update_credit: Callable = func(c: int):
		if is_instance_valid(lbl):
			lbl.text = _credit_text(c)
	GameState.credits_changed.connect(update_credit)
	# 匿名回调不会随 Label 自动断开；场景销毁时主动清理，避免菜单切换后累积连接。
	lbl.tree_exiting.connect(func():
		if is_instance_valid(GameState) and GameState.credits_changed.is_connected(update_credit):
			GameState.credits_changed.disconnect(update_credit)
	, CONNECT_ONE_SHOT)
	return lbl


static func _credit_text(credits: int) -> String:
	return "CREDIT：%d/%d" % [maxi(0, credits), GameState.CREDITS_PER_GAME]
