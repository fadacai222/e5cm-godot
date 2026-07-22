extends Node
## 训练室全局会话。
## 入口武装状态会跨越大模式/子模式/选歌场景；真正开始训练后改为 active。

signal session_changed

const SUPPORTED_SPEEDS := [0.5, 0.75, 0.9, 1.0]
const SUPPORTED_LOOP_COUNTS := [-1, 1, 3, 5, 10] # -1 = 无限循环
const MIN_SEGMENT_SECONDS := 5.0

var _entry_armed := false
var _active := false
var _song_payload := {}
var _config := {}
var _last_summary := {}


func arm_entry() -> void:
	_entry_armed = true
	_active = false
	session_changed.emit()


func cancel_entry() -> void:
	_entry_armed = false
	if not _active:
		_song_payload = {}
		_config = {}
	session_changed.emit()


func is_entry_armed() -> bool:
	return _entry_armed


func is_active() -> bool:
	return _active


func current_song() -> Dictionary:
	return _song_payload.duplicate(true)


func current_config() -> Dictionary:
	return _config.duplicate(true)


func last_summary() -> Dictionary:
	return _last_summary.duplicate(true)


func set_last_summary(summary: Dictionary) -> void:
	_last_summary = summary.duplicate(true)
	session_changed.emit()


func create_config(song_duration: float, start_sec: float = 0.0, end_sec: float = -1.0,
		speed: float = 1.0, loop_count: int = -1, auto_rewind_sec: float = 0.0,
		metronome := false, show_timing := true) -> Dictionary:
	var duration := maxf(0.1, song_duration)
	var minimum_segment := minf(MIN_SEGMENT_SECONDS, duration)
	var start_max := maxf(0.0, duration - minimum_segment)
	var normalized_start := clampf(start_sec, 0.0, start_max)
	var requested_end := duration if end_sec <= 0.0 else end_sec
	var normalized_end := clampf(requested_end,
		minf(duration, normalized_start + minimum_segment), duration)
	if normalized_end - normalized_start < minimum_segment:
		normalized_start = maxf(0.0, normalized_end - minimum_segment)

	return {
		"schema_version": 1,
		"song_duration": duration,
		"start_sec": normalized_start,
		"end_sec": normalized_end,
		"speed": _nearest_float(speed, SUPPORTED_SPEEDS),
		"loop_count": _nearest_int(loop_count, SUPPORTED_LOOP_COUNTS),
		"auto_rewind_sec": clampf(auto_rewind_sec, 0.0, 10.0),
		"metronome": metronome,
		"show_timing": show_timing,
	}


func begin(song_payload: Dictionary, requested_config: Dictionary) -> Dictionary:
	var duration := float(requested_config.get("song_duration", 0.0))
	_config = create_config(
		duration,
		float(requested_config.get("start_sec", 0.0)),
		float(requested_config.get("end_sec", duration)),
		float(requested_config.get("speed", 1.0)),
		int(requested_config.get("loop_count", -1)),
		float(requested_config.get("auto_rewind_sec", 0.0)),
		bool(requested_config.get("metronome", false)),
		bool(requested_config.get("show_timing", true)))
	if requested_config.get("problem_windows", []) is Array:
		_config["problem_windows"] = (requested_config.get("problem_windows", []) as Array).duplicate(true)
		_config["problem_window_index"] = clampi(
			int(requested_config.get("problem_window_index", 0)), 0,
			maxi(0, (_config["problem_windows"] as Array).size() - 1))
	_song_payload = song_payload.duplicate(true)
	_last_summary = {}
	_entry_armed = false
	_active = true

	var decorated := _song_payload.duplicate(true)
	decorated["training_mode"] = true
	decorated["training_config"] = _config.duplicate(true)
	# 资格隔离字段由正式结算和未来挑战/联赛统一读取。
	decorated["run_eligibility"] = {
		"official_record": false,
		"experience": false,
		"challenges": false,
		"ghost": false,
		"reason": "training_mode",
	}
	session_changed.emit()
	return decorated


func finish(clear_song := true) -> void:
	_entry_armed = false
	_active = false
	_config = {}
	if clear_song:
		_song_payload = {}
	session_changed.emit()


func reset_all() -> void:
	_entry_armed = false
	_active = false
	_song_payload = {}
	_config = {}
	_last_summary = {}
	session_changed.emit()


static func is_training_payload(data: Dictionary) -> bool:
	return bool(data.get("training_mode", false)) and data.get("training_config", {}) is Dictionary


static func _nearest_float(value: float, supported: Array) -> float:
	var best := float(supported[0])
	var best_distance := absf(value - best)
	for candidate in supported:
		var distance := absf(value - float(candidate))
		if distance < best_distance:
			best = float(candidate)
			best_distance = distance
	return best


static func _nearest_int(value: int, supported: Array) -> int:
	var best := int(supported[0])
	var best_distance := absi(value - best)
	for candidate in supported:
		var distance := absi(value - int(candidate))
		if distance < best_distance:
			best = int(candidate)
			best_distance = distance
	return best
