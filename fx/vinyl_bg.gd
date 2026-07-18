class_name VinylBg
extends Node2D
## 原版动态背景“唱片”的 Godot 复刻。
## 状态严格由 Combo 0/50/100/150 四档驱动：
## 1 唱片与粒子；2 唱片机/中心条/侧线；3 宇航员；4 描边宇航员与框线。

const VIEW_SIZE := Vector2(1920, 1080)
const RECORD_SIZE := 419.0
const RECORD_SPEED_DEG := 360.0 / 6.4
const MACHINE_WIDTH := 430.0
const ASTRONAUT_LEFT_WIDTH := 228.0
const ASTRONAUT_RIGHT_WIDTH := 216.0
const FRAME_WIDTH := 1500.0
const FOOT_WIDTH := 1920.0
const STATE_TRANSITION_SEC := 0.90
# 满档超过 300 个细粒子；速度和寿命足以从中心扩散到 1920×1080 屏幕外。
const PARTICLE_TARGETS := [144, 192, 252, 324]
const PARTICLE_SPEED_MIN := [105.0, 125.0, 145.0, 170.0]
const PARTICLE_SPEED_MAX := [310.0, 360.0, 420.0, 490.0]
const PARTICLE_LIFE_MIN := [2.0, 2.1, 2.2, 2.3]
const PARTICLE_LIFE_MAX := [3.5, 3.7, 3.9, 4.1]
const PARTICLE_ACCEL_MAX := [42.0, 50.0, 58.0, 68.0]
const PARTICLE_CORE_MIN := 0.55
const PARTICLE_CORE_MAX := 1.85
const SIDE_WIDTHS := [640.0, 264.0, 146.0, 310.0, 150.0]
const SIDE_Y := [-214.0, -104.0, 0.0, 114.0, 228.0]
const SIDE_PERIODS := [6.8, 5.1, 4.4, 5.8, 4.9]
const SIDE_DELAYS := [3.8, 1.7, 0.9, 2.4, 2.1]
const SIDE_TRAVEL := [780.0, 520.0, 360.0, 560.0, 420.0]

var cover_tex: Texture2D
var paused := false
var _time := 0.0
var _combo := 0
var _state := 1
var _state_from := 1
var _state_transition := 1.0
var _pulse := 0.0
var _background: TextureRect
var _record: Sprite2D
var _record_glow: Sprite2D
var _foot: TextureRect
var _machine_top: TextureRect
var _machine_bottom: TextureRect
var _astronaut_left: TextureRect
var _astronaut_right: TextureRect
var _frame: TextureRect
var _center_bar_left: TextureRect
var _center_bar_right: TextureRect
var _side_left: Array[TextureRect] = []
var _side_right: Array[TextureRect] = []


func setup(cover_path: String) -> void:
	cover_tex = AssetLoader.tex(cover_path)
	_build_background()
	_build_side_lines()
	_build_rig()
	_build_astronauts()
	_build_frame_and_foot()
	_apply_motion()
	queue_redraw()


func _build_background() -> void:
	_background = TextureRect.new()
	_background.name = "VinylBackground"
	_background.texture = AssetLoader.tex("UI-img/动态背景/唱片/素材/背景.png")
	_background.position = -VIEW_SIZE * 0.5
	_background.size = VIEW_SIZE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.z_index = -30
	add_child(_background)


func _build_side_lines() -> void:
	_side_left.clear()
	_side_right.clear()
	var files := ["矩形长.png", "矩形短.png", "矩形最短.png", "矩形短.png", "矩形最短.png"]
	for i in files.size():
		var left := _texture_layer("TechLineLeft%d" % i, files[i], Vector2(SIDE_WIDTHS[i], 12), -13)
		var right := _texture_layer("TechLineRight%d" % i, files[i], Vector2(SIDE_WIDTHS[i], 12), -13)
		left.visible = false
		right.visible = false
		_side_left.append(left)
		_side_right.append(right)


func _build_rig() -> void:
	var line_tex := AssetLoader.tex("UI-img/动态背景/唱片/素材/矩形长.png")
	_center_bar_left = _texture_layer("CenterBarLeft", "矩形长.png", Vector2(1480, 14), -11)
	_center_bar_right = _texture_layer("CenterBarRight", "矩形长.png", Vector2(1480, 14), -11)
	_center_bar_left.texture = line_tex
	_center_bar_right.texture = line_tex
	_center_bar_left.position = Vector2(-RECORD_SIZE * 0.5 - 1480.0, -7.0)
	_center_bar_right.position = Vector2(RECORD_SIZE * 0.5, -7.0)
	_center_bar_left.visible = false
	_center_bar_right.visible = false

	_machine_top = _texture_layer("MachineTop", "唱片机-上.png", _size_for_width("唱片机-上.png", MACHINE_WIDTH), -9)
	_machine_bottom = _texture_layer("MachineBottom", "唱片机-下.png", _size_for_width("唱片机-下.png", MACHINE_WIDTH), -9)
	_machine_top.visible = false
	_machine_bottom.visible = false

	_record_glow = Sprite2D.new()
	_record_glow.name = "RecordGlow"
	_record_glow.texture = AssetLoader.tex("UI-img/动态背景/唱片/素材/唱片.png")
	_record_glow.modulate = Color(1.0, 0.12, 0.12, 0.16)
	_record_glow.z_index = -8
	_record_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_record_glow)

	_record = Sprite2D.new()
	_record.name = "Record"
	_record.texture = AssetLoader.tex("UI-img/动态背景/唱片/素材/唱片.png")
	_record.z_index = -7
	# 不挂模糊 Shader，不使用 mipmap 拉糊；只做一次线性缩放并保持素材原色。
	_record.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_record)


func _build_astronauts() -> void:
	_astronaut_left = _texture_layer("AstronautLeft", "宇航员左侧.png",
		_size_for_width("宇航员左侧.png", ASTRONAUT_LEFT_WIDTH), -5)
	_astronaut_right = _texture_layer("AstronautRight", "宇航员右侧.png",
		_size_for_width("宇航员右侧.png", ASTRONAUT_RIGHT_WIDTH), -5)
	_astronaut_left.visible = false
	_astronaut_right.visible = false


func _build_frame_and_foot() -> void:
	_frame = _texture_layer("VinylFrame", "框线.png", _size_for_width("框线.png", FRAME_WIDTH), -6)
	_frame.visible = false
	_foot = _texture_layer("FootDecoration", "foot.png", _size_for_width("foot.png", FOOT_WIDTH), -3)
	# foot 是横跨底边的舞台底座，必须完整覆盖 1920 设计宽度。
	_foot.stretch_mode = TextureRect.STRETCH_SCALE
	_foot.position = Vector2(-VIEW_SIZE.x * 0.5, VIEW_SIZE.y * 0.5 - _foot.size.y)


func _size_for_width(file_name: String, width: float) -> Vector2:
	var texture := AssetLoader.tex("UI-img/动态背景/唱片/素材/%s" % file_name)
	if texture == null or texture.get_width() <= 0:
		return Vector2(width, width)
	return Vector2(width, width * float(texture.get_height()) / float(texture.get_width()))


func _texture_layer(node_name: String, file_name: String, target_size: Vector2, layer: int) -> TextureRect:
	var view := TextureRect.new()
	view.name = node_name
	view.texture = AssetLoader.tex("UI-img/动态背景/唱片/素材/%s" % file_name)
	view.size = target_size
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.z_index = layer
	add_child(view)
	return view


func on_combo(combo: int) -> void:
	var next_combo := maxi(0, combo)
	var next_state := _state_for_combo(next_combo)
	if next_state != _state:
		_state_from = _state
		_state = next_state
		_state_transition = 0.0
		_pulse = 1.0
	_combo = next_combo


func _state_for_combo(combo: int) -> int:
	if combo >= 150:
		return 4
	if combo >= 100:
		return 3
	if combo >= 50:
		return 2
	return 1


func state_for_test() -> int:
	return _state


func particle_profile_for_test(state: int) -> Dictionary:
	var index := clampi(state - 1, 0, 3)
	var life_max: float = float(PARTICLE_LIFE_MAX[index])
	var speed_max: float = float(PARTICLE_SPEED_MAX[index])
	var accel_max: float = float(PARTICLE_ACCEL_MAX[index])
	return {
		"count": int(PARTICLE_TARGETS[index]),
		"max_distance": speed_max * life_max + 0.5 * accel_max * life_max * life_max,
		"max_core_size": PARTICLE_CORE_MAX + 0.42,
		"life_min": float(PARTICLE_LIFE_MIN[index]),
		"life_max": life_max,
	}


func set_paused(value: bool) -> void:
	paused = value


func seek_for_test(seconds: float) -> void:
	_time = maxf(0.0, seconds)
	_apply_motion()
	queue_redraw()


func _process(delta: float) -> void:
	if paused:
		return
	_time += delta
	_pulse = maxf(0.0, _pulse - delta * 1.9)
	_state_transition = minf(1.0, _state_transition + delta / STATE_TRANSITION_SEC)
	_apply_motion()
	queue_redraw()


func _ease_out(value: float) -> float:
	var x := 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - x * x * x


func _layer_mix(required_state: int) -> float:
	var from_value := 1.0 if _state_from >= required_state else 0.0
	var to_value := 1.0 if _state >= required_state else 0.0
	return lerpf(from_value, to_value, _ease_out(_state_transition))


func _apply_motion() -> void:
	var record_scale := RECORD_SIZE / float(maxi(1, _record.texture.get_width())) if _record != null and _record.texture != null else 1.0
	var pulse_scale := 1.0 + 0.055 * _pulse
	if _record != null:
		_record.rotation = deg_to_rad(fmod(_time * RECORD_SPEED_DEG, 360.0))
		_record.scale = Vector2.ONE * record_scale * pulse_scale
		_record.position = Vector2.ZERO
	if _record_glow != null:
		_record_glow.rotation = _record.rotation
		_record_glow.scale = Vector2.ONE * record_scale * (1.055 + 0.08 * _pulse)
		_record_glow.modulate.a = 0.10 + 0.10 * (0.5 + 0.5 * sin(_time * 2.25)) + 0.16 * _pulse

	var machine_mix := _layer_mix(2)
	var machine_y := lerpf(38.0, RECORD_SIZE * 0.5 - 4.0, machine_mix)
	for view in [_machine_top, _machine_bottom, _center_bar_left, _center_bar_right]:
		view.visible = machine_mix > 0.001
		view.modulate.a = machine_mix * 0.96
	_machine_top.position = Vector2(-_machine_top.size.x * 0.5, -machine_y - _machine_top.size.y * 0.5)
	_machine_bottom.position = Vector2(-_machine_bottom.size.x * 0.5, machine_y - _machine_bottom.size.y * 0.5)
	_center_bar_left.scale.x = maxf(0.08, machine_mix)
	_center_bar_right.scale.x = maxf(0.08, machine_mix)

	for i in _side_left.size():
		var left := _side_left[i]
		var right := _side_right[i]
		left.visible = machine_mix > 0.001
		right.visible = machine_mix > 0.001
		var phase := fposmod((_time + SIDE_DELAYS[i]) / SIDE_PERIODS[i], 1.0)
		var travel: float = float(SIDE_TRAVEL[i])
		var alpha: float = machine_mix * sin(phase * PI)
		left.modulate.a = alpha
		right.modulate.a = alpha
		left.position = Vector2(-RECORD_SIZE * 0.5 - 18.0 - SIDE_WIDTHS[i] - phase * travel,
			SIDE_Y[i] - left.size.y * 0.5)
		right.position = Vector2(RECORD_SIZE * 0.5 + 18.0 + phase * travel,
			SIDE_Y[i] - right.size.y * 0.5)

	var astronaut_mix := _layer_mix(3)
	var left_center_x := -RECORD_SIZE * 0.5 - ASTRONAUT_LEFT_WIDTH + 26.0 + ASTRONAUT_LEFT_WIDTH * 0.5
	var right_center_x := RECORD_SIZE * 0.5 + ASTRONAUT_RIGHT_WIDTH - 24.0 - ASTRONAUT_RIGHT_WIDTH * 0.5
	var float_y := sin(_time * TAU / 6.8) * 7.0
	_astronaut_left.visible = astronaut_mix > 0.001
	_astronaut_right.visible = astronaut_mix > 0.001
	_astronaut_left.modulate.a = astronaut_mix
	_astronaut_right.modulate.a = astronaut_mix
	_astronaut_left.position = Vector2(left_center_x - _astronaut_left.size.x * 0.5 - (1.0 - astronaut_mix) * 28.0,
		-_astronaut_left.size.y * 0.5 + float_y)
	_astronaut_right.position = Vector2(right_center_x - _astronaut_right.size.x * 0.5 + (1.0 - astronaut_mix) * 28.0,
		-_astronaut_right.size.y * 0.5 - float_y)
	var astronaut_scale := lerpf(0.90, 1.0, astronaut_mix)
	_astronaut_left.scale = Vector2.ONE * astronaut_scale
	_astronaut_right.scale = Vector2.ONE * astronaut_scale
	var outlined := _state >= 4 and _state_transition > 0.45
	_astronaut_left.texture = AssetLoader.tex("UI-img/动态背景/唱片/素材/%s" %
		("宇航员左侧-带描边.png" if outlined else "宇航员左侧.png"))
	_astronaut_right.texture = AssetLoader.tex("UI-img/动态背景/唱片/素材/%s" %
		("宇航员右侧-带描边.png" if outlined else "宇航员右侧.png"))

	var frame_mix := _layer_mix(4)
	_frame.visible = frame_mix > 0.001
	_frame.position = -_frame.size * 0.5
	_frame.pivot_offset = _frame.size * 0.5
	_frame.modulate.a = frame_mix * (0.72 + 0.28 * (0.5 + 0.5 * sin(_time * TAU / 4.1)))
	_frame.scale = Vector2.ONE * lerpf(0.986, 1.0, frame_mix)


func _draw() -> void:
	# 原版左右角持续有红色光焰；使用多层半透明圆保持清晰，不给唱片素材套模糊。
	var flame_pulse := 0.72 + 0.28 * (0.5 + 0.5 * sin(_time * 1.9))
	for radius_variant in [420.0, 300.0, 190.0]:
		var radius: float = float(radius_variant)
		var alpha: float = flame_pulse * (0.018 + (420.0 - radius) / 420.0 * 0.025)
		draw_circle(Vector2(-940, -520), radius, Color(1.0, 0.08, 0.08, alpha))
		draw_circle(Vector2(940, 520), radius, Color(1.0, 0.08, 0.08, alpha))

	var state_index := clampi(_state - 1, 0, 3)
	var target_count: int = int(PARTICLE_TARGETS[state_index])
	var speed_min: float = float(PARTICLE_SPEED_MIN[state_index])
	var speed_max: float = float(PARTICLE_SPEED_MAX[state_index])
	var life_min: float = float(PARTICLE_LIFE_MIN[state_index])
	var life_max: float = float(PARTICLE_LIFE_MAX[state_index])
	var accel_max: float = float(PARTICLE_ACCEL_MAX[state_index])
	for i in target_count:
		var fi := float(i)
		var seed := fposmod(fi * 0.61803398875 + sin(fi * 1.73) * 0.17, 1.0)
		var angle := fposmod(fi * 2.399963 + sin(fi * 0.17) * 0.21, TAU)
		var speed := lerpf(speed_min, speed_max, seed)
		var life := lerpf(life_min, life_max, fposmod(fi * 0.371, 1.0))
		var age := fposmod(_time + fi * 0.043, life)
		var acceleration := lerpf(24.0, accel_max, fposmod(fi * 0.713, 1.0))
		var distance := speed * age + 0.5 * acceleration * age * age
		var direction := Vector2(cos(angle), sin(angle))
		# 轻微切向偏移让扩散像高速旋转甩出的星屑，而不是僵硬的放射圆。
		var tangent := Vector2(-direction.y, direction.x)
		var point := direction * distance + tangent * sin(age * 4.7 + fi) * (5.0 + age * 6.0)
		var progress := age / life
		var spawn_alpha := smoothstep(0.0, 0.08, progress)
		var alpha := clampf(spawn_alpha * (1.0 - progress) \
			* (0.78 + sin(age * 13.0 + fi) * 0.16), 0.0, 1.0)
		var size := lerpf(PARTICLE_CORE_MIN, PARTICLE_CORE_MAX,
			fposmod(fi * 0.237, 1.0)) + progress * 0.42
		var color_mix := 0.5 + 0.5 * sin(fi * 0.91 + _time * 0.7)
		var particle_color := Color(0.48, 0.92, 1.0).lerp(Color(1.0, 0.36, 0.74), color_mix)
		draw_circle(point, size + 1.4 + progress * 0.7,
			Color(particle_color.r, particle_color.g, particle_color.b, alpha * 0.14))
		draw_circle(point, size, Color(particle_color.r, particle_color.g, particle_color.b, alpha))
