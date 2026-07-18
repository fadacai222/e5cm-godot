extends SceneTree
## 曲库元数据编码契约：老曲包 GB18030/GBK TITLE 必须恢复为 Unicode，禁止把 U+FFFD 带进选歌 UI。

var _failures := 0


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	var asset_loader = load("res://autoload/asset_loader.gd").new()
	asset_loader.name = "AssetLoader"
	root.add_child(asset_loader)
	await process_frame

	var library = load("res://autoload/song_library.gd").new()
	library.name = "SongLibraryEncodingTest"
	root.add_child(library)
	library.use_static_index = false
	library._ready()

	var sample_path: String = str(asset_loader.abs_path(
		"songs/diy/破解原版曲包/wodetian_201601/wodetian_201601.sm"))
	_check(FileAccess.file_exists(sample_path), "GB18030 中文谱面样本存在", sample_path)
	_check(library.has_method("decode_song_metadata_for_test"),
		"SongLibrary 提供跨编码元数据解码入口")
	if library.has_method("decode_song_metadata_for_test"):
		var metadata: Dictionary = library.call("decode_song_metadata_for_test", sample_path)
		_check(str(metadata.get("title", "")) == "权志龙、太阳、黄光熙 - 我的天",
			"GB18030 TITLE 恢复为正确中文",
			str(metadata))
		_check(str(metadata.get("encoding", "")).to_lower().contains("gb"),
			"解码结果记录实际中文代码页", str(metadata.get("encoding", "")))

	_check(library.has_method("repair_song_names_for_test"),
		"SongLibrary 可修复静态索引中已损坏的歌曲名")
	if library.has_method("repair_song_names_for_test"):
		var songs := [{
			"name": "�������� - �ҵ���",
			"sm": sample_path,
			"mp3": "",
			"cover": "",
		}]
		var repaired: Array = library.call("repair_song_names_for_test", songs)
		_check(not repaired.is_empty() \
			and str(repaired[0].get("name", "")) == "权志龙、太阳、黄光熙 - 我的天" \
			and not str(repaired[0].get("name", "")).contains("�"),
			"损坏的静态索引名称在进入选歌卡片前被真实谱面 TITLE 替换",
			str(repaired))

	var diy_songs: Array = library.get_songs("DIY", "破解原版曲包")
	var real_card_name := ""
	for song in diy_songs:
		if str(song.get("sm", "")).contains("wodetian_201601"):
			real_card_name = str(song.get("name", ""))
			break
	_check(real_card_name == "权志龙、太阳、黄光熙 - 我的天",
		"真实 DIY 选歌数据在构建卡片前完成中文修复", real_card_name)

	var static_library = load("res://autoload/song_library.gd").new()
	static_library.name = "SongLibraryStaticEncodingTest"
	root.add_child(static_library)
	static_library._ready()
	var indexed_songs: Array = static_library.get_songs("DIY", "破解原版曲包")
	var indexed_card_name := ""
	for song in indexed_songs:
		if str(song.get("sm", "")).contains("wodetian_201601"):
			indexed_card_name = str(song.get("name", ""))
			break
	_check(indexed_card_name == "权志龙、太阳、黄光熙 - 我的天",
		"默认静态 song_index 路径同样在显示前修复中文", indexed_card_name)

	static_library.queue_free()
	library.queue_free()
	asset_loader.queue_free()
	await process_frame
	print("ALL SONG METADATA ENCODING TESTS PASSED" if _failures == 0 else
		"%d SONG METADATA ENCODING TEST(S) FAILED" % _failures)
	quit(_failures)
