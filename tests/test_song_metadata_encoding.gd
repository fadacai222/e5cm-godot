extends SceneTree
## 曲库元数据编码契约：老曲包 GB18030/GBK TITLE 必须恢复为 Unicode，
## 首次建立索引时解码子进程必须在后台线程执行，不能冻结选歌界面。

var _failures := 0
const EXPECTED_TITLE := "权志龙、太阳、黄光熙 - 我的天"
const EXPECTED_ARTIST := "测试歌手"
const TITLE_GB18030 := [200, 168, 214, 190, 193, 250, 161, 162, 204, 171, 209, 244,
	161, 162, 187, 198, 185, 226, 206, 245, 32, 45, 32, 206, 210, 181, 196, 204, 236]
const ARTIST_GB18030 := [178, 226, 202, 212, 184, 232, 202, 214]


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _write_gb18030_fixture(path: String) -> bool:
	var bytes := PackedByteArray()
	bytes.append_array("#TITLE:".to_ascii_buffer())
	bytes.append_array(PackedByteArray(TITLE_GB18030))
	bytes.append_array(";\r\n#ARTIST:".to_ascii_buffer())
	bytes.append_array(PackedByteArray(ARTIST_GB18030))
	bytes.append_array(";\r\n#BPMS:0.000=128.000;\r\n".to_ascii_buffer())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.close()
	return true


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

	var sync_fixture := "user://song_metadata_gb18030_sync.sm"
	var async_fixture := "user://song_metadata_gb18030_async.sm"
	_check(_write_gb18030_fixture(sync_fixture), "生成同步 GB18030 中文谱面样本")
	_check(_write_gb18030_fixture(async_fixture), "生成异步 GB18030 中文谱面样本")

	_check(library.has_method("decode_song_metadata_for_test"),
		"SongLibrary 提供跨编码元数据解码入口")
	var metadata: Dictionary = library.call("decode_song_metadata_for_test", sync_fixture)
	_check(str(metadata.get("title", "")) == EXPECTED_TITLE,
		"GB18030 TITLE 恢复为正确中文", str(metadata))
	_check(str(metadata.get("artist", "")) == EXPECTED_ARTIST,
		"GB18030 ARTIST 恢复为正确中文", str(metadata))
	_check(str(metadata.get("encoding", "")).to_lower().contains("gb"),
		"解码结果记录实际中文代码页", str(metadata.get("encoding", "")))

	var frame_before := Engine.get_process_frames()
	var async_metadata: Dictionary = await library.call(
		"decode_song_metadata_async_for_test", async_fixture)
	var frame_after := Engine.get_process_frames()
	_check(str(async_metadata.get("title", "")) == EXPECTED_TITLE,
		"后台线程同样正确恢复 GB18030 TITLE", str(async_metadata))
	_check(frame_after > frame_before,
		"异步元数据解码期间主循环继续推进", "%d -> %d" % [frame_before, frame_after])

	var broken_name := "�������� - �ҵ���"
	var repaired: Array = library.call("repair_song_names_for_test", [{
		"name": broken_name, "artist": "", "metadata_needs_decode": true,
		"sm": sync_fixture, "mp3": "", "cover": "",
	}])
	_check(not repaired.is_empty()
		and str(repaired[0].get("name", "")) == EXPECTED_TITLE
		and str(repaired[0].get("artist", "")) == EXPECTED_ARTIST,
		"同步修复入口替换损坏标题并补齐歌手", str(repaired))

	var async_repaired: Array = await library.call("repair_song_names_async_for_test", [{
		"name": broken_name, "artist": "", "metadata_needs_decode": true,
		"sm": async_fixture, "mp3": "", "cover": "",
	}])
	_check(not async_repaired.is_empty()
		and str(async_repaired[0].get("name", "")) == EXPECTED_TITLE
		and str(async_repaired[0].get("artist", "")) == EXPECTED_ARTIST,
		"选歌异步路径修复损坏标题并补齐歌手", str(async_repaired))

	DirAccess.remove_absolute(ProjectSettings.globalize_path(sync_fixture))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(async_fixture))
	library.queue_free()
	asset_loader.queue_free()
	await process_frame
	print("ALL SONG METADATA ENCODING TESTS PASSED" if _failures == 0 else
		"%d SONG METADATA ENCODING TEST(S) FAILED" % _failures)
	quit(_failures)
