extends SceneTree
## 2026-07-18 视觉验收后补修回归：搜索分帧、JSON 单双踏、ESC 退出、DIY 经验、Hold 轨迹与情侣皮肤。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SharedVideoBackground", "res://autoload/shared_video_background.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
	["GameState", "res://autoload/game_state.gd"],
	["ProfileStore", "res://autoload/profile_store.gd"],
	["SongLibrary", "res://autoload/song_library.gd"],
	["AudioDirector", "res://autoload/audio_director.gd"],
	["SceneRouter", "res://autoload/scene_router.gd"],
]

var _failures := 0
var _created: Array[Node] = []
var _search_progress_samples: Array = []


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _write_json(path: String, player2 := false, explicit_mode := "") -> void:
	var arrows := [
		{"aType": 1, "player": 1, "length": 0},
		{"aType": 4, "player": 1, "length": 96},
	]
	if player2:
		arrows.append({"aType": 7, "player": 2, "length": 0})
	var data := {
		"title": "验收 JSON",
		"artist": "验收歌手",
		"scoreInfo": {"offset": 0.0},
		"bpms": [{"lineNo": 0, "bpmVal": 128.0}],
		"boards": [{"lineDatas": [{"lineNo": 96, "arrows": arrows}]}],
	}
	if not explicit_mode.is_empty():
		data["mode"] = explicit_mode
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _on_search_progress(current: int, total: int, status: String) -> void:
	_search_progress_samples.append([current, total, status])


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame

	var settings = root.get_node("SettingsStore")
	settings.persist_enabled = false
	var profile_store = root.get_node("ProfileStore")
	profile_store.persist_enabled = false
	profile_store.profile = profile_store.call("_default_profile")
	profile_store.profile["进度"]["diy"] = {
		"等级": 37, "经验": 22.0, "累计歌曲": 12, "累计首数": 12,
	}

	# JSON 单人谱不能因为 caller 传入 prefer_double 就被扩成 10 轨。
	var single_path := "user://qa_post_visual_single.json"
	var double_path := "user://qa_post_visual_double.json"
	var remix_path := "user://qa_post_visual_remix.json"
	_write_json(single_path, false)
	_write_json(double_path, true)
	_write_json(remix_path, false, "remix")
	var sm_parser = load("res://core/sm_parser.gd")
	var single_result: Dictionary = sm_parser.build_json_events(single_path, true)
	var double_result: Dictionary = sm_parser.build_json_events(double_path, false)
	_check(int(single_result.get("columns", 0)) == 5,
		"单人 JSON 即使 prefer_double=true 仍保持 5 轨", str(single_result.get("columns")))
	_check(int(double_result.get("columns", 0)) == 10,
		"真实 player=2 JSON 自动识别为 10 轨", str(double_result.get("columns")))

	var library = root.get_node("SongLibrary")
	_check(library.has_method("json_song_mode_for_test"),
		"SongLibrary 提供 JSON 模式识别契约")
	if library.has_method("json_song_mode_for_test"):
		var remix_mode: Dictionary = library.call("json_song_mode_for_test", remix_path)
		var single_mode: Dictionary = library.call("json_song_mode_for_test", single_path)
		_check(str(remix_mode.get("style", "")) == "混音",
			"JSON 显式 remix 元数据映射为混音模式", str(remix_mode))
		_check(str(single_mode.get("charttype", "")) == "json-single",
			"未标模式的单人 JSON 安全回退 json-single", str(single_mode))

	# 大列表搜索必须提供分帧进度，不允许一次同步扫完所有谱面文件。
	_check(library.has_method("search_songs_async") and library.has_signal("search_progress"),
		"SongLibrary 提供渐进搜索与进度信号")
	if library.has_method("search_songs_async") and library.has_signal("search_progress"):
		if not library.search_progress.is_connected(_on_search_progress):
			library.search_progress.connect(_on_search_progress)
		var source: Array = []
		for i in 240:
			source.append({"name": "歌曲_%03d" % i,
				"artist": "凤凰传奇" if i % 60 == 0 else "其他歌手",
				"folder": "qa_%03d" % i, "subtitle": "", "sm": ""})
		var results: Array = await library.call("search_songs_async", source, "凤凰传奇")
		_check(results.size() == 4, "渐进搜索返回全部匹配歌曲", str(results.size()))
		_check(_search_progress_samples.size() >= 3 \
			and int(_search_progress_samples[-1][0]) == int(_search_progress_samples[-1][1]),
			"渐进搜索上报中间进度并以 100% 收尾", str(_search_progress_samples))

	# 非 Gameplay ESC 也必须提供退出到桌面入口，且资料页显示真实 DIY 进度。
	var menu = load("res://ui/esc_menu.gd").new(false)
	root.add_child(menu)
	await process_frame
	var tabs: Array = menu.call("_tab_defs")
	_check(tabs.any(func(tab): return str(tab[1]) == "EXIT TO DESKTOP"),
		"选歌 ESC 包含退出到桌面入口", str(tabs))
	menu.call("_set_tab", 4)
	await process_frame
	var content_body := menu.get("_content_body") as Control
	var diy_bar := content_body.get_node_or_null("ProfileProgressCard/diyProgress/diyExperienceProgress")
	var diy_level := content_body.get_node_or_null("ProfileProgressCard/diyProgress/Level") as Label
	_check(diy_bar != null and diy_level != null and diy_level.text.contains("37"),
		"ESC 用户信息页显示真实 DIY 37 级和经验进度",
		diy_level.text if diy_level else "missing")

	# Hold 禁止参与摇摆/旋转，Tap 仍正常参与。
	var field = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(field)
	field.setup(5, 1.0)
	var judge_script = load("res://core/judge_system.gd")
	var hold = judge_script.JudgeNote.new(2, "hold", 1.0, 3.0, [1.5, 2.0, 2.5])
	var tap = judge_script.JudgeNote.new(1, "tap", 1.4, 1.4, [])
	field.load_notes([hold, tap])
	settings.track_mode = "摇摆"
	field.update_field(0.0, 0.016)
	var hold_item: Dictionary = field.get("_render_notes")[0]
	var tap_item: Dictionary = field.get("_render_notes")[1]
	var lane_x: Array = field.get("_lane_x")
	var hold_head := hold_item.get("head") as Sprite2D
	var hold_tail := hold_item.get("tail") as Sprite2D
	var tap_head := tap_item.get("head") as Sprite2D
	_check(hold_head != null and hold_tail != null \
		and absf(hold_head.position.x - float(lane_x[2])) < 0.1 \
		and absf(hold_tail.position.x - float(lane_x[2])) < 0.1,
		"摇摆模式不改变 Hold 头尾直线轨迹")
	_check(tap_head != null and absf(tap_head.position.x - float(lane_x[1])) > 0.1,
		"摇摆模式仍作用于 Tap 音符")
	settings.track_mode = "旋转"
	field.update_field(0.1, 0.016)
	_check(absf((hold_item.get("head") as Sprite2D).rotation) < 0.001,
		"旋转模式不旋转 Hold 头身尾")

	# 情侣皮肤必须从专用目录加载，不污染 SettingsStore 普通皮肤。
	var asset_loader = root.get_node("AssetLoader")
	_check(asset_loader.has_method("couple_arrow_atlas") \
		and asset_loader.has_method("couple_key_atlas") \
		and not (asset_loader.call("couple_arrow_atlas") as Dictionary).is_empty() \
		and not (asset_loader.call("couple_key_atlas", 1) as Dictionary).is_empty() \
		and not (asset_loader.call("couple_key_atlas", 2) as Dictionary).is_empty(),
		"情侣模式专用 arrow/key 1P/2P 图集可用")
	var previous_skin := str(settings.arrow_skin)
	field.setup(10, 1.0, true)
	_check(bool(field.get("_couple_mode")) \
		and field.get("_arrow_atlas") == asset_loader.call("couple_arrow_atlas") \
		and str(settings.arrow_skin) == previous_skin,
		"情侣局强制专用图集且不污染用户普通箭头皮肤")
	menu.couple_mode = true
	menu.call("_step_skin", 1)
	_check(str(menu.call("_get_skin")).contains("情侣专用") \
		and str(settings.arrow_skin) == previous_skin,
		"情侣局 ESC 明确显示专用皮肤锁定，禁止切换普通皮肤")

	field.queue_free()
	menu.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(single_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(double_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(remix_path))
	await process_frame
	for i in range(_created.size() - 1, -1, -1):
		var node := _created[i]
		if is_instance_valid(node) and node.get_parent() == root:
			root.remove_child(node)
			node.free()
	print("ALL POST-VISUAL ACCEPTANCE TESTS PASSED" if _failures == 0 else
		"%d POST-VISUAL ACCEPTANCE TEST(S) FAILED" % _failures)
	quit(_failures)
