class_name RewardProfileCard
extends Control
## 纯代码玩家卡背景：按奖励主题绘制切角卡面、结构纹理与环绕流光。

var _visual: Dictionary = {}
var _phase := 0.0
var _animated := false
var _locked := false
var _performance_mode := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = true
	_refresh_performance_mode()
	_update_animation_state()
	queue_redraw()


func set_appearance(appearance: Dictionary) -> void:
	_visual = (appearance.get("visual", {}) as Dictionary).duplicate(true)
	if not _visual.has("rarity"):
		_visual["rarity"] = str(appearance.get("rarity", "common"))
	visible = bool(_visual.get("visible", true))
	_refresh_performance_mode()
	_update_animation_state()
	queue_redraw()


func set_locked(locked: bool) -> void:
	_locked = locked
	queue_redraw()


func set_performance_mode(enabled: bool) -> void:
	_performance_mode = enabled
	_update_animation_state()
	queue_redraw()


func _refresh_performance_mode() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var settings_store := tree.root.get_node_or_null("SettingsStore") if tree != null else null
	_performance_mode = bool(settings_store.performance_mode) if settings_store != null else false


func _update_animation_state() -> void:
	_animated = visible and not _performance_mode and bool(_visual.get("flow_enabled", true))
	set_process(_animated)


func _process(delta: float) -> void:
	var speed := clampf(float(_visual.get("flow_speed", 0.16)), 0.03, 0.65)
	_phase = fmod(_phase + delta * speed, 1.0)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func flow_phase_for_test() -> float:
	return _phase


func resolved_theme_for_test() -> String:
	return _resolve_theme()


func uses_texture_for_test() -> bool:
	return false


func _draw() -> void:
	if not visible or size.x < 40.0 or size.y < 28.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var cut := clampf(float(_visual.get("cut_size", minf(18.0, size.y * 0.18))), 4.0, 34.0)
	var outer := _cut_points(rect, cut)
	var fill_points := outer.duplicate()
	fill_points.resize(maxi(0, fill_points.size() - 1))
	var fill := _fill_color()
	var header := _header_color()
	var primary := _primary_color()
	var secondary := _secondary_color()
	var tertiary := _tertiary_color(primary, secondary)
	if _locked:
		fill = _gray(fill, 0.42)
		header = _gray(header, 0.48)
		primary = _gray(primary, 0.58)
		secondary = _gray(secondary, 0.50)
		tertiary = _gray(tertiary, 0.64)

	# 深色主面、顶部身份带和内层玻璃面。
	draw_colored_polygon(fill_points, fill)
	var header_height := clampf(float(_visual.get("header_height", size.y * 0.25)), 12.0, size.y * 0.40)
	var header_points := PackedVector2Array([
		Vector2(cut, 1.0), Vector2(size.x - cut, 1.0), Vector2(size.x - 1.0, cut),
		Vector2(size.x - 1.0, header_height), Vector2(size.x * 0.62, header_height),
		Vector2(size.x * 0.58, minf(size.y - 2.0, header_height + 8.0)),
		Vector2(cut * 0.35, minf(size.y - 2.0, header_height + 8.0)),
		Vector2(1.0, header_height), Vector2(1.0, cut),
	])
	draw_colored_polygon(header_points, header)
	var inner_rect := Rect2(Vector2(5.0, 5.0), size - Vector2(10.0, 10.0))
	var inner := _cut_points(inner_rect, maxf(2.0, cut - 4.0))
	draw_polyline(inner, Color(tertiary.r, tertiary.g, tertiary.b, 0.20), 1.0, true)

	match _resolve_theme():
		"gold":
			_draw_gold(rect, primary, secondary, tertiary)
		"speed":
			_draw_speed(rect, primary, secondary)
		"blueprint":
			_draw_blueprint(rect, primary, secondary)
		"aurora":
			_draw_aurora(rect, primary, secondary, tertiary)
		"prism":
			_draw_prism(rect, primary, secondary, tertiary)
		"neon":
			_draw_neon(rect, primary, secondary)
		_:
			_draw_cyber(rect, primary, secondary)

	_draw_scanlines(rect, primary)
	draw_polyline(outer, Color(primary.r, primary.g, primary.b, 0.94), 2.0, true)
	_draw_structure_lines(rect, cut, primary, secondary)
	_draw_rarity_marks(rect, primary, secondary)
	if _animated:
		_draw_flow(rect, outer, primary, secondary, tertiary)


func _draw_cyber(rect: Rect2, primary: Color, secondary: Color) -> void:
	var gap := maxf(14.0, rect.size.x / 18.0)
	var x := 8.0
	while x < rect.size.x - 8.0:
		draw_line(Vector2(x, rect.size.y * 0.34), Vector2(x, rect.size.y - 8.0),
			Color(primary.r, primary.g, primary.b, 0.08), 1.0)
		x += gap
	for i in 5:
		var y := rect.size.y * 0.38 + float(i) * maxf(7.0, rect.size.y * 0.105)
		draw_line(Vector2(9.0, y), Vector2(rect.size.x - 9.0, y),
			Color(secondary.r, secondary.g, secondary.b, 0.075), 1.0)
	for i in 6:
		var px := rect.size.x * (0.12 + float(i) * 0.145)
		var py := rect.size.y * (0.48 + float((i * 7) % 5) * 0.08)
		draw_rect(Rect2(Vector2(px, py), Vector2(2.0, 2.0)),
			Color(primary.r, primary.g, primary.b, 0.42), true)


func _draw_neon(rect: Rect2, primary: Color, secondary: Color) -> void:
	var base_y := rect.size.y * 0.72
	var points_primary := PackedVector2Array()
	var points_secondary := PackedVector2Array()
	for i in 25:
		var t := float(i) / 24.0
		var x := lerpf(8.0, rect.size.x - 8.0, t)
		points_primary.append(Vector2(x, base_y + sin(t * TAU * 2.0 + _phase * TAU) * rect.size.y * 0.075))
		points_secondary.append(Vector2(x, base_y + sin(t * TAU * 3.0 + 1.4 - _phase * TAU) * rect.size.y * 0.045))
	draw_polyline(points_primary, Color(primary.r, primary.g, primary.b, 0.16), 7.0, true)
	draw_polyline(points_primary, Color(primary.r, primary.g, primary.b, 0.72), 1.8, true)
	draw_polyline(points_secondary, Color(secondary.r, secondary.g, secondary.b, 0.58), 1.3, true)


func _draw_speed(rect: Rect2, primary: Color, secondary: Color) -> void:
	for i in 7:
		var y := rect.size.y * 0.38 + float(i) * rect.size.y * 0.075
		var shift := float(i % 3) * rect.size.x * 0.035
		draw_line(Vector2(rect.size.x * 0.12 + shift, y),
			Vector2(rect.size.x * 0.66 + shift, y - rect.size.y * 0.18),
			Color(primary.r, primary.g, primary.b, 0.12 + float(i % 2) * 0.08), 2.0, true)
	for i in 3:
		var x := rect.size.x * (0.70 + float(i) * 0.065)
		var center_y := rect.size.y * 0.65
		var chevron := PackedVector2Array([
			Vector2(x - 8.0, center_y - 12.0), Vector2(x + 3.0, center_y),
			Vector2(x - 8.0, center_y + 12.0),
		])
		draw_polyline(chevron, Color(secondary.r, secondary.g, secondary.b, 0.62 - float(i) * 0.13),
			2.2, true)


func _draw_blueprint(rect: Rect2, primary: Color, secondary: Color) -> void:
	var grid := maxf(12.0, minf(rect.size.x, rect.size.y) * 0.16)
	var x := grid
	while x < rect.size.x:
		draw_line(Vector2(x, rect.size.y * 0.28), Vector2(x, rect.size.y - 5.0),
			Color(primary.r, primary.g, primary.b, 0.10), 1.0)
		x += grid
	var y := rect.size.y * 0.32
	while y < rect.size.y:
		draw_line(Vector2(5.0, y), Vector2(rect.size.x - 5.0, y),
			Color(primary.r, primary.g, primary.b, 0.10), 1.0)
		y += grid
	draw_line(Vector2(rect.size.x * 0.18, rect.size.y * 0.80),
		Vector2(rect.size.x * 0.82, rect.size.y * 0.80),
		Color(secondary.r, secondary.g, secondary.b, 0.48), 1.0, true)
	for px in [rect.size.x * 0.18, rect.size.x * 0.82]:
		draw_line(Vector2(px, rect.size.y * 0.74), Vector2(px, rect.size.y * 0.86),
			Color(secondary.r, secondary.g, secondary.b, 0.48), 1.0, true)


func _draw_aurora(rect: Rect2, primary: Color, secondary: Color, tertiary: Color) -> void:
	var colors: Array[Color] = [primary, secondary, tertiary]
	for band in 3:
		var points := PackedVector2Array()
		for i in 19:
			var t := float(i) / 18.0
			var x := lerpf(5.0, rect.size.x - 5.0, t)
			var y := rect.size.y * (0.48 + float(band) * 0.10) \
				+ sin(t * TAU * (1.3 + float(band) * 0.35) + _phase * TAU + float(band)) * rect.size.y * 0.08
			points.append(Vector2(x, y))
		var color := colors[band]
		draw_polyline(points, Color(color.r, color.g, color.b, 0.10), 8.0, true)
		draw_polyline(points, Color(color.r, color.g, color.b, 0.48), 1.4, true)
	# 未来城市剪影。
	var skyline_y := rect.size.y - 6.0
	for i in 15:
		var width := maxf(4.0, rect.size.x / 35.0)
		var x := float(i) * rect.size.x / 15.0
		var h := rect.size.y * (0.10 + float((i * 7) % 9) * 0.018)
		draw_rect(Rect2(Vector2(x, skyline_y - h), Vector2(width, h)),
			Color(0.01, 0.04, 0.09, 0.62), true)


func _draw_prism(rect: Rect2, primary: Color, secondary: Color, tertiary: Color) -> void:
	var center := rect.get_center()
	var colors: Array[Color] = [primary, secondary, tertiary]
	for i in 8:
		var angle0 := TAU * float(i) / 8.0 + _phase * 0.22
		var angle1 := TAU * float(i + 1) / 8.0 + _phase * 0.22
		var radius0 := minf(rect.size.x, rect.size.y) * (0.22 + float(i % 3) * 0.06)
		var radius1 := minf(rect.size.x, rect.size.y) * (0.38 + float((i + 1) % 2) * 0.08)
		var tri := PackedVector2Array([
			center,
			center + Vector2(cos(angle0), sin(angle0)) * radius0,
			center + Vector2(cos(angle1), sin(angle1)) * radius1,
		])
		var color := colors[i % colors.size()]
		draw_colored_polygon(tri, Color(color.r, color.g, color.b, 0.065))
		draw_polyline(tri, Color(color.r, color.g, color.b, 0.20), 1.0, true)


func _draw_gold(rect: Rect2, primary: Color, secondary: Color, tertiary: Color) -> void:
	for i in 8:
		var x := rect.size.x * (0.08 + float(i) * 0.12)
		draw_line(Vector2(x, rect.size.y * 0.34),
			Vector2(x + rect.size.x * 0.10, rect.size.y - 6.0),
			Color(primary.r, primary.g, primary.b, 0.08 + float(i % 2) * 0.05), 1.5, true)
	var crown_center := Vector2(rect.size.x * 0.78, rect.size.y * 0.62)
	var crown := PackedVector2Array([
		crown_center + Vector2(-25.0, 10.0), crown_center + Vector2(-18.0, -10.0),
		crown_center + Vector2(-6.0, 5.0), crown_center + Vector2(2.0, -17.0),
		crown_center + Vector2(14.0, 5.0), crown_center + Vector2(24.0, -9.0),
		crown_center + Vector2(28.0, 10.0),
	])
	draw_polyline(crown, Color(secondary.r, secondary.g, secondary.b, 0.72), 2.0, true)
	draw_line(crown_center + Vector2(-25.0, 13.0), crown_center + Vector2(28.0, 13.0),
		Color(tertiary.r, tertiary.g, tertiary.b, 0.68), 2.0, true)


func _draw_scanlines(rect: Rect2, primary: Color) -> void:
	var gap := maxf(7.0, rect.size.y / 14.0)
	var y := 4.0 + (_phase * gap if _animated else 0.0)
	while y < rect.size.y - 3.0:
		draw_line(Vector2(3.0, y), Vector2(rect.size.x - 3.0, y),
			Color(primary.r, primary.g, primary.b, 0.035), 1.0)
		y += gap


func _draw_structure_lines(rect: Rect2, cut: float, primary: Color, secondary: Color) -> void:
	draw_line(Vector2(cut, 0.0), Vector2(rect.size.x * 0.43, 0.0), primary, 3.0, true)
	draw_line(Vector2(rect.size.x * 0.68, 0.0), Vector2(rect.size.x - cut, 0.0), secondary, 2.2, true)
	draw_line(Vector2(cut, rect.size.y), Vector2(rect.size.x * 0.34, rect.size.y), secondary, 2.0, true)
	draw_line(Vector2(rect.size.x * 0.61, rect.size.y), Vector2(rect.size.x - cut, rect.size.y), primary, 3.0, true)
	var marker_y := rect.size.y * 0.52
	draw_line(Vector2(0.0, marker_y), Vector2(10.0, marker_y), primary, 2.0, true)
	draw_line(Vector2(rect.size.x - 10.0, marker_y), Vector2(rect.size.x, marker_y), secondary, 2.0, true)


func _draw_rarity_marks(rect: Rect2, primary: Color, secondary: Color) -> void:
	var rarity := str(_visual.get("rarity", "common"))
	var count := int({"common": 1, "rare": 2, "epic": 3, "legendary": 4}.get(rarity, 1))
	var start_x := rect.size.x - 13.0 - float(count - 1) * 6.0
	for i in count:
		var color := primary.lerp(secondary, float(i) / maxf(1.0, float(count - 1)))
		draw_circle(Vector2(start_x + float(i) * 6.0, 7.0), 1.7,
			Color(color.r, color.g, color.b, 0.92))


func _draw_flow(rect: Rect2, outer: PackedVector2Array, primary: Color,
		secondary: Color, tertiary: Color) -> void:
	# 沿边框循环的主流光。
	var perimeter := _polyline_length(outer)
	var head_distance := _phase * perimeter
	var trail_length := perimeter * 0.18
	var previous := _point_on_polyline(outer, head_distance - trail_length)
	for i in 20:
		var t := float(i + 1) / 20.0
		var current := _point_on_polyline(outer, head_distance - trail_length + trail_length * t)
		var color := primary.lerp(secondary, t)
		var alpha := 0.12 + t * 0.82
		draw_line(previous, current, Color(color.r, color.g, color.b, alpha),
			1.2 + t * 2.2, true)
		previous = current
	var head := _point_on_polyline(outer, head_distance)
	draw_circle(head, 7.0, Color(tertiary.r, tertiary.g, tertiary.b, 0.12))
	draw_circle(head, 2.2, Color.WHITE)

	# 卡面斜向扫光，宽度随卡片尺寸自适应。
	var sweep_x := lerpf(-rect.size.x * 0.25, rect.size.x * 1.25, _phase)
	var sweep_width := maxf(18.0, rect.size.x * 0.055)
	var sweep := PackedVector2Array([
		Vector2(sweep_x - sweep_width, rect.size.y - 3.0),
		Vector2(sweep_x, 3.0),
		Vector2(sweep_x + sweep_width * 0.55, 3.0),
		Vector2(sweep_x - sweep_width * 0.45, rect.size.y - 3.0),
	])
	draw_colored_polygon(sweep, Color(tertiary.r, tertiary.g, tertiary.b, 0.075))


func _cut_points(rect: Rect2, cut: float) -> PackedVector2Array:
	var c := clampf(cut, 0.0, minf(rect.size.x, rect.size.y) * 0.24)
	return PackedVector2Array([
		Vector2(rect.position.x + c, rect.position.y),
		Vector2(rect.end.x - c, rect.position.y),
		Vector2(rect.end.x, rect.position.y + c),
		Vector2(rect.end.x, rect.end.y - c),
		Vector2(rect.end.x - c, rect.end.y),
		Vector2(rect.position.x + c, rect.end.y),
		Vector2(rect.position.x, rect.end.y - c),
		Vector2(rect.position.x, rect.position.y + c),
		Vector2(rect.position.x + c, rect.position.y),
	])


func _polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return maxf(1.0, total)


func _point_on_polyline(points: PackedVector2Array, raw_distance: float) -> Vector2:
	var total := _polyline_length(points)
	var distance := fposmod(raw_distance, total)
	for i in range(points.size() - 1):
		var segment := points[i].distance_to(points[i + 1])
		if distance <= segment:
			return points[i].lerp(points[i + 1], distance / maxf(0.001, segment))
		distance -= segment
	return points[points.size() - 1]


func _resolve_theme() -> String:
	var explicit := str(_visual.get("card_theme", "")).strip_edges().to_lower()
	if not explicit.is_empty():
		return explicit
	var style := str(_visual.get("style", "blue_grid")).to_lower()
	if style.contains("gold") or style.contains("vip") or style.contains("star_track"):
		return "gold"
	if style.contains("speed") or style.contains("lightning"):
		return "speed"
	if style.contains("blueprint") or style.contains("grid"):
		return "blueprint"
	if style.contains("aurora") or style.contains("city"):
		return "aurora"
	if style.contains("prism") or style.contains("myth"):
		return "prism"
	if style.contains("neon") or style.contains("fancy") or style.contains("wave"):
		return "neon"
	return "cyber"


func _fill_color() -> Color:
	return _as_color(_visual.get("fill_color", Color(0.008, 0.035, 0.095, 0.96)),
		Color(0.008, 0.035, 0.095, 0.96))


func _header_color() -> Color:
	return _as_color(_visual.get("header_color", Color(0.02, 0.16, 0.28, 0.72)),
		Color(0.02, 0.16, 0.28, 0.72))


func _primary_color() -> Color:
	return _as_color(_visual.get("border_color", E5OriginalTheme.CYAN), E5OriginalTheme.CYAN)


func _secondary_color() -> Color:
	return _as_color(_visual.get("secondary_color", E5OriginalTheme.MAGENTA), E5OriginalTheme.MAGENTA)


func _tertiary_color(primary: Color, secondary: Color) -> Color:
	var fallback := primary.lerp(secondary, 0.50).lightened(0.35)
	return _as_color(_visual.get("highlight_color", fallback), fallback)


func _as_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value)
	return Color.html(text) if Color.html_is_valid(text) else fallback


func _gray(color: Color, factor: float) -> Color:
	var luminance := color.get_luminance() * factor
	return Color(luminance, luminance, luminance, color.a)
