extends Node
## 设置存储（autoload: SettingsStore）
## 对应旧项目 sqlite 全局设置 + 游戏ESC设置作用域。
## 负责：加载/保存设置、运行时构建 InputMap（键位可重绑）。

const CONFIG_PATH := "user://settings.cfg"
const SUPPORTED_FPS_LIMITS := [60, 120, 144, 165, 240]

# ---- 游戏设置（默认值与旧版一致）----
var scroll_speed := 4.0            # 卷轴速度 X1.0~X7.0 步进0.25
var chart_offset_ms := 0           # 谱面偏移 ±500ms 步进10
var bgm_volume := 10               # 0~100
var muted := false
var hit_sound := true
var bpm_scroll_effect := true      # BPM变速效果
var image_slideshow := false       # 图片幻灯片模式
var background_mode := "动态背景"  # 图片 / 视频 / 动态背景
var dynamic_background_mode := "唱片"
var hidden_mode := "关闭"
var track_mode := "正常"
var direction_mode := "关闭"       # 关闭 / 反向（与原版一致）
var display_mode := "窗口"          # 窗口 / 独占全屏
var arrow_size_percent := 100
var status_hud_enabled := true
var performance_mode := false
var autoplay := false
var show_ready_animation := true
var background_brightness_level := 0
var arrow_skin := "原版默认"
var max_fps := 240        # 固定上限，禁止旧版“不限帧”把菜单跑到上千 FPS
var vsync := false

# ---- 默认键位（P1: 1/7/5/9/3 + 小键盘；P2/双人左区: Z/Q/S/E/C）----
# 轨道顺序：0=左下 1=左上 2=中间 3=右上 4=右下
const P1_DEFAULT_KEYS := {
	0: [KEY_1, KEY_KP_1],
	1: [KEY_7, KEY_KP_7],
	2: [KEY_5, KEY_KP_5],
	3: [KEY_9, KEY_KP_9],
	4: [KEY_3, KEY_KP_3],
}
const P2_DEFAULT_KEYS := {
	0: [KEY_Z],
	1: [KEY_Q],
	2: [KEY_S],
	3: [KEY_E],
	4: [KEY_C],
}

var key_bindings := {}   # action -> Array[int keycode | typed binding Dictionary]
var persist_enabled := true


func _ready() -> void:
	load_settings()
	apply_input_map()
	apply_performance()


## 应用帧率/垂直同步设置
func _normalize_fps_limit(value: int) -> int:
	return value if value in SUPPORTED_FPS_LIMITS else 240


func apply_performance() -> void:
	max_fps = _normalize_fps_limit(max_fps)
	Engine.max_fps = max_fps
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	apply_display_mode()


func apply_display_mode() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		return
	if display_mode == "独占全屏":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		# 远程桌面、部分多屏驱动或系统策略可能拒绝独占全屏。
		# 此时立即回退窗口，避免留下不可见/任务栏异常的窗口状态。
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			display_mode = "窗口"
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		key_bindings = _default_bindings()
		return
	scroll_speed = clampf(float(cfg.get_value("game", "scroll_speed", 4.0)), 1.0, 7.0)
	chart_offset_ms = clampi(int(cfg.get_value("game", "chart_offset_ms", 0)), -500, 500)
	bgm_volume = clampi(int(cfg.get_value("audio", "bgm_volume", 10)), 0, 100)
	muted = bool(cfg.get_value("audio", "muted", false))
	hit_sound = bool(cfg.get_value("audio", "hit_sound", true))
	bpm_scroll_effect = bool(cfg.get_value("game", "bpm_scroll_effect", true))
	image_slideshow = bool(cfg.get_value("game", "image_slideshow", false))
	background_mode = str(cfg.get_value("game", "background_mode", "动态背景"))
	dynamic_background_mode = str(cfg.get_value("game", "dynamic_background_mode", "唱片"))
	hidden_mode = _normalize_hidden_mode(str(cfg.get_value("game", "hidden_mode", "关闭")))
	track_mode = _normalize_track_mode(str(cfg.get_value("game", "track_mode", "正常")))
	direction_mode = _normalize_direction_mode(str(cfg.get_value("game", "direction_mode", "关闭")))
	display_mode = str(cfg.get_value("display", "mode", "窗口"))
	if display_mode not in ["窗口", "独占全屏"]:
		display_mode = "窗口"
	arrow_size_percent = clampi(int(cfg.get_value("game", "arrow_size_percent", 100)), 50, 150)
	status_hud_enabled = bool(cfg.get_value("game", "status_hud_enabled", true))
	performance_mode = bool(cfg.get_value("game", "performance_mode", false))
	autoplay = bool(cfg.get_value("debug", "autoplay", false))
	show_ready_animation = bool(cfg.get_value("game", "show_ready_animation", true))
	background_brightness_level = int(cfg.get_value("game", "background_brightness_level", 0))
	arrow_skin = str(cfg.get_value("game", "arrow_skin", "原版默认"))
	max_fps = _normalize_fps_limit(int(cfg.get_value("display", "max_fps", 240)))
	vsync = bool(cfg.get_value("display", "vsync", false))

	key_bindings = _default_bindings()
	var saved = cfg.get_value("input", "key_bindings", {})
	if saved is Dictionary:
		for action in saved:
			if key_bindings.has(action) and saved[action] is Array:
				key_bindings[action] = saved[action].duplicate()


func save_settings() -> void:
	if not persist_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("game", "scroll_speed", scroll_speed)
	cfg.set_value("game", "chart_offset_ms", chart_offset_ms)
	cfg.set_value("game", "bpm_scroll_effect", bpm_scroll_effect)
	cfg.set_value("game", "image_slideshow", image_slideshow)
	cfg.set_value("game", "background_mode", background_mode)
	cfg.set_value("game", "dynamic_background_mode", dynamic_background_mode)
	cfg.set_value("game", "hidden_mode", hidden_mode)
	cfg.set_value("game", "track_mode", track_mode)
	cfg.set_value("game", "direction_mode", direction_mode)
	cfg.set_value("game", "arrow_size_percent", arrow_size_percent)
	cfg.set_value("game", "status_hud_enabled", status_hud_enabled)
	cfg.set_value("game", "performance_mode", performance_mode)
	cfg.set_value("game", "show_ready_animation", show_ready_animation)
	cfg.set_value("game", "background_brightness_level", background_brightness_level)
	cfg.set_value("audio", "bgm_volume", bgm_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("audio", "hit_sound", hit_sound)
	cfg.set_value("debug", "autoplay", autoplay)
	cfg.set_value("game", "arrow_skin", arrow_skin)
	cfg.set_value("display", "max_fps", max_fps)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "mode", display_mode)
	cfg.set_value("input", "key_bindings", key_bindings)
	cfg.save(CONFIG_PATH)


func _normalize_hidden_mode(value: String) -> String:
	match value.strip_edges():
		"渐隐": return "半隐"
		"隐身": return "全隐"
		"关闭", "半隐", "全隐": return value.strip_edges()
	return "关闭"


func _normalize_track_mode(value: String) -> String:
	match value.strip_edges():
		"波浪": return "摇摆"
		"正常", "摇摆", "旋转": return value.strip_edges()
	return "正常"


func _normalize_direction_mode(value: String) -> String:
	return "反向" if value.strip_edges() == "反向" else "关闭"


func _default_bindings() -> Dictionary:
	var bindings := {}
	for lane in 5:
		bindings["p1_lane%d" % lane] = P1_DEFAULT_KEYS[lane].duplicate()
		bindings["p2_lane%d" % lane] = P2_DEFAULT_KEYS[lane].duplicate()
	# 菜单踏板抽象：左=1 右=3 确认=5（与旧版 踏板控制.py 一致）
	bindings["pedal_left"] = [KEY_1, KEY_KP_1]
	bindings["pedal_right"] = [KEY_3, KEY_KP_3]
	bindings["pedal_confirm"] = [KEY_5, KEY_KP_5]
	bindings["coin"] = [KEY_F]
	return bindings


func binding_signature(binding: Variant) -> String:
	if typeof(binding) == TYPE_INT:
		return "key:%d" % int(binding)
	if binding is Dictionary:
		var data: Dictionary = binding
		match str(data.get("type", "")):
			"key":
				return "key:%d" % int(data.get("code", 0))
			"mouse_button":
				return "mouse_button:%d" % int(data.get("button", 0))
			"joy_button":
				return "joy_button:%d:%d" % [int(data.get("device", -1)),
					int(data.get("button", -1))]
	return ""


func binding_display_name(binding: Variant) -> String:
	if typeof(binding) == TYPE_INT:
		return OS.get_keycode_string(int(binding))
	if not binding is Dictionary:
		return "未绑定"
	var data: Dictionary = binding
	match str(data.get("type", "")):
		"key":
			return OS.get_keycode_string(int(data.get("code", 0)))
		"mouse_button":
			return "MOUSE %d" % int(data.get("button", 0))
		"joy_button":
			return "JOY%d B%d" % [int(data.get("device", -1)) + 1,
				int(data.get("button", -1)) + 1]
	return "未绑定"


func binding_to_event(binding: Variant) -> InputEvent:
	if typeof(binding) == TYPE_INT:
		var key_event := InputEventKey.new()
		key_event.keycode = int(binding)
		return key_event
	if not binding is Dictionary:
		return null
	var data: Dictionary = binding
	match str(data.get("type", "")):
		"key":
			var key_event := InputEventKey.new()
			key_event.keycode = int(data.get("code", 0))
			return key_event
		"mouse_button":
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = int(data.get("button", 0))
			return mouse_event
		"joy_button":
			var joy_event := InputEventJoypadButton.new()
			joy_event.device = int(data.get("device", -1))
			joy_event.button_index = int(data.get("button", -1))
			return joy_event
	return null


func apply_input_map() -> void:
	for action in key_bindings:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action)
		for binding in key_bindings[action]:
			var event := binding_to_event(binding)
			if event != null:
				InputMap.action_add_event(action, event)


func rebind(action: String, bindings: Array) -> void:
	key_bindings[action] = bindings.duplicate(true)
	apply_input_map()
	save_settings()
