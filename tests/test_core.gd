extends SceneTree
## 核心逻辑自动化测试 —— 验证移植结果与旧版规则一致。
## 运行：godot --headless --path . --script res://tests/test_core.gd
## 数值基准全部来自《游戏设计报告.md》（旧 Python 代码实测行为）。

const JudgeSystemScript := preload("res://core/judge_system.gd")
const ScoreSystemScript := preload("res://core/score_system.gd")
const ChartBuilderScript := preload("res://core/chart_builder.gd")
const GradeScript := preload("res://core/grade.gd")
const HpSystemScript := preload("res://core/hp_system.gd")
const ExpSystemScript := preload("res://core/exp_system.gd")
const MatchFlowScript := preload("res://core/match_flow.gd")

var _failures := 0


func _initialize() -> void:
	_test_chart_builder()
	_test_judge_and_score()
	_test_grade()
	_test_hp()
	_test_exp()
	_test_match_flow()

	if _failures == 0:
		print("ALL TESTS PASSED")
	else:
		print("%d TEST(S) FAILED" % _failures)
	quit(_failures)


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


# BPM 120：1 拍 = 0.5 秒
func _beat_to_sec(beat: float) -> float:
	return beat * 0.5


func _build_test_chart() -> Dictionary:
	# tap 轨0 @beat2(1.0s)；hold 轨1 beat4~8(2.0s~4.0s，tick@2.5/3.0/3.5/4.0)；tap 轨2 @beat10(5.0s，故意不按)
	var events := [
		{"track": 0, "start_sec": 1.0, "end_sec": 1.0, "start_beat": 2.0, "end_beat": 2.0, "type": "tap"},
		{"track": 1, "start_sec": 2.0, "end_sec": 4.0, "start_beat": 4.0, "end_beat": 8.0, "type": "hold"},
		{"track": 2, "start_sec": 5.0, "end_sec": 5.0, "start_beat": 10.0, "end_beat": 10.0, "type": "tap"},
	]
	return ChartBuilderScript.build(events, _beat_to_sec)


func _test_chart_builder() -> void:
	print("== ChartBuilder ==")
	var chart := _build_test_chart()
	var notes: Array = chart["notes"]
	_check(notes.size() == 3, "音符数=3", str(notes.size()))
	var hold = notes[1]
	_check(hold.type == "hold" and hold.tick_secs.size() == 4,
		"hold tick 数=4（整拍 5,6,7,8）", str(hold.tick_secs))
	# 判定点：tap1 + (hold头1 + tick4) + tap1 = 7 -> 总分 35000
	_check(int(chart["total_score"]) == 35000, "总分=7×5000=35000", str(chart["total_score"]))


func _test_judge_and_score() -> void:
	print("== JudgeSystem + ScoreSystem ==")
	var chart := _build_test_chart()
	var judge = JudgeSystemScript.new()
	judge.load_chart(chart["notes"])
	var score = ScoreSystemScript.new(chart["total_score"])

	var held_tracks := {}
	var is_pressed := func(track: int) -> bool:
		return held_tracks.get(track, false)

	# 1) 提前 50ms 按轨0 -> perfect（+50 在 ±100 内）
	var r1: Array = judge.handle_press(0, 0.95)
	score.settle_all(r1)
	_check(r1.size() == 1 and r1[0].judge == "perfect" and absf(r1[0].time_diff_ms - 50.0) < 1e-6,
		"tap 提前50ms = perfect", "%s %.1fms" % [r1[0].judge if r1.size() else "无", r1[0].time_diff_ms if r1.size() else 0.0])
	_check(score.current_combo == 1 and score.current_score == 5000, "tap 后 combo=1 分=5000",
		"combo=%d score=%d" % [score.current_combo, score.current_score])

	# 2) 延后 30ms 按 hold 头 -> perfect；按住到结束
	var r2: Array = judge.handle_press(1, 2.03)
	score.settle_all(r2)
	_check(r2.size() == 1 and r2[0].type == "hold_head" and r2[0].judge == "perfect",
		"hold 头延后30ms = perfect", str(r2[0].judge if r2.size() else "无"))

	held_tracks[1] = true
	var t := 2.03
	while t < 4.2:
		t += 1.0 / 60.0
		score.settle_all(judge.update(t, is_pressed))
	held_tracks[1] = false

	# tap1 + hold头1 + tick4×4 = 2 + 16 = 18 连击；分 = 6×5000 = 30000
	_check(score.current_combo == 18, "hold 全程按住后 combo=18（tick 每拍+4）", "combo=%d" % score.current_combo)
	_check(score.current_score == 30000, "分数=30000", "score=%d" % score.current_score)
	_check(score.counts["perfect"] == 6, "perfect 计数=6（tick 继承头判）", str(score.counts))

	# 3) 轨2 不按，过点 -> 自动 miss，combo 清零
	score.settle_all(judge.update(5.3, is_pressed))
	_check(score.counts["miss"] == 1 and score.current_combo == 0, "超时自动 miss 且 combo 清零",
		"miss=%d combo=%d" % [score.counts["miss"], score.current_combo])
	_check(score.max_combo == 18, "max_combo 保留 18", str(score.max_combo))

	# 4) 百分比截断规则：30000/35000 = 0.857142.. -> 截断 0.8571 -> "85.71%"
	_check(score.get_percent_string() == "85.71%", "百分比截断（非四舍五入）= 85.71%",
		score.get_percent_string())

	# 5) 判定窗口边界
	var jw = JudgeSystemScript.new()
	_check(jw._judge_from_diff(100.0) == "perfect" and jw._judge_from_diff(101.0) == "cool",
		"±100ms perfect 边界")
	_check(jw._judge_from_diff(-150.0) == "cool" and jw._judge_from_diff(151.0) == "good",
		"±150ms cool 边界")
	_check(jw._judge_from_diff(200.0) == "good" and jw._judge_from_diff(-201.0) == "miss",
		"±200ms good 边界")

	# 6) 自动模式全 perfect
	var auto = JudgeSystemScript.new()
	auto.auto_mode = true
	var chart2 := _build_test_chart()
	auto.load_chart(chart2["notes"])
	var auto_score = ScoreSystemScript.new(chart2["total_score"])
	var t2 := 0.0
	while t2 < 6.0:
		t2 += 1.0 / 60.0
		auto_score.settle_all(auto.update(t2, is_pressed))
	_check(auto_score.get_percent_string() == "100.00%" and auto_score.is_all_perfect(),
		"autoplay 全 perfect 100.00%", auto_score.get_percent_string())


func _test_grade() -> void:
	print("== Grade ==")
	_check(GradeScript.from_percent(95.0) == "S" and GradeScript.from_percent(94.99) == "A", "S/A 边界 95")
	_check(GradeScript.from_percent(90.0) == "A" and GradeScript.from_percent(85.0) == "B", "A=90 B=85")
	_check(GradeScript.from_percent(80.0) == "C" and GradeScript.from_percent(70.0) == "E", "C=80 E=70（无D级）")
	_check(GradeScript.from_percent(69.9) == "F" and GradeScript.from_percent(99.0, true) == "F", "低于70=F，失败强制F")


func _test_hp() -> void:
	print("== HpSystem ==")
	var hp = HpSystemScript.new()
	_check(hp.hp == 700 and hp.visible_hp() == 500 and is_equal_approx(hp.visible_ratio(), 0.5),
		"初始总 HP=700，扣除隐藏 200 后显示 50%", "total=%d visible=%d ratio=%.3f" % [hp.hp, hp.visible_hp(), hp.visible_ratio()])
	var report := JudgeSystemScript.JudgeReport.new("tap", 0, "perfect", 0.0, 5000, 1)
	var miss := JudgeSystemScript.JudgeReport.new("tap", 0, "miss", 0.0, 0, 0)
	hp.apply_reports([report])
	_check(hp.hp == 720, "perfect +20", str(hp.hp))
	hp.apply_reports([miss])
	_check(hp.hp == 680, "miss -40", str(hp.hp))
	# 连吃 perfect 到上限 1200
	for i in 40:
		hp.apply_reports([report])
	_check(hp.hp == 1200 and hp.visible_hp() == 1000 and hp.is_overdrive(),
		"上限1200 显示钳1000 暴走", "hp=%d" % hp.hp)
	# 一路 miss 到死
	var dead := false
	for i in 30:
		dead = hp.apply_reports([miss])
		if dead:
			break
	_check(dead and hp.hp == 0, "HP 归零判死", "hp=%d" % hp.hp)


func _test_exp() -> void:
	print("== ExpSystem ==")
	_check(ExpSystemScript.exp_to_next_level(1) == 5 and ExpSystemScript.exp_to_next_level(12) == 5,
		"1~12级每级5经验")
	_check(ExpSystemScript.exp_to_next_level(13) == 10 and ExpSystemScript.exp_to_next_level(49) == 80,
		"分段表 13→10 / 49→80")
	_check(ExpSystemScript.exp_to_next_level(70) == 0, "满级70无需求")
	_check(ExpSystemScript.base_exp_for_grade("S") == 15 and ExpSystemScript.base_exp_for_grade("A") == 7
		and ExpSystemScript.base_exp_for_grade("C") == 5 and ExpSystemScript.base_exp_for_grade("F") == 0,
		"基础经验 S15/A7/BCDE5/F0")

	# 连续S倍率：第1次S ×1，第2次S ×2（封顶），非S清零
	var m1: Array = ExpSystemScript.s_streak_multiplier(0, "S")
	var m2: Array = ExpSystemScript.s_streak_multiplier(1, "S")
	var m3: Array = ExpSystemScript.s_streak_multiplier(2, "S")
	var m4: Array = ExpSystemScript.s_streak_multiplier(2, "A")
	_check(m1[0] == 1 and m2[0] == 2 and m3[0] == 2 and m4[0] == 1 and m4[1] == 0,
		"连续S倍率 1/2/2(封顶)，非S清零")

	# 全P ×2 优先于全连 ×1.5
	_check(ExpSystemScript.bonus_multiplier(true, true) == 2.0
		and ExpSystemScript.bonus_multiplier(true, false) == 1.5
		and ExpSystemScript.bonus_multiplier(false, false) == 1.0, "奖励倍率 全P2.0/全连1.5/普通1.0")

	# S + 连续S×2 + 全P×2 = 15×2×2 = 60
	_check(ExpSystemScript.final_exp(15, 2.0, 2.0) == 60, "最终经验 15×2×2=60")

	# 入账跨级：1级0经验 +12 -> 升2级（5+5）余2 -> 3级2经验
	var deposit := ExpSystemScript.deposit_exp(ExpSystemScript.default_progress(), 12.0)
	_check(int(deposit["等级"]) == 3 and absf(float(deposit["经验"]) - 2.0) < 1e-6
		and int(deposit["升级次数"]) == 2 and (deposit["进度片段"] as Array).size() == 3,
		"跨级入账 1级+12经验 -> 3级余2（3个进度片段）",
		"等级=%s 经验=%s" % [deposit["等级"], deposit["经验"]])

	# 旧版数据换算：经验版本1、0.6比例 × 5 = 3.0
	var legacy := {"等级": 5, "经验": 0.6, "累计歌曲": 0, "累计首数": 0}
	var normalized := ExpSystemScript.normalize_progress(legacy, 1)
	_check(absf(float(normalized["经验"]) - 3.0) < 1e-6, "旧版比例制经验换算 0.6→3.0", str(normalized["经验"]))


func _test_match_flow() -> void:
	print("== MatchFlow ==")
	var flow = MatchFlowScript.new()
	flow.start_new_match()

	# 三把 S -> 第3把触发赠送
	flow.current_round = 1
	var s1: Dictionary = flow.settle_round("S", false)
	flow.current_round = 2
	var s2: Dictionary = flow.settle_round("S", false)
	flow.current_round = 3
	var s3: Dictionary = flow.settle_round("S", false)
	_check(not s1["三把S赠送"] and not s2["三把S赠送"] and s3["三把S赠送"] and s3["结算后S数"] == 3,
		"三把S在第3把触发赠送第四把", str(s3))

	# 经验：3 首 S 全P —— 每首立即入账，局内仍保留连续 S 倍率与整局汇总。
	var flow2 = MatchFlowScript.new()
	flow2.start_new_match()
	var progress := ExpSystemScript.default_progress()
	var r1: Dictionary = flow2.settle_song_exp("竞速", progress, 1, "S", 0, 0, 0)
	_check(str(r1["结算类型"]) == "正式局单曲入账" and int(r1["经验增加值"]) == 30
		and int(r1["缓存经验值"]) == 30, "第1把 S全P 30经验立即入账（15×1×2）", str(r1))
	_check(not bool(r1.get("预览缓存", false)) and bool(r1.get("显示奖励窗", false)) \
		and int(r1.get("正式局总经验", 0)) == 30 and int(r1["模式进度"].get("等级", 0)) == 7,
		"第1把正式进度可直接保存，退出游戏也不丢经验", str(r1))
	progress = r1["模式进度"]
	var r2: Dictionary = flow2.settle_song_exp("竞速", progress, 2, "S", 0, 0, 0)
	_check(int(r2["经验增加值"]) == 60 and int(r2["缓存经验值"]) == 60,
		"第2把 连续S×2 的60经验立即入账（15×2×2）", str(r2))
	_check(not bool(r2.get("预览缓存", false)) and int(r2.get("正式局总经验", 0)) == 90
		and int(r2["模式进度"].get("等级", 0)) == 16,
		"第2把显示整局累计90经验，但只追加本首60经验", str(r2))
	progress = r2["模式进度"]
	var r3: Dictionary = flow2.settle_song_exp("竞速", progress, 3, "S", 0, 0, 0)
	_check(str(r3["结算类型"]) == "正式局结算" and int(r3["正式局总经验"]) == 150
		and int(r3["经验增加值"]) == 60 and bool(r3["显示奖励窗"]),
		"第3把整局汇总150经验，本首60经验不重复入账", str(r3))
	# 三首累计仍为 150：等级1~12每级5共60，13~21每级10共90，最终22级0经验。
	var final_progress: Dictionary = r3["模式进度"]
	_check(int(final_progress["等级"]) == 22 and float(final_progress["经验"]) < 1e-6
		and int(final_progress.get("累计歌曲", 0)) == 3,
		"三首累计150经验 1级→22级余0且计数=3", str(final_progress))

	# 第4把赠送歌：静默入账
	progress = r3["模式进度"]
	var r4: Dictionary = flow2.settle_song_exp("竞速", progress, 4, "A", 1, 0, 0)
	_check(str(r4["结算类型"]) == "赠送歌静默入账" and not bool(r4["显示奖励窗"])
		and int(r4["单首歌结果"]["最终经验"]) == 7, "第4把赠送歌 A=7经验 静默入账", str(r4["单首歌结果"]["最终经验"]))
