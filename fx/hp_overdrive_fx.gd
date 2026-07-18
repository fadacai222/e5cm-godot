class_name HpOverdriveFx
extends Node2D
## 暴走血条独立加法能量层：外溢光束、电弧和高速火花。
## 主贴图 Shader 负责内部循环，本层负责超出血条矩形的能量感。

@export var spark_count := 38
@export var overflow_padding := 32.0
@export var ribbon_count := 6

var _bar_rect := Rect2(345, 26, 1249, 67)
var _phase := 0.0
var _pulse := 0.5
var _paused := false


func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	z_index = 59
	visible = false


func configure(rect: Rect2) -> void:
	_bar_rect = rect
	position = rect.position - Vector2(overflow_padding, overflow_padding)
	queue_redraw()


func set_paused(value: bool) -> void:
	_paused = value


func set_energy_state(active: bool, phase_pixels: float, pulse_value: float,
		wave_x := 0.0) -> void:
	visible = active
	if not active:
		return
	position = _bar_rect.position + Vector2(wave_x, 0) \
		- Vector2(overflow_padding, overflow_padding)
	if not _paused:
		_phase = phase_pixels
		_pulse = clampf(pulse_value, 0.0, 1.0)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var pad := overflow_padding
	var width := _bar_rect.size.x
	var height := _bar_rect.size.y
	var left := pad
	var top := pad
	var right := left + width
	var bottom := top + height
	var cyan := Color(0.08, 0.92, 1.0, 0.30 + _pulse * 0.22)
	var pink := Color(1.0, 0.08, 0.48, 0.26 + _pulse * 0.20)
	var white_hot := Color(0.82, 0.98, 1.0, 0.22 + _pulse * 0.20)

	# 血条上下边缘的电离光晕；多层细线比一条粗模糊边更有速度感。
	for i in 5:
		var inset := float(i) * 2.0
		var alpha_scale := 1.0 - float(i) * 0.16
		draw_line(Vector2(left - 10.0, top - inset), Vector2(right + 10.0, top - inset),
			Color(cyan.r, cyan.g, cyan.b, cyan.a * alpha_scale), 1.0 + float(i) * 0.7)
		draw_line(Vector2(left - 10.0, bottom + inset), Vector2(right + 10.0, bottom + inset),
			Color(pink.r, pink.g, pink.b, pink.a * alpha_scale), 1.0 + float(i) * 0.7)

	# 向右高速循环的能量丝带，青粉交错并带白热核心。
	for i in ribbon_count:
		var fi := float(i)
		var base_y := top + height * (0.16 + 0.68 * fposmod(fi * 0.417, 1.0))
		var shift := fposmod(_phase * (1.25 + fi * 0.09) + fi * 211.0,
			width + 360.0) - 180.0
		var length := 140.0 + fposmod(fi * 97.0, 190.0)
		var start := Vector2(left + shift - length, base_y + sin(_phase * 0.025 + fi) * 4.0)
		var finish := Vector2(left + shift, base_y)
		var ribbon_color := cyan if i % 2 == 0 else pink
		draw_line(start, finish, Color(ribbon_color.r, ribbon_color.g, ribbon_color.b,
			ribbon_color.a * 0.46), 5.0 + _pulse * 2.0)
		draw_line(start + Vector2(length * 0.32, 0), finish,
			white_hot, 1.2 + _pulse * 1.2)

	# 确定性火花：数量固定、相位随歌曲推进，暂停时完全冻结。
	for i in spark_count:
		var fi := float(i)
		var x := fposmod(_phase * (1.8 + fposmod(fi * 0.173, 0.9)) + fi * 83.17,
			width + pad * 2.0) - pad
		var edge_selector := fposmod(fi * 0.6180339, 1.0)
		var y := top - 5.0 - fposmod(fi * 7.91, pad * 0.72) \
			if edge_selector < 0.5 else bottom + 5.0 + fposmod(fi * 5.73, pad * 0.72)
		var streak := 8.0 + fposmod(fi * 13.7, 27.0)
		var spark_color := cyan if i % 3 != 0 else pink
		draw_line(Vector2(left + x - streak, y), Vector2(left + x, y),
			Color(spark_color.r, spark_color.g, spark_color.b, 0.34 + _pulse * 0.40),
			0.8 + fposmod(fi * 0.31, 1.1))
		draw_circle(Vector2(left + x, y), 0.7 + fposmod(fi * 0.19, 0.9),
			Color(0.92, 1.0, 1.0, 0.56 + _pulse * 0.35))

	# 头尾脉冲爆点，让能量不是一张平移贴图，而像持续灌入血条。
	var flare_radius := 10.0 + _pulse * 12.0
	for point in [Vector2(left, top + height * 0.5), Vector2(right, top + height * 0.5)]:
		draw_circle(point, flare_radius * 1.8, Color(0.08, 0.78, 1.0, 0.08))
		draw_circle(point, flare_radius, Color(1.0, 0.12, 0.50, 0.13))
		draw_circle(point, 2.0 + _pulse * 2.0, white_hot)
