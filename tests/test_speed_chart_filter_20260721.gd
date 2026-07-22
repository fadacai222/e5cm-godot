extends SceneTree
## 变速谱筛选：分类规则、真实 Nu ABO 元数据与筛选面板接线。

const SongLibraryScript := preload("res://autoload/song_library.gd")
const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["AudioDirector", "res://autoload/audio_director.gd"],
	["SongLibrary", "res://autoload/song_library.gd"],
]

var failures := 0
var _created: Array[Node] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String, detail := "") -> void:
	if ok:
		print("[PASS] ", message)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message,
			" :: " + detail if not detail.is_empty() else ""])


func _find_button_text(node: Node, wanted: String) -> bool:
	if node is Button and str((node as Button).text).contains(wanted):
		return true
	for child in node.get_children():
		if _find_button_text(child, wanted):
			return true
	return false


func _run() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var service: Node = load(entry[1]).new()
			service.name = entry[0]
			root.add_child(service)
			_created.append(service)
	await process_frame

	var constant := SongLibraryScript.build_speed_profile([[0.0, 120.0], [32.0, 120.0]])
	_check(not bool(constant.get("variable", true)) and int(constant.get("change_count", -1)) == 0,
		"重复相同 BPM 不会误判为变速谱", str(constant))

	var micro := SongLibraryScript.build_speed_profile([[0.0, 120.0], [32.0, 124.0]])
	_check(not bool(micro.get("variable", true)),
		"微小 BPM 浮动不会误判为变速谱", str(micro))

	var variable := SongLibraryScript.build_speed_profile([[0.0, 120.0], [32.0, 150.0]])
	_check(bool(variable.get("variable", false)) and not bool(variable.get("extreme", true)),
		"显著常规 BPM 变化识别为变速谱", str(variable))

	var nu_profile := SongLibraryScript.build_speed_profile([
		[0.0, 95.0], [20.0, 1045.0], [20.2291666667, 4.13], [20.25, 1045.0],
	])
	_check(bool(nu_profile.get("variable", false)) and bool(nu_profile.get("extreme", false)),
		"Nu ABO 的 1045 / 4.13 BPM 识别为极端变速谱", str(nu_profile))

	var sample := [
		{"name": "常速", "style": "表演", "star": 10,
			"speed_profile": constant},
		{"name": "普通变速", "style": "表演", "star": 10,
			"speed_profile": variable},
		{"name": "Nu 类", "style": "表演", "star": 10,
			"speed_profile": nu_profile},
		{"name": "其他玩法", "style": "疯狂", "star": 12,
			"speed_profile": nu_profile},
	]
	var variable_only := SongLibraryScript.filter_songs(sample, "表演", 10, "variable")
	var extreme_only := SongLibraryScript.filter_songs(sample, "", 0, "extreme")
	_check(variable_only.size() == 2 and variable_only.all(func(song):
		return bool((song.get("speed_profile", {}) as Dictionary).get("variable", false))),
		"玩法、星级与变速筛选可组合", str(variable_only))
	_check(extreme_only.size() == 2 and extreme_only.all(func(song):
		return bool((song.get("speed_profile", {}) as Dictionary).get("extreme", false))),
		"极端变速筛选只返回 Nu ABO 类谱面", str(extreme_only))

	var library := SongLibraryScript.new()
	var real_path := "res://songs/diy/社区竞速/NUABO#10/NUABO.json"
	var metadata: Dictionary = library.call("_json_song_metadata", real_path)
	var real_profile: Dictionary = metadata.get("speed_profile", {})
	_check(bool(real_profile.get("variable", false)) and bool(real_profile.get("extreme", false))
		and float(real_profile.get("max_bpm", 0.0)) >= 1045.0
		and float(real_profile.get("min_bpm", 9999.0)) <= 4.13,
		"真实 Nu ABO 谱面扫描元数据可直接用于筛选", str(real_profile))
	library.free()

	var actual_library := root.get_node("SongLibrary")
	var community_songs: Array = actual_library.get_songs("DIY", "社区竞速")
	var community_variable := SongLibraryScript.filter_songs(
		community_songs, "", 0, SongLibraryScript.SPEED_FILTER_VARIABLE)
	var has_real_nu := community_variable.any(func(song):
		return str(song.get("name", "")).to_lower().replace(" ", "").contains("nuabo") \
			or str(song.get("folder", "")).to_lower().replace(" ", "").contains("nuabo"))
	_check(not community_songs.is_empty() and not community_variable.is_empty() and has_real_nu,
		"当前社区竞速曲库可筛出真实 Nu ABO 与其他变速谱",
		"all=%d variable=%d" % [community_songs.size(), community_variable.size()])

	var index_data = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/e5cm_runtime/song_index.json"))
	var indexed_total := 0
	var indexed_missing := 0
	var indexed_variable := 0
	var indexed_extreme := 0
	if index_data is Dictionary:
		for raw_entries in (index_data.get("songsByKey", {}) as Dictionary).values():
			if not raw_entries is Array:
				continue
			for raw_song in raw_entries:
				if not raw_song is Dictionary:
					continue
				indexed_total += 1
				var profile: Dictionary = (raw_song as Dictionary).get("speed_profile", {})
				if profile.is_empty():
					indexed_missing += 1
				elif bool(profile.get("extreme", false)):
					indexed_variable += 1
					indexed_extreme += 1
				elif bool(profile.get("variable", false)):
					indexed_variable += 1
	_check(indexed_total > 0 and indexed_missing == 0 and indexed_variable > 0
		and indexed_extreme > 0,
		"开发版完整曲库索引预计算全部变速元数据",
		"total=%d missing=%d variable=%d extreme=%d" % [
			indexed_total, indexed_missing, indexed_variable, indexed_extreme])

	var panel_script: GDScript = load("res://scenes/song_select/filter_panel.gd")
	var panel: Control = panel_script.new()
	root.add_child(panel)
	await process_frame
	panel.call("open", ["表演"], func(_style, _speed): return [10], "", 0, "variable")
	await process_frame
	_check(str(panel.call("speed_filter_for_test")) == "variable"
		and _find_button_text(panel, "变速谱") and _find_button_text(panel, "极端变速"),
		"玩法/星级筛选面板包含变速谱与极端变速入口")
	_check(str(panel.call("summary_text_for_test")).contains("变速谱"),
		"筛选摘要显示当前变速谱条件")
	root.remove_child(panel)
	panel.free()
	for service in _created:
		if is_instance_valid(service) and service.get_parent() == root:
			root.remove_child(service)
			service.free()

	await process_frame
	quit(1 if failures > 0 else 0)
