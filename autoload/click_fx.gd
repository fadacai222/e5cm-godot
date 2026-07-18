extends CanvasLayer
## 全局点击特效（autoload: ClickFx）—— 对应旧版 ui/点击特效.py
## 任意鼠标左键按下，在点击处播放 UI-img/点击特效 序列帧。

var _frames: Array = []


func _ready() -> void:
	layer = 90
	_frames = FrameAnim.from_dir(AssetLoader.abs_path("UI-img/点击特效"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_spawn(event.position)


func _input(event: InputEvent) -> void:
	# UI 控件会吞掉 unhandled，改用 _input 保证按钮上也有特效
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_spawn(event.position)


var _last_spawn_ms := 0


func _spawn(pos: Vector2) -> void:
	if _frames.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_spawn_ms < 30:   # _input 与 _unhandled_input 双触发去重
		return
	_last_spawn_ms = now
	var anim := FrameAnim.new()
	anim.position = pos
	anim.scale = Vector2(1.0, 1.0)
	anim.set_additive()
	add_child(anim)
	anim.play(_frames, 60.0, false)
