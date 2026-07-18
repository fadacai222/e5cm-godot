extends SceneTree
## READY/GO、结算前成就与全局投币音效契约。

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


func _payload() -> Dictionary:
	var base := "res://assets/e5cm_runtime/songs/竞速/club/SPEED_CLUB#12356_1612#11"
	return {
		"sm": base.path_join("12356_1612 [SPEED_CLUB].sm"),
		"mp3": "", "cover": "", "name": "12356_1612 [SPEED_CLUB]", "star": 11,
		"mode": "竞速", "submode": "club", "sm_key": "qa/audio-contract.sm",
		"prefer_double": true, "couple": false, "target_charttype": "pump-double",
	}


func _events() -> Array:
	var director := root.get_node("AudioDirector")
	if director.has_method("get_test_events"):
		return director.call("get_test_events")
	return []


func _clear_events() -> void:
	var director := root.get_node("AudioDirector")
	if director.has_method("clear_test_events"):
		director.call("clear_test_events")


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
	settings.show_ready_animation = true
	settings.autoplay = true
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SceneRouter").payload = _payload()

	var director := root.get_node("AudioDirector")
	_check(director.has_method("clear_test_events") and director.has_method("get_test_events"),
		"AudioDirector 提供确定性音效事件记录")

	var gameplay := (load("res://scenes/gameplay/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	await process_frame
	await process_frame

	# 原版只在引导/背景板开始的 1.22 秒触发一次完整 READY/GO 音效。
	var ready = gameplay.get("ready_anim")
	_check(ready != null and ready.has_method("advance_for_test"),
		"准备动画支持复用正式时间轴的音效触发测试")
	_clear_events()
	if ready != null:
		ready.call("play")
		ready.call("advance_for_test", 1.21)
		_check(_events().is_empty(), "1.22 秒前不提前播放准备音效", str(_events()))
		ready.call("advance_for_test", 1.23)
		var ready_events := _events()
		_check(ready_events.size() == 1, "READY/GO 音效在引导开始时只播放一次",
			str(ready_events))
		if ready_events.size() == 1:
			_check(str(ready_events[0].get("eventKey", "")) == "gameplay.ready_sequence",
				"准备音效事件类型正确", str(ready_events[0]))
			_check(absf(float(ready_events[0].get("timelineSeconds", -1.0)) - 1.22) <= 0.001,
				"准备音效触发点精确为 1.22 秒", str(ready_events[0]))
		ready.call("advance_for_test", 4.57)
		_check(_events().size() == 1, "GO 与退场阶段不会重复播放准备音效",
			str(_events()))
		ready.call("stop")
		ready.call("advance_for_test", 4.57)
		_check(_events().size() == 1, "跳过/停止准备动画后不会残留延迟音效",
			str(_events()))

	# 全 P / 全连都复用原版“全连.mp3”，普通判定不触发，同局同成就去重。
	_clear_events()
	_check(gameplay.has_method("_play_achievement_sfx"),
		"Gameplay 提供结算前成就音效唯一入口")
	if gameplay.has_method("_play_achievement_sfx"):
		_check(not bool(gameplay.call("_play_achievement_sfx", "")),
			"普通 Perfect/Combo 不触发成就音效")
		_check(bool(gameplay.call("_play_achievement_sfx", "full_perfect")),
			"All Perfect 首次触发原版成就音效")
		_check(not bool(gameplay.call("_play_achievement_sfx", "full_perfect")),
			"同局 All Perfect 不重复播放")
		var achievement_events := _events()
		_check(achievement_events.size() == 1, "All Perfect 事件只记录一次",
			str(achievement_events))
		if achievement_events.size() == 1:
			_check(str(achievement_events[0].get("path", "")).ends_with(
				"冷资源/Buttonsound/全连.mp3"),
				"All Perfect 使用原版全连音效", str(achievement_events[0]))
		gameplay.call("_start")
		_clear_events()
		_check(bool(gameplay.call("_play_achievement_sfx", "full_combo")),
			"新一局 All Combo 可触发原版成就音效")
		_check(not bool(gameplay.call("_play_achievement_sfx", "full_combo")),
			"同局 All Combo 不重复播放")
		_check(_events().size() == 1 and
			str(_events()[0].get("path", "")).ends_with("冷资源/Buttonsound/全连.mp3"),
			"All Combo 使用原版全连音效且只播放一次", str(_events()))

	# 投币只由 GameState 的全局成功入口播放；零增量与键盘 echo 都不播放。
	var game_state := root.get_node("GameState")
	game_state.credits = 0
	_clear_events()
	var before := int(game_state.credits)
	var inserted := bool(game_state.call("insert_coin", 1))
	_check(inserted and int(game_state.credits) == before + 1,
		"实际增加 CREDIT 时投币成功")
	_check(_events().size() == 1 and
		str(_events()[0].get("eventKey", "")) == "global.coin_insert",
		"全局投币成功路径播放一次投币音效", str(_events()))
	_check(not bool(game_state.call("insert_coin", 0)),
		"CREDIT 未增加时返回失败")
	_check(_events().size() == 1, "CREDIT 未增加时不播放投币音效", str(_events()))

	var echo_event := InputEventKey.new()
	echo_event.keycode = KEY_F
	echo_event.pressed = true
	echo_event.echo = true
	game_state.call("_unhandled_input", echo_event)
	_check(int(game_state.credits) == before + 1 and _events().size() == 1,
		"长按产生的键盘重复事件不会连投或叠音", str(_events()))

	var coin_source := FileAccess.get_file_as_string("res://scenes/coin/coin.gd")
	_check(not coin_source.contains(
		"AudioDirector.play_sfx(AssetLoader.sound(\"投币音效\"))"),
		"投币页不再建立第二条重复投币音效路径")

	root.remove_child(gameplay)
	gameplay.free()
	if director.has_method("release_for_shutdown"):
		director.call("release_for_shutdown")
	await create_timer(0.3).timeout
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	await process_frame

	print("ALL AUDIO/COIN CONTRACT TESTS PASSED" if _failures == 0 else
		"%d AUDIO/COIN CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
