extends SceneTree
## 选歌与 ESC 设置交互契约：星级缩略图、实时预览、踏板重绑与开始游戏音效。

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


func _song(star: int) -> Dictionary:
	return {
		"name": "交互契约测试曲",
		"cover": "",
		"mp3": "",
		"sm": "",
		"sm_key": "qa/song-select-settings.sm",
		"star": star,
		"style": "双踏板",
		"charttype": "pump-double",
		"bpm": 128.0,
	}


func _binding_signature(binding: Variant) -> String:
	if binding is int:
		return "key:%d" % int(binding)
	if binding is Dictionary:
		var data: Dictionary = binding
		return "%s:%d:%d" % [str(data.get("type", "")), int(data.get("device", -1)),
			int(data.get("button", -1))]
	return ""


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame

	var settings = root.get_node("SettingsStore")
	settings.persist_enabled = false
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("GameState").big_mode = "竞速"
	root.get_node("GameState").sub_mode = "club"
	root.get_node("GameState").player_count = 1

	var original_skin := str(settings.arrow_skin)
	var original_size := int(settings.arrow_size_percent)
	var original_background_mode := str(settings.background_mode)
	var original_brightness := int(settings.background_brightness_level)
	var original_bindings: Dictionary = settings.key_bindings.duplicate(true)

	# 1. 小卡星级必须按素材比例绘制；超过 10 星仍显示真实星星，不能改成“×N”。
	var song_select := (load("res://scenes/song_select/song_select.tscn") as PackedScene).instantiate() as Control
	song_select.size = Vector2(1920, 1080)
	root.add_child(song_select)
	await process_frame
	song_select.set("songs", [_song(12)])
	song_select.set("selected", 0)
	song_select.call("_build_page")
	await process_frame
	var card := song_select.get_node_or_null("SongCard0") as Control
	var stars: Array[Node] = []
	var multiplier_found := false
	if card != null:
		for child in card.get_children():
			if child.name.begins_with("Star"):
				stars.append(child)
			if child is Label and str((child as Label).text).begins_with("×"):
				multiplier_found = true
	_check(stars.size() == 12 and not multiplier_found,
		"12 星缩略图绘制两排真实星星，不使用 ×N 代替",
		"stars=%d multiplier=%s" % [stars.size(), multiplier_found])
	if not stars.is_empty():
		var star_view := stars[0] as TextureRect
		var texture_size := star_view.texture.get_size() if star_view.texture != null else Vector2.ZERO
		var texture_ratio := texture_size.x / maxf(1.0, texture_size.y)
		var view_ratio := star_view.size.x / maxf(1.0, star_view.size.y)
		_check(absf(view_ratio - texture_ratio) <= 0.02,
			"缩略图星星保持原素材宽高比", "view=%s texture=%s" % [view_ratio, texture_ratio])

	# 2. 箭头皮肤和尺寸修改后，右侧预览必须同帧/下一帧重建，并与实战缩放一致。
	settings.arrow_size_percent = 100
	var esc: CanvasLayer = load("res://ui/esc_menu.gd").new(false)
	root.add_child(esc)
	await process_frame
	esc.call("_set_tab", 0)
	await process_frame
	var preview_arrow_before := esc.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/LivePreview/PreviewLane0/PreviewArrow0") as TextureRect
	var preview_size_before := preview_arrow_before.size if preview_arrow_before != null else Vector2.ZERO
	esc.call("_step_arrow_size", 1)
	esc.call("_refresh_all")
	await process_frame
	var preview_arrow_after := esc.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/LivePreview/PreviewLane0/PreviewArrow0") as TextureRect
	var preview_footer := esc.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/LivePreview/PreviewFooter") as Label
	_check(preview_size_before.x > 0.0 and preview_arrow_after != null
		and preview_arrow_after.size.x > preview_size_before.x,
		"箭头大小修改后实时预览立即放大",
		"before=%s after=%s" % [preview_size_before,
			preview_arrow_after.size if preview_arrow_after else null])
	_check(preview_footer != null and preview_footer.text.contains("110%"),
		"箭头预览页脚同步显示最新尺寸", preview_footer.text if preview_footer else "null")

	var field: Node2D = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(field)
	settings.arrow_size_percent = 100
	field.call("setup", 5, 4.0)
	var scale_100: float = float((field.get("_receptors") as Array)[0].scale.x)
	settings.arrow_size_percent = 110
	field.call("setup", 5, 4.0)
	var scale_110: float = float((field.get("_receptors") as Array)[0].scale.x)
	_check(scale_110 > scale_100 * 1.09,
		"实战箭头使用与预览相同的尺寸百分比", "100=%s 110=%s" % [scale_100, scale_110])
	field.free()

	# 3. 背景预览必须使用真实图片/视频/唱片结构，并叠加与 Gameplay 相同的亮度蒙版。
	settings.background_mode = "动态背景"
	settings.background_brightness_level = 2
	esc.call("_set_tab", 1)
	await process_frame
	var dynamic_preview := esc.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/LivePreview/PreviewCanvas/PreviewDynamicBackground")
	var brightness_dim := esc.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/LivePreview/PreviewCanvas/BrightnessDim") as ColorRect
	_check(dynamic_preview != null, "动态背景预览使用唱片背景结构而非血条占位素材")
	_check(brightness_dim != null and is_equal_approx(brightness_dim.color.a, 0.65),
		"背景预览亮度蒙版与 Gameplay 计算一致",
		str(brightness_dim.color.a) if brightness_dim else "null")

	settings.background_mode = "图片"
	esc.call("_refresh_all")
	await process_frame
	_check(esc.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/LivePreview/PreviewCanvas/PreviewImage") != null,
		"图片模式实时预览真实图片素材")
	settings.background_mode = "视频"
	esc.call("_refresh_all")
	await process_frame
	_check(esc.get_node_or_null(
		"ModernMenu/ContentPanel/ContentBody/LivePreview/PreviewCanvas/PreviewVideo") != null,
		"视频模式实时预览真实视频素材")

	# 4. 键位页接受踏板/手柄按钮，并用同一冲突规则阻止静默覆盖。
	esc.call("_set_tab", 3)
	await process_frame
	var joy_event := InputEventJoypadButton.new()
	joy_event.device = 0
	joy_event.button_index = JOY_BUTTON_A
	joy_event.pressed = true
	esc.call("_start_rebind", "p1_lane0")
	var joy_handled := bool(esc.call("_handle_binding_input", joy_event))
	var p1_binding: Array = settings.key_bindings.get("p1_lane0", [])
	_check(joy_handled and p1_binding.size() == 1
		and _binding_signature(p1_binding[0]) == "joy_button:0:%d" % JOY_BUTTON_A,
		"踏板/手柄按钮可即时绑定并写入 InputMap", str(p1_binding))
	settings.key_bindings["p2_lane0"] = [{"type": "joy_button", "device": 0, "button": JOY_BUTTON_B}]
	settings.apply_input_map()
	var conflict_event := InputEventJoypadButton.new()
	conflict_event.device = 0
	conflict_event.button_index = JOY_BUTTON_B
	conflict_event.pressed = true
	esc.call("_start_rebind", "p1_lane0")
	esc.call("_handle_binding_input", conflict_event)
	var p1_after_conflict: Array = settings.key_bindings.get("p1_lane0", [])
	_check(_binding_signature(p1_after_conflict[0]) == "joy_button:0:%d" % JOY_BUTTON_A,
		"冲突踏板按钮不会覆盖现有绑定", str(p1_after_conflict))

	# 5. 只有详情确认进入加载页时播放原版开始游戏音效，并留下语义事件。
	root.get_node("AudioDirector").clear_test_events()
	root.get_node("SceneRouter").set("_busy", true) # 阻止本测试真正切场，只验证确认行为。
	song_select.call("_start_song")
	var audio_events: Array = root.get_node("AudioDirector").get_test_events()
	var start_event: Dictionary = audio_events[0] if not audio_events.is_empty() else {}
	_check(start_event.get("eventKey", "") == "song_select.start_game"
		and str(start_event.get("path", "")) == str(root.get_node("AssetLoader").sound("开始游戏")),
		"详情确认使用原版开始游戏音效且不复用普通按钮音", str(audio_events))
	root.get_node("SceneRouter").set("_busy", false)

	# 恢复测试前设置，避免污染后续测试。
	settings.arrow_skin = original_skin
	settings.arrow_size_percent = original_size
	settings.background_mode = original_background_mode
	settings.background_brightness_level = original_brightness
	settings.key_bindings = original_bindings
	settings.apply_input_map()

	if is_instance_valid(esc):
		esc.free()
	if is_instance_valid(song_select):
		var preview := song_select.get_node_or_null("PreviewPlayer") as AudioStreamPlayer
		if preview != null:
			preview.stop()
			preview.stream = null
		song_select.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL SONG SELECT/SETTINGS CONTRACT TESTS PASSED" if _failures == 0 else
		"%d SONG SELECT/SETTINGS CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
