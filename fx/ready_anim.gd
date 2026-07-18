class_name ReadyAnim
extends Control
## 原版“准备就绪”完整分层动画。
## 6 张素材不是序列帧：1=底板、2=流动装饰、3/4=READY 前后层、5/6=GO 前后层。

signal finished
signal audio_cue(cue_name: String, timeline_seconds: float)

const VIEW_SIZE := Vector2(1920, 1080)
const TOTAL_DURATION := 4.57
const BLACK_END := 0.09
const BACKGROUND_END := 0.39
const MASK_END := 0.47
const RECEPTOR_END := 0.67
const HUD_START := 0.67
const HUD_END := 1.22
const GUIDE_START := 1.22
const GUIDE_ENTER_END := 1.72
const BOARD_ENTER_END := 1.52
const READY_START := 1.72
const READY_END := 2.62
const GO_START := 3.02
const GO_END := 4.52
const EXIT_END := 4.57

var _elapsed := 0.0
var _playing := false
var _ready_sfx_emitted := false
var _dim: ColorRect
var _guide: Control
var _banner: TextureRect
var _decor_a: TextureRect
var _decor_b: TextureRect
var _ready_front: TextureRect
var _ready_back: TextureRect
var _go_front: TextureRect
var _go_back: TextureRect


func _ready() -> void:
	name = "ReadyAnim"
	position = Vector2.ZERO
	size = VIEW_SIZE
	custom_minimum_size = VIEW_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 1000
	_build_layers()
	visible = false


func _build_layers() -> void:
	_dim = ColorRect.new()
	_dim.name = "SceneDim"
	_dim.position = Vector2.ZERO
	_dim.size = VIEW_SIZE
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_guide = Control.new()
	_guide.name = "Guide"
	_guide.position = Vector2.ZERO
	_guide.size = VIEW_SIZE
	_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_guide)

	_banner = _texture_layer("Banner", "UI-img/游戏界面/准备就绪/1.png")
	_decor_a = _texture_layer("MovingDecorA", "UI-img/游戏界面/准备就绪/2.png")
	_decor_b = _texture_layer("MovingDecorB", "UI-img/游戏界面/准备就绪/2.png")
	_ready_back = _texture_layer("ReadyBack", "UI-img/游戏界面/准备就绪/4.png")
	_ready_front = _texture_layer("ReadyFront", "UI-img/游戏界面/准备就绪/3.png")
	_go_back = _texture_layer("GoBack", "UI-img/游戏界面/准备就绪/6.png")
	_go_front = _texture_layer("GoFront", "UI-img/游戏界面/准备就绪/5.png")


func _texture_layer(node_name: String, path: String) -> TextureRect:
	var view := TextureRect.new()
	view.name = node_name
	view.texture = AssetLoader.tex(path)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.pivot_offset = Vector2.ZERO
	_guide.add_child(view)
	return view


func total_duration() -> float:
	return TOTAL_DURATION


func is_playing() -> bool:
	return _playing


func play(_legacy_duration := TOTAL_DURATION) -> void:
	_elapsed = 0.0
	_playing = true
	_ready_sfx_emitted = false
	visible = true
	_apply_frame()


func stop() -> void:
	_playing = false
	_ready_sfx_emitted = true
	visible = false


func seek_for_test(seconds: float) -> void:
	_elapsed = clampf(seconds, 0.0, TOTAL_DURATION)
	_playing = false
	_ready_sfx_emitted = _elapsed >= GUIDE_START
	visible = _elapsed < TOTAL_DURATION
	_apply_frame()


func elapsed() -> float:
	return _elapsed


func receptor_progress() -> float:
	return _smoothstep(inverse_lerp(MASK_END, RECEPTOR_END, _elapsed))


func hud_progress() -> float:
	return _ease_out_cubic(inverse_lerp(HUD_START, HUD_END, _elapsed))


func _process(delta: float) -> void:
	if not _playing:
		return
	_advance_to(_elapsed + delta, true)


## 契约测试复用正式推进逻辑，不依赖真实帧率和系统时钟。
func advance_for_test(seconds: float) -> void:
	if not _playing:
		return
	_advance_to(seconds, true)


func _advance_to(seconds: float, emit_audio: bool) -> void:
	var previous := _elapsed
	_elapsed = clampf(seconds, previous, TOTAL_DURATION)
	if emit_audio and not _ready_sfx_emitted \
			and previous < GUIDE_START and _elapsed >= GUIDE_START:
		_ready_sfx_emitted = true
		audio_cue.emit("ready_sequence", GUIDE_START)
	if _elapsed >= TOTAL_DURATION:
		_apply_frame()
		_playing = false
		visible = false
		finished.emit()
		return
	_apply_frame()


func _apply_frame() -> void:
	# 黑场退去、背景出现后维持原版深色蒙版；引导出场时同时退场。
	var black_alpha := 1.0 - _smoothstep(inverse_lerp(BLACK_END, BACKGROUND_END, _elapsed))
	var mask_alpha := _smoothstep(inverse_lerp(BACKGROUND_END, MASK_END, _elapsed)) * (224.0 / 255.0)
	var exit_alpha := 1.0 - _smoothstep(inverse_lerp(GO_END, EXIT_END, _elapsed))
	_dim.color = Color(0, 0, 0, maxf(black_alpha, mask_alpha * exit_alpha))

	var board_enter := _ease_out_cubic(inverse_lerp(GUIDE_START, BOARD_ENTER_END, _elapsed))
	var board_exit := _smoothstep(inverse_lerp(GO_END, EXIT_END, _elapsed))
	var board_h := 240.0 * 1.09
	var board_w := VIEW_SIZE.x * (1.0 + board_exit * 0.035)
	var board_x := lerpf(-board_w, 0.0, board_enter) + lerpf(0.0, VIEW_SIZE.x + board_w * 0.08, board_exit)
	board_x -= (board_w - VIEW_SIZE.x) * 0.5
	var board_y := VIEW_SIZE.y * 0.5 - board_h * 0.5
	_banner.position = Vector2(board_x, board_y)
	_banner.size = Vector2(board_w, board_h)
	_banner.modulate.a = 1.0 - board_exit
	_banner.visible = board_enter > 0.0 and board_exit < 1.0

	var decor_h := board_h * 0.64
	var decor_w := VIEW_SIZE.x * decor_h / 149.0
	var decor_y := board_y + (board_h - decor_h) * 0.5
	var travel := maxf(0.0, _elapsed - GUIDE_START) * 350.0
	var decor_offset := fmod(travel, decor_w)
	for pair in [[_decor_a, -decor_w + decor_offset], [_decor_b, decor_offset]]:
		var decor: TextureRect = pair[0]
		decor.position = Vector2(board_x + float(pair[1]), decor_y)
		decor.size = Vector2(decor_w, decor_h)
		decor.modulate.a = 1.0 - board_exit
		decor.visible = _banner.visible

	_apply_prompt(_ready_back, _ready_front, READY_START, READY_END, GO_START,
		board_y, board_h, 0.82, true)
	_apply_prompt(_go_back, _go_front, GO_START, GO_END, EXIT_END,
		board_y, board_h, 0.82, false)


func _apply_prompt(back: TextureRect, front: TextureRect, start: float, active_end: float,
		final_end: float, board_y: float, board_h: float, height_ratio: float,
		is_ready: bool) -> void:
	var visible_now := _elapsed >= start and _elapsed < final_end
	back.visible = visible_now
	front.visible = visible_now
	if not visible_now:
		return
	var enter_span := (active_end - start) * (0.78 if is_ready else 0.32)
	var enter_t := _smoothstep(inverse_lerp(start, start + enter_span, _elapsed))
	var leave_t := _smoothstep(inverse_lerp(active_end, final_end, _elapsed))
	var base_scale := lerpf(0.96 if is_ready else 0.84, 1.0, enter_t)
	if not is_ready:
		base_scale = 1.0 + sin(enter_t * PI) * 0.05
	var stretch := lerpf(0.92 if is_ready else 1.0, 1.16 if is_ready else 1.05, enter_t)
	stretch = lerpf(stretch, 0.80 if is_ready else 1.12, leave_t)
	base_scale = lerpf(base_scale, 0.62 if is_ready else 1.0, leave_t)
	var target_h := board_h * height_ratio * base_scale
	var source := front.texture
	var ratio := 5.8
	if source != null and source.get_height() > 0:
		ratio = float(source.get_width()) / float(source.get_height())
	var target_w := minf(VIEW_SIZE.x * 0.84, target_h * ratio * stretch)
	var pos := Vector2((VIEW_SIZE.x - target_w) * 0.5, board_y + (board_h - target_h) * 0.5)
	var alpha := enter_t * (1.0 - leave_t)
	for layer in [back, front]:
		layer.position = pos
		layer.size = Vector2(target_w, target_h)
		layer.modulate.a = alpha * (0.86 if layer == back else 1.0)


static func _smoothstep(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _ease_out_cubic(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)
