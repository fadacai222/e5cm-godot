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
	if root_has_status_hud():
		StatusHud.visible = false
	PublicSystemMenu.visible = false
	splash.texture = AssetLoader.tex(STARTUP_IMAGE)
	splash.modulate.a = 0.0
	if splash.texture == null or OS.get_environment("E5CM_SKIP_BOOT") == "1":
		_finish()
		return
	_play_sequence()


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
