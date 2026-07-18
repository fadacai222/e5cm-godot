extends CanvasLayer
## 原版非游戏场景 ESC / SYSTEM 菜单。
## 适用于投币、登录、个人资料、大模式、子模式和加载页；
## 选歌与谱面播放器继续使用各自的专用 ESC 菜单。

const EXCLUDED_SCENES := ["Boot", "SongSelect", "Gameplay", "Settlement"]
const OPTION_COUNT := 4

var _panel: Panel
var _options: VBoxContainer
var _buttons: Array[Button] = []
var _status: Label
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
	dim.color = Color(0, 0, 0, 178.0 / 255.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.position = Vector2(530, 245)
	_panel.size = Vector2(860, 590)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(8.0 / 255.0, 13.0 / 255.0, 24.0 / 255.0, 0.96)
	panel_style.border_color = Color(76.0 / 255.0, 96.0 / 255.0, 136.0 / 255.0, 0.92)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(16)
	panel_style.shadow_color = Color(0, 0, 0, 0.48)
	panel_style.shadow_size = 18
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var title := Label.new()
	title.name = "Title"
	title.text = "系统菜单"
	title.position = Vector2(24, 8)
	title.size = Vector2(500, 52)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(245.0 / 255.0, 248.0 / 255.0, 1.0))
	_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.text = "ESC / SYSTEM"
	subtitle.position = Vector2(26, 54)
	subtitle.size = Vector2(400, 32)
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(140.0 / 255.0, 172.0 / 255.0, 225.0 / 255.0, 0.75))
	_panel.add_child(subtitle)

	_options = VBoxContainer.new()
	_options.name = "Options"
	_options.position = Vector2(22, 100)
	_options.size = Vector2(816, 346)
	_options.add_theme_constant_override("separation", 14)
	_panel.add_child(_options)
	for i in OPTION_COUNT:
		var button := Button.new()
		button.name = "Option%d" % i
		button.custom_minimum_size = Vector2(816, 58)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 22)
		button.pressed.connect(_activate.bind(i))
		button.mouse_entered.connect(_on_option_hover.bind(i))
		_options.add_child(button)
		_buttons.append(button)

	_status = Label.new()
	_status.name = "Status"
	_status.position = Vector2(26, 462)
	_status.size = Vector2(808, 42)
	_status.add_theme_font_size_override("font_size", 19)
	_status.add_theme_color_override("font_color", Color(1.0, 0.94, 0.55))
	_panel.add_child(_status)

	var help := Label.new()
	help.name = "Help"
	help.text = "投币键可随时投币   ESC关闭\n鼠标点击 / ↑↓选择 / ←→调节 / Enter或中踏板确认"
	help.position = Vector2(26, 512)
	help.size = Vector2(808, 64)
	help.add_theme_font_size_override("font_size", 17)
	help.add_theme_color_override("font_color", Color(132.0 / 255.0, 148.0 / 255.0, 178.0 / 255.0, 0.82))
	_panel.add_child(help)


func _button_style(selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(26.0 / 255.0, 34.0 / 255.0, 54.0 / 255.0) if selected else Color(18.0 / 255.0, 24.0 / 255.0, 40.0 / 255.0)
	style.border_color = Color(120.0 / 255.0, 238.0 / 255.0, 1.0) if selected else Color(76.0 / 255.0, 96.0 / 255.0, 136.0 / 255.0)
	style.set_border_width_all(2 if selected else 1)
	style.set_corner_radius_all(14)
	style.content_margin_left = 18
	return style


func _coin_key_name() -> String:
	var keys: Array = SettingsStore.key_bindings.get("coin", [KEY_F])
	return SettingsStore.binding_display_name(keys[0]) if not keys.is_empty() else "F"


func _refresh() -> void:
	var labels := [
		"01    设置投币快捷键（当前：%s）" % _coin_key_name(),
		"02    %s背景音乐" % ("开启" if _bgm_disabled else "关闭"),
		"03    音量-音乐与音效（当前：%d%%  ←/→调节）" % SettingsStore.bgm_volume,
		"04    退出到桌面",
	]
	for i in _buttons.size():
		var button := _buttons[i]
		button.text = labels[i]
		button.add_theme_stylebox_override("normal", _button_style(i == _selected))
		button.add_theme_stylebox_override("hover", _button_style(true))
		button.add_theme_stylebox_override("pressed", _button_style(true))
		button.add_theme_color_override("font_color",
			Color(1.0, 245.0 / 255.0, 164.0 / 255.0) if i == _selected else Color(226.0 / 255.0, 233.0 / 255.0, 246.0 / 255.0))
	if _rebinding_coin:
		_status.text = "等待按键输入：按任意键设为投币键（ESC取消）"


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
			_status.text = "等待按键输入：按任意键设为投币键（ESC取消）"
		1:
			_toggle_bgm()
		2:
			SettingsStore.bgm_volume = 0 if SettingsStore.bgm_volume >= 100 else SettingsStore.bgm_volume + 10
			AudioDirector.refresh_volume()
			_status.text = "音量（音乐与音效）：%d%%" % SettingsStore.bgm_volume
		3:
			SettingsStore.save_settings()
			get_tree().quit()
	_play_button_sound()
	_refresh()


func _adjust_selected(direction: int) -> void:
	if _selected != 2:
		return
	SettingsStore.bgm_volume = clampi(SettingsStore.bgm_volume + direction * 10, 0, 100)
	AudioDirector.refresh_volume()
	SettingsStore.save_settings()
	_status.text = "音量（音乐与音效）：%d%%" % SettingsStore.bgm_volume
	_play_button_sound()
	_refresh()


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
