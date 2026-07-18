extends SceneTree
## 1P/2P 投币界面的内置资源与视频解码接线测试。
## 运行：Godot_v4.6.2-stable_win64_console.exe --headless --path . --script res://tests/test_coin_internal_video.gd

const INTERNAL_KEYS := [
	"视频_玩家",
	"投币_logo",
	"投币_联网图标",
	"1P按钮",
	"2P按钮",
	"音乐_排行榜",
	"按钮音效",
	"投币音效",
	"满额音效",
]

var _failures := 0


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	var asset_loader: Node = load("res://autoload/asset_loader.gd").new()
	for key in INTERNAL_KEYS:
		var path := str(asset_loader.call("res_path", key))
		_check(path.begins_with("res://"), "%s 使用项目内路径" % key, path)
		_check(FileAccess.file_exists(path), "%s 文件存在" % key, path)
	var internal_logo := asset_loader.call("tex_key", "投币_logo") as Texture2D
	_check(internal_logo != null and internal_logo.resource_path.begins_with("res://"),
		"项目内 UI 通过 Godot ResourceLoader 加载",
		internal_logo.resource_path if internal_logo != null else "null")

	_check(ClassDB.class_exists("FFmpegVideoStream"), "内置 FFmpegVideoStream 解码器可用")
	var video_stream := load("res://assets/video/player_select/003.mp4")
	_check(video_stream is VideoStream, "内置 MP4 可加载为 VideoStream")
	var player := VideoStreamPlayer.new()
	player.stream = video_stream
	player.volume_db = -80.0
	root.add_child(player)
	await process_frame
	player.play()
	await create_timer(0.35).timeout
	_check(player.is_playing(), "内置 MP4 已进入播放状态")
	_check(player.stream_position > 0.0, "内置 MP4 播放进度前进", str(player.stream_position))
	player.stop()
	root.remove_child(player)
	player.free()
	video_stream = null
	asset_loader.free()

	if _failures == 0:
		print("ALL COIN INTERNAL VIDEO TESTS PASSED")
	else:
		print("%d COIN INTERNAL VIDEO TEST(S) FAILED" % _failures)
	quit(_failures)
