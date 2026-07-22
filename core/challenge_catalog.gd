class_name ChallengeCatalog
extends RefCounted
## 每日/周常挑战模板目录。只处理纯规则，不访问场景或存档。

const CATALOG_VERSION := 2
const ELIGIBILITY_VERSION := 1
const GRADE_ORDER := {"F": 0, "D": 1, "C": 2, "B": 3, "A": 4, "S": 5}

var _templates: Array[Dictionary] = [
	{"id": "launch_game", "category": "activity", "periods": ["daily"], "difficulty": "normal", "kind": "counter"},
	{"id": "clear_any", "category": "clear", "periods": ["daily", "weekly"], "difficulty": "normal", "kind": "counter"},
	{"id": "clear_mode", "category": "mode", "periods": ["daily", "weekly"], "difficulty": "normal", "kind": "counter"},
	{"id": "min_star", "category": "difficulty", "periods": ["daily", "weekly"], "difficulty": "advanced", "kind": "counter"},
	{"id": "grade_at_least", "category": "grade", "periods": ["daily", "weekly"], "difficulty": "advanced", "kind": "counter"},
	{"id": "combo_at_least", "category": "combo", "periods": ["daily", "weekly"], "difficulty": "advanced", "kind": "counter"},
	{"id": "miss_at_most", "category": "accuracy", "periods": ["daily", "weekly"], "difficulty": "challenge", "kind": "counter"},
	{"id": "good_at_most", "category": "accuracy", "periods": ["daily", "weekly"], "difficulty": "challenge", "kind": "counter"},
	{"id": "accuracy_at_least", "category": "accuracy", "periods": ["daily", "weekly"], "difficulty": "challenge", "kind": "counter"},
	{"id": "first_play", "category": "discovery", "periods": ["daily", "weekly"], "difficulty": "normal", "kind": "counter"},
	{"id": "new_record", "category": "record", "periods": ["daily", "weekly"], "difficulty": "advanced", "kind": "counter"},
	{"id": "random_song", "category": "discovery", "periods": ["daily", "weekly"], "difficulty": "normal", "kind": "counter"},
	{"id": "modifier_clear", "category": "settings", "periods": ["daily", "weekly"], "difficulty": "advanced", "kind": "counter"},
	{"id": "clear_count", "category": "volume", "periods": ["weekly"], "difficulty": "normal", "kind": "counter"},
	{"id": "s_count", "category": "grade", "periods": ["weekly"], "difficulty": "advanced", "kind": "counter"},
	{"id": "perfect_count", "category": "accuracy", "periods": ["weekly"], "difficulty": "advanced", "kind": "counter"},
	{"id": "unique_songs", "category": "discovery", "periods": ["weekly"], "difficulty": "normal", "kind": "absolute"},
	{"id": "multi_mode", "category": "mode", "periods": ["weekly"], "difficulty": "normal", "kind": "absolute"},
	{"id": "play_minutes", "category": "activity", "periods": ["weekly"], "difficulty": "normal", "kind": "counter"},
	{"id": "two_player_clear", "category": "two_player", "periods": ["daily", "weekly"], "difficulty": "advanced", "kind": "counter"},
]

func templates() -> Array:
	return _templates.duplicate(true)

func template(template_id: String) -> Dictionary:
	for item in _templates:
		if str(item.get("id", "")) == template_id:
			return item.duplicate(true)
	return {}

func supports_period(item: Dictionary, period: String) -> bool:
	return period in (item.get("periods", []) as Array)

func is_available(item: Dictionary, capabilities: Dictionary) -> bool:
	var template_id := str(item.get("id", ""))
	var modes: Dictionary = capabilities.get("modes", {})
	match template_id:
		"launch_game":
			return true
		"first_play":
			return bool(capabilities.get("has_unplayed", false))
		"new_record":
			return bool(capabilities.get("has_breakable_record", false))
		"two_player_clear":
			return bool(capabilities.get("two_player", false))
		"random_song":
			return bool(capabilities.get("has_random_source", false))
		_:
			return not modes.is_empty()

func describe(instance: Dictionary) -> String:
	var template_id := str(instance.get("template_id", ""))
	var params: Dictionary = instance.get("params", {})
	var target := int(instance.get("target", 1))
	match template_id:
		"launch_game": return "今日登录并查看挑战"
		"clear_any": return "完成 %d 首歌曲" % target
		"clear_mode": return "在%s模式完成 %d 首歌曲" % [str(params.get("mode", "指定")), target]
		"min_star": return "完成 %d 星及以上歌曲 %d 首" % [int(params.get("min_star", 1)), target]
		"grade_at_least": return "获得 %s 级及以上 %d 次" % [str(params.get("grade", "A")), target]
		"combo_at_least": return "单局达到 %d Combo" % int(params.get("combo", 100))
		"miss_at_most": return "以 Miss 不超过 %d 完成歌曲" % int(params.get("miss", 3))
		"good_at_most": return "以 Good 不超过 %d 完成歌曲" % int(params.get("good", 5))
		"accuracy_at_least": return "准确率达到 %.1f%%" % float(params.get("accuracy", 95.0))
		"first_play": return "完成 %d 首从未玩过的歌曲" % target
		"new_record": return "打破 %d 次个人最高分" % target
		"random_song": return "使用随机选歌完成 %d 局" % target
		"modifier_clear":
			var modifier := str(params.get("modifier", "反向"))
			return "开启%s效果完成 %d 局" % [modifier, target]
		"clear_count": return "本周累计完成 %d 首歌曲" % target
		"s_count": return "本周累计获得 %d 个 S" % target
		"perfect_count": return "本周累计获得 %d 个 Perfect" % target
		"unique_songs": return "本周完成 %d 首不同歌曲" % target
		"multi_mode": return "本周完成 %d 个不同大模式" % target
		"play_minutes": return "本周累计游玩 %d 分钟" % target
		"two_player_clear": return "2P 完成 %d 局" % target
	return "未知挑战"

func evaluate(instance: Dictionary, run: Dictionary, period_meta: Dictionary) -> float:
	if bool(run.get("failed", false)):
		return 0.0
	var template_id := str(instance.get("template_id", ""))
	var params: Dictionary = instance.get("params", {})
	match template_id:
		"launch_game": return 0.0
		"clear_any", "clear_count": return 1.0
		"clear_mode": return 1.0 if str(run.get("mode", "")) == str(params.get("mode", "")) else 0.0
		"min_star": return 1.0 if int(run.get("star", 0)) >= int(params.get("min_star", 1)) else 0.0
		"grade_at_least":
			var got := int(GRADE_ORDER.get(str(run.get("grade", "F")).to_upper(), 0))
			var need := int(GRADE_ORDER.get(str(params.get("grade", "A")).to_upper(), 4))
			return 1.0 if got >= need else 0.0
		"combo_at_least": return 1.0 if int(run.get("combo", 0)) >= int(params.get("combo", 100)) else 0.0
		"miss_at_most": return 1.0 if int(run.get("miss", 999999)) <= int(params.get("miss", 3)) else 0.0
		"good_at_most": return 1.0 if int(run.get("good", 999999)) <= int(params.get("good", 5)) else 0.0
		"accuracy_at_least": return 1.0 if float(run.get("accuracy", 0.0)) >= float(params.get("accuracy", 95.0)) else 0.0
		"first_play": return 1.0 if bool(run.get("first_play", false)) else 0.0
		"new_record": return 1.0 if bool(run.get("new_record", false)) else 0.0
		"random_song": return 1.0 if bool(run.get("random_song", false)) else 0.0
		"modifier_clear":
			var modifier := str(params.get("modifier", "反向"))
			match modifier:
				"反向": return 1.0 if str(run.get("direction_mode", "关闭")) == "反向" else 0.0
				"隐藏": return 1.0 if str(run.get("hidden_mode", "关闭")) != "关闭" else 0.0
				"摇摆": return 1.0 if str(run.get("track_mode", "正常")) == "摇摆" else 0.0
			return 0.0
		"s_count": return 1.0 if str(run.get("grade", "F")).to_upper() == "S" else 0.0
		"perfect_count": return float(maxi(0, int(run.get("perfect", 0))))
		"unique_songs": return float((period_meta.get("unique_charts", {}) as Dictionary).size())
		"multi_mode": return float((period_meta.get("modes", {}) as Dictionary).size())
		"play_minutes": return maxf(0.0, float(run.get("duration_sec", 0.0)) / 60.0)
		"two_player_clear": return 1.0 if int(run.get("players", 1)) >= 2 else 0.0
	return 0.0
