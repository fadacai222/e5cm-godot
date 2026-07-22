extends Node
## 每日/周常挑战唯一状态入口：稳定生成、时钟保护、run_id 幂等、自动奖励。

signal challenges_changed
signal run_progressed(changes: Array)
signal clock_guard_changed(locked: bool)

const Catalog = preload("res://core/challenge_catalog.gd")
const Generator = preload("res://core/challenge_generator.gd")
const DATA_PATH := "user://feature_data/challenge_state_v1.json"
const SCHEMA_VERSION := 1
const MAX_PROCESSED_RUNS := 512
const MAX_UNIQUE_CHARTS_PER_PERIOD := 128
const MAX_MODES_PER_PERIOD := 12
const CLOCK_ROLLBACK_GRACE_SEC := 1800

var data_path := DATA_PATH
var persist_enabled := true
var _catalog := Catalog.new()
var _generator := Generator.new()
var _data := {}
var _last_changes: Array = []
var _corrupt_on_load := false

func _ready() -> void:
	_load()

func _default_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"catalog_version": Catalog.CATALOG_VERSION,
		"profile_id": "",
		"daily_date": "",
		"weekly_key": "",
		"daily": [],
		"weekly": [],
		"daily_meta": _empty_period_meta(),
		"weekly_meta": _empty_period_meta(),
		"processed_run_ids": [],
		"streak": {"current": 0, "best": 0, "last_completed_date": ""},
		"clock_guard": {
			"last_seen_unix": 0,
			"last_seen_date": "",
			"timezone_offset_minutes": 0,
			"locked": false,
			"message": "",
		},
	}

func _empty_period_meta() -> Dictionary:
	return {"unique_charts": {}, "modes": {}, "play_seconds": 0.0}

func _load() -> void:
	_data = _default_data()
	_corrupt_on_load = false
	if not FileAccess.file_exists(data_path):
		return
	var parser := JSON.new()
	var parse_error := parser.parse(FileAccess.get_file_as_string(data_path))
	var parsed = parser.data
	if parse_error != OK or not parsed is Dictionary:
		_corrupt_on_load = true
		_backup_corrupt_file()
		return
	_data = parsed
	_normalize_data()

func _normalize_data() -> void:
	var defaults := _default_data()
	for key in defaults.keys():
		if not _data.has(key):
			_data[key] = defaults[key]
	for array_key in ["daily", "weekly", "processed_run_ids"]:
		if not _data.get(array_key, []) is Array:
			_data[array_key] = []
	for dict_key in ["daily_meta", "weekly_meta", "streak", "clock_guard"]:
		if not _data.get(dict_key, {}) is Dictionary:
			_data[dict_key] = defaults[dict_key]
	_data["schema_version"] = SCHEMA_VERSION

func ensure_current() -> void:
	var date_key := Time.get_date_string_from_system()
	var week_key := iso_week_key(date_key)
	var now_unix := int(Time.get_unix_time_from_system())
	var timezone := int(Time.get_time_zone_from_system().get("bias", 0))
	# 已生成周期只做时钟保护和奖励补发，禁止每次回到模式页重新遍历上万首曲库。
	var needs_generation := str(_data.get("daily_date", "")) != date_key \
		or str(_data.get("weekly_key", "")) != week_key \
		or int(_data.get("catalog_version", 0)) != Catalog.CATALOG_VERSION \
		or (_data.get("daily", []) as Array).is_empty() \
		or (_data.get("weekly", []) as Array).is_empty()
	var capabilities := build_capabilities() if needs_generation else {}
	var level := 1
	if has_node("/root/ProfileStore"):
		level = int(get_node("/root/ProfileStore").get_highest_mode_level())
	ensure_period_for_test(date_key, week_key, now_unix, timezone, capabilities, level)

func initialize_for_test(profile_id: String, date_key: String, week_key: String,
		now_unix: int, timezone_offset: int, capabilities: Dictionary, player_level: int) -> void:
	_data = _default_data()
	_data["profile_id"] = profile_id
	ensure_period_for_test(date_key, week_key, now_unix, timezone_offset, capabilities, player_level)

func ensure_period_for_test(date_key: String, week_key: String, now_unix: int,
		timezone_offset: int, capabilities: Dictionary, player_level: int) -> void:
	_normalize_data()
	_ensure_profile_id()
	var guard: Dictionary = _data.get("clock_guard", {})
	var last_seen := int(guard.get("last_seen_unix", 0))
	if last_seen > 0 and now_unix + CLOCK_ROLLBACK_GRACE_SEC < last_seen:
		var was_locked := bool(guard.get("locked", false))
		guard["locked"] = true
		guard["message"] = "检测到系统时间明显倒退，挑战将在时间恢复后继续刷新；现有进度与奖励不会丢失。"
		_data["clock_guard"] = guard
		if not was_locked:
			clock_guard_changed.emit(true)
		_save()
		return
	var was_locked := bool(guard.get("locked", false))
	guard["locked"] = false
	guard["message"] = ""
	guard["last_seen_unix"] = maxi(last_seen, now_unix)
	guard["last_seen_date"] = date_key
	guard["timezone_offset_minutes"] = timezone_offset
	_data["clock_guard"] = guard
	if was_locked:
		clock_guard_changed.emit(false)

	var changed := false
	var catalog_changed := int(_data.get("catalog_version", 0)) != Catalog.CATALOG_VERSION
	if str(_data.get("daily_date", "")) != date_key or catalog_changed:
		_data["daily_date"] = date_key
		_data["daily"] = _generator.generate_daily(date_key, str(_data["profile_id"]),
			capabilities, player_level)
		_data["daily_meta"] = _empty_period_meta()
		changed = true
	if str(_data.get("weekly_key", "")) != week_key or catalog_changed:
		_data["weekly_key"] = week_key
		_data["weekly"] = _generator.generate_weekly(week_key, str(_data["profile_id"]),
			capabilities, player_level)
		_data["weekly_meta"] = _empty_period_meta()
		changed = true
	_data["catalog_version"] = Catalog.CATALOG_VERSION
	_retry_pending_rewards()
	_save()
	if changed:
		challenges_changed.emit()

func _ensure_profile_id() -> void:
	if not str(_data.get("profile_id", "")).is_empty():
		return
	var source := OS.get_unique_id()
	if source.is_empty():
		source = "%s|%s" % [OS.get_name(), Time.get_ticks_usec()]
	if has_node("/root/ProfileStore"):
		source += "|" + str(get_node("/root/ProfileStore").profile.get("昵称", "玩家"))
	_data["profile_id"] = source.sha256_text().substr(0, 24)

func build_capabilities() -> Dictionary:
	var capabilities := {
		"modes": {},
		"has_unplayed": false,
		"has_breakable_record": false,
		"has_random_source": false,
		"two_player": false,
		"owned_rewards": _owned_reward_ids(),
	}
	if not has_node("/root/SongLibrary"):
		return capabilities
	var library = get_node("/root/SongLibrary")
	var profile_store = get_node_or_null("/root/ProfileStore")
	if library.has_method("challenge_capabilities_snapshot"):
		var records: Dictionary = profile_store.records if profile_store != null else {}
		var indexed: Dictionary = library.challenge_capabilities_snapshot(records)
		if not (indexed.get("modes", {}) as Dictionary).is_empty():
			capabilities = indexed
			if has_node("/root/GameState"):
				capabilities["two_player"] = int(get_node("/root/GameState").player_count) >= 2
			capabilities["owned_rewards"] = _owned_reward_ids()
			return capabilities
	# 索引缺失或损坏时保留文件系统兜底，功能可用性优先于生成速度。
	for mode in ["花式", "竞速", "DIY"]:
		var count := 0
		var stars_map := {}
		for raw_submode in library.list_submodes(mode):
			var songs: Array = library.get_songs(mode, str(raw_submode))
			count += songs.size()
			for raw_song in songs:
				if not raw_song is Dictionary:
					continue
				var song: Dictionary = raw_song
				stars_map[int(song.get("star", 0))] = true
				if profile_store != null:
					var record: Dictionary = profile_store.get_song_record(str(song.get("sm_key", "")))
					var plays := int(record.get("游玩次数", 0))
					if plays <= 0:
						capabilities["has_unplayed"] = true
					elif int(record.get("最高分", 0)) < 1350000:
						capabilities["has_breakable_record"] = true
		if count > 0:
			var stars: Array = stars_map.keys()
			stars.sort()
			capabilities["modes"][mode] = {"count": count, "stars": stars}
	if has_node("/root/GameState"):
		capabilities["two_player"] = int(get_node("/root/GameState").player_count) >= 2
	capabilities["owned_rewards"] = _owned_reward_ids()
	return capabilities


func _owned_reward_ids() -> Array:
	var result: Array = []
	var rewards = get_node_or_null("/root/RewardService")
	if rewards == null:
		return result
	for item in rewards.owned_rewards(false):
		result.append(str(item.get("id", "")))
	return result

func process_run(run_result: Dictionary) -> Array:
	_last_changes = []
	if not _run_is_eligible(run_result):
		return []
	var run_id := str(run_result.get("run_id", "")).strip_edges()
	if run_id.is_empty():
		return []
	var processed: Array = _data.get("processed_run_ids", [])
	if run_id in processed:
		return []
	processed.append(run_id)
	while processed.size() > MAX_PROCESSED_RUNS:
		processed.pop_front()
	_data["processed_run_ids"] = processed

	_update_period_meta("daily_meta", run_result)
	_update_period_meta("weekly_meta", run_result)
	_process_period("daily", "daily_meta", run_result)
	_process_period("weekly", "weekly_meta", run_result)
	_update_streak()
	_save()
	if not _last_changes.is_empty():
		challenges_changed.emit()
		run_progressed.emit(_last_changes.duplicate(true))
	return _last_changes.duplicate(true)

func _run_is_eligible(run_result: Dictionary) -> bool:
	return bool(run_result.get("eligible", false)) \
		and not bool(run_result.get("training", false)) \
		and not bool(run_result.get("autoplay", false)) \
		and not bool(run_result.get("debug", false)) \
		and not bool(run_result.get("failed", false))

func _update_period_meta(meta_key: String, run_result: Dictionary) -> void:
	var meta: Dictionary = _data.get(meta_key, _empty_period_meta())
	var chart_hash := str(run_result.get("chart_hash", ""))
	if not chart_hash.is_empty():
		var charts: Dictionary = meta.get("unique_charts", {})
		charts[chart_hash] = true
		while charts.size() > MAX_UNIQUE_CHARTS_PER_PERIOD:
			charts.erase(charts.keys()[0])
		meta["unique_charts"] = charts
	var mode := str(run_result.get("mode", ""))
	if not mode.is_empty():
		var modes: Dictionary = meta.get("modes", {})
		modes[mode] = true
		while modes.size() > MAX_MODES_PER_PERIOD:
			modes.erase(modes.keys()[0])
		meta["modes"] = modes
	meta["play_seconds"] = float(meta.get("play_seconds", 0.0)) \
		+ maxf(0.0, float(run_result.get("duration_sec", 0.0)))
	_data[meta_key] = meta

func _process_period(period_key: String, meta_key: String, run_result: Dictionary) -> void:
	var tasks: Array = _data.get(period_key, [])
	var meta: Dictionary = _data.get(meta_key, {})
	for i in tasks.size():
		if not tasks[i] is Dictionary:
			continue
		var task: Dictionary = tasks[i]
		if bool(task.get("completed", false)):
			if not bool(task.get("claimed", false)):
				_try_claim_reward(task)
			tasks[i] = task
			continue
		var previous := float(task.get("progress", 0.0))
		var value := _catalog.evaluate(task, run_result, meta)
		var template := _catalog.template(str(task.get("template_id", "")))
		var progress := maxf(previous, value) if str(template.get("kind", "counter")) == "absolute" \
			else previous + value
		var target := maxf(1.0, float(task.get("target", 1.0)))
		progress = minf(target, progress)
		if is_equal_approx(progress, previous):
			continue
		task["progress"] = progress
		var newly_completed := previous < target and progress >= target
		if newly_completed:
			task["completed"] = true
			_try_claim_reward(task)
		tasks[i] = task
		_last_changes.append({
			"id": str(task.get("id", "")),
			"period": period_key,
			"description": str(task.get("description", _catalog.describe(task))),
			"progress": progress,
			"target": target,
			"completed": bool(task.get("completed", false)),
			"reward_id": str(task.get("reward_id", "")),
			"claimed": bool(task.get("claimed", false)),
		})
	_data[period_key] = tasks

func note_game_opened() -> Array:
	_last_changes = []
	for period_key in ["daily", "weekly"]:
		var tasks: Array = _data.get(period_key, [])
		for i in tasks.size():
			if not tasks[i] is Dictionary:
				continue
			var task: Dictionary = tasks[i]
			if str(task.get("template_id", "")) != "launch_game" or bool(task.get("completed", false)):
				continue
			task["progress"] = 1.0
			task["completed"] = true
			_try_claim_reward(task)
			tasks[i] = task
			_last_changes.append({"id": task.get("id", ""), "period": period_key,
				"description": task.get("description", ""), "progress": 1.0, "target": 1.0,
				"completed": true, "reward_id": task.get("reward_id", ""),
				"claimed": task.get("claimed", false)})
		_data[period_key] = tasks
	_update_streak()
	_save()
	if not _last_changes.is_empty():
		challenges_changed.emit()
	return _last_changes.duplicate(true)

func _try_claim_reward(task: Dictionary) -> bool:
	if bool(task.get("claimed", false)):
		return true
	var reward_id := str(task.get("reward_id", ""))
	if reward_id.is_empty() or not is_inside_tree():
		return false
	var rewards = get_node_or_null("/root/RewardService")
	if rewards == null:
		return false
	var source := "challenge:" + str(task.get("id", ""))
	var result: Dictionary = rewards.grant(reward_id, source)
	if not bool(result.get("ok", false)):
		return false
	task["claimed"] = true
	task["reward_already_owned"] = bool(result.get("already_owned", false))
	if bool(result.get("already_owned", false)) and rewards.has_method("grant_duplicate_compensation"):
		var compensation: Dictionary = rewards.grant_duplicate_compensation(reward_id, source)
		task["duplicate_compensation"] = int(compensation.get("duplicate_compensation", 0))
	return true


func claim_task_reward_for_test(task: Dictionary) -> Dictionary:
	var copy := task.duplicate(true)
	_try_claim_reward(copy)
	return copy

func _retry_pending_rewards() -> void:
	for period_key in ["daily", "weekly"]:
		var tasks: Array = _data.get(period_key, [])
		for i in tasks.size():
			if tasks[i] is Dictionary and bool(tasks[i].get("completed", false)) \
					and not bool(tasks[i].get("claimed", false)):
				var task: Dictionary = tasks[i]
				_try_claim_reward(task)
				tasks[i] = task
		_data[period_key] = tasks

func _update_streak() -> void:
	var daily: Array = _data.get("daily", [])
	if daily.is_empty() or not daily.all(func(task): return task is Dictionary and bool(task.get("completed", false))):
		return
	var date_key := str(_data.get("daily_date", ""))
	var streak: Dictionary = _data.get("streak", {})
	var last_date := str(streak.get("last_completed_date", ""))
	if last_date == date_key:
		return
	var current := int(streak.get("current", 0))
	current = current + 1 if not last_date.is_empty() and _days_between(last_date, date_key) == 1 else 1
	streak["current"] = current
	streak["best"] = maxi(current, int(streak.get("best", 0)))
	streak["last_completed_date"] = date_key
	_data["streak"] = streak

func validate_current() -> Array[String]:
	var errors: Array[String] = []
	for period_key in ["daily", "weekly"]:
		var tasks: Array = _data.get(period_key, [])
		var expected := 3 if period_key == "daily" else 5
		if tasks.size() != expected:
			errors.append("%s_count" % period_key)
		for index in tasks.size():
			if not tasks[index] is Dictionary:
				errors.append("%s_%d_not_dictionary" % [period_key, index])
				continue
			var task: Dictionary = tasks[index]
			if str(task.get("id", "")).is_empty():
				errors.append("%s_%d_missing_id" % [period_key, index])
			if _catalog.template(str(task.get("template_id", ""))).is_empty():
				errors.append("%s_%d_unknown_template" % [period_key, index])
			if float(task.get("target", 0.0)) <= 0.0:
				errors.append("%s_%d_invalid_target" % [period_key, index])
			if str(task.get("description", "")).is_empty():
				errors.append("%s_%d_missing_description" % [period_key, index])
			if str(task.get("reward_id", "")).is_empty():
				errors.append("%s_%d_missing_reward" % [period_key, index])
			if bool(task.get("completed", false)) \
					and float(task.get("progress", 0.0)) < float(task.get("target", 1.0)):
				errors.append("%s_%d_completion_mismatch" % [period_key, index])
	return errors


func repair_current() -> Dictionary:
	ensure_current()
	var guard: Dictionary = _data.get("clock_guard", {})
	if bool(guard.get("locked", false)):
		return {"ok": false, "changed": false, "message": clock_guard_message()}
	var errors := validate_current()
	if errors.is_empty():
		_retry_pending_rewards()
		_save()
		return {"ok": true, "changed": false, "message": "挑战数据正常"}
	var capabilities := build_capabilities()
	var level := 1
	if has_node("/root/ProfileStore"):
		level = int(get_node("/root/ProfileStore").get_highest_mode_level())
	var old_daily: Array = (_data.get("daily", []) as Array).duplicate(true)
	var old_weekly: Array = (_data.get("weekly", []) as Array).duplicate(true)
	var daily := _generator.generate_daily(str(_data.get("daily_date", "")),
		str(_data.get("profile_id", "")), capabilities, level)
	var weekly := _generator.generate_weekly(str(_data.get("weekly_key", "")),
		str(_data.get("profile_id", "")), capabilities, level)
	_data["daily"] = _merge_repaired_progress(daily, old_daily)
	_data["weekly"] = _merge_repaired_progress(weekly, old_weekly)
	_retry_pending_rewards()
	_save()
	challenges_changed.emit()
	return {"ok": true, "changed": true,
		"message": "挑战数据已重新校验并恢复", "repaired": errors}


func _merge_repaired_progress(generated: Array, previous: Array) -> Array:
	var old_by_id := {}
	for raw_task in previous:
		if raw_task is Dictionary:
			old_by_id[str(raw_task.get("id", ""))] = raw_task
	for index in generated.size():
		if not generated[index] is Dictionary:
			continue
		var task: Dictionary = generated[index]
		var old: Dictionary = old_by_id.get(str(task.get("id", "")), {})
		if old.is_empty():
			continue
		var target := maxf(1.0, float(task.get("target", 1.0)))
		var progress := clampf(float(old.get("progress", 0.0)), 0.0, target)
		task["progress"] = progress
		task["completed"] = bool(old.get("completed", false)) and progress >= target
		task["claimed"] = bool(old.get("claimed", false)) and bool(task.get("completed", false))
		if bool(task.get("claimed", false)) and not str(old.get("reward_id", "")).is_empty():
			task["reward_id"] = str(old.get("reward_id", ""))
		generated[index] = task
	return generated


func summary() -> Dictionary:
	return {
		"daily_completed": _completed_count(_data.get("daily", [])),
		"daily_total": (_data.get("daily", []) as Array).size(),
		"weekly_completed": _completed_count(_data.get("weekly", [])),
		"weekly_total": (_data.get("weekly", []) as Array).size(),
		"streak": int((_data.get("streak", {}) as Dictionary).get("current", 0)),
		"clock_locked": bool((_data.get("clock_guard", {}) as Dictionary).get("locked", false)),
	}

func _completed_count(tasks: Array) -> int:
	var count := 0
	for task in tasks:
		if task is Dictionary and bool(task.get("completed", false)):
			count += 1
	return count

func snapshot() -> Dictionary:
	return _data.duplicate(true)

func replace_state_for_test(state: Dictionary) -> void:
	_data = state.duplicate(true)
	_normalize_data()

func consume_last_changes() -> Array:
	var result := _last_changes.duplicate(true)
	_last_changes.clear()
	return result

func clock_guard_message() -> String:
	return str((_data.get("clock_guard", {}) as Dictionary).get("message", ""))

func was_corrupt_on_load_for_test() -> bool:
	return _corrupt_on_load

func _days_between(from_date: String, to_date: String) -> int:
	var from_unix := int(Time.get_unix_time_from_datetime_string(from_date + "T12:00:00"))
	var to_unix := int(Time.get_unix_time_from_datetime_string(to_date + "T12:00:00"))
	return int(round(float(to_unix - from_unix) / 86400.0))

static func iso_week_key(date_key: String) -> String:
	var unix := int(Time.get_unix_time_from_datetime_string(date_key + "T12:00:00"))
	var date := Time.get_datetime_dict_from_unix_time(unix)
	var weekday := int(date.get("weekday", 0))
	var monday_weekday := 7 if weekday == 0 else weekday
	var thursday_unix := unix + (4 - monday_weekday) * 86400
	var thursday := Time.get_datetime_dict_from_unix_time(thursday_unix)
	var iso_year := int(thursday.get("year", 1970))
	var jan4_unix := int(Time.get_unix_time_from_datetime_string("%04d-01-04T12:00:00" % iso_year))
	var jan4 := Time.get_datetime_dict_from_unix_time(jan4_unix)
	var jan4_weekday := int(jan4.get("weekday", 0))
	var jan4_monday_weekday := 7 if jan4_weekday == 0 else jan4_weekday
	var week1_monday := jan4_unix - (jan4_monday_weekday - 1) * 86400
	var week := int(floor(float(thursday_unix - week1_monday) / 604800.0)) + 1
	return "%04d-W%02d" % [iso_year, week]

func _backup_corrupt_file() -> void:
	if not FileAccess.file_exists(data_path):
		return
	var absolute := ProjectSettings.globalize_path(data_path)
	var backup := absolute + ".corrupt-%d" % int(Time.get_unix_time_from_system())
	DirAccess.copy_absolute(absolute, backup)

func _save() -> void:
	if not persist_enabled:
		return
	var absolute := ProjectSettings.globalize_path(data_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var temp_path := data_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("ChallengeService: 无法写入挑战存档")
		return
	file.store_string(JSON.stringify(_data, "  ", false))
	file.close()
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var backup_absolute := absolute + ".bak"
	if FileAccess.file_exists(data_path):
		DirAccess.copy_absolute(absolute, backup_absolute)
		DirAccess.remove_absolute(absolute)
	var error := DirAccess.rename_absolute(temp_absolute, absolute)
	if error != OK:
		push_warning("ChallengeService: 原子替换失败 %s" % error_string(error))
		if FileAccess.file_exists(backup_absolute):
			DirAccess.copy_absolute(backup_absolute, absolute)
