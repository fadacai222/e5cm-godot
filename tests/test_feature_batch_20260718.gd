extends SceneTree
## 2026-07-18 曲库搜索、原版谱面设置、段位与百连演出契约。
## 运行：godot --headless --path . --script res://tests/test_feature_batch_20260718.gd

const SongLibraryScript := preload("res://autoload/song_library.gd")
const SettingsStoreScript := preload("res://autoload/settings_store.gd")
const ExpSystemScript := preload("res://core/exp_system.gd")
const ComboFxScript := preload("res://fx/combo_milestone_fx.gd")

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	var asset_loader: Node = root.get_node_or_null("AssetLoader")
	if asset_loader == null:
		asset_loader = load("res://autoload/asset_loader.gd").new()
		asset_loader.name = "AssetLoader"
		root.add_child(asset_loader)
	var settings: Node = root.get_node_or_null("SettingsStore")
	if settings == null:
		settings = SettingsStoreScript.new()
		settings.name = "SettingsStore"
		root.add_child(settings)
	settings.persist_enabled = false
	await process_frame

	print("== 2026-07-18 feature batch ==")
	_check(ExpSystemScript.rank_index_for_level(1) == 1 \
		and ExpSystemScript.rank_index_for_level(10) == 1 \
		and ExpSystemScript.rank_index_for_level(11) == 2 \
		and ExpSystemScript.rank_index_for_level(70) == 7,
		"原版等级 1~70 正确映射到 1~7 段")
	_check(ExpSystemScript.rank_index_for_progress({"等级": 8}, {"等级": 34}) == 4,
		"段位使用花式/竞速最高等级")

	var library := SongLibraryScript.new()
	var source := [
		{"name": "最炫民族风", "artist": "凤凰传奇", "folder": "folk#9"},
		{"name": "奢香夫人", "artist": "凤凰传奇", "folder": "folk2#10"},
		{"name": "海阔天空", "artist": "Beyond", "folder": "rock#8"},
	]
	var artist_results: Array = library.search_songs(source, "凤凰 传奇")
	var title_results: Array = library.search_songs(source, "最炫-民族风")
	_check(artist_results.size() == 2, "搜索歌手返回全部匹配歌曲", str(artist_results))
	_check(title_results.size() == 1 and str(title_results[0]["name"]) == "最炫民族风",
		"搜索忽略空格、下划线和连字符")

	_check(settings.call("_normalize_hidden_mode", "渐隐") == "半隐" \
		and settings.call("_normalize_hidden_mode", "隐身") == "全隐",
		"旧隐藏设置迁移到原版半隐/全隐")
	_check(settings.call("_normalize_track_mode", "波浪") == "摇摆",
		"旧波浪设置迁移到原版摇摆")
	_check(settings.call("_normalize_direction_mode", "镜像") == "关闭" \
		and settings.call("_normalize_direction_mode", "反向") == "反向",
		"方向只保留原版关闭/反向")

	var field: Node = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(field)
	settings.direction_mode = "关闭"
	_check(absf(float(field.call("receptor_y_for_test")) - 210.0) < 0.1 \
		and float(field.call("scroll_y_for_test", 2.0, 1.0, 100.0)) > 210.0,
		"正向卷轴未来音符位于上方判定线下侧")
	settings.direction_mode = "反向"
	_check(absf(float(field.call("receptor_y_for_test")) - 870.0) < 0.1 \
		and float(field.call("scroll_y_for_test", 2.0, 1.0, 100.0)) < 870.0,
		"反向卷轴判定线移到底部且未来音符从上方进入")

	settings.direction_mode = "关闭"
	settings.hidden_mode = "半隐"
	var near_visual: Dictionary = field.call("note_visual_for_test", 500.0, 215.0, 1.0, 2.0, 0)
	var far_visual: Dictionary = field.call("note_visual_for_test", 500.0, 700.0, 1.0, 2.0, 0)
	_check(float(near_visual["alpha"]) < 0.1 and float(far_visual["alpha"]) > 0.9,
		"半隐在判定线附近淡出、远处保持可见", "%s / %s" % [near_visual, far_visual])
	settings.hidden_mode = "全隐"
	var full_hidden: Dictionary = field.call("note_visual_for_test", 500.0, 700.0, 1.0, 2.0, 0)
	_check(float(full_hidden["alpha"]) == 0.0, "全隐隐藏运行音符")

	settings.hidden_mode = "关闭"
	settings.track_mode = "摇摆"
	var swing: Dictionary = field.call("note_visual_for_test", 500.0, 700.0, 1.3, 2.0, 1)
	settings.track_mode = "旋转"
	var rotate: Dictionary = field.call("note_visual_for_test", 500.0, 700.0, 1.3, 2.0, 1)
	_check(absf(float(swing["x"]) - 500.0) > 0.2, "摇摆模式产生有界横向轨迹", str(swing))
	_check(absf(float(rotate["rotation"])) > 0.01, "旋转模式产生箭头旋转", str(rotate))

	_check(ComboFxScript.milestone_for_combo(99) == 0 \
		and ComboFxScript.milestone_for_combo(100) == 100 \
		and ComboFxScript.milestone_for_combo(247) == 200,
		"百连里程碑按 100 的整数倍计算")

	var tile_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	tile_image.fill(Color.WHITE)
	var tile_texture := ImageTexture.create_from_image(tile_image)
	for height in range(1, 5000, 7):
		field.call("_tiled_hold_texture", tile_texture, "test", 16, height)
	_check(int(field.call("hold_tile_cache_size_for_test")) <= 96 \
		and int(field.call("hold_tile_height_step_for_test")) == 32,
		"Hold 平铺纹理按高度分档且缓存有硬上限",
		"cache=%d" % int(field.call("hold_tile_cache_size_for_test")))

	var effect_03: Dictionary = asset_loader.call("key_effect_atlas", "03")
	var effect_03_uses_shared_texture := false
	for raw_frame in effect_03.values():
		if raw_frame is AtlasTexture:
			var shared_atlas: Texture2D = (raw_frame as AtlasTexture).atlas
			effect_03_uses_shared_texture = shared_atlas != null \
				and shared_atlas.resource_path.replace("\\", "/").contains(
					"/箭头/02/key_effect/skin.png")
			break
	_check(not effect_03.is_empty() and effect_03_uses_shared_texture,
		"03 箭头保留独立帧表并复用 02 的相同击中特效纹理")

	library.free()
	field.free()
	if _failures == 0:
		print("\nALL FEATURE BATCH TESTS PASSED")
		quit(0)
	else:
		print("\n%d FEATURE BATCH TEST(S) FAILED" % _failures)
		quit(1)
