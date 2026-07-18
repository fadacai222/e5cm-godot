class_name ScoreSystem
extends RefCounted
## 计分系统 —— 移植自旧项目 core/玩法/计分系统.py
## 百分比规则：比例先截断到小数 4 位（不四舍五入），再显示 2 位。

var total_score := 0
var current_score := 0
var current_combo := 0
var max_combo := 0
var last_judge := ""
var last_diff_ms := 0.0

# 判定统计（旧版在谱面播放器里维护，这里合并进来）
var counts := {"perfect": 0, "cool": 0, "good": 0, "miss": 0}


func _init(p_total_score: int = 0) -> void:
	total_score = maxi(0, p_total_score)


func reset(p_total_score: int = -1) -> void:
	if p_total_score >= 0:
		total_score = p_total_score
	current_score = 0
	current_combo = 0
	max_combo = 0
	last_judge = ""
	last_diff_ms = 0.0
	counts = {"perfect": 0, "cool": 0, "good": 0, "miss": 0}


func settle_all(reports: Array) -> void:
	for report in reports:
		settle_one(report)


func settle_one(report: JudgeSystem.JudgeReport) -> void:
	last_judge = report.judge
	last_diff_ms = report.time_diff_ms
	if counts.has(report.judge):
		counts[report.judge] += 1

	if report.judge == "miss":
		current_combo = 0
	else:
		current_combo += maxi(0, report.combo_add)
		if current_combo > max_combo:
			max_combo = current_combo

	current_score += maxi(0, report.score_add)


func get_percent_value() -> float:
	if total_score <= 0:
		return 0.0
	var ratio := float(current_score) / float(total_score)
	var trunc4 := floorf(ratio * 10000.0) / 10000.0
	return maxf(0.0, trunc4 * 100.0)


func get_percent_string() -> String:
	if total_score <= 0:
		return "0.00%"
	return "%.2f%%" % get_percent_value()


func is_full_combo() -> bool:
	return counts["miss"] <= 0 and (counts["perfect"] + counts["cool"] + counts["good"]) > 0


func is_all_perfect() -> bool:
	return counts["perfect"] > 0 and counts["cool"] <= 0 and counts["good"] <= 0 and counts["miss"] <= 0
