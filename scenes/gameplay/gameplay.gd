extends Control
## 谱面播放场景（核心玩法 + 完整演出层）
## 载荷：{sm, mp3, cover, name, star, mode, submode, sm_key, prefer_double, couple}
## 演出：准备就绪动画、击中特效、手键装饰、判定弹字、血条原版皮肤、
##       圆环频谱（混音）、唱片动态背景、结算前成就动画、ESC 完整设置菜单。

const HP_OVERDRIVE_SPEED := 300.0
const HP_OVERDRIVE_BASE_X := 345.0
const HP_OVERDRIVE_PARTICLE_DELAY_SEC := 5.0
const STAGE_GROUP_OFFSET_X := -105.0
const STAGE_BOARD_ROTATION_DEG := 36.0
const ACHIEVEMENT_TIMEOUT_SEC := 4.6
const ROUTER_BUSY_TIMEOUT_SEC := 1.5
const AUDIO_EVENT_GRACE_SEC := 0.35
const MIN_VALID_AUDIO_DURATION_SEC := 0.5

var payload := {}

# 核心系统
var judge: JudgeSystem
var score: ScoreSystem
var hp: HpSystem
var conductor: Conductor
var chart_duration := 0.0
var track_count := 5
var hand_events: Array = []
var _hand_cursor := 0

# 节点
@onready var music_player: AudioStreamPlayer = $MusicPlayer
var bg_video: VideoStreamPlayer
var note_field: NoteField
@onready var bg_rect: TextureRect = $GameplayBackground
@onready var bg_dim: ColorRect = $BackgroundDim
@onready var hud: Control = $LegacyTopHud
@onready var lbl_score: Label = $LegacyTopHud/Score
@onready var lbl_percent: Label = $LegacyTopHud/Percent
@onready var lbl_combo: Label = $LegacyTopHud/Combo
@onready var combo_img: TextureRect = $LegacyTopHud/ComboImage
@onready var lbl_song: Label = $LegacyTopHud/SongTitle
@onready var lbl_countdown: Label = $LegacyTopHud/Countdown
@onready var lbl_fps: Label = $LegacyTopHud/Fps
@onready var lbl_autoplay: Label = $LegacyTopHud/Autoplay
@onready var hp_bar_fill_tr: TextureRect = $LegacyTopHud/HpFill
@onready var hp_full_fx: TextureRect = $LegacyTopHud/HpFullFx
@onready var _note_field_region: Control = $NoteFieldRegion
var _hp_fill_atlas: AtlasTexture
var _hp_fill_region := Rect2()
var _hp_fill_full_w := 0.0
var _hp_overdrive_tile_width := 1.0
var _hp_overdrive_material: ShaderMaterial
var _hp_overdrive_full_hold := 0.0
var _hp_overdrive_energy_active := false
var _visual_paused := false
var hp_overdrive_energy: HpOverdriveFx
var ready_anim: ReadyAnim
var esc_menu: EscMenu
var spectrum: SpectrumRing
var vinyl: VinylBg
var avatar_frame_fx: TextureRect
var vip_icon: TextureRect
var vip_particles: TextureRect
var stage_spectrum: SpectrumRing
var combo_milestone_fx: ComboMilestoneFx
var shortcut_hint: Label
var combo_group: Control
var combo_digits: Control
var combo_judge: TextureRect
var combo_word: TextureRect
var combo_groups: Array[Control] = []
var combo_digit_groups: Array[Control] = []
var combo_judges: Array[TextureRect] = []
var combo_words: Array[TextureRect] = []
var combo_prefixes: Array[String] = []
var _avatar_fx_frames: Array = []
var _vip_particle_frames: Array = []
var _combo_number_atlas := {}
var _combo_judge_atlas := {}
var _combo_last_value := -1
var _last_combo_milestone := 0
var _combo_anim_t := 0.0
var _hud_base_position := Vector2.ZERO
var _stage_song_scroll := 0.0

var _ended := false
var _finish_wait := 0.0
var _started_play := false
var _audio_finished := false
var _settlement_transition_started := false
var _chart_ready := false
var _load_error := ""
var _loaded_audio_path := ""
var _achievement_sfx_played := {}


func _ready() -> void:
	payload = SceneRouter.take_payload()
	if payload.is_empty():
		var songs: Array = SongLibrary.get_songs("竞速", "club")
		if not songs.is_empty():
			var s: Dictionary = songs[0]
			payload = {"sm": s["sm"], "mp3": s["mp3"], "cover": s["cover"],
				"name": s["name"], "star": s["star"], "mode": "竞速",
				"submode": "club", "sm_key": s["sm_key"],
				"prefer_double": true, "couple": false}

	_resolve_payload_paths()
	_build_ui()
	if await _load_chart():
		_start()
	else:
		_show_load_error(_load_error)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 固定层级：背景 < 黑幕 < 判定区/辅助 UI < 顶部血条 < READY/GO。
	# 黑幕只压暗背景，禁止再盖住判定区和血条。
	bg_rect.z_index = -200
	bg_dim.z_index = -100
	_note_field_region.z_index = 0
	hud.z_index = 100
	_apply_background_mode()
	var submode := str(payload.get("submode", ""))

	note_field = NoteField.new()
	_note_field_region.add_child(note_field)

	conductor = Conductor.new(music_player)
	add_child(conductor)
	conductor.music_started.connect(_on_music_started)
	conductor.music_finished_playing.connect(_on_music_finished_playing)

	# 原版 layout/谱面渲染器_布局.json 顶部 HUD（1280 基准 ×1.5）。
	var bb := AssetLoader.blood_bar_atlas()
	_configure_original_hud(bb)
	# 与选歌/模式页共用同一联网信用标，固定在游戏画面底部正中。
	TopBar.add_bottom_credit(self)

	# 混音模式额外保留左下频谱；右上 Stage 圆盘频谱在所有模式常驻。
	if submode.contains("混音"):
		spectrum = SpectrumRing.new()
		spectrum.position = Vector2(240, 840)
		spectrum.inner_radius = 90.0
		spectrum.max_len = 110.0
		add_child(spectrum)
		spectrum.bind_audio_player(music_player)

	ready_anim = ReadyAnim.new()
	add_child(ready_anim)
	ready_anim.audio_cue.connect(_on_ready_audio_cue)
	if SettingsStore.show_ready_animation:
		# 切场后的首帧立即锁在纯黑状态；谱面解析期间禁止 HUD/判定区抢先闪现。
		ready_anim.prime()
		hud.position = _hud_base_position + Vector2(0, -260.0)
		hud.modulate = Color(1, 1, 1, 0.0)
		note_field.modulate = Color(1, 1, 1, 0.0)
		bg_dim.modulate = Color.WHITE
		bg_dim.color = Color(0, 0, 0, ready_anim.intro_mask_alpha())
	else:
		ready_anim.stop()
		bg_dim.modulate = Color.WHITE

	esc_menu = EscMenu.new(true)
	esc_menu.couple_mode = _is_couple_mode()
	add_child(esc_menu)
	esc_menu.restart_requested.connect(_on_restart)
	esc_menu.quit_requested.connect(_on_quit_song)
	esc_menu.resumed.connect(_on_esc_resumed)
	esc_menu.setting_changed.connect(_on_setting_changed)
	_build_gameplay_assists()
	_refresh_autoplay_badge()


func _hud_tex(parent: Control, node_name: String, texture: Texture2D, rect: Rect2,
		stretch: TextureRect.StretchMode) -> TextureRect:
	var view := TextureRect.new()
	view.name = node_name
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.texture = texture
	view.position = rect.position
	view.custom_minimum_size = rect.size
	view.size = rect.size
	view.stretch_mode = stretch
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(view)
	return view


func _configure_original_hud(bb: Dictionary) -> void:
	_hud_base_position = Vector2.ZERO
	hud.position = _hud_base_position
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var avatar := hud.get_node("Avatar") as TextureRect
	var avatar_path := str(ProfileStore.profile.get("头像文件", ""))
	avatar.texture = AssetLoader.tex(avatar_path)
	if avatar.texture == null:
		avatar.texture = AssetLoader.tex("UI-img/个人中心-个人资料/默认头像.png")
	_set_control_rect(avatar, Rect2(196, 17, 137, 137))
	avatar.pivot_offset = avatar.size * 0.5
	avatar.clip_contents = false
	avatar.modulate = Color.WHITE
	avatar.self_modulate = Color.WHITE
	var avatar_shader := load("res://fx/circular_avatar_mask.gdshader") as Shader
	var avatar_material := ShaderMaterial.new()
	avatar_material.shader = avatar_shader
	avatar.material = avatar_material

	var avatar_frame := hud.get_node("AvatarFrame") as TextureRect
	avatar_frame.texture = bb.get("icon_bg_p1")
	_set_control_rect(avatar_frame, Rect2(165, -18, 205, 205))
	avatar_frame.z_index = 100

	avatar_frame_fx = _ensure_hud_texture("AvatarFrameFx", Rect2(129, -49, 281, 262), 102)
	_avatar_fx_frames = _atlas_frames(
		AssetLoader.atlas("UI-img/游戏界面/血条/头像框特效"), "MovieClip8_", 30)
	if not _avatar_fx_frames.is_empty():
		avatar_frame_fx.texture = _avatar_fx_frames[0]

	vip_icon = _ensure_hud_texture("VipIcon", Rect2(383, 109, 35, 35), 101)
	vip_icon.texture = AssetLoader.tex("UI-img/游戏界面/血条/vip.png")
	vip_particles = _ensure_hud_texture("VipParticles", Rect2(372, 94, 202, 60), 112)
	_vip_particle_frames = _atlas_frames(
		AssetLoader.atlas("UI-img/游戏界面/血条/VIP粒子效果"), "MovieClip10_", 30)
	if not _vip_particle_frames.is_empty():
		vip_particles.texture = _vip_particle_frames[0]

	var hp_frame := hud.get_node("HpFrame") as TextureRect
	hp_frame.texture = bb.get("bb_l_db")
	_set_control_rect(hp_frame, Rect2(164, 2, 1538, 131))
	var player_label := hud.get_node("PlayerLabel") as TextureRect
	player_label.texture = bb.get("label_p1")
	_set_control_rect(player_label, Rect2(322, 94, 81, 60))

	var rank_badge := hud.get_node("RankBadge") as TextureRect
	rank_badge.texture = AssetLoader.tex(ProfileStore.get_rank_asset_path())
	_set_control_rect(rank_badge, Rect2(208, 107, 101, 64))

	var nickname := hud.get_node("Nickname") as Label
	nickname.position = Vector2(438, 113)
	nickname.size = Vector2(270, 48)
	nickname.clip_text = false
	nickname.autowrap_mode = TextServer.AUTOWRAP_OFF
	nickname.add_theme_color_override("font_color", Color(249.0 / 255.0, 1.0, 63.0 / 255.0))
	nickname.add_theme_constant_override("outline_size", 0)
	_apply_gameplay_nickname(str(ProfileStore.profile.get("昵称", "玩家")))

	var score_font := FontVariation.new()
	score_font.base_font = load("res://assets/fonts/fzhei.ttf") as Font
	score_font.variation_embolden = 0.7
	score_font.spacing_glyph = 1
	lbl_score.text = ""
	lbl_score.clip_text = false
	lbl_score.custom_minimum_size = Vector2.ZERO
	lbl_score.position = Vector2(695, 102)
	lbl_score.size = Vector2(157, 60)
	lbl_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_score.add_theme_font_override("font", score_font)
	lbl_score.add_theme_font_size_override("font_size", 28)
	lbl_score.add_theme_color_override("font_color", Color.WHITE)
	lbl_score.add_theme_color_override("font_outline_color", Color(1.0, 110.0 / 255.0, 220.0 / 255.0))
	lbl_score.add_theme_constant_override("outline_size", 2)

	var stage_board := hud.get_node("StageBoard") as TextureRect
	stage_board.texture = AssetLoader.tex("UI-img/游戏界面/血条/board.png")
	_set_control_rect(stage_board, Rect2(1545 + STAGE_GROUP_OFFSET_X, -85, 264, 251))
	stage_board.pivot_offset = stage_board.size * 0.5
	stage_board.z_index = 80
	var stage_text := hud.get_node("StageText") as TextureRect
	stage_text.texture = bb.get("stage")
	_set_control_rect(stage_text, Rect2(872, 79, 88, 23))
	stage_text.z_index = 81
	var stage_number := hud.get_node("StageNumber") as TextureRect
	stage_number.texture = bb.get(str(clampi(GameState.flow.current_round, 0, 9)))
	_set_control_rect(stage_number, Rect2(962, 76, 33, 29))
	stage_number.z_index = 82

	stage_spectrum = SpectrumRing.new()
	stage_spectrum.name = "StageSpectrum"
	stage_spectrum.position = stage_board.position + stage_board.size * 0.5
	stage_spectrum.inner_radius = 104.0
	stage_spectrum.max_len = 44.0
	stage_spectrum.line_width = 2.4
	stage_spectrum.glow_width = 7.0
	stage_spectrum.z_index = 70
	hud.add_child(stage_spectrum)
	stage_spectrum.bind_audio_player(music_player)
	stage_spectrum.set_edge_texture(stage_board.texture, stage_board.size)

	lbl_song.text = str(payload.get("name", ""))
	lbl_song.clip_text = true
	lbl_song.custom_minimum_size = Vector2.ZERO
	lbl_song.position = Vector2(1599 + STAGE_GROUP_OFFSET_X, 9)
	lbl_song.size = Vector2(157, 29)
	lbl_song.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_song.add_theme_font_size_override("font_size", 18)
	lbl_song.add_theme_color_override("font_color", Color(0, 239.0 / 255.0, 251.0 / 255.0))
	lbl_song.add_theme_constant_override("outline_size", 0)
	lbl_song.z_index = 83
	var stars := hud.get_node("Stars") as Label
	stars.position = Vector2(1648 + STAGE_GROUP_OFFSET_X, 94)
	stars.size = Vector2(58, 29)
	stars.text = "%d★" % int(payload.get("star", 0))
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stars.add_theme_font_size_override("font_size", 22)
	stars.add_theme_color_override("font_color", Color(238.0 / 255.0, 244.0 / 255.0, 60.0 / 255.0))
	stars.add_theme_constant_override("outline_size", 0)
	stars.z_index = 83
	var countdown_font := FontVariation.new()
	countdown_font.base_font = load("res://assets/fonts/fzhei.ttf") as Font
	countdown_font.variation_embolden = 0.7
	countdown_font.spacing_glyph = 3
	lbl_countdown.position = Vector2(1617 + STAGE_GROUP_OFFSET_X, 37)
	lbl_countdown.size = Vector2(120, 50)
	lbl_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_countdown.add_theme_font_override("font", countdown_font)
	lbl_countdown.add_theme_font_size_override("font_size", 31)
	lbl_countdown.add_theme_constant_override("outline_size", 0)
	lbl_countdown.z_index = 83

	# 长血条使用原版有效内容区；节点宽度保存完整值，显示时只裁切右侧。
	_set_control_rect(hp_bar_fill_tr, Rect2(283, 26, 1345, 76))
	_hp_fill_atlas = AtlasTexture.new()
	var li_tex: Texture2D = bb.get("bb_d_li")
	if li_tex is AtlasTexture:
		_hp_fill_atlas.atlas = (li_tex as AtlasTexture).atlas
		_hp_fill_region = (li_tex as AtlasTexture).region
	_hp_fill_atlas.region = _hp_fill_region
	_hp_fill_full_w = hp_bar_fill_tr.size.x
	hp_bar_fill_tr.texture = _hp_fill_atlas
	_set_control_rect(hp_full_fx, Rect2(HP_OVERDRIVE_BASE_X, 26, 1249, 67))
	var full_source: Texture2D = bb.get("full_s_l")
	var full_image: Image
	if full_source is AtlasTexture:
		var full_atlas := full_source as AtlasTexture
		var atlas_image := full_atlas.atlas.get_image()
		var region := Rect2i(
			int(full_atlas.region.position.x), int(full_atlas.region.position.y),
			int(full_atlas.region.size.x), int(full_atlas.region.size.y))
		full_image = atlas_image.get_region(region)
	elif full_source != null:
		full_image = full_source.get_image()
	if full_image != null and not full_image.is_empty():
		hp_full_fx.texture = ImageTexture.create_from_image(full_image)
		_hp_overdrive_tile_width = float(full_image.get_width()) \
			* hp_full_fx.size.y / float(maxi(1, full_image.get_height()))
	else:
		hp_full_fx.texture = full_source
		_hp_overdrive_tile_width = hp_full_fx.size.x
	var overdrive_shader := Shader.new()
	overdrive_shader.code = """
shader_type canvas_item;
uniform float phase_pixels = 0.0;
uniform float tile_width_pixels = 1.0;
uniform float view_width_pixels = 1.0;
uniform float pulse = 0.5;
void fragment() {
	// phase 增长时纹理明确向屏幕右侧循环，不再出现来回摆动的错觉。
	float source_x = UV.x * view_width_pixels - phase_pixels;
	float tile_width = max(tile_width_pixels, 1.0);
	float base_u = fract(source_x / tile_width);
	float trail_u1 = fract((source_x + 10.0) / tile_width);
	float trail_u2 = fract((source_x + 24.0) / tile_width);
	vec4 base = texture(TEXTURE, vec2(base_u, UV.y));
	vec4 trail1 = texture(TEXTURE, vec2(trail_u1, UV.y));
	vec4 trail2 = texture(TEXTURE, vec2(trail_u2, UV.y));
	vec4 upper = texture(TEXTURE, vec2(base_u, clamp(UV.y - 0.055, 0.0, 1.0)));
	vec4 lower = texture(TEXTURE, vec2(base_u, clamp(UV.y + 0.055, 0.0, 1.0)));
	float halo = max(max(upper.a, lower.a), max(trail1.a, trail2.a) * 0.72);
	vec3 neon = mix(vec3(1.0, 0.08, 0.46), vec3(0.06, 0.96, 1.0), UV.x);
	float edge = pow(1.0 - abs(UV.y * 2.0 - 1.0), 0.34);
	float scan = pow(max(0.0, sin((UV.x * view_width_pixels + phase_pixels * 2.4) * 0.075)), 16.0);
	float micro = 0.5 + 0.5 * sin(UV.x * view_width_pixels * 0.23 - phase_pixels * 0.31);
	vec3 core = max(base.rgb, max(trail1.rgb * 0.62, trail2.rgb * 0.34));
	core *= 1.26 + pulse * 0.34;
	core += neon * halo * (0.30 + pulse * 0.34);
	core += vec3(0.86, 0.98, 1.0) * scan * edge * (0.34 + pulse * 0.50);
	core += neon.bgr * micro * base.a * 0.10;
	float white_hot = smoothstep(0.42, 0.96, max(max(core.r, core.g), core.b));
	core = mix(core, vec3(1.0, 0.98, 0.94), white_hot * (0.18 + pulse * 0.22));
	float alpha = max(base.a, max(trail1.a * 0.54, max(trail2.a * 0.30, halo * 0.25)));
	alpha = max(alpha, scan * edge * 0.36);
	COLOR = vec4(core, alpha) * COLOR;
}
"""
	_hp_overdrive_material = ShaderMaterial.new()
	_hp_overdrive_material.shader = overdrive_shader
	_hp_overdrive_material.set_shader_parameter("tile_width_pixels", _hp_overdrive_tile_width)
	_hp_overdrive_material.set_shader_parameter("view_width_pixels", hp_full_fx.size.x)
	hp_full_fx.material = _hp_overdrive_material
	hp_full_fx.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	hp_full_fx.z_index = 60
	hp_full_fx.visible = false

	hp_overdrive_energy = HpOverdriveFx.new()
	hp_overdrive_energy.name = "HpOverdriveEnergy"
	hp_overdrive_energy.configure(Rect2(HP_OVERDRIVE_BASE_X, 26, 1249, 67))
	hud.add_child(hp_overdrive_energy)

	_configure_autoplay_badge()
	lbl_fps.visible = false
	lbl_percent.position = Vector2(1086, 94)
	lbl_percent.size = Vector2(190, 54)
	lbl_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_percent.add_theme_font_size_override("font_size", 27)
	lbl_percent.add_theme_color_override("font_color", Color(0.20, 0.96, 1.0))
	lbl_percent.add_theme_color_override("font_outline_color", Color(0.34, 0.02, 0.48, 0.98))
	lbl_percent.add_theme_constant_override("outline_size", 5)
	lbl_percent.add_theme_constant_override("shadow_offset_x", 2)
	lbl_percent.add_theme_constant_override("shadow_offset_y", 3)
	lbl_percent.add_theme_color_override("font_shadow_color", Color(1.0, 0.04, 0.62, 0.48))
	lbl_combo.visible = false
	combo_img.visible = false
	_build_combo_hud()


func _build_gameplay_assists() -> void:
	combo_milestone_fx = ComboMilestoneFx.new()
	combo_milestone_fx.name = "ComboMilestoneFx"
	combo_milestone_fx.level_changed.connect(_on_combo_fx_level_changed)
	combo_milestone_fx.lane_fx_changed.connect(_on_combo_lane_fx_changed)
	combo_milestone_fx.effect_visibility_changed.connect(_on_combo_fx_visibility_changed)
	add_child(combo_milestone_fx)
	shortcut_hint = Label.new()
	shortcut_hint.name = "GameplayShortcutHint"
	shortcut_hint.position = Vector2(1582, 792)
	shortcut_hint.size = Vector2(300, 116)
	shortcut_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	shortcut_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shortcut_hint.add_theme_font_size_override("font_size", 20)
	shortcut_hint.add_theme_color_override("font_color", Color.WHITE)
	shortcut_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.06, 0.98))
	shortcut_hint.add_theme_constant_override("outline_size", 5)
	shortcut_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shortcut_hint.z_index = 204
	add_child(shortcut_hint)
	_refresh_shortcut_hint()


func _on_combo_fx_level_changed(level: int) -> void:
	if note_field != null:
		note_field.set_combo_gold_fx_level(level)


func _on_combo_lane_fx_changed(enabled: bool) -> void:
	if note_field != null and note_field.has_method("set_combo_lane_fx_enabled"):
		note_field.set_combo_lane_fx_enabled(enabled)


func _on_combo_fx_visibility_changed(value: float) -> void:
	if note_field != null and note_field.has_method("set_combo_gold_fx_visibility"):
		note_field.set_combo_gold_fx_visibility(value)


func _refresh_shortcut_hint() -> void:
	if shortcut_hint == null:
		return
	shortcut_hint.text = "F6  自动播放：%s\nF7  击中音效：%s" % [
		"开" if SettingsStore.autoplay else "关",
		"开" if SettingsStore.hit_sound else "关",
	]


func _configure_autoplay_badge() -> void:
	lbl_autoplay.position = Vector2(1736, 172)
	lbl_autoplay.size = Vector2(152, 48)
	lbl_autoplay.custom_minimum_size = lbl_autoplay.size
	lbl_autoplay.pivot_offset = lbl_autoplay.size * 0.5
	lbl_autoplay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_autoplay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_autoplay.z_index = 190
	lbl_autoplay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl_autoplay.add_theme_font_size_override("font_size", 22)
	lbl_autoplay.add_theme_color_override("font_color", Color(1.0, 0.96, 0.72))
	lbl_autoplay.add_theme_color_override("font_outline_color", Color(0.16, 0.0, 0.06, 1.0))
	lbl_autoplay.add_theme_constant_override("outline_size", 5)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.52, 0.02, 0.14, 0.90)
	badge_style.border_color = Color(1.0, 0.35, 0.48, 0.96)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(8)
	badge_style.shadow_color = Color(1.0, 0.02, 0.22, 0.52)
	badge_style.shadow_size = 10
	badge_style.content_margin_left = 10
	badge_style.content_margin_right = 10
	lbl_autoplay.add_theme_stylebox_override("normal", badge_style)
	_refresh_autoplay_badge()


func _refresh_autoplay_badge() -> void:
	var enabled := judge != null and judge.auto_mode
	lbl_autoplay.text = "AUTO PLAY" if enabled else ""
	lbl_autoplay.visible = enabled
	_refresh_shortcut_hint()
	if not enabled:
		lbl_autoplay.scale = Vector2.ONE
		lbl_autoplay.modulate = Color.WHITE


func _apply_gameplay_nickname(value: String) -> void:
	var nickname := hud.get_node_or_null("Nickname") as Label
	if nickname == null:
		return
	var text := value.strip_edges()
	if text.is_empty():
		text = "游客"
	nickname.text = text
	var font_size := 31
	var font := nickname.get_theme_font("font")
	while font_size > 14 \
			and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > 270.0:
		font_size -= 1
	nickname.add_theme_font_size_override("font_size", font_size)


func _set_control_rect(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
	control.custom_minimum_size = rect.size
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ensure_hud_texture(node_name: String, rect: Rect2, layer: int) -> TextureRect:
	var view := hud.get_node_or_null(node_name) as TextureRect
	if view == null:
		view = TextureRect.new()
		view.name = node_name
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hud.add_child(view)
	_set_control_rect(view, rect)
	view.z_index = layer
	return view


func _atlas_frames(atlas: Dictionary, prefix: String, count: int) -> Array:
	var result: Array = []
	for i in count:
		var key := "%s%04d.png" % [prefix, i]
		var frame: Texture2D = atlas.get(key)
		if frame != null:
			result.append(frame)
	return result


func _is_couple_mode() -> bool:
	return bool(payload.get("couple", false)) or str(payload.get("style", "")) == "情侣" \
		or str(payload.get("submode", "")).contains("情侣")


func _build_combo_hud() -> void:
	combo_groups.clear()
	combo_digit_groups.clear()
	combo_judges.clear()
	combo_words.clear()
	combo_prefixes.clear()
	_combo_number_atlas = AssetLoader.couple_number_atlas() if _is_couple_mode() else AssetLoader.number_atlas()
	_combo_judge_atlas = AssetLoader.couple_judge_atlas() if _is_couple_mode() else AssetLoader.judge_atlas()
	# 原版全场只有一套完整计数组。双踏板也不拆成左右两套，
	# 判定字、COMBO 和数字共用屏幕中心锚点进行缩放/回弹。
	var parts := _create_combo_group("ComboGroup", Vector2(960, 540), "pf1")
	combo_groups.append(parts.group)
	combo_digit_groups.append(parts.digits)
	combo_judges.append(parts.judge)
	combo_words.append(parts.word)
	combo_prefixes.append("pf1")
	combo_group = combo_groups[0]
	combo_digits = combo_digit_groups[0]
	combo_judge = combo_judges[0]
	combo_word = combo_words[0]


func _create_combo_group(node_name: String, pos: Vector2, prefix: String) -> Dictionary:
	var group := Control.new()
	group.name = node_name
	group.position = pos
	group.size = Vector2(1, 1)
	group.pivot_offset = Vector2.ZERO
	group.z_index = 200
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(group)
	var judge := _hud_tex(group, "Judge", _combo_texture("judge", "perfect", prefix),
		Rect2(-203, -124, 406, 99), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	judge.z_index = 201
	var word := _hud_tex(group, "ComboWord", _combo_texture("word", "combo", prefix),
		Rect2(-281, -29, 572, 75), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	word.z_index = 202
	var digits := Control.new()
	digits.name = "Digits"
	digits.position = Vector2(0, 49)
	digits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(digits)
	group.visible = false
	return {"group": group, "judge": judge, "word": word, "digits": digits}


func _first_atlas_texture(atlas: Dictionary, candidates: Array[String]) -> Texture2D:
	for candidate in candidates:
		var texture := atlas.get(candidate) as Texture2D
		if texture != null:
			return texture
	return null


func _combo_texture(kind: String, value: String, prefix := "pf1") -> Texture2D:
	match kind:
		"judge":
			return _first_atlas_texture(_combo_judge_atlas, [
				"text_%s_%s" % [prefix, value], "judge_%s" % value, value,
			])
		"word":
			return _first_atlas_texture(_combo_judge_atlas, [
				"text_%s_combo" % prefix, "judge_combo", "combo",
			])
		"digit":
			return _first_atlas_texture(_combo_number_atlas, [
				"text_%s_%s" % [prefix, value], "judge_number_%s" % value,
				"number_%s" % value, value,
			])
	return null


func _combo_texture_for_test(kind: String, value: String) -> Texture2D:
	return _combo_texture(kind, value, "pf1")


func _apply_combo_skin() -> void:
	_combo_number_atlas = AssetLoader.couple_number_atlas() if _is_couple_mode() else AssetLoader.number_atlas()
	_combo_judge_atlas = AssetLoader.couple_judge_atlas() if _is_couple_mode() else AssetLoader.judge_atlas()
	for i in combo_groups.size():
		combo_words[i].texture = _combo_texture("word", "combo", combo_prefixes[i])
		var judge_name := "perfect"
		if score != null and score.last_judge in ["perfect", "cool", "good", "miss"]:
			judge_name = score.last_judge
		combo_judges[i].texture = _combo_texture("judge", judge_name, combo_prefixes[i])
		_rebuild_combo_digits(combo_digit_groups[i],
			score.current_combo if score != null else 0, combo_prefixes[i])


func _mk_label(parent: Control, size: int, pos: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.position = pos
	parent.add_child(l)
	return l


func _apply_brightness() -> void:
	bg_dim.color = Color(0, 0, 0, 0.45 + 0.1 * float(SettingsStore.background_brightness_level))


func _load_gameplay_video_stream(path: String) -> VideoStream:
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as VideoStream
	if not path.is_empty() and ClassDB.class_exists("FFmpegVideoStream"):
		var stream_object = ClassDB.instantiate("FFmpegVideoStream")
		if stream_object != null:
			var native_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") else path
			stream_object.set("file", native_path)
			return stream_object as VideoStream
	return null


func _apply_background_mode() -> void:
	if bg_video != null:
		bg_video.stop()
		bg_video.free()
		bg_video = null
	if vinyl != null:
		vinyl.free()
		vinyl = null

	var mode := str(SettingsStore.background_mode)
	var use_vinyl := mode == "动态背景" \
		and str(SettingsStore.dynamic_background_mode) == "唱片"
	bg_rect.texture = AssetLoader.tex(str(payload.get("cover", ""))) if mode == "图片" else null
	bg_rect.modulate.a = 0.12 if use_vinyl else 1.0

	if mode == "视频":
		var video_stream := _load_gameplay_video_stream(_find_gameplay_video_path())
		if video_stream != null:
			bg_video = VideoStreamPlayer.new()
			bg_video.name = "GameplayVideo"
			bg_video.set_anchors_preset(Control.PRESET_FULL_RECT)
			bg_video.expand = true
			bg_video.loop = true
			bg_video.volume_db = -80.0
			bg_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bg_video.stream = video_stream
			bg_video.z_index = -200
			add_child(bg_video)
			move_child(bg_video, bg_rect.get_index())
			bg_rect.modulate.a = 0.16
			if _started_play:
				bg_video.play()
	elif use_vinyl:
		vinyl = VinylBg.new()
		vinyl.position = Vector2(960, 540)
		vinyl.z_index = -200
		vinyl.setup(str(payload.get("cover", "")))
		add_child(vinyl)
		move_child(vinyl, _note_field_region.get_index())
		if conductor != null and conductor.is_paused():
			vinyl.set_paused(true)
	_apply_brightness()


func background_state_for_test() -> Dictionary:
	return {
		"mode": str(SettingsStore.background_mode),
		"has_video": bg_video != null,
		"has_vinyl": vinyl != null,
		"has_image": bg_rect.texture != null,
	}


func _resolve_payload_paths() -> void:
	for field in ["sm", "mp3", "cover", "video"]:
		var path := str(payload.get(field, ""))
		if not path.is_empty():
			payload[field] = AssetLoader.abs_path(path)


func _clip_events_to_song_duration(source: Array, audio_duration: float,
		timeline: Array = [], offset := 0.0) -> Array:
	if audio_duration <= MIN_VALID_AUDIO_DURATION_SEC:
		return source
	var playable_until := audio_duration + AUDIO_EVENT_GRACE_SEC
	var clipped: Array = []
	for raw_event in source:
		if not raw_event is Dictionary:
			continue
		var start_sec := float((raw_event as Dictionary).get("start_sec", 0.0))
		if not is_finite(start_sec) or start_sec > playable_until:
			continue
		var event: Dictionary = (raw_event as Dictionary).duplicate(true)
		var end_sec := float(event.get("end_sec", start_sec))
		if not is_finite(end_sec):
			continue
		if end_sec > playable_until:
			event["end_sec"] = playable_until
			# 秒边界和拍边界必须一起裁。否则恶意超长 Hold 虽然画面只剩几秒，
			# ChartBuilder 仍可能遍历数百万拍生成 tick，造成主线程卡死。
			if not timeline.is_empty() and event.has("end_beat"):
				var clipped_end_beat := SmParser.sec_to_beat(playable_until + float(offset), timeline)
				event["end_beat"] = maxf(float(event.get("start_beat", clipped_end_beat)),
					clipped_end_beat)
		if float(event.get("end_sec", start_sec)) < start_sec:
			event["end_sec"] = start_sec
			event["end_beat"] = event.get("start_beat", event.get("end_beat", 0.0))
		clipped.append(event)
	return clipped


func _effective_chart_duration(parsed_duration: float, audio_duration: float) -> float:
	return audio_duration if audio_duration > MIN_VALID_AUDIO_DURATION_SEC else parsed_duration


func effective_chart_duration_for_test(parsed_duration: float, audio_duration: float) -> float:
	return _effective_chart_duration(parsed_duration, audio_duration)


func clip_events_to_song_duration_for_test(source: Array, audio_duration: float,
		timeline: Array = [], offset := 0.0) -> Array:
	return _clip_events_to_song_duration(source, audio_duration, timeline, offset)


func _load_chart() -> bool:
	_chart_ready = false
	_load_error = ""
	chart_duration = 0.0
	music_player.stop()
	music_player.stream = null

	var sm_path := str(payload.get("sm", ""))
	if sm_path.is_empty() or not FileAccess.file_exists(sm_path):
		_load_error = "谱面文件缺失：%s" % sm_path
		return false
	var mp3_path := str(payload.get("mp3", ""))
	if not mp3_path.is_empty() and not FileAccess.file_exists(mp3_path):
		_load_error = "歌曲音频缺失：%s" % mp3_path
		return false

	var result: Dictionary
	if bool(payload.get("couple", false)):
		result = SmParser.build_couple_events(sm_path)
		if not str(result.get("error", "")).is_empty() \
				or (result.get("events", []) as Array).is_empty():
			result = SmParser.build_events(sm_path, bool(payload.get("prefer_double", false)))
	else:
		result = SmParser.build_events(sm_path, bool(payload.get("prefer_double", false)),
			str(payload.get("target_charttype", "")))

	var parse_error := str(result.get("error", ""))
	var events: Array = result.get("events", [])
	var parsed_duration := float(result.get("duration", 0.0))
	if not parse_error.is_empty():
		_load_error = "谱面解析失败：%s" % parse_error
		return false
	if events.is_empty():
		_load_error = "谱面没有可玩的音符"
		return false

	track_count = 10 if int(result.get("columns", 5)) >= 10 else 5
	hand_events = result.get("hand_events", [])
	_hand_cursor = 0
	var timeline: Array = result.get("timeline", [])
	var offset := float(result.get("offset", 0.0))

	# 歌曲长度必须以实际音频流为准。DIY JSON 可能用 0.001 BPM 表示终局冻结，
	# 若只信谱面积分时长，会把两三分钟歌曲算成数十小时。
	if not mp3_path.is_empty():
		var prepared = payload.get("audio_stream")
		if prepared is AudioStream:
			music_player.stream = prepared
		elif music_player.stream == null or _loaded_audio_path != mp3_path:
			music_player.stream = await AudioDirector.load_song_stream_async(mp3_path)
		if music_player.stream == null:
			_load_error = "歌曲音频无法解码"
			return false
		_loaded_audio_path = mp3_path
		payload["audio_stream"] = music_player.stream
	var audio_duration := music_player.stream.get_length() if music_player.stream != null else 0.0
	chart_duration = _effective_chart_duration(parsed_duration, audio_duration)
	if chart_duration <= MIN_VALID_AUDIO_DURATION_SEC:
		_load_error = "谱面或音频时长无效"
		return false
	if audio_duration > MIN_VALID_AUDIO_DURATION_SEC:
		events = _clip_events_to_song_duration(events, audio_duration, timeline, offset)
		hand_events = _clip_events_to_song_duration(hand_events, audio_duration, timeline, offset)
		if events.is_empty():
			_load_error = "谱面音符全部超出歌曲音频时长"
			return false
	music_player.volume_db = linear_to_db(0.9 if not SettingsStore.muted else 0.0001)

	var b2s := func(beat: float) -> float:
		return SmParser.beat_to_sec(beat, timeline) - offset
	var chart := ChartBuilder.build(events, b2s)
	var chart_notes: Array = chart.get("notes", [])
	if chart_notes.is_empty():
		_load_error = "谱面转换后没有可玩的音符"
		return false

	judge = JudgeSystem.new()
	judge.auto_mode = SettingsStore.autoplay
	judge.input_offset_sec = float(SettingsStore.chart_offset_ms) / 1000.0
	judge.load_chart(chart_notes)

	score = ScoreSystem.new(int(chart["total_score"]))
	hp = HpSystem.new()

	note_field.setup(track_count, SettingsStore.scroll_speed, _is_couple_mode())
	if combo_milestone_fx != null:
		combo_milestone_fx.configure_track_rect(note_field.combo_fx_track_rect())
	note_field.load_notes(chart_notes)
	note_field.load_hand_events(hand_events)
	note_field.set_grayscale(false)

	_refresh_autoplay_badge()
	_chart_ready = true
	var old_error := get_node_or_null("GameplayLoadError")
	if old_error != null:
		old_error.queue_free()
	return true


func _show_load_error(message: String) -> void:
	var old_error := get_node_or_null("GameplayLoadError")
	if old_error != null:
		old_error.queue_free()
	var label := Label.new()
	label.name = "GameplayLoadError"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.text = "游戏资源加载失败\n%s\n\n按 ESC 或确认键返回选歌" % message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 4095
	add_child(label)


func _start() -> void:
	if not _chart_ready:
		return
	_ended = false
	_finish_wait = 0.0
	_started_play = false
	_audio_finished = false
	_settlement_transition_started = false
	_achievement_sfx_played.clear()
	_combo_anim_t = 0.0
	_combo_last_value = -1
	_last_combo_milestone = 0
	_reset_hp_overdrive_stage()
	_set_visual_pause(false)
	if combo_milestone_fx != null:
		combo_milestone_fx.stop_effect()
	if note_field != null:
		note_field.set_combo_gold_fx_enabled(false, 0.0)
	AudioDirector.stop_bgm()
	var lead_in := 0.0
	if SettingsStore.show_ready_animation and ready_anim != null:
		lead_in = ready_anim.total_duration()
		ready_anim.play()
	else:
		ready_anim.stop()
	if conductor != null:
		conductor.start(lead_in)


func _find_gameplay_video_path() -> String:
	var explicit := str(payload.get("video", "")).strip_edges()
	if not explicit.is_empty() and FileAccess.file_exists(explicit):
		return explicit
	var directory := AssetLoader.abs_path("backmovies/游戏中")
	var candidates: Array[String] = []
	for entry in AssetLoader.list_resources(directory,
			["mp4", "avi", "mpg", "mpeg", "webm", "mov"]):
		candidates.append(directory.path_join(entry))
	if candidates.is_empty():
		return ""
	var seed_text := str(payload.get("sm_key", payload.get("name", "gameplay")))
	var index := int(abs(hash(seed_text))) % candidates.size()
	return candidates[index]


func _on_music_started() -> void:
	_started_play = true
	_audio_finished = false
	if bg_video != null and bg_video.stream != null:
		bg_video.play()


func _on_music_finished_playing() -> void:
	# 只记录自然结束；真正切场景仍由 _process 统一延迟收口，避免同帧状态竞争。
	_audio_finished = true


func _on_ready_audio_cue(cue_name: String, timeline_seconds: float) -> void:
	if cue_name != "ready_sequence":
		return
	AudioDirector.play_sfx(AssetLoader.sound("准备就绪音效"),
		"gameplay.ready_sequence", timeline_seconds)


func _play_achievement_sfx(kind: String) -> bool:
	if kind not in ["full_perfect", "full_combo"] or _achievement_sfx_played.has(kind):
		return false
	var played := AudioDirector.play_sfx(AssetLoader.sound("结算前成就音效"),
		"gameplay.achievement.%s" % kind)
	if played:
		_achievement_sfx_played[kind] = true
	return played


func _stop_gameplay_video() -> void:
	if bg_video != null:
		bg_video.stop()


func _on_setting_changed(key: String) -> void:
	match key:
		"autoplay":
			judge.auto_mode = SettingsStore.autoplay
			_refresh_autoplay_badge()
		"chart_offset":
			judge.input_offset_sec = float(SettingsStore.chart_offset_ms) / 1000.0
		"scroll_speed":
			note_field.scroll_speed_mult = SettingsStore.scroll_speed
		"brightness":
			_apply_brightness()
		"background_mode", "dynamic_background":
			_apply_background_mode()
		"arrow_skin", "arrow_size", "direction_mode":
			# 情侣局强制专用图集；普通局才读取用户皮肤。
			note_field.setup(track_count, SettingsStore.scroll_speed, _is_couple_mode())
			if key == "arrow_skin":
				_apply_combo_skin()
		"hidden_mode", "track_mode":
			# NoteField 每帧读取这两项，无需重建节点和谱面状态。
			pass
		"profile":
			_refresh_profile_hud()
		"hit_sound", "display_mode":
			_refresh_shortcut_hint()


func _refresh_profile_hud() -> void:
	var avatar := hud.get_node_or_null("Avatar") as TextureRect
	if avatar != null:
		var avatar_path := str(ProfileStore.profile.get("头像文件", ""))
		avatar.texture = AssetLoader.tex(avatar_path)
		if avatar.texture == null:
			avatar.texture = AssetLoader.tex("UI-img/个人中心-个人资料/默认头像.png")
	_apply_gameplay_nickname(str(ProfileStore.profile.get("昵称", "玩家")))
	var rank_badge := hud.get_node_or_null("RankBadge") as TextureRect
	if rank_badge != null:
		rank_badge.texture = AssetLoader.tex(ProfileStore.get_rank_asset_path())


func _unhandled_input(event: InputEvent) -> void:
	if not _chart_ready:
		if event.is_action_pressed("ui_cancel") \
				or event.is_action_pressed("ui_accept") \
				or event.is_action_pressed("pedal_confirm"):
			_on_quit_song()
		return
	if _ended or conductor == null or esc_menu == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		if key == KEY_F6:
			_toggle_autoplay_shortcut()
			return
		if key == KEY_F7:
			_toggle_hit_sound_shortcut()
			return
		if key == KEY_SPACE:
			_toggle_space_pause()
			return
	if event.is_action_pressed("ui_cancel"):
		if not esc_menu.is_open():
			conductor.pause()
			_set_visual_pause(true)
			esc_menu.open_menu()
		return
	if conductor.is_paused():
		return
	for track in track_count:
		var action := _track_action(track)
		if event.is_action_pressed(action):
			note_field.flash_receptor(track)
			var reports: Array = judge.handle_press(track, conductor.get_chart_time_raw())
			if not reports.is_empty() and SettingsStore.hit_sound:
				AudioDirector.play_hit_tick()
			_apply_reports(reports)


func _toggle_autoplay_shortcut() -> void:
	SettingsStore.autoplay = not SettingsStore.autoplay
	if judge != null:
		judge.auto_mode = SettingsStore.autoplay
	SettingsStore.save_settings()
	_refresh_autoplay_badge()
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _toggle_hit_sound_shortcut() -> void:
	SettingsStore.hit_sound = not SettingsStore.hit_sound
	SettingsStore.save_settings()
	_refresh_shortcut_hint()
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _toggle_space_pause() -> void:
	# 原版 SPACE 只切换谱面播放状态，不打开 ESC 设置菜单。
	if conductor == null or (esc_menu != null and esc_menu.is_open()):
		return
	if conductor.is_paused():
		conductor.resume()
		_set_visual_pause(false)
	else:
		conductor.pause()
		_set_visual_pause(true)


func _on_esc_resumed() -> void:
	if conductor == null:
		return
	conductor.resume()
	_set_visual_pause(false)


func _set_visual_pause(value: bool) -> void:
	_visual_paused = value
	if bg_video != null:
		bg_video.paused = value
	if stage_spectrum != null:
		stage_spectrum.set_paused(value)
	if spectrum != null:
		spectrum.set_paused(value)
	if vinyl != null:
		vinyl.set_paused(value)
	if hp_overdrive_energy != null:
		hp_overdrive_energy.set_paused(value)
	if note_field != null and note_field.has_method("set_visual_paused"):
		note_field.set_visual_paused(value)
	if combo_milestone_fx != null:
		combo_milestone_fx.set_paused(value)


func _track_action(track: int) -> String:
	if track_count >= 10:
		return ("p2_lane%d" % track) if track < 5 else ("p1_lane%d" % (track - 5))
	return "p1_lane%d" % track


func _is_track_pressed(track: int) -> bool:
	return Input.is_action_pressed(_track_action(track))


func _process(delta: float) -> void:
	if not _chart_ready or conductor == null or score == null or hp == null or note_field == null:
		return
	var raw := conductor.get_chart_time_raw()
	_update_dynamic_hud(raw, delta)
	_update_ready_reveal()
	if _ended or conductor.is_paused():
		return

	var t := conductor.tick()
	raw = conductor.get_chart_time_raw()

	var reports: Array = judge.update(raw, _is_track_pressed)
	_apply_reports(reports)

	# 手键 tap/Hold 特效由 NoteField 按事件起止时间管理；避免 Gameplay 再次单发导致重影。
	note_field.update_field(t, delta)
	if vinyl != null:
		vinyl.on_combo(score.current_combo)
	_update_hud()

	var reached_chart_end := chart_duration > 0.0 and raw >= chart_duration
	var reached_audio_end := _audio_finished and _started_play
	if reached_chart_end or reached_audio_end:
		_finish_wait += delta
		if _finish_wait > 0.45:
			_finish_song(false)
	else:
		_finish_wait = 0.0


func _apply_reports(reports: Array) -> void:
	if reports.is_empty():
		return
	score.settle_all(reports)
	for r in reports:
		note_field.on_report(r)
	var dead := hp.apply_reports(reports)
	note_field.set_grayscale(hp.is_low())
	if dead:
		_finish_song(true)


func _update_ready_reveal() -> void:
	if ready_anim == null or not SettingsStore.show_ready_animation \
			or ready_anim.is_complete():
		hud.position = _hud_base_position
		hud.modulate = Color.WHITE
		note_field.modulate = Color.WHITE
		note_field.scale = Vector2.ONE
		note_field.position = Vector2.ZERO
		bg_dim.modulate = Color.WHITE
		_apply_brightness()
		return

	# 黑幕位于背景之上、判定区和 HUD 之下。它只负责背景明暗，不参与 UI 透明度。
	# 引导组右退时，把 70% 黑幕平滑交还给玩家设置，避免 GAME START 后亮度突然跳变。
	bg_dim.modulate = Color.WHITE
	var configured_dim_alpha := 0.45 + 0.1 * float(SettingsStore.background_brightness_level)
	var intro_dim_alpha := lerpf(ready_anim.intro_mask_alpha(), configured_dim_alpha,
		ready_anim.exit_progress())
	bg_dim.color = Color(0, 0, 0, intro_dim_alpha)

	# 判定区到点硬切显示，出现后始终满亮度。
	var receptor_t := ready_anim.receptor_progress()
	note_field.modulate = Color(1, 1, 1, receptor_t)
	note_field.scale = Vector2.ONE
	note_field.position = Vector2.ZERO

	# 顶部血条组从屏幕外缓慢落下，整个过程中保持原色满亮度。
	var hud_t := ready_anim.hud_progress()
	hud.position = _hud_base_position + Vector2(0, lerpf(-260.0, 0.0, hud_t))
	hud.modulate = Color(1, 1, 1, 1.0 if hud_t > 0.0 else 0.0)


func _hp_wave_offset(chart_time: float) -> float:
	return sin(chart_time * 2.7 * TAU) * 5.0


func _hp_overdrive_offset(chart_time: float) -> float:
	return fposmod(maxf(0.0, chart_time) * HP_OVERDRIVE_SPEED,
		maxf(1.0, _hp_overdrive_tile_width))


func _reset_hp_overdrive_stage() -> void:
	_hp_overdrive_full_hold = 0.0
	_hp_overdrive_energy_active = false
	if hp_overdrive_energy != null:
		hp_overdrive_energy.set_energy_state(false, 0.0, 0.0, 0.0)


func _update_hp_overdrive_stage(delta: float) -> void:
	if hp == null or not hp.is_overdrive():
		_reset_hp_overdrive_stage()
		return
	if _visual_paused:
		return
	_hp_overdrive_full_hold = minf(HP_OVERDRIVE_PARTICLE_DELAY_SEC,
		_hp_overdrive_full_hold + maxf(0.0, delta))
	_hp_overdrive_energy_active = _hp_overdrive_full_hold >= HP_OVERDRIVE_PARTICLE_DELAY_SEC


func hp_overdrive_particle_delay_for_test() -> float:
	return HP_OVERDRIVE_PARTICLE_DELAY_SEC


func hp_overdrive_full_hold_for_test() -> float:
	return _hp_overdrive_full_hold


func hp_overdrive_energy_active_for_test() -> bool:
	return _hp_overdrive_energy_active


func _update_stage_motion(chart_time: float) -> void:
	var stage_board := hud.get_node_or_null("StageBoard") as TextureRect
	var board_rotation := deg_to_rad(fmod(chart_time * STAGE_BOARD_ROTATION_DEG, 360.0))
	if stage_board != null:
		stage_board.rotation = board_rotation
	if stage_spectrum != null:
		# 频谱线角度保持稳定，只让其起始轮廓跟随 board.png 旋转，和原版一致。
		stage_spectrum.rotation = 0.0
		stage_spectrum.set_edge_rotation(board_rotation)
	# 原版短文本居中，长文本按 72px/s 循环。这里按字符窗口做确定性滚动，暂停时随 chart_time 停止。
	var title := str(payload.get("name", ""))
	if title.length() > 12:
		var shift := int(maxf(0.0, chart_time) * 4.0) % title.length()
		lbl_song.text = title.substr(shift) + "   " + title.substr(0, shift)
	else:
		lbl_song.text = title


func _update_dynamic_hud(chart_time: float, delta: float) -> void:
	_update_hp_overdrive_stage(delta)
	var wave := _hp_wave_offset(chart_time)
	hp_bar_fill_tr.position.x = 283.0 + wave
	hp_full_fx.position.x = HP_OVERDRIVE_BASE_X + wave
	var overdrive_phase := _hp_overdrive_offset(chart_time)
	var overdrive_pulse := 0.5 + 0.5 * sin(chart_time * TAU * 1.8)
	if _hp_overdrive_material != null:
		_hp_overdrive_material.set_shader_parameter("phase_pixels", overdrive_phase)
		_hp_overdrive_material.set_shader_parameter("pulse", overdrive_pulse)
	if hp_overdrive_energy != null and hp != null:
		hp_overdrive_energy.set_energy_state(
			_hp_overdrive_energy_active and hp.is_overdrive(), overdrive_phase,
			overdrive_pulse, wave)
	var avatar := hud.get_node_or_null("Avatar") as TextureRect
	if avatar != null:
		avatar.rotation = sin(chart_time * 0.8) * 0.035
	if avatar_frame_fx != null and not _avatar_fx_frames.is_empty():
		avatar_frame_fx.texture = _avatar_fx_frames[int(maxf(0.0, chart_time) * 30.0) % _avatar_fx_frames.size()]
	if vip_particles != null and not _vip_particle_frames.is_empty():
		var cycle := fmod(maxf(0.0, chart_time), 2.0)
		vip_particles.visible = cycle < 0.5
		vip_particles.texture = _vip_particle_frames[int(cycle * 60.0) % _vip_particle_frames.size()]
	_update_stage_motion(chart_time)
	if lbl_autoplay.visible:
		var auto_pulse := 1.0 + 0.035 * (0.5 + 0.5 * sin(chart_time * TAU * 1.6))
		lbl_autoplay.scale = Vector2.ONE * auto_pulse
		lbl_autoplay.modulate.a = 0.82 + 0.18 * (0.5 + 0.5 * sin(chart_time * TAU * 2.1))
	if vinyl != null:
		vinyl.on_combo(score.current_combo if score != null else 0)
	if _combo_anim_t > 0.0:
		_combo_anim_t = maxf(0.0, _combo_anim_t - delta)
		var p := 1.0 - _combo_anim_t / 0.75
		var bounce := 1.0 + sin(minf(1.0, p * 3.0) * PI) * 0.16
		for group in combo_groups:
			group.scale = Vector2.ONE * bounce
			group.modulate.a = clampf(_combo_anim_t / 0.18, 0.0, 1.0) if _combo_anim_t < 0.18 else 1.0
			if _combo_anim_t <= 0.0:
				group.visible = false


func _update_combo_sprite() -> void:
	if combo_groups.is_empty():
		return
	var combo := score.current_combo
	if combo != _combo_last_value:
		var crossed_stage := ComboMilestoneFx.effect_stage_for_combo(combo)
		if combo < 50 and _last_combo_milestone >= 50:
			# 50 Combo 预热阶段也参与缓退，断连后不瞬间撤走箭头金化。
			_last_combo_milestone = 0
			if combo_milestone_fx != null:
				combo_milestone_fx.start_decay()
			elif note_field != null:
				note_field.set_combo_gold_fx_level(0)
				if note_field.has_method("set_combo_lane_fx_enabled"):
					note_field.set_combo_lane_fx_enabled(false)
		elif crossed_stage > _last_combo_milestone:
			_last_combo_milestone = crossed_stage
			if combo_milestone_fx != null:
				if crossed_stage == 50:
					combo_milestone_fx.play_arrow_stage(50, SettingsStore.performance_mode)
				else:
					combo_milestone_fx.play_milestone(crossed_stage, SettingsStore.performance_mode)
			elif note_field != null:
				note_field.set_combo_gold_fx_level(1 if crossed_stage == 50 \
					else clampi(crossed_stage / 100, 1, 3))
				if note_field.has_method("set_combo_lane_fx_enabled"):
					note_field.set_combo_lane_fx_enabled(crossed_stage >= 100)
		_combo_last_value = combo
		if combo >= 2 and not score.last_judge.is_empty():
			_combo_anim_t = 0.75
	var judge_name := score.last_judge if score.last_judge in ["perfect", "cool", "good", "miss"] else "perfect"
	for i in combo_groups.size():
		_rebuild_combo_digits(combo_digit_groups[i], combo, combo_prefixes[i])
		# 自动播放沿用唯一中央计数组：持续显示，并在每次自动命中时继续回弹。
		var show := combo >= 2 and (_combo_anim_t > 0.0 or (judge != null and judge.auto_mode))
		combo_groups[i].visible = show
		combo_words[i].visible = show
		combo_judges[i].visible = show
		combo_judges[i].texture = _combo_texture("judge", judge_name, combo_prefixes[i])


func _rebuild_combo_digits(target: Control, combo: int, prefix: String) -> void:
	if target == null:
		return
	for child in target.get_children():
		target.remove_child(child)
		child.queue_free()
	if combo < 2:
		return
	var keys: Array[String] = ["x"]
	for ch in str(combo):
		keys.append(ch)
	var target_h := 79.0
	var gap := 3.0
	var widths: Array[float] = []
	var total_w := 0.0
	for key in keys:
		var tex: Texture2D = _combo_texture("digit", key, prefix)
		var w := target_h * 0.7
		if tex != null and tex.get_height() > 0:
			w = target_h * float(tex.get_width()) / float(tex.get_height())
		widths.append(w)
		total_w += w
	total_w += gap * maxi(0, keys.size() - 1)
	var x := -total_w * 0.5
	for i in keys.size():
		var view := TextureRect.new()
		view.name = "Digit%d" % i
		view.texture = _combo_texture("digit", keys[i], prefix)
		view.position = Vector2(x, 0)
		view.size = Vector2(widths[i], target_h)
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target.add_child(view)
		x += widths[i] + gap


func _update_hud() -> void:
	if score == null or hp == null:
		return
	lbl_score.text = "%d" % score.current_score
	lbl_percent.text = score.get_percent_string()
	var accuracy := clampf(score.get_percent_value() / 100.0, 0.0, 1.0)
	var percent_color := Color(0.10, 0.88, 1.0).lerp(Color(1.0, 0.16, 0.70), pow(accuracy, 1.35))
	if accuracy >= 0.97:
		percent_color = percent_color.lerp(Color(1.0, 0.92, 0.34), 0.42)
	lbl_percent.add_theme_color_override("font_color", percent_color)
	var raw := conductor.get_chart_time_raw() if conductor != null else 0.0
	var remain := maxi(0, int(ceilf(chart_duration - raw)))
	lbl_countdown.text = "%d:%02d" % [remain / 60, remain % 60]
	_update_combo_sprite()
	var ratio := hp.visible_ratio()
	var region := _hp_fill_region
	region.size.x = _hp_fill_region.size.x * ratio
	_hp_fill_atlas.region = region
	hp_bar_fill_tr.custom_minimum_size.x = _hp_fill_full_w * ratio
	hp_bar_fill_tr.size.x = _hp_fill_full_w * ratio
	if hp.is_low():
		hp_bar_fill_tr.modulate = Color(1.6, 0.4, 0.4)
	else:
		hp_bar_fill_tr.modulate = Color.WHITE
	hp_full_fx.visible = hp.is_overdrive()
	if hp_full_fx.visible:
		hp_full_fx.modulate = Color.WHITE
	if hp_overdrive_energy != null:
		hp_overdrive_energy.visible = _hp_overdrive_energy_active and hp.is_overdrive()


func _on_restart() -> void:
	conductor.stop()
	_reset_hp_overdrive_stage()
	if combo_milestone_fx != null:
		combo_milestone_fx.stop_effect()
	if note_field != null:
		note_field.set_combo_gold_fx_enabled(false, 0.0)
	if await _load_chart():
		_start()
	else:
		_show_load_error(_load_error)


func _on_quit_song() -> void:
	_ended = true
	conductor.stop()
	_reset_hp_overdrive_stage()
	if combo_milestone_fx != null:
		combo_milestone_fx.stop_effect()
	if note_field != null:
		note_field.set_combo_gold_fx_enabled(false, 0.0)
	_stop_gameplay_video()
	SceneRouter.change_to("song_select", GameState.song_select_restore)


## 结束 -> 成就动画（全连/全P）-> 结算
func _finish_song(failed: bool) -> void:
	if _ended:
		return
	_ended = true
	conductor.stop()
	_reset_hp_overdrive_stage()
	if combo_milestone_fx != null:
		combo_milestone_fx.stop_effect()
	if note_field != null:
		note_field.set_combo_gold_fx_enabled(false, 0.0)
	_stop_gameplay_video()

	var percent := score.get_percent_value()
	var grade := Grade.from_percent(percent, failed)
	var flow_result: Dictionary = GameState.flow.settle_round(grade, failed)

	var settle_payload := {
		"曲目名": str(payload.get("name", "")),
		"sm_key": str(payload.get("sm_key", "")),
		"mode": str(payload.get("mode", "竞速")),
		"submode": str(payload.get("submode", "")),
		"cover": str(payload.get("cover", "")),
		"star": int(payload.get("star", 0)),
		"本局最高分": score.current_score,
		"本局最大combo": score.max_combo,
		"歌曲时长秒": chart_duration,
		"百分比": score.get_percent_string(),
		"百分比数值": percent,
		"评级": grade,
		"失败": failed,
		"当前关卡": GameState.flow.current_round,
		"结算后S数": int(flow_result["结算后S数"]),
		"三把S赠送": bool(flow_result["三把S赠送"]),
		"是否赠送第四把": bool(flow_result["是否赠送第四把"]),
		"perfect数": int(score.counts["perfect"]),
		"cool数": int(score.counts["cool"]),
		"good数": int(score.counts["good"]),
		"miss数": int(score.counts["miss"]),
		"是否全perfect": score.is_all_perfect(),
		"是否全连": score.counts["miss"] <= 0 and not failed,
	}

	# 结算前成就动画使用有界等待。即使某个素材/信号异常，也必须在超时后进入结算。
	var anim_kind := ""
	if not failed:
		if score.is_all_perfect():
			anim_kind = "full_perfect"
		elif score.is_full_combo():
			anim_kind = "full_combo"
	if not anim_kind.is_empty():
		await _play_achievement_with_timeout(anim_kind)
	await _transition_to_settlement(settle_payload)


func _play_achievement_with_timeout(anim_kind: String) -> void:
	var anim := AchievementAnim.new()
	anim.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(anim)
	anim.play(anim_kind)
	_play_achievement_sfx(anim_kind)
	var deadline := Time.get_ticks_msec() + int(ACHIEVEMENT_TIMEOUT_SEC * 1000.0)
	while is_instance_valid(anim) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if is_instance_valid(anim):
		push_warning("Gameplay: 成就动画超时，已强制收口并继续结算 -> %s" % anim_kind)
		anim.queue_free()


func _transition_to_settlement(settle_payload: Dictionary) -> void:
	if _settlement_transition_started:
		return
	_settlement_transition_started = true
	var deadline := Time.get_ticks_msec() + int(ROUTER_BUSY_TIMEOUT_SEC * 1000.0)
	while SceneRouter.is_transition_busy() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	if not SceneRouter.is_transition_busy():
		SceneRouter.change_to("settlement", settle_payload)
		return
	# 极端情况下路由锁未释放，直接写入载荷并切结算，不能把玩家永久留在结束画面。
	push_warning("Gameplay: SceneRouter 长时间忙碌，启用结算直切兜底")
	SceneRouter.payload = settle_payload
	get_tree().change_scene_to_file("res://scenes/settlement/settlement.tscn")
