class_name RewardTitleBadge
extends Control
## 纯代码称号徽章。
## 不依赖称号贴图，通过主题、稀有度、轮廓、扫光和细节图元生成完整外观。

var _appearance: Dictionary = {}
var _visual: Dictionary = {}
var _label: Label
var _code_label: Label
var _legacy_glow: TextureRect
var _legacy_art: TextureRect
var _font_size := 15
var _phase := 0.0
var _locked := false
var _animated := false
var _theme := "cyber"
var _rarity := "common"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_ensure_nodes()
	_apply_appearance()


func set_appearance(appearance: Dictionary, font_size := 15) -> void:
	_appearance = appearance.duplicate(true)
	_visual = (_appearance.get("visual", {}) as Dictionary).duplicate(true) \
		if _appearance.get("visual", {}) is Dictionary else {}
	_font_size = font_size
	_rarity = str(_appearance.get("rarity", _visual.get("rarity", "common")))
	_theme = _resolve_theme(str(_visual.get("theme", "")), str(_visual.get("style", "")))
	_animated = bool(_visual.get("animated", _rarity in ["epic", "legendary"]))
	_ensure_nodes()
	_apply_appearance()


func set_locked(value: bool) -> void:
	_locked = value
	_apply_text_theme()
	queue_redraw()


func style_for_test() -> String:
	return str(_visual.get("style", ""))


func theme_for_test() -> String:
	return _theme


func animation_enabled_for_test() -> bool:
	return _animated


func _ensure_nodes() -> void:
	if _legacy_glow == null:
		_legacy_glow = TextureRect.new()
		_legacy_glow.name = "TitleBadgeGlow"
		_legacy_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_legacy_glow.visible = false
		add_child(_legacy_glow)
	if _legacy_art == null:
		_legacy_art = TextureRect.new()
		_legacy_art.name = "TitleBadgeArt"
		_legacy_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_legacy_art.visible = false
		add_child(_legacy_art)
	if _code_label == null:
		_code_label = Label.new()
		_code_label.name = "TitleCode"
		_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_code_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_code_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_code_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_code_label)
	if _label == null:
		_label = Label.new()
		_label.name = "TitleText"
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_label)


func _apply_appearance() -> void:
	var visible_by_data := bool(_visual.get("visible", true))
	var is_default := bool(_appearance.get("is_default", _appearance.is_empty()))
	visible = not is_default and visible_by_data
	if _label == null or _code_label == null:
		return
	_label.text = str(_appearance.get("name", ""))
	var badge_text := str(_visual.get("badge", "")).strip_edges()
	_code_label.text = RewardCatalog.rarity_display_name(_rarity) if badge_text.is_empty() else \
		badge_text.replace("_", " ").to_upper()
	_apply_text_theme()
	_layout_children()
	set_process(_animated and visible)
	queue_redraw()


func _apply_text_theme() -> void:
	if _label == null or _code_label == null:
		return
	var primary := _display_color(_color("primary_color", Color(0.16, 0.91, 1.0)))
	var text_color := _display_color(_color("text_color", Color.WHITE))
	var outline := Color(0.004, 0.008, 0.018, 0.98)
	_label.add_theme_font_size_override("font_size", _font_size)
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_color_override("font_outline_color", outline)
	_label.add_theme_constant_override("outline_size", 3 if _rarity in ["epic", "legendary"] else 2)
	_code_label.add_theme_font_size_override("font_size", maxi(8, _font_size - 6))
	_code_label.add_theme_color_override("font_color", primary.lightened(0.18))
	_code_label.add_theme_color_override("font_outline_color", outline)
	_code_label.add_theme_constant_override("outline_size", 2)


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * float(_visual.get("animation_speed", 0.58)), 1.0)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_children()
		queue_redraw()


func _layout_children() -> void:
	if _label == null or _code_label == null:
		return
	var compact := size.x < 220.0 or size.y < 36.0
	_code_label.visible = not compact
	if compact:
		_label.position = Vector2(14.0, 0.0)
		_label.size = Vector2(maxf(0.0, size.x - 28.0), size.y)
	else:
		var code_width := clampf(size.x * 0.29, 62.0, 92.0)
		_code_label.position = Vector2(12.0, 0.0)
		_code_label.size = Vector2(code_width - 8.0, size.y)
		_label.position = Vector2(code_width, 0.0)
		_label.size = Vector2(maxf(0.0, size.x - code_width - 14.0), size.y)


func _draw() -> void:
	if not visible or size.x < 52.0 or size.y < 20.0:
		return
	var primary := _display_color(_color("primary_color", Color(0.16, 0.91, 1.0)))
	var secondary := _display_color(_color("secondary_color", Color(1.0, 0.24, 0.78)))
	var tertiary := _display_color(_color("tertiary_color", primary.lightened(0.35)))
	var rect := Rect2(Vector2(3.0, 3.0), size - Vector2(6.0, 6.0))
	var cut := clampf(rect.size.y * 0.24, 4.0, 10.0)
	var outline := _octagon(rect, cut)
	_draw_glow(outline, primary, secondary)
	_draw_base(outline, rect, cut, primary, secondary)
	match _theme:
		"gold":
			_draw_gold(rect, primary, secondary, tertiary)
		"ice":
			_draw_ice(rect, primary, secondary)
		"flame":
			_draw_flame(rect, primary, secondary)
		"matrix":
			_draw_matrix(rect, primary, secondary)
		"aurora":
			_draw_aurora(rect, primary, secondary, tertiary)
		"void":
			_draw_void(rect, primary, secondary)
		"sakura":
			_draw_sakura(rect, primary, secondary)
		"industrial":
			_draw_industrial(rect, primary, secondary)
		"speed":
			_draw_speed(rect, primary, secondary)
		_:
			_draw_cyber(rect, primary, secondary)
	_draw_rarity_marks(rect, primary, secondary)


func _draw_glow(points: PackedVector2Array, primary: Color, secondary: Color) -> void:
	if _rarity not in ["rare", "epic", "legendary"]:
		return
	var pulse := 0.78 + sin(_phase * TAU) * 0.12 if _animated else 0.82
	var layers := 3 if _rarity == "legendary" else 2
	for i in range(layers, 0, -1):
		var width := 2.0 + float(i) * 2.3
		var glow_color := primary.lerp(secondary, 0.35)
		glow_color.a = (0.055 + float(i) * 0.025) * pulse
		draw_polyline(_closed(points), glow_color, width, true)


func _draw_base(points: PackedVector2Array, rect: Rect2, cut: float,
		primary: Color, secondary: Color) -> void:
	var dark := _display_color(_color("background_color", Color(0.01, 0.025, 0.055, 0.97)))
	draw_colored_polygon(_offset_points(points, Vector2(1.5, 2.0)), Color(0.0, 0.0, 0.0, 0.62))
	draw_colored_polygon(points, dark)
	var inner := rect.grow(-2.0)
	if inner.size.x > 10.0 and inner.size.y > 10.0:
		draw_colored_polygon(_octagon(inner, maxf(2.0, cut - 2.0)),
			Color(primary.r * 0.10, primary.g * 0.10, primary.b * 0.10, 0.68))
	for i in range(4):
		var y := rect.position.y + 4.0 + float(i) * maxf(2.0, (rect.size.y - 8.0) / 4.0)
		draw_line(Vector2(rect.position.x + cut, y), Vector2(rect.end.x - cut, y),
			Color(secondary.r, secondary.g, secondary.b, 0.035), 1.0, true)
	draw_polyline(_closed(points), Color(primary.r, primary.g, primary.b, 0.94), 1.7, true)
	var accent_y := rect.end.y - 3.0
	draw_line(Vector2(rect.position.x + cut + 3.0, accent_y),
		Vector2(rect.end.x - cut - 3.0, accent_y),
		Color(secondary.r, secondary.g, secondary.b, 0.76), 1.2, true)


func _draw_cyber(rect: Rect2, primary: Color, secondary: Color) -> void:
	var left := rect.position.x + 8.0
	var right := rect.end.x - 8.0
	var mid_y := rect.get_center().y
	for i in 3:
		var x := left + float(i) * 7.0
		draw_line(Vector2(x, rect.position.y + 5.0), Vector2(x + 8.0, rect.end.y - 5.0),
			Color(secondary.r, secondary.g, secondary.b, 0.34 - i * 0.07), 1.4, true)
	for i in 3:
		var x2 := right - float(i) * 7.0
		draw_line(Vector2(x2, rect.position.y + 5.0), Vector2(x2 - 8.0, rect.end.y - 5.0),
			Color(primary.r, primary.g, primary.b, 0.34 - i * 0.07), 1.4, true)
	draw_circle(Vector2(left + 28.0, mid_y), 2.2, secondary)
	draw_circle(Vector2(right - 28.0, mid_y), 2.2, primary)
	if _animated:
		var sweep_x := lerpf(rect.position.x + 18.0, rect.end.x - 18.0, _phase)
		draw_rect(Rect2(Vector2(sweep_x - 5.0, rect.position.y + 4.0),
			Vector2(10.0, rect.size.y - 8.0)), Color(primary.r, primary.g, primary.b, 0.10), true)
		var glitch_y := rect.position.y + 5.0 + fmod(_phase * 91.0, maxf(4.0, rect.size.y - 10.0))
		draw_line(Vector2(rect.position.x + 24.0, glitch_y),
			Vector2(rect.position.x + rect.size.x * 0.42, glitch_y),
			Color(secondary.r, secondary.g, secondary.b, 0.36), 1.0, true)


func _draw_gold(rect: Rect2, primary: Color, secondary: Color, tertiary: Color) -> void:
	var inner := rect.grow(-4.5)
	draw_rect(inner, Color(primary.r, primary.g, primary.b, 0.10), false, 1.0, true)
	var center_y := rect.get_center().y
	for raw_side in [-1.0, 1.0]:
		var side: float = float(raw_side)
		var anchor_x: float = rect.get_center().x + side * (rect.size.x * 0.42)
		var diamond := PackedVector2Array([
			Vector2(anchor_x, center_y - 5.0),
			Vector2(anchor_x + side * 7.0, center_y),
			Vector2(anchor_x, center_y + 5.0),
			Vector2(anchor_x - side * 4.0, center_y),
		])
		draw_colored_polygon(diamond, Color(primary.r, primary.g, primary.b, 0.42))
		draw_polyline(_closed(diamond), tertiary, 1.2, true)
	var crown_x := rect.get_center().x
	var crown_y := rect.position.y + 5.0
	var crown := PackedVector2Array([
		Vector2(crown_x - 12.0, crown_y + 4.0), Vector2(crown_x - 8.0, crown_y - 1.0),
		Vector2(crown_x - 2.0, crown_y + 3.0), Vector2(crown_x + 3.0, crown_y - 2.0),
		Vector2(crown_x + 9.0, crown_y + 4.0),
	])
	draw_polyline(crown, Color(secondary.r, secondary.g, secondary.b, 0.82), 1.3, true)
	if _animated:
		var shine_x := lerpf(rect.position.x - 20.0, rect.end.x + 20.0, _phase)
		var shine := PackedVector2Array([
			Vector2(shine_x - 10.0, rect.end.y - 4.0), Vector2(shine_x - 3.0, rect.position.y + 4.0),
			Vector2(shine_x + 5.0, rect.position.y + 4.0), Vector2(shine_x - 2.0, rect.end.y - 4.0),
		])
		draw_colored_polygon(shine, Color(tertiary.r, tertiary.g, tertiary.b, 0.14))


func _draw_ice(rect: Rect2, primary: Color, secondary: Color) -> void:
	for raw_side in [-1.0, 1.0]:
		var side: float = float(raw_side)
		var edge_x: float = rect.position.x + 10.0 if side < 0.0 else rect.end.x - 10.0
		for i in 3:
			var y := rect.position.y + 7.0 + i * 7.0
			var shard := PackedVector2Array([
				Vector2(edge_x, y), Vector2(edge_x + side * 8.0, y + 3.0),
				Vector2(edge_x + side * 2.0, y + 6.0),
			])
			draw_colored_polygon(shard, Color(primary.r, primary.g, primary.b, 0.24 + i * 0.07))
			draw_polyline(_closed(shard), Color(secondary.r, secondary.g, secondary.b, 0.58), 1.0, true)
	if _animated:
		var frost := 0.12 + (sin(_phase * TAU) + 1.0) * 0.04
		draw_rect(rect.grow(-4.0), Color(primary.r, primary.g, primary.b, frost), false, 1.0, true)


func _draw_flame(rect: Rect2, primary: Color, secondary: Color) -> void:
	var base_y := rect.end.y - 4.0
	var count := maxi(5, int(rect.size.x / 34.0))
	for i in count:
		var t := float(i) / maxf(1.0, float(count - 1))
		var x := lerpf(rect.position.x + 16.0, rect.end.x - 16.0, t)
		var wave := sin(t * TAU * 2.0 + _phase * TAU)
		var height := 4.0 + (wave + 1.0) * 2.2
		var flame := PackedVector2Array([
			Vector2(x - 5.0, base_y), Vector2(x, base_y - height), Vector2(x + 5.0, base_y),
		])
		draw_colored_polygon(flame, Color(primary.r, primary.g, primary.b, 0.22))
		draw_polyline(flame, Color(secondary.r, secondary.g, secondary.b, 0.64), 1.0, true)


func _draw_matrix(rect: Rect2, primary: Color, secondary: Color) -> void:
	var columns := maxi(6, int(rect.size.x / 28.0))
	for i in columns:
		var x := rect.position.x + 10.0 + float(i) * (rect.size.x - 20.0) / maxf(1.0, float(columns - 1))
		var h := 3.0 + float((i * 7) % 11)
		draw_line(Vector2(x, rect.position.y + 5.0), Vector2(x, rect.position.y + 5.0 + h),
			Color(primary.r, primary.g, primary.b, 0.20), 1.0, true)
	if _animated:
		var scan_y := lerpf(rect.position.y + 4.0, rect.end.y - 4.0, _phase)
		draw_line(Vector2(rect.position.x + 10.0, scan_y), Vector2(rect.end.x - 10.0, scan_y),
			Color(secondary.r, secondary.g, secondary.b, 0.42), 1.2, true)


func _draw_aurora(rect: Rect2, primary: Color, secondary: Color, tertiary: Color) -> void:
	var y := rect.position.y + 5.0
	var span := rect.size.x - 24.0
	var colors := [primary, secondary, tertiary]
	for i in 6:
		var x0 := rect.position.x + 12.0 + span * float(i) / 6.0
		var x1 := rect.position.x + 12.0 + span * float(i + 1) / 6.0
		var color: Color = colors[i % colors.size()]
		draw_line(Vector2(x0, y + sin(i + _phase * TAU) * 1.5),
			Vector2(x1, y + sin(i + 1 + _phase * TAU) * 1.5),
			Color(color.r, color.g, color.b, 0.68), 1.6, true)
	for i in 5:
		var px := rect.position.x + 18.0 + fmod(float(i * 41) + _phase * 37.0, maxf(20.0, rect.size.x - 36.0))
		var py := rect.position.y + 9.0 + float((i * 13) % maxi(4, int(rect.size.y - 18.0)))
		draw_circle(Vector2(px, py), 1.2 + float(i % 2), Color(tertiary.r, tertiary.g, tertiary.b, 0.52))


func _draw_void(rect: Rect2, primary: Color, secondary: Color) -> void:
	var center := rect.get_center()
	for i in 7:
		var x := rect.position.x + 14.0 + float((i * 37) % maxi(20, int(rect.size.x - 28.0)))
		var y := rect.position.y + 7.0 + float((i * 17) % maxi(6, int(rect.size.y - 14.0)))
		var pulse := 0.28 + (sin(_phase * TAU + i) + 1.0) * 0.10 if _animated else 0.34
		draw_circle(Vector2(x, y), 1.0 + float(i % 3) * 0.45,
			Color(secondary.r, secondary.g, secondary.b, pulse))
	draw_arc(center, minf(rect.size.x * 0.12, rect.size.y * 0.42), 0.0, TAU, 24,
		Color(primary.r, primary.g, primary.b, 0.16), 1.0, true)


func _draw_sakura(rect: Rect2, primary: Color, secondary: Color) -> void:
	for i in 5:
		var t := fmod(float(i) * 0.21 + _phase * 0.22, 1.0) if _animated else float(i) / 5.0
		var x := lerpf(rect.position.x + 14.0, rect.end.x - 14.0, t)
		var y := rect.position.y + 7.0 + float((i * 9) % maxi(5, int(rect.size.y - 14.0)))
		var petal := PackedVector2Array([
			Vector2(x, y - 2.8), Vector2(x + 3.5, y), Vector2(x, y + 2.8), Vector2(x - 2.0, y),
		])
		draw_colored_polygon(petal, Color(primary.r, primary.g, primary.b, 0.30))
		draw_polyline(_closed(petal), Color(secondary.r, secondary.g, secondary.b, 0.55), 0.8, true)


func _draw_industrial(rect: Rect2, primary: Color, secondary: Color) -> void:
	var corners: Array[Vector2] = [
		Vector2(rect.position.x + 10.0, rect.position.y + 8.0),
		Vector2(rect.end.x - 10.0, rect.position.y + 8.0),
		Vector2(rect.position.x + 10.0, rect.end.y - 8.0),
		Vector2(rect.end.x - 10.0, rect.end.y - 8.0),
	]
	for corner: Vector2 in corners:
		draw_circle(corner, 2.0, Color(primary.r, primary.g, primary.b, 0.74))
	for i in 4:
		var x := rect.position.x + 28.0 + i * 8.0
		draw_line(Vector2(x, rect.end.y - 7.0), Vector2(x + 5.0, rect.end.y - 3.0),
			Color(secondary.r, secondary.g, secondary.b, 0.46), 1.2, true)


func _draw_speed(rect: Rect2, primary: Color, secondary: Color) -> void:
	for raw_side in [-1.0, 1.0]:
		var side: float = float(raw_side)
		var base_x: float = rect.position.x + 13.0 if side < 0.0 else rect.end.x - 13.0
		for i in 3:
			var offset := float(i) * 7.0
			var x := base_x + side * offset
			var chevron := PackedVector2Array([
				Vector2(x - side * 4.0, rect.get_center().y - 6.0),
				Vector2(x + side * 2.0, rect.get_center().y),
				Vector2(x - side * 4.0, rect.get_center().y + 6.0),
			])
			draw_polyline(chevron, Color(primary.r, primary.g, primary.b, 0.62 - i * 0.12), 1.5, true)
	if _animated:
		var speed_x := lerpf(rect.position.x + 30.0, rect.end.x - 30.0, _phase)
		draw_line(Vector2(speed_x - 15.0, rect.position.y + 6.0),
			Vector2(speed_x + 5.0, rect.position.y + 6.0),
			Color(secondary.r, secondary.g, secondary.b, 0.54), 1.3, true)


func _draw_rarity_marks(rect: Rect2, primary: Color, secondary: Color) -> void:
	var count: int = int({"common": 1, "rare": 2, "epic": 3, "legendary": 4}.get(_rarity, 1))
	var start_x := rect.end.x - 12.0 - float(count - 1) * 5.0
	for i in count:
		var color := primary.lerp(secondary, float(i) / maxf(1.0, float(count - 1)))
		draw_circle(Vector2(start_x + i * 5.0, rect.position.y + 6.0), 1.4,
			Color(color.r, color.g, color.b, 0.86))


func _resolve_theme(explicit_theme: String, style: String) -> String:
	if not explicit_theme.is_empty():
		return explicit_theme
	var key := style.to_lower()
	if key.contains("gold") or key.contains("legend") or key.contains("lord") \
			or key.contains("sovereign") or key.contains("rhythm_god") or key.contains("combo_chip"):
		return "gold"
	if key.contains("ice") or key.contains("cryo") or key.contains("frost"):
		return "ice"
	if key.contains("battle") or key.contains("flame") or key.contains("ember"):
		return "flame"
	if key.contains("matrix") or key.contains("data"):
		return "matrix"
	if key.contains("aurora") or key.contains("prism") or key.contains("mint"):
		return "aurora"
	if key.contains("night") or key.contains("galaxy") or key.contains("star") or key.contains("void"):
		return "void"
	if key.contains("sakura") or key.contains("petal"):
		return "sakura"
	if key.contains("training") or key.contains("worker") or key.contains("industrial"):
		return "industrial"
	if key.contains("racing") or key.contains("speed") or key.contains("runner"):
		return "speed"
	return "cyber"


func _color(key: String, fallback: Color) -> Color:
	var value = _visual.get(key, fallback)
	if value is Color:
		return value
	var text := str(value)
	return Color.html(text) if Color.html_is_valid(text) else fallback


func _display_color(color: Color) -> Color:
	if not _locked:
		return color
	var luminance := clampf(color.get_luminance() * 0.68, 0.20, 0.72)
	return Color(luminance, luminance, luminance, color.a * 0.86)


func _octagon(rect: Rect2, cut: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(rect.position.x + cut, rect.position.y),
		Vector2(rect.end.x - cut, rect.position.y),
		Vector2(rect.end.x, rect.position.y + cut),
		Vector2(rect.end.x, rect.end.y - cut),
		Vector2(rect.end.x - cut, rect.end.y),
		Vector2(rect.position.x + cut, rect.end.y),
		Vector2(rect.position.x, rect.end.y - cut),
		Vector2(rect.position.x, rect.position.y + cut),
	])


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array(points)
	if not points.is_empty():
		result.append(points[0])
	return result


func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point + offset)
	return result
