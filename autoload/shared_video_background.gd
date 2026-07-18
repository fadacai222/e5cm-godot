extends CanvasLayer
## 投币→登录→个人中心→模式→玩法选择共用的唯一视频背景层。
## 场景切换只控制显隐，不替换 stream、不重新 seek，保证画面连续。

var sequence_active := false
var _fallback: TextureRect
var _player: VideoStreamPlayer


func _ready() -> void:
	layer = -100
	visible = false

	_fallback = TextureRect.new()
	_fallback.name = "PlayerSelectFallback"
	_fallback.texture = load("res://assets/textures/coin_bg.jpg") \
		if ResourceLoader.exists("res://assets/textures/coin_bg.jpg") \
		else AssetLoader.tex_key("背景_玩家")
	_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fallback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fallback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fallback)

	_player = VideoStreamPlayer.new()
	_player.name = "PlayerSelectVideo"
	# 4:3 源视频等比铺满 16:9，裁掉上下各 180px，人物比例不变。
	_player.position = Vector2(0, -180)
	_player.size = Vector2(1920, 1440)
	_player.expand = true
	_player.loop = true
	_player.volume_db = -80.0
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var video_path := AssetLoader.res_path("视频_玩家")
	if video_path.begins_with("res://") and FileAccess.file_exists(video_path) \
		and ClassDB.class_exists("FFmpegVideoStream"):
		var video_stream := load(video_path)
		if video_stream is VideoStream:
			_player.stream = video_stream
	add_child(_player)


func begin_sequence() -> void:
	sequence_active = true
	visible = true
	if _player.stream != null:
		_player.stop()
		_player.play()


func continue_sequence() -> void:
	visible = true
	if not sequence_active:
		sequence_active = true
		if _player.stream != null:
			_player.play()
	elif _player.stream != null and not _player.is_playing():
		_player.play()


func end_sequence() -> void:
	sequence_active = false
	visible = false
	_player.stop()
