class_name ChallengeProgressPopup
extends Control
## 结算挑战推进短提示：不暂停、不延长结算，允许点击立即关闭。

var _panel: Control
var _hide_tween: Tween

func _ready() -> void:
	name = "ChallengeProgressPopup"
	position = Vector2(1240, 700)
	size = Vector2(620, 300)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 2200
	visible = false

func show_changes(changes: Array) -> void:
	if changes.is_empty():
		return
	if _panel != null and is_instance_valid(_panel):
		_panel.free()
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.size = size
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	UiKit.hud_frame(_panel, Rect2(Vector2.ZERO, size), "Frame",
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 52.0, true, 18.0)
	var title := UiKit.label(_panel, "挑战进度 / CHALLENGE", 24,
		Vector2(24, 10), Color(0.35, 0.95, 1.0), 2)
	title.size = Vector2(500, 34)
	var shown := mini(3, changes.size())
	for i in shown:
		var change: Dictionary = changes[i] if changes[i] is Dictionary else {}
		var completed := bool(change.get("completed", false))
		var description := str(change.get("description", "挑战已推进"))
		var progress := float(change.get("progress", 0.0))
		var target := float(change.get("target", 1.0))
		var text := "%s %s  %s/%s" % [
			"完成" if completed else "推进", description,
			_format_value(progress), _format_value(target)]
		var label := UiKit.label(_panel, text, 18, Vector2(26, 66 + i * 62),
			Color(0.55, 1.0, 0.68) if completed else Color.WHITE, 2)
		label.size = Vector2(566, 28)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		if completed:
			var reward_id := str(change.get("reward_id", ""))
			var reward_prefix := "奖励已解锁：" if bool(change.get("claimed", false)) else "奖励待补发："
			var reward := UiKit.label(_panel, reward_prefix + RewardService.reward_name(reward_id),
				15, Vector2(44, 92 + i * 62), Color(1.0, 0.75, 0.95), 1)
			reward.size = Vector2(540, 24)
	if changes.size() > shown:
		var more := UiKit.label(_panel, "另有 %d 项进度已更新" % (changes.size() - shown),
			16, Vector2(26, 252), Color(0.75, 0.84, 0.96), 1)
		more.size = Vector2(400, 24)
	var close := Button.new()
	close.name = "Dismiss"
	close.text = "关闭"
	close.position = Vector2(500, 244)
	close.size = Vector2(96, 38)
	close.pressed.connect(hide_popup)
	UiKit.skin_arcade_button(close, false, false, 16, E5OriginalTheme.MAGENTA)
	_panel.add_child(close)

	visible = true
	_panel.modulate.a = 0.0
	_panel.position = Vector2(22, 0)
	var enter := create_tween().set_parallel(true)
	enter.tween_property(_panel, "modulate:a", 1.0, 0.18)
	enter.tween_property(_panel, "position", Vector2.ZERO, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _hide_tween != null and _hide_tween.is_valid():
		_hide_tween.kill()
	_hide_tween = create_tween()
	_hide_tween.tween_interval(4.2)
	_hide_tween.tween_property(_panel, "modulate:a", 0.0, 0.25)
	_hide_tween.tween_callback(hide_popup)

func hide_popup() -> void:
	visible = false
	if _hide_tween != null and _hide_tween.is_valid():
		_hide_tween.kill()
	_hide_tween = null

func _format_value(value: float) -> String:
	return "%.1f" % value if not is_equal_approx(value, roundf(value)) else str(int(roundf(value)))
