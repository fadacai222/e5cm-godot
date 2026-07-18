extends SceneTree
## 原版选歌列表视觉契约：1920×1080 卡片网格、Top 左侧图标、玻璃选中态、信息条与底栏。

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


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [message, detail])


func _near_rect(control: Control, expected: Rect2, tolerance := 1.1) -> bool:
	return control != null \
		and control.position.distance_to(expected.position) <= tolerance \
		and control.size.distance_to(expected.size) <= tolerance


func _song(index: int) -> Dictionary:
	return {
		"name": "视觉_歌曲_%02d#123" % index,
		"cover": "",
		"mp3": "",
		"sm": "",
		"sm_key": "qa/visual_%02d.sm" % index,
		"star": 6,
		"style": "学习",
		"bpm": 128.0,
	}


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
	# 故意使用别名，锁住原版同款归一化规则。
	root.get_node("GameState").big_mode = "Fancy 花式"
	root.get_node("GameState").sub_mode = "学习模式"
	root.get_node("GameState").player_count = 1

	var song_select := (load("res://scenes/song_select/song_select.tscn") as PackedScene).instantiate() as Control
	song_select.set_anchors_preset(Control.PRESET_TOP_LEFT)
	song_select.size = Vector2(1920, 1080)
	root.add_child(song_select)
	# 首次运行可能要建立新版搜索侧车；等待真实加载完成，不依赖固定两帧竞态。
	for _frame in 300:
		await process_frame
		var loading := song_select.get_node_or_null("SongLoadingOverlay") as Control
		if loading != null and not loading.visible:
			break
	var songs: Array = []
	for i in 8:
		songs.append(_song(i))
	song_select.set("songs", songs)
	song_select.set("selected", 0)
	song_select.call("_build_page")
	await process_frame
	await process_frame

	var guide := song_select.get_node_or_null("SongGrid") as Control
	_check(guide != null and not guide.visible, "运行时不显示调试网格边框")
	var card0 := song_select.get_node_or_null("SongCard0") as Control
	var card4 := song_select.get_node_or_null("SongCard4") as Control
	_check(_near_rect(card0, Rect2(121, 181, 403, 302)),
		"第一排卡片使用原版实际 4:3 框坐标", str(card0.get_rect()) if card0 else "null")
	_check(_near_rect(card4, Rect2(121, 539, 403, 302)),
		"第二排卡片使用原版实际 4:3 框坐标", str(card4.get_rect()) if card4 else "null")

	var mode_holder := song_select.get_node_or_null("TopBar/ModeBadge") as Control
	var sub_holder := song_select.get_node_or_null("TopBar/SubmodeBadge") as Control
	var mode_view := mode_holder.get_node_or_null("BadgeTexture") as TextureRect if mode_holder else null
	var sub_view := sub_holder.get_node_or_null("BadgeTexture") as TextureRect if sub_holder else null
	_check(mode_holder != null and absf(mode_holder.position.x - 192.0) <= 1.0,
		"Top 左侧大模式图从原版 x=10% 屏宽开始", str(mode_holder.position) if mode_holder else "null")
	_check(mode_view != null and mode_view.texture != null and mode_view.stretch_mode == TextureRect.STRETCH_SCALE,
		"大模式图使用原版非等比横向加宽")
	_check(sub_view != null and sub_view.texture != null and sub_view.stretch_mode == TextureRect.STRETCH_SCALE,
		"“学习模式”别名能正确绑定原版图片")
	_check(sub_holder != null and mode_holder != null \
		and absf(sub_holder.position.x - (mode_holder.position.x + mode_holder.size.x + 13.0)) <= 1.0,
		"Top 两张模式图按原版 13px 间距排列",
		"mode=%s sub=%s" % [mode_holder.get_rect() if mode_holder else null,
			sub_holder.get_rect() if sub_holder else null])

	var info_glass := card0.get_node_or_null("InfoGlass") as ColorRect if card0 else null
	var title := card0.get_node_or_null("SongName") as Label if card0 else null
	var underlay := card0.get_node_or_null("HoverUnderlay") as Control if card0 else null
	var glass := card0.get_node_or_null("SelectionGlass") as Control if card0 else null
	var card_mode_badge := card0.get_node_or_null("ModeBadge") as TextureRect if card0 else null
	_check(info_glass != null and is_equal_approx(info_glass.color.a, 118.0 / 255.0),
		"缩略图信息条使用原版 118/255 透明黑", str(info_glass.color.a) if info_glass else "null")
	_check(title != null and title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"缩略图歌名居中排列")
	_check(title != null and not title.text.contains("_") and not title.text.contains("#123"),
		"缩略图歌名按原版去下划线与尾部序号", title.text if title else "null")
	_check(underlay != null and glass != null and underlay.visible and glass.visible,
		"选中卡片包含原版半透明玻璃底光与叠层")
	_check(card_mode_badge != null and card_mode_badge.texture != null,
		"DIY/复合谱缩略图使用原版玩法模式角标")

	var bottom_expected := {
		"FilterButton": Rect2(94, 908, 122, 153),
		"FavoriteButton": Rect2(240, 908, 122, 153),
		"AllButton": Rect2(386, 908, 122, 153),
		"ReselectButton": Rect2(532, 908, 122, 153),
		"SearchButton": Rect2(678, 908, 122, 153),
		"JoinPlayerButton": Rect2(1558, 908, 122, 153),
		"SettingsButton": Rect2(1704, 908, 122, 153),
	}
	for node_name in bottom_expected:
		var control := song_select.get_node_or_null(node_name) as Control
		_check(_near_rect(control, bottom_expected[node_name]),
			"底栏 %s 使用原版槽位" % node_name,
			str(control.get_rect()) if control else "null")
	var filter_label := song_select.get_node_or_null("FilterButton/ActionLabel") as Label
	var favorite_label := song_select.get_node_or_null("FavoriteButton/ActionLabel") as Label
	var search_label := song_select.get_node_or_null("SearchButton/ActionLabel") as Label
	var search_icon := song_select.get_node_or_null("SearchButton/ActionIcon") as Control
	var reselect_icon := song_select.get_node_or_null("ReselectButton/ActionIcon") as Control
	var join_label := song_select.get_node_or_null("JoinPlayerButton/ActionLabel") as Label
	_check(filter_label != null and filter_label.text in ["歌曲分类", "筛选中"],
		"歌曲分类按钮恢复原版底部文字")
	_check(favorite_label != null and favorite_label.text in ["收藏夹", "退出收藏夹"],
		"收藏夹按钮恢复原版底部文字")
	_check(search_label != null and search_label.text == "搜索歌曲",
		"选歌底栏提供歌曲/歌手关键词搜索入口")
	_check(search_icon != null and search_icon is NeonSearchIcon \
		and reselect_icon != null and not (reselect_icon is NeonSearchIcon),
		"搜索按钮使用独立霓虹放大镜，不再复用重选模式图片")
	_check(search_label != null and search_icon != null \
		and search_label.position.y >= search_icon.position.y + search_icon.size.y - 2.0,
		"搜索按钮图标与文字按上下区域垂直对齐")
	_check(join_label != null and join_label.text == "2P加入",
		"1P 对局底栏显示原版 2P加入")
	_check(song_select.has_method("reselect_target_for_test") \
		and str(song_select.call("reselect_target_for_test")) == "mode_select",
		"选歌“重选模式”返回大模式选择，而非当前子模式页")
	var loading_overlay := song_select.get_node_or_null("SongLoadingOverlay") as Control
	var search_overlay := song_select.get_node_or_null("SongSearchOverlay") as Control
	var loading_bar := song_select.get("_loading_bar") as ProgressBar
	var search_input := song_select.get("_search_input") as LineEdit
	var search_progress := song_select.get("_search_progress_bar") as ProgressBar
	var search_percent := song_select.get("_search_progress_percent") as Label
	_check(loading_overlay != null and loading_bar != null,
		"选歌入场包含真实百分比加载遮罩和进度条")
	_check(search_overlay != null and search_input != null \
		and search_input.placeholder_text.contains("歌名"),
		"搜索弹层提供歌名/歌手输入框")
	_check(search_progress != null and search_percent != null,
		"搜索弹层包含实时百分比和进度条")
	var search_source := [_song(20), _song(21), _song(22)]
	search_source[0]["name"] = "最炫民族风"
	search_source[0]["artist"] = "凤凰传奇"
	search_source[0]["folder"] = "folk_a"
	search_source[1]["name"] = "奢香夫人"
	search_source[1]["artist"] = "凤凰传奇"
	search_source[1]["folder"] = "folk_b"
	search_source[2]["name"] = "海阔天空"
	search_source[2]["artist"] = "Beyond"
	search_source[2]["folder"] = "rock"
	song_select.set("_source_songs", search_source)
	song_select.set("favorites_mode", false)
	song_select.set("filter_style", "")
	song_select.set("filter_star", 0)
	song_select.call("_submit_search", "凤凰传奇")
	for _frame in 30:
		await process_frame
		if not bool(song_select.get("_search_running")):
			break
	var search_results: Array = song_select.get("songs")
	_check(search_results.size() == 2 and int(song_select.get("page")) == 0 \
		and int(song_select.get("selected")) == 0,
		"搜索歌手返回全部歌曲并自动跳到第一页首项", str(search_results))

	var preview := song_select.get_node("PreviewPlayer") as AudioStreamPlayer
	preview.stop()
	preview.stream = null
	root.remove_child(song_select)
	song_select.free()

	# 再次进入同一选歌场景必须直接复用 SongLibrary Autoload 内存列表。
	root.get_node("GameState").big_mode = "竞速"
	root.get_node("GameState").sub_mode = "club"
	var cached_fixture: Array = root.get_node("SongLibrary").get_songs("竞速", "club")
	_check(not cached_fixture.is_empty(), "缓存复用测试已准备真实歌曲列表")
	var cached_select := (load("res://scenes/song_select/song_select.tscn") as PackedScene).instantiate() as Control
	cached_select.set_anchors_preset(Control.PRESET_TOP_LEFT)
	cached_select.size = Vector2(1920, 1080)
	root.add_child(cached_select)
	await process_frame
	var cached_overlay := cached_select.get_node_or_null("SongLoadingOverlay") as Control
	var cached_source: Array = cached_select.get("_source_songs")
	_check(cached_overlay != null and not cached_overlay.visible and not cached_source.is_empty(),
		"再次进入选歌场景直接复用内存歌曲列表，不重新显示全库加载遮罩",
		"overlay=%s songs=%d" % [cached_overlay.visible if cached_overlay else null, cached_source.size()])
	var cached_preview := cached_select.get_node_or_null("PreviewPlayer") as AudioStreamPlayer
	if cached_preview != null:
		cached_preview.stop()
		cached_preview.stream = null
	root.remove_child(cached_select)
	cached_select.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL SONG SELECT VISUAL CONTRACT TESTS PASSED" if _failures == 0 else
		"%d SONG SELECT VISUAL CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
