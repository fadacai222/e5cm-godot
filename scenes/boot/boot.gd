extends Control
## 原版单图启动幻灯片：黑底居中、2 秒渐显、1 秒停留、1.5 秒渐隐。

const STARTUP_IMAGE := "backmovies/开场动画/001.png"
const FADE_IN_SEC := 2.0
const HOLD_SEC := 1.0
const FADE_OUT_SEC := 1.5

@onready var splash: TextureRect = $SplashImage
var _finished := false
var _sequence_tween: Tween


func _ready() -> void:
	if OS.get_environment("E5CM_RELEASE_ASSET_PROBE") == "1":
		call_deferred("_run_release_asset_probe")
		return
	if root_has_status_hud():
		StatusHud.visible = false
	PublicSystemMenu.visible = false
	splash.texture = AssetLoader.tex(STARTUP_IMAGE)
	splash.modulate.a = 0.0
	if splash.texture == null or OS.get_environment("E5CM_SKIP_BOOT") == "1":
		_finish()
		return
	_play_sequence()


func _run_release_asset_probe() -> void:
	await get_tree().process_frame
	var checks := {
		"startup_texture": AssetLoader.tex(STARTUP_IMAGE) != null,
		"song_select_background": AssetLoader.tex_key("背景_选歌") != null,
		"player_button_texture": AssetLoader.tex_key("1P按钮") != null,
		"arrow_atlas": not AssetLoader.arrow_atlas("原版默认").is_empty(),
		"key_atlas": not AssetLoader.key_atlas("原版默认").is_empty(),
		"judge_atlas": not AssetLoader.judge_atlas("原版默认").is_empty(),
		"number_atlas": not AssetLoader.number_atlas("原版默认").is_empty(),
		"key_effect_atlas": not AssetLoader.key_effect_atlas("原版默认").is_empty(),
		"blood_bar_atlas": not AssetLoader.blood_bar_atlas().is_empty(),
		"judge_text_atlas": not AssetLoader.judge_text_atlas().is_empty(),
		"player_select_video": AssetLoader.resource_exists(AssetLoader.res_path("视频_玩家")),
		"milestone_sound_removed": not AssetLoader.resource_exists(
			"res://assets/e5cm_runtime/冷资源/Buttonsound/点击-增益5.mp3"),
	}
	var sound_keys := [
		"音乐_UI", "音乐_开始", "音乐_show", "音乐_devil", "音乐_remix", "音乐_club",
		"刷卡音效", "开始游戏", "准备就绪音效", "结算音效", "gameover",
	]
	for sound_key in sound_keys:
		var path := AssetLoader.sound(sound_key)
		checks["sound_%s" % sound_key] = not path.is_empty() \
				and ResourceLoader.exists(path) \
				and load(path) is AudioStream
	var failed: Array[String] = []
	for key in checks:
		if not bool(checks[key]):
			failed.append(str(key))
	print("E5CM_RELEASE_ASSET_PROBE=%s" % JSON.stringify(checks))
	if failed.is_empty():
		print("E5CM_RELEASE_ASSET_PROBE_PASSED")
		get_tree().quit(0)
	else:
		printerr("E5CM_RELEASE_ASSET_PROBE_FAILED=%s" % ",".join(failed))
		get_tree().quit(41)


func root_has_status_hud() -> bool:
	return get_node_or_null("/root/StatusHud") != null


func _play_sequence() -> void:
	_sequence_tween = create_tween()
	_sequence_tween.tween_property(splash, "modulate:a", 1.0, FADE_IN_SEC).set_trans(Tween.TRANS_LINEAR)
	_sequence_tween.tween_interval(HOLD_SEC)
	_sequence_tween.tween_property(splash, "modulate:a", 0.0, FADE_OUT_SEC).set_trans(Tween.TRANS_LINEAR)
	await _sequence_tween.finished
	_sequence_tween = null
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	if root_has_status_hud():
		StatusHud.visible = true
	SceneRouter.change_to("coin", {}, false)


func _unhandled_input(event: InputEvent) -> void:
	# 原版启动幻灯片中 ESC 直接退出程序，不作为跳过键。
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _exit_tree() -> void:
	if _sequence_tween != null and _sequence_tween.is_valid():
		_sequence_tween.kill()
	_sequence_tween = null
	if root_has_status_hud():
		StatusHud.visible = true
