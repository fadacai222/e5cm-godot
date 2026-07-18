extends SceneTree
## 像素级对照截图契约测试。
## 运行：godot --headless --path . --script res://tests/test_capture_contract.gd

const CONTRACT_PATH := "res://tests/parity/capture_contract.gd"
var _failures := 0


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	_check(FileAccess.file_exists(CONTRACT_PATH), "存在统一截图尺寸契约", CONTRACT_PATH)
	if not FileAccess.file_exists(CONTRACT_PATH):
		print("%d CAPTURE CONTRACT TEST(S) FAILED" % _failures)
		quit(_failures)
		return

	var contract = load(CONTRACT_PATH)
	var good := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	var bad := Image.create(1886, 1061, false, Image.FORMAT_RGBA8)
	_check(contract.validation_error(good).is_empty(), "接受精确 1920x1080 截图")
	var detail: String = contract.validation_error(bad)
	_check(not detail.is_empty() and detail.contains("1886x1061") and detail.contains("1920x1080"),
		"拒绝非目标尺寸并给出实际值", detail)

	var temp_path := "user://capture-contract-invalid.png"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	var result: Dictionary = contract.save_png_checked(bad, temp_path)
	_check(not bool(result.get("ok", true)), "错误尺寸保存返回失败", str(result))
	_check(not FileAccess.file_exists(temp_path), "错误尺寸不会写入 PNG")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))

	if _failures == 0:
		print("ALL CAPTURE CONTRACT TESTS PASSED")
	else:
		print("%d CAPTURE CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
