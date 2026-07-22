class_name JudgementAnalysisPanel
extends Control
## 结算内全屏判定分析覆盖层。关闭后仍停留在同一结算实例，避免重复持久化。

const TimelineScript = preload("res://ui/judgement_timeline.gd")

signal close_requested
signal training_requested(song: Dictionary, config: Dictionary, summary: Dictionary)

var _data := {}
var _summary := {}
var _events: Array = []
var _trend := {}
var _song := {}
var _problem_windows: Array = []
var _selected_window := 0
var _active_tab := "overview"
var _content: Control
var _timeline: Control
var _training_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func open_analysis(data: Dictionary) -> void:
	_data = data.duplicate(true)
	_summary = (_data.get("summary", {}) as Dictionary).duplicate(true)
	_events = (_data.get("events", []) as Array).duplicate(true)
	_trend = (_data.get("trend", {}) as Dictionary).duplicate(true)
	_song = (_data.get("song", {}) as Dictionary).duplicate(true)
	_problem_windows = (_summary.get("worst_windows", []) as Array).duplicate(true)
	_selected_window = clampi(_selected_window, 0, maxi(0, _problem_windows.size() - 1))
	_active_tab = "overview"
	_rebuild()
	visible = true
	UiKit.animate_arcade_in(get_node("AnalysisFrame") as Control, Vector2(0, 18), 0.20)


func close_analysis() -> void:
	if not visible:
		return
	visible = false
	close_requested.emit()


func is_open() -> bool:
	return visible


func _rebuild() -> void:
	for child in get_children():
		child.free()
	var dim := ColorRect.new()
	dim.name = "AnalysisDim"
	dim.color = Color(0, 0, 0, 0.93)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var frame := UiKit.hud_frame(self, Rect2(70, 48, 1780, 984), "AnalysisFrame",
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 86.0, true, 26.0)
	frame.z_index = 2
	var title := UiKit.label(self, "判定分析  /  JUDGEMENT LAB", 32,
		Vector2(118, 68), Color.WHITE, 3)
	title.z_index = 3
	var song_title := UiKit.label(self, str(_song.get("name", "当前曲目")), 21,
		Vector2(620, 76), Color(0.62, 0.91, 1.0), 2)
	song_title.size = Vector2(760, 40)
	song_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	song_title.clip_text = true
	song_title.z_index = 3

	var overview := _button("总览", Vector2(118, 132), Vector2(190, 54), _show_overview)
	overview.name = "OverviewTab"
	var timeline := _button("时间轴", Vector2(320, 132), Vector2(190, 54), _show_timeline)
	timeline.name = "TimelineTab"
	var close := _button("关闭  ESC", Vector2(1570, 72), Vector2(220, 58), close_analysis)
	close.name = "CloseAnalysisButton"
	UiKit.skin_arcade_button(close, false, false, 21, E5OriginalTheme.MAGENTA)
	_training_button = _button("训练所选片段", Vector2(1510, 944), Vector2(280, 58), _request_training)
	_training_button.name = "TrainProblemWindowButton"
	_training_button.disabled = _problem_windows.is_empty() or _song.is_empty()
	UiKit.skin_arcade_button(_training_button, true, false, 21, E5OriginalTheme.CYAN)

	if _active_tab == "timeline":
		_build_timeline_content()
	else:
		_build_overview_content()


func _button(text_value: String, pos: Vector2, target_size: Vector2,
		callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = pos
	button.size = target_size
	button.z_index = 4
	button.pressed.connect(callback)
	UiKit.skin_arcade_button(button, false, false, 20)
	add_child(button)
	return button


func _clear_content() -> void:
	if _content != null and is_instance_valid(_content):
		_content.free()
	_content = null
	_timeline = null


func _show_overview() -> void:
	_active_tab = "overview"
	_clear_content()
	_build_overview_content()


func _show_timeline() -> void:
	_active_tab = "timeline"
	_clear_content()
	_build_timeline_content()


func show_timeline_for_test() -> void:
	_show_timeline()


func _build_overview_content() -> void:
	_content = Control.new()
	_content.name = "OverviewContent"
	_content.position = Vector2(104, 206)
	_content.size = Vector2(1712, 716)
	_content.z_index = 3
	add_child(_content)

	var metrics := UiKit.hud_frame(_content, Rect2(0, 0, 1712, 146), "Metrics",
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 34.0, true, 16.0)
	metrics.z_index = 0
	_metric("平均偏移", "%+.1f ms" % float(_summary.get("average_diff_ms", 0.0)),
		Vector2(34, 48), Color(0.35, 0.95, 1.0))
	_metric("中位数", "%+.1f ms" % float(_summary.get("median_diff_ms", 0.0)),
		Vector2(330, 48), Color(0.72, 0.82, 1.0))
	_metric("稳定性 σ", "%.1f ms" % float(_summary.get("standard_deviation_ms", 0.0)),
		Vector2(626, 48), Color(1.0, 0.80, 0.30))
	_metric("EARLY / LATE", "%d / %d" % [int(_summary.get("early_count", 0)),
		int(_summary.get("late_count", 0))], Vector2(922, 48), Color(0.98, 0.62, 0.92))
	_metric("P / C / G / M", "%d / %d / %d / %d" % [
		int(_summary.get("perfect", 0)), int(_summary.get("cool", 0)),
		int(_summary.get("good", 0)), int(_summary.get("miss", 0))],
		Vector2(1218, 48), Color.WHITE)

	var trend_frame := UiKit.hud_frame(_content, Rect2(0, 164, 1712, 126), "Trend",
		E5OriginalTheme.MAGENTA, E5OriginalTheme.CYAN, 32.0, true, 16.0)
	trend_frame.z_index = 0
	var suggestion: Dictionary = _trend.get("chart_suggestion", {})
	var suggestion_text := "样本不足：至少完成 3 局正式成绩，每局 100 个有效判定"
	var suggestion_color := Color(0.75, 0.82, 0.90)
	if bool(suggestion.get("enough_samples", false)):
		var adjustment := int(suggestion.get("suggested_adjustment_ms", 0))
		if adjustment == 0:
			suggestion_text = "近期判定方向稳定，无需调整偏移 · 置信度 %s" % suggestion.get("confidence", "低")
		else:
			suggestion_text = "%s按趋势：中位数 %+.1fms，可尝试偏移 %s%dms · 置信度 %s" % [
				"提前" if str(suggestion.get("direction", "")) == "early" else "延后",
				float(suggestion.get("median_diff_ms", 0.0)), "+" if adjustment > 0 else "",
				adjustment, str(suggestion.get("confidence", "低"))]
		suggestion_color = Color(1.0, 0.82, 0.26)
	var suggestion_label := UiKit.label(_content, suggestion_text, 23,
		Vector2(34, 206), suggestion_color, 2)
	suggestion_label.size = Vector2(1100, 44)
	var trend_label := UiKit.label(_content,
		"谱面 %d 局   模式 %d 局 (%+.1fms)   全局 %d 局 (%+.1fms)" % [
			int(_trend.get("chart_runs", 0)), int(_trend.get("mode_runs", 0)),
			float(_trend.get("mode_average_diff_ms", 0.0)), int(_trend.get("global_runs", 0)),
			float(_trend.get("global_average_diff_ms", 0.0))],
		20, Vector2(1120, 210), Color(0.64, 0.89, 1.0), 2)
	trend_label.size = Vector2(540, 42)
	trend_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var per_track: Array = _summary.get("per_track", [])
	var player1 := Control.new()
	player1.name = "Player1Tracks"
	player1.position = Vector2(0, 310)
	player1.size = Vector2(842, 390)
	_content.add_child(player1)
	var player2 := Control.new()
	player2.name = "Player2Tracks"
	player2.position = Vector2(870, 310)
	player2.size = Vector2(842, 390)
	_content.add_child(player2)
	_build_track_group(player1, "1P / 左侧轨道", per_track, 0, mini(5, per_track.size()))
	if per_track.size() > 5:
		_build_track_group(player2, "2P / 右侧轨道", per_track, 5, per_track.size())
	else:
		_build_track_group(player2, "轨道稳定性", per_track, 0, per_track.size())


func _metric(caption: String, value: String, pos: Vector2, color: Color) -> void:
	var caption_label := UiKit.label(_content, caption, 17, pos, Color(0.62, 0.78, 0.90), 2)
	caption_label.size = Vector2(270, 28)
	var value_label := UiKit.label(_content, value, 27, pos + Vector2(0, 27), color, 2)
	value_label.size = Vector2(270, 42)


func _build_track_group(parent: Control, title_text: String, per_track: Array,
		start_index: int, end_index: int) -> void:
	var frame := UiKit.hud_frame(parent, Rect2(0, 0, parent.size.x, parent.size.y), "TrackFrame",
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 42.0, true, 14.0)
	frame.z_index = 0
	var title := UiKit.label(parent, title_text, 22, Vector2(24, 8), Color.WHITE, 2)
	title.size = Vector2(parent.size.x - 48, 36)
	for row_index in range(start_index, end_index):
		var item: Dictionary = per_track[row_index]
		var counts: Dictionary = item.get("counts", {})
		var local_row := row_index - start_index
		var y := 58.0 + float(local_row) * 62.0
		var total := maxi(1, int(counts.get("perfect", 0)) + int(counts.get("cool", 0)) \
			+ int(counts.get("good", 0)) + int(counts.get("miss", 0)))
		var quality := clampf(float(int(counts.get("perfect", 0)) \
			+ int(counts.get("cool", 0))) / float(total), 0.0, 1.0)
		var lane := UiKit.label(parent, "轨道 %d" % (row_index + 1), 19,
			Vector2(24, y), Color.WHITE, 2)
		lane.size = Vector2(100, 34)
		var bar_bg := ColorRect.new()
		bar_bg.position = Vector2(132, y + 5)
		bar_bg.size = Vector2(310, 20)
		bar_bg.color = Color(0.04, 0.10, 0.16, 0.95)
		parent.add_child(bar_bg)
		var bar := ColorRect.new()
		bar.position = bar_bg.position
		bar.size = Vector2(bar_bg.size.x * quality, bar_bg.size.y)
		bar.color = Color(0.25, 0.92, 1.0, 0.92).lerp(Color(1.0, 0.28, 0.44, 0.92), 1.0 - quality)
		parent.add_child(bar)
		var counts_label := UiKit.label(parent, "P%d C%d G%d M%d   %+.1fms" % [
			int(counts.get("perfect", 0)), int(counts.get("cool", 0)),
			int(counts.get("good", 0)), int(counts.get("miss", 0)),
			float(item.get("median_diff_ms", 0.0))],
		18, Vector2(466, y), Color(0.74, 0.88, 0.96), 2)
		counts_label.size = Vector2(350, 34)


func _build_timeline_content() -> void:
	_content = Control.new()
	_content.name = "TimelineContent"
	_content.position = Vector2(104, 206)
	_content.size = Vector2(1712, 716)
	_content.z_index = 3
	add_child(_content)
	var duration := maxf(1.0, float(_summary.get("chart_duration", 1.0)))
	_timeline = TimelineScript.new()
	_timeline.name = "JudgementTimeline"
	_timeline.position = Vector2(0, 0)
	_timeline.size = Vector2(1712, 510)
	_timeline.window_selected.connect(_on_window_selected)
	_content.add_child(_timeline)
	_timeline.setup(_events, _problem_windows, duration, _selected_window,
		not SettingsStore.performance_mode)

	var legend := UiKit.label(_content,
		"细线=Perfect  蓝=Cool  黄=Good  红=Miss  金框=当前问题片段",
		18, Vector2(18, 518), Color(0.70, 0.86, 0.96), 2)
	legend.size = Vector2(820, 34)
	var prev := _content_button("◀ 上一问题段", Vector2(18, 570), Vector2(230, 54),
		func(): _select_window(-1))
	prev.disabled = _problem_windows.is_empty()
	var next := _content_button("下一问题段 ▶", Vector2(260, 570), Vector2(230, 54),
		func(): _select_window(1))
	next.disabled = _problem_windows.is_empty()
	_build_problem_labels()


func _content_button(text_value: String, pos: Vector2, target_size: Vector2,
		callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = pos
	button.size = target_size
	button.pressed.connect(callback)
	UiKit.skin_arcade_button(button, false, false, 19)
	_content.add_child(button)
	return button


func _build_problem_labels() -> void:
	for child in _content.get_children():
		if child.name.begins_with("ProblemWindow"):
			child.free()
	if _problem_windows.is_empty():
		var empty := UiKit.label(_content, "本局没有明显的高风险片段", 22,
			Vector2(560, 570), Color(0.48, 0.96, 0.72), 2)
		empty.name = "ProblemWindowEmpty"
		empty.size = Vector2(800, 52)
		return
	var window: Dictionary = _problem_windows[_selected_window]
	var label := UiKit.label(_content,
		"问题片段 %d / %d：%s - %s   风险 %.0f   Miss %d" % [
			_selected_window + 1, _problem_windows.size(),
			_format_time(float(window.get("start_sec", 0.0))),
			_format_time(float(window.get("end_sec", 0.0))),
			float(window.get("loss", 0.0)), int(window.get("miss_count", 0))],
		24, Vector2(560, 570), Color(1.0, 0.80, 0.26), 2)
	label.name = "ProblemWindowLabel"
	label.size = Vector2(1050, 58)


func _on_window_selected(index: int, _window: Dictionary) -> void:
	_selected_window = index
	_build_problem_labels()


func _select_window(direction: int) -> void:
	if _problem_windows.is_empty():
		return
	_selected_window = (_selected_window + direction + _problem_windows.size()) % _problem_windows.size()
	if _timeline != null:
		_timeline.set_selected_window(_selected_window)
	_build_problem_labels()


func problem_window_count_for_test() -> int:
	return _problem_windows.size()


func selected_training_config_for_test() -> Dictionary:
	if _problem_windows.is_empty():
		return {}
	var window: Dictionary = _problem_windows[_selected_window]
	var duration := maxf(0.1, float(_summary.get("chart_duration", 180.0)))
	var start := maxf(0.0, float(window.get("start_sec", 0.0)) - 2.0)
	var end := minf(duration, float(window.get("end_sec", start + 5.0)) + 2.0)
	var config := TrainingSession.create_config(duration, start, end, 1.0, 5, 3.0, false, true)
	config["problem_windows"] = _problem_windows.duplicate(true)
	config["problem_window_index"] = _selected_window
	return config


func _request_training() -> void:
	var config := selected_training_config_for_test()
	if config.is_empty() or _song.is_empty():
		return
	training_requested.emit(_song.duplicate(true), config, _summary.duplicate(true))


func handle_input(event: InputEvent) -> bool:
	if not visible:
		return false
	if event.is_action_pressed("ui_cancel"):
		close_analysis()
		return true
	if event.is_action_pressed("pedal_left") and _active_tab == "timeline":
		_select_window(-1)
		return true
	if event.is_action_pressed("pedal_right") and _active_tab == "timeline":
		_select_window(1)
		return true
	if event.is_action_pressed("pedal_confirm") and _active_tab == "timeline":
		_request_training()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if handle_input(event):
		get_viewport().set_input_as_handled()


static func _format_time(seconds: float) -> String:
	var total := maxi(0, int(roundf(seconds)))
	return "%d:%02d" % [total / 60, total % 60]
