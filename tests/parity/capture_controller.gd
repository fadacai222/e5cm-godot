extends RefCounted
## 精确 1920x1080 截图控制器；不缩放、不裁切、不补边。

const CaptureContract = preload("res://tests/parity/capture_contract.gd")


func configure_window(window: Window) -> void:
	window.mode = Window.MODE_WINDOWED
	window.borderless = true
	window.position = Vector2i.ZERO
	window.size = CaptureContract.EXPECTED_SIZE


func capture(viewport: Viewport, path: String) -> Dictionary:
	var image := viewport.get_texture().get_image()
	return CaptureContract.save_png_checked(image, path)
