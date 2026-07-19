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
	"loading": "res://scenes/loading/loading.tscn",
	"gameplay": "res://scenes/gameplay/gameplay.tscn",
	"settlement": "res://scenes/settlement/settlement.tscn",
}

var payload := {}          # 目标场景在 _ready 里读取
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _busy := false


func _ready() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)


## data = 传给目标场景的载荷；fade=false 对应旧版"禁用黑屏过渡"
func change_to(scene_key: String, data := {}, fade := true) -> void:
	if _busy or not SCENES.has(scene_key):
		push_warning("SceneRouter: 未知场景或切换中 -> %s" % scene_key)
		return
	_busy = true
	payload = data
	if fade:
		var tw := create_tween()
		tw.tween_property(_fade_rect, "color:a", 1.0, 0.2)
		await tw.finished
	var err := get_tree().change_scene_to_file(SCENES[scene_key])
	if err != OK:
		push_error("SceneRouter: 场景切换失败 %s -> %s" % [scene_key, error_string(err)])
		payload = {}
		_fade_rect.color.a = 0.0
		_busy = false
		return
	await get_tree().process_frame
	if fade:
		var tw2 := create_tween()
		tw2.tween_property(_fade_rect, "color:a", 0.0, 0.3)
		await tw2.finished
	_busy = false


## 原版公用放大过渡：前 25% 缩到 0.92，随后放大到 cover 全屏并淡出。
func change_to_with_zoom(scene_key: String, target: Control, data := {}, duration := 0.32) -> void:
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
	var shrink_sec := maxf(0.01, duration * 0.25)
	var expand_sec := maxf(0.01, duration - shrink_sec)
	var tween := create_tween()
	tween.tween_property(target, "scale", shrink_scale, shrink_sec) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "scale", end_scale, expand_sec) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(target, "modulate", end_color, expand_sec) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	var err := get_tree().change_scene_to_file(SCENES[scene_key])
	if err != OK:
		push_error("SceneRouter: 场景切换失败 %s -> %s" % [scene_key, error_string(err)])
		payload = {}
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_busy = false
		return
	await get_tree().process_frame
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false


func is_transition_busy() -> bool:
	return _busy


func take_payload() -> Dictionary:
	var data := payload
	payload = {}
	return data
