extends SceneTree
## 训练室兼容矩阵：1P、10轨/2P、情侣、DIY JSON，并验证 50 次循环无起点漂移。

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

var _failures := 0


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("[PASS] %s" % message)
		return
	_failures += 1
	push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	await process_frame
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SettingsStore").persist_enabled = false
	root.get_node("AnalyticsStore").persist_enabled = false
	root.get_node("SettingsStore").autoplay = false
	root.get_node("SettingsStore").show_ready_animation = false

	var samples: Dictionary = _find_samples()
	_check(samples.has("one_player"), "找到 1P 训练谱面", str(samples.keys()))
	_check(samples.has("ten_track"), "找到 10轨/2P 训练谱面", str(samples.keys()))
	_check(samples.has("couple"), "找到情侣训练谱面", str(samples.keys()))
	_check(samples.has("json"), "找到 DIY JSON 训练谱面", str(samples.keys()))
	if samples.has("one_player"):
		await _run_sample("1P", samples["one_player"], false, false, 5)
	if samples.has("ten_track"):
		await _run_sample("10轨/2P", samples["ten_track"], true, false, 10)
	if samples.has("couple"):
		await _run_sample("情侣", samples["couple"], true, true, 10)
	if samples.has("json"):
		var json_song: Dictionary = samples["json"]
		var expected := 10 if int(json_song.get("actual_columns", json_song.get("columns", 5))) >= 10 else 5
		await _run_sample("DIY JSON", json_song, expected >= 10, bool(json_song.get("couple", false)), expected)
	_test_fifty_loop_drift()
	_finish()


func _find_samples() -> Dictionary:
	var result := {}
	var library := root.get_node("SongLibrary")
	for mode in ["花式", "竞速", "DIY"]:
		for raw_submode in library.list_submodes(mode):
			var submode := str(raw_submode)
			var songs: Array = library.get_songs(mode, submode)
			for raw_song in songs:
				if not raw_song is Dictionary:
					continue
				var song: Dictionary = (raw_song as Dictionary).duplicate(true)
				song["mode"] = mode
				song["submode"] = submode
				var is_couple := bool(song.get("couple", false)) \
					or str(song.get("style", "")) == "情侣" or submode.contains("情侣")
				var is_json := str(song.get("chart_format", "")).to_lower() == "json" \
					or str(song.get("sm", "")).to_lower().ends_with(".json")
				var columns := _actual_columns(song, is_couple)
				song["actual_columns"] = columns
				if not result.has("one_player") and columns > 0 and columns < 10 and not is_couple:
					result["one_player"] = song
				if not result.has("ten_track") and columns >= 10 and not is_couple:
					result["ten_track"] = song
				if not result.has("couple") and is_couple:
					result["couple"] = song
				if not result.has("json") and is_json:
					result["json"] = song
				if result.size() >= 4:
					return result
	return result


func _actual_columns(song: Dictionary, couple: bool) -> int:
	var sm_path := str(root.get_node("AssetLoader").abs_path(str(song.get("sm", ""))))
	if sm_path.is_empty() or not FileAccess.file_exists(sm_path):
		return 0
	var parsed: Dictionary
	if couple:
		parsed = SmParser.build_couple_events(sm_path)
	else:
		parsed = SmParser.build_events(sm_path, false, str(song.get("charttype", "")))
	if not str(parsed.get("error", "")).is_empty() or (parsed.get("events", []) as Array).is_empty():
		return 0
	return int(parsed.get("columns", 5))


func _run_sample(label: String, song: Dictionary, prefer_double: bool,
		couple: bool, expected_tracks: int) -> void:
	var duration := 45.0
	var audio = song.get("audio_stream")
	if audio is AudioStream and audio.get_length() > 0.0:
		duration = audio.get_length()
	var base_payload := {
		"sm": song.get("sm", ""), "mp3": song.get("mp3", ""),
		"cover": song.get("cover", ""), "name": song.get("name", label),
		"star": int(song.get("star", 0)), "mode": song.get("mode", "竞速"),
		"submode": song.get("submode", ""), "sm_key": song.get("sm_key", ""),
		"prefer_double": prefer_double, "couple": couple,
		"target_charttype": str(song.get("charttype", "")),
		"style": str(song.get("style", "")), "bpm": float(song.get("bpm", 120.0)),
	}
	var config: Dictionary = root.get_node("TrainingSession").create_config(
		duration, 0.0, minf(duration, 30.0), 1.0, 1, 0.0, false, true)
	var training_payload: Dictionary = root.get_node("TrainingSession").begin(base_payload, config)
	root.get_node("SceneRouter").payload = training_payload
	var gameplay: Control = load("res://scenes/gameplay/gameplay.tscn").instantiate()
	root.add_child(gameplay)
	for i in 50:
		await process_frame
		if bool(gameplay.get("_chart_ready")):
			break
	_check(bool(gameplay.get("_chart_ready")), "%s 训练谱面可加载" % label,
		str(gameplay.get("_load_error")))
	if bool(gameplay.get("_chart_ready")):
		_check(int(gameplay.get("track_count")) == expected_tracks,
			"%s 训练轨道数正确" % label, str(gameplay.get("track_count")))
		_check(gameplay.get_node_or_null("TrainingHud") != null,
			"%s 训练 HUD 正常" % label)
	root.get_node("TrainingSession").finish()
	root.remove_child(gameplay)
	gameplay.free()
	await process_frame


func _test_fifty_loop_drift() -> void:
	var runtime: TrainingRuntime = TrainingRuntime.new({
		"bpm": 180.0,
		"training_config": {"start_sec": 32.5, "end_sec": 42.5,
			"speed": 0.75, "loop_count": 50, "auto_rewind_sec": 0.0,
			"show_timing": true, "metronome": false},
	})
	runtime.clamp_segment(120.0)
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	root.add_child(player)
	var conductor: Conductor = Conductor.new(player)
	root.add_child(conductor)
	var expected: float = runtime.start_sec
	for i in 50:
		runtime.set_runtime_start(expected)
		conductor.start(runtime.preroll_seconds(), runtime.runtime_start_sec)
		_check(is_equal_approx(conductor.start_chart_sec_for_test(), expected),
			"第 %d 次循环起点无累计漂移" % (i + 1))
		conductor.stop()
		if runtime.has_more_loops():
			runtime.advance_loop()
	_check(runtime.loop_index == 50, "连续循环 50 次计数准确", str(runtime.loop_index))
	root.remove_child(conductor)
	conductor.free()
	root.remove_child(player)
	player.free()


func _finish() -> void:
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.08).timeout
	quit(1 if _failures > 0 else 0)
