class_name JudgementAnalytics
extends RefCounted
## 单局判定分析。逐音符事件只保存在当前内存会话，不直接写玩家正式记录。

const WINDOW_SECONDS := 5.0
const WINDOW_STEP_SECONDS := 1.0
const LOSS_WEIGHT := {"perfect": 0.0, "cool": 1.0, "good": 3.0, "miss": 8.0}

var track_count := 5
var _events: Array = []
var _scoring_event_count := 0
var _live_counts := {"perfect": 0, "cool": 0, "good": 0, "miss": 0}
var _timing_sum := 0.0
var _timing_count := 0
var _early_count := 0
var _late_count := 0


func _init(p_track_count := 5) -> void:
	track_count = maxi(1, int(p_track_count))
	reset(track_count)


func reset(p_track_count := -1) -> void:
	if p_track_count > 0:
		track_count = int(p_track_count)
	_events.clear()
	_scoring_event_count = 0
	_live_counts = _empty_counts()
	_timing_sum = 0.0
	_timing_count = 0
	_early_count = 0
	_late_count = 0


func add_report(report: Variant, combo_after := 0, auto_generated := false) -> void:
	if report == null:
		return
	var event := {
		"note_index": int(report.note_index),
		"track": clampi(int(report.track), 0, maxi(0, track_count - 1)),
		"type": str(report.type),
		"judge": str(report.judge),
		"diff_ms": float(report.time_diff_ms),
		"start_sec": float(report.start_sec),
		"end_sec": float(report.end_sec),
		"combo_after": int(combo_after),
		"auto_generated": auto_generated,
		"scoring": bool(report.scoring),
	}
	_events.append(event)
	var judge := str(event["judge"])
	if bool(event["scoring"]):
		_scoring_event_count += 1
		if _live_counts.has(judge):
			_live_counts[judge] = int(_live_counts[judge]) + 1
	if _is_timing_sample(event):
		var diff := float(event["diff_ms"])
		_timing_sum += diff
		_timing_count += 1
		if diff > 0.0:
			_early_count += 1
		elif diff < 0.0:
			_late_count += 1


func event_count() -> int:
	return _events.size()


func events() -> Array:
	return _events.duplicate(true)


func quick_summary() -> Dictionary:
	return {
		"total": _scoring_event_count,
		"event_total": _events.size(),
		"counts": _live_counts.duplicate(),
		"perfect": int(_live_counts["perfect"]),
		"cool": int(_live_counts["cool"]),
		"good": int(_live_counts["good"]),
		"miss": int(_live_counts["miss"]),
		"sample_count": _timing_count,
		"early_count": _early_count,
		"late_count": _late_count,
		"average_diff_ms": _timing_sum / float(_timing_count) if _timing_count > 0 else 0.0,
	}


func summary() -> Dictionary:
	var counts := _live_counts.duplicate()
	var per_track: Array = []
	for track in track_count:
		per_track.append({
			"track": track,
			"counts": _empty_counts(),
			"average_diff_ms": 0.0,
			"median_diff_ms": 0.0,
			"sample_count": 0,
		})

	var timing_values: Array[float] = []
	var track_values: Array = []
	for track in track_count:
		track_values.append([])
	for event in _events:
		var judge := str(event.get("judge", "miss"))
		var track := clampi(int(event.get("track", 0)), 0, track_count - 1)
		var track_counts: Dictionary = per_track[track]["counts"]
		if bool(event.get("scoring", true)) and track_counts.has(judge):
			track_counts[judge] = int(track_counts[judge]) + 1
		if _is_timing_sample(event):
			var diff := float(event.get("diff_ms", 0.0))
			timing_values.append(diff)
			track_values[track].append(diff)

	for track in track_count:
		var values: Array = track_values[track]
		per_track[track]["sample_count"] = values.size()
		per_track[track]["average_diff_ms"] = _average(values)
		per_track[track]["median_diff_ms"] = _median(values)

	return {
		"schema_version": 2,
		"total": _scoring_event_count,
		"event_total": _events.size(),
		"counts": counts,
		"perfect": int(counts["perfect"]),
		"cool": int(counts["cool"]),
		"good": int(counts["good"]),
		"miss": int(counts["miss"]),
		"sample_count": timing_values.size(),
		"early_count": _early_count,
		"late_count": _late_count,
		"average_diff_ms": _timing_sum / float(_timing_count) if _timing_count > 0 else 0.0,
		"trimmed_mean_diff_ms": _trimmed_mean(timing_values),
		"median_diff_ms": _median(timing_values),
		"standard_deviation_ms": _standard_deviation(timing_values),
		"per_track": per_track,
		"worst_windows": _worst_windows(),
	}


func _is_timing_sample(event: Dictionary) -> bool:
	return bool(event.get("scoring", true)) \
		and str(event.get("judge", "miss")) != "miss" \
		and str(event.get("type", "")) != "hold_tick" \
		and not bool(event.get("auto_generated", false))


func _worst_windows() -> Array:
	if _events.is_empty():
		return []
	var buckets := {}
	var last_bucket := 0
	for event in _events:
		if not bool(event.get("scoring", true)):
			continue
		var bucket := maxi(0, int(floor(float(event.get("start_sec", 0.0)))))
		last_bucket = maxi(last_bucket, bucket)
		var item: Dictionary = buckets.get(bucket, {"loss": 0.0, "miss": 0, "events": 0})
		var judge := str(event.get("judge", "miss"))
		item["loss"] = float(item["loss"]) + float(LOSS_WEIGHT.get(judge, 0.0))
		item["miss"] = int(item["miss"]) + (1 if judge == "miss" else 0)
		item["events"] = int(item["events"]) + 1
		buckets[bucket] = item

	var candidates: Array = []
	var window_buckets := maxi(1, int(roundf(WINDOW_SECONDS / WINDOW_STEP_SECONDS)))
	for start_bucket in range(0, last_bucket + 1):
		var loss := 0.0
		var miss_count := 0
		var event_count := 0
		for offset_bucket in window_buckets:
			var item: Dictionary = buckets.get(start_bucket + offset_bucket, {})
			loss += float(item.get("loss", 0.0))
			miss_count += int(item.get("miss", 0))
			event_count += int(item.get("events", 0))
		if loss > 0.0:
			candidates.append({
				"start_sec": float(start_bucket),
				"end_sec": float(start_bucket) + WINDOW_SECONDS,
				"loss": loss,
				"miss_count": miss_count,
				"event_count": event_count,
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(float(a["loss"]), float(b["loss"])):
			return float(a["loss"]) > float(b["loss"])
		if int(a["miss_count"]) != int(b["miss_count"]):
			return int(a["miss_count"]) > int(b["miss_count"])
		return float(a["start_sec"]) < float(b["start_sec"]))

	var selected: Array = []
	for candidate in candidates:
		var overlaps := false
		for existing in selected:
			if float(candidate["start_sec"]) < float(existing["end_sec"]) \
					and float(candidate["end_sec"]) > float(existing["start_sec"]):
				overlaps = true
				break
		if not overlaps:
			selected.append(candidate)
		if selected.size() >= 3:
			break
	return selected


static func _empty_counts() -> Dictionary:
	return {"perfect": 0, "cool": 0, "good": 0, "miss": 0}


static func _average(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return float(sorted[middle])
	return (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5


static func _trimmed_mean(values: Array, trim_ratio := 0.1) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var trim_count := int(floor(float(sorted.size()) * clampf(trim_ratio, 0.0, 0.4)))
	if trim_count * 2 >= sorted.size():
		return _average(sorted)
	return _average(sorted.slice(trim_count, sorted.size() - trim_count))


static func offset_suggestion(history: Array) -> Dictionary:
	var eligible: Array[Dictionary] = []
	for raw_run in history:
		if not raw_run is Dictionary:
			continue
		var run: Dictionary = raw_run
		if int(run.get("sample_count", 0)) < 100:
			continue
		eligible.append(run)
	if eligible.size() < 3:
		return {
			"enough_samples": false,
			"confidence": "不足",
			"reason": "至少需要 3 局且每局 100 个有效判定",
			"run_count": eligible.size(),
		}
	var medians: Array[float] = []
	var positive := 0
	var negative := 0
	var total_samples := 0
	for run in eligible:
		var median := float(run.get("median_diff_ms", 0.0))
		medians.append(median)
		total_samples += int(run.get("sample_count", 0))
		if median > 2.0:
			positive += 1
		elif median < -2.0:
			negative += 1
	var consistency := float(maxi(positive, negative)) / float(eligible.size())
	var median_all := _median(medians)
	if consistency < 0.67 or absf(median_all) < 5.0:
		return {
			"enough_samples": true,
			"confidence": "低",
			"direction": "stable",
			"median_diff_ms": median_all,
			"suggested_adjustment_ms": 0,
			"sample_count": total_samples,
			"run_count": eligible.size(),
		}
	var rounded_adjustment := int(round(median_all / 5.0)) * 5
	rounded_adjustment = clampi(rounded_adjustment, -50, 50)
	var confidence := "高" if consistency >= 0.8 and eligible.size() >= 5 \
		and total_samples >= 750 else "中"
	return {
		"enough_samples": true,
		"confidence": confidence,
		"direction": "early" if median_all > 0.0 else "late",
		"median_diff_ms": median_all,
		"suggested_adjustment_ms": rounded_adjustment,
		"sample_count": total_samples,
		"run_count": eligible.size(),
		"consistency": consistency,
	}


static func _standard_deviation(values: Array) -> float:
	if values.size() < 2:
		return 0.0
	var mean := _average(values)
	var variance := 0.0
	for value in values:
		variance += pow(float(value) - mean, 2.0)
	return sqrt(variance / float(values.size()))
