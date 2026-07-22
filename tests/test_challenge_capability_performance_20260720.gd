extends SceneTree
## 挑战首次生成能力扫描：必须使用现有曲库缓存/静态索引，不能逐谱面重新解析。

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String, detail := "") -> void:
	if condition:
		print("[PASS] ", message, " ", detail)
	else:
		failures += 1
		push_error("[FAIL] %s%s" % [message, " :: " + detail if not detail.is_empty() else ""])

func _run() -> void:
	var service = root.get_node("ChallengeService")
	var started := Time.get_ticks_msec()
	var capabilities: Dictionary = service.build_capabilities()
	var elapsed := Time.get_ticks_msec() - started
	var modes: Dictionary = capabilities.get("modes", {})
	_check(modes.has("花式") and modes.has("竞速") and modes.has("DIY"),
		"真实全曲库能力扫描识别三大可玩模式")
	_check(int((modes.get("花式", {}) as Dictionary).get("count", 0)) > 0 \
		and int((modes.get("竞速", {}) as Dictionary).get("count", 0)) > 0 \
		and int((modes.get("DIY", {}) as Dictionary).get("count", 0)) > 0,
		"挑战生成只使用真实可玩谱面能力")
	_check(elapsed < 2000, "首次挑战能力扫描不造成不可接受卡顿", "%dms" % elapsed)
	quit(1 if failures > 0 else 0)
