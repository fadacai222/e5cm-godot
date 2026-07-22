class_name PlayerIdentityView
extends Panel
## 统一玩家身份组件：compact / gameplay / full。
## 保留 SongSelectProfileBadge 既有子节点命名，便于视觉契约和旧代码兼容。

const ResolverScript := preload("res://ui/reward_appearance_resolver.gd")
const AvatarFrameScript := preload("res://ui/reward_avatar_frame.gd")
const TitleBadgeScript := preload("res://ui/reward_title_badge.gd")
const ProfileCardScript := preload("res://ui/reward_profile_card.gd")
const ExpSystemScript := preload("res://core/exp_system.gd")

var identity_layout := "compact"
var player_tag := "1P"
var show_status := true
var show_progress := false
var _built := false
var _resolver := ResolverScript.new()
var _frame: E5HudFrame
var _card_art: TextureRect
var _card_fx: Control
var _avatar: TextureRect
var _avatar_frame: RewardAvatarFrame
var _nickname: Label
var _title_badge: RewardTitleBadge
var _rank: Label
var _level: Label
var _player_tag_label: Label
var _status_lights: Array[Label] = []
var _progress_labels: Array[Label] = []
var _preview_loadout := {}

func configure(layout_name: String, options := {}) -> void:
	identity_layout = layout_name if layout_name in ["compact", "gameplay", "full"] else "compact"
	player_tag = str(options.get("player_tag", player_tag))
	show_status = bool(options.get("show_status", identity_layout == "compact"))
	show_progress = bool(options.get("show_progress", identity_layout == "full"))
	if not _built:
		_build()
	_apply_layout()
	if is_inside_tree():
		refresh()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var transparent := StyleBoxFlat.new()
	transparent.bg_color = Color.TRANSPARENT
	transparent.set_border_width_all(0)
	add_theme_stylebox_override("panel", transparent)
	_build()
	_connect_signals()
	_apply_layout()
	refresh()

func _build() -> void:
	if _built:
		return
	_built = true
	_frame = UiKit.hud_frame(self, Rect2(Vector2.ZERO, Vector2(382, 112)), "PlayerHudFrame",
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 0.0, true, 14.0)
	_frame.show_side_ticks = false
	_card_art = TextureRect.new()
	_card_art.name = "ProfileCardArt"
	_card_art.position = Vector2.ZERO
	_card_art.size = Vector2(382, 112)
	_card_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_art.stretch_mode = TextureRect.STRETCH_SCALE
	_card_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_art.visible = false
	add_child(_card_art)
	move_child(_card_art, 0)

	_card_fx = ProfileCardScript.new()
	_card_fx.name = "RewardProfileCard"
	_card_fx.position = Vector2.ZERO
	_card_fx.size = Vector2(382, 112)
	add_child(_card_fx)
	move_child(_card_fx, 0)

	_player_tag_label = Label.new()
	_player_tag_label.name = "PlayerTag"
	_player_tag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_tag_label.add_theme_color_override("font_color", E5OriginalTheme.CYAN)
	_player_tag_label.add_theme_color_override("font_outline_color", Color(0, 0.04, 0.12, 0.96))
	_player_tag_label.add_theme_constant_override("outline_size", 4)
	_player_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_tag_label.text = player_tag
	add_child(_player_tag_label)

	_avatar = TextureRect.new()
	_avatar.name = "Avatar"
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar.modulate = Color.WHITE
	_avatar.self_modulate = Color.WHITE
	var avatar_shader := load("res://fx/circular_avatar_mask.gdshader") as Shader
	if avatar_shader != null:
		var avatar_material := ShaderMaterial.new()
		avatar_material.shader = avatar_shader
		_avatar.material = avatar_material
	add_child(_avatar)

	_avatar_frame = AvatarFrameScript.new()
	_avatar_frame.name = "RewardAvatarFrame"
	add_child(_avatar_frame)

	_nickname = Label.new()
	_nickname.name = "Nickname"
	_nickname.clip_text = true
	_nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_nickname.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_nickname.add_theme_color_override("font_color", Color.WHITE)
	_nickname.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	_nickname.add_theme_constant_override("outline_size", 4)
	_nickname.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nickname.text = "玩家"
	add_child(_nickname)

	_title_badge = TitleBadgeScript.new()
	_title_badge.name = "TitleBadge"
	add_child(_title_badge)

	_rank = Label.new()
	_rank.name = "Rank"
	_rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rank.add_theme_color_override("font_outline_color", Color(0.18, 0.07, 0.0, 0.94))
	_rank.add_theme_constant_override("outline_size", 4)
	_rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rank.text = "RANK"
	add_child(_rank)

	_level = Label.new()
	_level.name = "Level"
	_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level.add_theme_color_override("font_color", E5OriginalTheme.CYAN_SOFT)
	_level.add_theme_color_override("font_outline_color", Color(0, 0.03, 0.10, 0.96))
	_level.add_theme_constant_override("outline_size", 3)
	_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level.text = "LV.01"
	add_child(_level)

	for i in 5:
		var light := Label.new()
		light.name = "StatusLight%d" % i
		light.text = "♥"
		light.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		light.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		light.add_theme_color_override("font_outline_color", Color(0, 0.04, 0.10, 0.96))
		light.add_theme_constant_override("outline_size", 2)
		light.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(light)
		_status_lights.append(light)

	for mode in ["花式", "竞速", "DIY"]:
		var progress := Label.new()
		progress.name = "%sProgressSummary" % mode
		progress.add_theme_color_override("font_color", E5OriginalTheme.MUTED)
		progress.add_theme_constant_override("outline_size", 2)
		progress.add_theme_color_override("font_outline_color", Color(0, 0.02, 0.08, 0.92))
		progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(progress)
		_progress_labels.append(progress)

func _connect_signals() -> void:
	var profile_store = _root_service("ProfileStore")
	var reward_service = _root_service("RewardService")
	if profile_store != null:
		if not profile_store.profile_changed.is_connected(refresh):
			profile_store.profile_changed.connect(refresh)
		if not profile_store.progress_changed.is_connected(_on_progress_changed):
			profile_store.progress_changed.connect(_on_progress_changed)
	if reward_service != null and not reward_service.loadout_changed.is_connected(_on_loadout_changed):
		reward_service.loadout_changed.connect(_on_loadout_changed)
	var settings_store = _root_service("SettingsStore")
	if settings_store != null and settings_store.has_signal("performance_changed") \
			and not settings_store.performance_changed.is_connected(_on_performance_changed):
		settings_store.performance_changed.connect(_on_performance_changed)

func _root_service(service_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(service_name) if tree != null else null

func _on_progress_changed(_mode_key: String, _progress: Dictionary, _preview: bool) -> void:
	refresh()

func _on_loadout_changed(_loadout: Dictionary) -> void:
	_resolver.invalidate()
	refresh()

func _on_performance_changed(_enabled: bool) -> void:
	_resolver.invalidate()
	refresh()

func _apply_layout() -> void:
	if not _built:
		return
	match identity_layout:
		"gameplay":
			_apply_gameplay_layout()
		"full":
			_apply_full_layout()
		_:
			_apply_compact_layout()
	_avatar_frame.set_avatar_target(_avatar.get_rect(), 2.0)
	_frame.position = Vector2.ZERO
	_frame.size = size
	_card_art.position = Vector2.ZERO
	_card_art.size = size
	_card_fx.position = Vector2.ZERO
	_card_fx.size = size
	for light in _status_lights:
		light.visible = show_status
	for progress in _progress_labels:
		progress.visible = show_progress

func _apply_compact_layout() -> void:
	size = Vector2(382, 112)
	_player_tag_label.position = Vector2(14, 8)
	_player_tag_label.size = Vector2(46, 32)
	_player_tag_label.add_theme_font_size_override("font_size", 22)
	_avatar.position = Vector2(296, 17)
	_avatar.size = Vector2(76, 76)
	_avatar_frame.position = Vector2(292, 13)
	_avatar_frame.size = Vector2(84, 84)
	_nickname.position = Vector2(66, 5)
	_nickname.size = Vector2(214, 30)
	_nickname.add_theme_font_size_override("font_size", 21)
	_title_badge.position = Vector2(66, 35)
	_title_badge.size = Vector2(152, 24)
	_rank.position = Vector2(174, 60)
	_rank.size = Vector2(106, 22)
	_rank.add_theme_font_size_override("font_size", 16)
	_level.position = Vector2(66, 60)
	_level.size = Vector2(102, 22)
	_level.add_theme_font_size_override("font_size", 16)
	for i in _status_lights.size():
		_status_lights[i].position = Vector2(69 + i * 29, 85)
		_status_lights[i].size = Vector2(26, 23)
		_status_lights[i].add_theme_font_size_override("font_size", 17)

func _apply_gameplay_layout() -> void:
	size = Vector2(430, 150)
	_player_tag_label.position = Vector2(18, 14)
	_player_tag_label.size = Vector2(48, 34)
	_player_tag_label.add_theme_font_size_override("font_size", 20)
	_avatar.position = Vector2(20, 38)
	_avatar.size = Vector2(92, 92)
	_avatar_frame.position = Vector2(16, 34)
	_avatar_frame.size = Vector2(100, 100)
	_nickname.position = Vector2(136, 20)
	_nickname.size = Vector2(268, 42)
	_nickname.add_theme_font_size_override("font_size", 24)
	_title_badge.position = Vector2(136, 66)
	_title_badge.size = Vector2(190, 32)
	_rank.position = Vector2(286, 105)
	_rank.size = Vector2(118, 30)
	_rank.add_theme_font_size_override("font_size", 18)
	_level.position = Vector2(136, 105)
	_level.size = Vector2(130, 30)
	_level.add_theme_font_size_override("font_size", 18)

func _apply_full_layout() -> void:
	size = Vector2(820, 400)
	_player_tag_label.position = Vector2(34, 28)
	_player_tag_label.size = Vector2(70, 48)
	_player_tag_label.add_theme_font_size_override("font_size", 28)
	_avatar.position = Vector2(46, 94)
	_avatar.size = Vector2(190, 190)
	_avatar_frame.position = Vector2(39, 87)
	_avatar_frame.size = Vector2(204, 204)
	_nickname.position = Vector2(286, 64)
	_nickname.size = Vector2(480, 56)
	_nickname.add_theme_font_size_override("font_size", 34)
	_title_badge.position = Vector2(286, 132)
	_title_badge.size = Vector2(260, 42)
	_rank.position = Vector2(564, 190)
	_rank.size = Vector2(202, 46)
	_rank.add_theme_font_size_override("font_size", 28)
	_level.position = Vector2(286, 190)
	_level.size = Vector2(220, 46)
	_level.add_theme_font_size_override("font_size", 28)
	for i in _progress_labels.size():
		_progress_labels[i].position = Vector2(286, 258 + i * 38)
		_progress_labels[i].size = Vector2(470, 34)
		_progress_labels[i].add_theme_font_size_override("font_size", 19)

func refresh() -> void:
	if not _built:
		return
	var profile_store = _root_service("ProfileStore")
	var asset_loader = _root_service("AssetLoader")
	var settings_store = _root_service("SettingsStore")
	if profile_store == null or asset_loader == null:
		return
	var appearance: Dictionary = _resolver.resolve_loadout(_preview_loadout,
		bool(settings_store.performance_mode) if settings_store != null else false) \
		if not _preview_loadout.is_empty() else _resolver.resolve_current()
	_apply_card_theme(appearance.get("profile_card", {}))
	_avatar_frame.set_appearance(appearance.get("avatar_frame", {}))
	_title_badge.set_appearance(appearance.get("title", {}), 14 if identity_layout == "compact" else 18)
	_player_tag_label.text = player_tag
	var avatar_path := str(profile_store.profile.get("头像文件", ""))
	var avatar_texture = asset_loader.tex(avatar_path) if not avatar_path.is_empty() else null
	if avatar_texture == null:
		avatar_texture = asset_loader.tex("UI-img/个人中心-个人资料/默认头像.png")
	_avatar.texture = avatar_texture
	_avatar.modulate = Color.WHITE
	_avatar.self_modulate = Color.WHITE
	_nickname.text = str(profile_store.profile.get("昵称", "玩家"))
	_level.text = "LV.%02d" % int(profile_store.get_highest_mode_level_for_display())
	_rank.text = str(profile_store.get_rank_label_for_display())
	var card_visual: Dictionary = appearance.get("profile_card", {}).get("visual", {})
	_rank.add_theme_color_override("font_color", card_visual.get("rank_color", E5OriginalTheme.GOLD))
	var rank_index := int(profile_store.get_rank_index_for_display())
	for i in _status_lights.size():
		var active := i < mini(5, rank_index)
		_status_lights[i].add_theme_color_override("font_color", E5OriginalTheme.GOLD if active else Color(
			E5OriginalTheme.CYAN.r, E5OriginalTheme.CYAN.g, E5OriginalTheme.CYAN.b, 0.30))
	var modes := ["花式", "竞速", "DIY"]
	for i in _progress_labels.size():
		var progress: Dictionary = profile_store.get_mode_progress_for_display(modes[i])
		_progress_labels[i].text = "%s  Lv.%d  ·  总进度 %d%%" % [modes[i],
			int(progress.get("等级", 1)), roundi(ExpSystemScript.overall_progress_ratio(progress) * 100.0)]

func _apply_card_theme(card_appearance: Dictionary) -> void:
	var settings_store = _root_service("SettingsStore")
	var performance_mode := bool(settings_store.performance_mode) if settings_store != null else false
	_card_fx.set_appearance(card_appearance)
	_card_fx.set_performance_mode(performance_mode)

	# 旧节点只保留兼容名称；玩家卡视觉统一由 RewardProfileCard 纯代码绘制。
	_card_art.texture = null
	_card_art.visible = false
	_frame.fill_color = Color.TRANSPARENT
	_frame.header_color = Color.TRANSPARENT
	_frame.border_color = Color.TRANSPARENT
	_frame.secondary_color = Color.TRANSPARENT
	_frame.inner_color = Color.TRANSPARENT
	_frame.scanline_color = Color.TRANSPARENT
	_frame.show_scanlines = false
	_frame.show_corner_marks = false
	_frame.show_side_ticks = false
	_frame.queue_redraw()

func set_loadout_preview(loadout: Dictionary) -> void:
	_preview_loadout = loadout.duplicate(true)
	_resolver.invalidate()
	refresh()

func clear_loadout_preview() -> void:
	_preview_loadout.clear()
	_resolver.invalidate()
	refresh()

func avatar_node() -> TextureRect:
	return _avatar

func title_badge_node() -> RewardTitleBadge:
	return _title_badge

func avatar_frame_node() -> RewardAvatarFrame:
	return _avatar_frame
