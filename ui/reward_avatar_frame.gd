class_name RewardAvatarFrame
extends Control
## 纯代码头像框：按奖励主题绘制环形结构、轨道刻度与流光。
## 保留 AvatarFrameArt 节点作为旧场景兼容壳，但不再依赖 SVG/PNG 图集。

var _visual: Dictionary = {}
var _art: TextureRect
var _avatar_target := Rect2()
var _avatar_edge_overlap := 3.0
var _has_avatar_target := false
var _hole_side := 0.0
var _frame_padding := 18.0
var _phase := 0.0
var _animated := false
var _locked := false
var _performance_mode := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_art = TextureRect.new()
	_art.name = "AvatarFrameArt"
	_art.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	add_child(_art)
	_refresh_performance_mode()
	_update_animation_state()
	queue_redraw()


func set_appearance(appearance: Dictionary) -> void:
	_visual = (appearance.get("visual", {}) as Dictionary).duplicate(true)
	if not _visual.has("rarity"):
		_visual["rarity"] = str(appearance.get("rarity", "common"))
	var is_default := bool(appearance.get("is_default", appearance.is_empty()))
	visible = bool(_visual.get("visible", not is_default))
	_refresh_performance_mode()
	_layout_around_avatar()
	_update_animation_state()
	queue_redraw()


func set_locked(locked: bool) -> void:
	_locked = locked
	queue_redraw()


func set_avatar_target(avatar_rect: Rect2, edge_overlap := 3.0) -> void:
	_avatar_target = avatar_rect
	_avatar_edge_overlap = maxf(0.0, edge_overlap)
	_has_avatar_target = avatar_rect.size.x > 1.0 and avatar_rect.size.y > 1.0
	_layout_around_avatar()
	queue_redraw()


func _refresh_performance_mode() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var settings_store := tree.root.get_node_or_null("SettingsStore") if tree != null else null
	_performance_mode = bool(settings_store.performance_mode) if settings_store != null else false


func _update_animation_state() -> void:
	_animated = visible and not _performance_mode and bool(_visual.get("flow_enabled", true))
	set_process(_animated)


func _process(delta: float) -> void:
	var speed := clampf(float(_visual.get("flow_speed", 0.20)), 0.04, 0.75)
	_phase = fmod(_phase + delta * speed, 1.0)
	queue_redraw()


func _layout_around_avatar() -> void:
	if not _has_avatar_target:
		return
	var avatar_diameter := minf(_avatar_target.size.x, _avatar_target.size.y)
	_hole_side = maxf(8.0, avatar_diameter - _avatar_edge_overlap * 2.0)
	_frame_padding = clampf(float(_visual.get("frame_padding", avatar_diameter * 0.27)), 17.0, 48.0)
	var frame_side := _hole_side + _frame_padding * 2.0
	size = Vector2(frame_side, frame_side)
	custom_minimum_size = Vector2.ZERO
	position = _avatar_target.get_center() - size * 0.5
	if _art != null:
		_art.position = Vector2.ZERO
		_art.size = size


func avatar_hole_rect_for_test() -> Rect2:
	var hole := _hole_side
	if hole <= 0.0:
		hole = minf(size.x, size.y) * 0.66
	return Rect2(position + (size - Vector2(hole, hole)) * 0.5, Vector2(hole, hole))


func flow_phase_for_test() -> float:
	return _phase


func resolved_theme_for_test() -> String:
	return _resolve_theme()


func uses_texture_for_test() -> bool:
	return false


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _art != null:
			_art.position = Vector2.ZERO
			_art.size = size
		queue_redraw()


func _draw() -> void:
	if not visible or size.x < 24.0 or size.y < 24.0:
		return
	var center := size * 0.5
	var hole_radius := (_hole_side * 0.5) if _hole_side > 0.0 else minf(size.x, size.y) * 0.33
	var outer_radius := minf(size.x, size.y) * 0.5 - 3.0
	var rail_radius := lerpf(hole_radius + 2.0, outer_radius, 0.56)
	var primary := _primary_color()
	var secondary := _secondary_color()
	var tertiary := _tertiary_color(primary, secondary)
	if _locked:
		primary = _gray(primary, 0.58)
		secondary = _gray(secondary, 0.50)
		tertiary = _gray(tertiary, 0.64)
	var thickness := clampf(float(_visual.get("thickness", maxf(3.0, size.x * 0.022))), 2.0, 9.0)

	# 三层结构环：外部柔光、主结构环、贴近头像的保护环。
	draw_arc(center, rail_radius, 0.0, TAU, 112,
		Color(primary.r, primary.g, primary.b, 0.12), thickness + 9.0, true)
	draw_arc(center, rail_radius, 0.0, TAU, 112,
		Color(primary.r, primary.g, primary.b, 0.92), thickness, true)
	draw_arc(center, hole_radius + 2.5, 0.0, TAU, 112,
		Color(secondary.r, secondary.g, secondary.b, 0.74), maxf(1.2, thickness * 0.42), true)
	draw_arc(center, outer_radius - 1.0, 0.0, TAU, 112,
		Color(tertiary.r, tertiary.g, tertiary.b, 0.34), maxf(1.0, thickness * 0.28), true)

	match _resolve_theme():
		"gold":
			_draw_gold(center, rail_radius, outer_radius, primary, secondary, tertiary)
		"ice":
			_draw_ice(center, rail_radius, outer_radius, primary, secondary)
		"flame":
			_draw_flame(center, rail_radius, outer_radius, primary, secondary)
		"matrix":
			_draw_matrix(center, rail_radius, outer_radius, primary, secondary)
		"aurora":
			_draw_aurora(center, rail_radius, outer_radius, primary, secondary, tertiary)
		"pulse":
			_draw_pulse(center, rail_radius, outer_radius, primary, secondary)
		"silver":
			_draw_silver(center, rail_radius, outer_radius, primary, secondary)
		_:
			_draw_cyber(center, rail_radius, outer_radius, primary, secondary)

	_draw_rarity_nodes(center, outer_radius, primary, secondary)
	if _animated:
		_draw_flow(center, rail_radius, outer_radius, thickness, primary, secondary, tertiary)


func _draw_cyber(center: Vector2, rail_radius: float, outer_radius: float,
		primary: Color, secondary: Color) -> void:
	for i in 12:
		var angle := TAU * float(i) / 12.0 - PI * 0.5
		var radial := Vector2(cos(angle), sin(angle))
		var long_tick := i % 3 == 0
		var inner := rail_radius + (3.0 if long_tick else 5.0)
		var outer := outer_radius - (1.0 if long_tick else 4.0)
		var color := secondary if i % 4 == 0 else primary
		draw_line(center + radial * inner, center + radial * outer,
			Color(color.r, color.g, color.b, 0.88), 2.4 if long_tick else 1.4, true)
	for i in 4:
		var angle := PI * 0.25 + float(i) * PI * 0.5
		var radial := Vector2(cos(angle), sin(angle))
		var tangent := Vector2(-radial.y, radial.x)
		var point := center + radial * (outer_radius - 2.0)
		draw_line(point - tangent * 7.0, point + tangent * 7.0,
			Color(secondary.r, secondary.g, secondary.b, 0.76), 2.0, true)


func _draw_gold(center: Vector2, rail_radius: float, outer_radius: float,
		primary: Color, secondary: Color, tertiary: Color) -> void:
	for i in 8:
		var angle := TAU * float(i) / 8.0 - PI * 0.5
		var radial := Vector2(cos(angle), sin(angle))
		var tangent := Vector2(-radial.y, radial.x)
		var point := center + radial * (outer_radius - 2.5)
		var diamond := PackedVector2Array([
			point + radial * 7.0, point + tangent * 4.2,
			point - radial * 7.0, point - tangent * 4.2,
		])
		draw_colored_polygon(diamond, Color(primary.r, primary.g, primary.b, 0.34))
		draw_polyline(_closed(diamond), tertiary, 1.2, true)
	var crown_y := center.y - outer_radius - 3.0
	var crown := PackedVector2Array([
		Vector2(center.x - 18.0, crown_y + 10.0), Vector2(center.x - 13.0, crown_y),
		Vector2(center.x - 4.0, crown_y + 8.0), Vector2(center.x + 2.0, crown_y - 4.0),
		Vector2(center.x + 10.0, crown_y + 8.0), Vector2(center.x + 18.0, crown_y),
		Vector2(center.x + 22.0, crown_y + 12.0),
	])
	draw_polyline(crown, Color(secondary.r, secondary.g, secondary.b, 0.92), 2.0, true)
	draw_arc(center, rail_radius - 5.0, PI * 0.08, PI * 0.92, 48,
		Color(tertiary.r, tertiary.g, tertiary.b, 0.58), 1.6, true)


func _draw_ice(center: Vector2, rail_radius: float, outer_radius: float,
		primary: Color, secondary: Color) -> void:
	for i in 10:
		var angle := TAU * float(i) / 10.0 - PI * 0.5
		var radial := Vector2(cos(angle), sin(angle))
		var tangent := Vector2(-radial.y, radial.x)
		var base := center + radial * (rail_radius + 3.0)
		var shard := PackedVector2Array([
			base - tangent * 3.5,
			center + radial * (outer_radius + (5.0 if i % 2 == 0 else 1.5)),
			base + tangent * 3.5,
		])
		draw_colored_polygon(shard, Color(primary.r, primary.g, primary.b, 0.22))
		draw_polyline(shard, Color(secondary.r, secondary.g, secondary.b, 0.68), 1.0, true)


func _draw_flame(center: Vector2, rail_radius: float, outer_radius: float,
		primary: Color, secondary: Color) -> void:
	for i in 12:
		var angle := TAU * float(i) / 12.0
		var radial := Vector2(cos(angle), sin(angle))
		var tangent := Vector2(-radial.y, radial.x)
		var wave := (sin(float(i) * 1.7 + _phase * TAU) + 1.0) * 2.5
		var base := center + radial * (rail_radius + 4.0)
		var tip := center + radial * (outer_radius + 2.0 + wave)
		var flame := PackedVector2Array([base - tangent * 3.8, tip, base + tangent * 3.8])
		draw_colored_polygon(flame, Color(primary.r, primary.g, primary.b, 0.20))
		draw_polyline(flame, Color(secondary.r, secondary.g, secondary.b, 0.66), 1.1, true)


func _draw_matrix(center: Vector2, rail_radius: float, outer_radius: float,
		primary: Color, secondary: Color) -> void:
	for i in 16:
		var angle := TAU * float(i) / 16.0
		var radial := Vector2(cos(angle), sin(angle))
		var p := center + radial * lerpf(rail_radius + 3.0, outer_radius - 1.0,
			float((i * 7) % 11) / 10.0)
		var node_size := 2.0 + float(i % 3)
		draw_rect(Rect2(p - Vector2.ONE * node_size * 0.5, Vector2.ONE * node_size),
			Color(primary.r, primary.g, primary.b, 0.62), true)
	for i in 4:
		var angle := PI * 0.25 + float(i) * PI * 0.5
		var radial := Vector2(cos(angle), sin(angle))
		draw_line(center + radial * (rail_radius - 3.0), center + radial * (outer_radius - 2.0),
			Color(secondary.r, secondary.g, secondary.b, 0.48), 1.0, true)


func _draw_aurora(center: Vector2, rail_radius: float, outer_radius: float,
		primary: Color, secondary: Color, tertiary: Color) -> void:
	var colors: Array[Color] = [primary, secondary, tertiary]
	for i in 18:
		var angle0 := TAU * float(i) / 18.0
		var angle1 := TAU * float(i + 1) / 18.0
		var color := colors[i % colors.size()]
		draw_arc(center, outer_radius - 3.0, angle0, angle1, 4,
			Color(color.r, color.g, color.b, 0.72), 2.0, true)
	for i in 7:
		var angle := TAU * (float(i) / 7.0 + _phase * 0.18)
		var radial := Vector2(cos(angle), sin(angle))
		var p := center + radial * lerpf(rail_radius, outer_radius + 1.0, float(i % 3) / 2.0)
		draw_circle(p, 1.5 + float(i % 2), Color(tertiary.r, tertiary.g, tertiary.b, 0.66))


func _draw_pulse(center: Vector2, rail_radius: float, outer_radius: float,
		primary: Color, secondary: Color) -> void:
	for i in 24:
		var angle := TAU * float(i) / 24.0
		var radial := Vector2(cos(angle), sin(angle))
		var pulse := 3.0 + float((i * 5) % 7)
		if _animated:
			pulse += (sin(_phase * TAU * 2.0 + float(i) * 0.8) + 1.0) * 2.0
		draw_line(center + radial * (rail_radius + 3.0),
			center + radial * minf(outer_radius + 2.0, rail_radius + 3.0 + pulse),
			Color(primary.r, primary.g, primary.b, 0.66), 1.3, true)
	draw_arc(center, rail_radius - 4.0, 0.0, TAU, 96,
		Color(secondary.r, secondary.g, secondary.b, 0.32), 1.2, true)


func _draw_silver(center: Vector2, rail_radius: float, outer_radius: float,
		primary: Color, secondary: Color) -> void:
	for i in 4:
		var angle := PI * 0.25 + float(i) * PI * 0.5
		var radial := Vector2(cos(angle), sin(angle))
		var tangent := Vector2(-radial.y, radial.x)
		var p := center + radial * (outer_radius - 2.0)
		draw_line(p - tangent * 8.0, p + tangent * 8.0,
			Color(primary.r, primary.g, primary.b, 0.78), 1.4, true)
	draw_arc(center, rail_radius - 4.0, PI * 0.08, PI * 0.92, 48,
		Color(secondary.r, secondary.g, secondary.b, 0.34), 1.0, true)


func _draw_flow(center: Vector2, rail_radius: float, outer_radius: float, thickness: float,
		primary: Color, secondary: Color, tertiary: Color) -> void:
	var start := _phase * TAU - PI * 0.5
	_draw_gradient_arc(center, rail_radius, start, PI * 0.56, 22,
		secondary, tertiary, thickness + 5.0, 0.18)
	_draw_gradient_arc(center, rail_radius, start, PI * 0.56, 22,
		Color.WHITE, primary, maxf(1.6, thickness * 0.62), 0.94)
	var reverse_start := -_phase * TAU + PI * 0.5
	_draw_gradient_arc(center, outer_radius - 1.5, reverse_start, PI * 0.34, 16,
		primary, secondary, 1.4, 0.76)
	var head := center + Vector2(cos(start + PI * 0.56), sin(start + PI * 0.56)) * rail_radius
	draw_circle(head, thickness * 0.70 + 2.0, Color(tertiary.r, tertiary.g, tertiary.b, 0.16))
	draw_circle(head, maxf(1.5, thickness * 0.30), Color.WHITE)


func _draw_rarity_nodes(center: Vector2, outer_radius: float, primary: Color, secondary: Color) -> void:
	var rarity := str(_visual.get("rarity", "common"))
	var count := int({"common": 1, "rare": 2, "epic": 3, "legendary": 4}.get(rarity, 1))
	for i in count:
		var angle := -PI * 0.5 + (float(i) - float(count - 1) * 0.5) * 0.16
		var p := center + Vector2(cos(angle), sin(angle)) * (outer_radius + 1.0)
		var color := primary.lerp(secondary, float(i) / maxf(1.0, float(count - 1)))
		draw_circle(p, 2.2, Color(color.r, color.g, color.b, 0.92))


func _draw_gradient_arc(center: Vector2, radius: float, start: float, length: float,
		segments: int, from_color: Color, to_color: Color, width: float, alpha: float) -> void:
	for i in segments:
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var color := from_color.lerp(to_color, t0)
		draw_arc(center, radius, start + length * t0, start + length * t1, 3,
			Color(color.r, color.g, color.b, alpha), width, true)


func _resolve_theme() -> String:
	var explicit := str(_visual.get("frame_theme", "")).strip_edges().to_lower()
	if not explicit.is_empty():
		return explicit
	var style := str(_visual.get("style", "neon_ticks")).to_lower()
	if style.contains("gold") or style.contains("legend") or style.contains("vip") \
			or style.contains("perfect") or style.contains("crown"):
		return "gold"
	if style.contains("ice") or style.contains("snow") or style.contains("crystal"):
		return "ice"
	if style.contains("flame") or style.contains("fire"):
		return "flame"
	if style.contains("data") or style.contains("grid") or style.contains("matrix"):
		return "matrix"
	if style.contains("aurora") or style.contains("prism") or style.contains("starburst"):
		return "aurora"
	if style.contains("pulse") or style.contains("wave"):
		return "pulse"
	if style.contains("silver") or style.contains("minimal"):
		return "silver"
	return "cyber"


func _primary_color() -> Color:
	return _as_color(_visual.get("border_color", E5OriginalTheme.CYAN), E5OriginalTheme.CYAN)


func _secondary_color() -> Color:
	return _as_color(_visual.get("accent_color", E5OriginalTheme.MAGENTA), E5OriginalTheme.MAGENTA)


func _tertiary_color(primary: Color, secondary: Color) -> Color:
	return _as_color(_visual.get("highlight_color", primary.lerp(secondary, 0.50).lightened(0.35)),
		primary.lerp(secondary, 0.50).lightened(0.35))


func _as_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value)
	return Color.html(text) if Color.html_is_valid(text) else fallback


func _gray(color: Color, factor: float) -> Color:
	var luminance := color.get_luminance() * factor
	return Color(luminance, luminance, luminance, color.a)


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result
