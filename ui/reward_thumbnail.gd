class_name RewardThumbnail
extends Control
## 奖励背包缩略图：优先展示正式奖励美术；锁定项统一灰化并叠加锁标识。

const TitleBadgeScript := preload("res://ui/reward_title_badge.gd")
const AvatarFrameScript := preload("res://ui/reward_avatar_frame.gd")
const ProfileCardScript := preload("res://ui/reward_profile_card.gd")

var _reward: Dictionary = {}
var _locked := false
var _caption: Label
var _kind_label: Label
var _art: TextureRect
var _title_badge: RewardTitleBadge
var _avatar_preview: RewardAvatarFrame
var _card_preview: Control
var _has_art := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_ensure_art()
	_ensure_title_badge()
	_ensure_code_previews()
	_ensure_labels()
	_refresh_labels()
	queue_redraw()


func set_reward_data(reward: Dictionary, locked: bool) -> void:
	_reward = reward.duplicate(true)
	_locked = locked
	_ensure_art()
	_ensure_title_badge()
	_ensure_code_previews()
	_ensure_labels()
	_refresh_art()
	_refresh_labels()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if _art != null:
			_art.position = Vector2(4, 22)
			_art.size = Vector2(maxf(0.0, size.x - 8), maxf(0.0, size.y - 44))
		_layout_title_badge()
		_layout_code_previews()
		_layout_labels()
		queue_redraw()


func _ensure_art() -> void:
	if _art != null:
		return
	_art = TextureRect.new()
	_art.name = "RewardArt"
	_art.position = Vector2(4, 22)
	_art.size = Vector2(maxf(0.0, size.x - 8), maxf(0.0, size.y - 44))
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	move_child(_art, 0)


func _ensure_title_badge() -> void:
	if _title_badge != null:
		return
	_title_badge = TitleBadgeScript.new()
	_title_badge.name = "RewardTitlePreview"
	_title_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_badge)
	move_child(_title_badge, 1)
	_layout_title_badge()


func _layout_title_badge() -> void:
	if _title_badge == null:
		return
	var badge_height := clampf(size.y * 0.36, 30.0, 42.0)
	_title_badge.position = Vector2(6.0, maxf(25.0, (size.y - badge_height) * 0.48))
	_title_badge.size = Vector2(maxf(0.0, size.x - 12.0), badge_height)


func _ensure_code_previews() -> void:
	if _avatar_preview == null:
		_avatar_preview = AvatarFrameScript.new()
		_avatar_preview.name = "RewardAvatarFramePreview"
		_avatar_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_avatar_preview)
		move_child(_avatar_preview, 1)
	if _card_preview == null:
		_card_preview = ProfileCardScript.new()
		_card_preview.name = "RewardProfileCardPreview"
		_card_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_card_preview)
		move_child(_card_preview, 1)
	_layout_code_previews()


func _layout_code_previews() -> void:
	if _avatar_preview != null:
		var avatar_side := clampf(minf(size.x, size.y) * 0.38, 30.0, 54.0)
		var target := Rect2(
			Vector2((size.x - avatar_side) * 0.5, maxf(27.0, (size.y - avatar_side) * 0.48)),
			Vector2(avatar_side, avatar_side))
		_avatar_preview.set_avatar_target(target, 2.0)
	if _card_preview != null:
		_card_preview.position = Vector2(7.0, 28.0)
		_card_preview.size = Vector2(maxf(0.0, size.x - 14.0), maxf(0.0, size.y - 58.0))


func _ensure_labels() -> void:
	if _caption == null:
		_caption = Label.new()
		_caption.name = "ThumbnailCaption"
		_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_caption.clip_text = true
		_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_caption.add_theme_constant_override("outline_size", 2)
		_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_caption)
	if _kind_label == null:
		_kind_label = Label.new()
		_kind_label.name = "ThumbnailKind"
		_kind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_kind_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_kind_label.add_theme_constant_override("outline_size", 1)
		_kind_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		_kind_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_kind_label)
	_layout_labels()


func _layout_labels() -> void:
	if _caption != null:
		_caption.position = Vector2(5, size.y - 25)
		_caption.size = Vector2(maxf(0.0, size.x - 10), 20)
		_caption.add_theme_font_size_override("font_size", 10)
	if _kind_label != null:
		_kind_label.position = Vector2(6, 5)
		_kind_label.size = Vector2(maxf(0.0, size.x - 12), 16)
		_kind_label.add_theme_font_size_override("font_size", 9)


func _refresh_art() -> void:
	if _art == null:
		return
	var reward_type := str(_reward.get("type", "title"))
	_art.texture = null
	_art.visible = false
	if _title_badge != null:
		_title_badge.visible = false
	if _avatar_preview != null:
		_avatar_preview.visible = false
	if _card_preview != null:
		_card_preview.visible = false

	match reward_type:
		"title":
			_has_art = true
			if _title_badge != null:
				var title_appearance := _reward.duplicate(true)
				title_appearance["is_default"] = false
				_title_badge.visible = true
				_title_badge.set_appearance(title_appearance, 11 if size.x < 130.0 else 13)
				_title_badge.set_locked(_locked)
		"avatar_frame":
			_has_art = true
			if _avatar_preview != null:
				var frame_appearance := _reward.duplicate(true)
				frame_appearance["is_default"] = false
				_avatar_preview.visible = true
				_avatar_preview.set_appearance(frame_appearance)
				_avatar_preview.set_locked(_locked)
				_layout_code_previews()
		"profile_card":
			_has_art = true
			if _card_preview != null:
				var card_appearance := _reward.duplicate(true)
				card_appearance["is_default"] = false
				_card_preview.visible = true
				_card_preview.set_appearance(card_appearance)
				_card_preview.set_locked(_locked)
				_layout_code_previews()
		_:
			_has_art = false


func _refresh_labels() -> void:
	if _caption == null or _kind_label == null:
		return
	var reward_type := str(_reward.get("type", "title"))
	var visual: Dictionary = _reward.get("visual", {}) if _reward.get("visual", {}) is Dictionary else {}
	var caption := str(visual.get("badge", visual.get("style", _reward.get("name", "REWARD"))))
	caption = caption.replace("_", " ").to_upper()
	_caption.text = "LOCKED" if _locked else caption
	_kind_label.text = str({
		"title": "TITLE / 称号",
		"avatar_frame": "FRAME / 头像框",
		"profile_card": "CARD / 玩家卡",
	}.get(reward_type, "REWARD"))
	var text_color := Color(0.66, 0.70, 0.75) if _locked else _primary_color()
	_caption.add_theme_color_override("font_color", text_color)
	_kind_label.add_theme_color_override("font_color",
		Color(0.55, 0.59, 0.64) if _locked else Color(0.82, 0.91, 1.0))


func _draw() -> void:
	if size.x < 20.0 or size.y < 20.0:
		return
	var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var primary := _primary_color()
	var secondary := _secondary_color()
	if _locked:
		primary = _gray(primary, 0.62)
		secondary = _gray(secondary, 0.48)
	var bg := Color(0.018, 0.052, 0.082, 0.98) if not _locked else Color(0.085, 0.09, 0.105, 0.98)
	draw_rect(rect, bg, true)
	draw_rect(rect, Color(primary.r, primary.g, primary.b, 0.78), false, 2.0)
	draw_line(Vector2(8, 22), Vector2(size.x - 8, 22),
		Color(secondary.r, secondary.g, secondary.b, 0.58), 1.0, true)

	var reward_type := str(_reward.get("type", "title"))
	if reward_type == "avatar_frame" and _has_art:
		_draw_avatar_placeholder()
	elif not _has_art:
		match reward_type:
			"avatar_frame":
				_draw_avatar_frame(primary, secondary)
			"profile_card":
				_draw_profile_card(primary, secondary)
			_:
				_draw_title(primary, secondary)

	if _locked:
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), Color(0.05, 0.055, 0.065, 0.38), true)
		_draw_lock(Vector2(size.x * 0.5, size.y * 0.50))


func _draw_title(primary: Color, secondary: Color) -> void:
	var y := size.y * 0.48
	var left := 13.0
	var right := size.x - 13.0
	var ribbon := PackedVector2Array([
		Vector2(left, y - 14), Vector2(right - 8, y - 14), Vector2(right, y),
		Vector2(right - 8, y + 14), Vector2(left, y + 14), Vector2(left + 8, y),
	])
	draw_colored_polygon(ribbon, Color(primary.r, primary.g, primary.b, 0.30))
	draw_polyline(PackedVector2Array(Array(ribbon) + [ribbon[0]]), primary, 2.0, true)
	draw_line(Vector2(left + 18, y), Vector2(right - 18, y), secondary, 2.0, true)
	for x in [left + 10.0, right - 10.0]:
		draw_circle(Vector2(x, y), 3.0, secondary)


func _draw_avatar_placeholder() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.49)
	var radius := clampf(minf(size.x, size.y) * 0.18, 15.0, 27.0)
	draw_circle(center, radius, Color(0.075, 0.09, 0.12, 0.98))
	draw_circle(center + Vector2(0.0, -radius * 0.24), radius * 0.28,
		Color(0.42, 0.46, 0.52, 0.92))
	draw_arc(center + Vector2(0.0, radius * 0.50), radius * 0.48, PI, TAU, 24,
		Color(0.42, 0.46, 0.52, 0.92), radius * 0.42, true)


func _draw_avatar_frame(primary: Color, secondary: Color) -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.49)
	var radius := minf(size.x, size.y) * 0.28
	draw_circle(center, radius - 4.0, Color(0.10, 0.12, 0.15, 0.92))
	draw_circle(center + Vector2(0, -7), radius * 0.28, Color(0.42, 0.46, 0.50, 0.92))
	draw_arc(center + Vector2(0, radius * 0.48), radius * 0.48, PI, TAU, 24,
		Color(0.42, 0.46, 0.50, 0.92), radius * 0.42, true)
	draw_arc(center, radius, 0.0, TAU, 64, primary, 4.0, true)
	draw_arc(center, radius - 7.0, 0.0, TAU, 64,
		Color(secondary.r, secondary.g, secondary.b, 0.78), 2.0, true)
	for i in 8:
		var angle := TAU * float(i) / 8.0
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(center + dir * (radius + 2.0), center + dir * (radius + 8.0),
			secondary if i % 2 == 0 else primary, 2.0, true)


func _draw_profile_card(primary: Color, secondary: Color) -> void:
	var card := Rect2(Vector2(10, 29), Vector2(size.x - 20, size.y - 59))
	draw_rect(card, Color(primary.r, primary.g, primary.b, 0.16), true)
	draw_rect(card, primary, false, 2.0)
	draw_rect(Rect2(card.position + Vector2(1, 1), Vector2(card.size.x - 2, 11)),
		Color(secondary.r, secondary.g, secondary.b, 0.28), true)
	var avatar_center := card.position + Vector2(18, 30)
	draw_circle(avatar_center, 10.0, Color(0.10, 0.12, 0.16, 0.96))
	draw_arc(avatar_center, 11.0, 0.0, TAU, 32, secondary, 2.0, true)
	for i in 3:
		var line_y := card.position.y + 23 + i * 8
		draw_line(Vector2(card.position.x + 34, line_y),
			Vector2(card.end.x - 8 - i * 6, line_y),
			Color(primary.r, primary.g, primary.b, 0.78 - i * 0.13), 2.0, true)


func _draw_lock(center: Vector2) -> void:
	var lock_color := Color(0.82, 0.84, 0.87, 0.96)
	draw_arc(center + Vector2(0, -8), 9.0, PI, TAU, 20, lock_color, 3.0, true)
	draw_rect(Rect2(center + Vector2(-11, -7), Vector2(22, 18)), Color(0.14, 0.15, 0.17, 0.98), true)
	draw_rect(Rect2(center + Vector2(-11, -7), Vector2(22, 18)), lock_color, false, 2.0)
	draw_circle(center + Vector2(0, 1), 2.5, lock_color)
	draw_line(center + Vector2(0, 3), center + Vector2(0, 7), lock_color, 2.0, true)


func _primary_color() -> Color:
	var visual: Dictionary = _reward.get("visual", {}) if _reward.get("visual", {}) is Dictionary else {}
	var value = visual.get("primary_color", visual.get("border_color", Color(0.16, 0.91, 1.0)))
	return _as_color(value, Color(0.16, 0.91, 1.0))


func _secondary_color() -> Color:
	var visual: Dictionary = _reward.get("visual", {}) if _reward.get("visual", {}) is Dictionary else {}
	var value = visual.get("secondary_color", visual.get("accent_color", Color(1.0, 0.23, 0.78)))
	return _as_color(value, Color(1.0, 0.23, 0.78))


func _as_color(value, fallback: Color) -> Color:
	if value is Color:
		return value
	var text := str(value)
	return Color.html(text) if Color.html_is_valid(text) else fallback


func _gray(color: Color, factor: float) -> Color:
	var luminance := color.get_luminance() * factor
	return Color(luminance, luminance, luminance, color.a)
