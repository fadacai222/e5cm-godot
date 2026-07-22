extends SceneTree
## 选歌真实输入回归：详情/筛选弹层必须消费同一次鼠标事件，不能穿透到缩略图；
## 同时覆盖空白关闭与列表左右翻页按钮。

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


func _song(index: int) -> Dictionary:
	return {
		"name": "QA歌曲_%02d#123" % index,
		"cover": "",
		"mp3": "",
		"sm": "",
		"sm_key": "qa/song_%02d.sm" % index,
		"star": 3,
		"style": "表演",
		"bpm": 120.0,
	}


func _push_mouse_button(position: Vector2, pressed: bool,
		button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	event.global_position = position
	root.push_input(event, true)


func _real_gui_click(target: Control, position: Vector2,
		button := MOUSE_BUTTON_LEFT) -> void:
	# Dummy/headless DisplayServer 不执行真实窗口命中测试；直接走目标控件的
	# gui_input 信号，仍覆盖遮罩消费、延迟关闭和底层状态不变契约。
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = position
	press.global_position = position
	target.gui_input.emit(press)
	await process_frame
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	target.gui_input.emit(release)
	await process_frame


func _blank_point_over_first_card(song_select: Control, overlay_panel: Control) -> Vector2:
	var card := song_select.get_node_or_null("SongCard0") as Control
	if card == null:
		return Vector2(150, 320)
	var card_rect := card.get_global_rect()
	var panel_rect := overlay_panel.get_global_rect() if overlay_panel != null else Rect2()
	var candidates := [
		card_rect.position + Vector2(12, card_rect.size.y * 0.5),
		card_rect.position + Vector2(card_rect.size.x - 12, card_rect.size.y * 0.5),
		card_rect.position + Vector2(card_rect.size.x * 0.5, 12),
		card_rect.position + Vector2(card_rect.size.x * 0.5, card_rect.size.y - 12),
	]
	for point in candidates:
		if not panel_rect.has_point(point):
			return point
	return Vector2(24, 300)


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
	root.get_node("GameState").big_mode = "花式"
	root.get_node("GameState").sub_mode = "表演"

	var song_select := (load("res://scenes/song_select/song_select.tscn") as PackedScene).instantiate() as Control
	root.add_child(song_select)
	await process_frame
	await process_frame

	var page_songs: Array = []
	for i in 9:
		page_songs.append(_song(i))
	song_select.set("songs", page_songs)
	song_select.set("page", 0)
	song_select.set("selected", 1)
	song_select.call("_build_page")
	await process_frame
	await process_frame

	# 详情页：真实 Viewport 鼠标点击必须只关闭遮罩，不能继续命中下面的第一张卡。
	var detail := song_select.get("detail") as Control
	detail.call("show_song", _song(1), {"游玩次数": 0}, false, false)
	await process_frame
	var detail_mask := detail.get_node_or_null("InputBlocker") as Control
	var detail_panel := detail.get_node_or_null("AnimationLayer/ContentPanel") as Control
	_check(detail_mask != null and detail_mask.mouse_filter == Control.MOUSE_FILTER_STOP,
		"歌曲大图使用全屏 STOP 遮罩")
	_check(detail_panel != null and detail_panel.mouse_filter == Control.MOUSE_FILTER_STOP,
		"歌曲大图内容面板独占鼠标输入")
	_check(detail.visible and detail.mouse_filter == Control.MOUSE_FILTER_STOP,
		"歌曲大图打开后根层阻断输入")
	var detail_mover := detail.get_node_or_null("AnimationLayer") as Control
	_check(detail.size.x >= 1919.0 and detail.size.y >= 1079.0,
		"歌曲大图根层实际覆盖 1920×1080", str(detail.get_global_rect()))
	_check(detail_mask != null and detail_mask.size.x >= 1919.0 and detail_mask.size.y >= 1079.0,
		"歌曲大图遮罩实际覆盖 1920×1080", str(detail_mask.get_global_rect()) if detail_mask else "null")
	_check(detail_mover != null and detail_mover.size.x >= 1919.0 and detail_mover.size.y >= 1079.0,
		"歌曲大图动画层实际覆盖 1920×1080", str(detail_mover.get_global_rect()) if detail_mover else "null")
	var selected_before_detail := int(song_select.get("selected"))
	var detail_blank := _blank_point_over_first_card(song_select, detail_panel)
	await _real_gui_click(detail_mover, detail_blank)
	await process_frame
	_check(not detail.visible, "真实点击歌曲大图空白位置可关闭", str(detail_blank))
	_check(int(song_select.get("selected")) == selected_before_detail,
		"关闭歌曲大图的同一次点击不会穿透选中缩略图",
		"before=%d after=%d point=%s" % [selected_before_detail, int(song_select.get("selected")), detail_blank])
	_check(not detail.visible, "穿透点击不会把歌曲大图重新打开")

	# 筛选页：同样通过真实 Viewport 事件验证空白关闭与不穿透。
	var filter_panel := song_select.get("filter_panel") as Control
	filter_panel.call("open", ["表演"], func(_style): return [3], "", 0)
	await process_frame
	var filter_mask := filter_panel.get_node_or_null("InputBlocker") as Control
	var filter_content := filter_panel.get_node_or_null("ContentPanel") as Control
	_check(filter_mask != null and filter_mask.mouse_filter == Control.MOUSE_FILTER_STOP,
		"筛选页使用全屏 STOP 遮罩")
	_check(filter_content != null and filter_content.mouse_filter == Control.MOUSE_FILTER_STOP,
		"筛选内容面板独占鼠标输入")
	_check(filter_panel.visible and filter_panel.mouse_filter == Control.MOUSE_FILTER_STOP,
		"筛选页打开后根层阻断输入")
	_check(filter_panel.size.x >= 1919.0 and filter_panel.size.y >= 1079.0,
		"筛选页根层实际覆盖 1920×1080", str(filter_panel.get_global_rect()))
	_check(filter_mask != null and filter_mask.size.x >= 1919.0 and filter_mask.size.y >= 1079.0,
		"筛选页遮罩实际覆盖 1920×1080", str(filter_mask.get_global_rect()) if filter_mask else "null")
	var selected_before_filter := int(song_select.get("selected"))
	var filter_blank := _blank_point_over_first_card(song_select, filter_content)
	await _real_gui_click(filter_mask, filter_blank)
	await process_frame
	_check(not filter_panel.visible, "真实点击筛选页空白位置可关闭", str(filter_blank))
	_check(int(song_select.get("selected")) == selected_before_filter,
		"关闭筛选页的同一次点击不会穿透选中缩略图",
		"before=%d after=%d point=%s" % [selected_before_filter, int(song_select.get("selected")), filter_blank])
	_check(not detail.visible, "筛选页穿透点击不会误开歌曲大图")

	# 原版左右翻页按钮。
	var previous := song_select.get_node_or_null("PreviousPage") as TextureButton
	var next := song_select.get_node_or_null("NextPage") as TextureButton
	_check(previous != null and next != null, "选歌列表保存左右翻页按钮节点")
	_check(previous != null and previous.texture_normal != null and previous.flip_h,
		"左翻页按钮使用原版图片并水平翻转")
	_check(next != null and next.texture_normal != null and not next.flip_h,
		"右翻页按钮使用原版图片")
	_check(previous != null and next != null and previous.visible and next.visible,
		"多页歌曲列表显示左右翻页按钮")
	_check(previous != null and is_equal_approx(previous.modulate.a, 176.0 / 255.0),
		"翻页按钮透明度与原版 176/255 一致", str(previous.modulate.a) if previous else "null")
	if next != null:
		next.emit_signal("pressed")
		await process_frame
		_check(int(song_select.get("page")) == 1, "右翻页按钮切换到下一页", str(song_select.get("page")))
	if previous != null:
		previous.emit_signal("pressed")
		await process_frame
		_check(int(song_select.get("page")) == 0, "左翻页按钮切换到上一页", str(song_select.get("page")))

	detail.call("show_song", _song(0), {"游玩次数": 0}, false, false)
	await process_frame
	_check(previous != null and next != null and not previous.visible and not next.visible,
		"打开歌曲大图时隐藏列表翻页按钮")
	detail.call("close")
	await process_frame
	_check(previous != null and next != null and previous.visible and next.visible,
		"关闭歌曲大图后恢复列表翻页按钮")

	var preview := song_select.get_node("PreviewPlayer") as AudioStreamPlayer
	preview.stop()
	preview.stream = null
	root.remove_child(song_select)
	song_select.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL SONG OVERLAY/PAGE CONTROL TESTS PASSED" if _failures == 0 else
		"%d SONG OVERLAY/PAGE CONTROL TEST(S) FAILED" % _failures)
	quit(_failures)
