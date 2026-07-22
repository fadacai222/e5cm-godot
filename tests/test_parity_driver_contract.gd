extends SceneTree
## Godot 共享状态驱动器结构与清单加载回归测试。

const REQUIRED := [
	"res://tests/parity/parity_driver.gd",
	"res://tests/parity/parity_driver.tscn",
	"res://tests/parity/state_loader.gd",
	"res://tests/parity/fixture_controller.gd",
	"res://tests/parity/capture_controller.gd",
	"res://tests/parity/state_exporter.gd",
]
var _failures := 0


func _check(cond: bool, name: String, detail := "") -> void:
	if cond:
		print("  PASS  %s" % name)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [name, detail])


func _initialize() -> void:
	for path: String in REQUIRED:
		_check(FileAccess.file_exists(path), "驱动组件存在", path)
	if _failures == 0 and not FileAccess.file_exists("res://parity/state_manifest.json"):
		print("  SKIP  原版对照状态清单未随源码分发")
		print("ALL AVAILABLE PARITY DRIVER CONTRACT TESTS PASSED")
		quit(0)
		return
	if _failures == 0:
		var loader = load("res://tests/parity/state_loader.gd").new()
		var manifest: Dictionary = loader.load_manifest("res://parity/state_manifest.json")
		var resolution: Array = manifest.get("resolution", [])
		_check(resolution.size() == 2 and int(resolution[0]) == 1920 and int(resolution[1]) == 1080,
			"驱动读取精确分辨率")
		var state: Dictionary = loader.find_state(manifest, "coin.idle")
		_check(state.get("id", "") == "coin.idle", "按稳定 ID 读取状态")
		_check(loader.find_state(manifest, "missing.state").is_empty(), "未知状态不回退到近似项")
		loader = null
		var paths := ["user://credits.cfg", "user://profile.json", "user://records.json", "user://settings.cfg"]
		var before := {}
		for path in paths:
			before[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "<missing>"
		var fixtures = load("res://tests/parity/fixture_controller.gd").new()
		fixtures.begin({"credit": 0, "players": 1, "majorMode": "", "subMode": ""})
		fixtures.restore()
		fixtures.restore()
		var unchanged := true
		for path in paths:
			var after := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "<missing>"
			unchanged = unchanged and after == before[path]
		_check(unchanged, "夹具恢复幂等且不删除正式用户文件")
	if _failures == 0:
		print("ALL PARITY DRIVER CONTRACT TESTS PASSED")
	else:
		print("%d PARITY DRIVER CONTRACT TEST(S) FAILED" % _failures)
	quit(_failures)
