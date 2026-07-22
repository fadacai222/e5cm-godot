extends SceneTree
## 舞台觉醒 GPU 冒烟基准。非 headless 运行，分别测量冷场与神域全屏层。
## 运行：Godot_v4.6.2-stable_win64_console.exe --path . --script res://tests/benchmark_stage_awakening_gpu_20260722.gd

const SAMPLE_SECONDS := 2.0
var _samples: Array[float] = []


func _initialize() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))

	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.03, 0.04, 0.08, 1.0)
	host.add_child(background)

	var fx = load("res://fx/stage_awakening_fx.gd").new()
	host.add_child(fx)
	await process_frame
	await process_frame

	await _measure_stage(fx, 0, "cold")
	await _measure_stage(fx, 300, "divine")

	var cold := _samples[0] if _samples.size() > 0 else 0.0
	var divine := _samples[1] if _samples.size() > 1 else 0.0
	print("STAGE_AWAKENING_GPU cold=%.1f divine=%.1f ratio=%.3f" % [
		cold, divine, divine / maxf(cold, 1.0)])
	quit(0)


func _measure_stage(fx: Node, combo: int, label: String) -> void:
	fx.call("set_combo", combo, false)
	await create_timer(0.4).timeout
	var frame_count := 0
	var started := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - started) / 1000000.0 < SAMPLE_SECONDS:
		await process_frame
		frame_count += 1
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	var fps := float(frame_count) / maxf(elapsed, 0.001)
	_samples.append(fps)
	print("  GPU_STAGE %s %.1f FPS" % [label, fps])
