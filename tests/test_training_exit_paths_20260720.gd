extends SceneTree
## 训练退出路径：片段结束、音频结束、主动退出都清理会话且不污染正式流程。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"], ["SharedVideoBackground", "res://autoload/shared_video_background.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"], ["GameState", "res://autoload/game_state.gd"],
	["TrainingSession", "res://autoload/training_session.gd"], ["AnalyticsStore", "res://autoload/analytics_store.gd"],
	["ProfileStore", "res://autoload/profile_store.gd"], ["SongLibrary", "res://autoload/song_library.gd"],
	["AudioDirector", "res://autoload/audio_director.gd"], ["SceneRouter", "res://autoload/scene_router.gd"],
]
var _failures := 0

func _check(ok: bool, text: String) -> void:
	if ok: print("[PASS] %s" % text)
	else:
		_failures += 1
		push_error("[FAIL] %s" % text)

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new(); node.name = entry[0]; root.add_child(node)
	await process_frame
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("AnalyticsStore").persist_enabled = false
	root.get_node("SettingsStore").show_ready_animation = false
	var songs: Array = root.get_node("SongLibrary").get_songs("竞速", "club")
	_check(not songs.is_empty(), "退出路径测试找到真实歌曲")
	if songs.is_empty(): quit(1); return
	var song: Dictionary = songs[0]
	await _check_path(song, "segment")
	await _check_path(song, "audio")
	await _check_path(song, "manual")
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	quit(1 if _failures > 0 else 0)

func _check_path(song: Dictionary, kind: String) -> void:
	var base := {"sm": song["sm"], "mp3": song["mp3"], "cover": song["cover"],
		"name": song["name"], "star": song["star"], "mode": "竞速", "submode": "club",
		"sm_key": song["sm_key"], "prefer_double": true, "couple": false,
		"target_charttype": str(song.get("charttype", "")), "style": str(song.get("style", ""))}
	var config: Dictionary = root.get_node("TrainingSession").create_config(300.0, 0.0, 30.0, 1.0, 1)
	root.get_node("SceneRouter").payload = root.get_node("TrainingSession").begin(base, config)
	var gameplay: Control = load("res://scenes/gameplay/gameplay.tscn").instantiate()
	root.add_child(gameplay)
	var deadline := Time.get_ticks_msec() + 15000
	while not bool(gameplay.get("_chart_ready")) and Time.get_ticks_msec() < deadline: await process_frame
	_check(bool(gameplay.get("_chart_ready")), "%s 路径训练局加载" % kind)
	var flow = root.get_node("GameState").flow
	var round_before := int(flow.current_round)
	var records_before: Dictionary = root.get_node("ProfileStore").records.duplicate(true)
	root.get_node("SceneRouter").set("_busy", true)
	match kind:
		"segment": gameplay.call("_complete_training_loop")
		"audio":
			gameplay.set("_audio_finished", true); gameplay.set("_started_play", true)
			gameplay.call("_process", 0.5)
		"manual": gameplay.call("_on_quit_song")
	await process_frame
	root.get_node("SceneRouter").set("_busy", false)
	_check(not root.get_node("TrainingSession").is_active(), "%s 路径清理训练会话" % kind)
	_check(int(flow.current_round) == round_before, "%s 路径不推进正式把数" % kind)
	_check(root.get_node("ProfileStore").records == records_before, "%s 路径不写歌曲记录" % kind)
	root.remove_child(gameplay); gameplay.free(); await process_frame
