extends SceneTree
## 选歌玩法/星级筛选单元测试。
## 运行：godot --headless --path . --script res://tests/test_song_filters.gd

const SongLibraryScript := preload("res://autoload/song_library.gd")

var _failures := 0


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	var base := {
		"name": "复合谱测试曲", "star": 9, "sm_key": "songs/test/song.sm",
		"submode": "测试曲包",
	}
	var ten_columns := "0000000000\n1000000000"
	var candidates := [
		{"charttype": "hard", "description": "level12", "difficulty": "level12",
			"meter": "9", "notes": ten_columns},
		{"charttype": "single", "description": "level7", "difficulty": "level7",
			"meter": "6", "notes": ten_columns},
		{"charttype": "lover1", "description": "level5", "difficulty": "level5",
			"meter": "4", "notes": ten_columns},
		{"charttype": "lover2", "description": "level5", "difficulty": "level5",
			"meter": "4", "notes": ten_columns},
	]

	var variants: Array = SongLibraryScript.build_song_variants(base, candidates)
	_check(variants.size() == 3, "复合谱按玩法拆成三项", str(variants))
	_check(variants.map(func(s): return str(s["style"])) == ["疯狂", "表演", "情侣"],
		"玩法顺序与原版一致", str(variants))
	_check(variants.map(func(s): return int(s["star"])) == [12, 7, 5],
		"复合谱优先读取 level 星级", str(variants))
	_check(str(variants[0]["sm_key"]).ends_with("::charttype=hard"),
		"复合谱记录键包含 charttype", str(variants[0]))

	var songs := [
		{"name": "A", "style": "疯狂", "star": 12},
		{"name": "B", "style": "表演", "star": 7},
		{"name": "C", "style": "疯狂", "star": 7},
	]
	var filtered: Array = SongLibraryScript.filter_songs(songs, "疯狂", 7)
	_check(filtered.size() == 1 and str(filtered[0]["name"]) == "C",
		"玩法与星级执行组合筛选", str(filtered))
	_check(SongLibraryScript.available_styles(songs) == ["疯狂", "表演"],
		"玩法候选按固定顺序返回", str(SongLibraryScript.available_styles(songs)))
	_check(SongLibraryScript.available_stars(songs, "疯狂") == [7, 12],
		"星级候选受玩法条件约束", str(SongLibraryScript.available_stars(songs, "疯狂")))

	if _failures == 0:
		print("ALL SONG FILTER TESTS PASSED")
	quit(_failures)
