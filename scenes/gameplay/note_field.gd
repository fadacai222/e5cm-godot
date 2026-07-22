class_name NoteField
extends Node2D
## 音符轨道渲染器：原版图集皮肤（arrow/key/judge），支持正向/反向卷轴。
## 速度 = 630 px/s × 卷轴倍率（对应旧版 420px/s @720p 基准，等比换算到 1080p）。
## 布局：判定线（receptor）在上方 y=RECEPTOR_Y，未来音符在下方。

const BASE_SPEED := 630.0
const RECEPTOR_Y := 210.0
const REVERSE_RECEPTOR_Y := 870.0
const ARROW_SIZE := 122.0
const HALF_HIDDEN_FADE_DISTANCE := 290.0
const HALF_HIDDEN_CLEAR_DISTANCE := 42.0

## 轨道方向后缀：脚 0=左下 1=左上 2=中 3=右上 4=右下
const ARROW_SUFFIX := ["lb", "lt", "cc", "rt", "rb"]   # arrow_body_* 用
const KEY_SUFFIX := ["bl", "tl", "cc", "tr", "br"]     # key_* 用（判定区命名不同）

var track_count := 5
var scroll_speed_mult := 4.0
var lane_width := 132.0
var field_center_x := 960.0
var _bpm_scroll_enabled := false
var _bpm_timeline: Array = []
var _bpm_offset := 0.0
var _bpm_base := 120.0

var _arrow_atlas := {}
var _key_atlas := {}
var _key_atlas_p2 := {}
var _judge_atlas := {}
var _fx_atlas := {}
var _fx_groups := {}             # "hand"/"lb"/"lt"/"cc" -> Array[AtlasTexture]
var _fx_groups_p2 := {}
var _couple_mode := false
var _direction_indices: Array[int] = [0, 1, 2, 3, 4]

# 每轨道状态
var _lane_x: Array = []
var _receptors: Array = []       # Sprite2D
var _receptor_flash: Array = []  # 按下高亮计时
var _hand_receptors: Array = []  # 手键装饰判定区（每区 ll/rr 两个）

# 音符渲染项（活动中）
var _render_notes: Array = []    # {note_idx, track, start_sec, end_sec, type, head:Sprite2D, body:Sprite2D, tail:Sprite2D, done}
var _render_hand_notes: Array = [] # 装饰手键 tap/hold；只播放，不进入 Judge/Score/HP/Combo
var _judged_heads := {}          # note_idx -> true（tap 命中后隐藏）
var _hold_active := {}           # note_idx -> true（hold 头命中，身体吸附判定线）
var _note_pool: Array = []
const HOLD_TILE_HEIGHT_STEP := 32
const HOLD_TILE_CACHE_LIMIT := 96
var _hold_tile_cache := {}       # "suffix:width:quantized_height" -> ImageTexture
var _hold_tile_cache_order: Array[String] = []
var _hand_pressed := {}          # "zone:side" -> bool
var _active_hand_effects: Array[FrameAnim] = []
var _visual_paused := false
var _heavy_effects_enabled := true
const COMBO_GOLD_MAX_LEVEL := 3
const COMBO_LANE_TOP_Y := 110.0
# 故意延伸到 1080p 画布外 12px，避免缩放/裁切时底部露出空缝。
const COMBO_LANE_BOTTOM_Y := 1092.0

var _combo_gold_fx_enabled := false
var _combo_arrow_overlay_enabled := true
var _combo_lane_fx_enabled := false
var _combo_gold_fx_level := 0
var _combo_gold_fx_elapsed := 0.0
var _combo_gold_fx_visibility := 1.0
var _combo_gold_material: ShaderMaterial
var _combo_lane_fx_root: Node2D
var _combo_lane_glow_lines: Array[Line2D] = []
var _combo_lane_core_lines: Array[Line2D] = []
var _combo_lane_flow_lines: Array[Line2D] = []
var _combo_lane_flow_materials: Array[ShaderMaterial] = []
var _combo_lane_outline_count := 0
var _combo_lane_particles: Array[GPUParticles2D] = []
var _combo_lane_particle_texture: Texture2D
var _combo_lane_particle_ramp: GradientTexture1D

# 判定弹字
var _judge_popups: Array = []    # {sprite, t}
var _zone_timing_labels := {}    # zone -> Label
var _timing_popups: Array = []   # {label, t}

var _grayscale := false


func setup(p_track_count: int, p_speed_mult: float, p_couple_mode := false) -> void:
	track_count = p_track_count
	scroll_speed_mult = p_speed_mult
	_couple_mode = p_couple_mode
	if _couple_mode:
		_arrow_atlas = AssetLoader.couple_arrow_atlas()
		_key_atlas = AssetLoader.couple_key_atlas(1)
		_key_atlas_p2 = AssetLoader.couple_key_atlas(2)
		_judge_atlas = AssetLoader.couple_judge_atlas()
		_fx_atlas = AssetLoader.couple_key_effect_atlas(1)
		_fx_groups = _build_fx_groups_from_atlas(_fx_atlas)
		_fx_groups_p2 = _build_fx_groups_from_atlas(AssetLoader.couple_key_effect_atlas(2))
	else:
		_arrow_atlas = AssetLoader.arrow_atlas()
		_key_atlas = AssetLoader.key_atlas()
		_key_atlas_p2 = _key_atlas
		_judge_atlas = AssetLoader.judge_atlas()
		_fx_atlas = AssetLoader.key_effect_atlas()
		_fx_groups = _build_fx_groups_from_atlas(_fx_atlas)
		_fx_groups_p2 = _fx_groups
	# 原版“反向”只改变卷轴方向和判定线位置，不重排五键贴图。
	_direction_indices = [0, 1, 2, 3, 4]

	# 原版 1920×1080 轨道指标：目标箭头约 142px、中心间距 142px、槽宽约 160px。
	# 双踏板两区中缝 220px，精确中心为：
	# 左 [202,344,486,628,770] / 右 [1150,1292,1434,1576,1718]。
	_lane_x.clear()
	lane_width = 150.0
	var spacing := 142.0
	if track_count >= 10:
		for x in [202.0, 344.0, 486.0, 628.0, 770.0,
			1150.0, 1292.0, 1434.0, 1576.0, 1718.0]:
			_lane_x.append(x)
	else:
		var start_x := 960.0 - spacing * float(track_count - 1) * 0.5
		for i in track_count:
			_lane_x.append(start_x + float(i) * spacing)

	for r in _receptors:
		r.queue_free()
	for r in _hand_receptors:
		r.queue_free()
	_receptors.clear()
	_receptor_flash.clear()
	_hand_receptors.clear()
	for i in track_count:
		var spr := Sprite2D.new()
		var track_key_atlas: Dictionary = _key_atlas_p2 if _couple_mode and i >= 5 else _key_atlas
		var tex = track_key_atlas.get("key_%s" % KEY_SUFFIX[_direction_indices[i % 5]])
		spr.texture = tex
		spr.position = Vector2(_lane_x[i], _receptor_y())
		var s := _note_scale()
		spr.scale = Vector2(s, s)
		spr.modulate = Color(1, 1, 1, 0.85)
		spr.z_index = 10
		add_child(spr)
		_receptors.append(spr)
		_receptor_flash.append(0.0)

	# 手键装饰判定区：每区左右两侧 key_ll / key_rr（原版布局：位于轨道 0 左侧 / 轨道 4 右侧）
	var zones := 2 if track_count >= 10 else 1
	for z in zones:
		var base := z * 5
		var hand_spacing := lane_width
		var zone_key_atlas: Dictionary = _key_atlas_p2 if _couple_mode and z >= 1 else _key_atlas
		for pair in [["key_ll", float(_lane_x[base]) - hand_spacing], ["key_rr", float(_lane_x[base + 4]) + hand_spacing]]:
			var hs := Sprite2D.new()
			hs.texture = zone_key_atlas.get(str(pair[0]))
			hs.position = Vector2(float(pair[1]), _receptor_y())
			var s2 := _note_scale() * 0.9
			hs.scale = Vector2(s2, s2)
			hs.modulate = Color(1, 1, 1, 0.6)
			hs.z_index = 10
			add_child(hs)
			_hand_receptors.append(hs)
	_rebuild_combo_lane_fx()
	_apply_combo_gold_to_current_sprites()


func configure_bpm_scroll(bpms: Array, timeline: Array, offset: float) -> void:
	_bpm_scroll_enabled = false
	_bpm_timeline = timeline.duplicate(true)
	_bpm_offset = offset if is_finite(offset) else 0.0
	_bpm_base = 120.0
	for raw_entry in bpms:
		if raw_entry is Array and raw_entry.size() >= 2:
			var bpm := float(raw_entry[1])
			if is_finite(bpm) and bpm > 0.0:
				_bpm_base = bpm
				break
	_bpm_scroll_enabled = not _bpm_timeline.is_empty() and _bpm_base > 0.0


func clear_bpm_scroll() -> void:
	_bpm_scroll_enabled = false
	_bpm_timeline.clear()
	_bpm_offset = 0.0
	_bpm_base = 120.0


func bpm_scroll_enabled_for_test() -> bool:
	return _bpm_scroll_enabled


func _player_for_track(track: int) -> int:
	return 2 if _couple_mode and track >= 5 else 1


func _arrow_prefix_candidates(player: int) -> Array:
	if not _couple_mode:
		return ["arrow"]
	# 与原版一致：1P 优先 larrow，2P 优先 rarrow；保留普通/异色兜底，
	# 避免不完整皮肤再次把音符纹理解析成 null。
	return ["rarrow", "arrow", "larrow"] if player >= 2 else \
		["larrow", "arrow", "rarrow"]


func _arrow_texture(kind: String, suffix: String, player := 1) -> Texture2D:
	for prefix in _arrow_prefix_candidates(player):
		var texture = _arrow_atlas.get("%s_%s_%s" % [prefix, kind, suffix])
		if texture is Texture2D:
			return texture as Texture2D
	return null


## key_effect 帧分组：数字前缀升序前4组 = hand / lb / lt / cc（对应旧 击中特效序列帧.py）
## 历史皮肤同时存在 4 位和 5 位以上帧编号，不能写死位数。
func _build_fx_groups_from_atlas(source_atlas: Dictionary) -> Dictionary:
	var groups := {}
	var prefixes := {}
	for name in source_atlas.keys():
		var text := str(name)
		if not text.ends_with(".png"):
			continue
		var re := RegEx.new()
		re.compile("^(.*)_(\\d+)\\.png$")
		var m := re.search(text)
		if m == null:
			continue
		var prefix := m.get_string(1)
		if not prefixes.has(prefix):
			prefixes[prefix] = []
		prefixes[prefix].append([int(m.get_string(2)), source_atlas[name]])
	var sorted_prefixes := prefixes.keys()
	sorted_prefixes.sort()
	var roles := ["hand", "lb", "lt", "cc"]
	for i in mini(roles.size(), sorted_prefixes.size()):
		var frames: Array = prefixes[sorted_prefixes[i]]
		frames.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
		var texs := []
		for f in frames:
			texs.append(f[1])
		groups[roles[i]] = texs
	return groups


## 轨道→特效组与翻转（旧 轨道到击中序列 规则；轨道为区内 0~4）
func _fx_for_lane(lane5: int, groups: Dictionary) -> Array:
	match lane5:
		0: return [groups.get("lb", []), false]
		1: return [groups.get("lt", []), false]
		2: return [groups.get("cc", []), false]
		3: return [groups.get("lt", []), true]
		4: return [groups.get("lb", []), true]
	return [groups.get("cc", []), false]


func _is_reverse() -> bool:
	return SettingsStore.direction_mode == "反向"


func _receptor_y() -> float:
	return REVERSE_RECEPTOR_Y if _is_reverse() else RECEPTOR_Y


func _scroll_y(event_sec: float, chart_time: float, speed: float) -> float:
	var direction := -1.0 if _is_reverse() else 1.0
	return _receptor_y() + (event_sec - chart_time) * speed * direction


func _scroll_y_event(event_sec: float, event_beat: float,
		chart_time: float, speed: float) -> float:
	if not _bpm_scroll_enabled or not is_finite(event_beat):
		return _scroll_y(event_sec, chart_time, speed)
	var current_beat := SmParser.sec_to_beat(chart_time + _bpm_offset, _bpm_timeline)
	if not is_finite(current_beat):
		return _scroll_y(event_sec, chart_time, speed)
	var pixels_per_beat := speed * 60.0 / maxf(0.001, _bpm_base)
	var direction := -1.0 if _is_reverse() else 1.0
	return _receptor_y() + (event_beat - current_beat) * pixels_per_beat * direction


func _visual_x(base_x: float, chart_time: float, event_sec: float, lane: int) -> float:
	if SettingsStore.track_mode != "摇摆" or SettingsStore.performance_mode:
		return base_x
	var amplitude := minf(lane_width * 0.28, 34.0)
	var phase := chart_time * TAU * 2.05 + event_sec * 0.55 + float(lane % 5) * 0.72
	return base_x + sin(phase) * amplitude + sin(phase * 0.52 + float(lane) * 0.35) * amplitude * 0.22


func _visual_rotation(chart_time: float, event_sec: float, lane: int) -> float:
	if SettingsStore.track_mode != "旋转" or SettingsStore.performance_mode:
		return 0.0
	return deg_to_rad(fposmod(chart_time * 360.0 * 1.25 + event_sec * 140.0 + float(lane % 5) * 35.0, 360.0))


func _visual_alpha(y: float) -> float:
	match SettingsStore.hidden_mode:
		"全隐":
			return 0.0
		"半隐":
			var distance := absf(y - _receptor_y())
			return smoothstep(HALF_HIDDEN_CLEAR_DISTANCE, HALF_HIDDEN_FADE_DISTANCE, distance)
	return 1.0


func receptor_y_for_test() -> float:
	return _receptor_y()


func scroll_y_for_test(event_sec: float, chart_time: float, speed: float) -> float:
	return _scroll_y(event_sec, chart_time, speed)


func scroll_y_for_event_test(event_sec: float, event_beat: float,
		chart_time: float, speed: float) -> float:
	return _scroll_y_event(event_sec, event_beat, chart_time, speed)


func note_visual_for_test(base_x: float, y: float, chart_time: float,
		event_sec: float, lane: int) -> Dictionary:
	return {"x": _visual_x(base_x, chart_time, event_sec, lane),
		"rotation": _visual_rotation(chart_time, event_sec, lane), "alpha": _visual_alpha(y)}


func combo_fx_track_rect() -> Rect2:
	if _lane_x.is_empty():
		return Rect2(600, 120, 720, 820)
	var left := float(_lane_x[0]) - lane_width * 0.62
	var right := float(_lane_x[_lane_x.size() - 1]) + lane_width * 0.62
	return Rect2(left, COMBO_LANE_TOP_Y, maxf(160.0, right - left),
		COMBO_LANE_BOTTOM_Y - COMBO_LANE_TOP_Y)


func _ensure_combo_gold_material() -> void:
	if _combo_gold_material != null:
		return
	var shader := load("res://fx/gold_combo_outline.gdshader") as Shader
	if shader == null:
		return
	_combo_gold_material = ShaderMaterial.new()
	_combo_gold_material.shader = shader
	_combo_gold_material.set_shader_parameter("fx_time", 0.0)
	_combo_gold_material.set_shader_parameter("fx_strength", 1.38)
	_combo_gold_material.set_shader_parameter("outline_pixels", 3.4)
	_combo_gold_material.set_shader_parameter("gold_fill", 0.16)
	_combo_gold_material.set_shader_parameter("spark_density", 0.38)
	_combo_gold_material.set_shader_parameter("fx_visibility", _combo_gold_fx_visibility)


func _combo_lane_centers() -> Array[float]:
	var centers: Array[float] = []
	var zones := 2 if track_count >= 10 else 1
	for zone in zones:
		var base := zone * 5
		if _lane_x.size() < base + 5:
			continue
		centers.append(float(_lane_x[base]) - lane_width)
		for lane in 5:
			centers.append(float(_lane_x[base + lane]))
		centers.append(float(_lane_x[base + 4]) + lane_width)
	return centers


func _combo_lane_particle_tex() -> Texture2D:
	if _combo_lane_particle_texture != null:
		return _combo_lane_particle_texture
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24:
			var distance := Vector2(float(x) - 11.5, float(y) - 11.5).length() / 11.5
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), 2.55)
			var hot_core := pow(clampf(1.0 - distance * 1.7, 0.0, 1.0), 2.0)
			var rgb := Color(1.0, 0.82, 0.08).lerp(Color(1.0, 1.0, 0.94), hot_core)
			image.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, alpha))
	_combo_lane_particle_texture = ImageTexture.create_from_image(image)
	return _combo_lane_particle_texture


func _combo_lane_particle_color_ramp() -> GradientTexture1D:
	if _combo_lane_particle_ramp != null:
		return _combo_lane_particle_ramp
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.50, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.38, 1.30, 0.86, 0.0),
		Color(1.32, 1.22, 0.66, 1.0),
		Color(1.18, 0.90, 0.10, 0.96),
		Color(1.0, 0.50, 0.008, 0.72),
		Color(1.0, 0.24, 0.0, 0.0),
	])
	_combo_lane_particle_ramp = GradientTexture1D.new()
	_combo_lane_particle_ramp.gradient = gradient
	return _combo_lane_particle_ramp


func _combo_lane_gradient(alpha: float, hot_core := false) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.10, 0.34, 0.52, 0.72, 0.91, 1.0])
	if hot_core:
		gradient.colors = PackedColorArray([
			Color(1.0, 0.58, 0.0, 0.0),
			Color(1.0, 0.82, 0.08, alpha * 0.52),
			Color(1.28, 1.14, 0.48, alpha * 0.88),
			Color(1.55, 1.48, 1.10, alpha),
			Color(1.18, 0.92, 0.10, alpha * 0.90),
			Color(1.0, 0.52, 0.005, alpha * 0.38),
			Color(1.0, 0.30, 0.0, 0.0),
		])
	else:
		gradient.colors = PackedColorArray([
			Color(1.0, 0.35, 0.0, 0.0),
			Color(1.0, 0.56, 0.01, alpha * 0.30),
			Color(1.12, 0.82, 0.05, alpha * 0.60),
			Color(1.32, 1.12, 0.40, alpha),
			Color(1.02, 0.68, 0.02, alpha * 0.68),
			Color(1.0, 0.42, 0.0, alpha * 0.24),
			Color(1.0, 0.22, 0.0, 0.0),
		])
	return gradient


func _free_combo_lane_fx() -> void:
	if is_instance_valid(_combo_lane_fx_root):
		remove_child(_combo_lane_fx_root)
		_combo_lane_fx_root.free()
	_combo_lane_fx_root = null
	_combo_lane_glow_lines.clear()
	_combo_lane_core_lines.clear()
	_combo_lane_flow_lines.clear()
	_combo_lane_flow_materials.clear()
	_combo_lane_particles.clear()
	_combo_lane_outline_count = 0


func _create_combo_lane_edge(parent: Node2D, x: float, flow_shader: Shader,
		phase: float) -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	# 仅绘制轨道边缘：宽幅外光晕负责炫光，轨道本体始终保持透明。
	var glow_line := Line2D.new()
	glow_line.name = "GoldEdgeGlow"
	glow_line.width = 11.0
	glow_line.antialiased = true
	glow_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	glow_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	glow_line.points = PackedVector2Array([
		Vector2(x, COMBO_LANE_TOP_Y), Vector2(x, COMBO_LANE_BOTTOM_Y),
	])
	glow_line.gradient = _combo_lane_gradient(0.24)
	glow_line.material = additive
	glow_line.z_index = 0
	parent.add_child(glow_line)
	_combo_lane_glow_lines.append(glow_line)

	# 白热核心线提供清晰描边，不给轨道内部铺任何颜色。
	var core_line := Line2D.new()
	core_line.name = "GoldEdgeCore"
	core_line.width = 2.8
	core_line.antialiased = true
	core_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	core_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	core_line.points = glow_line.points
	core_line.gradient = _combo_lane_gradient(0.90, true)
	core_line.material = additive
	core_line.z_index = 1
	parent.add_child(core_line)
	_combo_lane_core_lines.append(core_line)

	# 短段白金流光沿着描边高速向下移动；用几何段移动，避免重新照亮轨道本体。
	var flow_line := Line2D.new()
	flow_line.name = "GoldEdgeFlow"
	flow_line.width = 7.0
	flow_line.antialiased = true
	flow_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	flow_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	flow_line.points = PackedVector2Array([
		Vector2(x, COMBO_LANE_TOP_Y), Vector2(x, COMBO_LANE_TOP_Y + 120.0),
	])
	flow_line.gradient = _combo_lane_gradient(1.0, true)
	flow_line.z_index = 2
	if flow_shader != null:
		var flow_material := ShaderMaterial.new()
		flow_material.shader = flow_shader
		flow_material.set_shader_parameter("fx_time", 0.0)
		flow_material.set_shader_parameter("intensity", 1.0)
		flow_material.set_shader_parameter("lane_phase", phase)
		flow_line.material = flow_material
		_combo_lane_flow_materials.append(flow_material)
	else:
		flow_line.material = additive
	parent.add_child(flow_line)
	_combo_lane_flow_lines.append(flow_line)

	var particles := GPUParticles2D.new()
	particles.name = "GoldEdgeParticles"
	particles.position = Vector2(x, (COMBO_LANE_TOP_Y + COMBO_LANE_BOTTOM_Y) * 0.5)
	particles.amount = 30
	particles.lifetime = 1.32
	particles.randomness = 0.86
	particles.texture = _combo_lane_particle_tex()
	var lane_height := COMBO_LANE_BOTTOM_Y - COMBO_LANE_TOP_Y
	particles.visibility_rect = Rect2(-48.0, -lane_height * 0.5 - 64.0,
		96.0, lane_height + 128.0)
	particles.draw_order = GPUParticles2D.DRAW_ORDER_LIFETIME
	particles.fixed_fps = 30
	particles.interpolate = true
	particles.emitting = false
	particles.z_index = 3
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(3.2, lane_height * 0.5, 0.0)
	material.direction = Vector3(0.0, -1.0, 0.0)
	material.spread = 7.0
	material.initial_velocity_min = 74.0
	material.initial_velocity_max = 188.0
	material.gravity = Vector3(0.0, -14.0, 0.0)
	material.damping_min = 2.0
	material.damping_max = 8.0
	material.scale_min = 0.20
	material.scale_max = 0.82
	material.angular_velocity_min = -72.0
	material.angular_velocity_max = 72.0
	material.color = Color(1.24, 1.10, 0.42, 1.0)
	material.color_ramp = _combo_lane_particle_color_ramp()
	particles.process_material = material
	particles.material = additive
	parent.add_child(particles)
	_combo_lane_particles.append(particles)


func _rebuild_combo_lane_fx() -> void:
	_free_combo_lane_fx()
	_combo_lane_fx_root = Node2D.new()
	_combo_lane_fx_root.name = "ComboGoldLaneFx"
	_combo_lane_fx_root.z_index = 2
	_combo_lane_fx_root.visible = false
	add_child(_combo_lane_fx_root)
	var half_width := lane_width * 0.39
	var centers := _combo_lane_centers()
	_combo_lane_outline_count = centers.size()
	var flow_shader := load("res://fx/gold_lane_flow.gdshader") as Shader
	var edge_index := 0
	var edge_count := maxi(1, centers.size() * 2)
	for center_value in centers:
		var center := float(center_value)
		_create_combo_lane_edge(_combo_lane_fx_root, center - half_width, flow_shader,
			float(edge_index) / float(edge_count))
		edge_index += 1
		_create_combo_lane_edge(_combo_lane_fx_root, center + half_width, flow_shader,
			float(edge_index) / float(edge_count))
		edge_index += 1
	_update_combo_lane_fx_style()


func _update_combo_lane_fx_style() -> void:
	if not is_instance_valid(_combo_lane_fx_root):
		return
	var enabled := _heavy_effects_enabled and _combo_gold_fx_enabled \
		and _combo_lane_fx_enabled and _combo_gold_fx_level > 0
	_combo_lane_fx_root.visible = enabled
	var progress := clampf(float(maxi(1, _combo_gold_fx_level) - 1) / 2.0, 0.0, 1.0)

	for line in _combo_lane_glow_lines:
		line.width = lerpf(11.0, 17.0, progress)
		line.gradient = _combo_lane_gradient(lerpf(0.24, 0.44, progress))
	for line in _combo_lane_core_lines:
		line.width = lerpf(2.8, 4.8, progress)
		line.gradient = _combo_lane_gradient(lerpf(0.88, 1.0, progress), true)
	for line in _combo_lane_flow_lines:
		line.width = lerpf(6.5, 9.5, progress)
		line.gradient = _combo_lane_gradient(1.0, true)
	for flow_material in _combo_lane_flow_materials:
		flow_material.set_shader_parameter("intensity", lerpf(1.05, 1.78, progress))

	for particles in _combo_lane_particles:
		particles.amount = roundi(lerpf(30.0, 58.0, progress)) \
			if not SettingsStore.performance_mode else roundi(lerpf(18.0, 34.0, progress))
		particles.speed_scale = lerpf(1.0, 1.24, progress)
		var material := particles.process_material as ParticleProcessMaterial
		if material != null:
			material.initial_velocity_min = lerpf(74.0, 108.0, progress)
			material.initial_velocity_max = lerpf(188.0, 286.0, progress)
			material.scale_min = lerpf(0.20, 0.26, progress)
			material.scale_max = lerpf(0.82, 1.18, progress)
			material.color = Color(lerpf(1.24, 1.42, progress),
				lerpf(1.10, 1.34, progress), lerpf(0.42, 0.76, progress), 1.0)
		particles.emitting = enabled
		if enabled:
			particles.restart()
	_combo_lane_fx_root.modulate = Color(1.0, 1.0, 1.0, _combo_gold_fx_visibility)


func combo_lane_fx_count_for_test() -> int:
	return _combo_lane_outline_count


func combo_lane_particle_system_count_for_test() -> int:
	return _combo_lane_particles.size()


func combo_lane_fx_visible_for_test() -> bool:
	return is_instance_valid(_combo_lane_fx_root) and _combo_lane_fx_root.visible


func combo_lane_flow_material_count_for_test() -> int:
	return _combo_lane_flow_materials.size()


func combo_lane_flow_line_count_for_test() -> int:
	return _combo_lane_flow_lines.size()


func combo_lane_body_fill_count_for_test() -> int:
	# 实际扫描节点，防止未来误把 Polygon2D 轨道面重新加回来。
	if not is_instance_valid(_combo_lane_fx_root):
		return 0
	var count := 0
	for child in _combo_lane_fx_root.get_children():
		if child is Polygon2D:
			count += 1
	return count


func combo_lane_edge_bottom_for_test() -> float:
	var bottom := 0.0
	for line in _combo_lane_glow_lines:
		if not line.points.is_empty():
			bottom = maxf(bottom, line.points[line.points.size() - 1].y)
	return bottom


func combo_lane_glow_line_count_for_test() -> int:
	return _combo_lane_glow_lines.size() + _combo_lane_core_lines.size()


func combo_lane_peak_particle_amount_for_test() -> int:
	var peak := 0
	for particles in _combo_lane_particles:
		peak = maxi(peak, particles.amount)
	return peak


func combo_lane_flow_intensity_for_test() -> float:
	if _combo_lane_flow_materials.is_empty():
		return 0.0
	return float(_combo_lane_flow_materials[0].get_shader_parameter("intensity"))


## 兼容旧调用；显式启用时沿用旧行为，同时打开箭头与轨道层。
## Gameplay 的 50/100 阶梯逻辑使用两个独立 setter，不走此兼容入口。
func set_combo_gold_fx_enabled(enabled: bool, _duration := 0.0) -> void:
	_combo_arrow_overlay_enabled = enabled
	set_combo_gold_fx_level(1 if enabled else 0)
	set_combo_lane_fx_enabled(enabled)


func set_heavy_effects_enabled(enabled: bool) -> void:
	if _heavy_effects_enabled == enabled:
		return
	_heavy_effects_enabled = enabled
	if enabled:
		return
	set_combo_gold_fx_level(0)
	set_combo_lane_fx_enabled(false)
	for item in _render_hand_notes:
		item["active_effect"] = null
	for child in get_children():
		if child is FrameAnim:
			var anim := child as FrameAnim
			anim.auto_free = false
			anim.stop()
			anim.queue_free()
	_active_hand_effects.clear()
	_hand_pressed.clear()


func heavy_effects_enabled_for_test() -> bool:
	return _heavy_effects_enabled


func set_combo_gold_fx_level(level: int) -> void:
	var next_level := clampi(level, 0, COMBO_GOLD_MAX_LEVEL) if _heavy_effects_enabled else 0
	var was_enabled := _combo_gold_fx_enabled
	_combo_gold_fx_level = next_level
	_combo_gold_fx_enabled = next_level > 0
	if not _combo_gold_fx_enabled:
		_combo_lane_fx_enabled = false
	if _combo_gold_fx_enabled:
		if not was_enabled:
			_combo_gold_fx_elapsed = 0.0
			_combo_gold_fx_visibility = 1.0
		_ensure_combo_gold_material()
		if _combo_gold_material != null:
			_combo_gold_material.set_shader_parameter("fx_visibility", _combo_gold_fx_visibility)
			# 保留原来 100/200/300 Combo 的强度，300 后不再继续变亮变粗。
			var progress := clampf(float(next_level - 1) / 2.0, 0.0, 1.0)
			_combo_gold_material.set_shader_parameter("fx_strength", lerpf(1.38, 2.10, progress))
			_combo_gold_material.set_shader_parameter("outline_pixels", lerpf(3.4, 5.0, progress))
			_combo_gold_material.set_shader_parameter("gold_fill", lerpf(0.16, 0.48, progress))
			_combo_gold_material.set_shader_parameter("spark_density", lerpf(0.38, 0.62, progress))
	_update_combo_lane_fx_style()
	_apply_combo_gold_to_current_sprites()


func set_combo_arrow_overlay_enabled(enabled: bool) -> void:
	_combo_arrow_overlay_enabled = _heavy_effects_enabled and enabled
	_apply_combo_gold_to_current_sprites()


func combo_arrow_overlay_enabled_for_test() -> bool:
	return _combo_arrow_overlay_enabled


func set_combo_lane_fx_enabled(enabled: bool) -> void:
	_combo_lane_fx_enabled = _heavy_effects_enabled and enabled \
		and _combo_gold_fx_enabled and _combo_gold_fx_level > 0
	_update_combo_lane_fx_style()


func is_combo_gold_fx_enabled() -> bool:
	return _combo_gold_fx_enabled and _combo_arrow_overlay_enabled


func is_combo_lane_fx_enabled() -> bool:
	return _combo_lane_fx_enabled


func combo_gold_fx_level_for_test() -> int:
	return _combo_gold_fx_level


func set_combo_gold_fx_visibility(value: float) -> void:
	_combo_gold_fx_visibility = clampf(value, 0.0, 1.0)
	if _combo_gold_material != null:
		_combo_gold_material.set_shader_parameter("fx_visibility", _combo_gold_fx_visibility)
	if is_instance_valid(_combo_lane_fx_root):
		_combo_lane_fx_root.modulate.a = _combo_gold_fx_visibility


func combo_gold_fx_visibility_for_test() -> float:
	return _combo_gold_fx_visibility


func _update_combo_gold_fx(delta: float) -> void:
	if not _combo_gold_fx_enabled or _visual_paused:
		return
	_combo_gold_fx_elapsed += delta
	if _combo_gold_material != null:
		_combo_gold_material.set_shader_parameter("fx_time", _combo_gold_fx_elapsed)
	for flow_material in _combo_lane_flow_materials:
		flow_material.set_shader_parameter("fx_time", _combo_gold_fx_elapsed)
	if is_instance_valid(_combo_lane_fx_root):
		var level_progress := clampf(float(maxi(1, _combo_gold_fx_level) - 1) / 2.0,
			0.0, 1.0)
		var pulse := 0.95 + sin(_combo_gold_fx_elapsed * TAU * 1.45) * 0.05
		var flash := pow(maxf(0.0, sin(_combo_gold_fx_elapsed * TAU * 2.8)), 18.0)
		_combo_lane_fx_root.modulate = Color(1.0 + flash * 0.16,
			1.0 + flash * 0.12, 1.0 + flash * 0.035,
			pulse * _combo_gold_fx_visibility)
		for i in _combo_lane_glow_lines.size():
			var wave := 0.70 + 0.30 * sin(_combo_gold_fx_elapsed * 5.4 + float(i) * 0.58)
			_combo_lane_glow_lines[i].modulate.a = wave
		for i in _combo_lane_core_lines.size():
			var shimmer := 0.84 + 0.16 * sin(_combo_gold_fx_elapsed * 8.2 + float(i) * 0.37)
			_combo_lane_core_lines[i].modulate = Color(1.0 + shimmer * 0.12,
				1.0 + shimmer * 0.08, 1.0, shimmer)

		# 流光只是一段沿边缘移动的白金短线，不再生成任何轨道内部填充。
		var travel_start := COMBO_LANE_TOP_Y - 150.0
		var travel_end := COMBO_LANE_BOTTOM_Y + 180.0
		var flow_speed := lerpf(0.72, 1.08, level_progress)
		var segment_length := lerpf(110.0, 175.0, level_progress)
		for i in _combo_lane_flow_lines.size():
			var flow_line := _combo_lane_flow_lines[i]
			var phase := fposmod(_combo_gold_fx_elapsed * flow_speed + float(i) * 0.083, 1.0)
			var head_y := lerpf(travel_start, travel_end, phase)
			var tail_y := head_y - segment_length
			var clipped_top := maxf(COMBO_LANE_TOP_Y, tail_y)
			var clipped_bottom := minf(COMBO_LANE_BOTTOM_Y, head_y)
			if clipped_bottom <= clipped_top + 1.0:
				flow_line.visible = false
				continue
			flow_line.visible = true
			var edge_x := flow_line.points[0].x if not flow_line.points.is_empty() else 0.0
			flow_line.points = PackedVector2Array([
				Vector2(edge_x, clipped_top), Vector2(edge_x, clipped_bottom),
			])
			var flow_pulse := 0.90 + 0.10 * sin(_combo_gold_fx_elapsed * 11.0 + float(i))
			flow_line.modulate = Color(1.18, 1.12, 0.82, flow_pulse)


func _sync_combo_gold_material(sprite: Sprite2D) -> void:
	if sprite == null:
		return
	if _combo_gold_fx_enabled and _combo_arrow_overlay_enabled \
			and _combo_gold_material != null:
		sprite.material = _combo_gold_material
	elif sprite.material == _combo_gold_material:
		sprite.material = null


func _apply_combo_gold_to_item(item: Dictionary) -> void:
	for key in ["head", "neck", "body", "tail"]:
		var sprite := item.get(key) as Sprite2D
		if sprite != null:
			_sync_combo_gold_material(sprite)


func _apply_combo_gold_to_current_sprites() -> void:
	for sprite in _receptors:
		_sync_combo_gold_material(sprite as Sprite2D)
	for sprite in _hand_receptors:
		_sync_combo_gold_material(sprite as Sprite2D)
	for item in _render_notes:
		_apply_combo_gold_to_item(item)
	for item in _render_hand_notes:
		_apply_combo_gold_to_item(item)


func spawn_hit_effect(track: int) -> void:
	if not _heavy_effects_enabled:
		return
	if track < 0 or track >= _lane_x.size():
		return
	var groups := _fx_groups_p2 if _couple_mode and track >= 5 else _fx_groups
	var cfg := _fx_for_lane(track % 5, groups)
	var frames: Array = cfg[0]
	if frames.is_empty():
		return
	var anim := FrameAnim.new()
	anim.position = Vector2(_lane_x[track], _receptor_y())
	# 原版：目标宽 = 箭头宽 × 特效缩放系数2.6 × 1.25；按帧宽换算缩放
	var frame_w := maxf(64.0, float((frames[0] as Texture2D).get_width()))
	var s := lane_width * 2.4 / frame_w
	anim.scale = Vector2(-s if bool(cfg[1]) else s, s)
	anim.z_index = 20
	anim.set_additive()
	add_child(anim)
	anim.play(frames, 60.0, false)


func _note_scale() -> float:
	return (lane_width - 8.0) / ARROW_SIZE * float(SettingsStore.arrow_size_percent) / 100.0


var _item_lookup := {}  # "track:开始秒(4位)" -> 渲染项


func load_notes(judge_notes: Array) -> void:
	for item in _render_notes:
		_free_note_item(item)
	_render_notes.clear()
	_judged_heads.clear()
	_hold_active.clear()
	_item_lookup.clear()
	for i in judge_notes.size():
		var note = judge_notes[i]
		var item := {
			"note_idx": i,
			"track": note.track,
			"start_sec": note.start_sec,
			"end_sec": note.end_sec,
			"start_beat": note.start_beat,
			"end_beat": note.end_beat,
			"type": note.type,
			"head": null, "neck": null, "body": null, "tail": null,
			"done": false,
		}
		_render_notes.append(item)
		_item_lookup[_item_key(note.track, note.start_sec)] = item


func load_hand_events(events: Array) -> void:
	for item in _render_hand_notes:
		_free_note_item(item)
	_render_hand_notes.clear()
	for i in events.size():
		if not events[i] is Dictionary:
			continue
		var event: Dictionary = events[i]
		var start_sec := float(event.get("start_sec", 0.0))
		var end_sec := maxf(start_sec, float(event.get("end_sec", start_sec)))
		_render_hand_notes.append({
			"note_idx": i,
			"dir": str(event.get("dir", "tt")).strip_edges().to_lower(),
			"player": clampi(int(event.get("player", 1)), 1, 2),
			"start_sec": start_sec,
			"end_sec": end_sec,
			"start_beat": float(event.get("start_beat", NAN)),
			"end_beat": float(event.get("end_beat", NAN)),
			"type": str(event.get("type", "tap")).strip_edges().to_lower(),
			"head": null, "neck": null, "body": null, "tail": null,
			"effect_started": false, "active_effect": null,
			"done": false,
		})


func _item_key(track: int, start_sec: float) -> String:
	return "%d:%.4f" % [track, start_sec]


func set_grayscale(on: bool) -> void:
	if _grayscale == on:
		return
	_grayscale = on
	modulate = Color(0.45, 0.45, 0.45) if on else Color.WHITE


## 判定回报表现反馈：按 (轨道, 开始秒) 找到渲染项，命中即隐藏/吸附
func on_report(report: JudgeSystem.JudgeReport) -> void:
	if report == null or not report.scoring:
		return
	var track := report.track
	if track >= 0 and track < _receptor_flash.size():
		if report.judge != "miss":
			_receptor_flash[track] = 0.18
			# Hold Tick 也连续触发命中特效，形成原版持续按住的光效节奏。
			spawn_hit_effect(track)
	# 判定文字统一由 Gameplay 中央计数组渲染；这里仅保留轨道击中特效和 EARLY/LATE。
	# 否则会在中央计数组上方再出现一份独立 Perfect/Cool/Good/Miss。
	_spawn_timing_hint(track, report)

	if report.type == "hold_tick":
		return
	var item := _find_render_item(track, report.start_sec)
	if item.is_empty():
		return
	var idx: int = item["note_idx"]
	if report.judge == "miss":
		return  # miss 的音符继续滚出屏幕（对齐旧版观感）
	if report.type == "tap":
		_judged_heads[idx] = true
		_hide_note_item(item)
		item["done"] = true
	elif report.type == "hold_head":
		_hold_active[idx] = true


func _find_render_item(track: int, start_sec: float) -> Dictionary:
	var item = _item_lookup.get(_item_key(track, start_sec))
	if item != null and not item["done"]:
		return item
	return {}


var _zone_judge_sprites := {}   # zone -> Sprite2D（每区单实例，原版判定文字为固定位置）


func _spawn_judge_popup(track: int, judge: String) -> void:
	var tex = _judge_atlas.get("judge_%s" % judge)
	if tex == null:
		return
	var zone := 1 if (track_count >= 10 and track >= 5) else 0
	var base := zone * 5
	var x := field_center_x
	if _lane_x.size() >= base + 5:
		x = (float(_lane_x[base]) + float(_lane_x[base + 4])) * 0.5
	var spr: Sprite2D = _zone_judge_sprites.get(zone)
	if spr == null:
		spr = Sprite2D.new()
		add_child(spr)
		_zone_judge_sprites[zone] = spr
	spr.texture = tex
	spr.position = Vector2(x, _receptor_y() + (-150.0 if _is_reverse() else 150.0))
	spr.visible = true
	spr.z_index = 30
	for popup in _judge_popups:
		if popup["sprite"] == spr:
			popup["t"] = 0.0
			return
	_judge_popups.append({"sprite": spr, "t": 0.0})


func _spawn_timing_hint(track: int, report: JudgeSystem.JudgeReport) -> void:
	if report.type == "hold_tick" or report.judge == "miss" or absf(report.time_diff_ms) < 0.5:
		return
	# 全场只使用一条中央毫秒差：不加 EARLY/LATE、边框、背景或描边。
	var zone := 1 if (track_count >= 10 and track >= 5) else 0
	var label := get_node_or_null("TimingHintP1") as Label
	if label == null:
		label = Label.new()
		label.name = "TimingHintP1"
		label.position = Vector2(896, _receptor_y() + (-150.0 if _is_reverse() else 480.0))
		label.size = Vector2(128, 38)
		label.pivot_offset = label.size * 0.5
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_constant_override("outline_size", 0)
		label.z_index = 230
		add_child(label)
	_zone_timing_labels[0] = label
	_zone_timing_labels[1] = label
	label.position = Vector2(896, _receptor_y() + (-150.0 if _is_reverse() else 480.0))
	var early := report.time_diff_ms > 0.0
	label.text = "%+.0f ms" % report.time_diff_ms
	label.add_theme_color_override("font_color",
		Color(0.45, 0.95, 1.0) if early else Color(1.0, 0.62, 0.34))
	label.scale = Vector2(0.90, 0.90)
	label.modulate.a = 1.0
	label.visible = true
	for popup in _timing_popups:
		if popup["label"] == label:
			popup["t"] = 0.0
			return
	_timing_popups.append({"label": label, "t": 0.0})


func update_field(chart_time: float, delta: float) -> void:
	_update_combo_gold_fx(delta)
	var speed := BASE_SPEED * scroll_speed_mult
	var scale := _note_scale()
	var screen_bottom := 1180.0
	var screen_top := -ARROW_SIZE
	var receptor_y := _receptor_y()
	var reverse := _is_reverse()

	_update_hand_notes(chart_time, speed, scale, screen_bottom)

	for item in _render_notes:
		if item["done"]:
			continue
		var start_sec: float = item["start_sec"]
		var end_sec: float = item["end_sec"]
		var start_beat := float(item.get("start_beat", NAN))
		var end_beat := float(item.get("end_beat", NAN))
		var idx: int = item["note_idx"]
		var is_hold: bool = item["type"] == "hold"
		var head_y := _scroll_y_event(start_sec, start_beat, chart_time, speed)
		var tail_y := _scroll_y_event(end_sec, end_beat, chart_time, speed)

		# hold 命中后头部吸附判定线；结束即收起
		if is_hold and _hold_active.has(idx):
			head_y = receptor_y
			if chart_time > end_sec:
				_hold_active.erase(idx)
				_judged_heads[idx] = true
				item["done"] = true
				_hide_note_item(item)
				continue

		var visible := true
		if _judged_heads.has(idx):
			visible = false
		elif not reverse and tail_y < receptor_y - 200.0:
			visible = false
			if chart_time > end_sec + 0.5:
				item["done"] = true
		elif reverse and tail_y > receptor_y + 200.0:
			visible = false
			if chart_time > end_sec + 0.5:
				item["done"] = true
		elif (not reverse and head_y > screen_bottom + ARROW_SIZE) \
				or (reverse and head_y < screen_top - ARROW_SIZE):
			visible = false
		if SettingsStore.hidden_mode == "全隐":
			visible = false

		if not visible:
			_hide_note_item(item)
			continue

		var track := int(item["track"])
		# 验收规则：轨迹摇摆/旋转只作用 Tap；Hold 必须保持头、身、尾同一直线。
		var draw_x := float(_lane_x[track]) if is_hold else \
			_visual_x(float(_lane_x[track]), chart_time, start_sec, track)
		var rotation := 0.0 if is_hold else _visual_rotation(chart_time, start_sec, track)
		var suffix: String = ARROW_SUFFIX[_direction_indices[track % 5]]
		var player := _player_for_track(track)
		# 头
		if item["head"] == null:
			item["head"] = _acquire_sprite()
		var head: Sprite2D = item["head"]
		head.texture = _arrow_texture("body", suffix, player)
		head.position = Vector2(draw_x, head_y)
		head.scale = Vector2(scale, scale)
		head.rotation = (PI if reverse else 0.0) + rotation
		head.modulate = Color(1, 1, 1, _visual_alpha(head_y))
		head.visible = head.modulate.a > 0.001
		head.z_index = 4

		if is_hold:
			# 原版 atlas 语义：body 是头，mask 跨过头部中心，repeat 从 mask 底部
			# 平铺到终点，tail 的顶部锚在终点；各段只做 0.5px 抗裂缝重叠。
			var mask_source := _arrow_texture("mask", suffix, player)
			var body_source := _arrow_texture("repeat", suffix, player)
			var tail_source := _arrow_texture("tail", suffix, player)
			if mask_source == null:
				mask_source = body_source
			var mask_h := maxf(1.0, float(mask_source.get_height()) * scale) if mask_source != null else 1.0
			var tail_h := maxf(1.0, float(tail_source.get_height()) * scale) if tail_source != null else 1.0
			var geometry := _hold_geometry(head_y, tail_y, mask_h, tail_h)
			if item["neck"] == null:
				item["neck"] = _acquire_sprite()
			var neck: Sprite2D = item["neck"]
			neck.texture = mask_source
			neck.position = Vector2(draw_x, float(geometry["mask_center"]))
			neck.scale = Vector2(scale, scale)
			neck.rotation = (PI if reverse else 0.0) + rotation
			neck.modulate = Color(1, 1, 1, _visual_alpha(float(geometry["mask_center"])))
			neck.visible = mask_source != null and neck.modulate.a > 0.001
			neck.z_index = 3

			if item["body"] == null:
				item["body"] = _acquire_sprite()
			var body: Sprite2D = item["body"]
			var tiled_len := maxf(1.0, float(geometry["body_bottom"]) - float(geometry["body_top"]))
			var target_w := maxi(8, int(round(ARROW_SIZE * scale)))
			var target_h := maxi(1, int(ceil(tiled_len)))
			body.texture = _tiled_hold_texture(body_source, "%d:%s" % [player, suffix],
				target_w, target_h)
			var body_texture_h := maxi(1, body.texture.get_height()) if body.texture != null else target_h
			body.scale = Vector2(1.0, float(target_h) / float(body_texture_h))
			body.position = Vector2(draw_x,
				float(geometry["body_top"]) + float(target_h) * 0.5)
			body.rotation = PI if reverse else 0.0
			body.modulate = Color(1, 1, 1, _visual_alpha(body.position.y))
			body.visible = body_source != null and absf(tail_y - head_y) > 1.0 \
				and body.modulate.a > 0.001
			body.z_index = 3

			if item["tail"] == null:
				item["tail"] = _acquire_sprite()
			var tail: Sprite2D = item["tail"]
			tail.texture = tail_source
			tail.position = Vector2(draw_x, float(geometry["tail_center"]))
			tail.scale = Vector2(scale, scale)
			tail.rotation = (PI if reverse else 0.0) + rotation
			tail.modulate = Color(1, 1, 1, _visual_alpha(float(geometry["tail_center"])))
			tail.visible = tail_source != null and tail.modulate.a > 0.001
			tail.z_index = 4
			head.z_index = 5
		_apply_combo_gold_to_item(item)

	# 判定区按下高亮
	for i in _receptors.size():
		if _receptor_flash[i] > 0.0:
			_receptor_flash[i] -= delta
			_receptors[i].modulate = Color(1.6, 1.6, 1.3, 1.0)
			var s := _note_scale() * 1.12
			_receptors[i].scale = Vector2(s, s)
		else:
			_receptors[i].modulate = Color(1, 1, 1, 0.85)
			var s2 := _note_scale()
			_receptors[i].scale = Vector2(s2, s2)

	# 判定弹字动画（每区单实例复用：砸入缩放 + 淡出隐藏）
	for popup in _judge_popups:
		popup["t"] += delta
		var t: float = popup["t"]
		var spr: Sprite2D = popup["sprite"]
		if t > 0.5:
			spr.visible = false
			continue
		var k := clampf(t / 0.12, 0.0, 1.0)
		spr.scale = Vector2(0.75 - 0.15 * k, 0.75 - 0.15 * k)
		spr.modulate.a = 1.0 - maxf(0.0, (t - 0.3) / 0.2)
	for popup in _timing_popups:
		popup["t"] += delta
		var timing_t: float = popup["t"]
		var timing_label: Label = popup["label"]
		if timing_t > 0.82:
			timing_label.visible = false
			continue
		var enter_t := clampf(timing_t / 0.14, 0.0, 1.0)
		var bounce := 1.0 + sin(enter_t * PI) * 0.08
		timing_label.scale = Vector2.ONE * lerpf(0.90, 1.0, enter_t) * bounce
		var timing_base_y := _receptor_y() + (-150.0 if _is_reverse() else 480.0)
		timing_label.position.y = timing_base_y - minf(14.0, timing_t * 19.0)
		timing_label.modulate.a = 1.0 - maxf(0.0, (timing_t - 0.50) / 0.32)


func _hand_texture(kind: String, direction: String, player: int) -> Texture2D:
	var texture := _arrow_texture(kind, direction, player)
	if texture == null:
		texture = _arrow_texture(kind, "cc", player)
	return texture


func _update_hand_notes(chart_time: float, speed: float, scale: float,
		screen_bottom: float) -> void:
	var hand_scale := scale * 0.88
	var reverse := _is_reverse()
	var receptor_y := _receptor_y()
	for item in _render_hand_notes:
		if bool(item.get("done", false)):
			continue
		var start_sec := float(item.get("start_sec", 0.0))
		var end_sec := float(item.get("end_sec", start_sec))
		var start_beat := float(item.get("start_beat", NAN))
		var end_beat := float(item.get("end_beat", NAN))
		var is_hold := str(item.get("type", "tap")) == "hold" or end_sec > start_sec + 0.001
		var direction := str(item.get("dir", "tt"))
		var player := int(item.get("player", 1))
		var target := _hand_target_position(direction, player)
		var lane_hint := clampi((player - 1) * 5 + 2, 0, maxi(0, track_count - 1))
		var draw_x := target.x if is_hold else _visual_x(target.x, chart_time, start_sec, lane_hint)
		var rotation := 0.0 if is_hold else _visual_rotation(chart_time, start_sec, lane_hint)
		var head_y := _scroll_y_event(start_sec, start_beat, chart_time, speed)
		var tail_y := _scroll_y_event(end_sec, end_beat, chart_time, speed)

		if not is_hold and chart_time >= start_sec - 0.001:
			if not bool(item.get("effect_started", false)):
				item["effect_started"] = true
				spawn_hand_effect(direction, player, false)
			item["done"] = true
			_hide_note_item(item)
			continue
		if is_hold:
			if chart_time >= end_sec - 0.001:
				_stop_hand_effect(item)
				item["done"] = true
				_hide_note_item(item)
				continue
			if chart_time >= start_sec:
				head_y = receptor_y
				if not bool(item.get("effect_started", false)):
					item["effect_started"] = true
					item["active_effect"] = spawn_hand_effect(direction, player, true)
		if SettingsStore.hidden_mode == "全隐" \
				or (not reverse and (head_y > screen_bottom + ARROW_SIZE or tail_y < receptor_y - 180.0)) \
				or (reverse and (head_y < -ARROW_SIZE * 2.0 or tail_y > receptor_y + 180.0)):
			_hide_note_item(item)
			continue

		if item["head"] == null:
			item["head"] = _acquire_sprite()
		var head := item["head"] as Sprite2D
		head.texture = _hand_texture("body", direction, player)
		head.position = Vector2(draw_x, head_y)
		head.scale = Vector2.ONE * hand_scale
		head.rotation = (PI if reverse else 0.0) + rotation
		head.modulate = Color(1, 1, 1, _visual_alpha(head_y))
		head.visible = head.modulate.a > 0.001
		head.z_index = 5
		_sync_combo_gold_material(head)

		if not is_hold:
			continue
		var mask_source := _hand_texture("mask", direction, player)
		var body_source := _hand_texture("repeat", direction, player)
		var tail_source := _hand_texture("tail", direction, player)
		if mask_source == null:
			mask_source = body_source
		var mask_h := maxf(1.0, float(mask_source.get_height()) * hand_scale) \
			if mask_source != null else 1.0
		var tail_h := maxf(1.0, float(tail_source.get_height()) * hand_scale) \
			if tail_source != null else 1.0
		var geometry := _hold_geometry(head_y, tail_y, mask_h, tail_h)
		if item["neck"] == null:
			item["neck"] = _acquire_sprite()
		var neck := item["neck"] as Sprite2D
		neck.texture = mask_source
		neck.position = Vector2(draw_x, float(geometry["mask_center"]))
		neck.scale = Vector2.ONE * hand_scale
		neck.rotation = (PI if reverse else 0.0) + rotation
		neck.modulate = Color(1, 1, 1, _visual_alpha(float(geometry["mask_center"])))
		neck.visible = mask_source != null and neck.modulate.a > 0.001
		neck.z_index = 4
		if item["body"] == null:
			item["body"] = _acquire_sprite()
		var body := item["body"] as Sprite2D
		var target_w := maxi(8, int(round(ARROW_SIZE * hand_scale)))
		var tiled_length := maxf(1.0,
			float(geometry["body_bottom"]) - float(geometry["body_top"]))
		var target_h := maxi(1, int(ceil(tiled_length)))
		body.texture = _tiled_hold_texture(body_source, "hand_%d_%s" % [player, direction],
			target_w, target_h)
		body.position = Vector2(draw_x,
			float(geometry["body_top"]) + float(target_h) * 0.5)
		var hand_body_texture_h := maxi(1, body.texture.get_height()) if body.texture != null else target_h
		body.scale = Vector2(1.0, float(target_h) / float(hand_body_texture_h))
		body.rotation = PI if reverse else 0.0
		body.modulate = Color(1, 1, 1, _visual_alpha(body.position.y))
		body.visible = body_source != null and absf(tail_y - head_y) > 1.0 \
			and body.modulate.a > 0.001
		body.z_index = 4
		if item["tail"] == null:
			item["tail"] = _acquire_sprite()
		var tail := item["tail"] as Sprite2D
		tail.texture = tail_source
		tail.position = Vector2(draw_x, float(geometry["tail_center"]))
		tail.scale = Vector2.ONE * hand_scale
		tail.rotation = (PI if reverse else 0.0) + rotation
		tail.modulate = Color(1, 1, 1, _visual_alpha(float(geometry["tail_center"])))
		tail.visible = tail_source != null and tail.modulate.a > 0.001
		tail.z_index = 5
		head.z_index = 6
		_apply_combo_gold_to_item(item)


func _tiled_hold_texture(source: Texture2D, suffix: String, target_w: int, target_h: int) -> Texture2D:
	if source == null:
		return null
	var quantized_h := maxi(HOLD_TILE_HEIGHT_STEP,
		int(ceil(float(target_h) / float(HOLD_TILE_HEIGHT_STEP))) * HOLD_TILE_HEIGHT_STEP)
	# suffix/尺寸相同并不代表纹理相同；运行中换皮肤时必须区分源 AtlasTexture，
	# 否则 Hold 头尾已换新皮，身体仍会命中旧缓存。
	var key := "%d:%s:%d:%d" % [source.get_instance_id(), suffix, target_w, quantized_h]
	if _hold_tile_cache.has(key):
		_hold_tile_cache_order.erase(key)
		_hold_tile_cache_order.append(key)
		return _hold_tile_cache[key]
	var source_image := source.get_image()
	if source_image == null or source_image.is_empty():
		return source
	var tile_h := maxi(2, int(round(float(source_image.get_height()) * float(target_w) /
		maxf(1.0, float(source_image.get_width())))))
	var tile := source_image.duplicate()
	tile.resize(target_w, tile_h, Image.INTERPOLATE_BILINEAR)
	var canvas := Image.create(target_w, quantized_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	var y := 0
	while y < quantized_h:
		var copy_h := mini(tile_h, quantized_h - y)
		canvas.blit_rect(tile, Rect2i(0, 0, target_w, copy_h), Vector2i(0, y))
		y += tile_h
	var texture := ImageTexture.create_from_image(canvas)
	_hold_tile_cache[key] = texture
	_hold_tile_cache_order.append(key)
	while _hold_tile_cache_order.size() > HOLD_TILE_CACHE_LIMIT:
		var oldest := str(_hold_tile_cache_order.pop_front())
		_hold_tile_cache.erase(oldest)
	return texture


func hold_tile_cache_size_for_test() -> int:
	return _hold_tile_cache.size()


func hold_tile_height_step_for_test() -> int:
	return HOLD_TILE_HEIGHT_STEP


func _hand_target_position(dir: String, player: int) -> Vector2:
	var direction := dir.strip_edges().to_lower()
	var zone := clampi(player - 1, 0, 1) if track_count >= 10 else 0
	var base := zone * 5
	if direction in ["tt", "bb"] and _lane_x.size() > base + 2:
		return Vector2(float(_lane_x[base + 2]), _receptor_y())
	var side := 0 if direction == "ll" else 1
	var index := zone * 2 + side
	if index >= 0 and index < _hand_receptors.size():
		return (_hand_receptors[index] as Sprite2D).position
	return Vector2(float(_lane_x[base + 2]) if _lane_x.size() > base + 2 else field_center_x,
		_receptor_y())


func hand_target_for_test(dir: String, player: int) -> Vector2:
	return _hand_target_position(dir, player)


func active_hand_visual_count_for_test() -> int:
	var count := 0
	for item in _render_hand_notes:
		var head := item.get("head") as Sprite2D
		if head != null and head.visible:
			count += 1
	return count


func set_hand_pressed(dir: String, player: int, pressed: bool) -> void:
	var direction := dir.strip_edges().to_lower()
	var zone := clampi(player - 1, 0, 1) if track_count >= 10 else 0
	if direction in ["tt", "bb"]:
		var middle_track := zone * 5 + 2
		if middle_track >= 0 and middle_track < _receptor_flash.size():
			_receptor_flash[middle_track] = 0.18 if pressed else 0.0
		return
	if _hand_receptors.is_empty():
		return
	var side := 0 if direction == "ll" else 1
	var index := zone * 2 + side
	if index < 0 or index >= _hand_receptors.size():
		return
	_hand_pressed["%d:%d" % [zone, side]] = pressed
	var hand := _hand_receptors[index] as Sprite2D
	var base_scale := _note_scale() * 0.9
	hand.scale = Vector2.ONE * (base_scale * (1.14 if pressed else 1.0))
	hand.modulate = Color(1.65, 1.65, 1.25, 1.0) if pressed else Color(1, 1, 1, 0.6)


func flash_receptor(track: int) -> void:
	if track >= 0 and track < _receptor_flash.size():
		_receptor_flash[track] = 0.1


func _hand_effect_transform(dir: String) -> Dictionary:
	match dir.strip_edges().to_lower():
		"rr": return {"rotation_degrees": 0.0, "scale_x_sign": -1.0}
		"tt": return {"rotation_degrees": 90.0, "scale_x_sign": 1.0}
		"bb": return {"rotation_degrees": -90.0, "scale_x_sign": 1.0}
		_: return {"rotation_degrees": 0.0, "scale_x_sign": 1.0}


func hand_effect_transform_for_test(dir: String) -> Dictionary:
	return _hand_effect_transform(dir)


## 手键装饰事件演出：dir=ll/tt/bb/rr，player 1/2；Hold 可循环到尾判。
func spawn_hand_effect(dir: String, player: int, loop := false) -> FrameAnim:
	if not _heavy_effects_enabled:
		return null
	var groups := _fx_groups_p2 if _couple_mode and player >= 2 else _fx_groups
	var frames: Array = groups.get("hand", [])
	if frames.is_empty():
		return null
	var target := _hand_target_position(dir, player)
	set_hand_pressed(dir, player, true)
	var transform := _hand_effect_transform(dir)
	var anim := FrameAnim.new()
	anim.position = target
	anim.rotation_degrees = float(transform["rotation_degrees"])
	var frame_w := maxf(64.0, float((frames[0] as Texture2D).get_width()))
	var s := lane_width * 2.0 / frame_w
	anim.scale = Vector2(s * float(transform["scale_x_sign"]), s)
	anim.z_index = 20
	anim.auto_free = not loop
	anim.set_additive()
	add_child(anim)
	anim.play(frames, 60.0, loop)
	anim.set_process(not _visual_paused)
	if loop:
		_active_hand_effects.append(anim)
	else:
		var tw := create_tween()
		tw.tween_callback(set_hand_pressed.bind(dir, player, false)).set_delay(0.18)
	return anim


func _stop_hand_effect(item: Dictionary) -> void:
	var anim := item.get("active_effect") as FrameAnim
	if anim != null and is_instance_valid(anim):
		_active_hand_effects.erase(anim)
		anim.stop()
		anim.queue_free()
	item["active_effect"] = null
	set_hand_pressed(str(item.get("dir", "tt")), int(item.get("player", 1)), false)


func active_hand_effect_count_for_test() -> int:
	_active_hand_effects = _active_hand_effects.filter(
		func(anim: FrameAnim): return is_instance_valid(anim) and not anim.is_queued_for_deletion())
	return _active_hand_effects.size()


func set_visual_paused(paused: bool) -> void:
	_visual_paused = paused
	for anim in _active_hand_effects:
		if is_instance_valid(anim):
			anim.set_process(not paused)


func _hold_geometry(head_y: float, tail_y: float, mask_h: float, tail_h: float) -> Dictionary:
	var mask_top := head_y - mask_h * 0.5
	var mask_bottom := mask_top + mask_h
	if tail_y >= head_y:
		var body_top := mask_bottom - 0.5
		var body_bottom := maxf(body_top, tail_y + 0.5)
		return {
			"mask_top": mask_top,
			"mask_center": head_y,
			"mask_bottom": mask_bottom,
			"body_top": body_top,
			"body_bottom": body_bottom,
			"tail_top": tail_y,
			"tail_center": tail_y + tail_h * 0.5,
		}
	# 反向卷轴中 tail 位于 head 上方。几何仍保持 body_top < body_bottom，
	# 贴图本身在调用处旋转 180°，避免 Hold 头/身/尾互相穿插。
	var reverse_body_top := minf(tail_y - 0.5, mask_top + 0.5)
	var reverse_body_bottom := maxf(reverse_body_top, mask_top + 0.5)
	return {
		"mask_top": mask_top,
		"mask_center": head_y,
		"mask_bottom": mask_bottom,
		"body_top": reverse_body_top,
		"body_bottom": reverse_body_bottom,
		"tail_top": tail_y,
		"tail_center": tail_y - tail_h * 0.5,
	}


func hold_geometry_for_test(head_y: float, tail_y: float, _head_h: float,
		mask_h: float, tail_h: float) -> Dictionary:
	return _hold_geometry(head_y, tail_y, mask_h, tail_h)


func _reset_pooled_sprite(spr: Sprite2D) -> void:
	spr.texture = null
	spr.position = Vector2.ZERO
	spr.rotation = 0.0
	spr.scale = Vector2.ONE
	spr.modulate = Color.WHITE
	spr.self_modulate = Color.WHITE
	spr.material = null
	spr.offset = Vector2.ZERO
	spr.centered = true
	spr.z_index = 0


func _acquire_sprite() -> Sprite2D:
	if not _note_pool.is_empty():
		var spr: Sprite2D = _note_pool.pop_back()
		_reset_pooled_sprite(spr)
		spr.visible = true
		return spr
	var s := Sprite2D.new()
	_reset_pooled_sprite(s)
	add_child(s)
	return s


func _hide_note_item(item: Dictionary) -> void:
	for k in ["head", "neck", "body", "tail"]:
		var spr = item[k]
		if spr != null:
			spr.visible = false
			_reset_pooled_sprite(spr)
			_note_pool.append(spr)
			item[k] = null


func _free_note_item(item: Dictionary) -> void:
	if item.has("active_effect") or item.has("effect_started"):
		_stop_hand_effect(item)
	for k in ["head", "neck", "body", "tail"]:
		var spr = item[k]
		if spr != null:
			spr.queue_free()
			item[k] = null
