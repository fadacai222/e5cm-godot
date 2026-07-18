extends RefCounted
## 原版/Godot 像素级对照的统一截图契约。

const EXPECTED_SIZE := Vector2i(1920, 1080)


static func validation_error(image: Image) -> String:
	if image == null or image.is_empty():
		return "capture image is empty; expected %dx%d" % [EXPECTED_SIZE.x, EXPECTED_SIZE.y]
	var actual := image.get_size()
	if actual != EXPECTED_SIZE:
		return "capture size %dx%d does not match required %dx%d" % [
			actual.x, actual.y, EXPECTED_SIZE.x, EXPECTED_SIZE.y]
	return ""


static func save_png_checked(image: Image, path: String) -> Dictionary:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)
	var message := validation_error(image)
	if not message.is_empty():
		return {"ok": false, "error": message, "path": absolute_path}
	var error := image.save_png(path)
	if error != OK:
		return {
			"ok": false,
			"error": "save_png failed with error %d" % error,
			"path": absolute_path,
		}
	return {
		"ok": true,
		"path": absolute_path,
		"width": EXPECTED_SIZE.x,
		"height": EXPECTED_SIZE.y,
	}
