extends Node
## 音频总管（autoload: AudioDirector）
## 对应旧项目 core/音频.py::音乐管理 + 各场景 BGM 切换规则。
## 子模式 -> 选歌 BGM 映射（旧 场景_子模式.py::子模式对应选歌BGM）：
##   表演/DIY -> show.mp3、疯狂 -> devil.mp3、混音 -> remix.mp3、club -> club.mp3、其他 -> UI音乐

var _bgm_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _current_bgm_path := ""
var _test_events: Array[Dictionary] = []
var _event_sequence := 0

const SFX_POOL_SIZE := 8


func _ready() -> void:
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx_players.append(p)
	_apply_volume()


func _apply_volume() -> void:
	var vol := 0.0 if SettingsStore.muted else float(SettingsStore.bgm_volume) / 100.0
	_bgm_player.volume_db = linear_to_db(maxf(0.0001, vol))
	var sfx_vol := 0.0 if SettingsStore.muted else 0.9
	for p in _sfx_players:
		p.volume_db = linear_to_db(maxf(0.0001, sfx_vol))


## 设置变更后由设置菜单调用
func refresh_volume() -> void:
	_apply_volume()


var _hit_tick_stream: AudioStreamWAV


## 击中音效：程序生成 20ms 短促 tick（原版击中音效开关对应）
func play_hit_tick() -> void:
	if SettingsStore.muted:
		return
	if _hit_tick_stream == null:
		var rate := 44100
		var samples := int(rate * 0.02)
		var data := PackedByteArray()
		data.resize(samples * 2)
		for i in samples:
			var env := 1.0 - float(i) / float(samples)
			var v := int(sin(float(i) * 0.35) * 12000.0 * env * env)
			data.encode_s16(i * 2, v)
		_hit_tick_stream = AudioStreamWAV.new()
		_hit_tick_stream.format = AudioStreamWAV.FORMAT_16_BITS
		_hit_tick_stream.mix_rate = rate
		_hit_tick_stream.data = data
	for p in _sfx_players:
		if not p.playing:
			p.stream = _hit_tick_stream
			p.volume_db = -12.0
			p.play()
			return


func play_bgm(path: String, restart := false) -> void:
	if path == "" or (path == _current_bgm_path and _bgm_player.playing and not restart):
		return
	var stream := _load_stream(path)
	if stream == null:
		return
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	_bgm_player.stream = stream
	_apply_volume()
	_bgm_player.play()
	_current_bgm_path = path


func stop_bgm() -> void:
	_bgm_player.stop()
	_current_bgm_path = ""


func get_audio_length(path: String) -> float:
	var stream := _load_stream(path)
	return maxf(0.0, stream.get_length()) if stream != null else 0.0


func current_bgm_path_for_test() -> String:
	return _current_bgm_path


func is_bgm_playing() -> bool:
	return _bgm_player != null and _bgm_player.playing


## 退出测试/程序前显式解除播放器与缓存对音频资源的引用。
## 仅 stop() 不会释放 AudioStreamPlayback，Godot 会在退出时报告 ObjectDB 泄漏。
func release_for_shutdown() -> void:
	if is_instance_valid(_bgm_player):
		_bgm_player.stop()
		_bgm_player.stream = null
	for p in _sfx_players:
		if is_instance_valid(p):
			p.stop()
			p.stream = null
	_current_bgm_path = ""
	_stream_cache.clear()
	_hit_tick_stream = null
	_test_events.clear()
	_event_sequence = 0


func _exit_tree() -> void:
	release_for_shutdown()


func play_sfx(path: String, event_key := "", timeline_seconds := -1.0) -> bool:
	var stream := _load_stream(path)
	if stream == null:
		return false
	if not str(event_key).is_empty():
		_event_sequence += 1
		_test_events.append({
			"sequence": _event_sequence,
			"eventKey": str(event_key),
			"path": path,
			"timelineSeconds": float(timeline_seconds),
		})
	var sfx_volume := 0.0 if SettingsStore.muted else 0.9
	for p in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = linear_to_db(maxf(0.0001, sfx_volume))
			p.play()
			return true
	_sfx_players[0].stream = stream
	_sfx_players[0].volume_db = linear_to_db(maxf(0.0001, sfx_volume))
	_sfx_players[0].play()
	return true


## 契约/parity 专用：只记录已成功解析并派发到音效池的语义事件。
func clear_test_events() -> void:
	_test_events.clear()
	_event_sequence = 0


func get_test_events() -> Array:
	return _test_events.duplicate(true)


var _stream_cache := {}   # path -> AudioStream（短音效/BGM 反复加载缓存）
var _song_load_jobs := {} # path -> 共享中的后台读取任务；完成后立即移除，不常驻歌曲数据
var _async_song_read_count := 0


## 曲库歌曲专用异步加载。外部 songs 目录通常带 .gdignore，不能依赖导入缓存；
## 文件读取放到工作线程，AudioStream 对象仍在主线程创建，避免快速切歌时卡住渲染。
## 曲库流不写入全局缓存：一首歌可能几十 MB，常驻缓存会随着浏览歌曲持续膨胀。
func load_song_stream_async(path: String) -> AudioStream:
	if path.is_empty():
		return null
	var imported := _load_imported_stream(path)
	if imported != null:
		return imported
	if not FileAccess.file_exists(path):
		return null

	# 预览尚未完成时立刻开始游戏，或两个界面同时请求同一路径，都等待同一任务。
	# Dictionary 是引用容器：拥有者更新 done/stream 后，所有等待者会同时看到结果。
	if _song_load_jobs.has(path):
		var shared_job: Dictionary = _song_load_jobs[path]
		while not bool(shared_job.get("done", false)):
			await get_tree().process_frame
		return shared_job.get("stream") as AudioStream

	var job := {"done": false, "stream": null}
	_song_load_jobs[path] = job
	_async_song_read_count += 1
	var reader := Thread.new()
	var start_error := reader.start(_read_audio_bytes.bind(path))
	if start_error != OK:
		push_warning("AudioDirector: 音频后台线程启动失败，回退同步读取：%s" % path)
		var fallback := _load_external_stream_sync(path)
		_finish_song_load_job(path, job, fallback)
		return fallback
	while reader.is_alive():
		await get_tree().process_frame
	var result = reader.wait_to_finish()
	var stream: AudioStream = null
	if result is Dictionary:
		var read_result := result as Dictionary
		var data: PackedByteArray = read_result.get("data", PackedByteArray())
		if not data.is_empty():
			stream = _decode_audio_bytes(path, data)
	_finish_song_load_job(path, job, stream)
	return stream


func _finish_song_load_job(path: String, job: Dictionary, stream: AudioStream) -> void:
	job["stream"] = stream
	job["done"] = true
	# 等待者已经持有 job 引用；从索引移除后，新一轮请求可以重新加载且不会常驻内存。
	if _song_load_jobs.get(path) == job:
		_song_load_jobs.erase(path)


func async_song_read_count_for_test() -> int:
	return _async_song_read_count


func active_song_load_job_count_for_test() -> int:
	return _song_load_jobs.size()


func reset_async_song_read_count_for_test() -> void:
	_async_song_read_count = 0


func _read_audio_bytes(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": FileAccess.get_open_error(), "data": PackedByteArray()}
	return {"error": OK, "data": file.get_buffer(file.get_length())}


func _decode_audio_bytes(path: String, data: PackedByteArray) -> AudioStream:
	var lower := path.to_lower()
	if lower.ends_with(".mp3"):
		var mp3 := AudioStreamMP3.new()
		mp3.data = data
		return mp3
	if lower.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_buffer(data)
	if lower.ends_with(".wav"):
		return AudioStreamWAV.load_from_buffer(data)
	return null


func _load_imported_stream(path: String) -> AudioStream:
	var song_path := AssetLoader != null and AssetLoader.has_method("is_song_path") \
		and bool(AssetLoader.call("is_song_path", path))
	if not song_path and path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null


func _load_external_stream_sync(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	var lower := path.to_lower()
	if lower.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(path)
	if lower.ends_with(".wav"):
		# 必须走 WAV 解析器：直接把整个文件塞进 .data 会把 RIFF 文件头当 PCM 播成雪花噪声
		return AudioStreamWAV.load_from_file(path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return _decode_audio_bytes(path, file.get_buffer(file.get_length()))


## 支持 res:// 内资源与外部绝对路径（短音效/BGM）。曲库歌曲请走 load_song_stream_async。
func _load_stream(path: String) -> AudioStream:
	var imported := _load_imported_stream(path)
	if imported != null:
		return imported
	if _stream_cache.has(path):
		return _stream_cache[path]
	var stream := _load_external_stream_sync(path)
	if stream != null:
		_stream_cache[path] = stream
	return stream
