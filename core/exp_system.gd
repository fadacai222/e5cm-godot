class_name ExpSystem
extends RefCounted
## 等级经验系统 —— 移植自旧项目 core/等级经验.py
## 模式进度按大模式独立（花式/竞速/diy），结构：{"等级":int, "经验":float, "累计歌曲":int, "累计首数":int}

const MAX_LEVEL := 70
const EXP_DATA_VERSION := 2
const MATCH_SONG_COUNT := 3           # 正式局歌曲数
const S_STREAK_CAP := 2               # 正式局连续S倍率计数上限


## 升到下一级所需经验（分段表）
static func exp_to_next_level(level: int) -> int:
	level = clampi(level, 0, MAX_LEVEL)
	if level >= MAX_LEVEL:
		return 0
	var table := [[12, 5], [24, 10], [36, 20], [48, 45], [58, 80], [65, 130], [MAX_LEVEL, 200]]
	for entry in table:
		if level <= int(entry[0]):
			return int(entry[1])
	return 50


static func default_progress() -> Dictionary:
	return {"等级": 1, "经验": 0.0, "累计歌曲": 0, "累计首数": 0}


## 资料页长期进度：等级占主进度，本级经验补充当前等级的小数部分。
## 例如 Lv.19 / 0 EXP 仍显示约 26%，避免高等级玩家看到一条完全空的进度条。
static func overall_progress_ratio(progress: Dictionary) -> float:
	var normalized := normalize_progress(progress)
	var level := int(normalized.get("等级", 1))
	if level >= MAX_LEVEL:
		return 1.0
	var need := float(maxi(1, exp_to_next_level(level)))
	var current_level_ratio := clampf(float(normalized.get("经验", 0.0)) / need, 0.0, 1.0)
	return clampf((float(level - 1) + current_level_ratio) / float(MAX_LEVEL - 1), 0.0, 1.0)


## 原版段位：花式/竞速最高等级每 10 级升一段，1~70 对应 1~7 段。
static func rank_index_for_level(level: int) -> int:
	return clampi((clampi(level, 1, MAX_LEVEL) - 1) / 10 + 1, 1, 7)


static func rank_index_for_progress(fancy: Dictionary, racing: Dictionary) -> int:
	return rank_index_for_level(maxi(int(fancy.get("等级", 1)), int(racing.get("等级", 1))))


static func rank_asset_path(rank_index: int) -> String:
	return "UI-img/个人中心-个人资料/等级/%d.png" % clampi(rank_index, 1, 7)


## 规范化模式进度；exp_version < 2 时旧数据（0~1 比例制）换算为经验值
static func normalize_progress(progress: Dictionary, exp_version: int = EXP_DATA_VERSION) -> Dictionary:
	var result := progress.duplicate()
	result["累计歌曲"] = maxi(0, int(result.get("累计歌曲", 0)))
	result["累计首数"] = maxi(0, int(result.get("累计首数", 0)))

	var level := clampi(int(result.get("等级", 1)), 1, MAX_LEVEL)
	var exp := float(result.get("经验", 0.0))

	if level >= MAX_LEVEL:
		exp = 0.0
	else:
		var need := float(maxi(1, exp_to_next_level(level)))
		if exp_version < EXP_DATA_VERSION and exp <= 1.0 + 1e-6:
			exp *= need
		exp = clampf(exp, 0.0, need)

	result["等级"] = level
	result["经验"] = exp
	return result


## 单首基础经验：S=15 / A=7 / B~E=5 / 其他=0
static func base_exp_for_grade(grade: String) -> int:
	match grade.strip_edges().to_upper():
		"S":
			return 15
		"A":
			return 7
		"B", "C", "D", "E":
			return 5
	return 0


static func is_all_perfect(cool_n: int, good_n: int, miss_n: int) -> bool:
	return cool_n <= 0 and good_n <= 0 and miss_n <= 0


## 正式局内连续 S 倍率：返回 [倍率, 新连续S数]；非 S 清零
static func s_streak_multiplier(current_streak: int, grade: String) -> Array:
	if grade.strip_edges().to_upper() != "S":
		return [1, 0]
	var new_streak := clampi(current_streak + 1, 1, S_STREAK_CAP)
	var table := {1: 1, 2: 2}
	return [int(table.get(new_streak, 1)), new_streak]


## 单首奖励倍率：全P ×2.0 > 全连 ×1.5 > 普通 ×1.0
static func bonus_multiplier(full_combo: bool, all_perfect: bool) -> float:
	if all_perfect:
		return 2.0
	if full_combo:
		return 1.5
	return 1.0


static func final_exp(base: int, streak_mult: float, bonus_mult: float) -> int:
	var v := maxf(0.0, float(base)) * maxf(1.0, streak_mult) * maxf(1.0, bonus_mult)
	return int(maxf(0.0, v) + 0.5)  # 四舍五入


## 正式局单首歌结果
static func song_result(grade: String, cool_n: int, good_n: int, miss_n: int, current_streak: int) -> Dictionary:
	var base := base_exp_for_grade(grade)
	var streak := s_streak_multiplier(current_streak, grade)
	var full_combo := miss_n <= 0
	var all_p := is_all_perfect(cool_n, good_n, miss_n)
	var bonus := bonus_multiplier(full_combo, all_p)
	return {
		"评级": grade.strip_edges().to_upper(),
		"基础经验": base,
		"连续S倍率": int(streak[0]),
		"连续S计数": int(streak[1]),
		"奖励倍率": bonus,
		"最终经验": final_exp(base, float(streak[0]), bonus),
		"是否全连": full_combo,
		"是否ALL_PERFECT": all_p,
	}


## 赠送歌经验（第四把）：仅基础经验，无倍率
static func gift_song_result(grade: String) -> Dictionary:
	var base := base_exp_for_grade(grade)
	return {
		"评级": grade.strip_edges().to_upper(),
		"基础经验": base,
		"连续S倍率": 1,
		"连续S计数": 0,
		"奖励倍率": 1.0,
		"最终经验": base,
		"是否全连": false,
		"是否ALL_PERFECT": false,
	}


## 经验入账：支持一次跨多级，返回逐级"进度片段"驱动经验条动画
static func deposit_exp(progress: Dictionary, add_exp: float) -> Dictionary:
	var normalized := normalize_progress(progress)
	var old_level := int(normalized["等级"])
	var old_exp := float(normalized["经验"])
	var remaining := maxf(0.0, add_exp)

	var level := old_level
	var exp := old_exp
	var applied := 0.0
	var segments: Array = []

	while remaining > 1e-6 and level < MAX_LEVEL:
		var need := float(maxi(1, exp_to_next_level(level)))
		var need_left := maxf(0.0, need - exp)
		if need_left <= 1e-6:
			level += 1
			exp = 0.0
			continue

		var grow := minf(remaining, need_left)
		var end_exp := exp + grow
		var leveled := end_exp >= need - 1e-6 and level < MAX_LEVEL
		segments.append({
			"等级": level,
			"等级所需经验": need,
			"起始经验": exp,
			"结束经验": 0.0 if leveled else end_exp,
			"增长": grow,
			"是否升级": leveled,
			"升级后等级": level + 1 if leveled else level,
		})
		applied += grow
		remaining -= grow
		if leveled:
			level += 1
			exp = 0.0
		else:
			exp = end_exp

	if level >= MAX_LEVEL:
		level = MAX_LEVEL
		exp = 0.0

	var new_progress := normalized.duplicate()
	new_progress["等级"] = level
	new_progress["经验"] = exp

	return {
		"原等级": old_level,
		"原经验": old_exp,
		"等级": level,
		"经验": exp,
		"申请增加经验": maxf(0.0, add_exp),
		"实际增加经验": maxf(0.0, applied),
		"剩余未使用经验": maxf(0.0, remaining),
		"升级次数": maxi(0, level - old_level),
		"是否升级": level > old_level,
		"是否满级": level >= MAX_LEVEL,
		"进度片段": segments,
		"模式进度": new_progress,
	}
