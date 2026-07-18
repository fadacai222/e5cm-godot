extends SceneTree
## 2026-07-18 轻量持续百连金化、侧边导向删除、曲库预建搜索索引与独立里程碑音效回归。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
	["SongLibrary", "res://autoload/song_library.gd"],
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
	settings.performance_mode = false

	# 按最新实机反馈删除左右空区导向带与侧边粒子，只保留轻量金化演出。
	var milestone_fx = load("res://fx/combo_milestone_fx.gd").new()
	root.add_child(milestone_fx)
	milestone_fx.configure_track_rect(Rect2(583, 110, 754, 840))
	milestone_fx.play_milestone(100, false)
	await process_frame
	_check(milestone_fx.has_method("uses_side_guides_for_test") \
		and milestone_fx.has_method("milestone_level_for_test"),
		"百连层提供侧边导向带禁用与分级契约")
	_check(not bool(milestone_fx.uses_side_guides_for_test()) \
		and int(milestone_fx.gold_particle_count_for_test()) == 0,
		"左右空区金色导向带、扫描栅格和侧边粒子已彻底删除")
	milestone_fx._process(8.0)
	_check(milestone_fx.is_active(),
		"100 Combo 轻量金化超过旧 5 秒后仍持续，直到 Combo 断掉")
	var intensity_100 := float(milestone_fx.global_gold_intensity_for_test())
	milestone_fx.play_milestone(300, false)
	var intensity_300 := float(milestone_fx.global_gold_intensity_for_test())
	_check(int(milestone_fx.milestone_level_for_test()) == 3 \
		and intensity_300 > intensity_100,
		"每多 100 Combo 只提高全局亮度与箭头金化，不再增加侧边绘制负担",
		"intensity=%.2f→%.2f" % [intensity_100, intensity_300])
	milestone_fx.stop_effect()
	_check(not milestone_fx.is_active(), "Combo 断掉后可立即停止持续金化")

	# 箭头金化必须随百连等级增强，并在高等级变成完整金色，而不是固定 5 秒描边。
	var note_field = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(note_field)
	note_field.setup(5, 4.0, false)
	_check(note_field.has_method("set_combo_gold_fx_level") \
		and note_field.has_method("combo_gold_fx_level_for_test"),
		"NoteField 提供百连等级金化接口")
	if note_field.has_method("set_combo_gold_fx_level"):
		note_field.set_combo_gold_fx_level(1)
		var receptors: Array = note_field.get("_receptors")
		var material_100 := (receptors[0] as Sprite2D).material as ShaderMaterial
		var fill_100 := float(material_100.get_shader_parameter("gold_fill")) \
			if material_100 != null else 0.0
		note_field.update_field(0.0, 8.0)
		_check(note_field.is_combo_gold_fx_enabled(),
			"箭头金化超过 5 秒仍保持，不再由定时器关闭")
		note_field.set_combo_gold_fx_level(7)
		var material_700 := (receptors[0] as Sprite2D).material as ShaderMaterial
		var fill_700 := float(material_700.get_shader_parameter("gold_fill")) \
			if material_700 != null else 0.0
		_check(int(note_field.combo_gold_fx_level_for_test()) == 7 \
			and fill_700 >= 0.98 and fill_700 > fill_100,
			"700 Combo 时整个箭头完成金化", "fill=%.2f→%.2f" % [fill_100, fill_700])
		note_field.set_combo_gold_fx_level(0)
		_check(not note_field.is_combo_gold_fx_enabled() \
			and (receptors[0] as Sprite2D).material == null,
			"Combo 断掉后箭头金化材质立即清理")

	# 曲库载入阶段预建并序列化搜索索引；正式搜索只查索引，不再读取谱面元数据。
	var library = root.get_node("SongLibrary")
	var source: Array = []
	for i in 1200:
		source.append({
			"name": "歌曲_%04d" % i,
			"artist": "凤凰传奇" if i % 200 == 0 else "其他歌手",
			"folder": "qa_%04d" % i,
			"subtitle": "",
			"sm": "",
			"sm_key": "qa_%04d" % i,
		})
	_check(library.has_method("build_search_index_for_test") \
		and library.has_method("search_index_ready_for_test") \
		and library.has_method("search_index_payload_for_test"),
		"SongLibrary 提供曲库载入阶段预建与持久化搜索索引契约")
	if library.has_method("build_search_index_for_test"):
		library.build_search_index_for_test(source)
		var payload: Dictionary = library.search_index_payload_for_test(source)
		_check(bool(library.search_index_ready_for_test(source)) \
			and payload.has("blobs") and payload.has("grams") \
			and (payload.get("blobs", []) as Array).size() == source.size(),
			"歌曲缓存同时生成搜索文本与二元索引")
		if not library.search_progress.is_connected(_on_search_progress):
			library.search_progress.connect(_on_search_progress)
		var results: Array = await library.search_songs_async(source, "凤凰传奇")
		_check(results.size() == 6, "索引搜索返回全部歌手匹配歌曲", str(results.size()))
		_check(not _search_progress_samples.is_empty() \
			and str(_search_progress_samples[-1][2]).contains("索引"),
			"搜索阶段直接查询已建索引，不再显示逐首建立索引", str(_search_progress_samples))

	# 百连里程碑必须使用短促独立音效，严禁再复用 5.4 秒 Full Combo 音效。
	var milestone_sound := str(root.get_node("AssetLoader").sound("百连突破音效"))
	var achievement_sound := str(root.get_node("AssetLoader").sound("结算前成就音效"))
	_check(not milestone_sound.is_empty() and milestone_sound != achievement_sound \
		and milestone_sound.ends_with("点击-增益5.mp3"),
		"百连使用独立短促增益音效，不再复用 Full Combo", milestone_sound)

	for node in [note_field, milestone_fx]:
		if is_instance_valid(node):
			root.remove_child(node)
			node.free()
	for node in _created:
		if is_instance_valid(node):
			root.remove_child(node)
			node.free()
	quit(1 if _failures > 0 else 0)
