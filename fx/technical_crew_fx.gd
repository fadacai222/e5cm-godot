extends Control
## 已废弃兼容占位：旧版本误把“计数组”识别成额外演示牌。
## 当前 Gameplay 不再实例化本脚本；若旧场景残留引用，也会立即自清理。

func _ready() -> void:
	visible = false
	queue_free()
