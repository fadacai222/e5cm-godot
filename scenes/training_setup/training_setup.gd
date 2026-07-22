extends Control
## 训练设置页：复用现有选歌流程，负责片段、速度和循环次数配置。

const SPEEDS := [0.5, 0.75, 0.9, 1.0]
const LOOPS := [-1, 1, 3, 5, 10]
const REWINDS := [0.0, 3.0, 5.0]
const SEGMENT_STEP_SMALL := 5.0
const SEGMENT_STEP_LARGE := 30.0

var payload := {}
var song := {}
var song_duration := 180.0
var start_sec := 0.0
var end_sec := 180.0
var speed := 1.0
var loop_count := -1
var auto_rewind_sec := 0.0
var metronome := false
var show_timing := true
var _duration_ready := false

var _start_value: Label
var _end_value: Label
var _speed_value: Label
var _loop_value: Label
var _rewind_value: Label
var _metronome_value: Label
var _timing_value: Label
var _status: Label
var _start_button: Button
var _summary_label: Label


func _ready() -> void:
	payload = SceneRouter.take_payload()
	song = payload.get("song", TrainingSession.current_song())
	if not song is Dictionary or song.is_empty():
		TrainingSession.reset_all()
		SceneRouter.change_to("mode_select")
		return
	SharedVideoBackground.continue_sequence()
	AudioDirector.play_bgm(AssetLoader.sound("音乐_UI"))
	_build_ui()
	_apply_returned_config()
	_refresh_values()
	await _resolve_song_duration()


func _build_ui() -> void:
	var bg := TextureRect.new()
	bg.name = "Background"
	bg.texture = AssetLoader.tex_key("背景_选歌")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	TopBar.add(self, "歌曲选择")
	var page_title := UiKit.center_label(self, "训练室  /  PRACTICE LAB", 34, 45,
		Color(0.35, 0.95, 1.0))
	page_title.z_index = 90

	var frame := UiKit.hud_frame(self, Rect2(145, 170, 1630, 805), "TrainingSetupFrame",
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 78.0, true, 24.0)
	frame.z_index = 10

	var header := UiKit.label(self, "训练配置", 30, Vector2(205, 188), Color.WHITE, 3)
	header.z_index = 12
	var warning := UiKit.label(self,
		"训练成绩不会写入最高分、经验、每日任务或联赛记录", 22,
		Vector2(420, 195), Color(1.0, 0.78, 0.28), 2)
	warning.z_index = 12

	_build_song_panel()
	_build_controls()
	_build_actions()
	_build_summary()
	TopBar.add_bottom_credit(self)
	UiKit.animate_arcade_in(frame, Vector2(0, 22), 0.22)


func _build_song_panel() -> void:
	var cover_frame := UiKit.hud_frame(self, Rect2(205, 270, 490, 490), "TrainingCoverFrame",
		E5OriginalTheme.MAGENTA, E5OriginalTheme.CYAN, 0.0, true, 16.0)
	cover_frame.z_index = 11
	var cover := TextureRect.new()
	cover.name = "TrainingCover"
	cover.texture = AssetLoader.tex(str(song.get("cover", "")))
	cover.position = Vector2(225, 290)
	cover.size = Vector2(450, 450)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.z_index = 12
	add_child(cover)

	var title := UiKit.label(self, str(song.get("name", "未知曲目")), 30,
		Vector2(205, 785), Color.WHITE, 3)
	title.size = Vector2(490, 50)
	title.clip_text = true
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.z_index = 12
	var meta := UiKit.label(self, "%s / %s    %d★" % [
		str(song.get("mode", GameState.big_mode)),
		str(song.get("submode", GameState.sub_mode)), int(song.get("star", 0))],
		21, Vector2(205, 835), Color(0.65, 0.9, 1.0), 2)
	meta.size = Vector2(490, 42)
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.z_index = 12

	_status = UiKit.label(self, "正在读取歌曲时长…", 20, Vector2(205, 888),
		Color(0.7, 0.85, 0.95), 2)
	_status.size = Vector2(490, 36)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.z_index = 12


func _build_controls() -> void:
	var x := 780.0
	var y := 275.0
	_start_value = _build_time_row("片段起点", y, x,
		func(): _step_start(-SEGMENT_STEP_LARGE),
		func(): _step_start(-SEGMENT_STEP_SMALL),
		func(): _step_start(SEGMENT_STEP_SMALL),
		func(): _step_start(SEGMENT_STEP_LARGE))
	y += 92.0
	_end_value = _build_time_row("片段终点", y, x,
		func(): _step_end(-SEGMENT_STEP_LARGE),
		func(): _step_end(-SEGMENT_STEP_SMALL),
		func(): _step_end(SEGMENT_STEP_SMALL),
		func(): _step_end(SEGMENT_STEP_LARGE))
	y += 100.0
	_speed_value = _build_cycle_row("播放速度", y, x, func(): _cycle_speed(-1), func(): _cycle_speed(1))
	y += 86.0
	_loop_value = _build_cycle_row("循环次数", y, x, func(): _cycle_loop(-1), func(): _cycle_loop(1))
	y += 86.0
	_rewind_value = _build_cycle_row("失误回退", y, x, func(): _cycle_rewind(-1), func(): _cycle_rewind(1))
	y += 86.0
	_metronome_value = _build_cycle_row("节拍器", y, x, _toggle_metronome, _toggle_metronome)
	y += 86.0
	_timing_value = _build_cycle_row("实时 EARLY/LATE", y, x, _toggle_timing, _toggle_timing)


func _build_time_row(title: String, y: float, x: float, cb0: Callable, cb1: Callable,
		cb2: Callable, cb3: Callable) -> Label:
	_build_row_label(title, Vector2(x, y))
	var value := _value_label(Vector2(x + 290, y), Vector2(240, 58))
	_make_button("-30", Vector2(x + 555, y), Vector2(100, 58), cb0)
	_make_button("-5", Vector2(x + 665, y), Vector2(90, 58), cb1)
	_make_button("+5", Vector2(x + 765, y), Vector2(90, 58), cb2)
	_make_button("+30", Vector2(x + 865, y), Vector2(100, 58), cb3)
	return value


func _build_cycle_row(title: String, y: float, x: float, prev_cb: Callable,
		next_cb: Callable) -> Label:
	_build_row_label(title, Vector2(x, y))
	_make_button("◀", Vector2(x + 290, y), Vector2(82, 58), prev_cb)
	var value := _value_label(Vector2(x + 382, y), Vector2(310, 58))
	_make_button("▶", Vector2(x + 702, y), Vector2(82, 58), next_cb)
	return value


func _build_row_label(text_value: String, pos: Vector2) -> void:
	var label := UiKit.label(self, text_value, 23, pos + Vector2(0, 10), Color.WHITE, 2)
	label.size = Vector2(260, 48)
	label.z_index = 12


func _value_label(pos: Vector2, target_size: Vector2) -> Label:
	var label := UiKit.label(self, "--", 24, pos, Color(0.3, 0.95, 1.0), 2)
	label.size = target_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 12
	return label


func _make_button(text_value: String, pos: Vector2, target_size: Vector2,
		callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = pos
	button.size = target_size
	button.z_index = 12
	button.pressed.connect(callback)
	UiKit.skin_arcade_button(button, false, false, 21)
	add_child(button)
	return button


func _build_actions() -> void:
	var back := _make_button("返回选歌", Vector2(780, 875), Vector2(260, 66), _back_to_song_select)
	UiKit.skin_arcade_button(back, false, false, 23, E5OriginalTheme.MAGENTA)
	_start_button = _make_button("开始训练", Vector2(1290, 875), Vector2(300, 66), _start_training)
	_start_button.name = "StartTrainingButton"
	_start_button.disabled = true
	UiKit.skin_arcade_button(_start_button, true, false, 25, E5OriginalTheme.CYAN)


func _build_summary() -> void:
	_summary_label = UiKit.label(self, "", 19, Vector2(780, 805), Color(0.85, 0.9, 1.0), 2)
	_summary_label.size = Vector2(810, 58)
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.z_index = 12
	var summary: Dictionary = payload.get("summary", TrainingSession.last_summary())
	if summary.is_empty():
		return
	_summary_label.text = "上一轮：P %d  C %d  G %d  M %d    平均偏移 %+.1fms    Early %d / Late %d" % [
		int(summary.get("perfect", 0)), int(summary.get("cool", 0)),
		int(summary.get("good", 0)), int(summary.get("miss", 0)),
		float(summary.get("average_diff_ms", 0.0)), int(summary.get("early_count", 0)),
		int(summary.get("late_count", 0))]


func _apply_returned_config() -> void:
	var returned: Dictionary = payload.get("training_config", {})
	if returned.is_empty():
		return
	start_sec = float(returned.get("start_sec", 0.0))
	end_sec = float(returned.get("end_sec", song_duration))
	speed = float(returned.get("speed", 1.0))
	loop_count = int(returned.get("loop_count", -1))
	auto_rewind_sec = float(returned.get("auto_rewind_sec", 0.0))
	metronome = bool(returned.get("metronome", false))
	show_timing = bool(returned.get("show_timing", true))


func _resolve_song_duration() -> void:
	var stream = song.get("audio_stream")
	if stream is AudioStream and stream.get_length() > 0.0:
		_apply_duration(stream.get_length())
		return
	var mp3_path := str(song.get("mp3", ""))
	if mp3_path.is_empty():
		_apply_duration(song_duration)
		return
	mp3_path = AssetLoader.abs_path(mp3_path)
	var loaded := await AudioDirector.load_song_stream_async(mp3_path)
	if not is_inside_tree():
		return
	if loaded == null or loaded.get_length() <= 0.0:
		_status.text = "无法读取音频时长，将按 3 分钟上限配置；游戏加载时会再次校验"
		_apply_duration(song_duration)
		return
	song["audio_stream"] = loaded
	_apply_duration(loaded.get_length())


func _apply_duration(value: float) -> void:
	var old_duration := song_duration
	song_duration = maxf(0.1, value)
	var minimum_segment := minf(TrainingSession.MIN_SEGMENT_SECONDS, song_duration)
	if end_sec <= 0.0 or is_equal_approx(end_sec, old_duration) or end_sec > song_duration:
		end_sec = song_duration
	start_sec = clampf(start_sec, 0.0, maxf(0.0, song_duration - minimum_segment))
	end_sec = clampf(end_sec, start_sec + minimum_segment, song_duration)
	_duration_ready = true
	_status.text = "歌曲时长 %s · 片段最短 %s" % [
		_format_time(song_duration), "%d 秒" % roundi(minimum_segment)]
	_start_button.disabled = false
	_refresh_values()


func _step_start(delta: float) -> void:
	var minimum_segment := minf(TrainingSession.MIN_SEGMENT_SECONDS, song_duration)
	start_sec = clampf(start_sec + delta, 0.0,
		maxf(0.0, end_sec - minimum_segment))
	_refresh_values()


func _step_end(delta: float) -> void:
	var minimum_segment := minf(TrainingSession.MIN_SEGMENT_SECONDS, song_duration)
	end_sec = clampf(end_sec + delta, start_sec + minimum_segment, song_duration)
	_refresh_values()


func _cycle_speed(direction: int) -> void:
	var index := SPEEDS.find(speed)
	if index < 0:
		index = SPEEDS.size() - 1
	speed = float(SPEEDS[(index + direction + SPEEDS.size()) % SPEEDS.size()])
	_refresh_values()


func _cycle_loop(direction: int) -> void:
	var index := LOOPS.find(loop_count)
	if index < 0:
		index = 0
	loop_count = int(LOOPS[(index + direction + LOOPS.size()) % LOOPS.size()])
	_refresh_values()


func _cycle_rewind(direction: int) -> void:
	var index := REWINDS.find(auto_rewind_sec)
	if index < 0:
		index = 0
	auto_rewind_sec = float(REWINDS[(index + direction + REWINDS.size()) % REWINDS.size()])
	_refresh_values()


func _toggle_metronome() -> void:
	metronome = not metronome
	_refresh_values()


func _toggle_timing() -> void:
	show_timing = not show_timing
	_refresh_values()


func _refresh_values() -> void:
	if _start_value == null:
		return
	_start_value.text = _format_time(start_sec)
	_end_value.text = _format_time(end_sec)
	_speed_value.text = "%d%%%s" % [roundi(speed * 100.0), "（变调）" if speed < 1.0 else ""]
	_loop_value.text = "无限" if loop_count < 0 else "%d 次" % loop_count
	_rewind_value.text = "关闭" if auto_rewind_sec <= 0.0 else "%d 秒" % roundi(auto_rewind_sec)
	_metronome_value.text = "开启" if metronome else "关闭"
	_timing_value.text = "显示" if show_timing else "隐藏"


func _start_training() -> void:
	if not _duration_ready:
		return
	var config := TrainingSession.create_config(song_duration, start_sec, end_sec, speed,
		loop_count, auto_rewind_sec, metronome, show_timing)
	var training_payload := TrainingSession.begin(song, config)
	AudioDirector.stop_bgm()
	SceneRouter.change_to("loading", training_payload)


func _back_to_song_select() -> void:
	TrainingSession.arm_entry()
	AudioDirector.stop_bgm()
	SceneRouter.change_to("song_select", GameState.song_select_restore)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_back_to_song_select()
	elif event.is_action_pressed("ui_accept") and _duration_ready:
		_start_training()


static func _format_time(seconds: float) -> String:
	var total := maxi(0, int(roundf(seconds)))
	return "%d:%02d" % [total / 60, total % 60]
