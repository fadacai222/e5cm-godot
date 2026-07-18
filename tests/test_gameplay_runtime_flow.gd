extends SceneTree
## 本轮运行时修复契约：音频单次结束、Stage 轮廓、唱片四档状态和游戏化 ESC 菜单。

const AUTOLOADS := [
	["AssetLoader", "res://autoload/asset_loader.gd"],
	["SettingsStore", "res://autoload/settings_store.gd"],
	["AudioDirector", "res://autoload/audio_director.gd"],
]

var _failures := 0
var _finish_signals := 0
var _created: Array[Node] = []


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _on_music_finished() -> void:
	_finish_signals += 1


func _ellipse_texture(width: int, height: int) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2((width - 1) * 0.5, (height - 1) * 0.5)
	var radius := Vector2(width * 0.46, height * 0.42)
	for y in height:
		for x in width:
			var normalized := Vector2((x - center.x) / radius.x, (y - center.y) / radius.y)
			if normalized.length_squared() <= 1.0:
				image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)


func _initialize() -> void:
	for entry in AUTOLOADS:
		if root.get_node_or_null(entry[0]) == null:
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
			_created.append(node)
	await process_frame
	root.get_node("SettingsStore").persist_enabled = false

	# Conductor：音乐结束只能锁存并通知一次，后续 tick 不能重新 play。
	var player := AudioStreamPlayer.new()
	root.add_child(player)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	wav.data = PackedByteArray([0, 0, 0, 0])
	player.stream = wav
	var conductor := Conductor.new(player)
	root.add_child(conductor)
	conductor.music_finished_playing.connect(_on_music_finished)
	conductor.start(0.0)
	conductor.set("_music_started_once", true)
	conductor.set("_last_chart_time", 0.25)
	conductor.tick()
	conductor.tick()
	_check(_finish_signals == 1 and conductor.has_music_finished(),
		"Conductor 对自然结束只发一次信号且锁存结束状态",
		"signals=%d finished=%s" % [_finish_signals, conductor.has_music_finished()])
	_check(not player.playing, "音乐结束后的后续 tick 不会自动从头重播")

	# SpectrumRing：按透明度轮廓计算每个角度起始半径，而不是固定圆。
	var spectrum := SpectrumRing.new()
	root.add_child(spectrum)
	spectrum.set_edge_texture(_ellipse_texture(80, 52), Vector2(80, 52))
	var radii: PackedFloat32Array = spectrum.get("_edge_radii")
	_check(spectrum.has_edge_profile() and radii.size() == 200,
		"Stage 频谱成功建立 200 条 board alpha 轮廓")
	_check(radii.size() == 200 and radii[50] > radii[0] + 8.0,
		"非圆形素材的横向/纵向贴边半径真实不同",
		"top=%s right=%s" % [radii[0] if radii.size() > 0 else -1, radii[50] if radii.size() > 50 else -1])

	# VinylBg：严格 0/50/100/150 四档，并核对原版主尺寸与无模糊材质。
	var vinyl = load("res://fx/vinyl_bg.gd").new()
	vinyl.position = Vector2(960, 540)
	root.add_child(vinyl)
	vinyl.setup("")
	var record := vinyl.get_node("Record") as Sprite2D
	var machine := vinyl.get_node("MachineTop") as TextureRect
	var astronaut := vinyl.get_node("AstronautLeft") as TextureRect
	var frame := vinyl.get_node("VinylFrame") as TextureRect
	var foot := vinyl.get_node("FootDecoration") as TextureRect
	_check(record != null and record.material == null \
		and absf(record.texture.get_width() * record.scale.x - 419.0) < 1.5,
		"唱片保持约 419px 原版尺寸且未挂模糊材质")
	_check(frame != null and absf(frame.size.x - 1500.0) < 1.0 \
		and foot != null and absf(foot.size.x - 1920.0) < 1.0 \
		and absf(foot.position.x + 960.0) < 1.0,
		"框线保持原尺寸，底部 foot 横向铺满 1920 设计宽度并居中")
	_check(vinyl.has_method("particle_profile_for_test"),
		"唱片背景提供可验收的粒子扩散配置")
	if vinyl.has_method("particle_profile_for_test"):
		var particle_profile: Dictionary = vinyl.call("particle_profile_for_test", 4)
		_check(int(particle_profile.get("count", 0)) >= 300 \
			and float(particle_profile.get("max_distance", 0.0)) >= 1200.0 \
			and float(particle_profile.get("max_core_size", 99.0)) <= 2.4,
			"满档粒子数量增加、扩散覆盖整屏且粒子核心缩小",
			str(particle_profile))
	for sample in [
		{"combo": 49, "state": 1},
		{"combo": 50, "state": 2},
		{"combo": 99, "state": 2},
		{"combo": 100, "state": 3},
		{"combo": 149, "state": 3},
		{"combo": 150, "state": 4},
	]:
		vinyl.on_combo(int(sample["combo"]))
		vinyl.set("_state_transition", 1.0)
		vinyl.call("_apply_motion")
		_check(vinyl.state_for_test() == int(sample["state"]),
			"Combo %d 对应动态背景状态 %d" % [sample["combo"], sample["state"]])
	vinyl.on_combo(50)
	vinyl.set("_state_transition", 1.0)
	vinyl.call("_apply_motion")
	_check(machine.visible and not astronaut.visible and not frame.visible,
		"状态2只展开唱片机/科技线，不提前显示宇航员和框线")
	vinyl.on_combo(150)
	vinyl.set("_state_transition", 1.0)
	vinyl.call("_apply_motion")
	_check(machine.visible and astronaut.visible and frame.visible,
		"状态4完整显示唱片机、宇航员与框线")

	# 游戏内 ESC：提供醒目的 PAUSED 舞台和直接继续入口，同时保留双栏设置能力。
	var esc = load("res://ui/esc_menu.gd").new(true)
	root.add_child(esc)
	await process_frame
	var nav := esc.get_node_or_null("ModernMenu/NavPanel") as Control
	var resume_tab: Button = null
	if nav != null:
		for child in nav.get_children():
			if child is Button and (child as Button).text.contains("继续游戏"):
				resume_tab = child as Button
				break
	_check(nav != null and esc.get_node_or_null("MenuGlowCyan") != null \
		and esc.get_node_or_null("MenuGlowPink") != null,
		"游戏内 ESC 使用青蓝/洋红霓虹暂停舞台而非普通后台遮罩")
	_check(resume_tab != null,
		"游戏内 ESC 提供明确的继续游戏入口且不依赖固定 Tab 索引")

	conductor.stop()
	player.stream = null
	for node in [esc, vinyl, spectrum, conductor, player]:
		if is_instance_valid(node):
			node.queue_free()
	root.get_node("AudioDirector").release_for_shutdown()
	await process_frame
	print("ALL GAMEPLAY RUNTIME FLOW TESTS PASSED" if _failures == 0 else
		"%d GAMEPLAY RUNTIME FLOW TEST(S) FAILED" % _failures)
	quit(_failures)
