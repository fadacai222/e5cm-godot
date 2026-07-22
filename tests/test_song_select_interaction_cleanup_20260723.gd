extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String, detail := "") -> void:
	if ok:
		print("[PASS] ", message)
		return
	failures += 1
	push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _find_button_text(node: Node, expected: String) -> Button:
	if node is Button and (node as Button).text == expected:
		return node as Button
	for child in node.get_children():
		var found := _find_button_text(child, expected)
		if found != null:
			return found
	return null

func _left_click(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event

func _run() -> void:
	var profile_store = root.get_node("ProfileStore")
	var game_state = root.get_node("GameState")
	var audio_director = root.get_node("AudioDirector")
	var original_favorites: Array = profile_store.favorites.duplicate(true)
	var original_mode: String = str(game_state.big_mode)
	var original_submode: String = str(game_state.sub_mode)

	var filter_panel := load("res://scenes/song_select/filter_panel.gd").new() as Control
	root.add_child(filter_panel)
	await process_frame
	filter_panel.call("open", ["表演"], func(_style, _speed): return [5, 7, 9], "", 7, "all")
	await process_frame
	var all_stars := _find_button_text(filter_panel, "ALL  全部星级")
	_check(all_stars != null, "星级筛选提供明确的全部星级选项")
	if all_stars != null:
		all_stars.pressed.emit()
		await process_frame
		_check(not str(filter_panel.call("summary_text_for_test")).contains("7★"),
			"点击全部星级会清除现有星级条件")
	root.remove_child(filter_panel)
	filter_panel.free()

	game_state.big_mode = "竞速"
	game_state.sub_mode = "不存在的测试分类"
	var song_select := (load("res://scenes/song_select/song_select.tscn") as PackedScene).instantiate() as Control
	root.add_child(song_select)
	await process_frame
	await process_frame

	var search_overlay := song_select.get_node_or_null("SongSearchOverlay") as Control
	var search_dim := song_select.get_node_or_null("SongSearchOverlay/SearchInputBlocker") as Control
	var search_panel := song_select.get_node_or_null("SongSearchOverlay/SearchPanel") as Control
	_check(song_select.get_node_or_null("SongSearchOverlay/SearchPanel/SearchCancelButton") == null,
		"搜索弹窗移除多余的取消按钮")
	if search_overlay != null and search_dim != null:
		search_overlay.visible = true
		search_dim.gui_input.emit(_left_click(Vector2(80, 80)))
		await process_frame
		_check(not search_overlay.visible, "点击搜索弹窗外部遮罩会关闭搜索")
	if search_overlay != null and search_panel != null:
		search_overlay.visible = true
		search_panel.gui_input.emit(_left_click(Vector2(520, 300)))
		await process_frame
		_check(search_overlay.visible, "点击搜索弹窗内容区域不会误关闭")
		song_select.call("_close_search")

	var song := {
		"sm_key": "tests/favorite-only.sm", "name": "收藏夹测试歌曲", "star": 7,
		"bpm": 128.0, "cover": "", "style": "表演", "sm": "", "mp3": "",
	}
	profile_store.favorites = [str(song["sm_key"])]
	song_select.set("songs", [song])
	song_select.set("page", 0)
	song_select.set("selected", 0)
	song_select.set("favorites_mode", true)
	song_select.call("_refresh_detail", false)
	await process_frame
	var detail = song_select.get("detail")
	var favorite_button := detail.get("_btn_fav") as TextureButton if detail != null else null
	_check(favorite_button != null and not favorite_button.visible,
		"收藏夹详情页隐藏添加或移除收藏按钮")

	profile_store.favorites = original_favorites
	game_state.big_mode = original_mode
	game_state.sub_mode = original_submode
	if song_select.get_parent() == root:
		root.remove_child(song_select)
	song_select.free()
	if audio_director.has_method("release_for_shutdown"):
		audio_director.release_for_shutdown()
	await process_frame
	await create_timer(0.05).timeout
	print("ALL SONG SELECT INTERACTION CLEANUP TESTS PASSED" if failures == 0 else
		"%d SONG SELECT INTERACTION CLEANUP TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)
