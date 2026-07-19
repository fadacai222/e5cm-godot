extends Node
## 外部曲库音频必须在后台线程读取；加载完成后能生成可播放流，且不进入常驻缓存。
## 运行：godot --headless --path . res://tests/test_async_audio_loading_20260719.tscn

var _failures := 0
var _parallel_stream_a: AudioStream
var _parallel_stream_b: AudioStream


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("  PASS  ", message)
		return
	_failures += 1
	push_error("  FAIL  %s%s" % [message, "：" + detail if not detail.is_empty() else ""])


func _copy_fixture(source_path: String, target_path: String) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return false
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_buffer(source.get_buffer(source.get_length()))
	return true


func _copy_fixture_repeated(source_path: String, target_path: String, repetitions: int) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return false
	var data := source.get_buffer(source.get_length())
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return false
	for _index in maxi(1, repetitions):
		target.store_buffer(data)
	return true


func _load_parallel_a(path: String) -> void:
	_parallel_stream_a = await AudioDirector.load_song_stream_async(path)


func _load_parallel_b(path: String) -> void:
	_parallel_stream_b = await AudioDirector.load_song_stream_async(path)


func _run() -> void:
	SettingsStore.persist_enabled = false
	print("== 2026-07-19 async audio loading ==")
	var fixture := "res://assets/e5cm_runtime/冷资源/backsound/开始游戏.mp3"
	var external := "user://async_audio_loading_fixture.mp3"
	_check(_copy_fixture(fixture, external), "测试音频复制到外部曲库路径")

	AudioDirector.reset_async_song_read_count_for_test()
	var stream := await AudioDirector.load_song_stream_async(external)
	_check(stream is AudioStreamMP3, "外部 MP3 后台读取后生成 AudioStreamMP3")
	_check(AudioDirector.async_song_read_count_for_test() == 1,
		"外部歌曲走一次异步读取", str(AudioDirector.async_song_read_count_for_test()))
	if stream is AudioStreamMP3:
		_check((stream as AudioStreamMP3).data.size() > 0, "异步读取结果包含有效音频数据")

	var ogg_fixture := "res://assets/e5cm_runtime/冷资源/backsound/开始游戏.ogg"
	var external_ogg := "user://async_audio_loading_fixture.ogg"
	_check(_copy_fixture(ogg_fixture, external_ogg), "OGG 测试音频复制到外部路径")
	var ogg_stream := await AudioDirector.load_song_stream_async(external_ogg)
	_check(ogg_stream is AudioStreamOggVorbis, "外部 OGG 后台读取后生成可播放流")

	var wav_fixture := "res://assets/e5cm_runtime/冷资源/Buttonsound/sound_key_judge.wav"
	var external_wav := "user://async_audio_loading_fixture.wav"
	_check(_copy_fixture(wav_fixture, external_wav), "WAV 测试音频复制到外部路径")
	var wav_stream := await AudioDirector.load_song_stream_async(external_wav)
	_check(wav_stream is AudioStreamWAV, "外部 WAV 后台读取后生成可播放流")

	var parallel_source := "res://assets/e5cm_runtime/冷资源/backsound/back_music_ui.mp3"
	var parallel_external := "user://async_audio_parallel_fixture.mp3"
	_check(_copy_fixture_repeated(parallel_source, parallel_external, 8),
		"生成足够大的并发读取样本")
	_parallel_stream_a = null
	_parallel_stream_b = null
	AudioDirector.reset_async_song_read_count_for_test()
	_load_parallel_a(parallel_external)
	_load_parallel_b(parallel_external)
	for _frame in 1200:
		if _parallel_stream_a != null and _parallel_stream_b != null:
			break
		await get_tree().process_frame
	_check(_parallel_stream_a != null and _parallel_stream_a == _parallel_stream_b,
		"同一路径的并发请求复用同一个 AudioStream")
	_check(AudioDirector.async_song_read_count_for_test() == 1,
		"并发请求只启动一次磁盘读取", str(AudioDirector.async_song_read_count_for_test()))
	_check(AudioDirector.active_song_load_job_count_for_test() == 0,
		"共享读取完成后任务索引立即释放")
	_parallel_stream_a = null
	_parallel_stream_b = null

	var reads_before_imported := AudioDirector.async_song_read_count_for_test()
	var imported := await AudioDirector.load_song_stream_async(fixture)
	_check(imported != null, "项目内已导入音频仍可直接加载")
	_check(AudioDirector.async_song_read_count_for_test() == reads_before_imported,
		"项目内已导入音频不启动外部读取线程")

	var fake_chart := "user://async_audio_loading_fixture.sm"
	var chart_file := FileAccess.open(fake_chart, FileAccess.WRITE)
	chart_file.store_string("#TITLE:Async Audio Test;\n#MUSIC:async_audio_loading_fixture.mp3;\n")
	chart_file.close()
	var loading_scene := load("res://scenes/loading/loading.tscn") as PackedScene
	AudioDirector.reset_async_song_read_count_for_test()
	SceneRouter.payload = {"sm": fake_chart, "mp3": external, "cover": "", "name": "异步测试",
		"star": 1, "mode": "测试", "submode": "测试", "sm_key": "async-test"}
	var loading := loading_scene.instantiate()
	add_child(loading)
	for frame in 180:
		if bool(loading.get("_payload_ready")):
			break
		await get_tree().process_frame
	_check(bool(loading.get("_payload_ready")), "加载页等待后台音频完成后才允许进入游戏")
	_check(AudioDirector.async_song_read_count_for_test() == 1, "加载页缺少预备流时只读取一次音频")
	var loading_payload: Dictionary = loading.get("payload")
	var prepared_stream = loading_payload.get("audio_stream")
	_check(prepared_stream is AudioStream, "加载页把后台读取结果写入场景载荷")
	loading.queue_free()
	await get_tree().process_frame

	AudioDirector.reset_async_song_read_count_for_test()
	SceneRouter.payload = {"sm": fake_chart, "mp3": external, "cover": "", "name": "复用测试",
		"star": 1, "mode": "测试", "submode": "测试", "sm_key": "reuse-test",
		"audio_stream": prepared_stream}
	var reused_loading := loading_scene.instantiate()
	add_child(reused_loading)
	await get_tree().process_frame
	_check(bool(reused_loading.get("_payload_ready")), "加载页直接接受选歌预览传来的音频流")
	_check(AudioDirector.async_song_read_count_for_test() == 0, "已有预备流时不重复读取整首音频")
	reused_loading.queue_free()
	await get_tree().process_frame
	loading_payload.clear()
	loading = null
	reused_loading = null

	stream = null
	ogg_stream = null
	wav_stream = null
	imported = null
	prepared_stream = null
	loading_scene = null
	SceneRouter.payload = {}
	AudioDirector.release_for_shutdown()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(external))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(external_ogg))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(external_wav))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(parallel_external))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fake_chart))
	# PackedScene/AudioStream 的引用释放会落后一两个空闲帧；给测试树一个短暂清理窗口，
	# 避免把正常延迟释放误报成 ObjectDB 泄漏。
	await get_tree().create_timer(0.08).timeout
	if _failures == 0:
		print("\nALL ASYNC AUDIO TESTS PASSED")
		get_tree().quit(0)
	else:
		push_error("\n%d ASYNC AUDIO TEST(S) FAILED" % _failures)
		get_tree().quit(1)
