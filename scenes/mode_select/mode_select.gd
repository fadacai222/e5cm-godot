extends Control
## 大模式：原版的“先选按钮、再点中央大图确认”两段式交互。

const FeatureQuickAccessRailScript = preload("res://ui/feature_quick_access_rail.gd")

const MODES := [
	{"key": "花式", "btn": "UI-img/大模式选择界面/按钮/花式模式按钮.png", "banner": "UI-img/大模式选择界面/花式模式.png", "desc": "花式模式：全新的谱面风格及舞蹈风格，音乐的专业性更强", "open": true},
	{"key": "竞速", "btn": "UI-img/大模式选择界面/按钮/竞速模式按钮.png", "banner": "UI-img/大模式选择界面/竞速模式.png", "desc": "竞速模式：挑战自我的速度极限", "open": true},
	{"key": "派对", "btn": "UI-img/大模式选择界面/按钮/派对模式按钮.png", "banner": "UI-img/大模式选择界面/派对模式.png", "desc": "派对模式（未开放）：展于个性的游戏模式，强调自我表现", "open": false},
	{"key": "DIY", "btn": "UI-img/大模式选择界面/按钮/DIY乐谱模式按钮.png", "banner": "UI-img/大模式选择界面/diy模式.png", "desc": "DIY乐谱：玩家自制的音乐谱面，优秀作品的聚集地", "open": true},
	{"key": "WEF", "btn": "UI-img/大模式选择界面/按钮/wef模式按钮.png", "banner": "UI-img/大模式选择界面/wef模式.png", "desc": "WEF联赛（未开放）：把握手中的机会，冲击联赛冠军！", "open": false},
]

const BTN_SIZE := Vector2(248, 237)
const BTN_GAP := 28.0
const BTN_Y := 669.0
const BANNER_RECT := Rect2(48, 151, 1824, 475)
const ENTER_DURATION := 0.32
const ENTER_OFFSET := 120.0

var _buttons: Array[TextureButton] = []
var _base_positions: Array[Vector2] = []
@onready var _banner: TextureButton = $ModeBanner
@onready var _desc: Label = $ModePrompt
@onready var _credit_label: Label = $BottomCreditCenter/BottomCreditRow/CreditLabel
var _selected := -1
var _shake_t := -1.0
var _banner_base_position := Vector2.ZERO
var _feature_rail: FeatureQuickAccessRail
var _feature_esc_menu: EscMenu


func _ready() -> void:
	SceneRouter.take_payload()
	SharedVideoBackground.continue_sequence()
	_build_banner()
	_build_buttons()
	_build_feature_quick_access()
	_update_credit_label(GameState.credits)
	GameState.credits_changed.connect(_update_credit_label)
	AudioDirector.play_bgm(AssetLoader.sound("音乐_UI"))


func _build_banner() -> void:
	_banner_base_position = _banner.position
	_banner.pivot_offset = _banner.size * 0.5
	_banner.visible = false
	_banner.pressed.connect(_confirm_selected)
	_desc.text = "请点击选择您喜欢的游戏模式"


func _build_buttons() -> void:
	_buttons = [$ModeButton0, $ModeButton1, $ModeButton2, $ModeButton3, $ModeButton4]
	_base_positions.clear()
	for i in MODES.size():
		var button := _buttons[i]
		button.texture_normal = AssetLoader.tex(str(MODES[i]["btn"]))
		var target := button.position
		button.position = target + Vector2(0, ENTER_OFFSET)
		button.pivot_offset = button.size * 0.5
		button.modulate.a = 0.0
		button.scale = Vector2.ONE
		button.pressed.connect(_activate.bind(i))
		_base_positions.append(target)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(button, "modulate:a", 1.0, ENTER_DURATION).set_delay(i * 0.06)
		tw.tween_property(button, "position", target, ENTER_DURATION).set_delay(i * 0.06) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_feature_quick_access() -> void:
	ChallengeService.ensure_current()
	ChallengeService.note_game_opened()
	_feature_rail = FeatureQuickAccessRailScript.new()
	_feature_rail.position = Vector2(1500, 18)
	_feature_rail.z_index = 20
	_feature_rail.training_requested.connect(_toggle_training_entry)
	_feature_rail.challenge_requested.connect(_open_challenge_center)
	$TopBar.add_child(_feature_rail)

	_feature_esc_menu = EscMenu.new(false)
	_feature_esc_menu.name = "FeatureEscMenu"
	add_child(_feature_esc_menu)


func _open_challenge_center() -> void:
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	_feature_esc_menu.open_menu(EscMenu.CHALLENGE_TAB_INDEX)


func _toggle_training_entry() -> void:
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	if TrainingSession.is_entry_armed():
		TrainingSession.cancel_entry()
		_desc.text = "请点击选择您喜欢的游戏模式"
		_desc.add_theme_color_override("font_color", Color.WHITE)
	else:
		TrainingSession.arm_entry()
		_desc.text = "训练室已开启：请选择歌曲来源模式，训练成绩不会计入正式记录"
		_desc.add_theme_color_override("font_color", Color(0.25, 0.95, 1.0))
	if _feature_rail != null:
		_feature_rail.refresh()


func _update_credit_label(credits: int) -> void:
	_credit_label.text = "CREDIT：%d/%d" % [maxi(0, credits), GameState.CREDITS_PER_GAME]


func _activate(index: int) -> void:
	if _selected == index:
		_confirm_selected()
	else:
		_select(index)


func _select(index: int) -> void:
	if index < 0 or index >= MODES.size() or _selected == index:
		return
	_selected = index
	var cfg: Dictionary = MODES[index]
	_banner.texture_normal = AssetLoader.tex(str(cfg["banner"]))
	_banner.visible = true
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.92, 0.92)
	_desc.text = str(cfg["desc"])
	_desc.add_theme_color_override("font_color", Color(251.0 / 255.0, 200.0 / 255.0, 106.0 / 255.0))
	_push_buttons(index)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_banner, "modulate:a", 1.0, 0.26)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _push_buttons(index: int) -> void:
	var spacing := BTN_SIZE.x + BTN_GAP
	var extra := BTN_SIZE.x * 0.35
	var targets: Array[float] = []
	for i in _buttons.size():
		var x := _base_positions[index].x + float(i - index) * spacing
		if i < index:
			x -= extra
		elif i > index:
			x += extra
		targets.append(x)
	var shift := 0.0
	if targets[0] < 24.0:
		shift = 24.0 - targets[0]
	if targets[-1] + BTN_SIZE.x + shift > 1896.0:
		shift -= targets[-1] + BTN_SIZE.x + shift - 1896.0
	for i in _buttons.size():
		var button := _buttons[i]
		button.visible = i != index
		if i == index:
			continue
		var target := Vector2(clampf(targets[i] + shift, 24.0, 1896.0 - BTN_SIZE.x), _base_positions[i].y)
		create_tween().tween_property(button, "position", target, 0.32) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _confirm(index := -1) -> void:
	if index >= 0 and index != _selected:
		_select(index)
		return
	_confirm_selected()


func _confirm_selected() -> void:
	if _selected < 0:
		_select(0)
		return
	var cfg: Dictionary = MODES[_selected]
	# 原版第二次确认无论模式是否开放都会再次播放按钮音效。
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	if not bool(cfg["open"]):
		UiKit.toast(self, "该模式暂未开放！")
		_shake_t = 0.0
		return
	GameState.big_mode = str(cfg["key"])
	SceneRouter.change_to_with_zoom("submode_select", _banner, {}, 0.18)


func _process(delta: float) -> void:
	if _shake_t < 0.0:
		return
	_shake_t += delta
	if _shake_t >= 0.34:
		_shake_t = -1.0
		_banner.position.x = _banner_base_position.x
	else:
		_banner.position.x = _banner_base_position.x + 14.0 * sin(_shake_t * 40.0) * (1.0 - _shake_t / 0.34)


func _unhandled_input(event: InputEvent) -> void:
	if _feature_esc_menu != null and _feature_esc_menu.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		_open_challenge_center()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pedal_left"):
		_select(MODES.size() - 1 if _selected < 0 else (_selected - 1 + MODES.size()) % MODES.size())
	elif event.is_action_pressed("pedal_right"):
		_select(0 if _selected < 0 else (_selected + 1) % MODES.size())
	elif event.is_action_pressed("pedal_confirm") or event.is_action_pressed("ui_accept"):
		if event.is_action_pressed("pedal_confirm") \
				and Input.is_action_pressed("pedal_left") \
				and Input.is_action_pressed("pedal_right"):
			_open_challenge_center()
		else:
			_confirm_selected()
	elif event.is_action_pressed("ui_cancel") and TrainingSession.is_entry_armed():
		TrainingSession.cancel_entry()
		_desc.text = "请点击选择您喜欢的游戏模式"
		_desc.add_theme_color_override("font_color", Color.WHITE)
		if _feature_rail != null:
			_feature_rail.refresh()
