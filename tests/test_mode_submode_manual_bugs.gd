extends SceneTree
## 人工差异清单回归：大模式文案黑条/二次音效、子模式波浪与全体推开。

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

	var mode := (load("res://scenes/mode_select/mode_select.tscn") as PackedScene).instantiate() as Control
	root.add_child(mode)
	await process_frame
	var desc_bar := mode.get_node("DescriptionBar") as ColorRect
	var prompt := mode.get_node("ModePrompt") as Label
	_check(absf(desc_bar.position.x) <= 0.1 and absf(desc_bar.size.x - 1920.0) <= 0.1,
		"大模式提示黑条贯穿 1920 全屏", str(Rect2(desc_bar.position, desc_bar.size)))
	_check(desc_bar.position.y >= 600.0 and desc_bar.position.y + desc_bar.size.y <= 669.0,
		"大模式提示黑条位于 Banner 下方和按钮上方，不遮挡大图", str(Rect2(desc_bar.position, desc_bar.size)))
	_check(prompt.position.is_equal_approx(desc_bar.position) and prompt.size.is_equal_approx(desc_bar.size),
		"提示文字与全宽黑条使用同一矩形", "%s / %s" % [Rect2(prompt.position, prompt.size), Rect2(desc_bar.position, desc_bar.size)])

	mode.call("_select", 2) # 派对：未开放，确认不会切场景，便于验证二次音效。
	await create_timer(0.05).timeout
	root.get_node("AudioDirector").release_for_shutdown()
	mode.call("_confirm_selected")
	await process_frame
	var sfx_players: Array = root.get_node("AudioDirector").get("_sfx_players")
	var confirm_streams := sfx_players.filter(func(player): return player.stream != null).size()
	_check(confirm_streams > 0, "大模式二次确认播放按钮音效", str(confirm_streams))
	root.get_node("AudioDirector").release_for_shutdown()
	root.remove_child(mode)
	mode.free()
	await process_frame

	var sub_script := load("res://scenes/submode_select/submode_select.gd") as Script
	var constants := sub_script.get_script_constant_map()
	_check(is_equal_approx(float(constants.get("IDLE_AMPLITUDE", -1.0)), 6.0),
		"子模式波浪幅度与原版一致为 6px", str(constants.get("IDLE_AMPLITUDE")))
	_check(is_equal_approx(float(constants.get("IDLE_PERIOD_MS", -1.0)), 1100.0),
		"子模式波浪周期与原版一致为 1100ms", str(constants.get("IDLE_PERIOD_MS")))
	_check(is_equal_approx(float(constants.get("IDLE_PHASE_STEP", -1.0)), 0.55),
		"子模式相邻图标波浪相位差与原版一致为 0.55", str(constants.get("IDLE_PHASE_STEP")))

	root.get_node("GameState").big_mode = "花式"
	var submode := (load("res://scenes/submode_select/submode_select.tscn") as PackedScene).instantiate() as Control
	root.add_child(submode)
	await process_frame
	var loaded_items: Array = submode.get("_items")
	_check(not loaded_items.is_empty() and submode.has_method("texture_cache_ready_for_test") \
		and bool(submode.call("texture_cache_ready_for_test", str(loaded_items[0]))),
		"子模式大小图在场景进入时预热，切换选择不再同步读盘")
	# 构造两行非 DIY 测试项，验证选中后并非只移动邻居或同一行。
	submode.set("_items", ["学习", "表演", "疯狂", "club", "情侣", "混音", "学习", "表演"])
	submode.set("_page", 0)
	submode.call("_build_page")
	await create_timer(1.85).timeout
	var base_positions: Array = submode.get("_base_positions")
	var buttons: Array = submode.get("_buttons")
	submode.call("_select", 2)
	await create_timer(0.38).timeout
	var moved_count := 0
	var expected_moved := maxi(0, buttons.size() - 1)
	for i in buttons.size():
		if i == 2:
			continue
		if absf((buttons[i] as Control).position.x - (base_positions[i] as Vector2).x) > 1.0:
			moved_count += 1
	_check(moved_count == expected_moved,
		"子模式二次选中会推开全部其他图标，而非仅邻居/同一行", "%d / %d" % [moved_count, expected_moved])

	root.remove_child(submode)
	submode.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame
	print("ALL MODE/SUBMODE MANUAL BUG TESTS PASSED" if _failures == 0 else
		"%d MODE/SUBMODE MANUAL BUG TEST(S) FAILED" % _failures)
	quit(_failures)
