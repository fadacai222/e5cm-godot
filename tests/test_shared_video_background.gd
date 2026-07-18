extends SceneTree
## 投币到选歌前共享视频背景回归测试。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_shared_video_background.gd

var _failures := 0


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	var path := "res://autoload/shared_video_background.gd"
	_check(FileAccess.file_exists(path), "存在跨场景共享视频背景组件", path)
	if not FileAccess.file_exists(path):
		quit(_failures)
		return

	var asset_loader: Node = root.get_node_or_null("AssetLoader")
	var created_asset_loader := asset_loader == null
	if created_asset_loader:
		asset_loader = load("res://autoload/asset_loader.gd").new()
		asset_loader.name = "AssetLoader"
		root.add_child(asset_loader)
	var shared: Node = root.get_node_or_null("SharedVideoBackground")
	var created_shared := shared == null
	if created_shared:
		shared = load(path).new()
		shared.name = "SharedVideoBackground"
		root.add_child(shared)
	await process_frame

	shared.call("begin_sequence")
	await create_timer(0.12).timeout
	var player := shared.get_node_or_null("PlayerSelectVideo") as VideoStreamPlayer
	_check(shared.get("sequence_active") == true, "进入投币场景时启动背景序列")
	_check(shared.visible, "共享视频层启动后可见")
	_check(player != null, "共享层只持有一个视频播放器")
	var before := player.get_stream_position() if player != null else 0.0

	shared.call("continue_sequence")
	await create_timer(0.12).timeout
	var after := player.get_stream_position() if player != null else 0.0
	_check(after > before + 0.03, "切换登录/中心/模式场景时视频继续前进且不倒回开头",
		"before=%.3f after=%.3f" % [before, after])
	_check(shared.get_child_count() == 2, "共享层不重复创建视频播放器", str(shared.get_child_count()))

	shared.call("end_sequence")
	_check(shared.get("sequence_active") == false, "进入选歌场景前结束视频序列")
	_check(not shared.visible, "选歌场景使用自身背景时隐藏共享层")

	if created_shared:
		root.remove_child(shared)
		shared.free()
	if created_asset_loader:
		root.remove_child(asset_loader)
		asset_loader.free()
	if _failures == 0:
		print("ALL SHARED VIDEO BACKGROUND TESTS PASSED")
	else:
		print("%d SHARED VIDEO BACKGROUND TEST(S) FAILED" % _failures)
	quit(_failures)
