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
var _hold_tile_cache := {}       # "suffix:width:height" -> ImageTexture，避免逐帧纵向拉伸
var _hand_pressed := {}          # "zone:side" -> bool
var _active_hand_effects: Array[FrameAnim] = []
var _visual_paused := false
var _combo_gold_fx_enabled := false
var _combo_gold_fx_level := 0
var _combo_gold_fx_elapsed := 0.0
var _combo_gold_material: ShaderMaterial

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
	_apply_combo_gold_to_current_sprites()


## key_effect 帧分组：数字前缀升序前4组 = hand / lb / lt / cc（对应旧 击中特效序列帧.py）
func _build_fx_groups_from_atlas(source_atlas: Dictionary) -> Dictionary:
	var groups := {}
	var prefixes := {}
	for name in source_atlas.keys():
		var text := str(name)
		if not text.ends_with(".png"):
			continue
		var re := RegEx.new()
		re.compile("^(.*)_(\\d{4})\\.png$")
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


func note_visual_for_test(base_x: float, y: float, chart_time: float,
		event_sec: float, lane: int) -> Dictionary:
	return {"x": _visual_x(base_x, chart_time, event_sec, lane),
		"rotation": _visual_rotation(chart_time, event_sec, lane), "alpha": _visual_alpha(y)}


func combo_fx_track_rect() -> Rect2:
	if _lane_x.is_empty():
		return Rect2(600, 120, 720, 820)
	var left := float(_lane_x[0]) - lane_width * 0.62
	var right := float(_lane_x[_lane_x.size() - 1]) + lane_width * 0.62
	return Rect2(left, 110.0, maxf(160.0, right - left), 840.0)


func _ensure_combo_gold_material() -> void:
	if _combo_gold_material != null:
		return
	var shader := load("res://fx/gold_combo_outline.gdshader") as Shader
	if shader == null:
		return
	_combo_gold_material = ShaderMaterial.new()
	_combo_gold_material.shader = shader
	_combo_gold_material.set_shader_parameter("fx_time", 0.0)
	_combo_gold_material.set_shader_parameter("fx_strength", 1.15)
	_combo_gold_material.set_shader_parameter("outline_pixels", 2.8)
	_combo_gold_material.set_shader_parameter("gold_fill", 0.12)
	_combo_gold_material.set_shader_parameter("spark_density", 0.30)


## 兼容旧调用；duration 参数故意忽略。百连金化只由 Combo 是否断掉控制。
func set_combo_gold_fx_enabled(enabled: bool, _duration := 0.0) -> void:
	set_combo_gold_fx_level(1 if enabled else 0)


func set_combo_gold_fx_level(level: int) -> void:
	var next_level := maxi(0, level)
	var was_enabled := _combo_gold_fx_enabled
	_combo_gold_fx_level = next_level
	_combo_gold_fx_enabled = next_level > 0
	if _combo_gold_fx_enabled:
		_ensure_combo_gold_material()
		if not was_enabled:
			_combo_gold_fx_elapsed = 0.0
		if _combo_gold_material != null:
			var progress := clampf(float(next_level - 1) / 6.0, 0.0, 1.0)
			_combo_gold_material.set_shader_parameter("fx_strength", lerpf(1.15, 2.85, progress))
			_combo_gold_material.set_shader_parameter("outline_pixels", lerpf(2.8, 6.2, progress))
			_combo_gold_material.set_shader_parameter("gold_fill", lerpf(0.12, 1.0, progress))
			_combo_gold_material.set_shader_parameter("spark_density", lerpf(0.30, 0.88, progress))
	_apply_combo_gold_to_current_sprites()


func is_combo_gold_fx_enabled() -> bool:
	return _combo_gold_fx_enabled


func combo_gold_fx_level_for_test() -> int:
	return _combo_gold_fx_level


func _update_combo_gold_fx(delta: float) -> void:
	if not _combo_gold_fx_enabled or _visual_paused:
		return
	_combo_gold_fx_elapsed += delta
	if _combo_gold_material != null:
		_combo_gold_material.set_shader_parameter("fx_time", _combo_gold_fx_elapsed)


func _sync_combo_gold_material(sprite: Sprite2D) -> void:
	if sprite == null:
		return
	if _combo_gold_fx_enabled and _combo_gold_material != null:
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
		var idx: int = item["note_idx"]
		var is_hold: bool = item["type"] == "hold"
		var head_y := _scroll_y(start_sec, chart_time, speed)
		var tail_y := _scroll_y(end_sec, chart_time, speed)

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
		# 头
		if item["head"] == null:
			item["head"] = _acquire_sprite()
		var head: Sprite2D = item["head"]
		head.texture = _arrow_atlas.get("arrow_body_%s" % suffix)
		head.position = Vector2(draw_x, head_y)
		head.scale = Vector2(scale, scale)
		head.rotation = (PI if reverse else 0.0) + rotation
		head.modulate = Color(1, 1, 1, _visual_alpha(head_y))
		head.visible = head.modulate.a > 0.001
		head.z_index = 4

		if is_hold:
			# 原版 atlas 语义：body 是头，mask 跨过头部中心，repeat 从 mask 底部
			# 平铺到终点，tail 的顶部锚在终点；各段只做 0.5px 抗裂缝重叠。
			var mask_source: Texture2D = _arrow_atlas.get("arrow_mask_%s" % suffix)
			var body_source: Texture2D = _arrow_atlas.get("arrow_repeat_%s" % suffix)
			var tail_source: Texture2D = _arrow_atlas.get("arrow_tail_%s" % suffix)
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
			body.texture = _tiled_hold_texture(body_source, suffix, target_w, target_h)
			body.scale = Vector2.ONE
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


func _hand_texture(kind: String, direction: String) -> Texture2D:
	var key := "arrow_%s_%s" % [kind, direction]
	var texture = _arrow_atlas.get(key)
	if texture == null:
		texture = _arrow_atlas.get("arrow_%s_cc" % kind)
	return texture as Texture2D


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
		var is_hold := str(item.get("type", "tap")) == "hold" or end_sec > start_sec + 0.001
		var direction := str(item.get("dir", "tt"))
		var player := int(item.get("player", 1))
		var target := _hand_target_position(direction, player)
		var lane_hint := clampi((player - 1) * 5 + 2, 0, maxi(0, track_count - 1))
		var draw_x := target.x if is_hold else _visual_x(target.x, chart_time, start_sec, lane_hint)
		var rotation := 0.0 if is_hold else _visual_rotation(chart_time, start_sec, lane_hint)
		var head_y := _scroll_y(start_sec, chart_time, speed)
		var tail_y := _scroll_y(end_sec, chart_time, speed)

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
		head.texture = _hand_texture("body", direction)
		head.position = Vector2(draw_x, head_y)
		head.scale = Vector2.ONE * hand_scale
		head.rotation = (PI if reverse else 0.0) + rotation
		head.modulate = Color(1, 1, 1, _visual_alpha(head_y))
		head.visible = head.modulate.a > 0.001
		head.z_index = 5
		_sync_combo_gold_material(head)

		if not is_hold:
			continue
		var mask_source := _hand_texture("mask", direction)
		var body_source := _hand_texture("repeat", direction)
		var tail_source := _hand_texture("tail", direction)
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
		body.texture = _tiled_hold_texture(body_source, "hand_%s" % direction, target_w, target_h)
		body.position = Vector2(draw_x,
			float(geometry["body_top"]) + float(target_h) * 0.5)
		body.scale = Vector2.ONE
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
	var key := "%s:%d:%d" % [suffix, target_w, target_h]
	if _hold_tile_cache.has(key):
		return _hold_tile_cache[key]
	var source_image := source.get_image()
	if source_image == null or source_image.is_empty():
		return source
	var tile_h := maxi(2, int(round(float(source_image.get_height()) * float(target_w) /
		maxf(1.0, float(source_image.get_width())))))
	var tile := source_image.duplicate()
	tile.resize(target_w, tile_h, Image.INTERPOLATE_BILINEAR)
	var canvas := Image.create(target_w, target_h, false, Image.FORMAT_RGBA8)
	canvas.fill(Color.TRANSPARENT)
	var y := 0
	while y < target_h:
		var copy_h := mini(tile_h, target_h - y)
		canvas.blit_rect(tile, Rect2i(0, 0, target_w, copy_h), Vector2i(0, y))
		y += tile_h
	var texture := ImageTexture.create_from_image(canvas)
	_hold_tile_cache[key] = texture
	return texture


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
