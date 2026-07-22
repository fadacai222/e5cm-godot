extends Node
## 奖励里程碑唯一规则入口。
## 所有非挑战随机奖励都必须在这里有可执行条件，禁止只写 unlock_hint 文案。

const DATA_PATH := "user://feature_data/reward_milestones_v1.json"
const SCHEMA_VERSION := 1
const MAX_PROCESSED_RUNS := 1024
const HIGH_DIFFICULTY_STAR := 15
const FLAME_STREAK_TARGET := 10
const ICE_CHART_TARGET := 5
const PRISM_CHART_TARGET := 3
const GALAXY_EPIC_TARGET := 8
const VIP_LEGENDARY_TARGET := 5

var data_path := DATA_PATH
var persist_enabled := true
var _data := {}
var _evaluating_collections := false


func _ready() -> void:
	_load()
	if not ProfileStore.progress_changed.is_connected(_on_progress_changed):
		ProfileStore.progress_changed.connect(_on_progress_changed)
	if not ChallengeService.challenges_changed.is_connected(_on_challenges_changed):
		ChallengeService.challenges_changed.connect(_on_challenges_changed)
	if not RewardService.inventory_changed.is_connected(_on_inventory_changed):
		RewardService.inventory_changed.connect(_on_inventory_changed)
	call_deferred("evaluate_existing_state")


func _default_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"processed_run_ids": [],
		"unique_completed_charts": {},
		"high_difficulty_streak": 0,
		"high_difficulty_streak_charts": {},
		"ice_charts": {},
		"prism_charts": {},
	}


func _load() -> void:
	_data = _default_data()
	if not FileAccess.file_exists(data_path):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(data_path)) != OK \
			or not parser.data is Dictionary:
		return
	_data = (parser.data as Dictionary).duplicate(true)
	_normalize_data()


func _normalize_data() -> void:
	var defaults := _default_data()
	for key in defaults.keys():
		if not _data.has(key):
			_data[key] = defaults[key]
	if not _data.get("processed_run_ids", []) is Array:
		_data["processed_run_ids"] = []
	for key in ["unique_completed_charts", "high_difficulty_streak_charts",
			"ice_charts", "prism_charts"]:
		if not _data.get(key, {}) is Dictionary:
			_data[key] = {}
	_data["high_difficulty_streak"] = maxi(0, int(_data.get("high_difficulty_streak", 0)))
	_data["schema_version"] = SCHEMA_VERSION


func _save() -> bool:
	if not persist_enabled:
		return true
	var absolute := ProjectSettings.globalize_path(data_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var temp_path := data_path + ".tmp"
	var temp_absolute := ProjectSettings.globalize_path(temp_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_warning("RewardMilestoneService: 里程碑存档写入失败")
		return false
	file.store_string(JSON.stringify(_data, "  ", false))
	file.close()
	if FileAccess.file_exists(data_path):
		DirAccess.remove_absolute(absolute)
	var error := DirAccess.rename_absolute(temp_absolute, absolute)
	if error != OK:
		push_warning("RewardMilestoneService: 里程碑存档替换失败 %s" % error_string(error))
		return false
	return true


func evaluate_existing_state() -> void:
	_sync_unique_charts_from_records()
	_evaluate_mode_levels()
	_evaluate_statistics()
	_evaluate_streak()
	_evaluate_collections()


func _on_progress_changed(_mode_key: String, _progress: Dictionary, preview: bool) -> void:
	if not preview:
		_evaluate_mode_levels()
		_evaluate_statistics()
		_evaluate_collections()


func _on_challenges_changed() -> void:
	_evaluate_streak()
	_evaluate_collections()


func _on_inventory_changed() -> void:
	_evaluate_collections()


func _evaluate_mode_levels() -> void:
	var specs := [
		["花式", 10, "title_fancy_lv10"],
		["竞速", 10, "title_racing_lv10"],
		["DIY", 10, "title_diy_lv10"],
		["DIY", 15, "frame_data_grid"],
		["花式", 15, "card_neon_wave"],
		["花式", 20, "card_fancy_stage"],
		["竞速", 20, "card_speed_lightning"],
		["DIY", 20, "card_diy_blueprint"],
		["花式", 25, "title_sakura_dream"],
		["DIY", 30, "title_matrix_ghost"],
	]
	var highest_level := 1
	var all_level_30 := true
	var all_level_40 := true
	for mode in ["花式", "竞速", "DIY"]:
		var level := int(ProfileStore.get_mode_progress(mode).get("等级", 1))
		highest_level = maxi(highest_level, level)
		all_level_30 = all_level_30 and level >= 30
		all_level_40 = all_level_40 and level >= 40
	for spec in specs:
		var mode := str(spec[0])
		var threshold := int(spec[1])
		if int(ProfileStore.get_mode_progress(mode).get("等级", 1)) >= threshold:
			_unlock(str(spec[2]), "mode-level:%s:%d" % [mode, threshold], "mode_level")
	if highest_level >= 30:
		_unlock("title_rhythm_master", "highest-mode-level:30", "mode_level")
	if highest_level >= 50:
		_unlock("frame_legend_wings", "highest-mode-level:50", "mode_level")
	if all_level_30:
		_unlock("title_beat_sovereign", "all-mode-level:30", "mode_level")
	if all_level_40:
		_unlock("title_void_watcher", "all-mode-level:40", "mode_level")


func _sync_unique_charts_from_records() -> void:
	var unique_charts: Dictionary = _data.get("unique_completed_charts", {})
	var changed := false
	for raw_key in ProfileStore.records.keys():
		var record: Dictionary = ProfileStore.records[raw_key] \
			if ProfileStore.records[raw_key] is Dictionary else {}
		if int(record.get("游玩次数", 0)) <= 0:
			continue
		var chart_key := str(raw_key).strip_edges()
		if chart_key.is_empty() or unique_charts.has(chart_key):
			continue
		unique_charts[chart_key] = true
		changed = true
	if changed:
		_data["unique_completed_charts"] = unique_charts
		_save()


func _evaluate_statistics() -> void:
	var stats: Dictionary = ProfileStore.profile.get("统计", {})
	var total_s := int(stats.get("累计评价S数", 0))
	var max_combo := int(stats.get("最大Combo", 0))
	var play_minutes := int(stats.get("游玩时长分钟", 0))
	var total_songs := 0
	for mode in ["花式", "竞速", "DIY"]:
		var progress: Dictionary = ProfileStore.get_mode_progress(mode)
		total_songs += int(progress.get("累计首数", progress.get("累计歌曲", 0)))
	var unique_songs := (_data.get("unique_completed_charts", {}) as Dictionary).size()
	var specs := [
		[total_s, 10, "title_precision_master", "total-s"],
		[total_s, 25, "frame_starburst", "total-s"],
		[total_s, 40, "title_frost_core", "total-s"],
		[total_s, 50, "card_black_gold_vip", "total-s"],
		[total_s, 100, "title_prism_oracle", "total-s"],
		[max_combo, 300, "title_cyber_ronin", "max-combo"],
		[max_combo, 500, "title_combo_king", "max-combo"],
		[max_combo, 500, "frame_pulse", "max-combo"],
		[play_minutes, 1000, "title_legend_performer", "play-minutes"],
		[play_minutes, 2000, "title_midas_destiny", "play-minutes"],
		[unique_songs, 100, "title_star_conqueror", "unique-songs"],
		[total_songs, 200, "title_ember_crown", "total-songs"],
		[total_songs, 300, "title_battle_hardened", "total-songs"],
	]
	for spec in specs:
		if int(spec[0]) >= int(spec[1]):
			_unlock(str(spec[2]), "%s:%d" % [str(spec[3]), int(spec[1])], "statistics")


func _evaluate_streak() -> void:
	var streak := int(ChallengeService.summary().get("streak", 0))
	var specs := [
		[3, "title_streak_3"],
		[7, "frame_streak_7"],
		[14, "frame_aurora"],
		[14, "card_aurora_city"],
		[30, "title_monthly_active"],
		[30, "card_streak_30"],
	]
	for spec in specs:
		if streak >= int(spec[0]):
			_unlock(str(spec[1]), "streak:%d" % int(spec[0]), "challenge_streak")


func _evaluate_collections() -> void:
	if _evaluating_collections:
		return
	_evaluating_collections = true
	if RewardService.owns("frame_aurora") and RewardService.owns("card_aurora_city"):
		_unlock("title_aurora_navigator", "collection:aurora", "collection")
	if RewardService.owns("frame_prism") and RewardService.owns("title_prism_oracle"):
		_unlock("card_prism_myth", "collection:prism", "collection")
	if _owned_rarity_count("epic", ["title_galaxy_lord"]) >= GALAXY_EPIC_TARGET:
		_unlock("title_galaxy_lord", "collection:epic:%d" % GALAXY_EPIC_TARGET, "collection")
	if _owned_rarity_count("legendary", ["frame_vip_crown", "title_rhythm_god"]) \
			>= VIP_LEGENDARY_TARGET:
		_unlock("frame_vip_crown", "collection:legendary:%d" % VIP_LEGENDARY_TARGET, "collection")
	if _all_other_legendary_owned():
		_unlock("title_rhythm_god", "collection:all-legendary", "collection")
	_evaluating_collections = false


func _owned_rarity_count(rarity: String, excluded: Array = []) -> int:
	var count := 0
	for item in RewardService.all_rewards():
		var reward_id := str(item.get("id", ""))
		if reward_id in excluded:
			continue
		if str(item.get("rarity", "")) == rarity and bool(item.get("owned", false)):
			count += 1
	return count


func _all_other_legendary_owned() -> bool:
	var found := false
	for item in RewardService.all_rewards():
		var reward_id := str(item.get("id", ""))
		if str(item.get("rarity", "")) != "legendary" or reward_id == "title_rhythm_god":
			continue
		found = true
		if not bool(item.get("owned", false)):
			return false
	return found


func _unlock(reward_id: String, source_instance_id: String, source: String) -> bool:
	var result: Dictionary = RewardService.unlock(reward_id, source_instance_id, source)
	return bool(result.get("ok", false)) and not bool(result.get("already_owned", true))


func _unlock_collect(reward_id: String, source_instance_id: String, source: String,
		unlocked: Array[String]) -> void:
	if _unlock(reward_id, source_instance_id, source):
		unlocked.append(reward_id)


func process_official_run(run_result: Dictionary) -> Array[String]:
	var unlocked: Array[String] = []
	if not _official_attempt(run_result):
		return unlocked
	var run_id := str(run_result.get("run_id", "")).strip_edges()
	if run_id.is_empty() or _already_processed(run_id):
		return unlocked
	_mark_processed(run_id)

	if bool(run_result.get("failed", run_result.get("失败", false))):
		_reset_high_difficulty_streak()
		_save()
		return unlocked

	_unlock_collect("frame_minimal_silver", "official-run:first-clear", "achievement", unlocked)
	if bool(run_result.get("full_combo", run_result.get("是否全连", false))):
		_unlock_collect("title_full_combo", "official-run:%s:full-combo" % run_id,
			"achievement", unlocked)
	if bool(run_result.get("all_perfect", run_result.get("是否全perfect", false))):
		_unlock_collect("frame_all_perfect", "official-run:%s:all-perfect" % run_id,
			"achievement", unlocked)

	var chart_key := str(run_result.get("chart_hash", run_result.get("sm_key", ""))).strip_edges()
	if not chart_key.is_empty():
		var unique_charts: Dictionary = _data.get("unique_completed_charts", {})
		unique_charts[chart_key] = true
		_data["unique_completed_charts"] = unique_charts

	var star := int(run_result.get("star", 0))
	_update_high_difficulty_streak(star, chart_key)
	if int(_data.get("high_difficulty_streak", 0)) >= FLAME_STREAK_TARGET:
		_unlock_collect("frame_flame", "high-difficulty-streak:%d" % FLAME_STREAK_TARGET,
			"achievement", unlocked)

	if not RewardService.owns("frame_ice") and star >= HIGH_DIFFICULTY_STAR \
			and int(run_result.get("miss", 999999)) <= 2:
		_add_unique_chart("ice_charts", chart_key)
	if not RewardService.owns("frame_prism") and star >= 17 \
			and str(run_result.get("grade", "F")).to_upper() == "S":
		_add_unique_chart("prism_charts", chart_key)
	if (_data.get("ice_charts", {}) as Dictionary).size() >= ICE_CHART_TARGET:
		_unlock_collect("frame_ice", "theme:ice:%d" % ICE_CHART_TARGET,
			"achievement", unlocked)
	if (_data.get("prism_charts", {}) as Dictionary).size() >= PRISM_CHART_TARGET:
		_unlock_collect("frame_prism", "theme:prism:%d" % PRISM_CHART_TARGET,
			"achievement", unlocked)

	var completed_hour := int(run_result.get("completed_hour", -1))
	if completed_hour >= 22 or (completed_hour >= 0 and completed_hour < 6):
		_unlock_collect("title_night_walker", "night-clear:first", "achievement", unlocked)

	_save()
	_evaluate_statistics()
	_evaluate_collections()
	return unlocked


func _official_attempt(run_result: Dictionary) -> bool:
	return bool(run_result.get("eligible", run_result.get("challenge_eligible", false))) \
		and not bool(run_result.get("training", false)) \
		and not bool(run_result.get("autoplay", false)) \
		and not bool(run_result.get("debug", run_result.get("debug_run", false)))


func _already_processed(run_id: String) -> bool:
	return run_id in (_data.get("processed_run_ids", []) as Array)


func _mark_processed(run_id: String) -> void:
	var processed: Array = _data.get("processed_run_ids", [])
	processed.append(run_id)
	while processed.size() > MAX_PROCESSED_RUNS:
		processed.pop_front()
	_data["processed_run_ids"] = processed


func _update_high_difficulty_streak(star: int, chart_key: String) -> void:
	if RewardService.owns("frame_flame"):
		return
	if star < HIGH_DIFFICULTY_STAR:
		_reset_high_difficulty_streak()
		return
	if chart_key.is_empty():
		return
	var charts: Dictionary = _data.get("high_difficulty_streak_charts", {})
	if charts.has(chart_key):
		return
	charts[chart_key] = true
	_data["high_difficulty_streak_charts"] = charts
	_data["high_difficulty_streak"] = int(_data.get("high_difficulty_streak", 0)) + 1


func _reset_high_difficulty_streak() -> void:
	_data["high_difficulty_streak"] = 0
	_data["high_difficulty_streak_charts"] = {}


func _add_unique_chart(key: String, chart_key: String) -> void:
	if chart_key.is_empty():
		return
	var charts: Dictionary = _data.get(key, {})
	charts[chart_key] = true
	_data[key] = charts


func process_training_completion(training_config: Dictionary, summary: Dictionary) -> Array[String]:
	var unlocked: Array[String] = []
	var windows: Array = training_config.get("problem_windows", []) \
		if training_config.get("problem_windows", []) is Array else []
	if windows.is_empty():
		return unlocked
	var total := int(summary.get("total", summary.get("judged", 0)))
	if total <= 0:
		return unlocked
	var chart_key := str(summary.get("chart_key", "training"))
	_unlock_collect("title_training_focus", "training-problem:%s" % chart_key,
		"training", unlocked)
	return unlocked


func progress_for_reward(reward_id: String) -> Dictionary:
	var stats: Dictionary = ProfileStore.profile.get("统计", {})
	var streak := int(ChallengeService.summary().get("streak", 0))
	var total_songs := 0
	for mode in ["花式", "竞速", "DIY"]:
		total_songs += int(ProfileStore.get_mode_progress(mode).get("累计首数", 0))
	var current := 0
	var target := 0
	match reward_id:
		"title_fancy_lv10": current = int(ProfileStore.get_mode_progress("花式").get("等级", 1)); target = 10
		"title_racing_lv10": current = int(ProfileStore.get_mode_progress("竞速").get("等级", 1)); target = 10
		"title_diy_lv10": current = int(ProfileStore.get_mode_progress("DIY").get("等级", 1)); target = 10
		"frame_data_grid": current = int(ProfileStore.get_mode_progress("DIY").get("等级", 1)); target = 15
		"card_neon_wave": current = int(ProfileStore.get_mode_progress("花式").get("等级", 1)); target = 15
		"card_fancy_stage": current = int(ProfileStore.get_mode_progress("花式").get("等级", 1)); target = 20
		"card_speed_lightning": current = int(ProfileStore.get_mode_progress("竞速").get("等级", 1)); target = 20
		"card_diy_blueprint": current = int(ProfileStore.get_mode_progress("DIY").get("等级", 1)); target = 20
		"title_sakura_dream": current = int(ProfileStore.get_mode_progress("花式").get("等级", 1)); target = 25
		"title_matrix_ghost": current = int(ProfileStore.get_mode_progress("DIY").get("等级", 1)); target = 30
		"title_rhythm_master": current = ProfileStore.get_highest_mode_level(); target = 30
		"frame_legend_wings": current = ProfileStore.get_highest_mode_level(); target = 50
		"title_beat_sovereign": current = _minimum_mode_level(); target = 30
		"title_void_watcher": current = _minimum_mode_level(); target = 40
		"frame_minimal_silver", "title_full_combo", "frame_all_perfect", "title_training_focus", "title_night_walker":
			current = 1 if RewardService.owns(reward_id) else 0
			target = 1
		"frame_flame":
			current = int(_data.get("high_difficulty_streak", 0)); target = FLAME_STREAK_TARGET
		"frame_ice":
			current = (_data.get("ice_charts", {}) as Dictionary).size(); target = ICE_CHART_TARGET
		"frame_prism":
			current = (_data.get("prism_charts", {}) as Dictionary).size(); target = PRISM_CHART_TARGET
		"title_star_conqueror":
			current = (_data.get("unique_completed_charts", {}) as Dictionary).size(); target = 100
		"title_precision_master": current = int(stats.get("累计评价S数", 0)); target = 10
		"frame_starburst": current = int(stats.get("累计评价S数", 0)); target = 25
		"title_frost_core": current = int(stats.get("累计评价S数", 0)); target = 40
		"card_black_gold_vip": current = int(stats.get("累计评价S数", 0)); target = 50
		"title_prism_oracle": current = int(stats.get("累计评价S数", 0)); target = 100
		"title_cyber_ronin": current = int(stats.get("最大Combo", 0)); target = 300
		"title_combo_king", "frame_pulse": current = int(stats.get("最大Combo", 0)); target = 500
		"title_legend_performer": current = int(stats.get("游玩时长分钟", 0)); target = 1000
		"title_midas_destiny": current = int(stats.get("游玩时长分钟", 0)); target = 2000
		"title_ember_crown": current = total_songs; target = 200
		"title_battle_hardened": current = total_songs; target = 300
		"title_streak_3": current = streak; target = 3
		"frame_streak_7": current = streak; target = 7
		"frame_aurora", "card_aurora_city": current = streak; target = 14
		"title_monthly_active", "card_streak_30": current = streak; target = 30
		"title_galaxy_lord": current = _owned_rarity_count("epic", ["title_galaxy_lord"]); target = GALAXY_EPIC_TARGET
		"frame_vip_crown": current = _owned_rarity_count("legendary", ["frame_vip_crown", "title_rhythm_god"]); target = VIP_LEGENDARY_TARGET
		"card_prism_myth":
			current = int(RewardService.owns("frame_prism")) + int(RewardService.owns("title_prism_oracle")); target = 2
		"title_aurora_navigator":
			current = int(RewardService.owns("frame_aurora")) + int(RewardService.owns("card_aurora_city")); target = 2
		"title_rhythm_god":
			var legendary_total := 0
			var legendary_owned := 0
			for item in RewardService.all_rewards():
				if str(item.get("rarity", "")) == "legendary" \
						and str(item.get("id", "")) != "title_rhythm_god":
					legendary_total += 1
					legendary_owned += 1 if bool(item.get("owned", false)) else 0
			current = legendary_owned; target = legendary_total
		_:
			return {}
	var safe_target := maxi(1, target)
	return {
		"current": current,
		"target": target,
		"ratio": clampf(float(current) / float(safe_target), 0.0, 1.0),
		"text": "%d / %d" % [mini(current, target), target],
	}


func _minimum_mode_level() -> int:
	return mini(int(ProfileStore.get_mode_progress("花式").get("等级", 1)),
		mini(int(ProfileStore.get_mode_progress("竞速").get("等级", 1)),
			int(ProfileStore.get_mode_progress("DIY").get("等级", 1))))


func snapshot_for_test() -> Dictionary:
	return _data.duplicate(true)


func replace_state_for_test(state: Dictionary) -> void:
	_data = state.duplicate(true)
	_normalize_data()


func reset_for_test() -> void:
	_data = _default_data()
