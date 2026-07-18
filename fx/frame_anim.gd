class_name FrameAnim
extends Sprite2D
## 通用序列帧动画：接受纹理数组，按 fps 播放，one-shot 自动回收或循环。

var frames: Array = []
var fps := 30.0
var loop := false
var auto_free := true

var _t := 0.0
var _playing := false


## 加法混合（击中特效/点击特效素材为黑底光效，必须 add 混合去黑底）
func set_additive() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat


static func from_dir(dir_abs: String) -> Array:
	## 从目录加载全部 png 帧（按文件名排序）
	var result: Array = []
	var names: Array[String] = AssetLoader.list_resources(dir_abs, ["png"])
	for n in names:
		var tex := AssetLoader.tex(dir_abs.path_join(n))
		if tex != null:
			result.append(tex)
	return result


func play(p_frames: Array, p_fps := 30.0, p_loop := false) -> void:
	frames = p_frames
	fps = maxf(1.0, p_fps)
	loop = p_loop
	_t = 0.0
	_playing = not frames.is_empty()
	if _playing:
		texture = frames[0]
	visible = _playing


func stop() -> void:
	_playing = false
	visible = false
	if auto_free:
		queue_free()


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	var idx := int(_t * fps)
	if idx >= frames.size():
		if loop:
			idx = idx % frames.size()
		else:
			stop()
			return
	texture = frames[idx]
