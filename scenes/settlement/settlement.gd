extends Control
## 结算场景 —— 布局取自 config/layout/结算场景布局.json（基准1600×900，×1.2 到 1080p）：
## panel(115,120,840,840) cover(282,356,206,220) 星级(184,610) 歌名(181,656)
## 数值右对齐列 miss(562,356)/good(554,418)/cool(554,484)/perfect(554,548)/combo(554,616)/
## accuracy(563,689)/score(552,804)；评级图右半区砸入；
## 阶段3 用原版提示图（下一把/继续挑战/是否续币/赠送一把/是/否/倒计时数字）。

const SC := 1.2

var payload := {}
var _phase := 1
var _t := 0.0
@onready var _grade_sprite: TextureRect = $GradeSprite
@onready var _top_badge: TextureRect = $TopStatusBadge
@onready var _new_record_badge: TextureRect = $NewRecordBadge
var _record_result := {}
var _exp_result := {}
var _settlement_sfx_duration := 0.0
var _settlement_bgm_started := false
var _grade_target_position := Vector2.ZERO
var _top_badge_target_position := Vector2.ZERO
var _new_record_target_position := Vector2.ZERO

# 阶段3
var _p3_type := ""
var _p3_deadline := 0.0
var _p3_action := {}
@onready var _p3_prompt: TextureRect = $Phase3Prompt
@onready var _p3_countdown: Label = $Phase3Countdown
@onready var _p3_countdown_digits: Control = $Phase3CountdownDigits
@onready var _p3_yes: TextureButton = $Phase3Yes
@onready var _p3_no: TextureButton = $Phase3No
var _p3_done := false
var _p3_selected := 0

const NUM_ANIM_SEC := 2.5
const GRADE_SLAM_SEC := 0.2
const TOP_BADGE_SLAM_SEC := 0.3
const PHASE1_SEC := 8.0
const PHASE2_SEC := 6.8

var _value_labels := {}
var exp_panel: Control
var _upgrade_effect: TextureRect
var _upgrade_started := false
var _exp_animation_tweens: Array[Tween] = []
@onready var _background: TextureRect = $SettlementBackground
@onready var _credit_label: Label = $BottomCreditCenter/BottomCreditRow/CreditLabel


func _rect(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(x * SC, y * SC, w * SC, h * SC)


func _ease_out_cubic(value: float) -> float:
	var x := 1.0 - clampf(value, 0.0, 1.0)
	return 1.0 - x * x * x


func _ease_out_back(value: float) -> float:
	var x := clampf(value, 0.0, 1.0) - 1.0
	const C1 := 1.70158
	const C3 := C1 + 1.0
	return 1.0 + C3 * x * x * x + C1 * x * x


func _apply_player_layout() -> void:
	if int(payload.get("玩家序号", 1)) != 2:
		return
	# 原版 2P 结算面板沿屏幕中线镜像；1080p 下偏移为 849.6px。
	var panel := $SettlementPanel as Control
	var target_left := size.x - 115.2 - panel.size.x
	var offset_x := target_left - panel.position.x
	for node_path in [
		"SettlementPanel", "CoverClip", "StarLabel", "SongTitle", "StageLabel",
		"Miss", "Good", "Cool", "Perfect", "Combo", "Accuracy", "Score",
		"GradeSprite", "TopStatusBadge", "NewRecordBadge"
	]:
		var control := get_node_or_null(node_path) as Control
		if control != null:
			control.position.x += offset_x


func _ready() -> void:
	payload = SceneRouter.take_payload()
	_apply_player_layout()
	_background.texture = AssetLoader.tex(str(payload.get("cover", "")))
	AudioDirector.stop_bgm()
	var settlement_sfx := AssetLoader.sound("结算音效")
	_settlement_sfx_duration = AudioDirector.get_audio_length(settlement_sfx)
	AudioDirector.play_sfx(settlement_sfx, "settlement.result")

	# 结算面板（原版通用背景）
	var panel := $SettlementPanel as TextureRect
	panel.texture = AssetLoader.tex("UI-img/游戏界面/结算/结算背景通用.png")

	# 封面区（clip 容器强制裁剪到布局矩形）
	($CoverClip/Cover as TextureRect).texture = AssetLoader.tex(str(payload.get("cover", "")))

	# 星级 + 歌名
	var star := int(payload.get("star", 0))
	$StarLabel.text = "★".repeat(mini(star, 10)) + ("×%d" % star if star > 10 else "")
	$SongTitle.text = str(payload.get("曲目名", ""))

	# 数值列（右对齐，滚动动画在 _process 填充）
	_value_labels = {
		"miss": $Miss, "good": $Good, "cool": $Cool, "perfect": $Perfect,
		"combo": $Combo, "accuracy": $Accuracy, "score": $Score/Value,
	}
	$StageLabel.text = "%s  第%d把" % [str(payload.get("submode", "")),
		int(payload.get("当前关卡", 1))]

	# 原版流程1：评级从屏幕左侧砸入 grade_main，顶部徽章随后从上方落下。
	var grade := str(payload.get("评级", "F"))
	_grade_sprite.texture = AssetLoader.grade_tex(grade)
	_grade_sprite.pivot_offset = _grade_sprite.size * 0.5
	_grade_target_position = _grade_sprite.position
	_grade_sprite.scale = Vector2(1.3, 1.3)
	_grade_sprite.modulate.a = 0.0
	_grade_sprite.position.x = -_grade_sprite.size.x

	var failed := bool(payload.get("失败", false)) or grade.to_upper() == "F"
	var full_combo := bool(payload.get("是否全连", payload.get("全连", false)))
	_top_badge.texture = AssetLoader.tex("UI-img/游戏界面/结算/评价/%s.png" % (
		"失败" if failed else "全连")) if failed or full_combo else null
	_top_badge_target_position = _top_badge.position
	_top_badge.pivot_offset = _top_badge.size * 0.5
	_top_badge.visible = false
	_top_badge.modulate.a = 0.0
	_top_badge.position.y = _top_badge_target_position.y - _top_badge.size.y

	_new_record_badge.texture = AssetLoader.tex("UI-img/游戏界面/结算/新纪录.png")
	_new_record_target_position = _new_record_badge.position
	_new_record_badge.pivot_offset = _new_record_badge.size * 0.5
	_new_record_badge.visible = false
	_new_record_badge.modulate.a = 0.0
	$FailImage.visible = false
	_update_credit_label(GameState.credits)
	GameState.credits_changed.connect(_update_credit_label)
	_persist_results()
	_build_phase3_ui()
	if bool(payload.get("三把S赠送", false)):
		_show_three_s_effect()


func _update_credit_label(credits: int) -> void:
	_credit_label.text = "CREDIT：%d/%d" % [maxi(0, credits), GameState.CREDITS_PER_GAME]


func _mk_value(key: String, rect: Rect2, color: Color) -> void:
	var l := Label.new()
	l.position = rect.position
	l.custom_minimum_size = rect.size
	l.size = rect.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", int(rect.size.y * 0.62))
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_child(l)
	_value_labels[key] = l


func _persist_results() -> void:
	var grade := str(payload.get("评级", "F"))
	var song_name := str(payload.get("曲目名", ""))
	var score := int(payload.get("本局最高分", 0))

	_record_result = ProfileStore.update_song_record(
		str(payload.get("sm_key", "")), song_name, score)

	var stats: Dictionary = ProfileStore.profile.get("统计", {})
	stats["游玩时长分钟"] = int(stats.get("游玩时长分钟", 0)) + \
		maxi(1, int(roundf(float(payload.get("歌曲时长秒", 60.0)) / 60.0)))
	if grade == "S" and not bool(payload.get("失败", false)):
		stats["累计评价S数"] = int(stats.get("累计评价S数", 0)) + 1
	if int(payload.get("本局最大combo", 0)) > int(stats.get("最大Combo", 0)):
		stats["最大Combo"] = int(payload.get("本局最大combo", 0))
		stats["最大Combo曲目"] = song_name
	if score > int(stats.get("最高分", 0)):
		stats["最高分"] = score
		stats["最高分曲目"] = song_name
	ProfileStore.profile["统计"] = stats

	var mode := str(payload.get("mode", "竞速"))
	var progress := ProfileStore.get_mode_progress(mode)
	_exp_result = GameState.flow.settle_song_exp(
		mode, progress, int(payload.get("当前关卡", 1)), grade,
		int(payload.get("cool数", 0)), int(payload.get("good数", 0)),
		int(payload.get("miss数", 0)))
	if bool(_exp_result.get("预览缓存", false)):
		# 前两把仍按原版规则不写正式等级，但个人中心要实时显示已经缓存的累计经验。
		var preview_deposit: Dictionary = _exp_result.get("经验结算", {})
		ProfileStore.set_mode_progress_preview(mode,
			preview_deposit.get("模式进度", progress))
		ProfileStore.save_profile()
	else:
		ProfileStore.set_mode_progress(mode, _exp_result["模式进度"])


func _process(delta: float) -> void:
	_t += delta
	_update_settlement_audio()
	match _phase:
		1:
			_update_phase1()
			if _t >= PHASE1_SEC:
				_enter_phase2()
		2:
			if _t >= PHASE2_SEC or not bool(_exp_result.get("显示奖励窗", false)):
				_enter_phase3()
		3:
			_update_phase3()


func _update_settlement_audio() -> void:
	if _settlement_bgm_started or _t < _settlement_sfx_duration:
		return
	_settlement_bgm_started = true
	AudioDirector.play_bgm(AssetLoader.sound("音乐_UI"), true)


func _update_phase1() -> void:
	var k := clampf(_t / NUM_ANIM_SEC, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	(_value_labels["score"] as Label).text = "%d" % int(float(payload.get("本局最高分", 0)) * e)
	(_value_labels["accuracy"] as Label).text = "%05.2f%%" % (float(payload.get("百分比数值", 0.0)) * e)
	(_value_labels["combo"] as Label).text = "%d" % int(float(payload.get("本局最大combo", 0)) * e)
	(_value_labels["perfect"] as Label).text = "%d" % int(float(payload.get("perfect数", 0)) * e)
	(_value_labels["cool"] as Label).text = "%d" % int(float(payload.get("cool数", 0)) * e)
	(_value_labels["good"] as Label).text = "%d" % int(float(payload.get("good数", 0)) * e)
	(_value_labels["miss"] as Label).text = "%d" % int(float(payload.get("miss数", 0)) * e)

	var slam_t := clampf((_t - NUM_ANIM_SEC) / GRADE_SLAM_SEC, 0.0, 1.0)
	if slam_t > 0.0:
		var eased := _ease_out_back(slam_t)
		var target_center := _grade_target_position + _grade_sprite.size * 0.5
		var start_center_x := -_grade_sprite.size.x * 0.5
		_grade_sprite.position = Vector2(
			lerpf(start_center_x, target_center.x, eased) - _grade_sprite.size.x * 0.5,
			_grade_target_position.y)
		_grade_sprite.modulate.a = _ease_out_cubic(slam_t)
		var grade_scale := lerpf(1.3, 1.0, eased)
		_grade_sprite.scale = Vector2.ONE * grade_scale
		if slam_t >= 1.0:
			_grade_sprite.position = _grade_target_position
			_grade_sprite.scale = Vector2.ONE
			_grade_sprite.modulate.a = 1.0

	var badge_t := clampf((_t - NUM_ANIM_SEC - GRADE_SLAM_SEC) / TOP_BADGE_SLAM_SEC, 0.0, 1.0)
	if _top_badge.texture != null and badge_t > 0.0:
		_top_badge.visible = true
		var badge_eased := _ease_out_back(badge_t)
		_top_badge.position = Vector2(_top_badge_target_position.x,
			lerpf(_top_badge_target_position.y - _top_badge.size.y,
				_top_badge_target_position.y, badge_eased))
		_top_badge.modulate.a = _ease_out_cubic(badge_t)
		_top_badge.scale = Vector2.ONE * lerpf(1.3, 1.0, badge_eased)

	var record_t := clampf((_t - NUM_ANIM_SEC - 0.15) / 0.28, 0.0, 1.0)
	if bool(_record_result.get("是否新纪录", false)) and record_t > 0.0:
		_new_record_badge.visible = true
		_new_record_badge.position = _new_record_target_position
		_new_record_badge.modulate.a = _ease_out_cubic(record_t)
		_new_record_badge.scale = Vector2.ONE * lerpf(0.86, 1.0, _ease_out_back(record_t))


func _enter_phase2() -> void:
	_phase = 2
	_t = 0.0
	_upgrade_effect = null
	_upgrade_started = false
	for tween in _exp_animation_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_exp_animation_tweens.clear()
	if not bool(_exp_result.get("显示奖励窗", false)):
		return
	if is_instance_valid(exp_panel):
		exp_panel.free()
	exp_panel = Control.new()
	exp_panel.name = "ExperienceRewardPanel"
	exp_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	exp_panel.z_index = 60
	add_child(exp_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exp_panel.add_child(dim)

	var window := TextureRect.new()
	window.name = "RewardWindow"
	window.texture = AssetLoader.tex("UI-img/游戏界面/结算/结算等级小窗/UI_I516.png")
	window.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	window.stretch_mode = TextureRect.STRETCH_SCALE
	window.position = Vector2(686.4, 326.4) if int(payload.get("玩家序号", 1)) != 2 \
		else Vector2(115.2, 326.4)
	window.size = Vector2(770.4, 386.4)
	window.pivot_offset = window.size * 0.5
	exp_panel.add_child(window)

	_build_exp_digits(window, int(_exp_result.get("正式局总经验", 0)))
	if bool(_exp_result.get("预览缓存", false)):
		var cache_round := int(_exp_result.get("缓存把数", 1))
		var cache_hint := UiKit.label(window,
			"第 %d / 3 把经验已缓存 · 第三把统一写入等级" % cache_round,
			16, Vector2(184, 108), Color(0.56, 0.94, 1.0), 2)
		cache_hint.name = "CachedExperienceHint"
		cache_hint.size = Vector2(440, 34)
		cache_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_exp_progress(window)
	window.modulate.a = 0.0
	window.scale = Vector2(0.86, 0.86)
	var enter := create_tween().set_parallel(true)
	enter.tween_property(window, "modulate:a", 1.0, 0.28)
	enter.tween_property(window, "scale", Vector2.ONE, 0.38) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_exp_digits(window: Control, total_exp: int) -> void:
	var holder := Control.new()
	holder.name = "ExpDigits"
	holder.position = Vector2(283.2, 19.2)
	holder.size = Vector2(187.2, 114.0)
	holder.clip_contents = true
	window.add_child(holder)
	var text := "+%d" % maxi(0, total_exp)
	var textures: Array[Texture2D] = []
	var ratios: Array[float] = []
	for i in text.length():
		var texture := AssetLoader.tex(
			"UI-img/游戏界面/结算/结算等级小窗/经验数字/%s.png" % text.substr(i, 1))
		if texture != null:
			textures.append(texture)
			ratios.append(float(texture.get_width()) / maxf(1.0, float(texture.get_height())))
	if textures.is_empty():
		return
	var gap := 3.0
	var height := 86.0
	var width_sum := 0.0
	for ratio in ratios:
		width_sum += height * ratio
	width_sum += gap * maxi(0, textures.size() - 1)
	if width_sum > holder.size.x:
		height *= holder.size.x / width_sum
	var x := 0.0
	var y := (holder.size.y - height) * 0.5
	for i in textures.size():
		var width := height * ratios[i]
		var digit := TextureRect.new()
		digit.name = "ExpDigit%d" % i
		digit.texture = textures[i]
		digit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		digit.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		digit.position = Vector2(x, y)
		digit.size = Vector2(width, height)
		holder.add_child(digit)
		x += width + gap


func _build_exp_progress(window: Control) -> void:
	var active_mode := str(payload.get("mode", "竞速"))
	var deposit: Dictionary = _exp_result.get("经验结算", {})
	var style_progress := deposit if active_mode == "花式" else ProfileStore.get_mode_progress("花式")
	var speed_progress := deposit if active_mode == "竞速" else ProfileStore.get_mode_progress("竞速")
	_build_mode_exp_row(window, "Style", "花式", style_progress,
		Rect2(37.2, 136.8, 100.8, 38.4), Rect2(158.4, 141.6, 483.6, 27.6),
		Rect2(158.4, 141.6, 483.6, 27.6), Rect2(652.8, 136.8, 132.0, 40.8))
	_build_mode_exp_row(window, "Speed", "竞速", speed_progress,
		Rect2(38.4, 188.4, 96.0, 38.4), Rect2(158.4, 195.6, 483.6, 27.6),
		Rect2(158.4, 195.6, 483.6, 27.6), Rect2(650.4, 188.4, 132.0, 40.8))
	_build_rank_icon(window)
	if not bool(_exp_result.get("预览缓存", false)) \
			and (bool(deposit.get("是否升级", false)) or int(deposit.get("升级次数", 0)) > 0):
		_build_upgrade_effect(window, maxi(1, int(deposit.get("升级次数", 1))))


func _build_mode_exp_row(window: Control, prefix: String, mode: String, progress: Dictionary,
		label_rect: Rect2, fill_rect: Rect2, frame_rect: Rect2, level_rect: Rect2) -> void:
	var animated := progress.has("原等级") and progress.has("原经验")
	var level := int(progress.get("原等级", progress.get("等级", 1))) if animated \
		else int(progress.get("等级", 1))
	var experience := float(progress.get("原经验", progress.get("经验", 0.0))) if animated \
		else float(progress.get("经验", 0.0))
	var needed := maxi(1, int(progress.get("等级所需经验",
		ExpSystem.exp_to_next_level(level))) if animated else ExpSystem.exp_to_next_level(level))
	var ratio := 1.0 if level >= ExpSystem.MAX_LEVEL else clampf(experience / float(needed), 0.0, 1.0)
	var label := UiKit.label(window, "%s经验：" % mode, 26, label_rect.position, Color.WHITE, 2)
	label.name = "%sExperienceLabel" % prefix
	label.size = label_rect.size

	var clip := Control.new()
	clip.name = "%sExperienceBarFillClip" % prefix
	clip.position = fill_rect.position
	clip.size = Vector2(fill_rect.size.x * ratio, fill_rect.size.y)
	clip.clip_contents = true
	clip.visible = true
	clip.z_index = 2
	window.add_child(clip)
	var fill := TextureRect.new()
	fill.name = "%sExperienceBarFill" % prefix
	fill.texture = AssetLoader.tex("UI-img/经验条/%s经验-值.png" % mode)
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.size = fill_rect.size
	fill.visible = true
	fill.z_index = 1
	clip.add_child(fill)

	var frame := TextureRect.new()
	frame.name = "%sExperienceBarFrame" % prefix
	frame.texture = AssetLoader.tex("UI-img/经验条/%s经验-框.png" % mode)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.position = frame_rect.position
	frame.size = frame_rect.size
	frame.visible = true
	frame.z_index = 3
	window.add_child(frame)

	var level_label := UiKit.label(window, "Lv : %d" % level, 26, level_rect.position,
		Color(1.0, 0.95, 0.74), 2)
	level_label.name = "%sLevelLabel" % prefix
	level_label.size = level_rect.size
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if animated:
		_animate_exp_row(clip, level_label, fill_rect.size.x, progress)


func _exp_segments(progress: Dictionary) -> Array:
	var segments: Array = progress.get("进度片段", []).duplicate(true)
	if not segments.is_empty():
		return segments
	var old_level := int(progress.get("原等级", progress.get("等级", 1)))
	var new_level := int(progress.get("等级", old_level))
	var old_exp := float(progress.get("原经验", 0.0))
	var final_exp := float(progress.get("经验", old_exp))
	if new_level <= old_level:
		return [{"等级": old_level, "等级所需经验": ExpSystem.exp_to_next_level(old_level),
			"起始经验": old_exp, "结束经验": final_exp, "是否升级": false,
			"升级后等级": old_level}]
	var explicit_first_needed := maxi(1, int(progress.get("等级所需经验",
		ExpSystem.exp_to_next_level(old_level))))
	for level in range(old_level, new_level):
		segments.append({"等级": level,
			"等级所需经验": explicit_first_needed if level == old_level else ExpSystem.exp_to_next_level(level),
			"起始经验": old_exp if level == old_level else 0.0,
			"结束经验": 0.0, "是否升级": true, "升级后等级": level + 1})
	if final_exp > 0.0:
		segments.append({"等级": new_level, "等级所需经验": ExpSystem.exp_to_next_level(new_level),
			"起始经验": 0.0, "结束经验": final_exp, "是否升级": false,
			"升级后等级": new_level})
	return segments


func _animate_exp_row(clip: Control, level_label: Label, full_width: float,
		progress: Dictionary) -> void:
	var segments := _exp_segments(progress)
	if segments.is_empty():
		return
	var tween := create_tween()
	_exp_animation_tweens.append(tween)
	var set_segment_start := func(target_level: int, target_width: float) -> void:
		level_label.text = "Lv : %d" % target_level
		clip.size.x = target_width
	var apply_level_up := func(next_level: int) -> void:
		level_label.text = "Lv : %d" % next_level
		clip.size.x = 0.0
		_start_upgrade_effect()
	tween.tween_interval(0.52)
	for raw_segment in segments:
		var segment: Dictionary = raw_segment
		var level := int(segment.get("等级", 1))
		var needed := maxf(1.0, float(segment.get("等级所需经验",
			ExpSystem.exp_to_next_level(level))))
		var start_ratio := clampf(float(segment.get("起始经验", 0.0)) / needed, 0.0, 1.0)
		var leveled := bool(segment.get("是否升级", false))
		var end_ratio := 1.0 if leveled else clampf(
			float(segment.get("结束经验", 0.0)) / needed, 0.0, 1.0)
		tween.tween_callback(set_segment_start.bind(level, full_width * start_ratio))
		tween.tween_property(clip, "size:x", full_width * end_ratio, 0.72) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if leveled:
			var next_level := int(segment.get("升级后等级", level + 1))
			tween.tween_callback(apply_level_up.bind(next_level))
			tween.tween_interval(0.18)


func exp_animation_state_for_test(progress: Dictionary) -> Dictionary:
	return {"segments": _exp_segments(progress), "upgrade_count": int(progress.get("升级次数", 0))}


func _build_rank_icon(window: Control) -> void:
	var rank := ProfileStore.get_rank_index()
	var icon := TextureRect.new()
	icon.name = "RankIcon"
	icon.texture = AssetLoader.tex(ProfileStore.get_rank_asset_path())
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(240.0, 220.8)
	icon.size = Vector2(297.6, 172.8)
	window.add_child(icon)
	var rank_label := UiKit.label(window, "%d段" % rank, 18,
		Vector2(32.4, 286.8), Color(0.88, 0.93, 1.0), 2)
	rank_label.name = "RankLabel"
	rank_label.size = Vector2(138.0, 40.8)


func _build_upgrade_effect(window: Control, upgrade_count: int) -> void:
	_upgrade_effect = TextureRect.new()
	_upgrade_effect.name = "LevelUpEffect"
	_upgrade_effect.texture = AssetLoader.tex("UI-img/游戏界面/结算/结算等级小窗/升级动画素材/升级.png")
	_upgrade_effect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_upgrade_effect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_upgrade_effect.position = Vector2(136.8, -158.4)
	_upgrade_effect.size = Vector2(531.6, 172.8)
	_upgrade_effect.pivot_offset = _upgrade_effect.size * 0.5
	window.add_child(_upgrade_effect)
	if upgrade_count > 1:
		var count_label := UiKit.label(_upgrade_effect, "×%d" % upgrade_count, 34,
			Vector2(410, 102), Color(1.0, 0.88, 0.28), 3)
		count_label.name = "MultiLevelCount"
		count_label.size = Vector2(100, 48)
	_upgrade_effect.scale = Vector2(0.62, 0.62)
	_upgrade_effect.modulate.a = 0.0
	_upgrade_effect.visible = false


func _start_upgrade_effect() -> void:
	if _upgrade_effect == null or not is_instance_valid(_upgrade_effect):
		return
	_upgrade_started = true
	_upgrade_effect.visible = true
	_upgrade_effect.scale = Vector2(0.62, 0.62)
	_upgrade_effect.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	_exp_animation_tweens.append(tween)
	tween.tween_property(_upgrade_effect, "modulate:a", 1.0, 0.18)
	tween.tween_property(_upgrade_effect, "scale", Vector2(1.08, 1.08), 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(_upgrade_effect, "scale", Vector2.ONE, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _build_phase3_ui() -> void:
	_p3_prompt.visible = false
	_p3_countdown.visible = false
	_p3_countdown_digits.visible = false
	_p3_yes.texture_normal = AssetLoader.tex("UI-img/游戏界面/结算/提示/是.png")
	_p3_no.texture_normal = AssetLoader.tex("UI-img/游戏界面/结算/提示/否.png")
	_p3_yes.pressed.connect(_on_yes)
	_p3_no.pressed.connect(_on_no)
	_p3_yes.visible = false
	_p3_no.visible = false


func _show_prompt(img_name: String) -> void:
	_p3_prompt.texture = AssetLoader.tex("UI-img/游戏界面/结算/提示/%s.png" % img_name)
	_p3_prompt.visible = true


func _render_countdown_digits(value: int) -> void:
	for child in _p3_countdown_digits.get_children():
		child.free()
	var text := str(maxi(0, value))
	var textures: Array[Texture2D] = []
	var ratios: Array[float] = []
	for i in text.length():
		var texture := AssetLoader.tex(
			"UI-img/游戏界面/结算/提示/数字-倒计时/%s.png" % text.substr(i, 1))
		if texture != null:
			textures.append(texture)
			ratios.append(float(texture.get_width()) / maxf(1.0, float(texture.get_height())))
	if textures.is_empty():
		_p3_countdown_digits.visible = false
		return
	var gap := 4.0
	var height := 104.0
	var total_width := gap * maxi(0, textures.size() - 1)
	for ratio in ratios:
		total_width += height * ratio
	if total_width > _p3_countdown_digits.size.x:
		height *= _p3_countdown_digits.size.x / total_width
		total_width = _p3_countdown_digits.size.x
	var x := (_p3_countdown_digits.size.x - total_width) * 0.5
	var y := (_p3_countdown_digits.size.y - height) * 0.5
	for i in textures.size():
		var width := height * ratios[i]
		var digit := TextureRect.new()
		digit.name = "CountdownDigit%d" % i
		digit.texture = textures[i]
		digit.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		digit.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		digit.position = Vector2(x, y)
		digit.size = Vector2(width, height)
		_p3_countdown_digits.add_child(digit)
		x += width + gap
	_p3_countdown_digits.visible = true


func _enter_phase3() -> void:
	if exp_panel != null:
		exp_panel.visible = false
	_phase = 3
	_t = 0.0
	var round_n := int(payload.get("当前关卡", 1))
	var failed := bool(payload.get("失败", false))

	if bool(payload.get("三把S赠送", false)):
		_auto_prompt("赠送一把", 2.0,
			{"next_round": 4, "consume": 0, "new_match": false, "to": "song_select"})
		return
	if round_n in [1, 2]:
		if not failed:
			_auto_prompt("下一把", 2.0,
				{"next_round": round_n + 1, "consume": 0, "new_match": false, "to": "song_select"})
		else:
			_continue_branch(round_n, false)
		return
	_continue_branch(1, true)


func _continue_branch(next_round: int, new_match: bool) -> void:
	var action := {"next_round": next_round, "consume": GameState.CREDITS_PER_GAME,
		"new_match": new_match, "to": "song_select"}
	_p3_action = action
	_p3_deadline = 10.0
	_p3_countdown.visible = false
	_render_countdown_digits(10)
	if GameState.credits >= GameState.CREDITS_PER_GAME:
		_p3_type = "继续挑战"
		_show_prompt("继续挑战")
		_p3_yes.visible = true
		_p3_no.visible = true
		_set_p3_selection(0)
	else:
		_p3_type = "续币等待"
		_show_prompt("是否续币")


func _auto_prompt(img_name: String, sec: float, action: Dictionary) -> void:
	_p3_type = "自动提示"
	_p3_action = action
	_p3_deadline = sec
	_p3_yes.visible = false
	_p3_no.visible = false
	_p3_countdown_digits.visible = false
	_show_prompt(img_name)


func _set_p3_selection(index: int) -> void:
	_p3_selected = clampi(index, 0, 1)
	UiKit.highlight(_p3_yes, _p3_selected == 0)
	UiKit.highlight(_p3_no, _p3_selected == 1)


func _show_three_s_effect() -> void:
	if get_node_or_null("ThreeSGradeEffect") != null:
		return
	var effect := TextureRect.new()
	effect.name = "ThreeSGradeEffect"
	effect.texture = AssetLoader.tex("UI-img/游戏界面/结算/评价/三把全连.png")
	effect.position = Vector2(1080, 150)
	effect.size = Vector2(680, 680)
	effect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	effect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	effect.pivot_offset = effect.size * 0.5
	effect.z_index = 55
	effect.modulate.a = 0.0
	effect.scale = Vector2(2.4, 2.4)
	add_child(effect)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(effect, "modulate:a", 1.0, 0.28)
	tween.tween_property(effect, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(effect, "rotation", 0.0, 0.42).from(-0.08) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_phase3() -> void:
	if _p3_done:
		return
	var remain := _p3_deadline - _t
	match _p3_type:
		"自动提示":
			if remain <= 0.0:
				_execute(_p3_action)
		"继续挑战":
			_render_countdown_digits(maxi(0, int(ceilf(remain))))
			if remain <= 0.0:
				_execute(_p3_action)
		"续币等待":
			_render_countdown_digits(maxi(0, int(ceilf(remain))))
			if GameState.credits >= GameState.CREDITS_PER_GAME:
				_p3_type = "自动提示"
				_show_prompt("下一把")
				_t = 0.0
				_p3_deadline = 2.0
				_p3_countdown_digits.visible = false
			elif remain <= 0.0:
				_show_prompt("游戏结束")
				_p3_type = "结束展示"
				_t = 0.0
				_p3_deadline = 1.6
		"结束展示":
			if remain <= 0.0:
				_execute({"to": "coin"})


func _on_yes() -> void:
	if _p3_done or _p3_type != "继续挑战":
		return
	_execute(_p3_action)


func _on_no() -> void:
	if _p3_done:
		return
	_show_prompt("游戏结束")
	_p3_yes.visible = false
	_p3_no.visible = false
	_p3_countdown_digits.visible = false
	_p3_type = "结束展示"
	_t = 0.0
	_p3_deadline = 1.6


func _execute(action: Dictionary) -> void:
	_p3_done = true
	var to := str(action.get("to", "coin"))
	if to == "coin":
		GameState.reset_flow_state()
		SceneRouter.change_to("coin")
		return
	var consume := int(action.get("consume", 0))
	if consume > 0:
		GameState.consume_credits(consume)
	if bool(action.get("new_match", false)):
		GameState.flow.start_new_match()
	GameState.flow.current_round = int(action.get("next_round", 1))
	SceneRouter.change_to("song_select", GameState.song_select_restore)


func _unhandled_input(event: InputEvent) -> void:
	if _phase < 3:
		if event.is_action_pressed("pedal_confirm") or event.is_action_pressed("ui_accept"):
			if _phase == 1:
				_t = PHASE1_SEC
			else:
				_enter_phase3()
		return
	if _p3_type == "继续挑战":
		if event.is_action_pressed("pedal_left") or event.is_action_pressed("ui_left"):
			_set_p3_selection(0)
		elif event.is_action_pressed("pedal_right") or event.is_action_pressed("ui_right"):
			_set_p3_selection(1)
		elif event.is_action_pressed("pedal_confirm") or event.is_action_pressed("ui_accept"):
			if _p3_selected == 0:
				_on_yes()
			else:
				_on_no()
