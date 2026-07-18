extends Control
## 登录磁卡场景。坐标与缩放直接移植旧版 2048×1152 设计。

const S := 0.9375
const STAGE1_GUEST_BASE := Rect2(255, 274, 712, 612)
const STAGE1_GUEST_SCALE := 1.4
const STAGE1_VIP_BASE := Rect2(1081, 353, 445, 446)
const STAGE2_GUEST_BASE := Rect2(277, 247, 507, 507)
const CARD_TARGET_BASE := Rect2(1197, 764, 662, 388)
const SWIPE_BG_SOURCE := Vector2(737, 360)
const SWIPE_HINT_SOURCE := Vector2(654, 267)
const SWIPE_BG_SCALE := 1.3
const CARD_SCALE := 0.5
const BUTTON_DISAPPEAR_SEC := 0.2

var _stage := "选择"
@onready var btn_guest: TextureButton = $Stage1Guest
@onready var btn_vip: TextureButton = $Stage1Vip
@onready var stage2_guest: TextureButton = $Stage2Guest
@onready var swipe_bg: TextureRect = $SwipeBackground
@onready var swipe_hint: TextureRect = $SwipeHint
@onready var swipe_hint_white: TextureRect = $SwipeHintWhite
@onready var vip_decoration: TextureRect = $VipDecoration
@onready var card: TextureRect = $VipCard
@onready var _hint_timer: Timer = $SwipeHintBlinkTimer
@onready var _credit_label: Label = $BottomCreditCenter/BottomCreditRow/CreditLabel
var _card_target := Rect2()
var _swipe_zone := Rect2()
var _dragging := false
var _drag_offset := Vector2.ZERO
var _auto_swiping := false
var _pedal_pick := ""
var _card_intro: Tween
var _button_transition: Tween
var _transitioning := false


func _ready() -> void:
	SceneRouter.take_payload()
	SharedVideoBackground.continue_sequence()
	for node in [swipe_bg, swipe_hint, swipe_hint_white, vip_decoration, stage2_guest, card]:
		node.modulate = Color.WHITE
	_swipe_zone = Rect2(swipe_bg.position, swipe_bg.size)
	_card_target = Rect2(card.position, card.size)
	btn_guest.pivot_offset = btn_guest.size * 0.5
	btn_vip.pivot_offset = btn_vip.size * 0.5
	btn_guest.pressed.connect(func(): _pick("游客"))
	btn_vip.pressed.connect(func(): _pick("VIP"))
	stage2_guest.pressed.connect(_back_to_select)
	card.gui_input.connect(_on_card_input)
	_hint_timer.timeout.connect(_toggle_swipe_hint)
	_update_credit_label(GameState.credits)
	GameState.credits_changed.connect(_update_credit_label)
	_set_stage("选择")


func _update_credit_label(credits: int) -> void:
	_credit_label.text = "CREDIT：%d/%d" % [maxi(0, credits), GameState.CREDITS_PER_GAME]


func _add_video_dim(alpha: float) -> void:
	var dim := ColorRect.new()
	dim.name = "SharedVideoDim"
	dim.color = Color(0, 0, 0, alpha)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)


func _scaled_rect(source: Rect2) -> Rect2:
	return Rect2(source.position * S, source.size * S)


func _scale_rect_about_center(source: Rect2, scale_value: float) -> Rect2:
	var new_size := source.size * scale_value
	return Rect2(source.get_center() - new_size * 0.5, new_size)


func _texture_rect(node_name: String, texture: Texture2D, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.name = node_name
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node


func _texture_button(node_name: String, texture: Texture2D, rect: Rect2,
	callback: Callable) -> TextureButton:
	var node := TextureButton.new()
	node.name = node_name
	node.texture_normal = texture
	node.ignore_texture_size = true
	node.stretch_mode = TextureButton.STRETCH_SCALE
	node.pressed.connect(callback)
	add_child(node)
	node.position = rect.position
	node.size = rect.size
	return node


func _set_stage(stage: String) -> void:
	if _button_transition != null and _button_transition.is_valid():
		_button_transition.kill()
	_button_transition = null
	_transitioning = false
	_stage = stage
	var selecting := stage == "选择"
	_dragging = false
	_auto_swiping = false
	btn_guest.scale = Vector2.ONE
	btn_vip.scale = Vector2.ONE
	btn_guest.visible = selecting
	btn_vip.visible = selecting
	for node in [swipe_bg, swipe_hint, swipe_hint_white, vip_decoration, stage2_guest, card]:
		node.visible = not selecting
	_hint_timer.stop()
	swipe_hint_white.visible = false
	if not selecting:
		_hint_timer.start()
		_start_card_intro()


func _start_card_intro() -> void:
	if _card_intro != null:
		_card_intro.kill()
	card.position = _card_target.position + Vector2(0, _card_target.size.y * 0.35)
	_card_intro = create_tween()
	_card_intro.tween_property(card, "position", _card_target.position, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _toggle_swipe_hint() -> void:
	swipe_hint_white.visible = not swipe_hint_white.visible
	swipe_hint.visible = not swipe_hint_white.visible


func _back_to_select() -> void:
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	_set_stage("选择")


func _pick(option: String) -> void:
	if _transitioning:
		return
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	if option == "游客":
		SceneRouter.change_to_with_zoom("mode_select", btn_guest)
	elif option == "VIP":
		_start_vip_transition()


func _start_vip_transition() -> void:
	_transitioning = true
	btn_guest.pivot_offset = btn_guest.size * 0.5
	btn_vip.pivot_offset = btn_vip.size * 0.5
	_button_transition = create_tween().set_parallel(true)
	_button_transition.tween_property(btn_guest, "scale", Vector2.ZERO, BUTTON_DISAPPEAR_SEC) \
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	_button_transition.tween_property(btn_vip, "scale", Vector2.ZERO, BUTTON_DISAPPEAR_SEC) \
		.set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	await _button_transition.finished
	_button_transition = null
	if not is_inside_tree():
		return
	_set_stage("刷卡")


func _on_card_input(event: InputEvent) -> void:
	if _stage != "刷卡" or _auto_swiping:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _card_intro != null:
				_card_intro.kill()
			_dragging = true
			_drag_offset = card.get_global_mouse_position() - card.global_position
		else:
			_dragging = false
			_check_swipe()


func _process(_delta: float) -> void:
	if _dragging:
		card.global_position = card.get_global_mouse_position() - _drag_offset
	if _auto_swiping:
		var target := _swipe_zone.get_center() - card.size * 0.5
		card.global_position = card.global_position.lerp(target, 0.15)
		if card.global_position.distance_to(target) < 8.0:
			_auto_swiping = false
			_swipe_success()


func _check_swipe() -> void:
	if Rect2(card.global_position, card.size).intersects(_swipe_zone):
		_swipe_success()
	else:
		_start_card_intro()


func _swipe_success() -> void:
	AudioDirector.play_sfx(AssetLoader.sound("刷卡音效"))
	SceneRouter.change_to_with_zoom("profile", card)


func _exit_tree() -> void:
	if _button_transition != null and _button_transition.is_valid():
		_button_transition.kill()
	_button_transition = null
	if _card_intro != null and _card_intro.is_valid():
		_card_intro.kill()
	_card_intro = null


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning:
		return
	if _stage == "选择":
		if event.is_action_pressed("pedal_left"):
			_pedal_pick = "游客"
			UiKit.highlight(btn_guest, true)
			UiKit.highlight(btn_vip, false)
		elif event.is_action_pressed("pedal_right"):
			_pedal_pick = "VIP"
			UiKit.highlight(btn_vip, true)
			UiKit.highlight(btn_guest, false)
		elif event.is_action_pressed("pedal_confirm") and _pedal_pick != "":
			_pick(_pedal_pick)
	elif _stage == "刷卡":
		if event.is_action_pressed("pedal_confirm") and not _auto_swiping:
			_auto_swiping = true
		elif event.is_action_pressed("ui_cancel"):
			_set_stage("选择")
