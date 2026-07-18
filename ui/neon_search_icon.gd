class_name NeonSearchIcon
extends Control
## 选歌底栏专用搜索图标：运行时矢量绘制，避免复用“重选模式”图片。

var pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	pulse = fposmod(pulse + delta, TAU)
	queue_redraw()


func _draw() -> void:
	var center := size * Vector2(0.43, 0.42)
	var radius := minf(size.x, size.y) * 0.22
	var glow_alpha := 0.22 + 0.08 * sin(pulse * 2.0)
	var cyan := Color(0.10, 0.94, 1.0, 1.0)
	var pink := Color(1.0, 0.14, 0.72, 1.0)
	for width in [12.0, 8.0, 5.0]:
		var glow := cyan.lerp(pink, 0.28)
		glow.a = glow_alpha * (13.0 - width) / 8.0
		draw_arc(center, radius, 0.0, TAU, 48, glow, width, true)
	var segments := 48
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var color := cyan.lerp(pink, float(i) / float(segments))
		draw_line(center + Vector2(cos(a0), sin(a0)) * radius,
			center + Vector2(cos(a1), sin(a1)) * radius, color, 4.0, true)
	var handle_start := center + Vector2(radius * 0.70, radius * 0.70)
	var handle_end := center + Vector2(radius * 1.55, radius * 1.55)
	draw_line(handle_start, handle_end, Color(0.84, 0.96, 1.0), 13.0, true)
	draw_line(handle_start, handle_end, pink, 5.0, true)
	var sparkle := center + Vector2(-radius * 0.55, -radius * 0.55)
	var sparkle_size := radius * (0.22 + 0.04 * sin(pulse * 3.0))
	draw_line(sparkle - Vector2(sparkle_size, 0), sparkle + Vector2(sparkle_size, 0), Color.WHITE, 2.4, true)
	draw_line(sparkle - Vector2(0, sparkle_size), sparkle + Vector2(0, sparkle_size), Color.WHITE, 2.4, true)
