extends CanvasLayer
## 非游戏场景共用 ESC / SYSTEM 菜单。
## 适用于投币、登录、个人资料、大模式、子模式和加载页；
## 选歌与谱面播放器继续使用 EscMenu，但三者共用同一套原版街机 HUD 视觉语言。

const EXCLUDED_SCENES := ["Boot", "SongSelect", "Gameplay", "Settlement"]
const OPTION_COUNT := 6
const OPTION_DEFS := [
	["投币快捷键", "COIN KEY", "修改全局投币按键。长按投币键时会持续投币。"],
	["背景音乐", "BACKGROUND MUSIC", "临时关闭或恢复当前场景的背景音乐。"],
	["音量", "AUDIO LEVEL", "统一调整背景音乐与界面音效音量。"],
	["显示模式", "WINDOW MODE", "在窗口模式与 Windows 独占全屏之间切换。"],
	["分辨率", "RESOLUTION", "切换输出分辨率；窗口过大时会自动等比缩小并居中。"],
	["退出到桌面", "EXIT TO DESKTOP", "保存当前设置并关闭 E5CM。"],
]

var _panel: Control
var _nav_panel: Panel
var _content_panel: Panel
var _options: VBoxContainer
var _buttons: Array[Button] = []
var _status: Label
var _detail_index: Label
var _detail_title: Label
var _detail_subtitle: Label
var _detail_description: Label
var _detail_value: Label
var _detail_hint: Label
var _selected := 0
var _rebinding_coin := false
var _bgm_disabled := false
var _resume_bgm_path := ""


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _scene_allows_menu() -> bool:
	var scene := get_tree().current_scene
	return scene != null and not EXCLUDED_SCENES.has(scene.name)


func open_menu() -> void:
	if not _scene_allows_menu():
		return
	_selected = 0
	_rebinding_coin = false
	_status.text = ""
	visible = true
	_refresh()
	UiKit.animate_arcade_in(_nav_panel, Vector2(-18, 0), 0.17)
	UiKit.animate_arcade_in(_content_panel, Vector2(18, 0), 0.19)


func close_menu() -> void:
	_rebinding_coin = false
	visible = false
	SettingsStore.save_settings()


func is_open() -> bool:
	return visible


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _rebinding_coin:
				_rebinding_coin = false
				_status.text = "已取消修改投币快捷键"
				_refresh()
			elif visible:
				close_menu()
			elif _scene_allows_menu():
				open_menu()
			else:
				return
			get_viewport().set_input_as_handled()
			return
	if not visible:
		return

	if _rebinding_coin:
		if event is InputEventKey and event.pressed and not event.echo:
			var code := int(event.keycode if event.keycode != 0 else event.physical_keycode)
			if code > 0:
				SettingsStore.rebind("coin", [code])
				_rebinding_coin = false
				_status.text = "投币快捷键已改为：%s" % OS.get_keycode_string(code)
				_play_button_sound()
				_refresh()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_up") or event.is_action_pressed("pedal_left"):
		_selected = (_selected - 1 + OPTION_COUNT) % OPTION_COUNT
		_play_button_sound()
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("pedal_right"):
		_selected = (_selected + 1) % OPTION_COUNT
		_play_button_sound()
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_adjust_selected(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_adjust_selected(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("pedal_confirm"):
		_activate(_selected)
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.position = Vector2.ZERO
	dim.size = Vector2(1920, 1080)
	dim.color = Color(1.0 / 255.0, 5.0 / 255.0, 18.0 / 255.0, 0.94)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	# 复用选歌 ESC 的原版设置页结构纹理，避免公共菜单像另一套产品。
	var settings_texture := TextureRect.new()
	settings_texture.name = "OriginalSettingsTexture"
	settings_texture.position = Vector2(250, 148)
	settings_texture.size = Vector2(1520, 768)
	settings_texture.texture = AssetLoader.tex("UI-img/选歌界面资源/设置/设置背景图.png")
	settings_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	settings_texture.stretch_mode = TextureRect.STRETCH_SCALE
	settings_texture.modulate = Color(0.72, 0.90, 1.0, 0.20)
	settings_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(settings_texture)

	# 与选歌 ESC 相同的青蓝 / 洋红舞台光，不使用旧版圆角桌面弹窗。
	for spec in [
		["MenuGlowCyan", Vector2(-180, 128), Vector2(980, 116), -11.0, Color(0.0, 0.86, 1.0, 0.12)],
		["MenuGlowBlue", Vector2(220, 920), Vector2(1120, 70), -5.0, Color(0.10, 0.30, 1.0, 0.07)],
		["MenuGlowPink", Vector2(1210, 760), Vector2(920, 124), -12.0, Color(1.0, 0.03, 0.55, 0.12)],
	]:
		var glow := ColorRect.new()
		glow.name = str(spec[0])
		glow.position = spec[1]
		glow.size = spec[2]
		glow.rotation_degrees = float(spec[3])
		glow.color = spec[4]
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(glow)

	_panel = Control.new()
	_panel.name = "Panel"
	_panel.position = Vector2.ZERO
	_panel.size = Vector2(1920, 1080)
	# 根容器不吞掉边缘点击；左右实体面板和按钮仍各自接管输入。
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_nav_panel = Panel.new()
	_nav_panel.name = "NavPanel"
	_nav_panel.position = Vector2(32, 32)
	_nav_panel.size = Vector2(360, 1016)
	_nav_panel.add_theme_stylebox_override("panel", E5OriginalTheme.panel_style(
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	_panel.add_child(_nav_panel)
	var nav_frame := UiKit.hud_frame(_nav_panel, Rect2(Vector2.ZERO, _nav_panel.size),
		"NavHudFrame", E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA,
		124.0, true, 20.0)
	nav_frame.fill_color = Color(0.008, 0.044, 0.105, 0.89)
	nav_frame.header_color = Color(0.025, 0.18, 0.30, 0.72)

	_content_panel = Panel.new()
	_content_panel.name = "ContentPanel"
	_content_panel.position = Vector2(415, 32)
	_content_panel.size = Vector2(1473, 1016)
	_content_panel.add_theme_stylebox_override("panel", E5OriginalTheme.panel_style(
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	_panel.add_child(_content_panel)
	var content_frame := UiKit.hud_frame(_content_panel,
		Rect2(Vector2.ZERO, _content_panel.size), "ContentHudFrame",
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 104.0, true, 22.0)
	content_frame.fill_color = Color(0.006, 0.035, 0.090, 0.87)
	content_frame.header_color = Color(0.022, 0.14, 0.26, 0.68)
	content_frame.scanline_color = Color(0.20, 0.66, 1.0, 0.032)

	var title := _make_label(_panel, "系统菜单", 42, Vector2(60, 56))
	title.name = "Title"
	title.size = Vector2(304, 56)
	title.add_theme_color_override("font_color", Color(0.36, 0.83, 1.0))
	var subtitle := _make_label(_panel, "ESC MENU / SYSTEM", 15, Vector2(62, 110))
	subtitle.name = "Subtitle"
	subtitle.size = Vector2(300, 28)
	subtitle.add_theme_color_override("font_color", Color(0.48, 0.70, 0.84))
	var nav_accent := ColorRect.new()
	nav_accent.name = "NavAccent"
	nav_accent.position = Vector2(56, 148)
	nav_accent.size = Vector2(312, 3)
	nav_accent.color = Color(1.0, 0.08, 0.70, 0.92)
	nav_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(nav_accent)

	_options = VBoxContainer.new()
	_options.name = "Options"
	_options.position = Vector2(56, 164)
	_options.size = Vector2(312, 640)
	_options.add_theme_constant_override("separation", 12)
	_panel.add_child(_options)
	for i in OPTION_COUNT:
		var button := Button.new()
		button.name = "Option%d" % i
		button.custom_minimum_size = Vector2(312, 88)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_activate.bind(i))
		button.mouse_entered.connect(_on_option_hover.bind(i))
		_options.add_child(button)
		_buttons.append(button)

	var content_title := _make_label(_content_panel, "系统设置  /  SYSTEM", 34, Vector2(42, 34))
	content_title.name = "ContentTitle"
	content_title.size = Vector2(1000, 52)
	content_title.add_theme_color_override("font_color", Color(0.86, 0.98, 1.0))
	var live_chip := _make_label(_content_panel, "●  LIVE CONFIG", 16, Vector2(1192, 42))
	live_chip.name = "LiveConfig"
	live_chip.size = Vector2(200, 34)
	live_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	live_chip.add_theme_color_override("font_color", Color(1.0, 0.30, 0.78))
	var rule := ColorRect.new()
	rule.name = "HeaderRule"
	rule.position = Vector2(42, 94)
	rule.size = Vector2(1389, 2)
	rule.color = Color(0.15, 0.49, 0.72, 0.55)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_panel.add_child(rule)

	var detail := Panel.new()
	detail.name = "DetailCard"
	detail.position = Vector2(42, 132)
	detail.size = Vector2(1389, 648)
	detail.add_theme_stylebox_override("panel", E5OriginalTheme.panel_style(
		Color(0.010, 0.048, 0.105, 0.86), Color(0.12, 0.48, 0.68, 0.72), 1, 0.04))
	_content_panel.add_child(detail)
	var detail_frame := UiKit.hud_frame(detail, Rect2(Vector2.ZERO, detail.size),
		"DetailHudFrame", Color(E5OriginalTheme.CYAN.r, E5OriginalTheme.CYAN.g,
		E5OriginalTheme.CYAN.b, 0.70), E5OriginalTheme.MAGENTA, 0.0, true, 12.0)
	detail_frame.fill_color = Color(0.005, 0.025, 0.070, 0.28)
	detail_frame.scanline_color = Color(0.20, 0.66, 1.0, 0.024)
	detail_frame.show_side_ticks = false

	_detail_index = _make_label(detail, "01", 80, Vector2(54, 48))
	_detail_index.name = "DetailIndex"
	_detail_index.size = Vector2(180, 100)
	_detail_index.add_theme_color_override("font_color", Color(0.16, 0.91, 1.0, 0.24))
	_detail_title = _make_label(detail, "", 42, Vector2(210, 60))
	_detail_title.name = "DetailTitle"
	_detail_title.size = Vector2(920, 58)
	_detail_title.add_theme_color_override("font_color", E5OriginalTheme.TEXT)
	_detail_subtitle = _make_label(detail, "", 17, Vector2(214, 118))
	_detail_subtitle.name = "DetailSubtitle"
	_detail_subtitle.size = Vector2(900, 30)
	_detail_subtitle.add_theme_color_override("font_color", E5OriginalTheme.CYAN_SOFT)

	var detail_rule := ColorRect.new()
	detail_rule.name = "DetailRule"
	detail_rule.position = Vector2(54, 176)
	detail_rule.size = Vector2(1278, 2)
	detail_rule.color = Color(E5OriginalTheme.CYAN.r, E5OriginalTheme.CYAN.g,
		E5OriginalTheme.CYAN.b, 0.36)
	detail_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.add_child(detail_rule)

	_detail_description = _make_label(detail, "", 24, Vector2(72, 220))
	_detail_description.name = "DetailDescription"
	_detail_description.size = Vector2(1220, 78)
	_detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_description.add_theme_color_override("font_color", Color(0.67, 0.77, 0.86))

	var value_panel := Panel.new()
	value_panel.name = "CurrentValuePanel"
	value_panel.position = Vector2(72, 336)
	value_panel.size = Vector2(1244, 130)
	value_panel.add_theme_stylebox_override("panel", E5OriginalTheme.panel_style(
		Color(0.018, 0.080, 0.135, 0.86), Color(E5OriginalTheme.CYAN.r,
		E5OriginalTheme.CYAN.g, E5OriginalTheme.CYAN.b, 0.54), 2))
	detail.add_child(value_panel)
	var value_caption := _make_label(value_panel, "CURRENT VALUE", 15, Vector2(28, 18))
	value_caption.size = Vector2(260, 26)
	value_caption.add_theme_color_override("font_color", E5OriginalTheme.MUTED)
	_detail_value = _make_label(value_panel, "", 34, Vector2(28, 52))
	_detail_value.name = "DetailValue"
	_detail_value.size = Vector2(1180, 56)
	_detail_value.add_theme_color_override("font_color", E5OriginalTheme.GOLD)

	_detail_hint = _make_label(detail, "", 18, Vector2(72, 510))
	_detail_hint.name = "DetailHint"
	_detail_hint.size = Vector2(1244, 44)
	_detail_hint.add_theme_color_override("font_color", E5OriginalTheme.CYAN_SOFT)

	_status = _make_label(_content_panel, "", 19, Vector2(66, 812))
	_status.name = "Status"
	_status.size = Vector2(1340, 42)
	_status.add_theme_color_override("font_color", E5OriginalTheme.GOLD)

	var help := _make_label(_content_panel,
		"投币键可随时投币   ESC 关闭\n鼠标点击 / ↑↓ 选择 / ←→ 调节 / Enter 或中踏板确认",
		17, Vector2(66, 878))
	help.name = "Help"
	help.size = Vector2(1340, 72)
	help.add_theme_color_override("font_color", Color(0.53, 0.66, 0.78, 0.86))


func _make_label(parent: Node, text_value: String, font_size: int,
		position_value: Vector2) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", E5OriginalTheme.TEXT)
	label.add_theme_constant_override("outline_size", 0)
	parent.add_child(label)
	return label


func _coin_key_name() -> String:
	var keys: Array = SettingsStore.key_bindings.get("coin", [KEY_F])
	return SettingsStore.binding_display_name(keys[0]) if not keys.is_empty() else "F"


func _current_value(index: int) -> String:
	match index:
		0:
			return "当前按键：%s" % _coin_key_name()
		1:
			return "背景音乐：%s" % ("已关闭" if _bgm_disabled else "已开启")
		2:
			return "音乐与音效：%d%%" % SettingsStore.bgm_volume
		3:
			return "当前模式：%s" % SettingsStore.display_mode
		4:
			return "输出分辨率：%s" % SettingsStore.resolution_display_name()
		5:
			return "保存设置并退出 E5CM"
	return ""


func _interaction_hint(index: int) -> String:
	match index:
		0:
			return "按 Enter / 中踏板后，再按任意键完成绑定；ESC 可取消。"
		1:
			return "按 Enter / 中踏板切换背景音乐。"
		2:
			return "按 ← / → 每次调整 10%；按 Enter / 中踏板也可递增。"
		3:
			return "按 ← / → 或 Enter / 中踏板切换窗口与独占全屏。"
		4:
			return "按 ← / → 选择分辨率；Enter / 中踏板切换到下一档。"
		5:
			return "危险操作：按 Enter / 中踏板立即退出到桌面。"
	return ""


func _refresh() -> void:
	for i in _buttons.size():
		var button := _buttons[i]
		var selected := i == _selected
		var danger := i == 5
		button.text = "%02d   %s\n       %s" % [i + 1, OPTION_DEFS[i][0], OPTION_DEFS[i][1]]
		button.modulate = Color.WHITE if selected else Color(0.82, 0.88, 0.96, 0.86)
		UiKit.skin_arcade_button(button, selected, danger, 20,
			E5OriginalTheme.DANGER if danger else E5OriginalTheme.CYAN)

	_detail_index.text = "%02d" % [_selected + 1]
	_detail_title.text = str(OPTION_DEFS[_selected][0])
	_detail_subtitle.text = str(OPTION_DEFS[_selected][1])
	_detail_description.text = str(OPTION_DEFS[_selected][2])
	_detail_value.text = _current_value(_selected)
	_detail_value.add_theme_color_override("font_color",
		E5OriginalTheme.DANGER if _selected == 5 else E5OriginalTheme.GOLD)
	_detail_hint.text = _interaction_hint(_selected)
	_detail_hint.add_theme_color_override("font_color",
		E5OriginalTheme.DANGER if _selected == 5 else E5OriginalTheme.CYAN_SOFT)
	if _rebinding_coin:
		_status.text = "等待按键输入：按任意键设为投币键（ESC 取消）"


func _on_option_hover(index: int) -> void:
	_selected = index
	_refresh()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close_menu()


func _activate(index: int) -> void:
	_selected = clampi(index, 0, OPTION_COUNT - 1)
	match _selected:
		0:
			_rebinding_coin = true
			_status.text = "等待按键输入：按任意键设为投币键（ESC 取消）"
		1:
			_toggle_bgm()
		2:
			SettingsStore.bgm_volume = 0 if SettingsStore.bgm_volume >= 100 else SettingsStore.bgm_volume + 10
			AudioDirector.refresh_volume()
			_status.text = "音量（音乐与音效）：%d%%" % SettingsStore.bgm_volume
		3:
			_toggle_display_mode()
		4:
			_step_resolution(1)
		5:
			SettingsStore.save_settings()
			get_tree().quit()
	_play_button_sound()
	_refresh()


func _adjust_selected(direction: int) -> void:
	match _selected:
		2:
			SettingsStore.bgm_volume = clampi(SettingsStore.bgm_volume + direction * 10, 0, 100)
			AudioDirector.refresh_volume()
			SettingsStore.save_settings()
			_status.text = "音量（音乐与音效）：%d%%" % SettingsStore.bgm_volume
		3:
			_toggle_display_mode()
		4:
			_step_resolution(direction)
		_:
			return
	_play_button_sound()
	_refresh()


func _toggle_display_mode() -> void:
	SettingsStore.display_mode = "窗口" if SettingsStore.display_mode == "独占全屏" else "独占全屏"
	SettingsStore.apply_display_mode()
	SettingsStore.save_settings()
	_status.text = "显示模式已切换为：%s" % SettingsStore.display_mode


func _step_resolution(direction: int) -> void:
	SettingsStore.step_resolution(direction)
	SettingsStore.save_settings()
	_status.text = "已选择 %s；重启游戏后生效" % SettingsStore.resolution_display_name()


func _toggle_bgm() -> void:
	if not _bgm_disabled:
		_resume_bgm_path = str(AudioDirector.get("_current_bgm_path"))
		AudioDirector.stop_bgm()
		_bgm_disabled = true
		_status.text = "背景音乐已关闭"
	else:
		_bgm_disabled = false
		if not _resume_bgm_path.is_empty():
			AudioDirector.play_bgm(_resume_bgm_path, true)
		_status.text = "背景音乐已开启"
	SettingsStore.save_settings()


func _play_button_sound() -> void:
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
