class_name EscMenu
extends CanvasLayer
## ESC 设置菜单（游戏内 + 选歌共用）—— 对应旧版 game_esc_menu / select_scene_esc_menu_host
## 原版素材：选歌界面资源/设置/设置背景图.png + 左右箭头。
## 游戏内模式含 继续/重新开始/退出本局；设置改动实时写 SettingsStore。

signal resumed
signal restart_requested
signal quit_requested
signal setting_changed(key: String)

var in_gameplay := false
var couple_mode := false

var _row_defs: Array = []      # [label, getter_name, stepper_name]
var _selected := 0
var _panel: Control
var _row_nodes: Array = []
var _arrow_skins: Array = []
var _content_body: Control
var _tab_buttons: Array[Button] = []
var _active_tab := 0
var _binding_actions: Array[String] = []
var _binding_buttons: Array[Button] = []
var _binding_selected := 0
var _rebinding_action := ""
var _binding_status: Label
var _preview_panel: Panel
var _profile_avatar: TextureRect
var _profile_name_input: LineEdit
var _profile_file_dialog: FileDialog
var _profile_feedback: Label
var _profile_refresh_queued := false

const FPS_OPTIONS := [60, 120, 144, 165, 240]
const BASE_TAB_DEFS := [
	["谱面设置", "CHART"], ["背景设置", "BACKGROUND"],
	["游戏 / 分辨率设置", "GAME / DISPLAY"], ["键位设置", "BINDINGS"],
	["用户信息", "PROFILE"],
]
const GAME_ACTION_TAB_DEFS := [
	["继续游戏", "RESUME"],
	["重新载入歌曲", "RELOAD SONG"],
	["退出本局", "RETURN TO SELECT"],
	["退出到桌面", "EXIT TO DESKTOP"],
]
const SYSTEM_ACTION_TAB_DEFS := [
	["退出游戏", "EXIT TO DESKTOP"],
]
const ROWS_BY_TAB := [
	[["调速", "_get_speed", "_step_speed", "调整谱面滚动速度"],
	 ["变速效果", "_get_bpm_fx", "_step_bpm_fx", "谱面 BPM 变化时同步改变滚动速度"],
	 ["谱面偏移", "_get_offset", "_step_offset", "按 10ms 调整视觉偏移，不影响判定"],
	 ["隐藏", "_get_hidden", "_step_hidden", "切换隐藏方式"],
	 ["轨迹", "_get_track", "_step_track", "切换轨迹动画"],
	 ["方向", "_get_direction", "_step_direction", "切换谱面方向"],
	 ["大小", "_get_arrow_size", "_step_arrow_size", "调整箭头尺寸"],
	 ["箭头", "_get_skin", "_step_skin", "切换箭头皮肤并同步预览"]],
	[["背景", "_get_background_mode", "_step_background_mode", "切换图片 / 视频 / 动态背景"],
	 ["每个关卡自动换下一张背景图", "_get_slideshow", "_step_slideshow", "仅图片背景生效"],
	 ["动态背景", "_get_dynamic_background", "_step_dynamic_background", "切换动态背景样式"],
	 ["背景亮度切换", "_get_brightness", "_step_brightness", "图片、视频和动态背景均可调节"]],
	[["显示模式", "_get_display_mode", "_step_display_mode", "切换窗口 / Windows 独占全屏"],
	 ["FPS 上限", "_get_fps", "_step_fps", "限制渲染帧率，降低菜单和选歌场景功耗"],
	 ["垂直同步", "_get_vsync", "_step_vsync", "减少画面撕裂"],
	 ["音量", "_get_volume", "_step_volume", "调整背景音乐音量"],
	 ["静音", "_get_muted", "_step_muted", "关闭所有游戏音频"],
	 ["状态HUD", "_get_status_hud", "_step_status_hud", "显示右下角 FPS / 渲染后端 / 分辨率"],
	 ["极简性能模式", "_get_performance", "_step_performance", "关闭重型效果，优先保证帧率"],
	 ["击中音效", "_get_hit_sound", "_step_hit_sound", "开关击中判定音效"],
	 ["自动播放", "_get_autoplay", "_step_autoplay", "切换自动判定 / 演示模式"]],
	[], [], [], [], [],
]


func _init(p_in_gameplay := false) -> void:
	in_gameplay = p_in_gameplay
	layer = 80


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scan_skins()
	_build_ui()
	if not ProfileStore.progress_changed.is_connected(_on_profile_progress_changed):
		ProfileStore.progress_changed.connect(_on_profile_progress_changed)
	visible = false


# ---------------- 行取值/步进 ----------------

func _get_speed() -> String: return "X%.2f" % SettingsStore.scroll_speed
func _step_speed(dir: int) -> void:
	SettingsStore.scroll_speed = clampf(SettingsStore.scroll_speed + 0.25 * dir, 1.0, 7.0)
	setting_changed.emit("scroll_speed")


func _get_offset() -> String: return "%+d ms" % SettingsStore.chart_offset_ms
func _step_offset(dir: int) -> void:
	SettingsStore.chart_offset_ms = clampi(SettingsStore.chart_offset_ms + 10 * dir, -500, 500)
	setting_changed.emit("chart_offset")


func _get_bpm_fx() -> String: return "开" if SettingsStore.bpm_scroll_effect else "关"
func _step_bpm_fx(_dir: int) -> void:
	SettingsStore.bpm_scroll_effect = not SettingsStore.bpm_scroll_effect


func _get_hit_sound() -> String: return "开" if SettingsStore.hit_sound else "关"
func _step_hit_sound(_dir: int) -> void:
	SettingsStore.hit_sound = not SettingsStore.hit_sound
	setting_changed.emit("hit_sound")


func _get_autoplay() -> String: return "开" if SettingsStore.autoplay else "关"
func _step_autoplay(_dir: int) -> void:
	SettingsStore.autoplay = not SettingsStore.autoplay
	setting_changed.emit("autoplay")


func _get_volume() -> String: return str(SettingsStore.bgm_volume)
func _step_volume(dir: int) -> void:
	SettingsStore.bgm_volume = clampi(SettingsStore.bgm_volume + 5 * dir, 0, 100)
	AudioDirector.refresh_volume()


func _get_muted() -> String: return "开" if SettingsStore.muted else "关"
func _step_muted(_dir: int) -> void:
	SettingsStore.muted = not SettingsStore.muted
	AudioDirector.refresh_volume()


func _get_skin() -> String:
	return "情侣专用（锁定）" if couple_mode else SettingsStore.arrow_skin
func _step_skin(dir: int) -> void:
	if couple_mode or _arrow_skins.is_empty():
		return
	var idx := _arrow_skins.find(SettingsStore.arrow_skin)
	idx = (idx + dir + _arrow_skins.size()) % _arrow_skins.size()
	SettingsStore.arrow_skin = _arrow_skins[idx]
	setting_changed.emit("arrow_skin")


func _get_brightness() -> String:
	return "%d%%" % [100 - SettingsStore.background_brightness_level * 20]
func _step_brightness(dir: int) -> void:
	SettingsStore.background_brightness_level = clampi(
		SettingsStore.background_brightness_level - dir, 0, 4)
	setting_changed.emit("brightness")


func _get_fps() -> String:
	return str(SettingsStore.max_fps)
func _step_fps(dir: int) -> void:
	var idx := FPS_OPTIONS.find(SettingsStore.max_fps)
	idx = (idx + dir + FPS_OPTIONS.size()) % FPS_OPTIONS.size()
	SettingsStore.max_fps = FPS_OPTIONS[idx]
	SettingsStore.apply_performance()


func _get_vsync() -> String: return "开" if SettingsStore.vsync else "关"
func _step_vsync(_dir: int) -> void:
	SettingsStore.vsync = not SettingsStore.vsync
	SettingsStore.apply_performance()


func _cycle_text(current: String, values: Array, dir: int) -> String:
	var idx := values.find(current)
	if idx < 0:
		idx = 0
	return str(values[(idx + dir + values.size()) % values.size()])


func _get_hidden() -> String: return SettingsStore.hidden_mode
func _step_hidden(dir: int) -> void:
	SettingsStore.hidden_mode = _cycle_text(SettingsStore.hidden_mode, ["关闭", "半隐", "全隐"], dir)
	setting_changed.emit("hidden_mode")


func _get_track() -> String: return SettingsStore.track_mode
func _step_track(dir: int) -> void:
	SettingsStore.track_mode = _cycle_text(SettingsStore.track_mode, ["正常", "摇摆", "旋转"], dir)
	setting_changed.emit("track_mode")


func _get_direction() -> String: return SettingsStore.direction_mode
func _step_direction(dir: int) -> void:
	SettingsStore.direction_mode = _cycle_text(SettingsStore.direction_mode, ["关闭", "反向"], dir)
	setting_changed.emit("direction_mode")


func _get_arrow_size() -> String: return "%d%%" % SettingsStore.arrow_size_percent
func _step_arrow_size(dir: int) -> void:
	SettingsStore.arrow_size_percent = clampi(SettingsStore.arrow_size_percent + dir * 10, 50, 150)
	setting_changed.emit("arrow_size")


func _get_background_mode() -> String: return SettingsStore.background_mode
func _step_background_mode(dir: int) -> void:
	SettingsStore.background_mode = _cycle_text(SettingsStore.background_mode, ["图片", "视频", "动态背景"], dir)
	setting_changed.emit("background_mode")


func _get_slideshow() -> String: return "开启" if SettingsStore.image_slideshow else "关闭"
func _step_slideshow(_dir: int) -> void:
	SettingsStore.image_slideshow = not SettingsStore.image_slideshow


func _get_dynamic_background() -> String: return SettingsStore.dynamic_background_mode
func _step_dynamic_background(_dir: int) -> void:
	SettingsStore.dynamic_background_mode = "唱片"
	setting_changed.emit("dynamic_background")


func _get_display_mode() -> String:
	return SettingsStore.display_mode
func _step_display_mode(_dir: int) -> void:
	SettingsStore.display_mode = "窗口" if SettingsStore.display_mode == "独占全屏" else "独占全屏"
	SettingsStore.apply_display_mode()
	setting_changed.emit("display_mode")


func _get_resolution() -> String: return "1920×1080"
func _step_resolution(_dir: int) -> void: pass
func _get_renderer() -> String: return RenderingServer.get_current_rendering_driver_name().to_upper()
func _step_renderer(_dir: int) -> void: pass
func _get_status_hud() -> String: return "开启" if SettingsStore.status_hud_enabled else "关闭"
func _step_status_hud(_dir: int) -> void:
	SettingsStore.status_hud_enabled = not SettingsStore.status_hud_enabled
	if StatusHud != null:
		StatusHud.visible = SettingsStore.status_hud_enabled
	setting_changed.emit("status_hud")
func _get_performance() -> String: return "开启" if SettingsStore.performance_mode else "关闭"
func _step_performance(_dir: int) -> void:
	SettingsStore.performance_mode = not SettingsStore.performance_mode
	setting_changed.emit("performance_mode")


func _tab_defs() -> Array:
	var result := BASE_TAB_DEFS.duplicate(true)
	result.append_array(GAME_ACTION_TAB_DEFS if in_gameplay else SYSTEM_ACTION_TAB_DEFS)
	return result


# ---------------- 菜单开关 ----------------

func open_menu() -> void:
	visible = true
	if _active_tab == 4:
		_set_tab(4)
	else:
		_refresh_all()
	var nav := _panel.get_node_or_null("NavPanel") as Control if _panel != null else null
	var content := _panel.get_node_or_null("ContentPanel") as Control if _panel != null else null
	if nav != null:
		UiKit.animate_arcade_in(nav, Vector2(-18, 0), 0.17)
	if content != null:
		UiKit.animate_arcade_in(content, Vector2(18, 0), 0.19)


func _on_profile_progress_changed(_mode_key: String, _progress: Dictionary,
		_preview: bool) -> void:
	if not visible or _active_tab != 4 or _profile_refresh_queued:
		return
	_profile_refresh_queued = true
	call_deferred("_refresh_profile_tab_from_progress")


func _refresh_profile_tab_from_progress() -> void:
	_profile_refresh_queued = false
	if visible and _active_tab == 4:
		_set_tab(4)


func close_menu() -> void:
	_cancel_rebind()
	visible = false
	SettingsStore.save_settings()
	resumed.emit()


func is_open() -> bool:
	return visible


func _scan_skins() -> void:
	_arrow_skins = []
	var base := AssetLoader.abs_path("UI-img/游戏界面/箭头")
	for entry in AssetLoader.list_directories(base):
		if FileAccess.file_exists(base.path_join(entry).path_join("arrow/skin.json")):
			_arrow_skins.append(entry)


# ---------------- UI ----------------

func _build_ui() -> void:
	# CanvasLayer 下动态 Control 只设 anchors 可能得到 0×0；显式建立 1920×1080 输入边界。
	var input_blocker := ColorRect.new()
	input_blocker.name = "GameplayPauseMenu" if in_gameplay else "SettingsInputBlocker"
	input_blocker.position = Vector2.ZERO
	input_blocker.size = Vector2(1920, 1080)
	input_blocker.color = Color(1.0 / 255.0, 5.0 / 255.0, 18.0 / 255.0, 0.94)
	input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(input_blocker)

	var dim := ColorRect.new()
	dim.name = "PauseDim"
	dim.position = Vector2.ZERO
	dim.size = Vector2(1920, 1080)
	dim.color = Color(0.02, 0.10, 0.22, 0.30)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	# 原版设置页纹理只作为结构底图，功能控件仍由 Godot 动态构建。
	var settings_texture := TextureRect.new()
	settings_texture.name = "OriginalSettingsTexture"
	settings_texture.position = Vector2(250, 148)
	settings_texture.size = Vector2(1520, 768)
	settings_texture.texture = AssetLoader.tex("UI-img/选歌界面资源/设置/%s" % (
		"设置背景图2p.png" if couple_mode else "设置背景图.png"))
	settings_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	settings_texture.stretch_mode = TextureRect.STRETCH_SCALE
	settings_texture.modulate = Color(0.72, 0.90, 1.0, 0.20)
	settings_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(settings_texture)

	# 青蓝/洋红双主色舞台光：设置页和暂停页共用同一视觉语言。
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
	_panel.name = "ModernMenu"
	_panel.position = Vector2.ZERO
	_panel.size = Vector2(1920, 1080)
	_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_panel)
	var nav := Panel.new()
	nav.name = "NavPanel"
	nav.position = Vector2(32, 32)
	nav.size = Vector2(360, 1016)
	nav.add_theme_stylebox_override("panel", E5OriginalTheme.panel_style(
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	_panel.add_child(nav)
	var nav_frame := UiKit.hud_frame(nav, Rect2(Vector2.ZERO, nav.size),
		"NavHudFrame", E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA,
		124.0, true, 20.0)
	nav_frame.fill_color = Color(0.008, 0.044, 0.105, 0.89)
	nav_frame.header_color = Color(0.025, 0.18, 0.30, 0.72)
	var content := Panel.new()
	content.name = "ContentPanel"
	content.position = Vector2(415, 32)
	content.size = Vector2(1473, 1016)
	content.add_theme_stylebox_override("panel", E5OriginalTheme.panel_style(
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	_panel.add_child(content)
	var content_frame := UiKit.hud_frame(content, Rect2(Vector2.ZERO, content.size),
		"ContentHudFrame", E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA,
		104.0, true, 22.0)
	content_frame.fill_color = Color(0.006, 0.035, 0.090, 0.87)
	content_frame.header_color = Color(0.022, 0.14, 0.26, 0.68)
	content_frame.scanline_color = Color(0.20, 0.66, 1.0, 0.032)

	var title := _mk_label(nav, "PAUSED" if in_gameplay else "ESC MENU", 42, Vector2(28, 30))
	title.size = Vector2(304, 56)
	title.add_theme_color_override("font_color", Color(0.20, 0.94, 1.0) if in_gameplay else Color(0.36, 0.83, 1.0))
	var sub := _mk_label(nav, "TRACK CONTROL / ESC" if in_gameplay else "SYSTEM / SETTINGS", 15, Vector2(30, 84))
	sub.size = Vector2(300, 28)
	sub.add_theme_color_override("font_color", Color(0.48, 0.70, 0.84))
	var nav_accent := ColorRect.new()
	nav_accent.position = Vector2(24, 116)
	nav_accent.size = Vector2(312, 3)
	nav_accent.color = Color(1.0, 0.08, 0.70, 0.92)
	nav_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_child(nav_accent)

	_tab_buttons.clear()
	var tabs := _tab_defs()
	for i in tabs.size():
		var tab := Button.new()
		tab.name = "Tab%d" % i
		tab.text = "%02d   %s\n       %s" % [i + 1, tabs[i][0], tabs[i][1]]
		tab.position = Vector2(24, 132 + i * (94 if in_gameplay else 112))
		tab.size = Vector2(312, 72 if in_gameplay else 88)
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.pressed.connect(_set_tab.bind(i))
		var action_tab := i >= 5
		var danger_tab := action_tab and ((not in_gameplay) or i >= 7)
		UiKit.skin_arcade_button(tab, false, danger_tab, 20,
			E5OriginalTheme.MAGENTA if action_tab else E5OriginalTheme.CYAN)
		nav.add_child(tab)
		_tab_buttons.append(tab)

	var content_title := _mk_label(content, "", 34, Vector2(42, 34))
	content_title.name = "ContentTitle"
	content_title.size = Vector2(1000, 52)
	content_title.add_theme_color_override("font_color", Color(0.86, 0.98, 1.0))
	var live_chip := _mk_label(content, "●  LIVE CONFIG", 16, Vector2(1192, 42))
	live_chip.size = Vector2(200, 34)
	live_chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	live_chip.add_theme_color_override("font_color", Color(1.0, 0.30, 0.78))
	var rule := ColorRect.new()
	rule.position = Vector2(42, 94)
	rule.size = Vector2(1389, 2)
	rule.color = Color(0.15, 0.49, 0.72, 0.55)
	content.add_child(rule)
	_content_body = Control.new()
	_content_body.name = "ContentBody"
	_content_body.position = Vector2(42, 120)
	_content_body.size = Vector2(1389, 842)
	content.add_child(_content_body)
	_set_tab(0)


func _panel_style(bg: Color, border: Color) -> StyleBoxFlat:
	return E5OriginalTheme.panel_style(bg, border, 1, 0.06)


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := E5OriginalTheme.panel_style(bg, border, 1, 0.05)
	style.content_margin_left = 16
	style.content_margin_right = 12
	style.set_corner_radius_all(2)
	return style


func _nav_action(parent: Control, text_value: String, pos: Vector2, cb: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = pos
	button.size = Vector2(312, 58)
	UiKit.skin_arcade_button(button, false, false, 21)
	button.pressed.connect(cb)
	parent.add_child(button)
	return button


func _set_tab(index: int) -> void:
	var tabs := _tab_defs()
	_active_tab = clampi(index, 0, tabs.size() - 1)
	for i in _tab_buttons.size():
		var button := _tab_buttons[i]
		var selected_tab := i == _active_tab
		var action_tab := i >= 5
		var danger_tab := action_tab and ((not in_gameplay) or i >= 7)
		button.modulate = Color.WHITE if selected_tab else Color(0.82, 0.88, 0.96, 0.86)
		button.position.x = 32.0 if selected_tab else 24.0
		button.size.x = 304.0 if selected_tab else 312.0
		UiKit.skin_arcade_button(button, selected_tab, danger_tab, 20,
			E5OriginalTheme.MAGENTA if action_tab else E5OriginalTheme.CYAN)
	var title := _panel.get_node("ContentPanel/ContentTitle") as Label
	title.text = "%s  /  %s" % [tabs[_active_tab][0], tabs[_active_tab][1]]
	for child in _content_body.get_children():
		child.free()
	_preview_panel = null
	_row_defs = ROWS_BY_TAB[_active_tab].duplicate(true) if _active_tab < ROWS_BY_TAB.size() else []
	_row_nodes.clear()
	_selected = 0
	_rebinding_action = ""
	if _active_tab == 3:
		_build_bindings()
	elif _active_tab == 4:
		_build_profile_tab()
	elif _active_tab >= 5:
		_build_action_tab(_active_tab)
	else:
		_build_rows()
	_refresh_all()


func _build_rows() -> void:
	var left_arrow := AssetLoader.tex("UI-img/选歌界面资源/设置/左小箭头.png")
	var right_arrow := AssetLoader.tex("UI-img/选歌界面资源/设置/右小箭头.png")
	var list_width := 700.0
	var row_step := 96.0
	for i in _row_defs.size():
		var holder := Panel.new()
		holder.name = "SettingRow%d" % i
		holder.position = Vector2(0, i * row_step)
		holder.size = Vector2(list_width, 80)
		holder.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.065, 0.105, 0.88), Color(0.1, 0.23, 0.34, 0.8)))
		_content_body.add_child(holder)
		var label := _mk_label(holder, str(_row_defs[i][0]), 21, Vector2(24, 10))
		label.size = Vector2(330, 30)
		if _row_defs[i].size() > 3:
			var hint := _mk_label(holder, str(_row_defs[i][3]), 14, Vector2(24, 42))
			hint.size = Vector2(360, 26)
			hint.add_theme_color_override("font_color", Color(0.45, 0.57, 0.68))
			hint.add_theme_constant_override("outline_size", 0)
		_mk_arrow(holder, left_arrow, Vector2(425, 18), i, -1)
		var value := _mk_label(holder, "", 20, Vector2(480, 10))
		value.name = "Value"
		value.size = Vector2(150, 56)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.add_theme_color_override("font_color", Color(0.99, 0.84, 0.31))
		_mk_arrow(holder, right_arrow, Vector2(640, 18), i, 1)
		holder.gui_input.connect(_on_row_input.bind(i))
		_row_nodes.append(holder)
	_build_preview_panel()


func _build_preview_panel() -> void:
	_preview_panel = Panel.new()
	_preview_panel.name = "LivePreview"
	_preview_panel.position = Vector2(735, 0)
	_preview_panel.size = Vector2(654, 842)
	_preview_panel.add_theme_stylebox_override("panel", _panel_style(
		Color(0.018, 0.05, 0.085, 0.94), Color(0.10, 0.23, 0.34, 0.8)))
	_content_body.add_child(_preview_panel)
	_populate_preview_panel()


func _refresh_preview_panel() -> void:
	if _preview_panel == null or not is_instance_valid(_preview_panel):
		return
	for child in _preview_panel.get_children():
		child.free()
	_populate_preview_panel()


func _populate_preview_panel() -> void:
	if _preview_panel == null:
		return
	var title_text := "谱面实时预览" if _active_tab == 0 else (
		"背景实时预览" if _active_tab == 1 else "显示状态预览")
	var title := _mk_label(_preview_panel, title_text, 23, Vector2(28, 24))
	title.size = Vector2(590, 40)
	var hint := _mk_label(_preview_panel,
		"设置会立即应用到右侧画布；游戏暂停时视频和动态层保持冻结。", 15, Vector2(28, 66))
	hint.size = Vector2(590, 32)
	hint.add_theme_color_override("font_color", Color(0.48, 0.60, 0.70))
	hint.add_theme_constant_override("outline_size", 0)
	if _active_tab == 0:
		_build_chart_preview(_preview_panel)
	elif _active_tab == 1:
		_build_background_preview(_preview_panel)
	else:
		_build_display_preview(_preview_panel)


func _preview_arrow_suffixes() -> Array[String]:
	# 原版“反向”改变卷轴方向，不改变五个箭头的贴图/键位顺序。
	return ["lb", "lt", "cc", "rt", "rb"]


func _build_chart_preview(parent: Control) -> void:
	var arrow_atlas := AssetLoader.couple_arrow_atlas() if couple_mode else \
		AssetLoader.arrow_atlas(SettingsStore.arrow_skin)
	var suffixes := _preview_arrow_suffixes()
	var start_x := 34.0
	var lane_w := 112.0
	var arrow_size := 96.0 * float(SettingsStore.arrow_size_percent) / 100.0
	for i in suffixes.size():
		var lane := Panel.new()
		lane.name = "PreviewLane%d" % i
		lane.position = Vector2(start_x + i * (lane_w + 10.0), 132)
		lane.size = Vector2(lane_w, 620)
		lane.add_theme_stylebox_override("panel", _panel_style(
			Color(0.015, 0.045, 0.075, 0.92), Color(0.08, 0.16, 0.24, 0.85)))
		parent.add_child(lane)
		var arrow := TextureRect.new()
		arrow.name = "PreviewArrow%d" % i
		arrow.texture = arrow_atlas.get("arrow_body_%s" % suffixes[i])
		arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arrow.position = Vector2((lane_w - arrow_size) * 0.5, 286.0 - arrow_size * 0.5)
		arrow.size = Vector2(arrow_size, arrow_size)
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lane.add_child(arrow)
	var footer := _mk_label(parent, "皮肤：%s    大小：%d%%    方向：%s" % [
		_get_skin(), SettingsStore.arrow_size_percent, SettingsStore.direction_mode],
		18, Vector2(34, 778))
	footer.name = "PreviewFooter"
	footer.size = Vector2(580, 36)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", Color(0.99, 0.84, 0.31))


func _first_preview_resource(rel_dir: String, extensions: Array[String]) -> String:
	var names := AssetLoader.list_resources(rel_dir, extensions)
	return "" if names.is_empty() else AssetLoader.abs_path(rel_dir.path_join(names[0]))


func _preview_video_stream(path: String) -> VideoStream:
	if path.is_empty():
		return null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as VideoStream
	if ClassDB.class_exists("FFmpegVideoStream"):
		var stream_object = ClassDB.instantiate("FFmpegVideoStream")
		if stream_object != null:
			stream_object.set("file", ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
			return stream_object as VideoStream
	return null


func _preview_texture(parent: Control, node_name: String, texture: Texture2D,
		rect: Rect2, stretch := TextureRect.STRETCH_KEEP_ASPECT_COVERED) -> TextureRect:
	var view := TextureRect.new()
	view.name = node_name
	view.texture = texture
	view.position = rect.position
	view.size = rect.size
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = stretch
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(view)
	return view


func _build_dynamic_background_preview(canvas: Control) -> void:
	var dynamic := Control.new()
	dynamic.name = "PreviewDynamicBackground"
	dynamic.position = Vector2.ZERO
	dynamic.size = canvas.size
	dynamic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(dynamic)
	_preview_texture(dynamic, "VinylBackground",
		AssetLoader.tex("UI-img/动态背景/唱片/素材/背景.png"), Rect2(Vector2.ZERO, dynamic.size))
	_preview_texture(dynamic, "Record",
		AssetLoader.tex("UI-img/动态背景/唱片/素材/唱片.png"),
		Rect2(Vector2(178, 80), Vector2(230, 230)), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_preview_texture(dynamic, "FootDecoration",
		AssetLoader.tex("UI-img/动态背景/唱片/素材/foot.png"),
		Rect2(Vector2(0, 448), Vector2(586, 72)), TextureRect.STRETCH_SCALE)
	if in_gameplay:
		var paused_label := _mk_label(dynamic, "PAUSED", 18, Vector2(458, 18))
		paused_label.name = "PausedState"
		paused_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.28))


func _build_background_preview(parent: Control) -> void:
	var canvas := ColorRect.new()
	canvas.name = "PreviewCanvas"
	canvas.position = Vector2(34, 130)
	canvas.size = Vector2(586, 520)
	canvas.color = Color(0, 0, 0, 0.92)
	canvas.clip_contents = true
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(canvas)
	match SettingsStore.background_mode:
		"图片":
			var image_path := _first_preview_resource("冷资源/backimages/背景图",
				["png", "jpg", "jpeg", "webp"])
			_preview_texture(canvas, "PreviewImage", AssetLoader.tex(image_path),
				Rect2(Vector2.ZERO, canvas.size))
		"视频":
			var video_path := _first_preview_resource("backmovies/游戏中", ["mp4", "ogv", "webm"])
			var video := VideoStreamPlayer.new()
			video.name = "PreviewVideo"
			video.position = Vector2.ZERO
			video.size = canvas.size
			video.expand = true
			video.loop = true
			video.volume_db = -80.0
			video.mouse_filter = Control.MOUSE_FILTER_IGNORE
			video.stream = _preview_video_stream(video_path)
			canvas.add_child(video)
			if video.stream != null:
				video.play()
				video.paused = in_gameplay
		_:
			_build_dynamic_background_preview(canvas)
	var brightness_dim := ColorRect.new()
	brightness_dim.name = "BrightnessDim"
	brightness_dim.position = Vector2.ZERO
	brightness_dim.size = canvas.size
	brightness_dim.color = Color(0, 0, 0, clampf(
		0.45 + 0.10 * float(SettingsStore.background_brightness_level), 0.0, 0.95))
	brightness_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(brightness_dim)
	var mode := _mk_label(parent, "%s / %s / 亮度 %s" % [SettingsStore.background_mode,
		SettingsStore.dynamic_background_mode, _get_brightness()], 22, Vector2(34, 686))
	mode.name = "PreviewMode"
	mode.size = Vector2(586, 44)
	mode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode.add_theme_color_override("font_color", Color(0.0, 0.94, 0.98))


func _build_display_preview(parent: Control) -> void:
	var info := [
		["显示模式", _get_display_mode()], ["分辨率", _get_resolution()],
		["渲染引擎", _get_renderer()], ["FPS 上限", _get_fps()],
	]
	for i in info.size():
		var row := Panel.new()
		row.position = Vector2(34, 132 + i * 112)
		row.size = Vector2(586, 88)
		row.add_theme_stylebox_override("panel", _panel_style(
			Color(0.025, 0.065, 0.105, 0.88), Color(0.1, 0.23, 0.34, 0.8)))
		parent.add_child(row)
		var key := _mk_label(row, str(info[i][0]), 20, Vector2(22, 16))
		key.size = Vector2(220, 48)
		var value := _mk_label(row, str(info[i][1]), 20, Vector2(250, 16))
		value.size = Vector2(300, 48)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_color_override("font_color", Color(0.99, 0.84, 0.31))


func _build_profile_tab() -> void:
	var profile_card := Panel.new()
	profile_card.name = "ProfileIdentityCard"
	profile_card.position = Vector2(0, 0)
	profile_card.size = Vector2(520, 842)
	profile_card.add_theme_stylebox_override("panel", E5OriginalTheme.panel_style(
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	_content_body.add_child(profile_card)
	var identity_frame := UiKit.hud_frame(profile_card, Rect2(Vector2.ZERO, profile_card.size),
		"IdentityHudFrame", E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA,
		66.0, true, 18.0)
	identity_frame.fill_color = Color(0.010, 0.052, 0.115, 0.96)

	var eyebrow := _mk_label(profile_card, "PLAYER IDENTITY / 本机档案", 18, Vector2(34, 28))
	eyebrow.size = Vector2(430, 34)
	eyebrow.add_theme_color_override("font_color", Color(0.0, 0.92, 1.0))
	_profile_avatar = TextureRect.new()
	_profile_avatar.name = "ProfileAvatar"
	_profile_avatar.position = Vector2(145, 82)
	_profile_avatar.size = Vector2(230, 230)
	_profile_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_profile_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_profile_avatar.texture = _profile_avatar_texture()
	_profile_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_profile_avatar.modulate = Color.WHITE
	_profile_avatar.self_modulate = Color.WHITE
	var avatar_shader := load("res://fx/circular_avatar_mask.gdshader") as Shader
	var avatar_material := ShaderMaterial.new()
	avatar_material.shader = avatar_shader
	_profile_avatar.material = avatar_material
	profile_card.add_child(_profile_avatar)
	var avatar_ring := ReferenceRect.new()
	avatar_ring.position = Vector2(136, 73)
	avatar_ring.size = Vector2(248, 248)
	avatar_ring.border_color = Color(1.0, 0.12, 0.78, 0.92)
	avatar_ring.border_width = 4.0
	avatar_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	profile_card.add_child(avatar_ring)

	var avatar_button := Button.new()
	avatar_button.text = "更换头像"
	avatar_button.position = Vector2(145, 334)
	avatar_button.size = Vector2(230, 54)
	UiKit.skin_arcade_button(avatar_button, false, false, 21,
		E5OriginalTheme.MAGENTA)
	avatar_button.pressed.connect(_open_profile_avatar_dialog)
	profile_card.add_child(avatar_button)

	var name_title := _mk_label(profile_card, "昵称", 18, Vector2(36, 430))
	name_title.size = Vector2(120, 30)
	name_title.add_theme_color_override("font_color", Color(0.62, 0.72, 0.86))
	_profile_name_input = LineEdit.new()
	_profile_name_input.name = "NicknameInput"
	_profile_name_input.text = str(ProfileStore.profile.get("昵称", "玩家"))
	_profile_name_input.position = Vector2(36, 468)
	_profile_name_input.size = Vector2(448, 58)
	_profile_name_input.max_length = 16
	UiKit.skin_arcade_input(_profile_name_input, 24)
	_profile_name_input.text_submitted.connect(func(_text: String): _save_profile_name())
	profile_card.add_child(_profile_name_input)
	var save_name := Button.new()
	save_name.text = "保存昵称"
	save_name.position = Vector2(36, 544)
	save_name.size = Vector2(448, 58)
	UiKit.skin_arcade_button(save_name, true, false, 22)
	save_name.pressed.connect(_save_profile_name)
	profile_card.add_child(save_name)
	_profile_feedback = _mk_label(profile_card, "头像支持 PNG / JPG / WEBP，昵称最多 16 字。", 16,
		Vector2(36, 620))
	_profile_feedback.size = Vector2(448, 68)
	_profile_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_profile_feedback.add_theme_color_override("font_color", Color(0.52, 0.64, 0.77))
	_profile_feedback.add_theme_constant_override("outline_size", 0)

	var progress_card := Panel.new()
	progress_card.name = "ProfileProgressCard"
	progress_card.position = Vector2(552, 0)
	progress_card.size = Vector2(837, 842)
	progress_card.add_theme_stylebox_override("panel", E5OriginalTheme.panel_style(
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0))
	_content_body.add_child(progress_card)
	var progress_frame := UiKit.hud_frame(progress_card, Rect2(Vector2.ZERO, progress_card.size),
		"ProgressHudFrame", E5OriginalTheme.MAGENTA, E5OriginalTheme.CYAN,
		66.0, true, 18.0)
	progress_frame.fill_color = Color(0.024, 0.028, 0.082, 0.96)
	var rank_title := _mk_label(progress_card, "RANK / 当前段位", 18, Vector2(38, 28))
	rank_title.size = Vector2(350, 34)
	rank_title.add_theme_color_override("font_color", Color(1.0, 0.36, 0.88))
	var rank_icon := TextureRect.new()
	rank_icon.name = "ProfileRankIcon"
	rank_icon.texture = AssetLoader.tex(ProfileStore.get_rank_asset_path_for_display())
	rank_icon.position = Vector2(40, 74)
	rank_icon.size = Vector2(260, 160)
	rank_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rank_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rank_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_card.add_child(rank_icon)
	var rank_label := _mk_label(progress_card, ProfileStore.get_rank_label_for_display(), 46, Vector2(326, 94))
	rank_label.name = "ProfileRankLabel"
	rank_label.size = Vector2(420, 70)
	rank_label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.38))
	var level_summary := _mk_label(progress_card, "最高模式等级  Lv.%d" % ProfileStore.get_highest_mode_level_for_display(),
		22, Vector2(328, 164))
	level_summary.size = Vector2(430, 42)
	level_summary.add_theme_color_override("font_color", Color(0.72, 0.84, 0.96))

	_build_profile_progress_row(progress_card, "花式", ProfileStore.get_mode_progress_for_display("花式"),
		Vector2(38, 248), Color(0.02, 0.92, 1.0))
	_build_profile_progress_row(progress_card, "竞速", ProfileStore.get_mode_progress_for_display("竞速"),
		Vector2(38, 394), Color(1.0, 0.14, 0.76))
	_build_profile_progress_row(progress_card, "diy", ProfileStore.get_mode_progress_for_display("DIY"),
		Vector2(38, 540), Color(0.72, 0.34, 1.0))
	var stats: Dictionary = ProfileStore.profile.get("统计", {})
	var stat_text := "MAX COMBO  %d     /     最高分  %d\n累计 S  %d          /     游玩 %d 分钟" % [
		int(stats.get("最大Combo", 0)), int(stats.get("最高分", 0)),
		int(stats.get("累计评价S数", 0)), int(stats.get("游玩时长分钟", 0)),
	]
	var stat_label := _mk_label(progress_card, stat_text, 18, Vector2(42, 704))
	stat_label.size = Vector2(730, 82)
	stat_label.add_theme_color_override("font_color", Color(0.70, 0.80, 0.92))


func _build_profile_progress_row(parent: Control, mode: String, progress: Dictionary,
		position: Vector2, accent: Color) -> void:
	var level := int(progress.get("等级", 1))
	var exp := float(progress.get("经验", 0.0))
	var need := ExpSystem.exp_to_next_level(level)
	var ratio := ExpSystem.overall_progress_ratio(progress)
	var display_mode := "DIY" if mode.to_lower() == "diy" else mode
	var holder := Panel.new()
	holder.name = "%sProgress" % mode
	holder.position = position
	holder.size = Vector2(760, 126)
	holder.add_theme_stylebox_override("panel", _panel_style(
		Color(0.015, 0.045, 0.075, 0.94), Color(accent.r, accent.g, accent.b, 0.62)))
	parent.add_child(holder)
	var title := _mk_label(holder, "%s等级  Lv.%d" % [display_mode, level], 24, Vector2(24, 12))
	title.name = "Level"
	title.size = Vector2(430, 40)
	title.add_theme_color_override("font_color", accent)
	var overall_percent := roundi(ratio * 100.0)
	var value_text := "总进度 100%  ·  MAX" if level >= ExpSystem.MAX_LEVEL else \
		"总进度 %d%%  ·  本级 %.0f/%d EXP" % [overall_percent, exp, need]
	var value := _mk_label(holder, value_text, 16, Vector2(410, 16))
	value.name = "ProgressValue"
	value.size = Vector2(320, 36)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bar := ProgressBar.new()
	bar.name = "%sExperienceProgress" % mode
	bar.position = Vector2(24, 72)
	bar.size = Vector2(712, 32)
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = ratio
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiKit.skin_arcade_progress(bar, accent,
		E5OriginalTheme.MAGENTA if mode != "竞速" else E5OriginalTheme.CYAN)
	holder.add_child(bar)


func _profile_avatar_texture() -> Texture2D:
	var avatar_path := str(ProfileStore.profile.get("头像文件", ""))
	var texture := AssetLoader.tex(avatar_path) if not avatar_path.is_empty() else null
	return texture if texture != null else AssetLoader.tex("UI-img/个人中心-个人资料/默认头像.png")


func _save_profile_name() -> void:
	if _profile_name_input == null:
		return
	if ProfileStore.set_nickname(_profile_name_input.text):
		_profile_name_input.text = str(ProfileStore.profile.get("昵称", "玩家"))
		_profile_feedback.text = "昵称已保存，并会同步到游戏 HUD。"
		_profile_feedback.add_theme_color_override("font_color", Color(0.34, 1.0, 0.72))
		setting_changed.emit("profile")
	else:
		_profile_feedback.text = "昵称不能为空。"
		_profile_feedback.add_theme_color_override("font_color", Color(1.0, 0.40, 0.50))


func _open_profile_avatar_dialog() -> void:
	if _profile_file_dialog == null:
		_profile_file_dialog = FileDialog.new()
		_profile_file_dialog.name = "AvatarFileDialog"
		_profile_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_profile_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_profile_file_dialog.filters = PackedStringArray([
			"*.png, *.jpg, *.jpeg, *.webp ; 图片文件",
		])
		_profile_file_dialog.use_native_dialog = true
		_profile_file_dialog.file_selected.connect(_on_profile_avatar_selected)
		add_child(_profile_file_dialog)
	_profile_file_dialog.popup_centered_ratio(0.72)


func _on_profile_avatar_selected(path: String) -> void:
	if ProfileStore.set_avatar_file(path):
		if _profile_avatar != null:
			_profile_avatar.texture = _profile_avatar_texture()
		_profile_feedback.text = "头像已保存，并会在下一帧同步到游戏 HUD。"
		_profile_feedback.add_theme_color_override("font_color", Color(0.34, 1.0, 0.72))
		setting_changed.emit("profile")
	else:
		_profile_feedback.text = "头像读取失败：请选择有效的 PNG/JPG/WEBP 文件。"
		_profile_feedback.add_theme_color_override("font_color", Color(1.0, 0.40, 0.50))


func _build_action_tab(index: int) -> void:
	if not in_gameplay:
		_build_exit_desktop_tab()
		return
	var titles := ["继续当前歌曲", "重新载入当前歌曲", "退出本局并返回选歌", "退出 E5CM 到桌面"]
	var descriptions := [
		"解除暂停并立即回到谱面。也可以再次按 ESC。",
		"重新从头载入当前谱面，分数、血量和 Combo 将重置。",
		"结束当前对局并返回歌曲选择界面。",
		"保存设置后关闭程序。",
	]
	var local := clampi(index - 5, 0, 3)
	var card := Panel.new()
	card.position = Vector2(170, 160)
	card.size = Vector2(1040, 500)
	var destructive := local >= 2
	card.add_theme_stylebox_override("panel", _panel_style(
		Color(0.06, 0.025, 0.04, 0.96) if destructive else Color(0.02, 0.075, 0.10, 0.96),
		Color(1.0, 0.22, 0.34, 0.90) if destructive else Color(0.08, 0.88, 1.0, 0.90)))
	_content_body.add_child(card)
	var heading := _mk_label(card, titles[local], 34, Vector2(52, 54))
	heading.size = Vector2(930, 60)
	var description := _mk_label(card, descriptions[local], 20, Vector2(52, 142))
	description.size = Vector2(930, 72)
	description.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
	var confirm := Button.new()
	confirm.text = "确认执行"
	confirm.position = Vector2(330, 310)
	confirm.size = Vector2(380, 86)
	UiKit.skin_arcade_button(confirm, local <= 1, destructive, 26,
		E5OriginalTheme.MAGENTA if destructive else E5OriginalTheme.CYAN)
	if local == 0:
		confirm.text = "返回游戏"
		confirm.pressed.connect(_on_resume_pressed)
	elif local == 1:
		confirm.pressed.connect(_on_restart_pressed)
	elif local == 2:
		confirm.pressed.connect(_on_quit_pressed)
	else:
		confirm.pressed.connect(_on_exit_desktop_pressed)
	card.add_child(confirm)


func _build_exit_desktop_tab() -> void:
	var card := Panel.new()
	card.name = "ExitDesktopCard"
	card.position = Vector2(170, 160)
	card.size = Vector2(1040, 500)
	card.add_theme_stylebox_override("panel", _panel_style(
		Color(0.065, 0.018, 0.045, 0.97), Color(1.0, 0.18, 0.42, 0.94)))
	_content_body.add_child(card)
	var heading := _mk_label(card, "退出 E5CM 到桌面", 36, Vector2(52, 54))
	heading.size = Vector2(930, 60)
	var description := _mk_label(card,
		"将保存当前设置和个人资料，然后关闭整个程序。此操作不会只返回上一级。",
		20, Vector2(52, 142))
	description.size = Vector2(930, 82)
	description.add_theme_color_override("font_color", Color(0.78, 0.82, 0.90))
	var confirm := Button.new()
	confirm.name = "ConfirmExitDesktop"
	confirm.text = "确认退出游戏"
	confirm.position = Vector2(330, 310)
	confirm.size = Vector2(380, 86)
	UiKit.skin_arcade_button(confirm, false, true, 26, E5OriginalTheme.DANGER)
	confirm.pressed.connect(_on_exit_desktop_pressed)
	card.add_child(confirm)


func _binding_center(player: int, lane: int) -> Vector2:
	var player_center := Vector2(345.0 + float(player) * 700.0, 360.0)
	var offsets := [
		Vector2(-160, 145), # 左下
		Vector2(-160, -145), # 左上
		Vector2(0, 0),       # 中间
		Vector2(160, -145),  # 右上
		Vector2(160, 145),   # 右下
	]
	return player_center + offsets[clampi(lane, 0, 4)]


func binding_position_for_test(player: int, lane: int) -> Vector2:
	return _binding_center(player, lane)


func _build_bindings() -> void:
	_binding_actions.clear()
	_binding_buttons.clear()
	_binding_selected = 0
	var help := _mk_label(_content_body, "按原版五键踏板位置选择轨道，再按确认录入新按键；冲突键不会覆盖。", 22, Vector2(0, 0))
	help.size = Vector2(1380, 42)
	for player in 2:
		var player_title := _mk_label(_content_body, "P%d 五键踏板" % (player + 1), 25,
			Vector2(215 + player * 700, 66))
		player_title.size = Vector2(260, 42)
		player_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_title.add_theme_color_override("font_color", Color(0.0, 0.94, 0.98))
	var key_atlas := AssetLoader.key_atlas()
	var key_names := ["bl", "tl", "cc", "tr", "br"]
	for lane in 5:
		for player in 2:
			var action := "%s_lane%d" % ["p1" if player == 0 else "p2", lane]
			var button := Button.new()
			button.name = "Binding_%s" % action
			button.size = Vector2(210, 96)
			button.position = _binding_center(player, lane) - button.size * 0.5
			button.alignment = HORIZONTAL_ALIGNMENT_CENTER
			UiKit.skin_arcade_button(button, false, false, 18,
				E5OriginalTheme.CYAN if player == 0 else E5OriginalTheme.MAGENTA)
			button.pressed.connect(_start_rebind.bind(action))
			_content_body.add_child(button)
			var icon := TextureRect.new()
			icon.name = "PadIcon"
			icon.texture = key_atlas.get("key_%s" % key_names[lane])
			icon.position = Vector2(6, 8)
			icon.size = Vector2(68, 68)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(icon)
			_binding_actions.append(action)
			_binding_buttons.append(button)
	_binding_status = _mk_label(_content_body, "", 22, Vector2(24, 690))
	_binding_status.name = "BindingStatus"
	_binding_status.size = Vector2(1310, 72)
	_binding_status.add_theme_color_override("font_color", Color(0.99, 0.84, 0.31))
	_refresh_binding_buttons()


func _binding_title(action: String) -> String:
	var player := "P1" if action.begins_with("p1_") else "P2"
	var lane_index := int(action.get_slice("lane", 1))
	var lane_names := ["左下", "左上", "中间", "右上", "右下"]
	return "%s %s" % [player, lane_names[clampi(lane_index, 0, 4)]]


func _refresh_binding_buttons() -> void:
	for i in _binding_buttons.size():
		var action := _binding_actions[i]
		var codes: Array = SettingsStore.key_bindings.get(action, [])
		var button := _binding_buttons[i]
		var selected_button := i == _binding_selected
		var rebinding := action == _rebinding_action
		button.text = "        %s\n        %s" % [_binding_title(action), _key_names(codes)]
		button.modulate = Color.WHITE
		UiKit.skin_arcade_button(button, selected_button or rebinding, false, 18,
			E5OriginalTheme.CYAN if action.begins_with("p1_") else E5OriginalTheme.MAGENTA)
		if rebinding:
			button.text = "%s\n等待按键…（ESC 取消）" % _binding_title(action)


func _start_rebind(action: String) -> void:
	if not _binding_actions.has(action):
		return
	_binding_selected = _binding_actions.find(action)
	_rebinding_action = action
	_binding_status.text = "正在修改 %s" % _binding_title(action)
	_refresh_binding_buttons()


func _cancel_rebind() -> void:
	if _rebinding_action.is_empty():
		return
	_rebinding_action = ""
	if _binding_status != null:
		_binding_status.text = "已取消按键修改"
	_refresh_binding_buttons()


func _binding_conflict(action: String, binding: Variant) -> String:
	var wanted := SettingsStore.binding_signature(binding)
	if wanted.is_empty():
		return ""
	for other_action in SettingsStore.key_bindings:
		if str(other_action) == action:
			continue
		var bindings: Array = SettingsStore.key_bindings[other_action]
		for other_binding in bindings:
			if SettingsStore.binding_signature(other_binding) == wanted:
				return str(other_action)
	return ""


func _try_rebind(action: String, binding: Variant) -> bool:
	if not SettingsStore.key_bindings.has(action) or SettingsStore.binding_signature(binding).is_empty():
		return false
	var conflict := _binding_conflict(action, binding)
	var display_name := SettingsStore.binding_display_name(binding)
	if not conflict.is_empty():
		if _binding_status != null:
			_binding_status.text = "输入 %s 已被 %s 占用" % [display_name, _binding_title(conflict)]
			_binding_status.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		return false
	SettingsStore.rebind(action, [binding])
	_rebinding_action = ""
	if _binding_status != null:
		_binding_status.text = "%s 已设为 %s" % [_binding_title(action), display_name]
		_binding_status.add_theme_color_override("font_color", Color(0.45, 1.0, 0.65))
	_refresh_binding_buttons()
	return true


func _try_rebind_key(action: String, keycode: int) -> bool:
	return keycode > 0 and _try_rebind(action, keycode)


func _try_rebind_event(action: String, event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var code := int(event.keycode if event.keycode != 0 else event.physical_keycode)
		return _try_rebind_key(action, code)
	if event is InputEventJoypadButton and event.pressed:
		return _try_rebind(action, {"type": "joy_button", "device": int(event.device),
			"button": int(event.button_index)})
	if event is InputEventMouseButton and event.pressed:
		return _try_rebind(action, {"type": "mouse_button", "button": int(event.button_index)})
	return false


func _handle_binding_input(event: InputEvent) -> bool:
	if not _rebinding_action.is_empty():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_cancel_rebind()
			return true
		if (event is InputEventKey and event.pressed and not event.echo) \
				or (event is InputEventJoypadButton and event.pressed) \
				or (event is InputEventMouseButton and event.pressed):
			_try_rebind_event(_rebinding_action, event)
			return true
		return false
	if event.is_action_pressed("ui_down"):
		_binding_selected = (_binding_selected + 2) % _binding_actions.size()
	elif event.is_action_pressed("ui_up"):
		_binding_selected = (_binding_selected - 2 + _binding_actions.size()) % _binding_actions.size()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_binding_selected = _binding_selected + 1 if _binding_selected % 2 == 0 else _binding_selected - 1
	elif event.is_action_pressed("ui_accept"):
		_start_rebind(_binding_actions[_binding_selected])
	else:
		return false
	_refresh_binding_buttons()
	return true


func _key_names(bindings: Array) -> String:
	var names := PackedStringArray()
	for binding in bindings:
		names.append(SettingsStore.binding_display_name(binding))
	return " / ".join(names) if not names.is_empty() else "未绑定"


func _mk_label(parent: Node, text: String, size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	parent.add_child(l)
	return l


func _mk_arrow(parent: Node, tex: Texture2D, pos: Vector2, row: int, dir: int) -> TextureButton:
	var b := TextureButton.new()
	b.texture_normal = tex
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
	b.custom_minimum_size = Vector2(44, 44)
	b.size = b.custom_minimum_size
	b.position = pos
	b.pressed.connect(_step_row.bind(row, dir))
	parent.add_child(b)
	return b


func _on_resume_pressed() -> void:
	close_menu()


func _on_restart_pressed() -> void:
	visible = false
	SettingsStore.save_settings()
	restart_requested.emit()


func _on_quit_pressed() -> void:
	visible = false
	SettingsStore.save_settings()
	quit_requested.emit()


func _on_exit_desktop_pressed() -> void:
	SettingsStore.save_settings()
	ProfileStore.save_profile()
	get_tree().quit()


func _on_row_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		_selected = i
		_refresh_all()


func _step_row(i: int, dir: int) -> void:
	_selected = i
	call(str(_row_defs[i][2]), dir)
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	_refresh_all()


func _refresh_all() -> void:
	for i in _row_nodes.size():
		var holder: Control = _row_nodes[i]
		var val: Label = holder.get_node("Value")
		var selected_row := i == _selected
		val.text = str(call(str(_row_defs[i][1])))
		val.add_theme_color_override("font_color",
			E5OriginalTheme.GOLD if selected_row else E5OriginalTheme.CYAN_SOFT)
		holder.modulate = Color.WHITE
		if holder is Panel:
			(holder as Panel).add_theme_stylebox_override("panel", _panel_style(
				Color(0.055, 0.14, 0.18, 0.96) if selected_row else Color(0.016, 0.052, 0.10, 0.92),
				E5OriginalTheme.GOLD if selected_row else Color(E5OriginalTheme.CYAN.r,
					E5OriginalTheme.CYAN.g, E5OriginalTheme.CYAN.b, 0.42)))
	_refresh_preview_panel()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _active_tab == 3 and _handle_binding_input(event):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down") and not _row_defs.is_empty():
		_selected = (_selected + 1) % _row_defs.size()
		_refresh_all()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") and not _row_defs.is_empty():
		_selected = (_selected - 1 + _row_defs.size()) % _row_defs.size()
		_refresh_all()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left") and not _row_defs.is_empty():
		_step_row(_selected, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") and not _row_defs.is_empty():
		_step_row(_selected, 1)
		get_viewport().set_input_as_handled()
