extends SceneTree

const Generator = preload("res://core/challenge_generator.gd")
const Catalog = preload("res://core/challenge_catalog.gd")
const Service = preload("res://autoload/challenge_service.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _caps() -> Dictionary:
	return {
		"modes": {
			"花式": {"count": 40, "stars": [3, 6, 9, 12]},
			"竞速": {"count": 40, "stars": [4, 7, 10, 13]},
			"DIY": {"count": 12, "stars": [4, 8, 11]},
		},
		"has_unplayed": true,
		"has_breakable_record": true,
		"has_random_source": false,
		"two_player": false,
	}

func _run() -> void:
	var generator := Generator.new()
	var seen_ids := {}
	var start_unix := int(Time.get_unix_time_from_datetime_string("2026-01-01T12:00:00"))
	var stable := true
	for day in 60:
		var date := Time.get_date_string_from_unix_time(start_unix + day * 86400)
		var tasks: Array = generator.generate_daily(date, "sixty-day-profile", _caps(), 25)
		if tasks.size() != 3:
			stable = false
			break
		for task in tasks:
			var task_id := str(task.get("id", ""))
			if task_id.is_empty() or seen_ids.has(task_id) or str(task.get("description", "")).is_empty():
				stable = false
				break
			seen_ids[task_id] = true
	_check(stable and seen_ids.size() == 180, "连续模拟 60 天生成 180 个有效且周期唯一的每日任务")

	var catalog := Catalog.new()
	var modifier_task := {"template_id": "modifier_clear", "params": {"modifier": "反向"}}
	var modifier_run := {"failed": false, "direction_mode": "反向"}
	_check(catalog.evaluate(modifier_task, modifier_run, {}) == 1.0, "反向设置类任务读取真实结算设置")
	var two_player_task := {"template_id": "two_player_clear", "params": {}}
	_check(catalog.evaluate(two_player_task, {"failed": false, "players": 2}, {}) == 1.0,
		"2P 正式结果可推进 2P 模板")
	_check(not catalog.is_available(catalog.template("two_player_clear"), _caps()),
		"单人能力集不会生成 2P 任务")
	_check(not catalog.is_available(catalog.template("random_song"), _caps()),
		"随机入口未实现前不会生成随机选歌死任务")

	var service := Service.new()
	service.persist_enabled = false
	service.initialize_for_test("tz-profile", "2026-03-28", "2026-W13", 2000000, 330, _caps(), 20)
	service.ensure_period_for_test("2026-03-29", "2026-W13", 2086400, 390, _caps(), 20)
	_check(not bool(service.snapshot().get("clock_guard", {}).get("locked", false)),
		"夏令时或时区变化但 Unix 时间前进时不会误锁")
	_check(int(service.snapshot().get("clock_guard", {}).get("timezone_offset_minutes", 0)) == 390,
		"时区偏移变化被记录")

	var bad_path := "user://feature_data/challenge_corrupt_test.json"
	var absolute := ProjectSettings.globalize_path(bad_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var bad_file := FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string("{broken-json")
	bad_file.close()
	var corrupt_service := Service.new()
	corrupt_service.data_path = bad_path
	corrupt_service.persist_enabled = false
	corrupt_service.call("_load")
	_check(corrupt_service.was_corrupt_on_load_for_test(), "损坏挑战存档被隔离而不是崩溃")
	_check((corrupt_service.snapshot().get("daily", []) as Array).is_empty(), "损坏存档恢复为空安全状态")
	DirAccess.remove_absolute(absolute)

	var repair_service := Service.new()
	repair_service.name = "ChallengeRepairService"
	repair_service.persist_enabled = false
	root.add_child(repair_service)
	var repair_date := Time.get_date_string_from_system()
	var repair_week := str(repair_service.call("iso_week_key", repair_date))
	repair_service.initialize_for_test("repair-profile", repair_date, repair_week,
		int(Time.get_unix_time_from_system()), int(Time.get_time_zone_from_system().get("bias", 0)), _caps(), 20)
	var damaged: Dictionary = repair_service.snapshot()
	var damaged_daily: Array = damaged.get("daily", [])
	damaged_daily[0]["target"] = 0
	damaged_daily[0]["description"] = ""
	damaged["daily"] = damaged_daily
	repair_service.replace_state_for_test(damaged)
	_check(not repair_service.validate_current().is_empty(), "可诊断结构损坏的挑战任务")
	var repaired: Dictionary = repair_service.repair_current()
	var repair_errors := repair_service.validate_current()
	_check(bool(repaired.get("ok", false)) and bool(repaired.get("changed", false)) \
		and repair_errors.is_empty(), "重新校验入口可安全恢复异常任务",
		"result=%s errors=%s" % [str(repaired), str(repair_errors)])

	var rewards = root.get_node_or_null("RewardService")
	if rewards != null:
		rewards.persist_enabled = false
		rewards.reset_for_test()
		var first: Dictionary = rewards.grant("frame_neon_cyan", "test")
		var second: Dictionary = rewards.grant("frame_neon_cyan", "test-repeat")
		_check(bool(first.get("ok", false)) and not bool(first.get("already_owned", true)),
			"首次奖励正常入库")
		_check(bool(second.get("ok", false)) and bool(second.get("already_owned", false)),
			"重复奖励标记为已拥有且不制造虚假货币")
		_check(rewards.equip("frame_neon_cyan") and rewards.equipped("frame") == "frame_neon_cyan",
			"已拥有头像框可以装备")
		var equipped_before: String = str(rewards.equipped("frame"))
		repair_service.replace_state_for_test({})
		_check(rewards.equipped("frame") == equipped_before,
			"挑战状态重置不会清除独立奖励库存与装备")

	service.free()
	corrupt_service.free()
	root.remove_child(repair_service)
	repair_service.free()
	await process_frame
	quit(1 if failures > 0 else 0)
