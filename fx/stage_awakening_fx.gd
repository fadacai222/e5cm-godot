class_name StageAwakeningFx
extends Control
## 动态舞台五阶段觉醒系统。
## 0 冷场、1 升温、2 爆发、3 暴走、4 神域。
## 使用单层全屏 Shader 和轻量背景缩放；断连后逐档降级，避免瞬间熄灭。

signal stage_changed(stage: int)
signal background_zoom_changed(value: float)

const DECAY_STEP_SEC := 0.56
const FINAL_FADE_SEC := 0.72
const IMPACT_DECAY_SPEED := 4.6
const ENERGY_RESPONSE := 30.0
const LOW_FPS_THRESHOLD := 52.0
const CRITICAL_FPS_THRESHOLD := 42.0
const LOW_FPS_HOLD_SEC := 0.75
const CRITICAL_FPS_HOLD_SEC := 1.50
const STAGE_STRENGTHS := [0.16, 0.38, 0.62, 0.82, 1.0]
const STAGE_ZOOMS := [1.0, 1.004, 1.009, 1.016, 1.023]
const REDUCED_MOTION_ZOOMS := [1.0, 1.001, 1.003, 1.005, 1.007]

var _overlay: ColorRect
var _material: ShaderMaterial
var _stage := 0
var _combo := 0
var _elapsed := 0.0
var _impact := 0.0
var _current_strength := STAGE_STRENGTHS[0]
var _music_energy_target := 0.0
var _music_energy := 0.0
var _background_zoom := 1.0
var _reduced_motion := false
var _paused := false
var _decaying := false
var _decay_elapsed := 0.0
var _final_fade := 1.0
var _auto_low_cost := false
var _overlay_disabled_by_budget := false
var _low_fps_elapsed := 0.0
var _critical_fps_elapsed := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 位于背景之上、BackgroundDim 黑幕之下；READY 首帧仍保持纯黑。
	z_index = -150
	_build_overlay()
	_refresh_render_activity()
	_apply_shader_state()


func _build_overlay() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "StageAwakeningOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.color = Color.WHITE
	var shader := load("res://fx/stage_awakening.gdshader") as Shader
	if shader != null:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_overlay.material = _material
	add_child(_overlay)
	_overlay.visible = false


static func stage_for_combo(combo: int) -> int:
	if combo >= 300:
		return 4
	if combo >= 200:
		return 3
	if combo >= 100:
		return 2
	if combo >= 50:
		return 1
	return 0


func set_combo(combo: int, reduced_motion := false) -> void:
	_combo = maxi(0, combo)
	_reduced_motion = reduced_motion
	var next_stage := stage_for_combo(_combo)
	if next_stage < _stage:
		start_decay()
		return
	if next_stage == _stage:
		if _decaying and next_stage > 0:
			_cancel_decay_at_stage(next_stage)
		else:
			_refresh_strength_and_zoom()
			_apply_shader_state()
		return
	_decaying = false
	_decay_elapsed = 0.0
	_final_fade = 1.0
	_set_stage(next_stage, true)


func start_decay() -> void:
	if _stage <= 0 or _decaying:
		return
	_decaying = true
	_decay_elapsed = 0.0
	_final_fade = 1.0


func _cancel_decay_at_stage(stage: int) -> void:
	_decaying = false
	_decay_elapsed = 0.0
	_final_fade = 1.0
	_set_stage(stage, false)


func reset_immediate() -> void:
	_combo = 0
	_decaying = false
	_decay_elapsed = 0.0
	_final_fade = 1.0
	_music_energy_target = 0.0
	_music_energy = 0.0
	_impact = 0.0
	_auto_low_cost = false
	_overlay_disabled_by_budget = false
	_low_fps_elapsed = 0.0
	_critical_fps_elapsed = 0.0
	_set_stage(0, false)
	_refresh_render_activity()
	_apply_shader_state()


func set_paused(value: bool) -> void:
	_paused = value


func set_music_energy(value: float) -> void:
	_music_energy_target = clampf(value, 0.0, 1.0) if _stage > 0 else 0.0


func update_performance_budget(fps: float, delta: float) -> void:
	if _stage <= 0 or fps <= 1.0:
		return
	var safe_delta := maxf(0.0, delta)
	if fps < LOW_FPS_THRESHOLD:
		_low_fps_elapsed += safe_delta
	else:
		_low_fps_elapsed = 0.0
	if fps < CRITICAL_FPS_THRESHOLD:
		_critical_fps_elapsed += safe_delta
	else:
		_critical_fps_elapsed = 0.0
	if not _auto_low_cost and _low_fps_elapsed >= LOW_FPS_HOLD_SEC:
		_auto_low_cost = true
		_apply_shader_state()
	if not _overlay_disabled_by_budget \
			and _critical_fps_elapsed >= CRITICAL_FPS_HOLD_SEC:
		_overlay_disabled_by_budget = true
		_refresh_render_activity()


func get_stage() -> int:
	return _stage


func get_background_zoom() -> float:
	return _background_zoom


func _set_stage(value: int, with_impact: bool) -> void:
	var next_stage := clampi(value, 0, 4)
	var changed := next_stage != _stage
	_stage = next_stage
	if with_impact and changed:
		_impact = 1.0
	_refresh_strength_and_zoom()
	if changed:
		stage_changed.emit(_stage)
	_refresh_render_activity()
	_apply_shader_state()


func _refresh_render_activity() -> void:
	var active := _stage > 0 or _decaying
	set_process(active)
	if _overlay != null:
		_overlay.visible = active and not _overlay_disabled_by_budget


func _refresh_strength_and_zoom() -> void:
	var strength_scale := 0.72 if _reduced_motion else 1.0
	_current_strength = float(STAGE_STRENGTHS[_stage]) * strength_scale * _final_fade
	var zooms: Array = REDUCED_MOTION_ZOOMS if _reduced_motion else STAGE_ZOOMS
	var next_zoom := lerpf(1.0, float(zooms[_stage]), _final_fade)
	if not is_equal_approx(next_zoom, _background_zoom):
		_background_zoom = next_zoom
		background_zoom_changed.emit(_background_zoom)


func _advance_decay(delta: float) -> void:
	if not _decaying:
		return
	_decay_elapsed += maxf(0.0, delta)
	while _stage > 1 and _decay_elapsed >= DECAY_STEP_SEC:
		_decay_elapsed -= DECAY_STEP_SEC
		_set_stage(_stage - 1, false)
		var recovered_stage := stage_for_combo(_combo)
		if recovered_stage >= _stage and recovered_stage > 0:
			_cancel_decay_at_stage(recovered_stage)
			return
	if _stage > 1:
		return
	var recovered_stage := stage_for_combo(_combo)
	if recovered_stage >= _stage and recovered_stage > 0:
		_cancel_decay_at_stage(recovered_stage)
		return
	if _stage == 1 and _decay_elapsed < DECAY_STEP_SEC:
		return
	var fade_elapsed := _decay_elapsed - DECAY_STEP_SEC
	var fade_progress := clampf(fade_elapsed / FINAL_FADE_SEC, 0.0, 1.0)
	_final_fade = 1.0 - smoothstep(0.0, 1.0, fade_progress)
	_refresh_strength_and_zoom()
	if fade_progress >= 1.0:
		_decaying = false
		_decay_elapsed = 0.0
		_final_fade = 1.0
		_set_stage(0, false)


func _process(delta: float) -> void:
	if _paused:
		return
	var safe_delta := maxf(0.0, delta)
	_elapsed += safe_delta
	_advance_decay(safe_delta)
	_music_energy = lerpf(_music_energy, _music_energy_target,
		1.0 - exp(-ENERGY_RESPONSE * safe_delta))
	_impact = maxf(0.0, _impact - safe_delta * IMPACT_DECAY_SPEED)
	_apply_shader_state()


func _apply_shader_state() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("fx_time", _elapsed)
	_material.set_shader_parameter("fx_stage", float(_stage))
	_material.set_shader_parameter("fx_strength", _current_strength)
	_material.set_shader_parameter("fx_impact", _impact)
	_material.set_shader_parameter("music_energy", _music_energy)
	_material.set_shader_parameter("reduced_motion", 1.0 if _reduced_motion else 0.0)
	_material.set_shader_parameter("low_cost", 1.0 if (_reduced_motion or _auto_low_cost) else 0.0)


func current_stage_for_test() -> int:
	return _stage


func current_strength_for_test() -> float:
	return _current_strength


func background_zoom_for_test() -> float:
	return _background_zoom


func music_energy_for_test() -> float:
	return _music_energy


func reduced_motion_for_test() -> bool:
	return _reduced_motion


func low_cost_mode_for_test() -> bool:
	return _reduced_motion or _auto_low_cost


func overlay_disabled_by_budget_for_test() -> bool:
	return _overlay_disabled_by_budget


func is_decaying() -> bool:
	return _decaying


func decay_step_seconds_for_test() -> float:
	return DECAY_STEP_SEC


func final_fade_seconds_for_test() -> float:
	return FINAL_FADE_SEC
