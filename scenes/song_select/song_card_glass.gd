class_name SongCardGlass
extends Control
## 原版缩略图悬停/踏板选中玻璃效果。
## layer_mode=0 画卡片下方底光；layer_mode=1 画卡片上方玻璃高光。

@export_enum("UNDERLAY", "OVERLAY") var layer_mode := 1
var _selected := false
var _hovered := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false


func set_state(selected: bool, hovered: bool) -> void:
	_selected = selected
	_hovered = hovered
	queue_redraw()


func _palette() -> Dictionary:
	if _selected:
		return {
			"shadow": Color8(255, 192, 96, 42),
			"rim": Color8(255, 226, 168, 92),
			"accent": Color8(255, 214, 138, 188),
			"sheen": Color8(255, 250, 236, 56),
		}
	return {
		"shadow": Color8(20, 36, 64, 34),
		"rim": Color8(150, 220, 255, 84),
		"accent": Color8(118, 232, 255, 182),
		"sheen": Color8(255, 255, 255, 48),
	}


func _style_box(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _draw() -> void:
	if not _selected and not _hovered:
		return
	var colors := _palette()
	if layer_mode == 0:
		_draw_underlay(colors)
	else:
		_draw_overlay(colors)


func _draw_underlay(colors: Dictionary) -> void:
	# Pygame 原版：frame.inflate(18,16).move(0,8)，因此上边不外扩、左右9、底部16。
	var shadow_rect := Rect2(-9.0, 0.0, size.x + 18.0, size.y + 16.0)
	var radius := maxi(22, int(minf(shadow_rect.size.x, shadow_rect.size.y) * 0.18))
	draw_style_box(_style_box(colors.shadow, colors.rim, 2, radius), shadow_rect)


func _draw_overlay(colors: Dictionary) -> void:
	var inner := Rect2(4.0, 4.0, maxf(1.0, size.x - 8.0), maxf(1.0, size.y - 8.0))
	var radius := maxi(18, int(minf(inner.size.x, inner.size.y) * 0.12))
	draw_style_box(_style_box(Color.TRANSPARENT, colors.rim, 2, radius), inner)

	var top_bar_width := maxf(28.0, inner.size.x * 0.28)
	draw_style_box(_style_box(colors.accent, Color.TRANSPARENT, 0, 4),
		Rect2(inner.position + Vector2(12, 8),
			Vector2(minf(top_bar_width, maxf(1.0, inner.size.x - 24.0)), 4)))

	var sheen := PackedVector2Array([
		inner.position,
		inner.position + Vector2(inner.size.x * 0.56, 0),
		inner.position + Vector2(inner.size.x * 0.28, inner.size.y * 0.34),
		inner.position + Vector2(0, inner.size.y * 0.34),
	])
	draw_colored_polygon(sheen, colors.sheen)

	var corner_length := maxf(18.0, minf(inner.size.x, inner.size.y) * 0.12)
	var top_left := inner.position + Vector2(8, 10)
	var bottom_right := inner.end - Vector2(8, 10)
	draw_line(top_left, top_left + Vector2(corner_length, 0), colors.accent, 3.0, true)
	draw_line(top_left, top_left + Vector2(0, corner_length), colors.accent, 3.0, true)
	draw_line(bottom_right, bottom_right - Vector2(corner_length, 0), colors.accent, 3.0, true)
	draw_line(bottom_right, bottom_right - Vector2(0, corner_length), colors.accent, 3.0, true)
