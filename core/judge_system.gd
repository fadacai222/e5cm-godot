class_name JudgeSystem
extends RefCounted
## 判定系统 —— 逐行移植自旧项目 core/玩法/判定系统.py
## 输入输出全为数据，不依赖任何 Node，可单元测试。
## 时间差符号约定：正 = 提前按，负 = 延后按（单位 ms）。


class JudgeNote:
	var track: int
	var type: String            # "tap" / "hold"
	var start_sec: float
	var end_sec: float
	var tick_secs: Array = []   # hold 用：每个整拍的判定时刻（秒）
	var start_beat := NAN      # 仅供视觉变速使用，不参与判定
	var end_beat := NAN

	func _init(p_track: int, p_type: String, p_start: float, p_end: float,
			p_ticks: Array = [], p_start_beat := NAN, p_end_beat := NAN) -> void:
		track = p_track
		type = p_type
		start_sec = p_start
		end_sec = p_end
		tick_secs = p_ticks.duplicate()
		start_beat = float(p_start_beat)
		end_beat = float(p_end_beat)


class JudgeReport:
	var type: String            # "tap" / "hold_head" / "hold_tick" / "hold_end"
	var track: int
	var judge: String           # "perfect" / "cool" / "good" / "miss"
	var time_diff_ms: float
	var score_add: int
	var combo_add: int          # tap/hold_head=1; hold_tick=4; miss=0
	var start_sec: float
	var end_sec: float
	var note_index: int
	var scoring: bool

	func _init(p_type: String, p_track: int, p_judge: String, p_diff: float,
			p_score: int, p_combo: int, p_start: float = 0.0, p_end: float = 0.0,
			p_note_index: int = -1, p_scoring := true) -> void:
		type = p_type
		track = p_track
		judge = p_judge
		time_diff_ms = p_diff
		score_add = p_score
		combo_add = p_combo
		start_sec = p_start
		end_sec = p_end
		note_index = p_note_index
		scoring = bool(p_scoring)


static func report_to_dict(report: JudgeReport) -> Dictionary:
	if report == null:
		return {}
	return {
		"type": report.type,
		"track": report.track,
		"judge": report.judge,
		"time_diff_ms": report.time_diff_ms,
		"score_add": report.score_add,
		"combo_add": report.combo_add,
		"start_sec": report.start_sec,
		"end_sec": report.end_sec,
		"note_index": report.note_index,
		"scoring": report.scoring,
	}


static func report_from_dict(data: Dictionary) -> JudgeReport:
	if data.is_empty():
		return null
	return JudgeReport.new(
		str(data.get("type", "tap")), int(data.get("track", 0)),
		str(data.get("judge", "miss")), float(data.get("time_diff_ms", 0.0)),
		int(data.get("score_add", 0)), int(data.get("combo_add", 0)),
		float(data.get("start_sec", 0.0)), float(data.get("end_sec", 0.0)),
		int(data.get("note_index", -1)), bool(data.get("scoring", true)))


# ---- 判定参数（旧版 判定参数 dataclass）----
var perfect_early_ms := 100.0
var perfect_late_ms := -100.0
var cool_early_ms := 150.0
var cool_late_ms := -150.0
var good_early_ms := 200.0
var good_late_ms := -200.0
var search_radius_sec := 0.20
var hold_combo_per_tick := 4
var hold_release_grace_ms := 1000.0
var hold_reconnect_grace_ms := 360.0

var input_offset_sec := 0.0
var auto_mode := false

# ---- 内部状态 ----
var _notes: Array = []                 # Array[JudgeNote]
var _head_judged: Array = []           # Array[bool]
var _finished: Array = []              # Array[bool]
var _track_indices := {}               # track -> Array[int]（按开始秒排序）
var _track_cursor := {}                # track -> int
var _hold_tick_cursor := {}            # note_idx -> tick_idx
var _active_holds: Array = []          # 已判头未结束的 hold 索引
var _hold_head_judge := {}             # note_idx -> "perfect"...
var _hold_last_pressed := {}           # note_idx -> 最近确认按住秒
var _track_reconnect_until := {}       # track -> 允许无新按下续接 hold 的截止秒


func load_chart(notes: Array) -> void:
	_notes = notes.duplicate()
	_head_judged = []
	_finished = []
	for i in _notes.size():
		_head_judged.append(false)
		_finished.append(false)

	_track_indices = {}
	for i in _notes.size():
		var note: JudgeNote = _notes[i]
		if not _track_indices.has(note.track):
			_track_indices[note.track] = []
		_track_indices[note.track].append(i)
	for track in _track_indices:
		var idx_list: Array = _track_indices[track]
		idx_list.sort_custom(func(a, b): return _notes[a].start_sec < _notes[b].start_sec)
	_track_cursor = {}
	for track in _track_indices:
		_track_cursor[track] = 0

	_hold_tick_cursor = {}
	_active_holds = []
	_hold_head_judge = {}
	_hold_last_pressed = {}
	_track_reconnect_until = {}


# ---------- 对外：按下 ----------
func handle_press(track: int, chart_sec: float) -> Array:
	if auto_mode:
		return []
	chart_sec += input_offset_sec
	var candidate := _find_candidate(track, chart_sec)
	if candidate < 0:
		return []
	return _settle_head(candidate, chart_sec, track)


# ---------- 每帧更新：miss 判定 + hold tick ----------
## is_track_pressed: Callable(track: int) -> bool
func update(chart_sec: float, is_track_pressed: Callable) -> Array:
	chart_sec += input_offset_sec
	if auto_mode:
		return _auto_update(chart_sec)

	var reports: Array = []
	var pressed_cache := {}
	var get_pressed := func(track: int) -> bool:
		if not pressed_cache.has(track):
			pressed_cache[track] = bool(is_track_pressed.call(track))
		return pressed_cache[track]

	# hold 持续按住时不断续期，允许后一个 hold 头在没有新按下时接上
	for idx in _active_holds:
		if _finished[idx]:
			continue
		var note: JudgeNote = _notes[idx]
		if note.type != "hold":
			continue
		if get_pressed.call(note.track):
			_refresh_reconnect(note.track, chart_sec)

	for track in _track_indices:
		if not get_pressed.call(track):
			continue
		reports.append_array(_try_reconnect_hold(track, chart_sec))

	# 1) 自动 miss：超过 good 延后窗口还没判头 -> miss
	for track in _track_indices:
		var idx_list: Array = _track_indices[track]
		var cursor: int = _track_cursor.get(track, 0)
		while cursor < idx_list.size():
			var idx: int = idx_list[cursor]
			if _finished[idx]:
				cursor += 1
				continue
			var note: JudgeNote = _notes[idx]
			if _head_judged[idx]:
				break
			var diff_ms := (note.start_sec - chart_sec) * 1000.0
			if diff_ms < good_late_ms:
				_head_judged[idx] = true
				_finished[idx] = true
				reports.append(JudgeReport.new(
					"tap" if note.type == "tap" else "hold_head",
					note.track, "miss", diff_ms, 0, 0, note.start_sec, note.end_sec, idx))
				cursor += 1
				continue
			break
		_track_cursor[track] = cursor

	# 2) hold tick：tick 时刻 <= 当前秒就结算一次（按住=继承头判，否则 miss）
	var still_active: Array = []
	var release_grace_sec: float = maxf(0.0, hold_release_grace_ms / 1000.0)
	for idx in _active_holds:
		if _finished[idx]:
			continue
		var note: JudgeNote = _notes[idx]
		if note.type != "hold":
			_finished[idx] = true
			continue

		var tick_cursor: int = _hold_tick_cursor.get(idx, 0)
		var ticks: Array = note.tick_secs
		var last_pressed = _hold_last_pressed.get(idx, null)

		if get_pressed.call(note.track):
			last_pressed = chart_sec
			_hold_last_pressed[idx] = chart_sec
			_refresh_reconnect(note.track, chart_sec)

		while tick_cursor < ticks.size() and float(ticks[tick_cursor]) <= chart_sec:
			var tick_sec := float(ticks[tick_cursor])
			var held := last_pressed != null and (tick_sec - float(last_pressed)) <= release_grace_sec
			if held:
				var tick_judge: String = str(_hold_head_judge.get(idx, "perfect"))
				reports.append(JudgeReport.new(
					"hold_tick", note.track, tick_judge, 0.0,
					_score_for(tick_judge), hold_combo_per_tick,
					note.start_sec, note.end_sec, idx))
			else:
				reports.append(JudgeReport.new(
					"hold_tick", note.track, "miss", 0.0, 0, 0,
					note.start_sec, note.end_sec, idx))
			tick_cursor += 1
		_hold_tick_cursor[idx] = tick_cursor

		# tick 都算完，并且超过结束秒一定时间，认为结束。
		# hold_end 仅描述生命周期，不参与分数、Combo、血量或判定统计。
		if tick_cursor >= ticks.size() and chart_sec > note.end_sec + 0.05:
			var end_judge := str(_hold_head_judge.get(idx, "perfect"))
			reports.append(JudgeReport.new("hold_end", note.track, end_judge, 0.0,
				0, 0, note.start_sec, note.end_sec, idx, false))
			_finished[idx] = true
			_hold_head_judge.erase(idx)
			_hold_last_pressed.erase(idx)
		else:
			still_active.append(idx)
	_active_holds = still_active

	return reports


func _settle_head(candidate: int, chart_sec: float, track: int) -> Array:
	var note: JudgeNote = _notes[candidate]
	var diff_ms := (note.start_sec - chart_sec) * 1000.0  # 正 = 提前按
	var judge := _judge_from_diff(diff_ms)
	var score := _score_for(judge)

	if note.type == "tap":
		_head_judged[candidate] = true
		_finished[candidate] = true
		return [JudgeReport.new("tap", track, judge, diff_ms, score,
				0 if judge == "miss" else 1, note.start_sec, note.end_sec, candidate)]

	_head_judged[candidate] = true
	var reports: Array = [JudgeReport.new("hold_head", track, judge, diff_ms, score,
			0 if judge == "miss" else 1, note.start_sec, note.end_sec, candidate)]

	if judge == "miss":
		_finished[candidate] = true
		_track_reconnect_until.erase(note.track)
		return reports

	if not _hold_tick_cursor.has(candidate):
		_hold_tick_cursor[candidate] = 0
	if not _active_holds.has(candidate):
		_active_holds.append(candidate)
	_hold_head_judge[candidate] = judge
	_hold_last_pressed[candidate] = chart_sec
	_refresh_reconnect(note.track, chart_sec)
	return reports


func _refresh_reconnect(track: int, chart_sec: float) -> void:
	var grace_sec: float = maxf(0.0, hold_reconnect_grace_ms / 1000.0)
	if grace_sec <= 0.0:
		return
	var until := chart_sec + grace_sec
	_track_reconnect_until[track] = maxf(float(_track_reconnect_until.get(track, 0.0)), until)


func _try_reconnect_hold(track: int, chart_sec: float) -> Array:
	var until := float(_track_reconnect_until.get(track, 0.0))
	if until <= 0.0:
		return []
	if chart_sec > until:
		_track_reconnect_until.erase(track)
		return []
	var candidate := _find_candidate(track, chart_sec)
	if candidate < 0:
		return []
	var note: JudgeNote = _notes[candidate]
	if note.type != "hold":
		return []
	if chart_sec + 1e-6 < note.start_sec:
		return []
	var diff_ms := (note.start_sec - chart_sec) * 1000.0
	if _judge_from_diff(diff_ms) == "miss":
		return []
	return _settle_head(candidate, chart_sec, track)


# ---------- 自动模式（autoplay/演示） ----------
func _auto_update(chart_sec: float) -> Array:
	var reports: Array = []

	for track in _track_indices:
		var idx_list: Array = _track_indices[track]
		var cursor: int = _track_cursor.get(track, 0)
		while cursor < idx_list.size():
			var idx: int = idx_list[cursor]
			if _finished[idx]:
				cursor += 1
				continue
			var note: JudgeNote = _notes[idx]
			if _head_judged[idx]:
				break
			if note.start_sec <= chart_sec:
				_head_judged[idx] = true
				if note.type == "tap":
					_finished[idx] = true
					reports.append(JudgeReport.new("tap", note.track, "perfect", 0.0,
							5000, 1, note.start_sec, note.end_sec, idx))
				else:
					reports.append(JudgeReport.new("hold_head", note.track, "perfect", 0.0,
							5000, 1, note.start_sec, note.end_sec, idx))
					if not _hold_tick_cursor.has(idx):
						_hold_tick_cursor[idx] = 0
					if not _active_holds.has(idx):
						_active_holds.append(idx)
					_hold_head_judge[idx] = "perfect"
					_hold_last_pressed[idx] = chart_sec
				cursor += 1
				continue
			break
		_track_cursor[track] = cursor

	var still_active: Array = []
	for idx in _active_holds:
		if _finished[idx]:
			continue
		var note: JudgeNote = _notes[idx]
		var tick_cursor: int = _hold_tick_cursor.get(idx, 0)
		var ticks: Array = note.tick_secs
		while tick_cursor < ticks.size() and float(ticks[tick_cursor]) <= chart_sec:
			reports.append(JudgeReport.new("hold_tick", note.track, "perfect", 0.0,
					5000, hold_combo_per_tick, note.start_sec, note.end_sec, idx))
			tick_cursor += 1
		_hold_tick_cursor[idx] = tick_cursor
		if tick_cursor >= ticks.size() and chart_sec > note.end_sec + 0.05:
			reports.append(JudgeReport.new("hold_end", note.track, "perfect", 0.0,
				0, 0, note.start_sec, note.end_sec, idx, false))
			_finished[idx] = true
			_hold_head_judge.erase(idx)
			_hold_last_pressed.erase(idx)
		else:
			still_active.append(idx)
	_active_holds = still_active
	return reports


# ---------- 内部：找候选 ----------
func _find_candidate(track: int, chart_sec: float) -> int:
	var idx_list: Array = _track_indices.get(track, [])
	if idx_list.is_empty():
		return -1
	var cursor: int = _track_cursor.get(track, 0)
	var candidates: Array = []
	var i := cursor
	while i < idx_list.size():
		var idx: int = idx_list[i]
		if _finished[idx] or _head_judged[idx]:
			i += 1
			continue
		var note: JudgeNote = _notes[idx]
		var dt := note.start_sec - chart_sec
		if dt < -search_radius_sec:
			i += 1
			continue
		if dt > search_radius_sec:
			break
		candidates.append(idx)
		i += 1
	if candidates.is_empty():
		return -1
	var best: int = candidates[0]
	var best_abs: float = absf(_notes[best].start_sec - chart_sec)
	for idx in candidates:
		var a: float = absf(_notes[idx].start_sec - chart_sec)
		if a < best_abs:
			best_abs = a
			best = idx
	return best


# ---------- 内部：判定 ----------
func _judge_from_diff(diff_ms: float) -> String:
	if perfect_late_ms <= diff_ms and diff_ms <= perfect_early_ms:
		return "perfect"
	if cool_late_ms <= diff_ms and diff_ms <= cool_early_ms:
		return "cool"
	if good_late_ms <= diff_ms and diff_ms <= good_early_ms:
		return "good"
	return "miss"


static func _score_for(judge: String) -> int:
	match judge:
		"perfect":
			return 5000
		"cool":
			return 4000
		"good":
			return 3000
	return 0
