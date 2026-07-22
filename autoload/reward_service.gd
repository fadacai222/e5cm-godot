extends Node
## 奖励库存、装配与重复奖励碎片服务 v3。
## 奖励状态和演出解耦；资源缺失不会删除 owned 或装备 ID。

signal inventory_changed
signal equipped_changed(slot: String, reward_id: String) # v1 兼容
signal reward_unlocked(reward_id: String, reward: Dictionary)
signal reward_seen(reward_id: String)
signal loadout_changed(loadout: Dictionary)

const RewardCatalogScript = preload("res://core/reward_catalog.gd")
const DATA_PATH := "user://feature_data/rewards_v1.json"
const SCHEMA_VERSION := 3
const MAX_DUPLICATE_COMPENSATION_SOURCES := 4096
const CHALLENGE_REDEEMABLE_IDS := [
	"title_daily_rookie", "frame_neon_cyan",
	"title_rhythm_worker", "frame_neon_magenta",
	"title_weekly_runner", "card_grid_blue",
]

var data_path := DATA_PATH
var persist_enabled := true
var _data := {}
var _catalog := RewardCatalogScript.new()
var _corrupt_on_load := false

func _ready() -> void:
	_load()

func _default_equipped() -> Dictionary:
	return {
		"title": "",
		"avatar_frame": "",
		"profile_card": "",
		"settlement_signature": "",
		"coin_sfx": "",
		"menu_sfx": "",
		"combo_theme": "",
	}

func _default_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"catalog_version": RewardCatalogScript.CATALOG_VERSION,
		"owned": {},
		"equipped": _default_equipped(),
		"duplicate_shards": 0,
		"duplicate_compensation_sources": {},
		"migration": {"from_version": SCHEMA_VERSION, "completed_unix": 0},
	}

func _load() -> void:
	_corrupt_on_load = false
	_data = _default_data()
	if not FileAccess.file_exists(data_path):
		return
	var parsed := _parse_dictionary(FileAccess.get_file_as_string(data_path))
	if parsed.is_empty():
		_corrupt_on_load = true
		_backup_current_file(".corrupt-%d" % int(Time.get_unix_time_from_system()))
		return
	var old_version := int(parsed.get("schema_version", 1))
	if old_version < SCHEMA_VERSION:
		_backup_current_file(".v%d.bak" % old_version)
	_data = migrate_data_for_test(parsed)
	var repair := validate_and_repair(false)
	if old_version < SCHEMA_VERSION or bool(repair.get("changed", false)):
		_save()

func _parse_dictionary(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {}
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {}
	return (parser.data as Dictionary).duplicate(true)

func migrate_data_for_test(raw: Dictionary) -> Dictionary:
	var result := raw.duplicate(true)
	var old_version := int(result.get("schema_version", 1))
	var owned: Dictionary = result.get("owned", {}) if result.get("owned", {}) is Dictionary else {}
	for raw_id in owned.keys():
		var reward_id := str(raw_id)
		var entry: Dictionary = owned[raw_id] if owned[raw_id] is Dictionary else {}
		entry["source"] = str(entry.get("source", "legacy"))
		entry["source_instance_id"] = str(entry.get("source_instance_id", entry.get("source", "legacy")))
		entry["unlocked_unix"] = int(entry.get("unlocked_unix", entry.get("unlocked_at", 0)))
		entry["seen"] = bool(entry.get("seen", false))
		entry["orphaned"] = not _catalog.has(reward_id)
		owned[reward_id] = entry
	result["owned"] = owned

	var previous_equipped: Dictionary = result.get("equipped", {}) \
		if result.get("equipped", {}) is Dictionary else {}
	var equipped := _default_equipped()
	for raw_slot in previous_equipped.keys():
		var slot := _catalog.canonical_slot(str(raw_slot))
		if slot in RewardCatalogScript.VALID_SLOTS:
			equipped[slot] = str(previous_equipped[raw_slot])
	result["equipped"] = equipped
	result["duplicate_shards"] = maxi(0, int(result.get("duplicate_shards", 0)))
	result["duplicate_compensation_sources"] = result.get("duplicate_compensation_sources", {}) \
		if result.get("duplicate_compensation_sources", {}) is Dictionary else {}
	result["schema_version"] = SCHEMA_VERSION
	result["catalog_version"] = RewardCatalogScript.CATALOG_VERSION
	result["migration"] = {
		"from_version": old_version,
		"completed_unix": int(Time.get_unix_time_from_system()),
	}
	return result

func reward_info(reward_id: String) -> Dictionary:
	return _catalog.get_item(reward_id)

func reward_name(reward_id: String) -> String:
	return _catalog.display_name(reward_id)


func progress_for(reward_id: String) -> Dictionary:
	var milestones = get_node_or_null("/root/RewardMilestoneService")
	if milestones != null and milestones.has_method("progress_for_reward"):
		return milestones.progress_for_reward(reward_id)
	return {}


func unlock(reward_id: String, source_instance_id: String, source := "feature") -> Dictionary:
	if not _catalog.has(reward_id):
		return {"ok": false, "already_owned": false, "reason": "unknown_reward", "reward_id": reward_id}
	var owned: Dictionary = _data.get("owned", {})
	if owned.has(reward_id):
		return {
			"ok": true,
			"already_owned": true,
			"same_source_instance": str((owned[reward_id] as Dictionary).get("source_instance_id", "")) == source_instance_id,
			"reward_id": reward_id,
		}
	var entry := {
		"source": source,
		"source_instance_id": source_instance_id,
		"unlocked_unix": int(Time.get_unix_time_from_system()),
		"seen": false,
		"orphaned": false,
	}
	owned[reward_id] = entry
	_data["owned"] = owned
	_save()
	inventory_changed.emit()
	var info := reward_info(reward_id)
	info["id"] = reward_id
	info["owned_meta"] = entry.duplicate(true)
	reward_unlocked.emit(reward_id, info)
	return {"ok": true, "already_owned": false, "reward_id": reward_id, "reward": info}

# v1 兼容：source 同时作为来源实例 ID，已拥有奖励不会重复演出。
func grant(reward_id: String, source := "challenge") -> Dictionary:
	return unlock(reward_id, source, source.get_slice(":", 0))


func grant_duplicate_compensation(reward_id: String, source := "challenge") -> Dictionary:
	var source_key := source.strip_edges()
	var compensated: Dictionary = _data.get("duplicate_compensation_sources", {}) \
		if _data.get("duplicate_compensation_sources", {}) is Dictionary else {}
	if not source_key.is_empty() and compensated.has(source_key):
		return {
			"ok": true,
			"already_compensated": true,
			"reward_id": reward_id,
			"source": source_key,
			"duplicate_compensation": 0,
			"duplicate_shards": duplicate_shards(),
		}
	var info: Dictionary = reward_info(reward_id)
	var rarity := str(info.get("rarity", "common"))
	var amount := int({"common": 1, "rare": 2, "epic": 4, "legendary": 8}.get(rarity, 1))
	_data["duplicate_shards"] = maxi(0, int(_data.get("duplicate_shards", 0))) + amount
	if not source_key.is_empty():
		compensated[source_key] = true
		while compensated.size() > MAX_DUPLICATE_COMPENSATION_SOURCES:
			compensated.erase(compensated.keys()[0])
		_data["duplicate_compensation_sources"] = compensated
	_save()
	inventory_changed.emit()
	return {
		"ok": true,
		"already_compensated": false,
		"reward_id": reward_id,
		"source": source_key,
		"duplicate_compensation": amount,
		"duplicate_shards": duplicate_shards(),
	}


func duplicate_shards() -> int:
	return maxi(0, int(_data.get("duplicate_shards", 0)))


func is_challenge_reward(reward_id: String) -> bool:
	return reward_id in CHALLENGE_REDEEMABLE_IDS


func shard_cost_for(reward_id: String) -> int:
	if not is_challenge_reward(reward_id) or owns(reward_id):
		return 0
	var rarity := str(reward_info(reward_id).get("rarity", "common"))
	return int({"common": 5, "rare": 10}.get(rarity, 0))


func can_redeem_with_shards(reward_id: String) -> bool:
	var cost := shard_cost_for(reward_id)
	return cost > 0 and duplicate_shards() >= cost


func redeem_with_shards(reward_id: String) -> Dictionary:
	var cost := shard_cost_for(reward_id)
	if cost <= 0:
		return {"ok": false, "reason": "not_redeemable", "reward_id": reward_id}
	var balance := duplicate_shards()
	if balance < cost:
		return {
			"ok": false, "reason": "insufficient_shards", "reward_id": reward_id,
			"cost": cost, "duplicate_shards": balance,
		}
	_data["duplicate_shards"] = balance - cost
	var result: Dictionary = unlock(reward_id, "shard-redeem:%s" % reward_id, "shard_redeem")
	if not bool(result.get("ok", false)) or bool(result.get("already_owned", false)):
		_data["duplicate_shards"] = balance
		_save()
		return {"ok": false, "reason": "unlock_failed", "reward_id": reward_id}
	result["cost"] = cost
	result["duplicate_shards"] = duplicate_shards()
	return result

# 支持 equip(reward_id) 旧调用，也支持 equip(slot, reward_id) 严格调用。
func equip(slot_or_reward: String, reward_id := "") -> bool:
	var slot := ""
	var target_id := reward_id
	if target_id.is_empty():
		target_id = slot_or_reward
		var item := _catalog.get_item(target_id)
		slot = _catalog.canonical_slot(str(item.get("slot", "")))
	else:
		slot = _catalog.canonical_slot(slot_or_reward)
	if slot not in RewardCatalogScript.VALID_SLOTS or not owns(target_id):
		return false
	var info := _catalog.get_item(target_id)
	if info.is_empty() or _catalog.canonical_slot(str(info.get("slot", ""))) != slot:
		return false
	var equipped: Dictionary = _data.get("equipped", _default_equipped())
	if str(equipped.get(slot, "")) == target_id:
		return true
	equipped[slot] = target_id
	_data["equipped"] = equipped
	_save()
	equipped_changed.emit(slot, target_id)
	loadout_changed.emit(current_loadout())
	return true

func reset_slot(slot: String) -> void:
	var canonical := _catalog.canonical_slot(slot)
	if canonical not in RewardCatalogScript.VALID_SLOTS:
		return
	var equipped: Dictionary = _data.get("equipped", _default_equipped())
	if str(equipped.get(canonical, "")).is_empty():
		return
	equipped[canonical] = ""
	_data["equipped"] = equipped
	_save()
	equipped_changed.emit(canonical, "")
	loadout_changed.emit(current_loadout())

func unequip(slot: String) -> void:
	reset_slot(slot)

func equipped(slot: String) -> String:
	var canonical := _catalog.canonical_slot(slot)
	return str((_data.get("equipped", {}) as Dictionary).get(canonical, ""))

func current_loadout() -> Dictionary:
	var result := _default_equipped()
	var equipped_data: Dictionary = _data.get("equipped", {})
	for slot in result.keys():
		result[slot] = str(equipped_data.get(slot, ""))
	return result

func owns(reward_id: String) -> bool:
	return (_data.get("owned", {}) as Dictionary).has(reward_id)

func mark_seen(reward_id: String) -> void:
	var owned: Dictionary = _data.get("owned", {})
	if not owned.has(reward_id):
		return
	var entry: Dictionary = owned[reward_id]
	if bool(entry.get("seen", false)):
		return
	entry["seen"] = true
	owned[reward_id] = entry
	_data["owned"] = owned
	_save()
	reward_seen.emit(reward_id)
	inventory_changed.emit()

func mark_all_seen() -> void:
	var changed := false
	var owned: Dictionary = _data.get("owned", {})
	for raw_id in owned.keys():
		var entry: Dictionary = owned[raw_id]
		if not bool(entry.get("seen", false)):
			entry["seen"] = true
			owned[raw_id] = entry
			changed = true
	if changed:
		_data["owned"] = owned
		_save()
		inventory_changed.emit()

func unseen_count() -> int:
	var count := 0
	for entry in (_data.get("owned", {}) as Dictionary).values():
		if entry is Dictionary and not bool(entry.get("seen", false)):
			count += 1
	return count

func owned_rewards(include_orphaned := true) -> Array:
	var result: Array = []
	var owned: Dictionary = _data.get("owned", {})
	for raw_id in owned.keys():
		var reward_id := str(raw_id)
		var meta: Dictionary = owned[raw_id] if owned[raw_id] is Dictionary else {}
		if bool(meta.get("orphaned", false)) and not include_orphaned:
			continue
		var info: Dictionary = reward_info(reward_id)
		if info.is_empty():
			info = {
				"slot": "", "type": "orphaned", "name": reward_id,
				"description": "旧版本奖励定义暂不可用，数据已保留。",
				"unlock_hint": "历史奖励", "rarity": "common", "visual": {}, "surfaces": [],
			}
		info["id"] = reward_id
		info["owned"] = true
		info["seen"] = bool(meta.get("seen", false))
		info["source"] = str(meta.get("source", ""))
		info["source_instance_id"] = str(meta.get("source_instance_id", ""))
		info["unlocked_unix"] = int(meta.get("unlocked_unix", 0))
		info["orphaned"] = bool(meta.get("orphaned", false))
		var slot := _catalog.canonical_slot(str(info.get("slot", "")))
		info["equipped"] = not slot.is_empty() and equipped(slot) == reward_id
		result.append(info)
	result.sort_custom(func(a, b):
		if bool(a.get("seen", false)) != bool(b.get("seen", false)):
			return not bool(a.get("seen", false))
		return str(a.get("name", "")) < str(b.get("name", "")))
	return result

func all_rewards() -> Array:
	var result: Array = []
	var owned: Dictionary = _data.get("owned", {})
	for reward_id in _catalog.ids():
		var info := _catalog.get_item(reward_id)
		var meta: Dictionary = owned.get(reward_id, {}) if owned.get(reward_id, {}) is Dictionary else {}
		info["id"] = reward_id
		info["owned"] = owned.has(reward_id)
		info["seen"] = bool(meta.get("seen", true))
		info["source"] = str(meta.get("source", ""))
		info["unlocked_unix"] = int(meta.get("unlocked_unix", 0))
		var slot := _catalog.canonical_slot(str(info.get("slot", "")))
		info["equipped"] = owned.has(reward_id) and equipped(slot) == reward_id
		result.append(info)
	return result

func validate_and_repair(save_after := true) -> Dictionary:
	var changed := false
	var messages: Array[String] = []
	if not _data.get("owned", {}) is Dictionary:
		_data["owned"] = {}
		changed = true
		messages.append("owned 已重建")
	if not _data.get("equipped", {}) is Dictionary:
		_data["equipped"] = _default_equipped()
		changed = true
		messages.append("equipped 已重建")
	var owned: Dictionary = _data.get("owned", {})
	for raw_id in owned.keys():
		var reward_id := str(raw_id)
		var entry: Dictionary = owned[raw_id] if owned[raw_id] is Dictionary else {}
		var orphaned := not _catalog.has(reward_id)
		if bool(entry.get("orphaned", false)) != orphaned:
			entry["orphaned"] = orphaned
			changed = true
		if not entry.has("seen"):
			entry["seen"] = false
			changed = true
		if not entry.has("source_instance_id"):
			entry["source_instance_id"] = str(entry.get("source", "legacy"))
			changed = true
		owned[reward_id] = entry
	_data["owned"] = owned

	var previous: Dictionary = _data.get("equipped", {})
	var normalized := _default_equipped()
	for raw_slot in previous.keys():
		var canonical := _catalog.canonical_slot(str(raw_slot))
		if canonical in RewardCatalogScript.VALID_SLOTS:
			normalized[canonical] = str(previous[raw_slot])
	if normalized != previous:
		_data["equipped"] = normalized
		changed = true
	var normalized_shards := maxi(0, int(_data.get("duplicate_shards", 0)))
	if int(_data.get("duplicate_shards", 0)) != normalized_shards or not _data.has("duplicate_shards"):
		_data["duplicate_shards"] = normalized_shards
		changed = true
	if not _data.has("duplicate_compensation_sources") \
			or not _data.get("duplicate_compensation_sources", {}) is Dictionary:
		_data["duplicate_compensation_sources"] = {}
		changed = true
	_data["schema_version"] = SCHEMA_VERSION
	_data["catalog_version"] = RewardCatalogScript.CATALOG_VERSION
	if changed and save_after:
		_save()
		inventory_changed.emit()
		loadout_changed.emit(current_loadout())
	return {"ok": true, "changed": changed, "messages": messages}

func snapshot() -> Dictionary:
	return _data.duplicate(true)

func replace_state_for_test(state: Dictionary) -> void:
	_data = migrate_data_for_test(state)
	validate_and_repair(false)

func reset_for_test() -> void:
	_data = _default_data()

func was_corrupt_on_load_for_test() -> bool:
	return _corrupt_on_load

func _backup_current_file(suffix: String) -> void:
	if not FileAccess.file_exists(data_path):
		return
	var absolute := ProjectSettings.globalize_path(data_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	DirAccess.copy_absolute(absolute, absolute + suffix)

func _save() -> bool:
	if not persist_enabled:
		return true
	var absolute := ProjectSettings.globalize_path(data_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var temp_path := data_path + ".tmp"
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("RewardService: 奖励存档写入失败")
		return false
	file.store_string(JSON.stringify(_data, "  ", false))
	file.close()
	var backup_absolute := absolute + ".bak"
	if FileAccess.file_exists(data_path):
		DirAccess.copy_absolute(absolute, backup_absolute)
		DirAccess.remove_absolute(absolute)
	var error := DirAccess.rename_absolute(temp_absolute, absolute)
	if error != OK:
		push_warning("RewardService: 奖励存档替换失败 %s" % error_string(error))
		if FileAccess.file_exists(backup_absolute):
			DirAccess.copy_absolute(backup_absolute, absolute)
		return false
	return true
