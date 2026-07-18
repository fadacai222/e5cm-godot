extends SceneTree
## 音频资源生命周期回归测试。
## 运行：godot --headless --path . --script res://tests/test_audio_cleanup.gd

var _failures := 0


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	var settings: Node = root.get_node_or_null("SettingsStore")
	var created_settings := settings == null
	if created_settings:
		settings = load("res://autoload/settings_store.gd").new()
		settings.name = "SettingsStore"
		root.add_child(settings)
	settings.persist_enabled = false
	settings.muted = false

	var audio: Node = root.get_node_or_null("AudioDirector")
	var created_audio := audio == null
	if created_audio:
		audio = load("res://autoload/audio_director.gd").new()
		audio.name = "AudioDirector"
		root.add_child(audio)
	await process_frame

	audio.call("play_hit_tick")
	await process_frame
	var players: Array = audio.get("_sfx_players")
	var held_streams := players.filter(func(player): return player.stream != null).size()
	_check(held_streams > 0, "测试前播放器持有音频流", str(held_streams))
	_check(audio.has_method("release_for_shutdown"), "提供统一音频释放入口")

	if audio.has_method("release_for_shutdown"):
		audio.call("release_for_shutdown")
		var remaining := players.filter(func(player): return player.stream != null).size()
		_check(remaining == 0, "释放后所有音效播放器解除 stream 引用", str(remaining))
		var bgm: AudioStreamPlayer = audio.get("_bgm_player")
		_check(bgm == null or bgm.stream == null, "释放后 BGM 播放器解除 stream 引用")
		_check((audio.get("_stream_cache") as Dictionary).is_empty(), "释放后清空外部音频缓存")
		_check(audio.get("_hit_tick_stream") == null, "释放后清空生成音效引用")

	if created_audio:
		root.remove_child(audio)
		audio.free()
	if created_settings:
		root.remove_child(settings)
		settings.free()

	if _failures == 0:
		print("ALL AUDIO CLEANUP TESTS PASSED")
	else:
		print("%d AUDIO CLEANUP TEST(S) FAILED" % _failures)
	quit(_failures)
