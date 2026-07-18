class_name Grade
extends RefCounted
## 评级规则 —— 取自旧项目 场景_谱面播放器.py::_构建结算载荷
## 注意：没有 D 级（S/A/B/C/E/F）。


static func from_percent(percent: float, failed: bool = false) -> String:
	if failed:
		return "F"
	if percent >= 95.0:
		return "S"
	if percent >= 90.0:
		return "A"
	if percent >= 85.0:
		return "B"
	if percent >= 80.0:
		return "C"
	if percent >= 70.0:
		return "E"
	return "F"
