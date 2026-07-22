class_name SpectrumRing
extends Node2D
## 圆环频谱 —— 对应旧 ui/圆环频谱叠加.py。
## 默认读取 GameplaySpectrum 总线上的真实音乐频谱；分析器不可用时才启用轻量兜底动画。
## Stage 场景可绑定 board.png 的 alpha 轮廓，让每根频谱线从唱片盘真实边缘起跳。

const BARS := 200
# 画面仍保留 200 根线，但 FFT 只采 64 个频段并插值；频谱最多 60Hz 更新。
# 原实现每个 SpectrumRing 每渲染帧做 200 次频段查询 + 400 次 draw_line，
# 高刷下主要卡 CPU/Canvas 提交，5090 再强也无法替主线程完成这些调用。
const ANALYZER_BANDS := 64
const UPDATE_HZ := 60.0
const UPDATE_INTERVAL := 1.0 / UPDATE_HZ
const FREQ_LO := 55.0
const FREQ_HI := 9500.0
const RISE := 0.78
const FALL := 0.84
const SPECTRUM_BUS := "GameplaySpectrum"
const ANALYZER_DB_FLOOR := -72.0
const ANALYZER_DB_CEILING := -12.0
const ANALYZER_RETRY_SEC := 0.35
const SILENCE_FALLBACK_SEC := 0.28
const PALETTE := [
	Color8(0, 255, 246),     # 高亮青
	Color8(42, 132, 255),    # 电光蓝
	Color8(126, 58, 255),    # 清晰紫
	Color8(255, 32, 174),    # 玫红
	Color8(255, 118, 20),    # 金橙收尾，拉开相邻色相
]
const GLOW_PALETTE := [
	Color8(0, 174, 255),
	Color8(76, 54, 255),
	Color8(222, 24, 255),
	Color8(255, 26, 102),
	Color8(255, 58, 12),
]

var inner_radius := 110.0
var max_len := 150.0
var rotate_speed := 0.0
var line_width := 2.0
var glow_width := 5.0

var _levels := PackedFloat32Array()
var _edge_radii := PackedFloat32Array()
var _instance: AudioEffectSpectrumAnalyzerInstance
var _source_player: AudioStreamPlayer
var _angle := 0.0
var _edge_rotation := 0.0
var _analyzer_retry := 0.0
var _silence_elapsed := 0.0
var _bass_peak := 0.0
var _update_accumulator := UPDATE_INTERVAL
var paused := false
var enabled := true


func _ready() -> void:
	_levels.resize(BARS)
	visible = enabled
	set_process(enabled)
	if enabled:
		_ensure_analyzer()


func bind_audio_player(player: AudioStreamPlayer) -> void:
	_source_player = player
	if enabled:
		_ensure_analyzer()
	if _source_player != null:
		_source_player.bus = SPECTRUM_BUS if enabled else "Master"


func set_edge_texture(texture: Texture2D, target_size: Vector2) -> void:
	_edge_radii = PackedFloat32Array()
	if texture == null:
		queue_redraw()
		return
	var image := texture.get_image()
	if image == null or image.is_empty():
		queue_redraw()
		return
	var width := maxi(1, roundi(target_size.x))
	var height := maxi(1, roundi(target_size.y))
	if image.get_width() != width or image.get_height() != height:
		image.resize(width, height, Image.INTERPOLATE_LANCZOS)
	var center := Vector2((float(width) - 1.0) * 0.5, (float(height) - 1.0) * 0.5)
	var max_radius := ceili(Vector2(width, height).length())
	_edge_radii.resize(BARS)
	for i in BARS:
		var angle := TAU * float(i) / float(BARS) - PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var last_radius := 0.0
		for radius in max_radius + 1:
			var point := center + direction * float(radius)
			var x := roundi(point.x)
			var y := roundi(point.y)
			if x < 0 or x >= width or y < 0 or y >= height:
				break
			if image.get_pixel(x, y).a >= 72.0 / 255.0:
				last_radius = float(radius)
		_edge_radii[i] = maxf(6.0, last_radius)
	_smooth_edge_radii()
	queue_redraw()


func set_edge_rotation(radians: float) -> void:
	# _process() 的 60Hz 重绘会带上最新轮廓角度；这里不再每个渲染帧额外排队重绘。
	_edge_rotation = radians


func has_edge_profile() -> bool:
	return _edge_radii.size() == BARS


func set_paused(value: bool) -> void:
	paused = value


func set_enabled(value: bool) -> void:
	enabled = value
	visible = value
	set_process(value)
	_update_accumulator = UPDATE_INTERVAL
	if _source_player != null:
		# 真正绕开 FFT 总线；仅隐藏节点仍会让音频线程继续做频谱分析。
		_source_player.bus = SPECTRUM_BUS if value else "Master"
	if value:
		_ensure_analyzer()
		queue_redraw()
	else:
		_bass_peak = 0.0
		for i in _levels.size():
			_levels[i] = 0.0


func is_enabled_for_test() -> bool:
	return enabled and visible and is_processing()


func bass_energy_for_visuals() -> float:
	return clampf(_bass_peak, 0.0, 1.0)


func _ensure_analyzer() -> void:
	var bus := AudioServer.get_bus_index(SPECTRUM_BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(bus, SPECTRUM_BUS)
		AudioServer.set_bus_send(bus, "Master")
	var effect_index := -1
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectSpectrumAnalyzer:
			effect_index = i
			break
	if effect_index < 0:
		var analyzer := AudioEffectSpectrumAnalyzer.new()
		analyzer.buffer_length = 0.12
		analyzer.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_2048
		AudioServer.add_bus_effect(bus, analyzer)
		effect_index = AudioServer.get_bus_effect_count(bus) - 1
	_instance = AudioServer.get_bus_effect_instance(bus, effect_index) as AudioEffectSpectrumAnalyzerInstance
	if _source_player != null:
		_source_player.bus = SPECTRUM_BUS


func _process(delta: float) -> void:
	if paused or not enabled:
		return
	_update_accumulator += delta
	if _update_accumulator < UPDATE_INTERVAL:
		return
	var sample_delta := _update_accumulator
	_update_accumulator = fmod(_update_accumulator, UPDATE_INTERVAL)
	_angle += rotate_speed * sample_delta
	if _instance == null:
		_analyzer_retry += sample_delta
		if _analyzer_retry >= ANALYZER_RETRY_SEC:
			_analyzer_retry = 0.0
			_ensure_analyzer()
	var measured := PackedFloat32Array()
	measured.resize(BARS)
	var peak := 0.0
	if _instance != null:
		var sampled := PackedFloat32Array()
		sampled.resize(ANALYZER_BANDS)
		for i in ANALYZER_BANDS:
			var f0 := FREQ_LO * pow(FREQ_HI / FREQ_LO, float(i) / float(ANALYZER_BANDS))
			var f1 := FREQ_LO * pow(FREQ_HI / FREQ_LO, float(i + 1) / float(ANALYZER_BANDS))
			var magnitude := _instance.get_magnitude_for_frequency_range(
				f0, f1, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
			var db := linear_to_db(maxf(magnitude, 0.0000001))
			var normalized := clampf((db - ANALYZER_DB_FLOOR) /
				(ANALYZER_DB_CEILING - ANALYZER_DB_FLOOR), 0.0, 1.0)
			sampled[i] = pow(normalized, 0.78)
			peak = maxf(peak, sampled[i])
		for i in BARS:
			var sample_pos := float(i) * float(ANALYZER_BANDS - 1) / float(BARS - 1)
			var left := int(floor(sample_pos))
			var right := mini(left + 1, ANALYZER_BANDS - 1)
			measured[i] = lerpf(sampled[left], sampled[right], sample_pos - float(left))
	var source_is_playing := _source_player != null and _source_player.playing
	if source_is_playing and peak < 0.015:
		_silence_elapsed += delta
	else:
		_silence_elapsed = 0.0
	if _instance == null or (source_is_playing and _silence_elapsed >= SILENCE_FALLBACK_SEC):
		measured = _fallback_levels(_source_player.get_playback_position() if source_is_playing else _angle)
	var bass_sample := 0.0
	for i in mini(42, BARS):
		bass_sample = maxf(bass_sample, measured[i])
	if bass_sample >= _bass_peak:
		_bass_peak = lerpf(_bass_peak, bass_sample, 0.88)
	else:
		_bass_peak = lerpf(_bass_peak, bass_sample, 0.16)
	for i in BARS:
		var next_level := measured[i]
		if next_level >= _levels[i]:
			# 原版公式：78% 使用新能量；旧实现误写成 22%，导致鼓点几乎推不起来。
			_levels[i] = lerpf(_levels[i], next_level, RISE)
		else:
			_levels[i] *= FALL
	queue_redraw()


func _fallback_levels(seconds: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(BARS)
	var beat := pow(maxf(0.0, sin(seconds * TAU * 2.05)), 8.0)
	for i in BARS:
		var phase := TAU * float(i) / float(BARS)
		var wave := 0.5 + 0.5 * sin(phase * 2.0 + seconds * 2.4)
		var detail := 0.5 + 0.5 * sin(phase * 7.0 - seconds * 5.1)
		var low_weight := 1.0 - clampf(float(i) / float(BARS) * 1.4, 0.0, 1.0)
		result[i] = clampf(0.05 + wave * 0.10 + detail * 0.06 + beat * low_weight * 0.55, 0.0, 1.0)
	return result


func _smooth_edge_radii() -> void:
	if _edge_radii.size() != BARS:
		return
	var source := _edge_radii.duplicate()
	for i in BARS:
		var previous := source[(i - 1 + BARS) % BARS]
		var current := source[i]
		var next := source[(i + 1) % BARS]
		_edge_radii[i] = (previous + current * 2.0 + next) * 0.25


func _edge_radius(index: int) -> float:
	if _edge_radii.size() != BARS:
		return inner_radius
	var offset := _edge_rotation / TAU * float(BARS)
	var sample := fposmod(float(index) - offset, float(BARS))
	var left := int(floor(sample)) % BARS
	var right := (left + 1) % BARS
	return lerpf(_edge_radii[left], _edge_radii[right], sample - floor(sample))


func _draw() -> void:
	var outer_contour := PackedVector2Array()
	var inner_contour := PackedVector2Array()
	for i in BARS:
		var angle := _angle + TAU * float(i) / float(BARS) - PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		var start_radius := maxf(8.0, _edge_radius(i) - maxf(1.5, line_width))
		var value := _levels[i]
		var bottom_weight := 0.12 + 0.88 * pow(clampf((sin(angle) + 1.0) * 0.5, 0.0, 1.0), 1.75)
		var jagged := 0.86 + 0.30 * absf(sin(float(i) * 2.173))
		var low_band_weight := pow(1.0 - clampf(float(i) / 72.0, 0.0, 1.0), 1.7)
		var beat_lift := pow(_bass_peak, 1.35) * low_band_weight * 0.48
		var length := (pow(value, 0.62) + beat_lift) * max_len * bottom_weight * jagged
		var from := direction * start_radius
		var to := direction * (start_radius + length)
		var color := sample_color_for_test(float(i) / float(BARS), value)
		var glow := sample_glow_color(float(i) / float(BARS), value)
		glow.a = 0.18 + value * 0.24
		draw_line(from, to, glow, glow_width, true)
		draw_line(from, to, color, line_width, true)
		if has_edge_profile():
			outer_contour.append(direction * start_radius)
			inner_contour.append(direction * maxf(4.0, start_radius - 2.0))
	if has_edge_profile() and outer_contour.size() >= 3:
		outer_contour.append(outer_contour[0])
		inner_contour.append(inner_contour[0])
		draw_polyline(outer_contour, Color8(0, 246, 255), 2.0, true)
		draw_polyline(inner_contour, Color8(212, 36, 255), 1.0, true)
	else:
		draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, BARS, Color8(0, 246, 255), 2.0, true)
		draw_arc(Vector2.ZERO, inner_radius + 6.0, 0.0, TAU, BARS, Color8(212, 36, 255), 1.0, true)


func sample_glow_color(angle_ratio: float, amplitude: float) -> Color:
	var wrapped := fposmod(angle_ratio, 1.0)
	var segment := wrapped * float(GLOW_PALETTE.size())
	var index := int(floor(segment)) % GLOW_PALETTE.size()
	var next_index := (index + 1) % GLOW_PALETTE.size()
	var color: Color = GLOW_PALETTE[index].lerp(GLOW_PALETTE[next_index], segment - floor(segment))
	var level := clampf(amplitude, 0.0, 1.0)
	color = color.lerp(Color.WHITE, pow(level, 2.2) * 0.28)
	color.a = 1.0
	return color


func sample_color_for_test(angle_ratio: float, amplitude: float) -> Color:
	var wrapped := fposmod(angle_ratio, 1.0)
	var segment := wrapped * float(PALETTE.size())
	var index := int(floor(segment)) % PALETTE.size()
	var next_index := (index + 1) % PALETTE.size()
	var color: Color = PALETTE[index].lerp(PALETTE[next_index], segment - floor(segment))
	var level := clampf(amplitude, 0.0, 1.0)
	var brightness := 0.58 + 0.78 * level
	color.r = clampf(color.r * brightness, 0.0, 1.0)
	color.g = clampf(color.g * brightness, 0.0, 1.0)
	color.b = clampf(color.b * brightness, 0.0, 1.0)
	var white_lift := 86.0 / 255.0 * pow(level, 1.7)
	color.r = clampf(color.r + white_lift, 0.0, 1.0)
	color.g = clampf(color.g + white_lift, 0.0, 1.0)
	color.b = clampf(color.b + white_lift, 0.0, 1.0)
	color.a = 1.0
	return color
