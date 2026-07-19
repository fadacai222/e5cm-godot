extends SceneTree
## 原版街机 UI 统一契约：切角框、搜索/筛选、选歌玩家 HUD 与全部 ESC 共用视觉系统。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SharedVideoBackground", "res://autoload/shared_video_background.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
	["GameState", "res://autoload/game_state.gd"],
	["ProfileStore", "res://autoload/profile_store.gd"],
	["SongLibrary", "res://autoload/song_library.gd"],
	["AudioDirector", "res://autoload/audio_director.gd"],
	["SceneRouter", "res://autoload/scene_router.gd"],
]

var _failures := 0
var _created: Array[Node] = []


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _find_button_by_text(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node as Button
	for child in node.get_children():
		var found := _find_button_by_text(child, text)
		if found != null:
			return found
	return null


func _flat_style(control: Control, style_name: String) -> StyleBoxFlat:
	if control == null:
		return null
	return control.get_theme_stylebox(style_name) as StyleBoxFlat


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame
	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false

	var frame := load("res://ui/e5_hud_frame.gd").new() as Control
	frame.size = Vector2(640, 360)
	root.add_child(frame)
	await process_frame
	_check(frame is E5HudFrame and float(frame.get("cut_size")) >= 12.0
		and bool(frame.get("show_scanlines")),
		"共享 HUD 框提供切角、扫描线和双主色绘制能力")
	root.remove_child(frame)
	frame.free()

	var animated_panel := Control.new()
	animated_panel.position = Vector2(100, 80)
	animated_panel.size = Vector2(320, 180)
	root.add_child(animated_panel)
	E5OriginalTheme.animate_in(animated_panel, Vector2(24, 0), 0.05)
	await create_timer(0.015).timeout
	E5OriginalTheme.animate_in(animated_panel, Vector2(24, 0), 0.05)
	await create_timer(0.08).timeout
	_check(animated_panel.position.distance_to(Vector2(100, 80)) < 0.1,
		"弹层快速重复打开不会累积位置漂移", str(animated_panel.position))
	root.remove_child(animated_panel)
	animated_panel.free()

	var filter := load("res://scenes/song_select/filter_panel.gd").new() as Control
	root.add_child(filter)
	await process_frame
	filter.call("open", ["学习", "疯狂"], func(_style: String): return [3, 6, 9], "学习", 6)
	await process_frame
	var filter_panel := filter.get_node_or_null("ContentPanel") as Panel
	var filter_frame := filter.get_node_or_null("ContentPanel/OriginalHudFrame") as E5HudFrame
	var filter_selected := _find_button_by_text(filter, "学习")
	var filter_style := _flat_style(filter_selected, "normal")
	_check(filter_panel != null and filter_frame != null
		and filter_frame.header_height > 100.0 and filter_frame.cut_size >= 18.0,
		"玩法/星级筛选使用原版切角标题框而非普通圆角弹窗")
	_check(filter_selected != null and filter_style != null
		and filter_style.corner_radius_top_left <= 2
		and filter_style.border_color.is_equal_approx(E5OriginalTheme.GOLD),
		"筛选选中态使用金色细边和小圆角",
		str(filter_style.border_color) if filter_style != null else "missing")

	var song_select := (load("res://scenes/song_select/song_select.tscn") as PackedScene).instantiate() as Control
	var top_bar := song_select.get_node_or_null("TopBar") as Control
	song_select.call("_build_top_profile_badge", top_bar)
	song_select.call("_build_search_overlay")
	var badge := top_bar.get_node_or_null("SongSelectProfileBadge") as Panel if top_bar else null
	var player_frame := badge.get_node_or_null("PlayerHudFrame") as E5HudFrame if badge else null
	var avatar := badge.get_node_or_null("Avatar") as TextureRect if badge else null
	var level := badge.get_node_or_null("Level") as Label if badge else null
	var status_count := 0
	if badge != null:
		for i in 5:
			if badge.get_node_or_null("StatusLight%d" % i) != null:
				status_count += 1
	_check(badge != null and player_frame != null and avatar != null
		and avatar.position.x > badge.size.x * 0.70 and level != null
		and level.text.begins_with("LV.") and status_count == 5,
		"选歌右上玩家信息为头像在右的横向街机 HUD，包含等级、段位和五格状态装饰")
	var search_panel := song_select.get_node_or_null("SongSearchOverlay/SearchPanel") as Panel
	var search_frame := song_select.get_node_or_null(
		"SongSearchOverlay/SearchPanel/OriginalSearchHudFrame") as E5HudFrame
	var search_input := song_select.get_node_or_null(
		"SongSearchOverlay/SearchPanel/SearchInput") as LineEdit
	var search_normal := _flat_style(search_input, "normal")
	var language_button := song_select.get_node_or_null(
		"SongSearchOverlay/SearchPanel/SearchLanguage全部") as Button
	var language_style := _flat_style(language_button, "normal")
	_check(search_panel != null and search_frame != null and search_frame.cut_size >= 20.0
		and search_input != null and search_normal != null
		and search_normal.corner_radius_top_left <= 2,
		"搜索菜单使用原版切角大面板和非默认输入框皮肤")
	_check(language_button != null and language_style != null
		and language_style.corner_radius_top_left <= 2,
		"搜索语言分类使用统一街机按钮皮肤")

	var menu: Node = load("res://ui/esc_menu.gd").new(true)
	root.add_child(menu)
	await process_frame
	var nav_frame := menu.get_node_or_null("ModernMenu/NavPanel/NavHudFrame") as E5HudFrame
	var content_frame := menu.get_node_or_null("ModernMenu/ContentPanel/ContentHudFrame") as E5HudFrame
	var original_texture := menu.get_node_or_null("OriginalSettingsTexture") as TextureRect
	var tab0 := menu.get_node_or_null("ModernMenu/NavPanel/Tab0") as Button
	var tab_style := _flat_style(tab0, "normal")
	_check(nav_frame != null and content_frame != null and original_texture != null
		and original_texture.texture != null,
		"全部 ESC 页面共用双切角框架并叠加原版设置页纹理")
	_check(tab0 != null and tab_style != null and tab_style.corner_radius_top_left <= 2,
		"ESC 导航不再使用大圆角通用卡片")
	menu.call("_set_tab", 4)
	await process_frame
	var identity_frame := menu.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/ProfileIdentityCard/IdentityHudFrame") as E5HudFrame
	var progress_frame := menu.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/ProfileProgressCard/ProgressHudFrame") as E5HudFrame
	_check(identity_frame != null and progress_frame != null,
		"ESC 用户资料与成长信息继续复用原版 HUD 框架")

	var select_menu: Node = load("res://ui/esc_menu.gd").new(false)
	root.add_child(select_menu)
	await process_frame
	_check(select_menu.get_node_or_null("SettingsInputBlocker") != null
		and select_menu.get_node_or_null("ModernMenu/NavPanel/NavHudFrame") is E5HudFrame
		and select_menu.get_node_or_null("ModernMenu/ContentPanel/ContentHudFrame") is E5HudFrame,
		"选歌场景 ESC 与游戏内 ESC 使用同一套原版框架")

	for node in [select_menu, menu, filter]:
		if is_instance_valid(node):
			if node.get_parent() == root:
				root.remove_child(node)
			node.free()
	if is_instance_valid(song_select):
		song_select.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.15).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL ORIGINAL ARCADE UI CONTRACT TESTS PASSED" if _failures == 0 else
		"%d ORIGINAL ARCADE UI CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
