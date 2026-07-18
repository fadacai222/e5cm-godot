extends Control
## 选歌场景 —— 原版布局（config/layout/选歌布局.json）：
## 卡片网格 4×2、外留白120、间距22/39；卡片框=缩略图小.png(256²,内容高247)；
## 封面区 (0.1w,0.055h,0.845w)；信息条占0.35h（星区+歌名+记录行）；
## 角标 NEW/热门/VIP/收藏；底部槽位 收藏夹/设置/ALL；top栏"歌曲选择"；
## 单击卡片/踏板确认=进详情大图页（SongDetail），详情内确认=开始游戏；
## ESC=设置菜单；Backspace/右键=返回玩法选择（详情页内=返回列表）。

const FilterPanelScript := preload("res://scenes/song_select/filter_panel.gd")
const SongCardGlassScript := preload("res://scenes/song_select/song_card_glass.gd")
const NeonSearchIconScript := preload("res://ui/neon_search_icon.gd")

const CARDS_PER_PAGE := 8
const COLS := 4
const ROWS := 2
const TOP_H := 140
const BOTTOM_H := 191
const GRID_OUTER_PAD := 120
const GRID_VERTICAL_PAD := 36
const GAP_X := 22
const GAP_Y := 39
const GRID_SHIFT_RATIO := 0.10
const CARD_FRAME_Y_OFFSET_RATIO := 0.20
const FRAME_VISIBLE_BOTTOM_RATIO := 231.0 / 247.0
const INFO_ALPHA := 118.0 / 255.0
const TOP_BADGE_X := 192.0
const TOP_BADGE_GAP := 13.0
const TOP_BADGE_HEIGHT_RATIO := 0.45
const TOP_BADGE_SCALE := 1.10
const TOP_BADGE_STRETCH_X := 1.30

var songs: Array = []
var page := 0
var selected := 0
var favorites_mode := false
var filter_style := ""
var filter_star := 0
var search_keyword := ""

var _cards: Array = []
var _source_songs: Array = []
@onready var _lbl_page: Label = $PageLabel
@onready var _lbl_filter: Label = $FilterLabel
@onready var _song_grid: ReferenceRect = $SongGrid
@onready var _background: TextureRect = $SongSelectBackground
@onready var _credit_label: Label = $BottomCreditCenter/BottomCreditRow/CreditLabel
var _empty_state: Control
@onready var _preview_player: AudioStreamPlayer = $PreviewPlayer
@onready var _preview_timer: Timer = $PreviewTimer
var esc_menu: EscMenu
var detail: SongDetail
var filter_panel: FilterPanel
var _loading_overlay: Control
var _loading_bar: ProgressBar
var _loading_status: Label
var _loading_percent: Label
var _search_overlay: Control
var _search_input: LineEdit
var _search_result_hint: Label
var _search_progress_bar: ProgressBar
var _search_progress_status: Label
var _search_progress_percent: Label
var _search_submit_button: Button
var _search_clear_button: Button
var _search_cancel_button: Button
var _search_running := false
var _search_generation := 0

var _card_frame: Texture2D
var _star_tex: Texture2D
var _card_w := 0.0
var _card_h := 0.0


func _ready() -> void:
	SharedVideoBackground.end_sequence()
	var restore := SceneRouter.take_payload()
	var bg := AssetLoader.tex_key("背景_选歌")
	_background.texture = bg if bg != null else AssetLoader.tex_key("背景_模式")
	AudioDirector.play_bgm(_song_select_bgm())

	_card_frame = AssetLoader.tex("UI-img/选歌界面资源/缩略图小.png")
	_star_tex = AssetLoader.tex("UI-img/选歌界面资源/小星星/小星星.png")
	_song_grid.visible = false
	_song_grid.position = Vector2(0, TOP_H)
	_song_grid.size = Vector2(1920, 1080 - TOP_H - BOTTOM_H)
	var first_frame := _card_frame_rect(0)
	_card_w = first_frame.size.x
	_card_h = first_frame.size.y

	var top_bar := $TopBar
	_build_mode_badges(top_bar)
	_setup_bottom_actions()
	_build_loading_overlay()
	_build_search_overlay()
	$RoundLabel.text = "第%d把" % GameState.flow.current_round
	_update_credit_label(GameState.credits)
	GameState.credits_changed.connect(_update_credit_label)
	_preview_timer.timeout.connect(_start_preview)

	detail = SongDetail.new()
	detail.prev_requested.connect(_detail_step.bind(-1))
	detail.next_requested.connect(_detail_step.bind(1))
	detail.start_requested.connect(_start_song)
	detail.favorite_toggled.connect(_on_detail_favorite)
	add_child(detail)

	filter_panel = FilterPanelScript.new()
	filter_panel.name = "FilterPanel"
	filter_panel.filter_changed.connect(_on_filter_changed)
	add_child(filter_panel)

	esc_menu = EscMenu.new(false)
	add_child(esc_menu)
	if not SongLibrary.scan_progress.is_connected(_on_song_scan_progress):
		SongLibrary.scan_progress.connect(_on_song_scan_progress)
	if not SongLibrary.search_progress.is_connected(_on_song_search_progress):
		SongLibrary.search_progress.connect(_on_song_search_progress)

	var restore_detail := false
	if restore is Dictionary and not restore.is_empty():
		favorites_mode = bool(restore.get("favorites_mode", false))
		filter_style = str(restore.get("filter_style", "")).strip_edges()
		filter_star = clampi(int(restore.get("filter_star", 0)), 0, 20)
		search_keyword = str(restore.get("search_keyword", "")).strip_edges()
	await _reload_songs_async()
	if restore is Dictionary and not restore.is_empty():
		page = clampi(int(restore.get("page", 0)), 0, maxi(0, _page_count() - 1))
		selected = clampi(int(restore.get("selected", 0)), 0, CARDS_PER_PAGE - 1)
		restore_detail = bool(restore.get("detail", false))
	_build_page()
	_refresh_bottom_labels()
	if restore_detail:
		_refresh_detail(false)


func _song_select_bgm() -> String:
	var mode_name := GameState.sub_mode
	if GameState.big_mode == "DIY" or mode_name.contains("表演"):
		return AssetLoader.sound("音乐_show")
	if mode_name.contains("疯狂"):
		return AssetLoader.sound("音乐_devil")
	if mode_name.contains("混音"):
		return AssetLoader.sound("音乐_remix")
	if mode_name.to_lower().contains("club"):
		return AssetLoader.sound("音乐_club")
	return AssetLoader.sound("音乐_UI")


func _update_credit_label(credits: int) -> void:
	_credit_label.text = "CREDIT：%d/%d" % [maxi(0, credits), GameState.CREDITS_PER_GAME]


func _card_base_rect(index: int) -> Rect2:
	var middle := Rect2(0, TOP_H, 1920, 1080 - TOP_H - BOTTOM_H)
	var area := Rect2(middle.position + Vector2(GRID_OUTER_PAD, GRID_VERTICAL_PAD),
		middle.size - Vector2(GRID_OUTER_PAD * 2, GRID_VERTICAL_PAD * 2))
	var base_w := floori((area.size.x - (COLS - 1) * GAP_X) / float(COLS))
	var base_h := floori((area.size.y - (ROWS - 1) * GAP_Y) / float(ROWS))
	var block_w := COLS * base_w + (COLS - 1) * GAP_X
	var block_h := ROWS * base_h + (ROWS - 1) * GAP_Y
	var start_x := floori(area.get_center().x - block_w * 0.5)
	var start_y := floori(area.get_center().y - block_h * 0.5) - int(area.size.y * GRID_SHIFT_RATIO)
	var row := index / COLS
	var column := index % COLS
	return Rect2(start_x + column * (base_w + GAP_X),
		start_y + row * (base_h + GAP_Y), base_w, base_h)


func _card_frame_rect(index: int) -> Rect2:
	var base := _card_base_rect(index)
	var frame_w := int(base.size.x)
	var frame_h := roundi(frame_w * 0.75)
	var frame_x := floori(base.get_center().x - frame_w * 0.5)
	var frame_y := floori(base.get_center().y - frame_h * 0.5) \
		+ roundi(base.size.y * CARD_FRAME_Y_OFFSET_RATIO)
	return Rect2(frame_x, frame_y, frame_w, frame_h)


func _small_card_layout(card_size: Vector2) -> Dictionary:
	var cover := Rect2(card_size.x * 0.10, card_size.y * 0.055,
		card_size.x * 0.845, card_size.y * 0.94)
	cover.size.x = minf(cover.size.x, card_size.x - cover.position.x)
	cover.size.y = minf(cover.size.y, card_size.y - cover.position.y)
	var visible_bottom := minf(cover.end.y, card_size.y * FRAME_VISIBLE_BOTTOM_RATIO)
	var cover_visible := Rect2(cover.position,
		Vector2(cover.size.x, maxf(1.0, visible_bottom - cover.position.y)))
	var info_h := cover_visible.size.y * 0.35
	var info := Rect2(cover_visible.position + Vector2(0, cover_visible.size.y - info_h),
		Vector2(cover_visible.size.x, info_h))
	var star := Rect2(info.position, Vector2(info.size.x, info.size.y * 0.50))
	var text_pad := maxf(4.0, info.size.x * 0.04)
	var stats_h := maxf(18.0, info.size.y * 0.20)
	var stats := Rect2(info.position + Vector2(text_pad, info.size.y - stats_h - info.size.y * 0.08),
		Vector2(info.size.x - text_pad * 2.0, stats_h))
	var title_y := star.end.y
	var title := Rect2(Vector2(info.position.x + text_pad, title_y),
		Vector2(info.size.x - text_pad * 2.0, maxf(12.0, stats.position.y - title_y)))
	return {"cover": cover, "cover_visible": cover_visible, "info": info,
		"star": star, "title": title, "stats": stats}


func _display_song_name(raw: String) -> String:
	var text := raw.strip_edges().replace("_", " ")
	var regex := RegEx.create_from_string("\\s*[#＃]\\s*\\d+\\s*$")
	return regex.sub(text, "").strip_edges()


func _configure_bottom_action(button: TextureButton, texture_path: String,
		label_text: String, icon_scale := 1.0) -> void:
	button.texture_normal = null
	button.texture_hover = null
	button.texture_pressed = null
	button.ignore_texture_size = true
	for child in button.get_children():
		button.remove_child(child)
		child.free()
	var label_height := 39.0 if not label_text.is_empty() else 0.0
	var icon_area := maxf(36.0, button.size.y - label_height)
	var icon_size := maxf(24.0, minf(button.size.x, icon_area) * icon_scale)
	var icon: Control
	if texture_path.is_empty():
		icon = NeonSearchIconScript.new()
	else:
		var texture_icon := TextureRect.new()
		texture_icon.texture = AssetLoader.tex(texture_path)
		texture_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon = texture_icon
	icon.name = "ActionIcon"
	icon.position = Vector2((button.size.x - icon_size) * 0.5,
		(icon_area - icon_size) * 0.5)
	icon.size = Vector2(icon_size, icon_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	if not label_text.is_empty():
		var label := Label.new()
		label.name = "ActionLabel"
		label.text = label_text
		label.position = Vector2(0, icon_area)
		label.size = Vector2(button.size.x, label_height)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("outline_size", 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)


func _setup_bottom_actions() -> void:
	_configure_bottom_action($FilterButton, "UI-img/选歌界面资源/歌曲分类.png", "歌曲分类")
	_configure_bottom_action($FavoriteButton, "UI-img/选歌界面资源/收藏夹.png", "收藏夹")
	_configure_bottom_action($AllButton, "UI-img/选歌界面资源/all按钮.png", "", 0.60)
	_configure_bottom_action($ReselectButton, "UI-img/选歌界面资源/默认按钮背景.png", "重选模式", 0.62)
	_configure_bottom_action($SearchButton, "", "搜索歌曲", 0.72)
	_configure_bottom_action($JoinPlayerButton, "UI-img/选歌界面资源/1p加入.png",
		"2P加入" if GameState.player_count == 1 else "1P加入")
	_configure_bottom_action($SettingsButton, "UI-img/选歌界面资源/设置.png", "设置")
	$FavoriteButton.pressed.connect(_on_slot_fav)
	$SettingsButton.pressed.connect(_on_slot_settings)
	$FilterButton.pressed.connect(_on_slot_filter)
	$AllButton.pressed.connect(_on_slot_all)
	$ReselectButton.pressed.connect(_reselect_major_mode)
	$SearchButton.pressed.connect(_open_search)
	$JoinPlayerButton.pressed.connect(_on_join_player)


func _set_bottom_label(button: TextureButton, text: String) -> void:
	var label := button.get_node_or_null("ActionLabel") as Label
	if label != null:
		label.text = text


func _refresh_bottom_labels() -> void:
	_set_bottom_label($FilterButton, "筛选中" if not _filter_summary().is_empty() else "歌曲分类")
	_set_bottom_label($FavoriteButton, "退出收藏夹" if favorites_mode else "收藏夹")
	_set_bottom_label($SearchButton, "清除搜索" if not search_keyword.is_empty() else "搜索歌曲")
	_set_bottom_label($JoinPlayerButton, "2P加入" if GameState.player_count == 1 else "1P加入")


func _on_join_player() -> void:
	GameState.player_count = 2 if GameState.player_count == 1 else 1
	_refresh_bottom_labels()
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _on_slot_fav() -> void:
	favorites_mode = not favorites_mode
	page = 0
	selected = 0
	_reload_songs()
	_build_page()
	_refresh_bottom_labels()
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _on_slot_settings() -> void:
	esc_menu.open_menu()


func _on_slot_filter() -> void:
	var source := _current_filter_source()
	filter_panel.open(SongLibrary.available_styles(source), _filter_stars_for_style,
		filter_style, filter_star)
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _on_slot_all() -> void:
	favorites_mode = false
	filter_style = ""
	filter_star = 0
	search_keyword = ""
	page = 0
	selected = 0
	_reload_songs()
	_build_page()
	_refresh_bottom_labels()
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _reload_songs_async() -> void:
	# SongLibrary 是 Autoload。返回选歌时直接复用它的内存列表，不再闪一次“全库加载”。
	if SongLibrary.has_cached_songs(GameState.big_mode, GameState.sub_mode):
		_source_songs = SongLibrary.get_cached_songs(GameState.big_mode, GameState.sub_mode)
		_apply_song_filters()
		_show_loading_overlay(false)
		return
	_show_loading_overlay(true)
	_source_songs = await SongLibrary.get_songs_async(GameState.big_mode, GameState.sub_mode)
	_apply_song_filters()
	_show_loading_overlay(false)


func _reload_songs() -> void:
	if _source_songs.is_empty():
		_source_songs = SongLibrary.get_songs(GameState.big_mode, GameState.sub_mode)
	_apply_song_filters()


func _apply_song_filters() -> void:
	var source := _current_filter_source()
	var filtered := SongLibrary.filter_songs(source, filter_style, filter_star)
	songs = SongLibrary.search_songs(filtered, search_keyword)


func _current_filter_source() -> Array:
	if favorites_mode:
		return _source_songs.filter(func(s): return ProfileStore.favorites.has(str(s["sm_key"])))
	return _source_songs


func _filter_stars_for_style(style: String) -> Array:
	return SongLibrary.available_stars(_current_filter_source(), style)


func _on_filter_changed(style: String, star: int) -> void:
	filter_style = style.strip_edges()
	filter_star = clampi(star, 0, 20)
	page = 0
	selected = 0
	_reload_songs()
	_build_page()
	_refresh_bottom_labels()


func _filter_summary() -> String:
	var parts := []
	if favorites_mode:
		parts.append("收藏夹")
	if not filter_style.is_empty():
		parts.append(filter_style)
	if filter_star > 0:
		parts.append("%d星" % filter_star)
	if not search_keyword.is_empty():
		parts.append("搜索“%s”" % search_keyword)
	return " / ".join(parts)


func _build_loading_overlay() -> void:
	_loading_overlay = Control.new()
	_loading_overlay.name = "SongLoadingOverlay"
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.z_index = 500
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_loading_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.012, 0.035, 0.92)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_overlay.add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(490, 405)
	panel.size = Vector2(940, 270)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.055, 0.10, 0.98)
	style.border_color = Color(0.0, 0.92, 1.0, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.shadow_color = Color(0.74, 0.03, 0.92, 0.48)
	style.shadow_size = 28
	panel.add_theme_stylebox_override("panel", style)
	_loading_overlay.add_child(panel)
	var title := UiKit.label(panel, "COMMUNITY LIBRARY  /  曲库载入", 34,
		Vector2(46, 34), Color(0.80, 0.98, 1.0), 4)
	title.size = Vector2(700, 52)
	_loading_status = UiKit.label(panel, "正在准备曲库…", 24, Vector2(48, 103),
		Color(0.88, 0.92, 1.0), 2)
	_loading_status.size = Vector2(700, 42)
	_loading_bar = ProgressBar.new()
	_loading_bar.position = Vector2(48, 158)
	_loading_bar.size = Vector2(750, 34)
	_loading_bar.min_value = 0
	_loading_bar.max_value = 100
	_loading_bar.value = 0
	_loading_bar.show_percentage = false
	_loading_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_loading_bar)
	_loading_percent = UiKit.label(panel, "0%", 28, Vector2(812, 151),
		Color(1.0, 0.48, 0.92), 3)
	_loading_percent.size = Vector2(100, 48)
	_loading_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var hint := UiKit.label(panel, "首次载入会同时建立歌曲缓存与搜索索引；后续搜索直接查索引。", 18,
		Vector2(48, 210), Color(0.62, 0.72, 0.86), 1)
	hint.size = Vector2(820, 34)
	_loading_overlay.visible = false


func _show_loading_overlay(value: bool) -> void:
	if _loading_overlay == null:
		return
	_loading_overlay.visible = value
	if value:
		_loading_bar.value = 0
		_loading_percent.text = "0%"
		_loading_status.text = "正在准备曲库…"
		move_child(_loading_overlay, get_child_count() - 1)


func _on_song_scan_progress(mode: String, submode: String, current: int, total: int,
		status: String) -> void:
	if mode != GameState.big_mode or submode != GameState.sub_mode or _loading_overlay == null:
		return
	var ratio := clampf(float(current) / float(maxi(1, total)), 0.0, 1.0)
	_loading_bar.value = ratio * 100.0
	_loading_percent.text = "%d%%" % roundi(ratio * 100.0)
	_loading_status.text = status


func _build_search_overlay() -> void:
	_search_overlay = Control.new()
	_search_overlay.name = "SongSearchOverlay"
	_search_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_search_overlay.z_index = 480
	_search_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_search_overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.03, 0.78)
	_search_overlay.add_child(dim)
	var panel := Panel.new()
	panel.position = Vector2(535, 315)
	panel.size = Vector2(850, 440)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.045, 0.09, 0.98)
	style.border_color = Color(0.95, 0.12, 0.78, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.0, 0.8, 1.0, 0.42)
	style.shadow_size = 26
	panel.add_theme_stylebox_override("panel", style)
	_search_overlay.add_child(panel)
	var title := UiKit.label(panel, "搜索歌曲 / SEARCH", 38, Vector2(44, 34),
		Color(0.82, 0.98, 1.0), 4)
	title.size = Vector2(700, 55)
	var subtitle := UiKit.label(panel, "输入歌名或歌手，例如：凤凰传奇", 21,
		Vector2(46, 91), Color(0.68, 0.78, 0.92), 2)
	subtitle.size = Vector2(720, 38)
	_search_input = LineEdit.new()
	_search_input.name = "SearchInput"
	_search_input.position = Vector2(46, 142)
	_search_input.size = Vector2(758, 58)
	_search_input.placeholder_text = "歌名 / 歌手关键词"
	_search_input.clear_button_enabled = true
	_search_input.add_theme_font_size_override("font_size", 25)
	_search_input.text_submitted.connect(_submit_search)
	panel.add_child(_search_input)
	_search_progress_status = UiKit.label(panel, "等待输入关键词", 17, Vector2(46, 214),
		Color(0.64, 0.78, 0.94), 1)
	_search_progress_status.name = "SearchProgressStatus"
	_search_progress_status.size = Vector2(610, 30)
	_search_progress_bar = ProgressBar.new()
	_search_progress_bar.name = "SearchProgressBar"
	_search_progress_bar.position = Vector2(46, 248)
	_search_progress_bar.size = Vector2(674, 24)
	_search_progress_bar.min_value = 0.0
	_search_progress_bar.max_value = 100.0
	_search_progress_bar.value = 0.0
	_search_progress_bar.show_percentage = false
	_search_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var search_bar_bg := StyleBoxFlat.new()
	search_bar_bg.bg_color = Color(0.01, 0.02, 0.07, 0.96)
	search_bar_bg.border_color = Color(0.10, 0.52, 0.78, 0.78)
	search_bar_bg.set_border_width_all(2)
	search_bar_bg.set_corner_radius_all(9)
	var search_bar_fill := StyleBoxFlat.new()
	search_bar_fill.bg_color = Color(0.08, 0.90, 1.0)
	search_bar_fill.border_color = Color(1.0, 0.12, 0.72, 0.92)
	search_bar_fill.set_border_width_all(2)
	search_bar_fill.set_corner_radius_all(8)
	search_bar_fill.shadow_color = Color(0.16, 0.78, 1.0, 0.62)
	search_bar_fill.shadow_size = 9
	_search_progress_bar.add_theme_stylebox_override("background", search_bar_bg)
	_search_progress_bar.add_theme_stylebox_override("fill", search_bar_fill)
	panel.add_child(_search_progress_bar)
	_search_progress_percent = UiKit.label(panel, "0%", 17, Vector2(728, 242),
		Color(0.98, 0.36, 0.86), 2)
	_search_progress_percent.name = "SearchProgressPercent"
	_search_progress_percent.size = Vector2(76, 34)
	_search_progress_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_search_submit_button = Button.new()
	_search_submit_button.name = "SearchSubmitButton"
	_search_submit_button.text = "搜索并跳转"
	_search_submit_button.position = Vector2(46, 302)
	_search_submit_button.size = Vector2(250, 60)
	_search_submit_button.add_theme_font_size_override("font_size", 23)
	_search_submit_button.pressed.connect(func(): _submit_search(_search_input.text))
	panel.add_child(_search_submit_button)
	_search_clear_button = Button.new()
	_search_clear_button.name = "SearchClearButton"
	_search_clear_button.text = "清除搜索"
	_search_clear_button.position = Vector2(312, 302)
	_search_clear_button.size = Vector2(210, 60)
	_search_clear_button.add_theme_font_size_override("font_size", 23)
	_search_clear_button.pressed.connect(_clear_search)
	panel.add_child(_search_clear_button)
	_search_cancel_button = Button.new()
	_search_cancel_button.name = "SearchCancelButton"
	_search_cancel_button.text = "取消"
	_search_cancel_button.position = Vector2(538, 302)
	_search_cancel_button.size = Vector2(266, 60)
	_search_cancel_button.add_theme_font_size_override("font_size", 23)
	_search_cancel_button.pressed.connect(_cancel_or_close_search)
	panel.add_child(_search_cancel_button)
	_search_result_hint = UiKit.label(panel, "", 18, Vector2(46, 382),
		Color(1.0, 0.72, 0.90), 1)
	_search_result_hint.size = Vector2(758, 34)
	_search_overlay.visible = false


func _open_search() -> void:
	if not search_keyword.is_empty():
		_clear_search()
		return
	_search_input.text = search_keyword
	_search_result_hint.text = "当前曲库共 %d 首可搜索" % _source_songs.size()
	_search_progress_bar.value = 0.0
	_search_progress_percent.text = "0%"
	_search_progress_status.text = "等待输入关键词"
	_search_cancel_button.text = "取消"
	_set_search_controls_enabled(true)
	_search_overlay.visible = true
	move_child(_search_overlay, get_child_count() - 1)
	_search_input.grab_focus()
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _close_search() -> void:
	if _search_running:
		return
	_search_overlay.visible = false


func _cancel_or_close_search() -> void:
	if _search_running:
		_search_generation += 1
		_search_running = false
		_search_progress_status.text = "搜索已取消"
		_search_cancel_button.text = "关闭"
		_set_search_controls_enabled(true)
		return
	_close_search()


func _set_search_controls_enabled(enabled: bool) -> void:
	if _search_input != null:
		_search_input.editable = enabled
	if _search_submit_button != null:
		_search_submit_button.disabled = not enabled
	if _search_clear_button != null:
		_search_clear_button.disabled = not enabled


func _search_cancelled(generation: int) -> bool:
	return generation != _search_generation or not _search_running \
		or not is_instance_valid(_search_overlay)


func _on_song_search_progress(current: int, total: int, status: String) -> void:
	if not _search_running or _search_progress_bar == null:
		return
	var ratio := clampf(float(current) / float(maxi(1, total)), 0.0, 1.0)
	_search_progress_bar.value = ratio * 100.0
	_search_progress_percent.text = "%d%%" % roundi(ratio * 100.0)
	_search_progress_status.text = status


func _clear_search() -> void:
	search_keyword = ""
	page = 0
	selected = 0
	_reload_songs()
	_build_page()
	_refresh_bottom_labels()
	_close_search()


func _submit_search(value: String) -> void:
	if _search_running:
		return
	var keyword := value.strip_edges().substr(0, 64)
	if keyword.is_empty():
		_clear_search()
		return
	_search_running = true
	_search_generation += 1
	var generation := _search_generation
	_set_search_controls_enabled(false)
	_search_cancel_button.text = "取消搜索"
	_search_progress_bar.value = 0.0
	_search_progress_percent.text = "0%"
	_search_progress_status.text = "正在查询已建立的歌曲索引"
	_search_result_hint.text = ""
	var filtered := SongLibrary.filter_songs(_current_filter_source(), filter_style, filter_star)
	var found: Array = await SongLibrary.search_songs_async(filtered, keyword, 8,
		_search_cancelled.bind(generation))
	if _search_cancelled(generation):
		return
	search_keyword = keyword
	songs = found
	page = 0
	selected = 0
	_search_running = false
	_set_search_controls_enabled(true)
	_search_cancel_button.text = "关闭"
	_build_page()
	_refresh_bottom_labels()
	_search_result_hint.text = "找到 %d 首匹配歌曲" % songs.size()
	_search_progress_status.text = "搜索完成"
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	_close_search()


func _normalize_big_mode(raw: String) -> String:
	var text := raw.strip_edges()
	var lower := text.to_lower()
	if text.contains("花") or lower.contains("fancy"):
		return "花式"
	if text.contains("竞") or lower.contains("speed") or lower.contains("race"):
		return "竞速"
	if text.contains("派对") or lower.contains("party"):
		return "派对"
	if lower.contains("diy"):
		return "diy"
	if lower.contains("wef"):
		return "wef"
	return text


func _normalize_submode(raw: String) -> String:
	var text := raw.strip_edges()
	var lower := text.to_lower()
	if text.contains("表演") or lower.contains("show"):
		return "表演"
	if text.contains("学习") or lower.contains("learn"):
		return "学习"
	if text.contains("疯狂") or lower.contains("crazy"):
		return "疯狂"
	if text.contains("混音") or lower.contains("mix"):
		return "混音"
	if text.contains("情侣") or lower.contains("lover"):
		return "情侣"
	if text.contains("双踏板") or lower.contains("club"):
		return "club"
	return text


func _build_mode_badges(top_bar: Control) -> void:
	var mode_key := _normalize_big_mode(GameState.big_mode)
	var sub_key := _normalize_submode(GameState.sub_mode)
	var mode_paths := {
		"花式": "UI-img/选歌界面资源/top栏小标题/大模式-花式.png",
		"竞速": "UI-img/选歌界面资源/top栏小标题/大模式-竞速.png",
		"派对": "UI-img/选歌界面资源/top栏小标题/大模式-派对模式.png",
		"diy": "UI-img/选歌界面资源/top栏小标题/大模式-diy.png",
		"wef": "UI-img/选歌界面资源/top栏小标题/大模式-wef.png",
	}
	var sub_paths := {
		"表演": "UI-img/选歌界面资源/top栏小标题/表演模式.png",
		"学习": "UI-img/选歌界面资源/top栏小标题/学习模式.png",
		"疯狂": "UI-img/选歌界面资源/top栏小标题/疯狂模式.png",
		"混音": "UI-img/选歌界面资源/top栏小标题/混音模式.png",
		"情侣": "UI-img/选歌界面资源/top栏小标题/情侣模式.png",
		"club": "UI-img/选歌界面资源/top栏小标题/双踏板模式.png",
	}
	var x := TOP_BADGE_X
	x += _add_top_badge(top_bar, "ModeBadge", str(mode_paths.get(mode_key, "")),
		mode_key, Vector2(x, 0)) + TOP_BADGE_GAP
	_add_top_badge(top_bar, "SubmodeBadge", str(sub_paths.get(sub_key, "")),
		sub_key, Vector2(x, 0))


func _add_top_badge(parent: Control, node_name: String, path: String,
		fallback_text: String, pos: Vector2) -> float:
	var holder := parent.get_node_or_null(node_name) as Control
	if holder == null:
		holder = Control.new()
		holder.name = node_name
		parent.add_child(holder)
	for child in holder.get_children():
		holder.remove_child(child)
		child.free()
	holder.position = pos
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture := AssetLoader.tex(path) if not path.is_empty() else null
	var height := maxf(1.0, (parent.size.y if parent.size.y > 0.0 else 150.0) \
		* TOP_BADGE_HEIGHT_RATIO * TOP_BADGE_SCALE)
	var width := 150.0
	if texture != null and texture.get_height() > 0:
		# 原版先按高度等比 fit，再只把宽度拉长 1.30 倍。
		width = height * float(texture.get_width()) / float(texture.get_height()) \
			* TOP_BADGE_STRETCH_X
		var view := TextureRect.new()
		view.name = "BadgeTexture"
		view.texture = texture
		view.size = Vector2(width, height)
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_SCALE
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(view)
	else:
		var label := UiKit.label(holder, fallback_text, 25, Vector2.ZERO, Color.WHITE, 4)
		label.name = "BadgeFallback"
		label.size = Vector2(width, height)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.size = Vector2(width, height)
	return width


func _page_count() -> int:
	return maxi(1, int(ceilf(float(songs.size()) / CARDS_PER_PAGE)))


func _page_songs() -> Array:
	var start := page * CARDS_PER_PAGE
	return songs.slice(start, mini(start + CARDS_PER_PAGE, songs.size()))


func _raise_runtime_overlays() -> void:
	# 卡片会在运行时反复 add_child；z_index 只决定绘制，GUI 命中仍受兄弟顺序影响。
	# 始终把弹层放到最后，保证它们先于缩略图接收鼠标。
	for overlay in [detail, filter_panel, esc_menu, _search_overlay, _loading_overlay]:
		if is_instance_valid(overlay) and overlay.get_parent() == self:
			move_child(overlay, get_child_count() - 1)


func _build_page() -> void:
	for c in _cards:
		if is_instance_valid(c):
			if c.get_parent() == self:
				remove_child(c)
			c.queue_free()
	_cards.clear()
	if is_instance_valid(_empty_state):
		remove_child(_empty_state)
		_empty_state.queue_free()
		_empty_state = null

	var page_songs := _page_songs()
	var visible_cover_paths: Array[String] = []
	if page_songs.is_empty():
		_build_empty_state()
		_lbl_page.text = "0 / 0"
		var empty_summary := _filter_summary()
		_lbl_filter.text = "无匹配结果：%s" % empty_summary if not empty_summary.is_empty() else "当前目录没有歌曲"
		selected = 0
		_preview_timer.stop()
		_raise_runtime_overlays()
		return
	for i in page_songs.size():
		var s: Dictionary = page_songs[i]
		var card := Control.new()
		card.name = "SongCard%d" % i
		var frame_rect := _card_frame_rect(i)
		card.position = frame_rect.position
		card.size = frame_rect.size
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.clip_contents = false
		add_child(card)
		var layout := _small_card_layout(card.size)
		var cover_rect: Rect2 = layout.cover
		var cover_visible: Rect2 = layout.cover_visible
		var info_rect: Rect2 = layout.info
		var star_rect: Rect2 = layout.star
		var title_rect: Rect2 = layout.title
		var stats_rect: Rect2 = layout.stats

		var underlay = SongCardGlassScript.new()
		underlay.name = "HoverUnderlay"
		underlay.layer_mode = 0
		underlay.position = Vector2.ZERO
		underlay.size = card.size
		card.add_child(underlay)

		# 封面按原版 0.94 高度绘制，但裁切到框体设计像素 231/247。
		var cover_clip := Control.new()
		cover_clip.name = "CoverClip"
		cover_clip.position = cover_visible.position
		cover_clip.size = cover_visible.size
		cover_clip.clip_contents = true
		cover_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cover_clip)
		var cover := TextureRect.new()
		cover.name = "Cover"
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var cover_path := str(s["cover"])
		visible_cover_paths.append(cover_path)
		cover.texture = AssetLoader.tex(cover_path)
		cover.position = Vector2.ZERO
		cover.custom_minimum_size = cover_visible.size
		cover.size = cover_visible.size
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cover_clip.add_child(cover)
		_build_card_mode_badge(card, str(s.get("style", "")))

		# 原版信息条为 118/255 透明黑，不是接近全黑的实心底。
		var info_glass := ColorRect.new()
		info_glass.name = "InfoGlass"
		info_glass.color = Color(0, 0, 0, INFO_ALPHA)
		info_glass.position = info_rect.position
		info_glass.size = info_rect.size
		info_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(info_glass)

		# 原版小图规则：<=10 单排；>10 时下排固定 10 颗、上排显示溢出数量，
		# 并按素材真实宽高比自动缩小到星区内，不能用“×N”替代。
		_build_card_stars(card, star_rect, int(s["star"]))

		# 歌名居中，并按原版去掉下划线与尾部 #数字。
		var name_lbl := UiKit.label(card, _display_song_name(str(s["name"])),
			maxi(16, int(title_rect.size.y * 0.78)), title_rect.position, Color.WHITE, 3)
		name_lbl.name = "SongName"
		name_lbl.size = title_rect.size
		name_lbl.clip_text = true
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var record := ProfileStore.get_song_record(str(s["sm_key"]))
		var stat_font := maxi(13, int(stats_rect.size.y * 0.80))
		var play_label := UiKit.label(card, "游玩次数:%d" % int(record.get("游玩次数", 0)),
			stat_font, stats_rect.position, Color(0.78, 0.87, 1.0), 2)
		play_label.name = "PlayCount"
		play_label.size = Vector2(stats_rect.size.x * 0.54, stats_rect.size.y)
		play_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		play_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bpm_value := float(s.get("bpm", 0.0))
		var bpm_text := "BPM:?" if bpm_value <= 0.0 else "BPM:%d" % int(roundf(bpm_value))
		var bpm_label := UiKit.label(card, bpm_text, stat_font,
			Vector2(stats_rect.position.x + stats_rect.size.x * 0.46, stats_rect.position.y),
			Color.WHITE, 2)
		bpm_label.name = "Bpm"
		bpm_label.size = Vector2(stats_rect.size.x * 0.54, stats_rect.size.y)
		bpm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		bpm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bpm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# 框图最后覆盖内容边缘，保持原版玻璃边框层级。
		var frame := TextureRect.new()
		frame.name = "Frame"
		frame.texture = _card_frame
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(frame)

		# 角标：NEW（左上）/ 热门（右上）/ VIP / 收藏
		if bool(s.get("is_new", false)):
			_badge(card, "UI-img/选歌界面资源/NEW绿色.png", Vector2(_card_w * 0.06, 2), _card_w * 0.2)
		var record_hot := int(record["游玩次数"]) >= 10
		if record_hot:
			_badge(card, "UI-img/选歌界面资源/热门.png", Vector2(_card_w * 0.72, 2), _card_w * 0.2)
		if ProfileStore.favorites.has(str(s["sm_key"])):
			_badge(card, "UI-img/选歌界面资源/添加收藏.png", Vector2(_card_w * 0.82, _card_h * 0.52), _card_w * 0.14)

		var glass = SongCardGlassScript.new()
		glass.name = "SelectionGlass"
		glass.layer_mode = 1
		glass.position = Vector2.ZERO
		glass.size = card.size
		card.add_child(glass)
		card.set_meta("hovered", false)
		card.mouse_entered.connect(_on_card_hover.bind(i, true))
		card.mouse_exited.connect(_on_card_hover.bind(i, false))
		card.gui_input.connect(_on_card_input.bind(i))
		_cards.append(card)

	_lbl_page.text = "%d / %d" % [page + 1, _page_count()]
	var summary := _filter_summary()
	_lbl_filter.text = "筛选：%s（%d首）" % [summary, songs.size()] if not summary.is_empty() else ""
	selected = clampi(selected, 0, maxi(0, page_songs.size() - 1))
	_apply_selection()
	# 只保留当前页和最近翻过页面的少量封面，避免浏览曲库后内存持续增长。
	AssetLoader.trim_song_texture_cache(visible_cover_paths)
	_raise_runtime_overlays()


func _build_card_mode_badge(card: Control, style: String) -> void:
	var paths := {
		"学习": "UI-img/选歌界面资源/top栏小标题/学习模式.png",
		"表演": "UI-img/选歌界面资源/top栏小标题/表演模式.png",
		"疯狂": "UI-img/选歌界面资源/top栏小标题/疯狂模式.png",
		"混音": "UI-img/选歌界面资源/top栏小标题/混音模式.png",
		"情侣": "UI-img/选歌界面资源/top栏小标题/情侣模式.png",
		"双踏板": "UI-img/选歌界面资源/top栏小标题/双踏板模式.png",
	}
	var texture := AssetLoader.tex(str(paths.get(style, "")))
	if texture == null:
		return
	var badge := TextureRect.new()
	badge.name = "ModeBadge"
	badge.texture = texture
	badge.position = Vector2(16, 14)
	badge.size = Vector2(132, 38)
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_SCALE
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 8
	card.add_child(badge)


func _build_card_stars(card: Control, region: Rect2, star_count: int) -> void:
	if card == null or _star_tex == null or star_count <= 0:
		return
	var texture_size := _star_tex.get_size()
	var texture_ratio := texture_size.x / maxf(1.0, texture_size.y)
	var top_count := mini(star_count, 10)
	var bottom_count := 0
	if star_count > 10:
		top_count = star_count - 10
		bottom_count = 10
	var rows := 2 if bottom_count > 0 else 1
	var star_h := maxf(6.0, region.size.y * 0.42)
	var star_w := star_h * texture_ratio
	var gap := maxf(1.0, star_w * 0.10)
	var row_gap := maxf(0.0, star_h * 0.35)
	for _attempt in 18:
		var top_width := top_count * star_w + maxi(0, top_count - 1) * gap
		var bottom_width := bottom_count * star_w + maxi(0, bottom_count - 1) * gap
		var total_height := star_h if rows == 1 else star_h * 2.0 + row_gap
		if maxf(top_width, bottom_width) <= region.size.x and total_height <= region.size.y:
			break
		star_h = maxf(3.0, star_h * 0.92)
		star_w = star_h * texture_ratio
		gap = maxf(1.0, star_w * 0.10)
		row_gap = maxf(0.0, star_h * 0.35)
	var total_height := star_h if rows == 1 else star_h * 2.0 + row_gap
	var y := region.position.y + (region.size.y - total_height) * 0.5
	var star_index := 0
	star_index = _add_card_star_row(card, region, top_count, y, star_w, star_h, gap, star_index)
	if bottom_count > 0:
		_add_card_star_row(card, region, bottom_count, y + star_h + row_gap,
			star_w, star_h, gap, star_index)


func _add_card_star_row(card: Control, region: Rect2, count: int, y: float,
		star_w: float, star_h: float, gap: float, start_index: int) -> int:
	if count <= 0:
		return start_index
	var row_width := count * star_w + maxi(0, count - 1) * gap
	var x := region.get_center().x - row_width * 0.5
	for i in count:
		var star := TextureRect.new()
		star.name = "Star%d" % (start_index + i)
		star.texture = _star_tex
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.position = Vector2(x + i * (star_w + gap), y)
		star.size = Vector2(star_w, star_h)
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(star)
	return start_index + count


func _build_empty_state() -> void:
	_empty_state = Panel.new()
	_empty_state.name = "SongEmptyState"
	_empty_state.size = Vector2(900, 430)
	_empty_state.position = _song_grid.position + (_song_grid.size - _empty_state.size) * 0.5
	_empty_state.z_index = 25
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.055, 0.095, 0.94)
	style.border_color = Color(0.18, 0.62, 0.9, 0.82)
	style.set_border_width_all(3)
	style.set_corner_radius_all(16)
	_empty_state.add_theme_stylebox_override("panel", style)
	add_child(_empty_state)
	var title := UiKit.label(_empty_state, "没有找到符合条件的歌曲", 38,
		Vector2(140, 92), Color(0.92, 0.96, 1.0), 5)
	title.size = Vector2(620, 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var detail_label := UiKit.label(_empty_state, "可清除收藏夹、玩法和星级筛选后返回全部歌曲。", 23,
		Vector2(120, 182), Color(0.7, 0.8, 0.9), 3)
	detail_label.size = Vector2(660, 50)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var reset := Button.new()
	reset.name = "ResetFilters"
	reset.text = "显示全部歌曲"
	reset.position = Vector2(300, 280)
	reset.size = Vector2(300, 72)
	reset.add_theme_font_size_override("font_size", 26)
	reset.pressed.connect(_on_slot_all)
	_empty_state.add_child(reset)


func _badge(parent: Control, rel: String, pos: Vector2, w: float) -> void:
	var tex := AssetLoader.tex(rel)
	if tex == null:
		return
	var t := TextureRect.new()
	t.texture = tex
	t.position = pos
	var h := w * float(tex.get_height()) / float(tex.get_width())
	t.custom_minimum_size = Vector2(w, h)
	t.size = Vector2(w, h)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)


func _on_card_hover(index: int, hovered: bool) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card := _cards[index] as Control
	card.set_meta("hovered", hovered)
	_apply_card_glass(index)


func _apply_card_glass(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card := _cards[index] as Control
	var is_selected := index == selected
	var is_hovered := bool(card.get_meta("hovered", false))
	var underlay := card.get_node_or_null("HoverUnderlay")
	var glass := card.get_node_or_null("SelectionGlass")
	if underlay != null and underlay.has_method("set_state"):
		underlay.call("set_state", is_selected, is_hovered)
	if glass != null and glass.has_method("set_state"):
		glass.call("set_state", is_selected, is_hovered)


func _apply_selection() -> void:
	for i in _cards.size():
		_apply_card_glass(i)
	_preview_timer.start(0.35)


func _start_preview() -> void:
	var page_songs := _page_songs()
	if selected >= page_songs.size():
		return
	var s: Dictionary = page_songs[selected]
	var mp3 := str(s["mp3"])
	if not FileAccess.file_exists(mp3):
		return
	var f := FileAccess.open(mp3, FileAccess.READ)
	var stream := AudioStreamMP3.new()
	stream.data = f.get_buffer(f.get_length())
	_preview_player.stream = stream
	var meta := SmParser.parse_meta(str(s["sm"]))
	var sample_start := float(meta.get("sample_start", 0.0))
	if is_nan(sample_start) or sample_start < 0.0:
		sample_start = 0.0
	AudioDirector.stop_bgm()
	_preview_player.play(sample_start)


func _on_card_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected = i
		_apply_selection()
		AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
		_refresh_detail(true)


## 打开/刷新详情大图页（对应旧 进入详情_原始索引 / _详情切到视图索引）
func _refresh_detail(animate: bool) -> void:
	var page_songs := _page_songs()
	if selected >= page_songs.size():
		return
	var s: Dictionary = page_songs[selected]
	var key := str(s["sm_key"])
	detail.show_song(s, ProfileStore.get_song_record(key),
		ProfileStore.favorites.has(key), animate)


func _detail_step(step: int) -> void:
	_move_selection(step)
	_refresh_detail(false)


func _on_detail_favorite() -> void:
	_toggle_favorite()
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	_refresh_detail(false)


func _move_selection(step: int) -> void:
	var count := _page_songs().size()
	if count == 0:
		return
	var next := selected + step
	if next < 0:
		_flip_page(-1)
		selected = _page_songs().size() - 1
		_apply_selection()
		return
	if next >= count:
		_flip_page(1)
		selected = 0
		_apply_selection()
		return
	selected = next
	_apply_selection()
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _flip_page(step: int) -> void:
	page = (page + step + _page_count()) % _page_count()
	_build_page()


func _toggle_favorite() -> void:
	var page_songs := _page_songs()
	if selected >= page_songs.size():
		return
	ProfileStore.toggle_favorite(str(page_songs[selected]["sm_key"]))
	_build_page()


func _start_song() -> void:
	var page_songs := _page_songs()
	if selected >= page_songs.size():
		return
	var s: Dictionary = page_songs[selected]
	_preview_player.stop()
	# 原版大图二次确认只播放 backsound/开始游戏.mp3，不复用普通按钮音。
	AudioDirector.play_sfx(AssetLoader.sound("开始游戏"), "song_select.start_game")

	GameState.song_select_restore = {
		"page": page, "selected": selected, "favorites_mode": favorites_mode,
		"detail": detail.is_open(), "filter_style": filter_style, "filter_star": filter_star,
		"search_keyword": search_keyword,
	}
	var sub := GameState.sub_mode
	var style := str(s.get("style", ""))
	var couple := bool(s.get("couple", false)) or sub.contains("情侣") or style == "情侣"
	var is_json := str(s.get("chart_format", "")).to_lower() == "json" \
		or str(s.get("sm", "")).to_lower().ends_with(".json")
	# JSON 只相信谱面真实玩家/模式元数据，不能因当前 2P UI 或 DIY 大模式被强制成双踏。
	var prefer_double := int(s.get("columns", 5)) >= 10 if is_json else (
		sub.to_lower().contains("club") or style == "双踏板" or couple \
		or GameState.player_count >= 2)
	SceneRouter.change_to("loading", {
		"sm": s["sm"], "mp3": s["mp3"], "cover": s["cover"], "name": s["name"],
		"star": s["star"], "mode": GameState.big_mode, "submode": sub,
		"sm_key": s["sm_key"], "prefer_double": prefer_double, "couple": couple,
		"target_charttype": str(s.get("charttype", "")), "style": style,
	})


func _back_to_submode() -> void:
	_preview_player.stop()
	AudioDirector.play_bgm(AssetLoader.sound("音乐_UI"))
	SceneRouter.change_to("submode_select")


func _reselect_major_mode() -> void:
	_preview_player.stop()
	GameState.big_mode = ""
	GameState.sub_mode = ""
	GameState.song_select_restore = {}
	AudioDirector.play_bgm(AssetLoader.sound("音乐_UI"))
	SceneRouter.change_to("mode_select")


func reselect_target_for_test() -> String:
	return "mode_select"


func _unhandled_input(event: InputEvent) -> void:
	if filter_panel.is_open():
		if event.is_action_pressed("ui_cancel"):
			filter_panel.close()
		return
	if esc_menu.is_open():
		return
	if detail.is_open():
		if event.is_action_pressed("pedal_left"):
			_detail_step(-1)
		elif event.is_action_pressed("pedal_right"):
			_detail_step(1)
		elif event.is_action_pressed("pedal_confirm"):
			_start_song()
		elif event.is_action_pressed("ui_cancel"):
			detail.close()
		elif event is InputEventKey and event.pressed and not event.echo:
			match event.keycode:
				KEY_V:
					_on_detail_favorite()
				KEY_BACKSPACE:
					detail.close()
		return
	if event.is_action_pressed("pedal_left"):
		_move_selection(-1)
	elif event.is_action_pressed("pedal_right"):
		_move_selection(1)
	elif event.is_action_pressed("pedal_confirm"):
		_refresh_detail(true)
	elif event.is_action_pressed("ui_cancel"):
		esc_menu.open_menu()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_V:
				_toggle_favorite()
			KEY_BACKSPACE:
				_back_to_submode()
			KEY_F1:
				_on_slot_fav()
			KEY_F2:
				_on_slot_filter()
			KEY_PAGEUP:
				_flip_page(-1)
			KEY_PAGEDOWN:
				_flip_page(1)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_flip_page(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_flip_page(1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_back_to_submode()
