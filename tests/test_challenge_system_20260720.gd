extends SceneTree

const ChallengeCatalogScript = preload("res://core/challenge_catalog.gd")
const ChallengeGeneratorScript = preload("res://core/challenge_generator.gd")
const ChallengeServiceScript = preload("res://autoload/challenge_service.gd")

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] " + message)

func _capabilities() -> Dictionary:
	return {
		"modes": {
			"花式": {"count": 20, "stars": [4, 7, 10, 12]},
			"竞速": {"count": 20, "stars": [5, 8, 11, 13]},
			"DIY": {"count": 8, "stars": [4, 8, 10]},
		},
		"has_unplayed": true,
		"has_breakable_record": true,
		"two_player": false,
	}

func _run() -> void:
	var catalog = ChallengeCatalogScript.new()
	_check(catalog.templates().size() >= 15, "挑战目录包含至少 15 个模板")
	_check(not catalog.describe({"template_id": "clear_mode", "params": {"mode": "竞速"}, "target": 1}).is_empty(),
		"挑战模板可生成人类可读描述")

	var generator = ChallengeGeneratorScript.new()
	var a := generator.generate_daily("2026-07-20", "profile-a", _capabilities(), 20)
	var b := generator.generate_daily("2026-07-20", "profile-a", _capabilities(), 20)
	_check(a == b and a.size() == 3, "同一日期和档案稳定生成 3 个每日挑战")
	var weekly := generator.generate_weekly("2026-W30", "profile-a", _capabilities(), 20)
	_check(weekly.size() == 5, "每周稳定生成 5 个挑战")
	var categories := {}
	for item in a:
		categories[str(item.get("category", ""))] = true
	_check(categories.size() >= 2, "每日任务避免全部要求同一行为")

	var empty_caps := {"modes": {}, "has_unplayed": false, "has_breakable_record": false, "two_player": false}
	var fallback := generator.generate_daily("2026-07-20", "profile-a", empty_caps, 1)
	_check(fallback.size() == 3, "空曲库仍生成安全兜底任务")
	_check(fallback.all(func(item): return str(item.get("template_id", "")) == "launch_game"),
		"空曲库兜底任务不要求游玩不存在的谱面")

	var service = ChallengeServiceScript.new()
	service.persist_enabled = false
	service.initialize_for_test("profile-a", "2026-07-20", "2026-W30", 1000000, 330, _capabilities(), 20)
	var initial := service.snapshot()
	_check((initial.get("daily", []) as Array).size() == 3, "ChallengeService 初始化每日任务")
	var legacy_state: Dictionary = initial.duplicate(true)
	legacy_state["catalog_version"] = 0
	var legacy_daily: Array = legacy_state.get("daily", [])
	legacy_daily[0]["description"] = "旧版本任务"
	legacy_state["daily"] = legacy_daily
	service.replace_state_for_test(legacy_state)
	service.ensure_period_for_test("2026-07-20", "2026-W30", 1000100, 330, _capabilities(), 20)
	var migrated: Dictionary = service.snapshot()
	_check(int(migrated.get("catalog_version", 0)) == ChallengeCatalogScript.CATALOG_VERSION \
		and str((migrated.get("daily", []) as Array)[0].get("description", "")) != "旧版本任务",
		"catalog_version 升级会在同周期重建任务，而非只改版本号")
	var run := {
		"run_id": "run-1", "eligible": true, "mode": "竞速", "star": 12,
		"grade": "S", "failed": false, "combo": 300, "miss": 0, "good": 0,
		"accuracy": 99.2, "perfect": 500, "duration_sec": 150.0,
		"chart_hash": "chart-a", "first_play": true, "new_record": true,
		"random_song": false, "players": 1,
	}
	var changes := service.process_run(run)
	var after_once := service.snapshot()
	service.process_run(run)
	_check(service.snapshot() == after_once, "同一 run_id 重复处理不会重复推进")
	_check(not changes.is_empty(), "合格正式成绩推进至少一个挑战")

	var blocked := run.duplicate(true)
	blocked["run_id"] = "run-training"
	blocked["eligible"] = false
	blocked["training"] = true
	var before_blocked := service.snapshot()
	_check(service.process_run(blocked).is_empty() and service.snapshot() == before_blocked,
		"训练或无资格成绩不会推进挑战")

	var old_daily: Array = (service.snapshot().get("daily", []) as Array).duplicate(true)
	service.ensure_period_for_test("2026-07-21", "2026-W30", 1003600, 330, _capabilities(), 20)
	_check(service.snapshot().get("daily", []) != old_daily, "跨日只刷新每日任务")
	var current_weekly: Array = (service.snapshot().get("weekly", []) as Array).duplicate(true)
	service.ensure_period_for_test("2026-07-22", "2026-W30", 999000, 330, _capabilities(), 20)
	_check(bool(service.snapshot().get("clock_guard", {}).get("locked", false)), "系统时间明显倒退时锁定刷新")
	_check(service.snapshot().get("weekly", []) == current_weekly, "时钟倒退不会重复刷新周常")

	service.free()
	catalog = null
	generator = null
	await process_frame
	quit(1 if failures > 0 else 0)
