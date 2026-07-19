extends SceneTree
## 曲库扫描冒烟测试：验证各模式/子模式能扫出歌、字段完整。
## 运行：godot --headless --path . --script res://tests/test_song_library.gd

const SmParserScript := preload("res://core/sm_parser.gd")

var _failures := 0


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	# SceneTree --script 模式下 autoload 不生效，手动实例化
	var lib = load("res://autoload/song_library.gd").new()
	lib._ready()

	var t0 := Time.get_ticks_msec()
	var submodes: Array = lib.list_submodes("竞速")
	_check(submodes.has("club") and submodes.has("疯狂") and submodes.has("混音"),
		"精选竞速曲库包含已打包的 club / 疯狂 / 混音子模式", str(submodes))
	_check(lib.list_submodes("花式").has("学习"), "花式含学习模式")
	_check(not lib.list_submodes("DIY").is_empty(), "DIY 有曲包目录", str(lib.list_submodes("DIY")))

	var songs: Array = lib.get_songs("竞速", "club")
	var t1 := Time.get_ticks_msec()
	_check(not songs.is_empty(), "精选竞速/club 至少扫出一首真实歌曲", str(songs.size()))
	print("        首扫 %d 首耗时 %dms" % [songs.size(), t1 - t0])

	if not songs.is_empty():
		var s: Dictionary = songs[0]
		_check(FileAccess.file_exists(str(s["sm"])), "sm 路径有效", str(s["sm"]))
		_check(int(s["star"]) >= 1, "星级解析", str(s["star"]))
		_check(str(s["sm_key"]).begins_with("songs/"), "sm_key 规范化", str(s["sm_key"]))
		_check(not str(s["name"]).is_empty(), "歌名非空", str(s["name"]))
		print("        示例: %s 星级%d bpm%.0f" % [s["name"], s["star"], float(s["bpm"])])
		_check(lib.search_index_ready_for_test(songs),
			"曲库载入完成时搜索索引已同步建立")
		var keyword := str(s["name"]).substr(0, mini(2, str(s["name"]).length()))
		var search_started := Time.get_ticks_usec()
		var search_result: Array = lib.search_songs(songs, keyword)
		var search_elapsed_us := Time.get_ticks_usec() - search_started
		_check(not search_result.is_empty() and search_elapsed_us < 50000,
			"歌曲搜索直接查询内存索引且在 50ms 内完成",
			"keyword=%s results=%d elapsed=%dus" % [keyword, search_result.size(), search_elapsed_us])

	# DIY JSON：无需 SM/SSC，也必须被目录扫描识别并保留 JSON 格式信息。
	var diy_dir := "user://qa_diy_json_song"
	var diy_abs := ProjectSettings.globalize_path(diy_dir)
	DirAccess.make_dir_recursive_absolute(diy_abs)
	var diy_json := diy_dir.path_join("qa_chart.json")
	var diy_file := FileAccess.open(diy_json, FileAccess.WRITE)
	diy_file.store_string(JSON.stringify({
		"scoreInfo": {"offset": 0.0},
		"bpms": [{"lineNo": 0, "bpmVal": 128.0}],
		"boards": [{"lineDatas": [{"lineNo": 96, "arrows": [
			{"aType": 1, "player": 1, "length": 0},
		]}]}],
	}))
	diy_file.close()
	var diy_song: Dictionary = lib.call("_scan_song_dir", diy_abs, "qa_diy_json_song", "DIY", "qa")
	_check(not diy_song.is_empty() and str(diy_song.get("chart_format", "")) == "json" \
		and str(diy_song.get("sm", "")).to_lower().ends_with(".json") \
		and absf(float(diy_song.get("bpm", 0.0)) - 128.0) < 0.01,
		"DIY JSON 谱面可被曲库扫描识别", str(diy_song))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(diy_json))
	DirAccess.remove_absolute(diy_abs)

	# 二次读取走内存缓存
	var t2 := Time.get_ticks_msec()
	lib.get_songs("竞速", "club")
	_check(Time.get_ticks_msec() - t2 <= 5, "内存缓存生效")

	# 磁盘缓存：新实例读同一子模式应显著加速
	var lib2 = load("res://autoload/song_library.gd").new()
	lib2._ready()
	var t3 := Time.get_ticks_msec()
	var songs2: Array = lib2.get_songs("竞速", "club")
	var t4 := Time.get_ticks_msec()
	_check(songs2.size() == songs.size(), "磁盘缓存内容一致")
	_check(lib2.search_index_ready_for_test(songs2),
		"新实例从磁盘侧车缓存恢复搜索索引，无需搜索时重建")
	print("        磁盘缓存读取耗时 %dms" % (t4 - t3))

	# DIY/社区曲包使用渐进扫描并持续上报真实阶段，选歌页据此刷新进度条。
	var async_lib: Node = load("res://autoload/song_library.gd").new()
	root.add_child(async_lib)
	await process_frame
	var progress_events: Array = []
	async_lib.scan_progress.connect(func(mode: String, submode: String, current: int,
			total: int, status: String) -> void:
		progress_events.append({"mode": mode, "submode": submode, "current": current,
			"total": total, "status": status}))
	var diy_submodes: Array = async_lib.list_submodes("DIY")
	if not diy_submodes.is_empty():
		await async_lib.get_songs_async("DIY", str(diy_submodes[0]))
	var final_progress: Dictionary = progress_events[-1] if not progress_events.is_empty() else {}
	_check(not progress_events.is_empty() \
		and int(final_progress.get("current", -1)) == int(final_progress.get("total", -2)) \
		and int(final_progress.get("total", 0)) > 0,
		"DIY 渐进扫描上报阶段、百分比并以 100% 收尾", str(final_progress))

	lib.free()
	lib2.free()
	root.remove_child(async_lib)
	async_lib.free()
	if _failures == 0:
		print("ALL SONG LIBRARY TESTS PASSED")
	quit(_failures)
