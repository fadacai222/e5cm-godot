extends Node
## 自动测试入口场景：把驾驶器挂到 root（场景切换时存活），然后交出控制权。

func _ready() -> void:
	var driver: Node = load("res://tests/autotest_driver.gd").new()
	driver.name = "AutotestDriver"
	get_tree().root.add_child.call_deferred(driver)
