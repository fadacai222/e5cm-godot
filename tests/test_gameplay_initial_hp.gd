extends SceneTree
## 游戏开局血量回归：总 HP 与可见血条必须遵循原版的 200 点隐藏血量映射。

const HpSystemScript := preload("res://core/hp_system.gd")

var _failures := 0


func _initialize() -> void:
	var hp = HpSystemScript.new()
	_check(hp.hp == 700, "开局总 HP 保持 700", "actual=%d" % hp.hp)
	_check(hp.visible_hp() == 500, "开局可见 HP 为 500", "actual=%d" % hp.visible_hp())
	_check(is_equal_approx(hp.visible_ratio(), 0.5), "开局血条显示 50%%", "actual=%.3f" % hp.visible_ratio())
	_check(not hp.is_low(), "开局不进入低血量状态")
	_check(not hp.is_overdrive(), "开局不进入暴走状态")

	hp.hp = 200
	_check(hp.visible_hp() == 0 and is_zero_approx(hp.visible_ratio()),
		"低血量隐藏区显示为 0%%", "visible=%d ratio=%.3f" % [hp.visible_hp(), hp.visible_ratio()])
	_check(hp.is_low(), "总 HP 低于 201 时进入低血量状态")

	hp.hp = 201
	_check(hp.visible_hp() == 1 and is_equal_approx(hp.visible_ratio(), 0.001),
		"脱离低血量阈值后从 1 点可见 HP 开始", "visible=%d ratio=%.3f" % [hp.visible_hp(), hp.visible_ratio()])
	_check(not hp.is_low(), "总 HP 为 201 时退出低血量状态")

	hp.hp = 1000
	_check(hp.visible_hp() == 800 and is_equal_approx(hp.visible_ratio(), 0.8),
		"总 HP 1000 对应 80%% 可见血条", "visible=%d ratio=%.3f" % [hp.visible_hp(), hp.visible_ratio()])
	_check(not hp.is_overdrive(), "总 HP 1000 尚未暴走")

	hp.hp = 1199
	_check(hp.visible_hp() == 999 and not hp.is_overdrive(),
		"暴走前一刻保持 99.9%%", "visible=%d" % hp.visible_hp())

	hp.hp = 1200
	_check(hp.visible_hp() == 1000 and is_equal_approx(hp.visible_ratio(), 1.0),
		"满血显示 100%%", "visible=%d ratio=%.3f" % [hp.visible_hp(), hp.visible_ratio()])
	_check(hp.is_overdrive(), "只有总 HP 1200 时进入暴走")

	hp.reset()
	_check(hp.hp == 700 and hp.visible_hp() == 500,
		"重开恢复 700 总 HP / 500 可见 HP", "total=%d visible=%d" % [hp.hp, hp.visible_hp()])

	if _failures == 0:
		print("INITIAL HP TEST PASSED")
	else:
		print("%d INITIAL HP TEST(S) FAILED" % _failures)
	quit(_failures)


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("  PASS  %s" % message)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [message, detail])
