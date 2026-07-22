extends Node
## 场景路由（autoload: SceneRouter）
## 对应旧项目 main.py 的场景表 + {"切换到": …, "载荷": …} 协议。
## 过渡效果：黑屏淡入淡出（默认）或原版选中元素缩小后放大覆盖全屏。

const SCENES := {
	"boot": "res://scenes/boot/boot.tscn",
	"coin": "res://scenes/coin/coin.tscn",
	"login": "res://scenes/login/login.tscn",
	"profile": "res://scenes/profile/profile.tscn",
	"mode_select": "res://scenes/mode_select/mode_select.tscn",
	"submode_select": "res://scenes/submode_select/submode_select.tscn",
	"song_select": "res://scenes/song_select/song_select.tscn",
	"training_setup": "res://scenes/training_setup/training_setup.tscn",
	"loading": "res://scenes/loading/loading.tscn",
	"gameplay": "res://scenes/gameplay/gameplay.tscn",
	"settlement": "res://scenes/settlement/settlement.tscn",
}

const FADE_TO_BLACK_SECONDS := 0.06
const FADE_FROM_BLACK_SECONDS := 0.10
const MAX_ZOOM_TRANSITION_SECONDS := 0.18
const PREWARM_SCENE_KEYS := [
	"login", "profile", "mode_select", "submode_select", "song_select", "training_setup",
]

var payload := {}          # 目标场景在 _ready 里读取
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _busy := false
var _prewarm_pending := {}
var _prewarm_queue: Array[String] = []
var _prewarmed_scenes := {}


func _ready() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)
	call_deferred("_begin_menu_prewarm")


func _begin_menu_prewarm() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		return
	_prewarm_queue.clear()
	for raw_key in PREWARM_SCENE_KEYS:
		var key := str(raw_key)
		if not _prewarmed_scenes.has(key):
			_prewarm_queue.append(key)
	_request_next_prewarm()


func _request_next_prewarm() -> void:
	if not _prewarm_pending.is_empty() or _prewarm_queue.is_empty():
		return
	var key: String = _prewarm_queue.pop_front()
	var path := str(SCENES.get(key, ""))
	if path.is_empty():
		_request_next_prewarm()
		return
	# Godot 4.6 同时用多个子线程解析文本 tscn 会偶发依赖争抢；逐个后台加载更稳定。
	var err := ResourceLoader.load_threaded_request(path, "PackedScene", false)
	if err == OK:
		_prewarm_pending[key] = path
	else:
		_request_next_prewarm()


func _process(_delta: float) -> void:
	if _prewarm_pending.is_empty():
		return
	var completed := false
	for raw_key in _prewarm_pending.keys():
		var key := str(raw_key)
		var path := str(_prewarm_pending[key])
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			if packed != null:
				_prewarmed_scenes[key] = packed
			_prewarm_pending.erase(key)
			completed = true
		elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_prewarm_pending.erase(key)
			completed = true
	if completed:
		_request_next_prewarm()


func _change_scene_now(scene_key: String) -> Error:
	var packed := _prewarmed_scenes.get(scene_key) as PackedScene
	if packed != null:
		return get_tree().change_scene_to_packed(packed)
	if _prewarm_pending.has(scene_key):
		var path := str(_prewarm_pending[scene_key])
		packed = ResourceLoader.load_threaded_get(path) as PackedScene
		_prewarm_pending.erase(scene_key)
		if packed != null:
			_prewarmed_scenes[scene_key] = packed
			_request_next_prewarm()
			return get_tree().change_scene_to_packed(packed)
	# 尚未开始预热的目标从队列移除，避免同步加载后后台再次解析同一场景。
	_prewarm_queue.erase(scene_key)
	return get_tree().change_scene_to_file(str(SCENES[scene_key]))


## data = 传给目标场景的载荷；fade=false 对应旧版"禁用黑屏过渡"
func change_to(scene_key: String, data := {}, fade := true) -> void:
	if _busy or not SCENES.has(scene_key):
		push_warning("SceneRouter: 未知场景或切换中 -> %s" % scene_key)
		return
	_busy = true
	payload = data
	if fade:
		var tw := create_tween()
		tw.tween_property(_fade_rect, "color:a", 1.0, FADE_TO_BLACK_SECONDS)
		await tw.finished
	var err := _change_scene_now(scene_key)
	if err != OK:
		push_error("SceneRouter: 场景切换失败 %s -> %s" % [scene_key, error_string(err)])
		payload = {}
		_fade_rect.color.a = 0.0
		_busy = false
		return
	await get_tree().process_frame
	# TopBar 与黑屏淡出同时播放，绝不能排在淡出之后形成额外等待感。
	TopBar.play_scene_entry(get_tree().current_scene)
	if fade:
		var tw2 := create_tween()
		tw2.tween_property(_fade_rect, "color:a", 0.0, FADE_FROM_BLACK_SECONDS)
		await tw2.finished
	_busy = false


## 原版公用放大过渡：前 25% 缩到 0.92，随后放大到 cover 全屏并淡出。
func change_to_with_zoom(scene_key: String, target: Control, data := {}, duration := 0.18) -> void:
	if _busy or not SCENES.has(scene_key):
		push_warning("SceneRouter: 未知场景或切换中 -> %s" % scene_key)
		return
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		change_to(scene_key, data, false)
		return
	_busy = true
	payload = data
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.z_index = 4095
	if target.pivot_offset == Vector2.ZERO:
		target.pivot_offset = target.size * 0.5
	var start_scale := target.scale
	var shrink_scale := start_scale * 0.92
	var width := maxf(1.0, target.size.x * maxf(0.001, start_scale.x))
	var height := maxf(1.0, target.size.y * maxf(0.001, start_scale.y))
	var cover := maxf(1920.0 / width, 1080.0 / height) * 1.04
	var end_scale := start_scale * maxf(1.0, cover)
	var end_color := target.modulate
	end_color.a = 0.0
	var effective_duration := minf(maxf(0.06, duration), MAX_ZOOM_TRANSITION_SECONDS)
	var shrink_sec := maxf(0.01, effective_duration * 0.22)
	var expand_sec := maxf(0.01, effective_duration - shrink_sec)
	var tween := create_tween()
	tween.tween_property(target, "scale", shrink_scale, shrink_sec) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "scale", end_scale, expand_sec) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(target, "modulate", end_color, expand_sec) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	var err := _change_scene_now(scene_key)
	if err != OK:
		push_error("SceneRouter: 场景切换失败 %s -> %s" % [scene_key, error_string(err)])
		payload = {}
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_busy = false
		return
	await get_tree().process_frame
	TopBar.play_scene_entry(get_tree().current_scene)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func is_transition_busy() -> bool:
	return _busy


func take_payload() -> Dictionary:
	var data := payload
	payload = {}
	return data
