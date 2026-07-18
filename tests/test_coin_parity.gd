extends SceneTree
## 投币页关键可见性必须与原版状态机一致。

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


func _check(condition: bool, name: String) -> void:
	if condition:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s" % name)


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	await process_frame

	var game_state := root.get_node("GameState")
	game_state.persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SettingsStore").persist_enabled = false
	game_state.credits = 0

	var scene: Control = load("res://scenes/coin/coin.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._refresh(false)
	_check(not scene.get_node("Logo").visible, "0 credit hides logo")
	_check(not scene.get_node("OnePlayerButton").visible, "0 credit hides player buttons")

	game_state.credits = 1
	scene._refresh(false)
	_check(scene.get_node("Logo").visible, "partial credit shows logo")
	_check(not scene.get_node("OnePlayerButton").visible, "partial credit hides player buttons")

	game_state.credits = game_state.CREDITS_PER_GAME
	scene._refresh(false)
	_check(scene.get_node("Logo").visible, "enough credit shows logo")
	_check(scene.get_node("OnePlayerButton").visible, "enough credit shows player buttons")

	root.remove_child(scene)
	scene.free()
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.1).timeout
	print("ALL COIN PARITY TESTS PASSED" if _failures == 0 else "%d COIN PARITY TEST(S) FAILED" % _failures)
	quit(_failures)
