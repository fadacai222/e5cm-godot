extends Control
## 加载页 —— 旧版设计 2048×1152 ×0.9375：
## 封面(64,356,756,524) 右侧信息(906,518,764,290) 左下记录(46,893,536,136) 右下记录(1016,823,662,161)
## 背景=冷资源/backimages/选歌界面.png，星星=大星星.png。

var payload := {}
var _elapsed := 0.0
var _done := false
var _payload_ready := false
var _go_requested := false
var _load_error := ""
var _audio_status: Label
@onready var _background: TextureRect = $LoadingBackground
@onready var _cover: TextureRect = $Cover
@onready var _stars: Control = $Stars
@onready var _song_name: Label = $SongName
@onready var _song_meta: Label = $SongMeta
@onready var _credit_label: Label = $BottomCreditCenter/BottomCreditRow/CreditLabel


func _ready() -> void:
	payload = SceneRouter.take_payload()
	_resolve_payload_paths()
	_load_error = _validate_payload()
	_payload_ready = false
	_background.texture = AssetLoader.tex_key("背景_选歌")

	# 封面区
	_cover.texture = AssetLoader.tex(str(payload.get("cover", "")))
	if not _load_error.is_empty():
		_show_load_error(_load_error)

	# 右侧信息区（星区 30% + 名区 18% + 数值区 18%）
	var star := int(payload.get("star", 0))
	var star_tex := AssetLoader.tex("UI-img/选歌界面资源/小星星/大星星.png")
	var star_n := mini(star, 10)
	var star_size := minf(_stars.size.y, _stars.size.x / maxf(1.0, float(star_n)) - 4.0)
	var star_total := star_n * (star_size + 4.0)
	for k in star_n:
		var st := TextureRect.new()
		st.texture = star_tex
		st.position = Vector2((_stars.size.x - star_total) * 0.5 + k * (star_size + 4.0), 0)
		st.custom_minimum_size = Vector2(star_size, star_size)
		st.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		st.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		_stars.add_child(st)
	if star > 10:
		UiKit.label(_stars, "×%d" % star, int(star_size * 0.8),
			Vector2(_stars.size.x - 90, 8), Color(1, 0.85, 0.3))

	_song_name.text = str(payload.get("name", ""))
	_song_meta.text = "%s / %s    第 %d 把" % [str(payload.get("mode", "")),
		str(payload.get("submode", "")), GameState.flow.current_round]

	# 左下/右下记录区
	var record := ProfileStore.get_song_record(str(payload.get("sm_key", "")))
	var player_name := str(ProfileStore.profile.get("昵称", "未知")).strip_edges()
	if player_name.is_empty():
		player_name = "未知"
	$PlayerSummary/PlayerName.text = "记录保持者：%s" % player_name
	$PlayerSummary/HighScore.text = "最高分：%d" % int(record["最高分"])
	$PlayerSummary/PlayCount.text = "游玩次数：%d" % int(record["游玩次数"])
	$PlayerSummary/CurrentPlayer.text = "玩家：%s" % player_name
	$PlayerSummary/StoreName.text = "店铺：%s的电脑" % player_name
	_update_credit_label(GameState.credits)
	GameState.credits_changed.connect(_update_credit_label)
	AudioDirector.play_sfx(AssetLoader.sound("开始游戏") if AssetLoader.sound("开始游戏") != "" else "")
	_build_audio_status()
	if _load_error.is_empty():
		_prepare_audio_async()


func _build_audio_status() -> void:
	_audio_status = Label.new()
	_audio_status.name = "AudioLoadStatus"
	_audio_status.position = Vector2(906, 735)
	_audio_status.size = Vector2(764, 42)
	_audio_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_audio_status.add_theme_font_size_override("font_size", 24)
	_audio_status.add_theme_color_override("font_color", Color(0.75, 0.94, 1.0))
	_audio_status.text = "正在准备歌曲音频…" if _load_error.is_empty() else ""
	add_child(_audio_status)


func _prepare_audio_async() -> void:
	var prepared = payload.get("audio_stream")
	if prepared is AudioStream:
		_payload_ready = true
		_audio_status.text = "歌曲音频已就绪"
		return
	var mp3_path := str(payload.get("mp3", ""))
	if mp3_path.is_empty():
		_payload_ready = true
		_audio_status.text = "歌曲资源已就绪"
		return
	var stream := await AudioDirector.load_song_stream_async(mp3_path)
	if not is_inside_tree() or _done:
		return
	if stream == null:
		_load_error = "歌曲音频无法解码"
		_audio_status.text = "音频载入失败"
		_show_load_error(_load_error)
		return
	payload["audio_stream"] = stream
	_payload_ready = true
	_audio_status.text = "歌曲音频已就绪"
	if _go_requested or _elapsed >= 3.0:
		_go()


func _update_credit_label(credits: int) -> void:
	_credit_label.text = "CREDIT：%d/%d" % [maxi(0, credits), GameState.CREDITS_PER_GAME]


func _process(delta: float) -> void:
	_elapsed += delta
	if _payload_ready and _elapsed >= 3.0:
		_go()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pedal_confirm") or event.is_action_pressed("ui_accept"):
		_go()
	elif event.is_action_pressed("ui_cancel"):
		_done = true
		if _payload_ready:
			SceneRouter.change_to("submode_select")
		else:
			SceneRouter.change_to("song_select", GameState.song_select_restore)


func _go() -> void:
	if _done:
		return
	if not _payload_ready:
		_go_requested = true
		return
	_done = true
	SceneRouter.change_to("gameplay", payload, false)


func _resolve_payload_paths() -> void:
	for field in ["sm", "mp3", "cover", "video"]:
		var path := str(payload.get(field, ""))
		if not path.is_empty():
			payload[field] = AssetLoader.abs_path(path)


func _validate_payload() -> String:
	var sm_path := str(payload.get("sm", ""))
	if sm_path.is_empty() or not FileAccess.file_exists(sm_path):
		return "谱面文件缺失，无法开始游戏"
	var mp3_path := str(payload.get("mp3", ""))
	if not mp3_path.is_empty() and not FileAccess.file_exists(mp3_path):
		return "歌曲音频缺失，无法开始游戏"
	return ""


func _show_load_error(message: String) -> void:
	var label := Label.new()
	label.name = "LoadingError"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.text = "%s\n\n按 ESC 返回选歌" % message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.z_index = 100
	add_child(label)
