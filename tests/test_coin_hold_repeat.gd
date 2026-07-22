extends SceneTree
## F/投币动作：短按一次，长按延迟后快速连发，松手立即停止。

var _failures := 0


func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("[PASS] %s" % message)
		return
	_failures += 1
	push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var game_state_script := load("res://autoload/game_state.gd") as Script
	var game_state: Node = game_state_script.new()
	game_state.persist_credits = false
	game_state.credits = 0

	_check(game_state.has_method("coin_hold_begin_for_test"),
		"提供可测试的长按开始入口")
	_check(game_state.has_method("coin_hold_tick_for_test"),
		"提供可测试的长按计时入口")
	_check(game_state.has_method("coin_hold_end_for_test"),
		"提供可测试的长按结束入口")

	if game_state.has_method("coin_hold_begin_for_test"):
		game_state.call("coin_hold_begin_for_test")
		_check(game_state.credits == 1, "按下投币键立即增加 1 CREDIT", str(game_state.credits))

		game_state.call("coin_hold_tick_for_test", 0.29)
		_check(game_state.credits == 1, "未达到长按延迟时不连发", str(game_state.credits))

		game_state.call("coin_hold_tick_for_test", 0.02)
		_check(game_state.credits >= 2, "达到长按延迟后开始连发", str(game_state.credits))

		var after_start: int = int(game_state.credits)
		game_state.call("coin_hold_tick_for_test", 0.24)
		_check(game_state.credits >= after_start + 3,
			"持续按住时以高频率连续投币", "%d -> %d" % [after_start, game_state.credits])

		game_state.call("coin_hold_end_for_test")
		var after_release: int = int(game_state.credits)
		game_state.call("coin_hold_tick_for_test", 1.0)
		_check(game_state.credits == after_release, "松手后立即停止连发", str(game_state.credits))

		game_state.call("coin_hold_begin_for_test")
		_check(game_state.credits == after_release + 1, "再次短按仍只先增加 1 CREDIT",
			str(game_state.credits))
		game_state.call("coin_hold_end_for_test")

	game_state.free()
	quit(1 if _failures > 0 else 0)
