class_name ChartBuilder
extends RefCounted
## 谱面构建 —— 移植自旧项目 core/玩法/谱面构建.py
## 输入音符事件 -> 判定音符列表 + 总分。
## 规则：
##  - tap = 1 个判定点
##  - hold = 头 1 个判定点 + 每个整拍 tick 1 个判定点
##  - tick 从"下一个整数拍"开始（避免与头部重叠），到结束拍为止，且必须落在 [开始秒, 结束秒] 内
##  - 总分 = 判定点数 × 5000


## events: Array[Dictionary]，每项 {track:int, start_sec:float, end_sec:float,
##          start_beat:float, end_beat:float, type:"tap"/"hold"}
## beat_to_sec: Callable(beat: float) -> float
## 返回 {"notes": Array[JudgeSystem.JudgeNote], "total_score": int}
static func build(events: Array, beat_to_sec: Callable) -> Dictionary:
	var notes: Array = []
	var point_count := 0

	for e in events:
		var track := int(e.get("track", 0))
		var st := float(e.get("start_sec", 0.0))
		var ed := float(e.get("end_sec", 0.0))
		var sb := float(e.get("start_beat", 0.0))
		var eb := float(e.get("end_beat", 0.0))
		var type := str(e.get("type", "tap"))

		if type == "tap":
			notes.append(JudgeSystem.JudgeNote.new(track, "tap", st, st, [], sb, sb))
			point_count += 1
			continue

		# hold：tick 按整拍生成
		var tick_secs: Array = []
		var first_tick_beat := int(ceilf(sb + 1e-9))
		var last_tick_beat := int(floorf(eb + 1e-9))
		for b in range(first_tick_beat, last_tick_beat + 1):
			var t := float(beat_to_sec.call(float(b)))
			if st <= t and t <= ed + 1e-6:
				tick_secs.append(t)

		notes.append(JudgeSystem.JudgeNote.new(track, "hold", st, ed, tick_secs, sb, eb))
		point_count += 1 + tick_secs.size()

	var total_score := maxi(0, point_count * 5000)
	notes.sort_custom(func(a, b): return a.start_sec < b.start_sec)
	return {"notes": notes, "total_score": total_score}
