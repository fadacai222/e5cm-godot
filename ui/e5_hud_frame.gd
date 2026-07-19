class_name E5HudFrame
extends Control
## 原版街机 HUD 切角框：深蓝半透明底、双主色结构线、内框、扫描线与角标。
## 只负责绘制，不接管输入；外部内容节点叠在本节点上方。

@export var fill_color := Color(0.018, 0.075, 0.16, 0.94)
@export var header_color := Color(0.035, 0.18, 0.30, 0.78)
@export var border_color := Color(0.16, 0.91, 1.0, 0.92)
@export var secondary_color := Color(1.0, 0.22, 0.76, 0.88)
@export var inner_color := Color(0.42, 0.78, 1.0, 0.30)
@export var scanline_color := Color(0.28, 0.70, 1.0, 0.055)
@export_range(0.0, 48.0, 1.0) var cut_size := 18.0
@export_range(0.0, 120.0, 1.0) var header_height := 0.0
@export_range(1.0, 6.0, 0.5) var border_width := 2.0
@export_range(4.0, 24.0, 1.0) var scanline_gap := 8.0
@export var show_scanlines := true
@export var show_corner_marks := true
@export var show_side_ticks := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _cut_points(rect: Rect2, cut: float) -> PackedVector2Array:
	var c := clampf(cut, 0.0, minf(rect.size.x, rect.size.y) * 0.24)
	var x := rect.position.x
	var y := rect.position.y
	var right := rect.end.x
	var bottom := rect.end.y
	return PackedVector2Array([
		Vector2(x + c, y), Vector2(right - c, y),
		Vector2(right, y + c), Vector2(right, bottom - c),
		Vector2(right - c, bottom), Vector2(x + c, bottom),
		Vector2(x, bottom - c), Vector2(x, y + c),
		Vector2(x + c, y),
	])


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 4.0 or h < 4.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var outer := _cut_points(rect, cut_size)
	var fill_points := outer.duplicate()
	fill_points.resize(maxi(0, fill_points.size() - 1))
	draw_colored_polygon(fill_points, fill_color)

	if header_height > 0.0:
		var hh := minf(header_height, h - 4.0)
		var hc := minf(cut_size, hh * 0.48)
		var header_points := PackedVector2Array([
			Vector2(cut_size, 0), Vector2(w - cut_size, 0),
			Vector2(w, cut_size), Vector2(w, hh),
			Vector2(w * 0.64, hh), Vector2(w * 0.60, hh + minf(12.0, h - hh)),
			Vector2(cut_size * 0.35, hh + minf(12.0, h - hh)),
			Vector2(0, hh), Vector2(0, hc),
		])
		draw_colored_polygon(header_points, header_color)
		draw_line(Vector2(0, hh), Vector2(w * 0.60, hh), border_color, 1.5, true)
		draw_line(Vector2(w * 0.60, hh), Vector2(w * 0.64, hh + minf(12.0, h - hh)),
			secondary_color, 2.0, true)

	if show_scanlines:
		var y := maxf(3.0, header_height + 4.0)
		var gap := maxf(4.0, scanline_gap)
		while y < h - 3.0:
			draw_line(Vector2(2.0, y), Vector2(w - 2.0, y), scanline_color, 1.0)
			y += gap

	draw_polyline(outer, border_color, border_width, true)
	if w > 18.0 and h > 18.0:
		var inner_rect := Rect2(Vector2(5.0, 5.0), size - Vector2(10.0, 10.0))
		draw_polyline(_cut_points(inner_rect, maxf(2.0, cut_size - 4.0)), inner_color, 1.0, true)

	# 原版截图中的“青色主定位 + 洋红辅助定位”结构线。
	var top_left_end := clampf(w * 0.42, cut_size + 20.0, w - cut_size)
	var top_right_start := clampf(w * 0.68, cut_size, w - cut_size - 20.0)
	draw_line(Vector2(cut_size, 0), Vector2(top_left_end, 0), border_color, 3.0, true)
	draw_line(Vector2(top_right_start, 0), Vector2(w - cut_size, 0), secondary_color, 2.5, true)
	draw_line(Vector2(cut_size, h), Vector2(w * 0.34, h), secondary_color, 2.0, true)
	draw_line(Vector2(w * 0.60, h), Vector2(w - cut_size, h), border_color, 3.0, true)

	if show_corner_marks:
		var mark := minf(24.0, maxf(10.0, cut_size + 4.0))
		var inset := 10.0
		# 左上 / 右下使用青色，右上 / 左下使用洋红，形成玩家侧色彩平衡。
		draw_line(Vector2(inset, cut_size + 5.0), Vector2(inset, cut_size + mark), border_color, 2.0)
		draw_line(Vector2(cut_size + 5.0, inset), Vector2(cut_size + mark, inset), border_color, 2.0)
		draw_line(Vector2(w - inset, cut_size + 5.0), Vector2(w - inset, cut_size + mark), secondary_color, 2.0)
		draw_line(Vector2(w - cut_size - 5.0, inset), Vector2(w - cut_size - mark, inset), secondary_color, 2.0)
		draw_line(Vector2(inset, h - cut_size - 5.0), Vector2(inset, h - cut_size - mark), secondary_color, 2.0)
		draw_line(Vector2(cut_size + 5.0, h - inset), Vector2(cut_size + mark, h - inset), secondary_color, 2.0)
		draw_line(Vector2(w - inset, h - cut_size - 5.0), Vector2(w - inset, h - cut_size - mark), border_color, 2.0)
		draw_line(Vector2(w - cut_size - 5.0, h - inset), Vector2(w - cut_size - mark, h - inset), border_color, 2.0)

	if show_side_ticks and h > 90.0:
		for ratio in [0.28, 0.50, 0.72]:
			var ty := h * float(ratio)
			draw_line(Vector2(0, ty), Vector2(12, ty), border_color, 2.0)
			draw_line(Vector2(w - 12, ty), Vector2(w, ty), secondary_color, 2.0)
