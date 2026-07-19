class_name ReadyAnim
extends Control
## 原版“准备就绪”分层流程：
## 全黑 → 背景完整出现 → 底层黑幕缓慢加深到 70% → 判定区直出 → 顶部 HUD 下落
## → ARE YOU READY 从左侧进场并停留 → GAME START → 整组从右侧退场。
## 6 张素材不是序列帧：1=底板、2=流动装饰、3/4=READY 前后层、5/6=GO 前后层。

signal finished
signal audio_cue(cue_name: String, timeline_seconds: float)

const VIEW_SIZE := Vector2(1920, 1080)
const TOTAL_DURATION := 8.15

# 背景阶段刻意放慢：先看见完整背景，再把底层黑幕加深到 70%。
const BLACK_HOLD_END := 0.55
const BACKGROUND_REVEAL_END := 1.35
const BACKGROUND_CLEAR_HOLD_END := 1.65
const MASK_SETTLE_END := 2.45

# 判定区直接出现；顶部 HUD 保持满亮度，从屏幕外向下落入。
const RECEPTOR_SHOW := 2.55
const HUD_START := 2.75
const HUD_END := 3.80

# 引导组整体左进右出；READY 和 GO 在组内分阶段播放。
const GUIDE_START := 4.05
const GUIDE_ENTER_END := 4.85
const READY_START := 4.78
const READY_FADE_IN_END := 5.10
const READY_FADE_OUT_START := 6.10
const READY_END := 6.42
const GO_START := 6.38
const GO_FADE_IN_END := 6.68
const GUIDE_EXIT_START := 7.15
const GO_FADE_OUT_START := 7.40
const EXIT_END := 8.15

const TARGET_MASK_ALPHA := 0.70
const BOARD_Y := 420.0
const BOARD_HEIGHT := 240.0
const GUIDE_OFFSCREEN_PADDING := 96.0

var _elapsed := 0.0
var _playing := false
var _ready_sfx_emitted := false
var _guide: Control
var _banner_glow: TextureRect
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
	# 此层只负责 READY/GO 图形；黑幕由 GameplayBackground 与判定区之间的 BackgroundDim 绘制。
	z_index = 1000
	_build_layers()
	visible = false


func _build_layers() -> void:
	_guide = Control.new()
	_guide.name = "Guide"
	_guide.position = Vector2(-VIEW_SIZE.x - GUIDE_OFFSCREEN_PADDING, 0.0)
	_guide.size = VIEW_SIZE
	_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_guide)

	_banner_glow = _texture_layer("BannerGlow", "UI-img/游戏界面/准备就绪/1.png")
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_banner_glow.material = glow_material
	_banner = _texture_layer("Banner", "UI-img/游戏界面/准备就绪/1.png")
	var opaque_banner_material := ShaderMaterial.new()
	opaque_banner_material.shader = load("res://fx/ready_banner_opaque.gdshader") as Shader
	opaque_banner_material.set_shader_parameter("top_color", Color(0.51, 0.31, 0.56, 1.0))
	opaque_banner_material.set_shader_parameter("bottom_color", Color(0.39, 0.20, 0.44, 1.0))
	opaque_banner_material.set_shader_parameter("center_lift", 0.045)
	_banner.material = opaque_banner_material
	_decor_a = _texture_layer("MovingDecorA", "UI-img/游戏界面/准备就绪/2.png")
	_decor_b = _texture_layer("MovingDecorB", "UI-img/游戏界面/准备就绪/2.png")
	var arrow_shader := load("res://fx/ready_banner_arrows.gdshader") as Shader
	var decor_material_a := ShaderMaterial.new()
	decor_material_a.shader = arrow_shader
	decor_material_a.set_shader_parameter("arrow_color", Color(0.68, 0.37, 0.75, 1.0))
	decor_material_a.set_shader_parameter("arrow_highlight", Color(0.86, 0.62, 0.91, 1.0))
	decor_material_a.set_shader_parameter("source_alpha_max", 0.212)
	decor_material_a.set_shader_parameter("opacity", 0.92)
	_decor_a.material = decor_material_a
	var decor_material_b := decor_material_a.duplicate() as ShaderMaterial
	_decor_b.material = decor_material_b
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
	_guide.add_child(view)
	return view


func total_duration() -> float:
	return TOTAL_DURATION


func is_playing() -> bool:
	return _playing


func is_complete() -> bool:
	return _elapsed >= TOTAL_DURATION


func elapsed() -> float:
	return _elapsed


## Gameplay 刚切入但谱面尚未解析完成时固定在第 0 帧，避免 HUD/判定区闪现。
func prime() -> void:
	_elapsed = 0.0
	_playing = false
	_ready_sfx_emitted = false
	visible = true
	_apply_frame()


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
	_ready_sfx_emitted = _elapsed >= READY_START
	visible = _elapsed < TOTAL_DURATION
	_apply_frame()


## 底层黑幕透明度。BackgroundDim 位于背景之上、判定区和 HUD 之下，因此 UI 始终满亮度。
func intro_mask_alpha() -> float:
	if _elapsed <= BLACK_HOLD_END:
		return 1.0
	if _elapsed < BACKGROUND_REVEAL_END:
		var reveal_t := _smootherstep(inverse_lerp(
			BLACK_HOLD_END, BACKGROUND_REVEAL_END, _elapsed))
		return lerpf(1.0, 0.0, reveal_t)
	if _elapsed < BACKGROUND_CLEAR_HOLD_END:
		return 0.0
	if _elapsed < MASK_SETTLE_END:
		var settle_t := _smootherstep(inverse_lerp(
			BACKGROUND_CLEAR_HOLD_END, MASK_SETTLE_END, _elapsed))
		return lerpf(0.0, TARGET_MASK_ALPHA, settle_t)
	return TARGET_MASK_ALPHA


## 判定区到点硬切，不使用透明度插值或缩放。
func receptor_progress() -> float:
	return 1.0 if _elapsed >= RECEPTOR_SHOW else 0.0


## 顶部 HUD 从屏幕外缓慢落入，末段只有很轻的回弹。
func hud_progress() -> float:
	return _ease_out_back_soft(inverse_lerp(HUD_START, HUD_END, _elapsed))


## 右退期间用于把 70% 引导黑幕平滑交还给玩家的正式背景亮度设置。
func exit_progress() -> float:
	return _smoothstep(inverse_lerp(GUIDE_EXIT_START, EXIT_END, _elapsed))


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
	# 原音效约 2.944 秒：在 READY 出字时触发，GAME START 与右退阶段自然同步。
	if emit_audio and not _ready_sfx_emitted \
			and previous < READY_START and _elapsed >= READY_START:
		_ready_sfx_emitted = true
		audio_cue.emit("ready_sequence", READY_START)
	_apply_frame()
	if _elapsed >= TOTAL_DURATION:
		_playing = false
		visible = false
		finished.emit()


func _apply_frame() -> void:
	_apply_guide_motion()
	_apply_guide_layers()


func _apply_guide_motion() -> void:
	var x := -VIEW_SIZE.x - GUIDE_OFFSCREEN_PADDING
	if _elapsed >= GUIDE_START:
		var enter_t := _ease_out_quint(inverse_lerp(GUIDE_START, GUIDE_ENTER_END, _elapsed))
		x = lerpf(-VIEW_SIZE.x - GUIDE_OFFSCREEN_PADDING, 0.0, enter_t)
		# 只留 14px 的柔和过冲，避免此前那种廉价弹跳感。
		if enter_t > 0.72 and enter_t < 1.0:
			var settle_t := inverse_lerp(0.72, 1.0, enter_t)
			x += sin(settle_t * PI) * 14.0
	if _elapsed >= GUIDE_EXIT_START:
		var exit_t := _ease_in_out_cubic(inverse_lerp(GUIDE_EXIT_START, EXIT_END, _elapsed))
		x = lerpf(0.0, VIEW_SIZE.x + GUIDE_OFFSCREEN_PADDING, exit_t)
	_guide.position = Vector2(x, 0.0)
	_guide.visible = _elapsed >= GUIDE_START and _elapsed < EXIT_END


func _apply_guide_layers() -> void:
	var guide_alpha := _smoothstep(inverse_lerp(GUIDE_START, GUIDE_START + 0.24, _elapsed))
	guide_alpha *= 1.0 - _smoothstep(inverse_lerp(GO_FADE_OUT_START, EXIT_END, _elapsed))

	_banner_glow.position = Vector2(-8.0, BOARD_Y - 5.0)
	_banner_glow.size = Vector2(VIEW_SIZE.x + 16.0, BOARD_HEIGHT + 10.0)
	_banner_glow.modulate = Color(0.92, 0.48, 1.0, guide_alpha * 0.10)
	_banner_glow.visible = _guide.visible

	_banner.position = Vector2(0.0, BOARD_Y)
	_banner.size = Vector2(VIEW_SIZE.x, BOARD_HEIGHT)
	# 底板源图本身只有 60% Alpha；专用材质会忽略源图透明度。
	# 这里只保留整组进退场的 Alpha，完全进场后横幅为实心不透明。
	_banner.modulate = Color(1, 1, 1, guide_alpha)
	_banner.visible = _guide.visible

	var decor_size := Vector2(1920.0, 149.0)
	var decor_y := BOARD_Y + (BOARD_HEIGHT - decor_size.y) * 0.5
	var travel := maxf(0.0, _elapsed - GUIDE_START) * 240.0
	var decor_offset := fposmod(travel, decor_size.x)
	_decor_a.position = Vector2(-decor_size.x + decor_offset, decor_y)
	_decor_b.position = Vector2(decor_offset, decor_y)
	for decor in [_decor_a, _decor_b]:
		decor.size = decor_size
		# 箭头专用材质会把原贴图极低的 Alpha 归一化成清晰淡紫色，
		# 节点本身不再额外压暗。
		decor.modulate = Color(1, 1, 1, guide_alpha)
		decor.visible = _guide.visible

	_apply_prompt(
		_ready_back, _ready_front,
		READY_START, READY_FADE_IN_END, READY_FADE_OUT_START, READY_END,
		0.975, 0.008)
	_apply_prompt(
		_go_back, _go_front,
		GO_START, GO_FADE_IN_END, GO_FADE_OUT_START, EXIT_END,
		0.965, 0.012)


func _apply_prompt(back: TextureRect, front: TextureRect, start: float,
		fade_in_end: float, fade_out_start: float, final_end: float,
		start_scale: float, pulse_amount: float) -> void:
	var visible_now := _guide.visible and _elapsed >= start and _elapsed < final_end
	back.visible = visible_now
	front.visible = visible_now
	if not visible_now:
		return

	var fade_in := _ease_out_cubic(inverse_lerp(start, fade_in_end, _elapsed))
	var fade_out := 1.0 - _smoothstep(inverse_lerp(fade_out_start, final_end, _elapsed))
	var alpha := fade_in * fade_out
	var hold_t := clampf(inverse_lerp(fade_in_end, fade_out_start, _elapsed), 0.0, 1.0)
	var scale_value := lerpf(start_scale, 1.0, fade_in)
	scale_value *= 1.0 + sin(hold_t * PI) * pulse_amount

	var native_size := Vector2(1054.0, 178.0)
	if front.texture != null:
		native_size = Vector2(front.texture.get_width(), front.texture.get_height())
	var target_size := native_size * 1.06 * scale_value
	var prompt_pos := Vector2(
		(VIEW_SIZE.x - target_size.x) * 0.5,
		BOARD_Y + (BOARD_HEIGHT - target_size.y) * 0.5)

	back.position = prompt_pos + Vector2(4.0, 2.0)
	back.size = target_size
	back.modulate = Color(0.82, 0.94, 1.0, alpha * 0.76)
	front.position = prompt_pos
	front.size = target_size
	front.modulate = Color(1, 1, 1, alpha)


static func _smoothstep(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _smootherstep(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


static func _ease_out_cubic(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func _ease_out_quint(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 5.0)


static func _ease_in_out_cubic(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5


static func _ease_out_back_soft(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	if x <= 0.0 or x >= 1.0:
		return x
	const C1 := 0.82
	const C3 := C1 + 1.0
	return 1.0 + C3 * pow(x - 1.0, 3.0) + C1 * pow(x - 1.0, 2.0)
