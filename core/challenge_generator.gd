class_name ChallengeGenerator
extends RefCounted
## 基于周期键、档案 ID 和模板版本稳定生成可完成挑战。

const Catalog = preload("res://core/challenge_catalog.gd")
const DAILY_COUNT := 3
const WEEKLY_COUNT := 5
const DAILY_NORMAL_REWARD_IDS := ["title_daily_rookie", "frame_neon_cyan"]
const DAILY_ADVANCED_REWARD_IDS := ["title_rhythm_worker", "frame_neon_magenta"]
const WEEKLY_REWARD_IDS := ["title_weekly_runner", "card_grid_blue"]

var _catalog := Catalog.new()

func generate_daily(date_key: String, profile_id: String, capabilities: Dictionary,
		player_level: int) -> Array:
	return _generate("daily", date_key, profile_id, capabilities, player_level, DAILY_COUNT)

func generate_weekly(week_key: String, profile_id: String, capabilities: Dictionary,
		player_level: int) -> Array:
	return _generate("weekly", week_key, profile_id, capabilities, player_level, WEEKLY_COUNT)

func _generate(period: String, period_key: String, profile_id: String,
		capabilities: Dictionary, player_level: int, count: int) -> Array:
	var seed_text := "%s|%s|%s|%d" % [period, period_key, profile_id, Catalog.CATALOG_VERSION]
	var digest := seed_text.sha256_text()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(digest.substr(0, 15).hex_to_int())

	var candidates: Array[Dictionary] = []
	for raw in _catalog.templates():
		var item: Dictionary = raw
		if _catalog.supports_period(item, period) and _catalog.is_available(item, capabilities):
			candidates.append(item)
	if candidates.is_empty() or (capabilities.get("modes", {}) as Dictionary).is_empty():
		return _fallback(period, period_key, count)

	_shuffle(candidates, rng)
	var selected: Array[Dictionary] = []
	var used_ids := {}
	var used_categories := {}
	# 每日固定为“普通 + 进阶 + 自适应”骨架，再在每档内稳定随机。
	if period == "daily":
		var desired_difficulties := ["normal", "advanced", "challenge" if player_level >= 20 else "normal"]
		for desired in desired_difficulties:
			for item in candidates:
				var template_id := str(item.get("id", ""))
				var category := str(item.get("category", ""))
				if used_ids.has(template_id) or used_categories.has(category) \
						or str(item.get("difficulty", "normal")) != str(desired):
					continue
				selected.append(_instantiate(item, period, period_key, selected.size(), capabilities,
					player_level, rng))
				used_ids[template_id] = true
				used_categories[category] = true
				break
	# 第一轮继续保证类型多样，填补能力集过滤后缺失的难度档。
	for item in candidates:
		if selected.size() >= count:
			break
		var category := str(item.get("category", ""))
		if used_categories.has(category):
			continue
		selected.append(_instantiate(item, period, period_key, selected.size(), capabilities,
			player_level, rng))
		used_ids[str(item.get("id", ""))] = true
		used_categories[category] = true
	# 第二轮补足数量，仍禁止同模板重复。
	for item in candidates:
		if selected.size() >= count:
			break
		var template_id := str(item.get("id", ""))
		if used_ids.has(template_id):
			continue
		selected.append(_instantiate(item, period, period_key, selected.size(), capabilities,
			player_level, rng))
		used_ids[template_id] = true
	if selected.size() < count:
		var fallback := _fallback(period, period_key, count - selected.size(), selected.size())
		selected.append_array(fallback)
	return selected

func _instantiate(template: Dictionary, period: String, period_key: String, index: int,
		capabilities: Dictionary, player_level: int, rng: RandomNumberGenerator) -> Dictionary:
	var template_id := str(template.get("id", "clear_any"))
	var params := {}
	var target := 1
	var difficulty := str(template.get("difficulty", "normal"))
	var modes: Dictionary = capabilities.get("modes", {})
	var mode_names: Array = modes.keys()
	mode_names.sort()
	match template_id:
		"clear_any": target = 1 if period == "daily" else 5
		"clear_mode":
			params["mode"] = str(mode_names[rng.randi_range(0, mode_names.size() - 1)])
			target = 1 if period == "daily" else 3
		"min_star":
			var stars: Array[int] = []
			for raw_mode in mode_names:
				for raw_star in (modes[raw_mode] as Dictionary).get("stars", []):
					stars.append(int(raw_star))
			stars.sort()
			var percentile := 0.45 if player_level < 10 else (0.60 if player_level < 30 else 0.72)
			var star_index := clampi(int(floor(float(maxi(0, stars.size() - 1)) * percentile)), 0,
				maxi(0, stars.size() - 1))
			params["min_star"] = stars[star_index] if not stars.is_empty() else 1
			target = 1 if period == "daily" else 3
		"grade_at_least":
			params["grade"] = "A" if player_level < 35 else "S"
			target = 1 if period == "daily" else 3
		"combo_at_least": params["combo"] = 50 if player_level < 10 else (100 if player_level < 30 else 200)
		"miss_at_most": params["miss"] = 8 if player_level < 10 else (4 if player_level < 30 else 2)
		"good_at_most": params["good"] = 12 if player_level < 10 else (6 if player_level < 30 else 3)
		"accuracy_at_least": params["accuracy"] = 88.0 if player_level < 10 else (94.0 if player_level < 30 else 97.0)
		"first_play": target = 1 if period == "daily" else 3
		"new_record": target = 1 if period == "daily" else 3
		"random_song": target = 1 if period == "daily" else 3
		"modifier_clear":
			var modifiers := ["反向", "隐藏", "摇摆"]
			params["modifier"] = modifiers[rng.randi_range(0, modifiers.size() - 1)]
			target = 1 if period == "daily" else 3
		"clear_count": target = 10
		"s_count": target = 5 if player_level < 25 else 8
		"perfect_count": target = 1000 if player_level < 20 else 2500
		"unique_songs": target = 7
		"multi_mode": target = mini(3, maxi(1, mode_names.size()))
		"play_minutes": target = 30
		"two_player_clear": target = 1 if period == "daily" else 3
	var reward_pool := _reward_pool(period, difficulty)
	var owned_rewards: Array = capabilities.get("owned_rewards", []) \
		if capabilities.get("owned_rewards", []) is Array else []
	var available_pool: Array = reward_pool.filter(func(reward_id): return str(reward_id) not in owned_rewards)
	var resolved_pool: Array = available_pool if not available_pool.is_empty() else reward_pool
	var reward_digest := ("%s|%s|%d|reward" % [period, period_key, index]).sha256_text()
	var reward_index := int(reward_digest.substr(0, 8).hex_to_int()) % resolved_pool.size()
	var instance := {
		"id": "%s_%s_%d" % [period, period_key.replace("-", "").replace("W", "w"), index + 1],
		"period": period,
		"template_id": template_id,
		"category": str(template.get("category", "general")),
		"difficulty": difficulty,
		"params": params,
		"target": target,
		"progress": 0.0,
		"completed": false,
		"claimed": false,
		"reward_id": resolved_pool[reward_index],
		"catalog_version": Catalog.CATALOG_VERSION,
		"eligibility_version": Catalog.ELIGIBILITY_VERSION,
	}
	instance["description"] = _catalog.describe(instance)
	return instance

func _fallback(period: String, period_key: String, count: int, start_index := 0) -> Array:
	var result: Array = []
	var reward_pool := _reward_pool(period)
	for offset in count:
		var index := start_index + offset
		var item := {
			"id": "%s_%s_fallback_%d" % [period, period_key, index + 1],
			"period": period,
			"template_id": "launch_game",
			"category": "activity",
			"difficulty": "normal",
			"params": {},
			"target": 1,
			"progress": 0.0,
			"completed": false,
			"claimed": false,
			"reward_id": reward_pool[index % reward_pool.size()],
			"catalog_version": Catalog.CATALOG_VERSION,
			"eligibility_version": Catalog.ELIGIBILITY_VERSION,
		}
		item["description"] = _catalog.describe(item)
		result.append(item)
	return result

func _reward_pool(period: String, difficulty := "normal") -> Array:
	if period == "weekly":
		return WEEKLY_REWARD_IDS
	return DAILY_ADVANCED_REWARD_IDS \
		if difficulty in ["advanced", "challenge"] else DAILY_NORMAL_REWARD_IDS

func _shuffle(items: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]
		items[i] = items[j]
		items[j] = tmp
