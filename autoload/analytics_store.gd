extends Node
## 判定分析长期存档。只保存正式、具备记录资格的聚合摘要；逐音符事件不落盘。

signal analytics_changed(chart_key: String)

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "user://feature_data/analytics_v1.json"
const MAX_RECENT_RUNS := 10
const MAX_CHARTS := 500
const MAX_FILE_BYTES := 4 * 1024 * 1024

var data_path := DEFAULT_PATH
var persist_enabled := true
var _data := {}
var _corrupt_on_load := false


func _ready() -> void:
	_load()


func _default_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"charts": {},
		"modes": {},
		"global": _empty_aggregate(),
	}


func _empty_aggregate() -> Dictionary:
	return {
		"run_count": 0,
		"sample_count": 0,
		"timing_sum": 0.0,
		"early_count": 0,
		"late_count": 0,
		"perfect": 0,
		"cool": 0,
		"good": 0,
		"miss": 0,
		"last_updated": 0,
	}


func _load() -> void:
	_corrupt_on_load = false
	if not FileAccess.file_exists(data_path):
		_data = _default_data()
		return
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(data_path))
	var parsed = parser.data
	if parse_error != OK or not parsed is Dictionary:
		_corrupt_on_load = true
		_backup_corrupt_file()
		_data = _default_data()
		return
	_data = _migrate(parsed as Dictionary)


func _migrate(source: Dictionary) -> Dictionary:
	var migrated := _default_data()
	var version := int(source.get("schema_version", 0))
	if version <= SCHEMA_VERSION:
		if source.get("charts", {}) is Dictionary:
			migrated["charts"] = (source.get("charts", {}) as Dictionary).duplicate(true)
		if source.get("modes", {}) is Dictionary:
			migrated["modes"] = (source.get("modes", {}) as Dictionary).duplicate(true)
		if source.get("global", {}) is Dictionary:
			migrated["global"] = _normalize_aggregate(source.get("global", {}))
	migrated["schema_version"] = SCHEMA_VERSION
	_normalize_loaded_data(migrated)
	return migrated


func _normalize_loaded_data(target: Dictionary) -> void:
	var charts: Dictionary = target.get("charts", {})
	for raw_key in charts.keys():
		var key := str(raw_key)
		var chart: Dictionary = charts.get(raw_key, {}) if charts.get(raw_key, {}) is Dictionary else {}
		var recent: Array = chart.get("recent", []) if chart.get("recent", []) is Array else []
		if recent.size() > MAX_RECENT_RUNS:
			recent = recent.slice(recent.size() - MAX_RECENT_RUNS)
		charts[key] = {
			"mode": str(chart.get("mode", "")),
			"recent": recent,
			"last_updated": int(chart.get("last_updated", 0)),
		}
		if key != raw_key:
			charts.erase(raw_key)
	target["charts"] = charts
	var modes: Dictionary = target.get("modes", {})
	for raw_mode in modes.keys():
		modes[str(raw_mode)] = _normalize_aggregate(modes.get(raw_mode, {}))
		if str(raw_mode) != raw_mode:
			modes.erase(raw_mode)
	target["modes"] = modes
	target["global"] = _normalize_aggregate(target.get("global", {}))


func _normalize_aggregate(raw: Variant) -> Dictionary:
	var result := _empty_aggregate()
	if not raw is Dictionary:
		return result
	for key in result.keys():
		if (raw as Dictionary).has(key):
			result[key] = (raw as Dictionary)[key]
	return result


func _backup_corrupt_file() -> void:
	var absolute := ProjectSettings.globalize_path(data_path)
	var backup := absolute + ".corrupt"
	DirAccess.remove_absolute(backup)
	DirAccess.rename_absolute(absolute, backup)


func record_run(chart_key: String, mode: String, summary: Dictionary, eligible: bool) -> bool:
	var normalized_key := chart_key.strip_edges()
	if not eligible or normalized_key.is_empty():
		return false
	if _data.is_empty():
		_data = _default_data()
	var now := int(summary.get("timestamp", Time.get_unix_time_from_system()))
	var stored := _compact_summary(summary, now)
	var charts: Dictionary = _data.get("charts", {})
	var chart: Dictionary = charts.get(normalized_key, {
		"mode": mode,
		"recent": [],
		"last_updated": now,
	})
	var recent: Array = chart.get("recent", [])
	recent.append(stored)
	if recent.size() > MAX_RECENT_RUNS:
		recent = recent.slice(recent.size() - MAX_RECENT_RUNS)
	chart["mode"] = mode
	chart["recent"] = recent
	chart["last_updated"] = now
	charts[normalized_key] = chart
	_data["charts"] = charts

	var modes: Dictionary = _data.get("modes", {})
	var mode_aggregate := _normalize_aggregate(modes.get(mode, {}))
	_update_aggregate(mode_aggregate, stored, now)
	modes[mode] = mode_aggregate
	_data["modes"] = modes
	var global_aggregate := _normalize_aggregate(_data.get("global", {}))
	_update_aggregate(global_aggregate, stored, now)
	_data["global"] = global_aggregate
	_prune_charts()
	_save()
	analytics_changed.emit(normalized_key)
	return true


func _compact_summary(summary: Dictionary, timestamp: int) -> Dictionary:
	return {
		"schema_version": int(summary.get("schema_version", 1)),
		"timestamp": timestamp,
		"sample_count": maxi(0, int(summary.get("sample_count", 0))),
		"average_diff_ms": float(summary.get("average_diff_ms", 0.0)),
		"trimmed_mean_diff_ms": float(summary.get("trimmed_mean_diff_ms",
			summary.get("average_diff_ms", 0.0))),
		"median_diff_ms": float(summary.get("median_diff_ms", 0.0)),
		"standard_deviation_ms": float(summary.get("standard_deviation_ms", 0.0)),
		"early_count": maxi(0, int(summary.get("early_count", 0))),
		"late_count": maxi(0, int(summary.get("late_count", 0))),
		"perfect": maxi(0, int(summary.get("perfect", 0))),
		"cool": maxi(0, int(summary.get("cool", 0))),
		"good": maxi(0, int(summary.get("good", 0))),
		"miss": maxi(0, int(summary.get("miss", 0))),
		"per_track": (summary.get("per_track", []) as Array).duplicate(true)
			if summary.get("per_track", []) is Array else [],
	}


func _update_aggregate(aggregate: Dictionary, run: Dictionary, timestamp: int) -> void:
	var samples := int(run.get("sample_count", 0))
	aggregate["run_count"] = int(aggregate.get("run_count", 0)) + 1
	aggregate["sample_count"] = int(aggregate.get("sample_count", 0)) + samples
	aggregate["timing_sum"] = float(aggregate.get("timing_sum", 0.0)) \
		+ float(run.get("average_diff_ms", 0.0)) * float(samples)
	for key in ["early_count", "late_count", "perfect", "cool", "good", "miss"]:
		aggregate[key] = int(aggregate.get(key, 0)) + int(run.get(key, 0))
	aggregate["last_updated"] = timestamp


func _prune_charts() -> void:
	var charts: Dictionary = _data.get("charts", {})
	if charts.size() <= MAX_CHARTS:
		return
	var keys: Array = charts.keys()
	keys.sort_custom(func(a, b):
		return int((charts[a] as Dictionary).get("last_updated", 0)) \
			< int((charts[b] as Dictionary).get("last_updated", 0)))
	while charts.size() > MAX_CHARTS and not keys.is_empty():
		charts.erase(keys.pop_front())
	_data["charts"] = charts


func _save() -> void:
	if not persist_enabled:
		return
	var absolute := ProjectSettings.globalize_path(data_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var text := JSON.stringify(_data, "  ", false)
	while text.to_utf8_buffer().size() > MAX_FILE_BYTES:
		var charts: Dictionary = _data.get("charts", {})
		if charts.is_empty():
			break
		var oldest_key := ""
		var oldest_time := 9223372036854775807
		for raw_key in charts.keys():
			var updated := int((charts[raw_key] as Dictionary).get("last_updated", 0))
			if updated < oldest_time:
				oldest_time = updated
				oldest_key = str(raw_key)
		if oldest_key.is_empty():
			break
		charts.erase(oldest_key)
		_data["charts"] = charts
		text = JSON.stringify(_data, "  ", false)
	var temp_path := data_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("AnalyticsStore: 无法写入分析存档 %s" % temp_path)
		return
	file.store_string(text)
	file.close()
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var backup_absolute := absolute + ".bak"
	DirAccess.remove_absolute(backup_absolute)
	var had_previous := FileAccess.file_exists(data_path)
	if had_previous:
		var backup_error := DirAccess.rename_absolute(absolute, backup_absolute)
		if backup_error != OK:
			DirAccess.remove_absolute(temp_absolute)
			push_warning("AnalyticsStore: 无法备份旧分析存档 %s" % error_string(backup_error))
			return
	var error := DirAccess.rename_absolute(temp_absolute, absolute)
	if error != OK:
		if had_previous and FileAccess.file_exists(backup_absolute):
			DirAccess.rename_absolute(backup_absolute, absolute)
		push_warning("AnalyticsStore: 原子替换失败，已尝试恢复旧存档 %s" % error_string(error))
		return
	DirAccess.remove_absolute(backup_absolute)


func get_chart_history(chart_key: String) -> Array:
	var chart: Dictionary = (_data.get("charts", {}) as Dictionary).get(chart_key, {})
	return (chart.get("recent", []) as Array).duplicate(true) if chart.get("recent", []) is Array else []


func get_trend(chart_key: String, mode: String) -> Dictionary:
	var history := get_chart_history(chart_key)
	var mode_aggregate := _normalize_aggregate((_data.get("modes", {}) as Dictionary).get(mode, {}))
	var global_aggregate := _normalize_aggregate(_data.get("global", {}))
	return {
		"chart_runs": history.size(),
		"chart_suggestion": JudgementAnalytics.offset_suggestion(history),
		"mode_runs": int(mode_aggregate.get("run_count", 0)),
		"mode_average_diff_ms": _aggregate_average(mode_aggregate),
		"global_runs": int(global_aggregate.get("run_count", 0)),
		"global_average_diff_ms": _aggregate_average(global_aggregate),
	}


func _aggregate_average(aggregate: Dictionary) -> float:
	var samples := int(aggregate.get("sample_count", 0))
	return float(aggregate.get("timing_sum", 0.0)) / float(samples) if samples > 0 else 0.0


func clear_all() -> void:
	_data = _default_data()
	_save()


func was_corrupt_on_load_for_test() -> bool:
	return _corrupt_on_load
