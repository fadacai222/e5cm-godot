class_name HpSystem
extends RefCounted
## 血量系统 —— 数值取自旧项目 场景_谱面播放器.py
## 总上限 1200（显示上限 1000 + 隐藏 200），初始 700。
## Perfect/Cool/Good +20，Miss -40；HP<=0 立即失败。

const MAX_HP := 1200
const VISIBLE_MAX_HP := 1000
const HIDDEN_HP := 200
const START_HP := 700
const LOW_HP_GRAY_THRESHOLD := 201   # 低于此值音符层变灰

var hp := START_HP


func reset() -> void:
	hp = START_HP


static func delta_for(judge: String) -> int:
	match judge:
		"perfect", "cool", "good":
			return 20
		"miss":
			return -40
	return 0


## 返回 true 表示血量归零（立即失败）
func apply_reports(reports: Array) -> bool:
	if reports.is_empty():
		return false
	var new_hp := hp
	for report in reports:
		if report == null or not report.scoring:
			continue
		new_hp += delta_for(report.judge)
	hp = clampi(new_hp, 0, MAX_HP)
	return hp <= 0


func visible_hp() -> int:
	return clampi(hp - HIDDEN_HP, 0, VISIBLE_MAX_HP)


func visible_ratio() -> float:
	return clampf(float(visible_hp()) / float(VISIBLE_MAX_HP), 0.0, 1.0)


func is_low() -> bool:
	return hp < LOW_HP_GRAY_THRESHOLD


func is_overdrive() -> bool:
	return visible_hp() >= VISIBLE_MAX_HP
