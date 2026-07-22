class_name Conductor
extends Node
## 音频时钟：谱面时间以音频硬件时钟为准（谱面秒 == 音频秒，OFFSET 已折算进事件）。
## 开始前有负时间倒计时区（READY GO），music 从 0 播。
## 音乐只允许起播一次；自然结束后锁存结束状态并发出单次信号，避免结尾被重复 play()。

signal music_started
signal music_finished_playing

var player: AudioStreamPlayer
var lead_in_sec := 2.0
var user_offset_sec := 0.0

var _started := false
var _start_tick_usec := 0
var _smooth_time := -999.0
var _paused := false
var _pause_chart_time := 0.0
var _music_started_once := false
var _music_finished_emitted := false
var _last_chart_time := 0.0
var _start_chart_sec := 0.0


func _init(p_player: AudioStreamPlayer) -> void:
	player = p_player


func start(lead_in := 2.0, start_chart_sec := 0.0) -> void:
	lead_in_sec = maxf(0.0, lead_in)
	_start_chart_sec = maxf(0.0, start_chart_sec)
	_started = true
	_paused = false
	_music_started_once = false
	_music_finished_emitted = false
	_last_chart_time = _start_chart_sec
	_start_tick_usec = Time.get_ticks_usec()
	_smooth_time = _start_chart_sec - lead_in_sec
	if player != null:
		player.stream_paused = false
		if player.playing:
			player.stop()


func stop() -> void:
	_started = false
	_paused = false
	if player != null:
		player.stream_paused = false
		if player.playing:
			player.stop()


func pause() -> void:
	if _paused or not _started:
		return
	_pause_chart_time = get_chart_time_raw()
	_paused = true
	if player != null:
		player.stream_paused = true


func resume() -> void:
	if not _paused:
		return
	_paused = false
	if player != null:
		player.stream_paused = false
	if not _music_started_once and _pause_chart_time < _start_chart_sec:
		var elapsed_from_countdown_start := _pause_chart_time - _start_chart_sec + lead_in_sec
		_start_tick_usec = Time.get_ticks_usec() - int(elapsed_from_countdown_start * 1e6)


func is_paused() -> bool:
	return _paused


func has_music_started() -> bool:
	return _music_started_once


func has_music_finished() -> bool:
	return _music_finished_emitted


## QA/parity 专用确定性定位：不依赖真实音频设备时钟。
func seek_for_test(seconds: float, paused := true) -> void:
	var target := maxf(0.0, seconds)
	_start_chart_sec = target
	_started = true
	_paused = paused
	_music_started_once = true
	_music_finished_emitted = false
	_pause_chart_time = target
	_last_chart_time = target
	_smooth_time = target
	_start_tick_usec = Time.get_ticks_usec() - int((target + lead_in_sec) * 1e6)
	if player != null:
		if player.playing:
			player.stop()
		player.stream_paused = paused


func _audio_clock_time() -> float:
	if player == null:
		return _last_chart_time
	return player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency() \
		+ user_offset_sec


## 原始谱面时间（秒）：<0 为开场倒计时区。
func get_chart_time_raw() -> float:
	if not _started:
		return -lead_in_sec
	if _paused:
		return _pause_chart_time
	if player != null and player.playing:
		_last_chart_time = maxf(_last_chart_time, _audio_clock_time())
		return _last_chart_time
	if _music_started_once:
		# 音频自然结束后不再退回倒计时系统时钟，更不能重新从 0 起播。
		return _last_chart_time
	var countdown := float(Time.get_ticks_usec() - _start_tick_usec) / 1e6 - lead_in_sec
	return _start_chart_sec + countdown + user_offset_sec


## 每帧调用：负时间归零点自动起播音乐；返回平滑后的谱面时间。
func tick() -> float:
	if _started and not _paused:
		if not _music_started_once:
			var countdown := float(Time.get_ticks_usec() - _start_tick_usec) / 1e6 - lead_in_sec
			if countdown >= 0.0 and player != null and player.stream != null:
				player.play(_start_chart_sec)
				_music_started_once = true
				_music_finished_emitted = false
				_last_chart_time = maxf(_start_chart_sec, _start_chart_sec + user_offset_sec)
				music_started.emit()
		elif player != null and not player.playing and not _music_finished_emitted:
			_music_finished_emitted = true
			var stream_length := player.stream.get_length() if player.stream != null else 0.0
			if stream_length > 0.0:
				_last_chart_time = maxf(_last_chart_time, stream_length + user_offset_sec)
			music_finished_playing.emit()
	var raw := get_chart_time_raw()
	if absf(raw - _smooth_time) > 0.25:
		_smooth_time = raw
	else:
		_smooth_time = lerpf(_smooth_time, raw, 0.35)
	return _smooth_time


func start_chart_sec_for_test() -> float:
	return _start_chart_sec
