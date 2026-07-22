class_name ChallengeDashboard
extends Control
## ESC 菜单内嵌的每日/周常挑战页。

var _summary_label: Label
var _clock_label: Label
var _daily_column: Control
var _weekly_column: Control
var _repair_button: Button


func _ready() -> void:
	name = "ChallengeDashboard"
	size = Vector2(1389, 842)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build()
	if not ChallengeService.challenges_changed.is_connected(refresh):
		ChallengeService.challenges_changed.connect(refresh)
	if not RewardService.inventory_changed.is_connected(refresh):
		RewardService.inventory_changed.connect(refresh)
	refresh()


func _build() -> void:
	var summary_card := Control.new()
	summary_card.name = "SummaryCard"
	summary_card.position = Vector2.ZERO
	summary_card.size = Vector2(1389, 104)
	add_child(summary_card)
	var summary_frame := UiKit.hud_frame(summary_card, Rect2(Vector2.ZERO, summary_card.size),
		"SummaryFrame", E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 0.0, true, 16.0)
	summary_frame.fill_color = Color(0.006, 0.035, 0.078, 0.97)
	summary_frame.show_side_ticks = false
	var eyebrow := UiKit.label(summary_card, "MISSION CONTROL", 14,
		Vector2(28, 12), Color(0.42, 0.68, 0.82), 1)
	eyebrow.size = Vector2(300, 24)
	_summary_label = UiKit.label(summary_card, "", 25, Vector2(28, 36), Color.WHITE, 2)
	_summary_label.size = Vector2(1060, 42)
	_clock_label = UiKit.label(summary_card, "", 14, Vector2(28, 76),
		Color(1.0, 0.78, 0.28), 1)
	_clock_label.size = Vector2(1040, 24)

	_repair_button = Button.new()
	_repair_button.name = "RepairButton"
	_repair_button.text = "重新校验"
	_repair_button.position = Vector2(1170, 27)
	_repair_button.size = Vector2(176, 50)
	_repair_button.pressed.connect(_repair)
	UiKit.skin_arcade_button(_repair_button, false, false, 17, E5OriginalTheme.MAGENTA)
	summary_card.add_child(_repair_button)

	# 每日任务是当下决策焦点；周常缩窄并降噪，避免两栏同权争抢视线。
	_daily_column = _build_column("DailyColumn", "今日主任务  /  DAILY FOCUS", Vector2(0, 122),
		Vector2(820, 720), E5OriginalTheme.CYAN, true)
	_weekly_column = _build_column("WeeklyColumn", "本周进度  /  WEEKLY", Vector2(846, 122),
		Vector2(543, 720), E5OriginalTheme.MAGENTA, false)


func _build_column(node_name: String, title_text: String, pos: Vector2,
		column_size: Vector2, accent: Color, primary: bool) -> Control:
	var column := Control.new()
	column.name = node_name
	column.position = pos
	column.size = column_size
	add_child(column)
	var frame := UiKit.hud_frame(column, Rect2(Vector2.ZERO, column_size), "ColumnFrame",
		accent, E5OriginalTheme.MAGENTA if accent == E5OriginalTheme.CYAN else E5OriginalTheme.CYAN,
		58.0, true, 18.0)
	frame.fill_color = Color(0.008, 0.043, 0.094, 0.97) if primary else \
		Color(0.010, 0.025, 0.060, 0.92)
	frame.header_color = Color(accent.r * (0.18 if primary else 0.09),
		accent.g * (0.18 if primary else 0.09), accent.b * (0.18 if primary else 0.09), 0.88)
	frame.scanline_color = Color(accent.r, accent.g, accent.b, 0.035 if primary else 0.014)
	var title := UiKit.label(column, title_text, 25 if primary else 19, Vector2(24, 13),
		Color(1.0, 0.86, 0.34) if primary else Color(0.68, 0.72, 0.84), 2 if primary else 1)
	title.size = Vector2(column_size.x - 48, 38)
	return column


func refresh() -> void:
	if _summary_label == null:
		return
	ChallengeService.ensure_current()
	var summary: Dictionary = ChallengeService.summary()
	_summary_label.text = "今日完成 %d/%d   ·   连续活跃 %d 天" % [
		int(summary.get("daily_completed", 0)), int(summary.get("daily_total", 0)),
		int(summary.get("streak", 0))]
	_clock_label.text = ChallengeService.clock_guard_message()
	_clock_label.visible = not _clock_label.text.is_empty()
	var errors: Array[String] = ChallengeService.validate_current()
	_repair_button.visible = not errors.is_empty()
	_clear_rows(_daily_column)
	_clear_rows(_weekly_column)
	var snapshot: Dictionary = ChallengeService.snapshot()
	_build_rows(_daily_column, snapshot.get("daily", []), 3, true)
	_build_rows(_weekly_column, snapshot.get("weekly", []), 5, false)


func _clear_rows(column: Control) -> void:
	for child in column.get_children():
		if str(child.name).begins_with("TaskRow"):
			child.free()


func _build_rows(column: Control, raw_tasks: Variant, expected_count: int, daily: bool) -> void:
	var tasks: Array = raw_tasks if raw_tasks is Array else []
	var row_height := 208.0 if daily else 122.0
	var focus_index := -1
	if daily:
		for i in mini(tasks.size(), expected_count):
			if tasks[i] is Dictionary and not bool((tasks[i] as Dictionary).get("completed", false)):
				focus_index = i
				break
	for i in mini(tasks.size(), expected_count):
		if tasks[i] is Dictionary:
			_build_task_row(column, tasks[i], i, row_height, daily and i == focus_index, daily)


func _build_task_row(column: Control, task: Dictionary, index: int, row_height: float,
		focused: bool, daily: bool) -> void:
	var row := Control.new()
	row.name = "TaskRow%d" % index
	row.position = Vector2(16, 70 + index * row_height)
	row.size = Vector2(column.size.x - 32, row_height - 12)
	column.add_child(row)
	var completed := bool(task.get("completed", false))
	var accent := E5OriginalTheme.GOLD if completed else (
		E5OriginalTheme.CYAN if focused else Color(0.30, 0.52, 0.68))
	var frame := UiKit.hud_frame(row, Rect2(Vector2.ZERO, row.size), "Frame", accent,
		E5OriginalTheme.MAGENTA, 0.0, false, 11.0)
	frame.fill_color = Color(0.030, 0.030, 0.016, 0.84) if completed else (
		Color(0.008, 0.090, 0.145, 0.98) if focused else Color(0.010, 0.035, 0.070, 0.82))
	frame.scanline_color = Color(accent.r, accent.g, accent.b, 0.045 if focused else 0.012)
	frame.show_side_ticks = focused

	var difficulty := str(task.get("difficulty", "normal"))
	var badge_text: String = str({
		"normal": "普通", "advanced": "进阶", "challenge": "挑战"}.get(difficulty, "普通"))
	var marker := "✓" if completed else ("▶" if focused else "·")
	var title := UiKit.label(row, "%s  %s" % [marker,
		str(task.get("description", "挑战"))], 18 if not daily else (24 if focused else 20),
		Vector2(20, 12), Color(0.55, 1.0, 0.68) if completed else (
			Color.WHITE if focused else Color(0.72, 0.80, 0.90)), 3 if focused else 1)
	title.size = Vector2(row.size.x - 150, 40)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var badge := UiKit.label(row, badge_text, 14, Vector2(row.size.x - 110, 13),
		Color(1.0, 0.78, 0.28) if focused else Color(0.56, 0.60, 0.70), 1)
	badge.size = Vector2(86, 28)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var progress := float(task.get("progress", 0.0))
	var target := maxf(1.0, float(task.get("target", 1.0)))
	var bar := ProgressBar.new()
	bar.name = "Progress"
	bar.position = Vector2(20, 57 if row_height >= 150 else 50)
	bar.size = Vector2(row.size.x - 170, 22)
	bar.min_value = 0.0
	bar.max_value = target
	bar.value = progress
	bar.show_percentage = false
	UiKit.skin_arcade_progress(bar, accent,
		E5OriginalTheme.MAGENTA if focused else Color(0.20, 0.24, 0.34))
	row.add_child(bar)
	var progress_label := UiKit.label(row, "%s / %s" % [
		_format_value(progress), _format_value(target)], 16,
		Vector2(row.size.x - 136, bar.position.y - 2), Color(0.84, 0.92, 1.0), 1)
	progress_label.size = Vector2(110, 28)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var reward_name := RewardService.reward_name(str(task.get("reward_id", "")))
	var reward := UiKit.label(row, "奖励  /  " + reward_name, 15 if focused else 13,
		Vector2(20, 100 if row_height >= 150 else 82),
		Color(0.95, 0.72, 1.0) if focused else Color(0.56, 0.54, 0.66), 1)
	reward.size = Vector2(row.size.x - 40, 28)


func _repair() -> void:
	var result: Dictionary = ChallengeService.repair_current()
	refresh()
	UiKit.toast(self, str(result.get("message", "挑战校验完成")))


func _format_value(value: float) -> String:
	return "%.1f" % value if not is_equal_approx(value, roundf(value)) else str(int(roundf(value)))
