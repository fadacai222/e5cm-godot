class_name SmParser
extends RefCounted
## SM/SSC 谱面解析器 —— 逐行移植自旧项目 scenes/场景_谱面播放器.py（1100~2300 行段）
## 关键规则：
##  - 事件秒 = beat转秒(beat) - OFFSET（谱面秒 == 音频秒）
##  - 时间轴按 #BPMS 分段；无 BPMS 用 DISPLAYBPM 兜底，再兜底 120
##  - 舞推专用 charttype（single/hard/double/remix/lover1/lover2 且 10/20 列）：
##      每组 10 槽位，脚 {1,2,4,6,7}->轨道{0..4}，手 {0,3,5,8}->{ll,tt,bb,rr}（装饰）
##  - 通用类型（pump-double 等）：列直接映射轨道 0..列数-1
##  - 音符字符：1=tap 2/4=hold头 3=hold尾 0=空，其他忽略

const FOOT_SLOT_TO_TRACK := {1: 0, 2: 1, 4: 2, 6: 3, 7: 4}
const HAND_SLOT_TO_DIR := {0: "ll", 3: "tt", 5: "bb", 8: "rr"}
const SLOTS_PER_GROUP := 10
# E5 DIY 特效谱兼容阈值。事件时间轴保留作者原始 BPM；只有总时长估算
# 会排除足以制造异常长尾的末尾极低 BPM，与旧项目补丁保持一致。
const JSON_TERMINAL_FREEZE_BPM_THRESHOLD := 1.0
const JSON_TERMINAL_FREEZE_ABNORMAL_SEC := 30.0
const JSON_EXTREME_VISUAL_BPM_THRESHOLD := 1_000_000.0
const JSON_DEFAULT_TICKS_PER_BEAT := 96


# ============================ 文本工具 ============================

static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	# UTF-8 BOM
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		bytes = bytes.slice(3)
	var text := bytes.get_string_from_utf8()
	if text.is_empty() and bytes.size() > 0:
		text = bytes.get_string_from_ascii()  # GBK 谱面极少见，ASCII 兜底
	return text


## 提取 #TAG: 值 ;（去注释、合并多行）
static func extract_tag(sm_text: String, tag: String) -> String:
	var re := RegEx.new()
	re.compile("(?im)^\\s*#" + tag + "\\s*:\\s*([^;]*);?")
	var m := re.search(sm_text)
	if m == null:
		return ""
	var raw := m.get_string(1)
	var lines := raw.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var cleaned := PackedStringArray()
	for line in lines:
		var l := line
		if l.contains("//"):
			l = l.split("//", true, 1)[0]
		cleaned.append(l)
	return "".join(cleaned).strip_edges()


## 提取保留换行的标签原始值（用于 #NOTES / SSC NOTEDATA）
static func extract_tag_raw(sm_text: String, tag: String) -> String:
	var text := sm_text.replace("\r\n", "\n").replace("\r", "\n")
	var re := RegEx.new()
	re.compile("(?im)^\\s*#" + tag + "\\s*:\\s*")
	var m := re.search(text)
	if m == null:
		return ""
	var start := m.get_end()
	var end := text.find(";", start)
	if end < 0:
		end = text.length()
	return text.substr(start, end - start)


static func _first_number(text: String) -> float:
	var re := RegEx.new()
	re.compile("-?\\d+(?:\\.\\d+)?")
	var m := re.search(text)
	return float(m.get_string()) if m else NAN


# ============================ 元数据 ============================

static func parse_offset(sm_text: String) -> float:
	var v := _first_number(extract_tag(sm_text, "OFFSET"))
	return 0.0 if is_nan(v) else v


static func parse_display_bpm(sm_text: String) -> float:
	var v := _first_number(extract_tag(sm_text, "DISPLAYBPM"))
	if is_nan(v) or v <= 0.0:
		return -1.0
	return v


static func parse_rows_per_beat(sm_text: String) -> float:
	var raw := extract_tag(sm_text, "ROWSPERBEAT")
	for part in raw.split(","):
		var seg := str(part).strip_edges()
		if seg.is_empty():
			continue
		if seg.contains("="):
			seg = seg.split("=", true, 1)[1]
		var v := _first_number(seg)
		if not is_nan(v) and v > 0.0:
			return v
	return 192.0


## 位置文本 -> beat（支持 "384r" 行号后缀，按行每拍换算）
static func _parse_position_beat(text: String, rows_per_beat: float) -> float:
	var t := text.strip_edges().to_lower()
	if t.is_empty():
		return NAN
	var v := _first_number(t)
	if is_nan(v):
		return NAN
	if t.ends_with("r"):
		var rpb := rows_per_beat if rows_per_beat > 0.0 else 192.0
		return v / rpb
	return v


## 解析 BPMS 原始值 -> [[beat, bpm], ...]（按 beat 排序、去重）
static func parse_bpms_raw(raw: String, rows_per_beat: float = 192.0) -> Array:
	var result := []
	if raw.is_empty():
		return result
	var body := raw.strip_edges().trim_suffix(";").strip_edges()
	for part in body.split(","):
		var p := str(part).strip_edges()
		if p.is_empty() or not p.contains("="):
			continue
		var kv := p.split("=", true, 1)
		var beat := _parse_position_beat(kv[0], rows_per_beat)
		if is_nan(beat):
			continue
		var bpm := _first_number(kv[1])
		if is_nan(bpm) or bpm <= 0.0:
			continue
		result.append([beat, bpm])
	if result.is_empty():
		return []
	var dedup := {}
	for entry in result:
		dedup[float(entry[0])] = float(entry[1])
	var beats := dedup.keys()
	beats.sort()
	var sorted_result := []
	for b in beats:
		sorted_result.append([b, dedup[b]])
	return sorted_result


static func parse_bpms(sm_text: String) -> Array:
	var rpb := parse_rows_per_beat(sm_text)
	var result := parse_bpms_raw(extract_tag(sm_text, "BPMS"), rpb)
	if not result.is_empty():
		return result
	var display := parse_display_bpm(sm_text)
	if display > 0.0:
		return [[0.0, display]]
	return [[0.0, 120.0]]


# ============================ 时间轴 ============================

## 生成时间轴段：[[段起beat, 段起秒, bpm], ...]
static func build_timeline(bpms: Array) -> Array:
	var segments := []
	for i in bpms.size():
		var beat := float(bpms[i][0])
		var bpm := float(bpms[i][1])
		if i == 0:
			segments.append([beat, 0.0, bpm])
			continue
		var prev: Array = segments[-1]
		var delta_beat := beat - float(prev[0])
		if delta_beat < 0.0:
			continue
		var delta_sec := delta_beat * (60.0 / float(prev[2])) if float(prev[2]) > 0.0 else 0.0
		segments.append([beat, float(prev[1]) + delta_sec, bpm])
	return segments if not segments.is_empty() else [[0.0, 0.0, 120.0]]


static func beat_to_sec(beat: float, segments: Array) -> float:
	var lo := 0
	var hi := segments.size() - 1
	var idx := 0
	while lo <= hi:
		var mid := (lo + hi) / 2
		if float(segments[mid][0]) <= beat:
			idx = mid
			lo = mid + 1
		else:
			hi = mid - 1
	var seg: Array = segments[idx]
	var delta := beat - float(seg[0])
	var bpm := float(seg[2])
	return float(seg[1]) + (delta * (60.0 / bpm) if bpm > 0.0 else 0.0)


static func sec_to_beat(sec: float, segments: Array) -> float:
	if segments.is_empty():
		return sec * 2.0
	var lo := 0
	var hi := segments.size() - 1
	var idx := 0
	while lo <= hi:
		var mid := (lo + hi) / 2
		if float(segments[mid][1]) <= sec:
			idx = mid
			lo = mid + 1
		else:
			hi = mid - 1
	var seg: Array = segments[idx]
	var bpm := float(seg[2])
	if bpm <= 0.0:
		return float(seg[0])
	return float(seg[0]) + (sec - float(seg[1])) * bpm / 60.0


# ============================ 谱面块收集与选择 ============================

static func _normalize(text: String) -> String:
	var re := RegEx.new()
	re.compile("[\\s_\\-]+")
	return re.sub(text.strip_edges().to_lower(), "", true)


static func count_columns(notes_text: String) -> int:
	var text := notes_text.replace("\r\n", "\n").replace("\r", "\n")
	for measure in text.split(","):
		for line in measure.split("\n"):
			var l := str(line).strip_edges()
			if not l.is_empty() and not l.begins_with("//"):
				return maxi(1, l.length())
	return 5


static func _is_dance_pad_type(charttype: String, columns: int) -> bool:
	return columns in [10, 20] and charttype.strip_edges().to_lower() in \
		["single", "hard", "double", "remix", "lover1", "lover2"]


## 谱面块上下文标识（块前 420 字符里找 lover1/lover2/couple）
static func _context_tag(sm_text: String, notes_start: int) -> String:
	var text := sm_text.replace("\r\n", "\n").replace("\r", "\n")
	var start := clampi(notes_start, 0, text.length())
	var before := text.substr(maxi(0, start - 420), mini(420, start))
	var lines := []
	for line in before.split("\n"):
		var l := str(line).strip_edges()
		if not l.is_empty():
			lines.append(l)
	var tail: Array = lines.slice(maxi(0, lines.size() - 10))
	tail.reverse()
	for line in tail:
		var norm := _normalize(line)
		if norm.is_empty():
			continue
		if norm.contains("lover2"):
			return "lover2"
		if norm.contains("lover1"):
			return "lover1"
		if norm.contains("couple") or str(line).contains("情侣"):
			return "couple"
	return ""


static func _is_couple_tag(text: String) -> bool:
	var norm := _normalize(text)
	if norm.is_empty():
		return false
	for kw in ["lover1", "lover2", "lover", "couple", "情侣"]:
		if norm.contains(kw):
			return true
	return norm.contains("情侣")


## 收集全部谱面候选（SM #NOTES 六字段 + SSC #NOTEDATA 块）
static func collect_candidates(sm_text: String) -> Array:
	var candidates := []
	var text := sm_text.replace("\r\n", "\n").replace("\r", "\n")

	var re := RegEx.new()
	re.compile("(?is)#NOTES\\s*:(.*?);")
	for m in re.search_all(text):
		var block := m.get_string(1)
		var fields := block.split(":", true, 5)
		if fields.size() >= 6:
			candidates.append({
				"charttype": str(fields[0]).strip_edges().to_lower(),
				"description": str(fields[1]).strip_edges(),
				"difficulty": str(fields[2]).strip_edges(),
				"meter": str(fields[3]).strip_edges(),
				"notes": str(fields[5]),
				"context_tag": _context_tag(text, m.get_start()),
			})
		elif fields.size() >= 5:
			# 舞推变体：type:desc:diff:meter:notes
			candidates.append({
				"charttype": str(fields[0]).strip_edges().to_lower(),
				"description": str(fields[1]).strip_edges(),
				"difficulty": str(fields[2]).strip_edges(),
				"meter": str(fields[3]).strip_edges(),
				"notes": str(fields[4]),
				"context_tag": _context_tag(text, m.get_start()),
			})

	# SSC：#NOTEDATA:; 块
	var re_ssc := RegEx.new()
	re_ssc.compile("(?ims)^\\s*#NOTEDATA\\s*:\\s*;\\s*(.*?)(?=^\\s*#NOTEDATA\\s*:\\s*;|\\z)")
	for m in re_ssc.search_all(text):
		var block := m.get_string(1)
		var notedata := extract_tag_raw(block, "NOTES")
		if notedata.strip_edges().is_empty():
			continue
		candidates.append({
			"charttype": extract_tag(block, "STEPSTYPE").to_lower(),
			"description": extract_tag(block, "DESCRIPTION"),
			"difficulty": extract_tag(block, "DIFFICULTY"),
			"meter": extract_tag(block, "METER"),
			"notes": notedata,
			"context_tag": "",
			"local_bpms": extract_tag_raw(block, "BPMS"),
			"local_offset": extract_tag(block, "OFFSET"),
		})
	return candidates


## 优先级（移植自 _谱面候选优先级）：返回 [基础优先级, meter, 列数, 恋爱优先]
static func _candidate_priority(charttype: String, columns: int, meter_text: String, prefer_double: bool) -> Array:
	var ct := charttype.strip_edges().to_lower()
	var meter := int(_first_number(meter_text)) if not is_nan(_first_number(meter_text)) else 0
	var base := 10

	if _is_dance_pad_type(ct, columns):
		if prefer_double:
			match ct:
				"double": base = 95
				"lover1", "lover2": base = 90
				"hard": base = 70
				"single": base = 60
				"remix": base = 50
				_: base = 10
		else:
			match ct:
				"hard": base = 90
				"single": base = 80
				"remix": base = 70
				"double": base = 55
				"lover1", "lover2": base = 40
				_: base = 10
		return [base, meter, columns, 1 if ct == "lover1" else 0]

	if prefer_double:
		if ct.contains("pump-double"): base = 80
		elif ct.contains("pump-single"): base = 70
		elif ct.contains("dance-single"): base = 60
		elif ct.contains("single"): base = 50
		elif ct.contains("double"): base = 40
	else:
		if ct.contains("pump-single"): base = 80
		elif ct.contains("dance-single"): base = 70
		elif ct.contains("single"): base = 60
		elif ct.contains("pump-double"): base = 50
		elif ct.contains("double"): base = 40
	return [base, meter, columns, 0]


static func _candidate_matches(candidate: Dictionary, tag: String) -> bool:
	var target := _normalize(tag)
	if target.is_empty():
		return false
	for key in ["charttype", "description", "difficulty", "context_tag"]:
		var v := _normalize(str(candidate.get(key, "")))
		if v == target or v.contains(target):
			return true
	return false


## 选择谱面块：返回候选 Dictionary（含 notes/charttype/columns），找不到返回 {}
static func select_candidate(sm_text: String, prefer_double: bool,
		target_charttype := "", target_keyword := "", strict := false) -> Dictionary:
	var candidates := collect_candidates(sm_text)
	if candidates.is_empty():
		return {}
	for c in candidates:
		c["columns"] = count_columns(str(c["notes"]))

	# 目标匹配（严格模式匹配不到就失败）
	var target := target_charttype if not target_charttype.is_empty() else target_keyword
	if not target.is_empty():
		var matched := []
		for c in candidates:
			if _candidate_matches(c, target):
				matched.append(c)
		if not matched.is_empty():
			candidates = matched
		elif strict:
			return {}

	var best: Dictionary = candidates[0]
	var best_pri := _candidate_priority(str(best["charttype"]), int(best["columns"]),
			str(best.get("meter", "")), prefer_double)
	for i in range(1, candidates.size()):
		var c: Dictionary = candidates[i]
		var pri := _candidate_priority(str(c["charttype"]), int(c["columns"]),
				str(c.get("meter", "")), prefer_double)
		for k in 4:
			if float(pri[k]) > float(best_pri[k]):
				best = c
				best_pri = pri
				break
			elif float(pri[k]) < float(best_pri[k]):
				break
	return best


# ============================ 事件构建 ============================


static func _json_tick_per_beat(data: Dictionary) -> int:
	var candidates := ["tickPerBeat", "ticksPerBeat", "linePerBeat", "linesPerBeat",
		"rowPerBeat", "rowsPerBeat", "resolution"]
	for node in [data, data.get("scoreInfo", {})]:
		if not node is Dictionary:
			continue
		for key in candidates:
			if (node as Dictionary).has(key):
				var value := int(round(float((node as Dictionary).get(key, 0))))
				if value > 0:
					return value
	var boards: Array = data.get("boards", [])
	if not boards.is_empty() and boards[0] is Dictionary:
		for key in candidates:
			if (boards[0] as Dictionary).has(key):
				var value := int(round(float((boards[0] as Dictionary).get(key, 0))))
				if value > 0:
					return value
	return 96


static func _add_compat_patch(patches: Dictionary, patch_name: String) -> void:
	if not patch_name.is_empty():
		patches[patch_name] = true


static func _compat_patch_list(patches: Dictionary) -> Array:
	var result: Array = patches.keys()
	result.sort()
	return result


static func _normalize_json_bpms(data: Dictionary, ticks_per_beat: int,
		patches: Dictionary) -> Array:
	var bpm_by_line := {}
	var valid_count := 0
	var raw_count := 0
	var duplicate_count := 0
	for raw_bpm in data.get("bpms", []):
		raw_count += 1
		if not raw_bpm is Dictionary:
			_add_compat_patch(patches, "invalid_bpm_entries_ignored")
			continue
		var line_no := int((raw_bpm as Dictionary).get("lineNo",
			(raw_bpm as Dictionary).get("line", 0)))
		var bpm := float((raw_bpm as Dictionary).get("bpmVal",
			(raw_bpm as Dictionary).get("bpm", 0.0)))
		if line_no < 0 or not is_finite(bpm) or bpm <= 0.0:
			_add_compat_patch(patches, "invalid_bpm_entries_ignored")
			continue
		if bpm_by_line.has(line_no):
			duplicate_count += 1
		bpm_by_line[line_no] = bpm # 同一行最后一个有效值获胜，与旧项目一致。
		valid_count += 1
	if duplicate_count > 0:
		_add_compat_patch(patches, "duplicate_bpm_lines_collapsed")
	if valid_count < raw_count:
		_add_compat_patch(patches, "invalid_bpm_entries_ignored")
	if bpm_by_line.is_empty():
		_add_compat_patch(patches, "missing_bpm_defaulted")
		return [[0.0, 120.0]]
	var lines: Array = bpm_by_line.keys()
	lines.sort()
	var bpms: Array = []
	for line_no in lines:
		bpms.append([float(int(line_no)) / float(maxi(1, ticks_per_beat)),
			float(bpm_by_line[line_no])])
	if float(bpms[0][0]) > 0.0:
		bpms.push_front([0.0, float(bpms[0][1])])
		_add_compat_patch(patches, "initial_bpm_backfilled")
	return bpms


static func _recognized_json_arrow_type(arrow_type: int) -> bool:
	return arrow_type in [0, 1, 2, 3, 4, 5, 6, 7, 8]


static func _json_last_playable_beat(data: Dictionary, ticks_per_beat: int,
		patches: Dictionary) -> float:
	var last_line := 0
	var boards: Array = data.get("boards", [])
	if boards.is_empty() or not boards[0] is Dictionary:
		return 0.0
	# build_json_events 当前只消费主 board，时长估算必须使用同一数据边界；
	# 否则未选中的备用 board 可能把当前谱面的时长无故拉长。
	for raw_line in (boards[0] as Dictionary).get("lineDatas", []):
		if not raw_line is Dictionary:
			continue
		var line_no := int((raw_line as Dictionary).get("lineNo", 0))
		if line_no < 0:
			_add_compat_patch(patches, "invalid_note_fields_sanitized")
			continue
		for raw_arrow in (raw_line as Dictionary).get("arrows", []):
			if not raw_arrow is Dictionary:
				_add_compat_patch(patches, "invalid_note_fields_sanitized")
				continue
			var arrow_type := int((raw_arrow as Dictionary).get("aType", -1))
			if not _recognized_json_arrow_type(arrow_type):
				continue
			var raw_length := int((raw_arrow as Dictionary).get("length", 0))
			if raw_length < 0:
				_add_compat_patch(patches, "invalid_note_fields_sanitized")
			last_line = maxi(last_line, line_no + maxi(0, raw_length))
	return float(last_line) / float(maxi(1, ticks_per_beat))


static func _json_duration_bpms(bpms: Array, last_playable_beat: float,
		patches: Dictionary) -> Array:
	var result: Array = bpms.duplicate(true)
	while result.size() > 1:
		var final_entry: Array = result[-1]
		var final_beat := float(final_entry[0])
		var final_bpm := float(final_entry[1])
		if final_bpm >= JSON_TERMINAL_FREEZE_BPM_THRESHOLD:
			break
		var remaining_beat := last_playable_beat - final_beat
		if remaining_beat <= 0.0:
			result.pop_back()
			_add_compat_patch(patches, "terminal_low_bpm_excluded_from_duration")
			continue
		var tail_seconds := remaining_beat * 60.0 / final_bpm
		if tail_seconds < JSON_TERMINAL_FREEZE_ABNORMAL_SEC:
			break
		result.pop_back()
		_add_compat_patch(patches, "terminal_low_bpm_excluded_from_duration")
	return result if not result.is_empty() else [[0.0, 120.0]]


static func _json_visual_pulses(data: Dictionary, ticks_per_beat: int,
		timeline: Array, offset: float) -> Array:
	var result: Array = []
	var boards: Array = data.get("boards", [])
	if boards.is_empty() or not boards[0] is Dictionary:
		return result
	for raw_item in (boards[0] as Dictionary).get("bpmSpeeds", []):
		if not raw_item is Dictionary:
			continue
		var start_beat := float((raw_item as Dictionary).get("beats", NAN))
		if is_nan(start_beat):
			start_beat = float(int((raw_item as Dictionary).get("lineNo", 0))) \
				/ float(maxi(1, ticks_per_beat))
		var speed := float((raw_item as Dictionary).get("speed", 1.0))
		var length := float((raw_item as Dictionary).get("length", 0.0))
		if not is_finite(start_beat) or not is_finite(speed) or speed <= 8.0:
			continue
		if not is_finite(length) or length <= 0.000001:
			length = 0.125
		var end_beat := start_beat + maxf(0.03125, length)
		var start_sec := beat_to_sec(start_beat, timeline) - offset
		var end_sec := beat_to_sec(end_beat, timeline) - offset
		if not is_finite(start_sec) or not is_finite(end_sec):
			continue
		if end_sec <= start_sec + 0.000001:
			end_sec = start_sec + 0.05
		var intensity := clampf(log(maxf(1.0, speed)) / log(10.0) / 3.0, 0.15, 1.0)
		result.append({"start_sec": start_sec, "end_sec": end_sec,
			"intensity": intensity, "speed": speed})
	return result


static func _json_fake_render_window(start_beat: float, end_beat: float,
		bpms: Array, timeline: Array, offset: float) -> Vector2:
	var extreme_start := NAN
	var extreme_end := NAN
	for i in bpms.size():
		var entry: Array = bpms[i]
		if float(entry[1]) < JSON_EXTREME_VISUAL_BPM_THRESHOLD:
			continue
		var segment_start := float(entry[0])
		var segment_end := float(bpms[i + 1][0]) if i + 1 < bpms.size() else segment_start + 1.0
		if segment_start <= start_beat and start_beat < segment_end:
			extreme_start = segment_start
			extreme_end = maxf(segment_end, segment_start + 0.03125)
			break
	if is_nan(extreme_start):
		var start_sec := beat_to_sec(start_beat, timeline) - offset
		var end_sec := beat_to_sec(end_beat, timeline) - offset
		return Vector2(start_sec, maxf(start_sec, end_sec))
	var window_start := beat_to_sec(maxf(0.0, extreme_start - 1.0), timeline) - offset + 0.06
	var normalized_start := clampf((start_beat - extreme_start) /
		maxf(0.000001, extreme_end - extreme_start), 0.0, 1.0)
	var normalized_end := clampf((end_beat - extreme_start) /
		maxf(0.000001, extreme_end - extreme_start), normalized_start, 1.0)
	var window_duration := 1.4
	return Vector2(window_start + normalized_start * window_duration,
		window_start + normalized_end * window_duration)


static func _json_mode_text(data: Dictionary) -> String:
	var values := PackedStringArray()
	for node in [data, data.get("scoreInfo", {})]:
		if not node is Dictionary:
			continue
		for key in ["mode", "style", "chartType", "chart_type", "gameMode", "game_mode",
				"difficulty", "type", "玩法", "模式", "谱面类型"]:
			var value := str((node as Dictionary).get(key, "")).strip_edges()
			if not value.is_empty():
				values.append(value)
	return " ".join(values).to_lower()


static func json_mode_info_from_data(data: Dictionary) -> Dictionary:
	var text := _json_mode_text(data)
	var has_player2 := false
	for raw_board in data.get("boards", []):
		if not raw_board is Dictionary:
			continue
		for raw_line in (raw_board as Dictionary).get("lineDatas", []):
			if not raw_line is Dictionary:
				continue
			for raw_arrow in (raw_line as Dictionary).get("arrows", []):
				if raw_arrow is Dictionary and int((raw_arrow as Dictionary).get("player", 1)) == 2:
					has_player2 = true
					break
			if has_player2:
				break
		if has_player2:
			break
	var explicit_couple := text.contains("lover") or text.contains("couple") or text.contains("情侣")
	var explicit_double := text.contains("double") or text.contains("club") \
		or text.contains("双踏板") or text.contains("双人")
	var style := "表演"
	if explicit_couple:
		style = "情侣"
	elif text.contains("remix") or text.contains("mix") or text.contains("混音"):
		style = "混音"
	elif text.contains("hard") or text.contains("crazy") or text.contains("devil") \
			or text.contains("疯狂"):
		style = "疯狂"
	elif explicit_double or has_player2:
		style = "双踏板"
	elif text.contains("learn") or text.contains("easy") or text.contains("学习"):
		style = "学习"
	var columns := 10 if explicit_couple or explicit_double or has_player2 else 5
	var charttype := "json-couple" if explicit_couple else ("json-double" if columns >= 10 else "json-single")
	return {"style": style, "charttype": charttype, "columns": columns,
		"has_player2": has_player2, "explicit_double": explicit_double,
		"couple": explicit_couple}


static func json_mode_info(json_path: String) -> Dictionary:
	if not FileAccess.file_exists(json_path):
		return {"style": "表演", "charttype": "json-single", "columns": 5,
			"has_player2": false, "explicit_double": false, "couple": false}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	return json_mode_info_from_data(parsed) if parsed is Dictionary else {
		"style": "表演", "charttype": "json-single", "columns": 5,
		"has_player2": false, "explicit_double": false, "couple": false,
	}


static func build_json_events(json_path: String, _prefer_double := false) -> Dictionary:
	var default_bpms := [[0.0, 120.0]]
	var default_timeline := build_timeline(default_bpms)
	var empty := {
		"events": [], "hand_events": [], "fake_events": [],
		"visual_pulses": [], "offset": 0.0, "duration": 0.0,
		"columns": 5, "charttype": "json-single", "bpms": default_bpms,
		"timeline": default_timeline, "duration_timeline": default_timeline,
		"ticks_per_beat": JSON_DEFAULT_TICKS_PER_BEAT,
		"compat_patches": [], "error": "",
	}
	if not FileAccess.file_exists(json_path):
		empty["error"] = "读取失败"
		return empty
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not parsed is Dictionary:
		empty["error"] = "JSON 格式无效"
		return empty
	var data: Dictionary = parsed
	var patches := {}
	var score_info: Dictionary = data.get("scoreInfo", {})
	var offset := float(score_info.get("offset", data.get("offset", 0.0)))
	if not is_finite(offset):
		offset = 0.0
		_add_compat_patch(patches, "invalid_offset_defaulted")
	var ticks_per_beat := maxi(1, _json_tick_per_beat(data))
	var bpms := _normalize_json_bpms(data, ticks_per_beat, patches)
	var timeline := build_timeline(bpms)
	var last_playable_beat := _json_last_playable_beat(data, ticks_per_beat, patches)
	var duration_bpms := _json_duration_bpms(bpms, last_playable_beat, patches)
	var duration_timeline := build_timeline(duration_bpms)
	var events: Array = []
	var hand_events: Array = []
	var fake_events: Array = []
	var max_duration_sec := 0.0
	var has_player2 := false
	var boards: Array = data.get("boards", [])
	if boards.is_empty() or not boards[0] is Dictionary:
		empty["offset"] = offset
		empty["bpms"] = bpms
		empty["timeline"] = timeline
		empty["duration_timeline"] = duration_timeline
		empty["compat_patches"] = _compat_patch_list(patches)
		empty["error"] = "JSON 缺少 boards"
		return empty
	var foot_map := {1: 0, 2: 1, 4: 2, 6: 3, 7: 4}
	var hand_map := {0: "ll", 3: "tt", 5: "bb", 8: "rr"}
	for raw_line in (boards[0] as Dictionary).get("lineDatas", []):
		if not raw_line is Dictionary:
			_add_compat_patch(patches, "invalid_note_fields_sanitized")
			continue
		var line_no := int((raw_line as Dictionary).get("lineNo", 0))
		if line_no < 0:
			_add_compat_patch(patches, "invalid_note_fields_sanitized")
			continue
		var start_beat := float(line_no) / float(ticks_per_beat)
		for raw_arrow in (raw_line as Dictionary).get("arrows", []):
			if not raw_arrow is Dictionary:
				_add_compat_patch(patches, "invalid_note_fields_sanitized")
				continue
			var arrow_type := int((raw_arrow as Dictionary).get("aType", -1))
			if not foot_map.has(arrow_type) and not hand_map.has(arrow_type):
				continue
			var raw_player := int((raw_arrow as Dictionary).get("player", 1))
			var player := clampi(raw_player, 1, 2)
			var raw_length := int((raw_arrow as Dictionary).get("length", 0))
			var length_lines := maxi(0, raw_length)
			if raw_player != player or raw_length < 0:
				_add_compat_patch(patches, "invalid_note_fields_sanitized")
			has_player2 = has_player2 or player == 2
			var end_beat := start_beat + float(length_lines) / float(ticks_per_beat)
			var start_sec := beat_to_sec(start_beat, timeline) - offset
			var end_sec := beat_to_sec(end_beat, timeline) - offset
			var duration_end_sec := beat_to_sec(end_beat, duration_timeline) - offset
			if not is_finite(start_sec) or not is_finite(end_sec) \
					or not is_finite(duration_end_sec):
				_add_compat_patch(patches, "non_finite_event_ignored")
				continue
			if end_sec < start_sec:
				var swap_sec := start_sec
				start_sec = end_sec
				end_sec = swap_sec
				var swap_beat := start_beat
				start_beat = end_beat
				end_beat = swap_beat
				_add_compat_patch(patches, "reversed_event_range_repaired")
			var event_type := "hold" if length_lines > 0 else "tap"
			var is_fake := bool((raw_arrow as Dictionary).get("isFaked", false))
			var event := {"start_sec": start_sec, "end_sec": end_sec,
				"start_beat": start_beat, "end_beat": end_beat,
				"type": event_type, "player": player}
			if foot_map.has(arrow_type):
				event["track"] = int(foot_map[arrow_type]) + (5 if player == 2 else 0)
			else:
				event["dir"] = str(hand_map[arrow_type])
			if is_fake:
				var render_window := _json_fake_render_window(start_beat, end_beat,
					bpms, timeline, offset)
				event["render_only"] = true
				event["render_start_sec"] = render_window.x
				event["render_end_sec"] = maxf(render_window.x, render_window.y)
				fake_events.append(event)
				_add_compat_patch(patches, "fake_notes_excluded_from_judgement")
			elif foot_map.has(arrow_type):
				events.append(event)
			else:
				hand_events.append(event)
			max_duration_sec = maxf(max_duration_sec, duration_end_sec)
	events.sort_custom(func(a, b): return float(a["start_sec"]) < float(b["start_sec"]))
	hand_events.sort_custom(func(a, b): return float(a["start_sec"]) < float(b["start_sec"]))
	fake_events.sort_custom(func(a, b):
		return float(a.get("render_start_sec", a.get("start_sec", 0.0))) \
			< float(b.get("render_start_sec", b.get("start_sec", 0.0))))
	var mode_info := json_mode_info_from_data(data)
	var columns := int(mode_info.get("columns", 10 if has_player2 else 5))
	return {
		"events": events, "hand_events": hand_events, "fake_events": fake_events,
		"visual_pulses": _json_visual_pulses(data, ticks_per_beat, timeline, offset),
		"offset": offset, "duration": maxf(0.0, max_duration_sec + 2.0),
		"columns": columns,
		"charttype": str(mode_info.get("charttype",
			"json-double" if columns >= 10 else "json-single")),
		"bpms": bpms, "timeline": timeline,
		"duration_timeline": duration_timeline,
		"ticks_per_beat": ticks_per_beat,
		"compat_patches": _compat_patch_list(patches),
		"error": "" if not events.is_empty() else "JSON 没有可玩的脚键音符",
	}


## 返回：{events, hand_events, offset, duration, columns, charttype, bpms, timeline, error}
## events 项：{track, start_sec, end_sec, start_beat, end_beat, type, player}
## hand_events 项：{dir, start_sec, end_sec, start_beat, end_beat, type, player}
static func build_events(sm_path: String, prefer_double := false,
		target_charttype := "", target_keyword := "", strict := false) -> Dictionary:
	if sm_path.to_lower().ends_with(".json"):
		return build_json_events(sm_path, prefer_double)
	var empty := {
		"events": [], "hand_events": [], "offset": 0.0, "duration": 0.0,
		"columns": 5, "charttype": "", "bpms": [[0.0, 120.0]],
		"timeline": build_timeline([[0.0, 120.0]]), "error": "",
	}
	var sm_text := read_text(sm_path)
	if sm_text.is_empty():
		empty["error"] = "读取失败"
		return empty

	var offset := parse_offset(sm_text)
	var bpms := parse_bpms(sm_text)
	var candidate := select_candidate(sm_text, prefer_double, target_charttype, target_keyword, strict)
	if candidate.is_empty():
		empty["offset"] = offset
		empty["bpms"] = bpms
		empty["timeline"] = build_timeline(bpms)
		empty["error"] = "无谱面块"
		return empty

	# SSC 块局部 OFFSET/BPMS 覆盖
	var local_offset := str(candidate.get("local_offset", "")).strip_edges()
	if not local_offset.is_empty():
		var v := _first_number(local_offset)
		if not is_nan(v):
			offset = v
	var local_bpms := str(candidate.get("local_bpms", ""))
	if not local_bpms.strip_edges().is_empty():
		var parsed := parse_bpms_raw(local_bpms, parse_rows_per_beat(sm_text))
		if not parsed.is_empty():
			bpms = parsed

	var timeline := build_timeline(bpms)
	var notes_text := str(candidate["notes"]).replace("\r\n", "\n").replace("\r", "\n")
	var columns := int(candidate["columns"])
	var charttype := str(candidate["charttype"])

	# 是否走舞推 10 槽位组解析
	var dance_pad := _is_dance_pad_type(charttype, columns)
	if not dance_pad and columns in [10, 20]:
		if charttype in ["pump-double", "pump-couple", "dance-couple", "pump-routine", "dance-routine"]:
			var ctx := str(candidate.get("context_tag", ""))
			if _is_couple_tag(ctx) or _is_couple_tag(target_keyword) or _is_couple_tag(target_charttype):
				dance_pad = true

	var measures := notes_text.split(",")
	if dance_pad:
		return _build_dance_pad_events(measures, columns, offset, timeline, bpms, charttype)
	return _build_generic_events(measures, columns, offset, timeline, bpms, charttype)


static func _measure_lines(measure: String) -> Array:
	var lines := []
	for line in measure.split("\n"):
		var l := str(line).strip_edges()
		if not l.is_empty() and not l.begins_with("//"):
			lines.append(l)
	return lines


## 通用解析：列直接映射轨道
static func _build_generic_events(measures: PackedStringArray, columns: int, offset: float,
		timeline: Array, bpms: Array, charttype: String) -> Dictionary:
	var events := []
	var open_holds := {}  # track -> [start_sec, start_beat]
	var max_sec := 0.0

	for mi in measures.size():
		var lines := _measure_lines(measures[mi])
		if lines.is_empty():
			continue
		var divisions := lines.size()
		for li in lines.size():
			var line: String = lines[li]
			if line.length() < columns:
				continue
			var beat := float(mi) * 4.0 + (float(li) / float(maxi(1, divisions))) * 4.0
			var t := beat_to_sec(beat, timeline) - offset
			for col in columns:
				var ch := line[col]
				if ch == "0":
					continue
				if ch == "1":
					events.append({"track": col, "start_sec": t, "end_sec": t,
						"start_beat": beat, "end_beat": beat, "type": "tap", "player": 1})
					max_sec = maxf(max_sec, t)
				elif ch == "2" or ch == "4":
					open_holds[col] = [t, beat]
					max_sec = maxf(max_sec, t)
				elif ch == "3":
					if open_holds.has(col):
						var head: Array = open_holds[col]
						open_holds.erase(col)
						var st := float(head[0])
						var sb := float(head[1])
						var ed := t
						var eb := beat
						if ed < st:
							var tmp := st; st = ed; ed = tmp
							var tmpb := sb; sb = eb; eb = tmpb
						events.append({"track": col, "start_sec": st, "end_sec": ed,
							"start_beat": sb, "end_beat": eb, "type": "hold", "player": 1})
						max_sec = maxf(max_sec, ed)

	events.sort_custom(func(a, b): return float(a["start_sec"]) < float(b["start_sec"]))
	return {
		"events": events, "hand_events": [], "offset": offset,
		"duration": maxf(0.0, max_sec + 2.0), "columns": columns,
		"charttype": charttype, "bpms": bpms, "timeline": timeline, "error": "",
	}


## 舞推解析：每组 10 槽位（脚 5 + 手 4），支持 double 20 列两组
static func _build_dance_pad_events(measures: PackedStringArray, columns: int, offset: float,
		timeline: Array, bpms: Array, _charttype: String) -> Dictionary:
	var group_count := maxi(1, columns / SLOTS_PER_GROUP)

	# 第一遍：找活跃组（有脚音符的组优先；分组归一按固定组索引排序，防 1P/2P 串色）
	var active_main := {}
	var active_any := {}
	for mi in measures.size():
		for line in _measure_lines(measures[mi]):
			var l: String = line
			if l.length() < columns:
				continue
			for g in group_count:
				var seg := l.substr(g * SLOTS_PER_GROUP, SLOTS_PER_GROUP)
				if seg.lstrip("0").rstrip("0").is_empty() and not seg.contains("1") \
						and not seg.contains("2") and not seg.contains("3") and not seg.contains("4"):
					continue
				active_any[g] = true
				for slot in FOOT_SLOT_TO_TRACK:
					if slot < seg.length() and seg[slot] != "0":
						active_main[g] = true
						break
	var main_groups: Array = active_main.keys() if not active_main.is_empty() else active_any.keys()
	if main_groups.is_empty():
		main_groups = [0]
	main_groups.sort()
	var group_map := {}  # 组索引 -> 归一玩家索引(0/1)
	for i in mini(2, main_groups.size()):
		group_map[int(main_groups[i])] = i

	var events := []
	var hand_events := []
	var open_main := {}   # "player:track" -> [start_sec, start_beat]
	var open_hand := {}   # "player:dir" -> [start_sec, start_beat]
	var max_sec := 0.0

	for mi in measures.size():
		var lines := _measure_lines(measures[mi])
		if lines.is_empty():
			continue
		var divisions := lines.size()
		for li in lines.size():
			var line: String = lines[li]
			if line.length() < columns:
				continue
			var beat := float(mi) * 4.0 + (float(li) / float(maxi(1, divisions))) * 4.0
			var t := beat_to_sec(beat, timeline) - offset

			for g in group_count:
				var seg := line.substr(g * SLOTS_PER_GROUP, SLOTS_PER_GROUP)
				if seg.length() < SLOTS_PER_GROUP:
					continue
				var player_idx = group_map.get(g, null)

				for slot in SLOTS_PER_GROUP:
					var ch := seg[slot]
					if ch == "0":
						continue

					if FOOT_SLOT_TO_TRACK.has(slot):
						if player_idx == null:
							continue
						var track: int = int(player_idx) * 5 + int(FOOT_SLOT_TO_TRACK[slot])
						var key := "%d:%d" % [int(player_idx), track]
						if ch == "1":
							events.append({"track": track, "start_sec": t, "end_sec": t,
								"start_beat": beat, "end_beat": beat, "type": "tap",
								"player": int(player_idx) + 1})
							max_sec = maxf(max_sec, t)
						elif ch == "2" or ch == "4":
							open_main[key] = [t, beat]
							max_sec = maxf(max_sec, t)
						elif ch == "3":
							if open_main.has(key):
								var head: Array = open_main[key]
								open_main.erase(key)
								var st := float(head[0]); var sb := float(head[1])
								var ed := t; var eb := beat
								if ed < st:
									var tmp := st; st = ed; ed = tmp
									var tmpb := sb; sb = eb; eb = tmpb
								events.append({"track": track, "start_sec": st, "end_sec": ed,
									"start_beat": sb, "end_beat": eb, "type": "hold",
									"player": int(player_idx) + 1})
								max_sec = maxf(max_sec, ed)
						continue

					# 手键装饰
					var dir := str(HAND_SLOT_TO_DIR.get(slot, ""))
					if dir.is_empty():
						continue
					var hp_idx = player_idx
					if hp_idx == null:
						if group_map.size() == 1:
							hp_idx = 0
						else:
							continue
					var player_no := int(hp_idx) + 1
					var hkey := "%d:%s" % [int(hp_idx), dir]
					if ch == "1":
						hand_events.append({"dir": dir, "start_sec": t, "end_sec": t,
							"start_beat": beat, "end_beat": beat, "type": "tap", "player": player_no})
						max_sec = maxf(max_sec, t)
					elif ch == "2" or ch == "4":
						open_hand[hkey] = [t, beat]
						max_sec = maxf(max_sec, t)
					elif ch == "3":
						if open_hand.has(hkey):
							var head: Array = open_hand[hkey]
							open_hand.erase(hkey)
							var st := float(head[0]); var sb := float(head[1])
							var ed := t; var eb := beat
							if ed < st:
								var tmp := st; st = ed; ed = tmp
								var tmpb := sb; sb = eb; eb = tmpb
							hand_events.append({"dir": dir, "start_sec": st, "end_sec": ed,
								"start_beat": sb, "end_beat": eb, "type": "hold", "player": player_no})
							max_sec = maxf(max_sec, ed)

	events.sort_custom(func(a, b): return float(a["start_sec"]) < float(b["start_sec"]))
	hand_events.sort_custom(func(a, b): return float(a["start_sec"]) < float(b["start_sec"]))
	var result_columns := 10 if group_map.size() >= 2 else 5
	return {
		"events": events, "hand_events": hand_events, "offset": offset,
		"duration": maxf(0.0, max_sec + 2.0), "columns": result_columns,
		"charttype": "pump-double" if result_columns >= 10 else "pump-single",
		"bpms": bpms, "timeline": timeline, "error": "",
	}


## 情侣双谱合并：lover1 -> 轨道0~4(玩家1)，lover2 -> 轨道5~9(玩家2)
static func build_couple_events(sm_path: String) -> Dictionary:
	var sm_text := read_text(sm_path)
	if sm_text.is_empty():
		return {"error": "情侣谱面读取失败"}
	var candidates := collect_candidates(sm_text)
	var has_l1 := false
	var has_l2 := false
	for c in candidates:
		if _candidate_matches(c, "lover1"):
			has_l1 = true
		if _candidate_matches(c, "lover2"):
			has_l2 = true
	if not has_l1 or not has_l2:
		return {"error": "情侣谱面缺少 lover1/lover2"}

	var left := build_events(sm_path, false, "", "lover1", true)
	var right := build_events(sm_path, false, "", "lover2", true)
	if (left["events"] as Array).is_empty() and (left["hand_events"] as Array).is_empty():
		return {"error": "情侣谱面解析不完整"}
	if (right["events"] as Array).is_empty() and (right["hand_events"] as Array).is_empty():
		return {"error": "情侣谱面解析不完整"}

	var merged := []
	var left_double := int(left["columns"]) >= 10
	var right_double := int(right["columns"]) >= 10
	for e in left["events"]:
		var ev: Dictionary = e.duplicate()
		var tr := int(ev["track"])
		ev["track"] = tr % 10 if left_double else (tr % 5)
		ev["player"] = 1
		merged.append(ev)
	for e in right["events"]:
		var ev: Dictionary = e.duplicate()
		var tr := int(ev["track"])
		ev["track"] = tr % 10 if right_double else (tr % 5 + 5)
		ev["player"] = 2
		merged.append(ev)
	merged.sort_custom(func(a, b): return float(a["start_sec"]) < float(b["start_sec"]))

	var merged_hands := []
	for e in left["hand_events"]:
		var ev: Dictionary = e.duplicate()
		ev["player"] = 1 if not left_double else (2 if int(ev.get("player", 1)) == 2 else 1)
		merged_hands.append(ev)
	for e in right["hand_events"]:
		var ev: Dictionary = e.duplicate()
		ev["player"] = 2 if not right_double else (2 if int(ev.get("player", 1)) == 2 else 1)
		merged_hands.append(ev)
	merged_hands.sort_custom(func(a, b): return float(a["start_sec"]) < float(b["start_sec"]))

	return {
		"events": merged, "hand_events": merged_hands,
		"offset": float(left["offset"]),
		"duration": maxf(float(left["duration"]), float(right["duration"])),
		"columns": 10, "charttype": "couple",
		"bpms": left["bpms"], "timeline": left["timeline"], "error": "",
	}


## 便捷：解析元数据（选歌/加载页用，不解析音符）
static func parse_meta(sm_path: String) -> Dictionary:
	var text := read_text(sm_path)
	if text.is_empty():
		return {}
	return {
		"title": extract_tag(text, "TITLE"),
		"artist": extract_tag(text, "ARTIST"),
		"music": extract_tag(text, "MUSIC"),
		"background": extract_tag(text, "BACKGROUND"),
		"banner": extract_tag(text, "BANNER"),
		"display_bpm": parse_display_bpm(text),
		"offset": parse_offset(text),
		"sample_start": _first_number(extract_tag(text, "SAMPLESTART")),
		"sample_length": _first_number(extract_tag(text, "SAMPLELENGTH")),
	}
