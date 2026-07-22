extends SceneTree
## 用真实曲库载荷实例化训练 Gameplay，验证片段、速度、HUD 和资格隔离。

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
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	await process_frame
	root.get_node("GameState").persist_credits = false
	root.get_node("ProfileStore").persist_enabled = false
	root.get_node("SettingsStore").persist_enabled = false
	# 训练局必须在普通对局 READY 动画开启时仍直接显示游戏画面。
	# 此配置曾导致训练局停在 READY 第 0 帧，只有训练 HUD 可见、背景永久全黑。
	root.get_node("SettingsStore").show_ready_animation = true

	var songs: Array = root.get_node("SongLibrary").get_songs("竞速", "club")
	_check(not songs.is_empty(), "真实竞速/club 曲库可用于训练冒烟")
	if songs.is_empty():
		_finish()
		return
	var s: Dictionary = songs[0]
	var song_payload := {
		"sm": s["sm"], "mp3": s["mp3"], "cover": s["cover"], "name": s["name"],
		"star": s["star"], "mode": "竞速", "submode": "club", "sm_key": s["sm_key"],
		"prefer_double": true, "couple": false, "target_charttype": str(s.get("charttype", "")),
		"style": str(s.get("style", "")),
	}
	var config: Dictionary = root.get_node("TrainingSession").create_config(
		300.0, 0.0, 300.0, 0.75, 1)
	var training_payload: Dictionary = root.get_node("TrainingSession").begin(song_payload, config)
	root.get_node("SceneRouter").payload = training_payload

	var gameplay: Control = load("res://scenes/gameplay/gameplay.tscn").instantiate()
	root.add_child(gameplay)
	var deadline := Time.get_ticks_msec() + 15000
	while not bool(gameplay.get("_chart_ready")) and Time.get_ticks_msec() < deadline:
		await process_frame

	_check(bool(gameplay.get("_chart_ready")), "训练 Gameplay 能完成真实谱面加载",
		str(gameplay.get("_load_error")))
	_check(bool(gameplay.get("_training_mode")), "Gameplay 识别训练载荷")
	var player := gameplay.get_node("MusicPlayer") as AudioStreamPlayer
	_check(is_equal_approx(player.pitch_scale, 0.75), "训练速度应用到歌曲播放器", str(player.pitch_scale))
	_check(gameplay.get_node_or_null("TrainingHud") != null, "训练 HUD 已创建")
	var gameplay_hud := gameplay.get_node("LegacyTopHud") as Control
	var live_note_field = gameplay.get("note_field")
	var background_dim := gameplay.get_node("BackgroundDim") as ColorRect
	_check(gameplay_hud.modulate.a > 0.99 and gameplay_hud.position.y > -1.0,
		"训练局跳过 READY 黑场并恢复主 HUD")
	_check(live_note_field != null and float(live_note_field.modulate.a) > 0.99,
		"训练局判定区不会被 READY 第 0 帧永久隐藏")
	_check(background_dim.color.a < 0.99,
		"训练局背景黑幕恢复到玩家亮度而非保持全黑")
	var runtime = gameplay.get("_training_runtime")
	var notes: Array = runtime.chart_notes
	_check(not notes.is_empty(), "训练片段裁剪后仍有判定音符")
	_check(not bool(training_payload.get("run_eligibility", {}).get("official_record", true)),
		"训练载荷明确拒绝正式记录资格")

	var flow = root.get_node("GameState").flow
	var round_before := int(flow.current_round)
	var s_before := int(flow.s_count)
	var original_note_count := notes.size()
	gameplay.call("_restart_training_loop", float(runtime.start_sec), false)
	await process_frame
	var conductor = gameplay.get("conductor")
	_check(is_equal_approx(float(conductor.call("start_chart_sec_for_test")),
		float(runtime.start_sec)), "训练重开仍从片段起点启动")
	_check(runtime.chart_notes.size() == original_note_count,
		"训练重开不丢失原始片段音符")
	_check(int(flow.current_round) == round_before and int(flow.s_count) == s_before,
		"训练重开不会推进正式三把流程")

	var records_before: Dictionary = root.get_node("ProfileStore").records.duplicate(true)
	gameplay.call("_finish_song", false)
	_check(int(flow.current_round) == round_before and int(flow.s_count) == s_before,
		"训练结束不会推进正式三把流程")
	_check(root.get_node("ProfileStore").records == records_before,
		"训练结束不会写入歌曲最高分或游玩次数")
	_check(not root.get_node("TrainingSession").is_active(),
		"训练结束立即清理 active 会话")
	var router = root.get_node("SceneRouter")
	var transition_deadline := Time.get_ticks_msec() + 2000
	while router.is_transition_busy() and Time.get_ticks_msec() < transition_deadline:
		await process_frame
	if current_scene != null and is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
		await process_frame
	if is_instance_valid(gameplay) and gameplay.get_parent() != null:
		gameplay.get_parent().remove_child(gameplay)
		gameplay.free()
	_finish()


func _finish() -> void:
	root.get_node("TrainingSession").reset_all()
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	await create_timer(0.2).timeout
	quit(1 if _failures > 0 else 0)
