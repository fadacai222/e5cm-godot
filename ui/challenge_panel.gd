class_name ChallengePanel
extends Control
## 模式选择页全屏挑战中心：每日/周常、连续活跃、奖励装备。

signal close_requested

var _content: Control
var _summary_label: Label
var _clock_label: Label
var _daily_column: Control
var _weekly_column: Control
var _close_button: Button
var _repair_button: Button
var _focus_buttons: Array[Button] = []
var _focus_index := 0
var _visible_open := false

func _ready() -> void:
	name = "ChallengePanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1800
	_build()
	visible = false

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.015, 0.045, 0.90)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_content = Control.new()
	_content.name = "Content"
	_content.position = Vector2(110, 66)
	_content.size = Vector2(1700, 940)
	add_child(_content)
	UiKit.hud_frame(_content, Rect2(0, 0, 1700, 940), "MainFrame",
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 76.0, true, 24.0)

	var title := UiKit.label(_content, "今日挑战 / DAILY & WEEKLY", 35,
		Vector2(42, 20), Color(0.35, 0.95, 1.0), 2)
	title.size = Vector2(900, 50)
	_summary_label = UiKit.label(_content, "", 22, Vector2(44, 80), Color.WHITE, 2)
	_summary_label.size = Vector2(1500, 42)
	_clock_label = UiKit.label(_content, "", 17, Vector2(44, 116),
		Color(1.0, 0.78, 0.28), 2)
	_clock_label.size = Vector2(1500, 34)

	_repair_button = Button.new()
	_repair_button.name = "RepairButton"
	_repair_button.text = "重新校验"
	_repair_button.position = Vector2(1260, 18)
	_repair_button.size = Vector2(190, 48)
	_repair_button.pressed.connect(_repair_challenges)
	UiKit.skin_arcade_button(_repair_button, false, false, 19, E5OriginalTheme.CYAN)
	_content.add_child(_repair_button)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "关闭  ESC"
	_close_button.position = Vector2(1470, 18)
	_close_button.size = Vector2(185, 48)
	_close_button.pressed.connect(close_panel)
	UiKit.skin_arcade_button(_close_button, false, false, 20, E5OriginalTheme.MAGENTA)
	_content.add_child(_close_button)

	_daily_column = _build_column("每日任务  3项", Vector2(34, 158), Vector2(790, 720))
	_weekly_column = _build_column("本周任务  5项", Vector2(876, 158), Vector2(790, 720))

	var footer := UiKit.label(_content,
		"正式成绩会自动推进；训练、自动播放和调试成绩不计入。完成后奖励自动入库。",
		18, Vector2(46, 895), Color(0.72, 0.82, 0.95), 1)
	footer.size = Vector2(1500, 30)

func _build_column(column_title: String, pos: Vector2, size: Vector2) -> Control:
	var column := Control.new()
	column.name = "DailyColumn" if column_title.begins_with("每日") else "WeeklyColumn"
	column.position = pos
	column.size = size
	_content.add_child(column)
	UiKit.hud_frame(column, Rect2(Vector2.ZERO, size), column_title.replace(" ", ""),
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 50.0, true, 18.0)
	var label := UiKit.label(column, column_title, 25, Vector2(24, 10),
		Color(1.0, 0.82, 0.30), 2)
	label.size = Vector2(size.x - 48, 38)
	return column

func open_panel() -> void:
	ChallengeService.ensure_current()
	ChallengeService.note_game_opened()
	_refresh()
	_visible_open = true
	visible = true
	_content.modulate.a = 0.0
	_content.position = Vector2(110, 84)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_content, "modulate:a", 1.0, 0.18)
	tween.tween_property(_content, "position", Vector2(110, 66), 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_focus_index = 0
	if not _focus_buttons.is_empty():
		_focus_buttons[0].grab_focus()
	get_viewport().set_input_as_handled()

func _repair_challenges() -> void:
	var result: Dictionary = ChallengeService.repair_current()
	_refresh()
	UiKit.toast(self, str(result.get("message", "挑战校验完成")))


func close_panel() -> void:
	if not _visible_open:
		return
	_visible_open = false
	visible = false
	close_requested.emit()

func is_open() -> bool:
	return _visible_open

func _refresh() -> void:
	var summary: Dictionary = ChallengeService.summary()
	_summary_label.text = "今日 %d/%d    本周 %d/%d    连续活跃 %d 天    已解锁奖励 %d 件" % [
		int(summary.get("daily_completed", 0)), int(summary.get("daily_total", 0)),
		int(summary.get("weekly_completed", 0)), int(summary.get("weekly_total", 0)),
		int(summary.get("streak", 0)), RewardService.owned_rewards().size()]
	_clock_label.text = ChallengeService.clock_guard_message()
	_clock_label.visible = not _clock_label.text.is_empty()
	_focus_buttons.clear()
	if _repair_button != null:
		_focus_buttons.append(_repair_button)
	if _close_button != null:
		_focus_buttons.append(_close_button)
	_clear_task_rows(_daily_column)
	_clear_task_rows(_weekly_column)
	var snapshot: Dictionary = ChallengeService.snapshot()
	_build_task_rows(_daily_column, snapshot.get("daily", []), 3)
	_build_task_rows(_weekly_column, snapshot.get("weekly", []), 5)

func _clear_task_rows(column: Control) -> void:
	for child in column.get_children():
		if str(child.name).begins_with("TaskRow"):
			child.free()

func _build_task_rows(column: Control, raw_tasks: Variant, expected_count: int) -> void:
	var tasks: Array = raw_tasks if raw_tasks is Array else []
	var row_height := 204.0 if expected_count <= 3 else 122.0
	for i in mini(tasks.size(), expected_count):
		if not tasks[i] is Dictionary:
			continue
		_build_task_row(column, tasks[i], i, row_height)

func _build_task_row(column: Control, task: Dictionary, index: int, row_height: float) -> void:
	var row := Control.new()
	row.name = "TaskRow%d" % index
	row.position = Vector2(18, 62 + index * row_height)
	row.size = Vector2(column.size.x - 36, row_height - 10)
	column.add_child(row)
	var completed := bool(task.get("completed", false))
	UiKit.hud_frame(row, Rect2(Vector2.ZERO, row.size), "Frame",
		E5OriginalTheme.MAGENTA if completed else E5OriginalTheme.CYAN,
		E5OriginalTheme.CYAN, 0.0, false, 12.0)

	var difficulty := str(task.get("difficulty", "normal"))
	var badge_text: String = str({"normal": "普通", "advanced": "进阶", "challenge": "挑战"}.get(difficulty, "普通"))
	var title := UiKit.label(row, "%s  %s" % ["✓" if completed else "◆", str(task.get("description", "挑战"))],
		19 if row_height < 150 else 22, Vector2(18, 12),
		Color(0.50, 1.0, 0.65) if completed else Color.WHITE, 2)
	title.size = Vector2(row.size.x - 180, 34)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var badge := UiKit.label(row, badge_text, 17, Vector2(row.size.x - 105, 12),
		Color(1.0, 0.78, 0.28), 1)
	badge.size = Vector2(88, 30)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var progress := float(task.get("progress", 0.0))
	var target := maxf(1.0, float(task.get("target", 1.0)))
	var bar := ProgressBar.new()
	bar.name = "Progress"
	bar.position = Vector2(18, 55 if row_height >= 150 else 48)
	bar.size = Vector2(row.size.x - 230, 24)
	bar.min_value = 0.0
	bar.max_value = target
	bar.value = progress
	bar.show_percentage = false
	UiKit.skin_arcade_progress(bar, E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA)
	row.add_child(bar)
	var progress_label := UiKit.label(row, "%s / %s" % [_format_value(progress), _format_value(target)],
		17, Vector2(row.size.x - 195, bar.position.y - 2), Color(0.85, 0.92, 1.0), 1)
	progress_label.size = Vector2(90, 28)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var reward_id := str(task.get("reward_id", ""))
	var reward_name := RewardService.reward_name(reward_id)
	var reward := UiKit.label(row, "奖励：" + reward_name, 17,
		Vector2(18, 92 if row_height >= 150 else 80), Color(0.95, 0.76, 1.0), 1)
	reward.size = Vector2(row.size.x - 220, 28)
	if completed and RewardService.owns(reward_id):
		var info: Dictionary = RewardService.reward_info(reward_id)
		var slot := str(info.get("slot", ""))
		var equip := Button.new()
		equip.name = "EquipReward"
		equip.text = "已装备" if RewardService.equipped(slot) == reward_id else "装备"
		equip.position = Vector2(row.size.x - 122, 82 if row_height >= 150 else 72)
		equip.size = Vector2(100, 38)
		equip.disabled = RewardService.equipped(slot) == reward_id
		equip.pressed.connect(func():
			RewardService.equip(reward_id)
			_refresh())
		UiKit.skin_arcade_button(equip, equip.disabled, false, 17, E5OriginalTheme.MAGENTA)
		row.add_child(equip)
		if not equip.disabled:
			_focus_buttons.append(equip)

func _format_value(value: float) -> String:
	return "%.1f" % value if not is_equal_approx(value, roundf(value)) else str(int(roundf(value)))

func _unhandled_input(event: InputEvent) -> void:
	if not _visible_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pedal_left") and not _focus_buttons.is_empty():
		_focus_index = (_focus_index - 1 + _focus_buttons.size()) % _focus_buttons.size()
		_focus_buttons[_focus_index].grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pedal_right") and not _focus_buttons.is_empty():
		_focus_index = (_focus_index + 1) % _focus_buttons.size()
		_focus_buttons[_focus_index].grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pedal_confirm") and not _focus_buttons.is_empty():
		_focus_buttons[_focus_index].pressed.emit()
		get_viewport().set_input_as_handled()
