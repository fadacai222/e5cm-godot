extends SceneTree
## 全场景冒烟测试：手动装配 autoload，逐个实例化核心场景，抓脚本运行错误。
## 运行：godot --headless --path . --script res://tests/test_scenes.gd
## 判定标准：输出中不出现 SCRIPT ERROR 即通过（由外层 grep 检查）。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SharedVideoBackground", "res://autoload/shared_video_background.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
	["GameState", "res://autoload/game_state.gd"],
	["TrainingSession", "res://autoload/training_session.gd"],
	["AnalyticsStore", "res://autoload/analytics_store.gd"],
	["ProfileStore", "res://autoload/profile_store.gd"],
	["SongLibrary", "res://autoload/song_library.gd"],
	["AudioDirector", "res://autoload/audio_director.gd"],
	["SceneRouter", "res://autoload/scene_router.gd"],
]

const SCENES := [
	"res://scenes/boot/boot.tscn",
	"res://scenes/coin/coin.tscn",
	"res://scenes/login/login.tscn",
	"res://scenes/profile/profile.tscn",
	"res://scenes/mode_select/mode_select.tscn",
	"res://scenes/submode_select/submode_select.tscn",
	"res://scenes/song_select/song_select.tscn",
	"res://scenes/training_setup/training_setup.tscn",
	"res://scenes/loading/loading.tscn",
	"res://scenes/gameplay/gameplay.tscn",
	"res://scenes/settlement/settlement.tscn",
]


func _initialize() -> void:
	var scene_filter := OS.get_environment("E5CM_TEST_SCENE").strip_edges().to_lower()
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
	var router := root.get_node("SceneRouter")
	game_state.big_mode = "竞速"
	game_state.sub_mode = "club"
	game_state.credits = 6

	var song_payload := {}
	var lib := root.get_node("SongLibrary")
	var songs: Array = lib.get_songs("竞速", "club")
	if not songs.is_empty():
		var s: Dictionary = songs[0]
		song_payload = {"sm": s["sm"], "mp3": s["mp3"], "cover": s["cover"],
			"name": s["name"], "star": s["star"], "mode": "竞速", "submode": "club",
			"sm_key": s["sm_key"], "prefer_double": true, "couple": false}

	for scene_path in SCENES:
		var key := str(scene_path).get_file().get_basename()
		if not scene_filter.is_empty() and key.to_lower() != scene_filter:
			continue
		# 准备载荷
		if key == "loading" or key == "gameplay":
			router.payload = song_payload.duplicate()
		elif key == "training_setup":
			router.payload = {"song": song_payload.duplicate()}
		elif key == "settlement":
			router.payload = {
				"曲目名": "测试曲", "sm_key": str(song_payload.get("sm_key", "")),
				"mode": "竞速", "submode": "club", "cover": str(song_payload.get("cover", "")),
				"star": 8, "本局最高分": 123450, "本局最大combo": 88, "歌曲时长秒": 95.0,
				"百分比": "96.20%", "百分比数值": 96.2, "评级": "S", "失败": false,
				"当前关卡": 1, "结算后S数": 1, "三把S赠送": false, "是否赠送第四把": false,
				"perfect数": 100, "cool数": 0, "good数": 0, "miss数": 0,
				"是否全perfect": true, "是否全连": true,
			}
		else:
			router.payload = {}

		var packed: PackedScene = load(scene_path)
		var inst: Node = packed.instantiate()
		root.add_child(inst)
		# 跑几帧让 _ready/_process 执行
		for i in 5:
			await process_frame
		root.remove_child(inst)
		inst.free()
		print("  OK  %s" % key)

	# 本脚本手动挂载 autoload；SceneTree.quit() 前先释放音频后端引用，
	# 否则 --script 退出路径来不及依赖节点树析构完成回收。
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.1).timeout
	print("SCENE SMOKE DONE")
	quit(0)
