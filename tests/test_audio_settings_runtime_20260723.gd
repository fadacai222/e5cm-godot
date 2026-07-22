extends SceneTree
## ESC 音量/静音运行时回归：音乐播放器即时跟随音量，静音覆盖全部 Master 音频。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_audio_settings_runtime_20260723.gd

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	var settings := root.get_node_or_null("SettingsStore")
	var audio_director := root.get_node_or_null("AudioDirector")
	if settings == null or audio_director == null:
		print("  FAIL  SettingsStore/AudioDirector 自动加载器缺失")
		quit(1)
		return
	settings.persist_enabled = false
	await process_frame

	var old_volume := int(settings.bgm_volume)
	var old_muted := bool(settings.muted)
	var player := AudioStreamPlayer.new()
	player.bus = "Master"
	root.add_child(player)
	if audio_director.has_signal("audio_settings_changed"):
		audio_director.audio_settings_changed.connect(
			func(): audio_director.apply_music_volume(player))

	print("== Audio settings runtime regression ==")
	settings.muted = false
	settings.bgm_volume = 25
	audio_director.refresh_volume()
	_check(audio_director.has_method("apply_music_volume"),
		"AudioDirector 提供独立音乐播放器音量同步接口")
	if audio_director.has_method("apply_music_volume"):
		audio_director.apply_music_volume(player)
	_check(absf(player.volume_db - linear_to_db(0.25)) < 0.05,
		"25% 音量即时应用到外部歌曲播放器", "db=%.2f" % player.volume_db)

	settings.muted = true
	audio_director.refresh_volume()
	var master_index := AudioServer.get_bus_index("Master")
	_check(master_index >= 0 and AudioServer.is_bus_mute(master_index),
		"静音开关即时静音 Master 总线")
	_check(player.volume_db <= -79.0,
		"静音时已注册歌曲播放器即时归零", "db=%.2f" % player.volume_db)

	settings.muted = false
	settings.bgm_volume = 60
	audio_director.refresh_volume()
	_check(master_index >= 0 and not AudioServer.is_bus_mute(master_index),
		"关闭静音后即时恢复 Master 总线")
	_check(absf(player.volume_db - linear_to_db(0.60)) < 0.05,
		"解除静音后恢复当前 60% 音量", "db=%.2f" % player.volume_db)

	var gameplay_source := FileAccess.get_file_as_string("res://scenes/gameplay/gameplay.gd")
	var select_source := FileAccess.get_file_as_string("res://scenes/song_select/song_select.gd")
	_check(not gameplay_source.contains("linear_to_db(0.9 if not SettingsStore.muted"),
		"Gameplay 不再把歌曲音量写死为 90%")
	_check(gameplay_source.contains("AudioDirector.apply_music_volume(music_player)"),
		"Gameplay 歌曲播放器接入统一音量同步")
	_check(select_source.contains("AudioDirector.apply_music_volume(_preview_player)"),
		"选歌预览播放器接入统一音量同步")

	settings.bgm_volume = old_volume
	settings.muted = old_muted
	audio_director.refresh_volume()
	root.remove_child(player)
	player.free()
	await process_frame
	print("ALL AUDIO SETTINGS RUNTIME TESTS PASSED" if _failures == 0 else
		"%d AUDIO SETTINGS RUNTIME TEST(S) FAILED" % _failures)
	quit(_failures)
