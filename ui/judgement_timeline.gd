class_name JudgementTimeline
extends Control
## 当前对局判定时间轴。只绘制内存事件，不读取或写入玩家存档。

signal window_selected(index: int, window: Dictionary)

var events: Array = []
var problem_windows: Array = []
var chart_duration := 1.0
var selected_window := 0
var animation_enabled := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	queue_redraw()


func setup(source_events: Array, windows: Array, duration: float,
		selected_index := 0, animate := true) -> void:
	events = source_events.duplicate(true)
	problem_windows = windows.duplicate(true)
	chart_duration = maxf(1.0, duration)
	selected_window = clampi(selected_index, 0, maxi(0, problem_windows.size() - 1))
	animation_enabled = animate
	queue_redraw()


func set_selected_window(index: int) -> void:
	if problem_windows.is_empty():
		selected_window = 0
		queue_redraw()
		return
	selected_window = clampi(index, 0, problem_windows.size() - 1)
	queue_redraw()


func _plot_rect() -> Rect2:
	return Rect2(36, 42, maxf(1.0, size.x - 72.0), maxf(1.0, size.y - 92.0))


func _x_for_time(seconds: float) -> float:
	var plot := _plot_rect()
	return plot.position.x + clampf(seconds / chart_duration, 0.0, 1.0) * plot.size.x


func _draw() -> void:
	var plot := _plot_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.025, 0.055, 0.96), true)
	draw_rect(plot, Color(0.025, 0.07, 0.12, 0.96), true)
	draw_rect(plot, Color(0.18, 0.82, 1.0, 0.72), false, 2.0)
	for i in 11:
		var ratio := float(i) / 10.0
		var x := plot.position.x + plot.size.x * ratio
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y),
			Color(0.35, 0.72, 0.92, 0.14), 1.0)
		var total := int(roundf(chart_duration * ratio))
		draw_string(get_theme_default_font(), Vector2(x - 18.0, plot.end.y + 28.0),
			"%d:%02d" % [total / 60, total % 60], HORIZONTAL_ALIGNMENT_LEFT,
			48.0, 14, Color(0.64, 0.83, 0.94))

	for i in problem_windows.size():
		var window: Dictionary = problem_windows[i]
		var x0 := _x_for_time(float(window.get("start_sec", 0.0)))
		var x1 := _x_for_time(float(window.get("end_sec", 0.0)))
		var selected := i == selected_window
		var fill := Color(1.0, 0.26, 0.62, 0.22 if selected else 0.10)
		var border := Color(1.0, 0.72, 0.18, 0.95) if selected else Color(1.0, 0.32, 0.62, 0.60)
		draw_rect(Rect2(x0, plot.position.y, maxf(2.0, x1 - x0), plot.size.y), fill, true)
		draw_rect(Rect2(x0, plot.position.y, maxf(2.0, x1 - x0), plot.size.y), border, false,
			3.0 if selected else 1.5)

	for raw_event in events:
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		if not bool(event.get("scoring", true)):
			continue
		var judge := str(event.get("judge", "perfect"))
		var x := _x_for_time(float(event.get("start_sec", 0.0)))
		var height := 5.0
		var color := Color(0.32, 0.94, 1.0, 0.34)
		match judge:
			"cool":
				height = 18.0
				color = Color(0.25, 0.85, 1.0, 0.80)
			"good":
				height = 34.0
				color = Color(1.0, 0.76, 0.18, 0.92)
			"miss":
				height = 54.0
				color = Color(1.0, 0.20, 0.34, 0.96)
		var lane_ratio := float(int(event.get("track", 0)) % 5) / 4.0
		var base_y := lerpf(plot.end.y - 10.0, plot.position.y + 22.0, lane_ratio)
		draw_line(Vector2(x, base_y), Vector2(x, maxf(plot.position.y, base_y - height)), color,
			2.0 if judge != "perfect" else 1.0)


func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed \
			or event.button_index != MOUSE_BUTTON_LEFT or problem_windows.is_empty():
		return
	var click_x: float = event.position.x
	var best_index := 0
	var best_distance: float = INF
	for i in problem_windows.size():
		var window: Dictionary = problem_windows[i]
		var center := (_x_for_time(float(window.get("start_sec", 0.0))) \
			+ _x_for_time(float(window.get("end_sec", 0.0)))) * 0.5
		var distance := absf(click_x - center)
		if distance < best_distance:
			best_distance = distance
			best_index = i
	set_selected_window(best_index)
	window_selected.emit(best_index, problem_windows[best_index])
	accept_event()
