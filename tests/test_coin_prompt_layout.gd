extends SceneTree
## 投币提示闪烁与底部信用栏布局回归测试。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_coin_prompt_layout.gd

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
var _created_autoloads: Array[Node] = []


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created_autoloads.append(node)
	await process_frame

	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("GameState").credits = 0
	var coin: Control = load("res://scenes/coin/coin.tscn").instantiate()
	# 这些节点必须直接保存在 PackedScene 中；否则 Godot 编辑器只能看到空根节点，
	# 无法在 2D 视图里拖拽修改布局。
	for node_path in [
		"EditorPreviewBackground", "DimOverlay", "Logo", "HintLabel", "CoinKeyHint",
		"BottomCreditCenter/BottomCreditRow/CreditOnlineIcon",
		"BottomCreditCenter/BottomCreditRow/CreditLabel",
		"OnePlayerButton", "TwoPlayerButton",
	]:
		_check(coin.get_node_or_null(node_path) != null,
			"%s 已保存为可视化场景节点" % node_path)
	root.add_child(coin)
	for i in 3:
		await process_frame

	var hint: Label = coin.get("lbl_hint")
	_check(hint.text == "请投币！", "投币主提示沿用原版独立文案", hint.text)
	var coin_key_hint := coin.get_node_or_null("CoinKeyHint") as Label
	_check(coin_key_hint != null and coin_key_hint.text.ends_with("投币"),
		"投币快捷键独立显示在右上角", coin_key_hint.text if coin_key_hint else "null")
	var saw_hidden := false
	for i in 12:
		await create_timer(0.12).timeout
		saw_hidden = saw_hidden or not hint.visible
	_check(saw_hidden, "请投币提示按原版 1 秒硬切持续闪烁", str(hint.visible))

	var credit: Label = coin.get("lbl_credit")
	_check(credit.get_theme_color("font_color") == Color.WHITE, "CREDIT 字色为白色",
		str(credit.get_theme_color("font_color")))

	var row := coin.get_node_or_null("BottomCreditCenter/BottomCreditRow") as HBoxContainer
	_check(row != null, "联网图标与 CREDIT 使用同一布局组")
	if row != null:
		await process_frame
		var center_x := row.global_position.x + row.size.x * 0.5
		_check(absf(center_x - 960.0) <= 1.0, "联网图标与 CREDIT 整体水平居中", str(center_x))
		var icon := row.get_node_or_null("CreditOnlineIcon") as Control
		var label := row.get_node_or_null("CreditLabel") as Control
		_check(icon != null and label != null and icon.global_position.x < label.global_position.x,
			"联网图标位于 CREDIT 左侧")

	root.get_node("GameState").insert_coin(3)
	await create_timer(0.6).timeout
	_check(not hint.visible and bool(coin.get("_hint_blinking")) == false,
		"进入玩家选择后停止闪烁并隐藏底部投币文案", "%s / %s" % [hint.visible, coin.get("_hint_blinking")])
	_check(int(coin.get("_pedal_pick")) == 1, "投满后默认选中 1P", str(coin.get("_pedal_pick")))
	var one_player: TextureButton = coin.get("btn_1p")
	_check(one_player.modulate != Color.WHITE, "默认 1P 具有清楚的高亮反馈", str(one_player.modulate))
	var constants := (coin.get_script() as Script).get_script_constant_map()
	_check(constants.has("PICK_TOTAL_SEC") and is_equal_approx(float(constants["PICK_TOTAL_SEC"]), 0.32),
		"人数确认动画总时长为原版 0.32 秒")
	_check(constants.has("PICK_END_SCALE") and is_equal_approx(float(constants["PICK_END_SCALE"]), 4.0),
		"人数确认按钮最终放大到原版 4 倍")

	root.remove_child(coin)
	coin.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await create_timer(0.3).timeout
	for i in range(_created_autoloads.size() - 1, -1, -1):
		root.remove_child(_created_autoloads[i])
		_created_autoloads[i].free()
	await process_frame
	if _failures == 0:
		print("ALL COIN PROMPT LAYOUT TESTS PASSED")
	else:
		print("%d COIN PROMPT LAYOUT TEST(S) FAILED" % _failures)
	quit(_failures)
