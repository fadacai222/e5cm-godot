extends SceneTree

const CatalogScript := preload("res://core/reward_catalog.gd")
const ResolverScript := preload("res://ui/reward_appearance_resolver.gd")
const RewardServiceScript := preload("res://autoload/reward_service.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String, detail := "") -> void:
	if ok:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _run() -> void:
	var catalog = CatalogScript.new()
	_check(CatalogScript.CATALOG_VERSION == 5, "RewardCatalog 已升级到全代码外观主题 v5")
	var errors: Array[String] = catalog.validate_catalog()
	_check(errors.is_empty(), "当前奖励目录通过 v5 schema 校验", "\n".join(errors))
	for reward_id in [
		"title_daily_rookie", "title_rhythm_worker", "title_weekly_runner",
		"frame_neon_cyan", "frame_neon_magenta", "card_grid_blue",
	]:
		var item: Dictionary = catalog.get_item(reward_id)
		_check(not item.is_empty() and item.has("type") and item.has("visual")
			and not (item.get("surfaces", []) as Array).is_empty(),
			"%s 具备可展示的 v2 视觉定义" % reward_id)

	var service = root.get_node("RewardService")
	service.persist_enabled = false
	service.reset_for_test()
	var v1 := {
		"schema_version": 1,
		"owned": {
			"frame_neon_cyan": {"source": "challenge", "unlocked_unix": 1},
			"title_daily_rookie": {"source": "challenge", "unlocked_unix": 2},
			"legacy_missing_reward": {"source": "legacy", "unlocked_unix": 3},
		},
		"equipped": {"title": "title_daily_rookie", "frame": "frame_neon_cyan", "card": ""},
	}
	var migrated: Dictionary = service.migrate_data_for_test(v1)
	_check(int(migrated.get("schema_version", 0)) == 3
		and int(migrated.get("duplicate_shards", -1)) == 0,
		"v1 奖励存档迁移到 v3 并补齐重复奖励碎片字段")
	var equipped: Dictionary = migrated.get("equipped", {})
	_check(str(equipped.get("avatar_frame", "")) == "frame_neon_cyan"
		and str(equipped.get("title", "")) == "title_daily_rookie",
		"旧 frame/card 槽位无损迁移到正式槽位")
	_check(bool((migrated.get("owned", {}) as Dictionary).get("legacy_missing_reward", {}).get("orphaned", false)),
		"未知历史奖励被保留并标记 orphaned")

	service.replace_state_for_test(migrated)
	_check(service.equipped("frame") == "frame_neon_cyan"
		and service.equipped("avatar_frame") == "frame_neon_cyan",
		"旧槽位名称保留只读兼容")
	_check(service.unseen_count() == 3, "迁移后的历史奖励默认标记为未读")
	service.mark_seen("title_daily_rookie")
	_check(service.unseen_count() == 2, "查看奖励后未读数量减少")
	_check(service.equip("avatar_frame", "frame_neon_cyan"), "严格槽位装备成功")
	_check(not service.equip("title", "frame_neon_cyan"), "错误槽位拒绝装备")
	service.reset_slot("avatar_frame")
	_check(service.equipped("avatar_frame").is_empty(), "取消装备恢复默认外观")

	var first_unlock: Dictionary = service.unlock("card_grid_blue", "unit-source-1", "unit-test")
	var duplicate_unlock: Dictionary = service.unlock("card_grid_blue", "unit-source-1", "unit-test")
	_check(bool(first_unlock.get("ok", false)) and not bool(first_unlock.get("already_owned", true)),
		"新奖励首次解锁成功")
	_check(bool(duplicate_unlock.get("already_owned", false)), "相同来源实例重复解锁保持幂等")
	service.equip("profile_card", "card_grid_blue")
	service.equip("title", "title_daily_rookie")

	var resolver = ResolverScript.new()
	var appearance: Dictionary = resolver.resolve_loadout(service.current_loadout(), false)
	_check(str(appearance.get("title", {}).get("id", "")) == "title_daily_rookie",
		"外观解析器返回已装备称号")
	_check(str(appearance.get("profile_card", {}).get("id", "")) == "card_grid_blue",
		"外观解析器返回已装备玩家卡")
	var missing: Dictionary = service.current_loadout()
	missing["avatar_frame"] = "legacy_missing_reward"
	var fallback: Dictionary = resolver.resolve_loadout(missing, false)
	_check(bool(fallback.get("avatar_frame", {}).get("is_default", false)),
		"缺失奖励安全回退默认头像框且保留档案 ID")
	for i in 1000:
		resolver.resolve_loadout(service.current_loadout(), i % 2 == 0)
	_check(resolver.cache_size_for_test() <= 16, "1000 次外观解析使用有界缓存")

	var corrupt_path := "user://feature_data/reward_test_corrupt.json"
	var corrupt_absolute := ProjectSettings.globalize_path(corrupt_path)
	DirAccess.make_dir_recursive_absolute(corrupt_absolute.get_base_dir())
	var corrupt_file := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt_file.store_string("{broken reward json")
	corrupt_file.close()
	var corrupt_service = RewardServiceScript.new()
	corrupt_service.name = "CorruptRewardServiceTest"
	corrupt_service.data_path = corrupt_path
	corrupt_service.persist_enabled = false
	root.add_child(corrupt_service)
	await process_frame
	_check(corrupt_service.was_corrupt_on_load_for_test()
		and (corrupt_service.snapshot().get("owned", {}) as Dictionary).is_empty(),
		"奖励存档损坏时恢复默认装配且不影响游戏启动")
	var backups := DirAccess.get_files_at(corrupt_absolute.get_base_dir())
	var found_corrupt_backup := false
	for file_name in backups:
		if str(file_name).begins_with("reward_test_corrupt.json.corrupt-"):
			found_corrupt_backup = true
			break
	_check(found_corrupt_backup, "损坏奖励存档被隔离备份而非静默删除")
	root.remove_child(corrupt_service)
	corrupt_service.free()
	for file_name in backups:
		if str(file_name).begins_with("reward_test_corrupt.json"):
			DirAccess.remove_absolute(corrupt_absolute.get_base_dir().path_join(str(file_name)))

	service.reset_for_test()
	catalog = null
	resolver = null
	await process_frame
	quit(1 if failures > 0 else 0)
