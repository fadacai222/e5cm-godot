extends Control
## 个人中心：按原版 2048×1152 布局等比换算到 1920×1080。

const SCALE := 0.9375
const STAT_FONT_SIZE := 21
const STAT_LABEL_COLOR := Color.WHITE
const STAT_VALUE_COLOR := Color(1.0, 220.0 / 255.0, 80.0 / 255.0)
const STAT_SONG_COLOR := Color(190.0 / 255.0, 140.0 / 255.0, 1.0)
const WELCOME_TEXT := "e舞成名重构版（测试）为非盈利性的游戏；\n本游戏软件为交流、学习、测试使用，如有侵权，请率先联系我们。\n如果你有意参与我们的开发项目；\n请进人QQ群：1084318862\n进群后联系Emma_H。"
const DISCLAIMER_TEXT := "本游戏设计初衷是为了让更多e舞玩家能在各地玩到e舞成名，本项目纯爱发电，没有任何盈利性质，如您发现有人倒卖本软件，请及时联系我们。"

@onready var _avatar_view: TextureRect = $ProfileAvatar
@onready var _nickname_label: Label = $ProfileNickname
var _avatar_dialog: Control
var _nickname_dialog: Control
var _nickname_input: LineEdit
var _avatar_path_input: LineEdit
var _editor_overlay: Control
var _editor_preview: TextureRect
@onready var _leave_button: TextureButton = $LeaveButton
@onready var _credit_label: Label = $BottomCreditCenter/BottomCreditRow/CreditLabel
var _profile_fill_atlases := {}


func _ready() -> void:
	SceneRouter.take_payload()
	SharedVideoBackground.continue_sequence()
	$ProfileTopPanel.texture = AssetLoader.tex("UI-img/个人中心-个人资料/上背景.png")
	$ProfileBottomPanel.texture = AssetLoader.tex("UI-img/个人中心-个人资料/下背景.png")
	_build_identity()
	_build_progress("花式", Rect2(633, 387, 969, 35))
	_build_progress("竞速", Rect2(632, 437, 969, 35))
	_build_software_info()
	_leave_button.texture_normal = AssetLoader.tex("UI-img/个人中心-个人资料/离开.png")
	_leave_button.pressed.connect(_confirm)
	$AvatarEditButton.pressed.connect(_open_avatar_editor)
	$NicknameEditButton.pressed.connect(_open_nickname_editor)
	_update_credit_label(GameState.credits)
	GameState.credits_changed.connect(_update_credit_label)


func _update_credit_label(credits: int) -> void:
	_credit_label.text = "CREDIT：%d/%d" % [maxi(0, credits), GameState.CREDITS_PER_GAME]


func _r(source: Rect2) -> Rect2:
	return Rect2(source.position * SCALE, source.size * SCALE)


func _add_texture(name_text: String, path: String, source: Rect2) -> TextureRect:
	var rect := _r(source)
	var view := TextureRect.new()
	view.name = name_text
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.texture = AssetLoader.tex(path)
	view.position = rect.position
	view.custom_minimum_size = rect.size
	view.size = rect.size
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	return view


func _add_texture_button(name_text: String, path: String, source: Rect2, cb: Callable) -> TextureButton:
	var rect := _r(source)
	var button := TextureButton.new()
	button.name = name_text
	button.texture_normal = AssetLoader.tex(path)
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(cb)
	add_child(button)
	return button


func _label(text: String, font_size: int, source: Rect2, color := Color.WHITE,
		alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var rect := _r(source)
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", maxi(10, int(font_size * SCALE)))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.82))
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
	return label


func _build_identity() -> void:
	var profile: Dictionary = ProfileStore.profile
	var avatar_path := str(profile.get("头像文件", ""))
	_avatar_view.texture = AssetLoader.tex(avatar_path)
	if _avatar_view.texture == null:
		_avatar_view.texture = AssetLoader.tex("UI-img/个人中心-个人资料/默认头像.png")
	_nickname_label.text = str(profile.get("昵称", "玩家"))

	var progress: Dictionary = ProfileStore.get_mode_progress("花式")
	$RankBadge.texture = AssetLoader.tex(ProfileStore.get_rank_asset_path())

	var stats: Dictionary = profile.get("统计", {})
	var rows := [
		["游玩时长：", "%d分钟" % int(stats.get("游玩时长分钟", 0)), ""],
		["累计评价S：", str(int(stats.get("累计评价S数", 0))), ""],
		["最大Combo：", str(int(stats.get("最大Combo", 0))),
			"（%s）" % str(stats.get("最大Combo曲目", ""))],
		["最高分：", str(int(stats.get("最高分", 0))),
			"（%s）" % str(stats.get("最高分曲目", ""))],
	]
	var stat_font := FontVariation.new()
	stat_font.base_font = load("res://assets/fonts/fzhei.ttf") as Font
	stat_font.spacing_glyph = 2
	var widest_label := 0.0
	for row_data in rows:
		widest_label = maxf(widest_label, stat_font.get_string_size(
			str(row_data[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, STAT_FONT_SIZE).x)
	var value_column := widest_label + 23.0
	for i in rows.size():
		var row := get_node("Stat%d" % i) as Label
		# 固定长曲名比旧默认夹具更长，使用统计区与介绍区之间的安全留白；
		# 右边界仍停在介绍区左侧，不通过裁切或换行掩盖问题。
		row.size.x = 760.0
		_build_stat_line(row, rows[i], stat_font, value_column)

	var welcome := $WelcomeText as Label
	welcome.text = WELCOME_TEXT
	welcome.add_theme_font_override("font", stat_font)
	welcome.add_theme_font_size_override("font_size", 15)
	welcome.add_theme_color_override("font_color", Color(160.0 / 255.0, 160.0 / 255.0, 160.0 / 255.0))
	welcome.add_theme_constant_override("outline_size", 0)
	welcome.add_theme_constant_override("line_spacing", 3)
	welcome.vertical_alignment = VERTICAL_ALIGNMENT_TOP


func _build_stat_line(row: Label, parts: Array, font: Font, value_column: float) -> void:
	for child in row.get_children():
		child.queue_free()
	row.text = ""
	row.clip_text = false
	row.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_theme_constant_override("outline_size", 0)
	var font_size := STAT_FONT_SIZE
	# 固定资料使用全角括号，原版排版中数值与括号直接相接。
	var gap := 0.0
	var label_text := str(parts[0])
	var value_text := str(parts[1])
	var song_text := str(parts[2])
	while font_size > 14:
		var value_w := font.get_string_size(
			value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var song_w := font.get_string_size(
			song_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var total_right := value_column + value_w + (gap + song_w if not song_text.is_empty() else 0.0)
		if total_right <= row.size.x:
			break
		font_size -= 1
	var x_positions := [0.0, value_column]
	var value_width := font.get_string_size(
		value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	x_positions.append(value_column + value_width + gap)
	var values := [
		["LabelPart", label_text, STAT_LABEL_COLOR],
		["ValuePart", value_text, STAT_VALUE_COLOR],
		["SongPart", song_text, STAT_SONG_COLOR],
	]
	for i in values.size():
		var segment := Label.new()
		segment.name = str(values[i][0])
		segment.text = str(values[i][1])
		segment.position = Vector2(float(x_positions[i]), 0.0)
		var width := font.get_string_size(
			segment.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		segment.size = Vector2(ceilf(width), row.size.y)
		segment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		segment.clip_text = false
		segment.autowrap_mode = TextServer.AUTOWRAP_OFF
		segment.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		segment.add_theme_font_override("font", font)
		segment.add_theme_font_size_override("font_size", font_size)
		segment.add_theme_color_override("font_color", values[i][2])
		segment.add_theme_constant_override("outline_size", 0)
		row.add_child(segment)


func _add_edit_hotspot(node_name: String, source: Rect2, hint: String, cb: Callable) -> Button:
	var rect := _r(source)
	var button := Button.new()
	button.name = node_name
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = hint
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(cb)
	add_child(button)
	return button


func _open_avatar_editor() -> void:
	_build_editor_overlay("avatar")


func _apply_avatar_file(path: String) -> void:
	if not ProfileStore.set_avatar_file(path):
		UiKit.toast(self, "头像文件无效")
		return
	var texture := AssetLoader.tex(path)
	if texture != null:
		_avatar_view.texture = texture
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	call_deferred("_close_editor")


func _open_nickname_editor() -> void:
	_build_editor_overlay("nickname")


func _apply_nickname() -> void:
	if not ProfileStore.set_nickname(_nickname_input.text):
		UiKit.toast(self, "昵称不能为空")
		return
	_nickname_label.text = str(ProfileStore.profile.get("昵称", "玩家"))
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	call_deferred("_close_editor")


func _build_editor_overlay(kind: String) -> void:
	_close_editor()
	var overlay := ColorRect.new()
	overlay.name = "ProfileEditorOverlay"
	overlay.color = Color(0.008, 0.025, 0.045, 0.88)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 200
	add_child(overlay)
	_editor_overlay = overlay

	var panel := Panel.new()
	panel.name = "EditorPanel"
	panel.position = Vector2(510, 230)
	panel.size = Vector2(900, 620)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.065, 0.105, 0.985)
	style.border_color = Color(0.18, 0.63, 0.92, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(18)
	style.shadow_color = Color(0, 0, 0, 0.72)
	style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)

	var title_text := "修改昵称" if kind == "nickname" else "修改头像"
	var title := UiKit.label(panel, title_text, 42, Vector2(64, 42), Color(0.42, 0.88, 1.0), 5)
	title.size = Vector2(772, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if kind == "nickname":
		var help := UiKit.label(panel, "请输入新昵称（最多 16 个字符）", 24,
			Vector2(100, 144), Color(0.75, 0.84, 0.92), 3)
		help.size = Vector2(700, 46)
		_nickname_input = LineEdit.new()
		_nickname_input.name = "NicknameInput"
		_nickname_input.position = Vector2(100, 210)
		_nickname_input.size = Vector2(700, 68)
		_nickname_input.max_length = 16
		_nickname_input.add_theme_font_size_override("font_size", 28)
		_nickname_input.text = str(ProfileStore.profile.get("昵称", "玩家"))
		_nickname_input.text_submitted.connect(func(_text: String): _apply_nickname())
		panel.add_child(_nickname_input)
		_nickname_input.select_all()
		_nickname_input.grab_focus.call_deferred()
		_nickname_dialog = overlay
		_editor_button(panel, "保存昵称", Vector2(210, 430), _apply_nickname)
	else:
		_editor_preview = TextureRect.new()
		_editor_preview.name = "AvatarPreview"
		_editor_preview.texture = _avatar_view.texture
		_editor_preview.position = Vector2(350, 122)
		_editor_preview.size = Vector2(200, 200)
		_editor_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_editor_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_editor_preview.clip_contents = true
		panel.add_child(_editor_preview)
		var help_avatar := UiKit.label(panel, "输入本机 PNG/JPG/WEBP/BMP 图片路径", 22,
			Vector2(100, 340), Color(0.75, 0.84, 0.92), 3)
		help_avatar.size = Vector2(700, 42)
		_avatar_path_input = LineEdit.new()
		_avatar_path_input.name = "AvatarPathInput"
		_avatar_path_input.position = Vector2(100, 392)
		_avatar_path_input.size = Vector2(700, 58)
		_avatar_path_input.add_theme_font_size_override("font_size", 20)
		_avatar_path_input.placeholder_text = "C:\\Users\\...\\avatar.png"
		_avatar_path_input.text = str(ProfileStore.profile.get("头像文件", ""))
		_avatar_path_input.text_submitted.connect(func(path: String): _apply_avatar_file(path))
		panel.add_child(_avatar_path_input)
		_avatar_path_input.grab_focus.call_deferred()
		_avatar_dialog = overlay
		_editor_button(panel, "应用头像", Vector2(210, 500),
			func(): _apply_avatar_file(_avatar_path_input.text))
	_editor_button(panel, "取消", Vector2(500, 500 if kind == "avatar" else 430), _close_editor)


func _editor_button(parent: Control, text_value: String, pos: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = pos
	button.size = Vector2(190, 68)
	button.add_theme_font_size_override("font_size", 25)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _close_editor() -> void:
	if is_instance_valid(_editor_overlay):
		remove_child(_editor_overlay)
		_editor_overlay.queue_free()
	_editor_overlay = null
	_avatar_dialog = null
	_nickname_dialog = null
	_nickname_input = null
	_avatar_path_input = null
	_editor_preview = null


func _build_progress(mode: String, source: Rect2) -> void:
	var progress: Dictionary = ProfileStore.get_mode_progress(mode)
	var level := int(progress.get("等级", 1))
	var exp := float(progress.get("经验", 0.0))
	var need := maxi(1, ExpSystem.exp_to_next_level(level))
	var ratio := 1.0 if level >= ExpSystem.MAX_LEVEL else clampf(exp / float(need), 0.0, 1.0)
	var prefix := "Fancy" if mode == "花式" else "Speed"
	var fill := get_node("%sExpFill" % prefix) as TextureRect
	var frame := get_node("%sExpFrame" % prefix) as TextureRect
	var level_label := get_node("%sLevelLabel" % prefix) as Label
	var value_label := get_node("%sExpValue" % prefix) as Label
	var rect := _r(source)
	frame.position = rect.position
	frame.size = rect.size
	frame.custom_minimum_size = Vector2.ZERO
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture = AssetLoader.tex("UI-img/经验条/%s经验-框.png" % mode)
	fill.position = rect.position
	fill.custom_minimum_size = Vector2.ZERO
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	var fill_source := AssetLoader.tex("UI-img/经验条/%s经验-值.png" % mode)
	var atlas := AtlasTexture.new()
	atlas.atlas = fill_source
	_profile_fill_atlases[prefix] = atlas
	fill.texture = atlas

	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/fzhei.ttf") as Font
	font.spacing_glyph = 2
	var title_rect := _r(Rect2(source.position + Vector2(-238, -10),
		Vector2(230, source.size.y + 20)))
	level_label.position = title_rect.position
	level_label.size = title_rect.size
	level_label.text = "%s经验值：" % mode
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_font_override("font", font)
	level_label.add_theme_font_size_override("font_size", 23)
	level_label.add_theme_color_override("font_color", Color.WHITE)
	level_label.add_theme_constant_override("outline_size", 0)

	var value_rect := _r(Rect2(source.position + Vector2(source.size.x + 10, -10),
		Vector2(130, source.size.y + 20)))
	value_label.position = value_rect.position
	value_label.size = value_rect.size
	value_label.text = "Lv. %d" % level
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_override("font", font)
	value_label.add_theme_font_size_override("font_size", 23)
	value_label.add_theme_color_override("font_color", Color.WHITE)
	value_label.add_theme_constant_override("outline_size", 0)
	_apply_progress_ratio(prefix, ratio)


func _apply_progress_ratio(prefix: String, ratio: float) -> void:
	var frame := get_node_or_null("%sExpFrame" % prefix) as TextureRect
	var fill := get_node_or_null("%sExpFill" % prefix) as TextureRect
	var atlas = _profile_fill_atlases.get(prefix)
	if frame == null or fill == null or not atlas is AtlasTexture:
		return
	var value := clampf(ratio, 0.0, 1.0)
	fill.position = frame.position
	fill.size = Vector2(frame.size.x * value, frame.size.y)
	fill.visible = value > 0.0
	var source := (atlas as AtlasTexture).atlas
	if source != null:
		(atlas as AtlasTexture).region = Rect2(
			Vector2.ZERO, Vector2(float(source.get_width()) * value, source.get_height()))


func _build_software_info() -> void:
	$SoftwareBadge.texture = AssetLoader.tex("UI-img/个人中心-个人资料/软件信息.png")
	var info := $SoftwareInfo as RichTextLabel
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/fzhei.ttf") as Font
	font.spacing_glyph = 2
	info.bbcode_enabled = true
	info.scroll_active = false
	info.fit_content = false
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_override("normal_font", font)
	info.add_theme_font_override("bold_font", font)
	info.add_theme_font_size_override("normal_font_size", 18)
	info.add_theme_font_size_override("bold_font_size", 18)
	info.add_theme_constant_override("line_separation", 8)
	info.text = (
		"[color=#ffdc50]游戏版本：[/color][color=#ebebeb]e舞成名重构版4.12.1         [/color]"
		+ "[color=#ffdc50]开发团队：[/color][color=#ebebeb]程序工程师/策划/游戏制作人：良    UE/UI设计/策划：Emma_H（林曦）[/color]\n"
		+ "[color=#ffdc50]特别鸣谢（排名不分先后）：[/color]\n"
		+ "[color=#ebebeb]    Cyan（音效提供）|  飞翔e舞模拟器（曲谱资源提供）[/color]\n"
		+ "[color=#ebebeb]LifeErrOr（美术提供）|  小鱼（美术提供）[/color]\n"
		+ "[color=#ebebeb]“e舞时刻”官方粉丝1群参与讨论的群友（反馈提供）[/color]\n\n"
		+ "[color=#ebebeb]玩家交流QQ群：1084318862[/color]"
	)
	var disclaimer := $Disclaimer as Label
	disclaimer.text = DISCLAIMER_TEXT
	disclaimer.add_theme_font_override("font", font)
	disclaimer.add_theme_font_size_override("font_size", 14)
	disclaimer.add_theme_color_override("font_color", Color(190.0 / 255.0, 190.0 / 255.0, 190.0 / 255.0))
	disclaimer.add_theme_constant_override("outline_size", 0)
	disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _confirm() -> void:
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	SceneRouter.change_to_with_zoom("mode_select", _leave_button)


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_editor_overlay):
		if event.is_action_pressed("ui_cancel"):
			_close_editor()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pedal_confirm") or event.is_action_pressed("ui_accept"):
		_confirm()
