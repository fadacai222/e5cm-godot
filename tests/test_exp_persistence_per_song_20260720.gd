extends SceneTree
## 回归：花式/竞速/DIY 每首结算都必须形成可落盘的正式进度，不能等第三把才写入。

const ExpSystemScript = preload("res://core/exp_system.gd")
const MatchFlowScript = preload("res://core/match_flow.gd")
const ProfileStoreScript = preload("res://autoload/profile_store.gd")

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	print("== EXP PER-SONG PERSISTENCE ==")
	var flow = MatchFlowScript.new()
	flow.start_new_match()
	var progress := ExpSystemScript.default_progress()

	var first: Dictionary = flow.settle_song_exp("竞速", progress, 1, "S", 0, 0, 0)
	var first_progress: Dictionary = first.get("模式进度", {})
	_check(not bool(first.get("预览缓存", false))
		and int(first.get("经验增加值", 0)) == 30,
		"第一把经验立即成为正式入账结果", str(first))
	_check(int(first_progress.get("等级", 0)) == 7
		and absf(float(first_progress.get("经验", -1.0))) < 0.001
		and int(first_progress.get("累计歌曲", 0)) == 1
		and int(first_progress.get("累计首数", 0)) == 1,
		"第一把 30 经验与游玩计数可直接持久化", str(first_progress))

	var temp_profile_path := "user://test_exp_persistence_per_song_20260720.json"
	var absolute_temp_path := ProjectSettings.globalize_path(temp_profile_path)
	DirAccess.remove_absolute(absolute_temp_path)
	var writer = ProfileStoreScript.new()
	writer.profile_path = temp_profile_path
	writer.persist_enabled = true
	writer.profile = writer.call("_default_profile")
	writer.set_mode_progress("竞速", first_progress)
	var reader = ProfileStoreScript.new()
	reader.profile_path = temp_profile_path
	reader.profile = reader.call("_load_json", temp_profile_path, reader.call("_default_profile"))
	var reloaded_first: Dictionary = reader.get_mode_progress("竞速")
	_check(reloaded_first == first_progress,
		"第一把结束后重启读取仍保持正式等级与经验", str(reloaded_first))
	writer.free()
	reader.free()
	DirAccess.remove_absolute(absolute_temp_path)

	var second: Dictionary = flow.settle_song_exp(
		"竞速", first_progress, 2, "S", 0, 0, 0)
	var second_progress: Dictionary = second.get("模式进度", {})
	_check(int(second.get("经验增加值", 0)) == 60
		and int(second_progress.get("等级", 0)) == 16
		and int(second_progress.get("累计歌曲", 0)) == 2,
		"第二把只追加本首 60 经验，不依赖未落盘预览", str(second))

	var third: Dictionary = flow.settle_song_exp(
		"竞速", second_progress, 3, "S", 0, 0, 0)
	var third_progress: Dictionary = third.get("模式进度", {})
	_check(int(third.get("正式局总经验", 0)) == 150
		and int(third.get("经验增加值", 0)) == 60,
		"第三把保留整局 150 经验汇总，但只追加尚未入账的本首经验", str(third))
	_check(int(third_progress.get("等级", 0)) == 22
		and absf(float(third_progress.get("经验", -1.0))) < 0.001
		and int(third_progress.get("累计歌曲", 0)) == 3
		and int(third_progress.get("累计首数", 0)) == 3,
		"三把最终等级与原规则一致且不会重复入账", str(third_progress))

	print("ALL EXP PER-SONG PERSISTENCE TESTS PASSED" if _failures == 0 else
		"%d EXP PER-SONG PERSISTENCE TEST(S) FAILED" % _failures)
	quit(_failures)
