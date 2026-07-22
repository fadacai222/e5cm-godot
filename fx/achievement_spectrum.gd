class_name AchievementSpectrum
extends Node2D
## ALL COMBO / ALL PERFECT 专用 50 段假频谱。
## 数值模型逐项对应旧版 ui/结算前成就动画.py 与 ui/圆环频谱叠加.py。

const BARS := 50
const RISE := 0.84
const FALL := 0.72

var inner_radius := 96.0
var max_length := 70.0
var line_width := 3.0
var ring_width := 2.0

var _time := 0.0
var _main_color := Color8(233, 146, 32)
var _palette: Array[Color] = []
var _levels := PackedFloat32Array()
var _phase1 := PackedFloat32Array()
var _phase2 := PackedFloat32Array()
var _phase3 := PackedFloat32Array()
var _gate_phase := PackedFloat32Array()


func _ready() -> void:
	_ensure_arrays()
	_rebuild_palette()
	queue_redraw()


func configure(main_color: Color, target_inner_radius: float, target_max_length: float,
		target_line_width: float, target_ring_width: float) -> void:
	_main_color = main_color
	inner_radius = maxf(18.0, target_inner_radius)
	max_length = maxf(20.0, target_max_length)
	line_width = maxf(1.0, target_line_width)
	ring_width = maxf(1.0, target_ring_width)
	_ensure_arrays()
	_rebuild_palette()
	queue_redraw()


func set_animation_time(seconds: float) -> void:
	_time = maxf(0.0, seconds)
	_ensure_arrays()
	var generated := _generate_fake_levels(_time)
	for i in BARS:
		if generated[i] >= _levels[i]:
			_levels[i] = lerpf(_levels[i], generated[i], RISE)
		else:
			_levels[i] *= FALL
	queue_redraw()


func reset_levels() -> void:
	_ensure_arrays()
	for i in BARS:
		_levels[i] = 0.0
	queue_redraw()


func _ensure_arrays() -> void:
	if _levels.size() == BARS:
		return
	_levels.resize(BARS)
	_phase1.resize(BARS)
	_phase2.resize(BARS)
	_phase3.resize(BARS)
	_gate_phase.resize(BARS)
	for i in BARS:
		_levels[i] = 0.0
		_phase1[i] = float(i) * 0.73 + 0.15
		_phase2[i] = float(i) * 1.17 + 0.37
		_phase3[i] = float(i) * 0.41 + 0.93
		_gate_phase[i] = float(i) * 0.57 + 0.22


func _rebuild_palette() -> void:
	_palette = [
		_main_color.darkened(0.24),
		_main_color,
		_main_color.lightened(0.22),
		_main_color.lightened(0.40),
	]


func _generate_fake_levels(seconds: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(BARS)
	for i in BARS:
		var wave1 := 0.5 + 0.5 * sin(seconds * 6.3 + _phase1[i])
		var wave2 := 0.5 + 0.5 * sin(seconds * 10.7 + _phase2[i])
		var wave3 := 0.5 + 0.5 * sin(seconds * 3.8 + _phase3[i])
		var gate := 0.25 + 0.75 * pow(
			0.5 + 0.5 * sin(seconds * 4.9 - float(i) * 0.53 + _gate_phase[i]), 2.1)
		var value := ((wave1 * 0.18) + (wave2 * 0.57) + (wave3 * 0.25)) * gate
		value = 0.06 + minf(1.0, pow(maxf(0.0, value), 1.45) * 1.10)
		result[i] = clampf(value, 0.0, 1.0)
	return result


func _sample_color(angle_ratio: float, amplitude: float) -> Color:
	if _palette.size() < 2:
		_rebuild_palette()
	var wrapped := fposmod(angle_ratio, 1.0)
	var segment := wrapped * float(_palette.size())
	var index := int(floor(segment)) % _palette.size()
	var next_index := (index + 1) % _palette.size()
	var color: Color = _palette[index].lerp(_palette[next_index], segment - floor(segment))
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


func _draw() -> void:
	if _levels.size() != BARS:
		return
	for i in BARS:
		var angle := TAU * float(i) / float(BARS)
		var direction := Vector2(cos(angle), sin(angle))
		var amplitude := _levels[i]
		var jagged := 0.86 + 0.30 * absf(sin(float(i) * 2.173))
		var length := pow(amplitude, 0.62) * max_length * jagged
		var from := direction * inner_radius
		var to := direction * (inner_radius + length)
		draw_line(from, to, _sample_color(float(i) / float(BARS), amplitude),
			line_width, true)
	draw_arc(Vector2.ZERO, inner_radius, 0.0, TAU, BARS,
		_main_color.lightened(0.20), ring_width, true)
	draw_arc(Vector2.ZERO, inner_radius + 6.0, 0.0, TAU, BARS,
		_main_color.darkened(0.18), 1.0, true)


func state_for_test() -> Dictionary:
	var peak := 0.0
	for level in _levels:
		peak = maxf(peak, level)
	return {
		"bars": BARS,
		"inner_radius": inner_radius,
		"max_length": max_length,
		"line_width": line_width,
		"main_color": _main_color,
		"peak": peak,
	}
