extends Control
## 投币场景 —— 布局按旧版 bbox 精确还原（设计 1920×1080）：
## logo(478,247,1443,689) 请投币(860,893,1060,950) 联网(703,991,767,1046)
## credit(788,1001,1132,1046) 1P(125,718,368,874) 2P(1551,718,1795,874)
## 背景 = 工程内置 backmovies/003.mp4，由 EIRTeam.FFmpeg 循环解码。

@onready var lbl_hint: Label = $HintLabel
@onready var lbl_credit: Label = $BottomCreditCenter/BottomCreditRow/CreditLabel
@onready var btn_1p: TextureButton = $OnePlayerButton
@onready var btn_2p: TextureButton = $TwoPlayerButton
@onready var logo: TextureRect = $Logo
@onready var _coin_key_hint: Label = $CoinKeyHint
@onready var _top_hint: Label = $TopHintLabel
@onready var _editor_preview_background: TextureRect = $EditorPreviewBackground
var _stage := "投币"
var _pedal_pick := 0
var _switching := false
var _hint_blinking := false
var _blink_start_ms := 0

const PICK_TOTAL_SEC := 0.32
const PICK_PRESS_SEC := 0.10
const PICK_END_SCALE := 4.0


func _ready() -> void:
	SceneRouter.take_payload()
	_blink_start_ms = Time.get_ticks_msec()

	# 编辑器里保留静态背景方便排版；运行时隐藏，让共享视频背景继续显示。
	_editor_preview_background.visible = false
	SharedVideoBackground.begin_sequence()
	var coin_keys: Array = SettingsStore.key_bindings.get("coin", [KEY_F])
	var key_name := SettingsStore.binding_display_name(coin_keys[0]) if not coin_keys.is_empty() else "F"
	_coin_key_hint.text = "%s投币" % key_name.to_upper()
	_update_credit_label(GameState.credits)
	btn_1p.pressed.connect(_on_one_player_pressed)
	btn_2p.pressed.connect(_on_two_player_pressed)

	GameState.credits_changed.connect(_on_credits_changed)
	AudioDirector.play_bgm(AssetLoader.sound("音乐_排行榜"))
	_refresh(false)


func _on_credits_changed(credits: int) -> void:
	_update_credit_label(credits)
	_refresh(true)


func _update_credit_label(credits: int) -> void:
	lbl_credit.text = "CREDIT：%d/%d" % [maxi(0, credits), GameState.CREDITS_PER_GAME]


func _on_one_player_pressed() -> void:
	_pick(1)


func _on_two_player_pressed() -> void:
	_pick(2)


func _refresh(play_full_sfx: bool) -> void:
	var enough := GameState.has_enough_credits()
	logo.visible = GameState.credits > 0
	if enough and _stage == "投币":
		_stage = "玩家选择"
		_pedal_pick = 1
		if play_full_sfx:
			AudioDirector.play_sfx(AssetLoader.sound("满额音效"))
	elif not enough:
		_stage = "投币"
		_pedal_pick = 0
	btn_1p.visible = _stage == "玩家选择"
	btn_2p.visible = _stage == "玩家选择"
	UiKit.highlight(btn_1p, _stage == "玩家选择" and _pedal_pick == 1)
	UiKit.highlight(btn_2p, _stage == "玩家选择" and _pedal_pick == 2)
	# 原版在玩家选择阶段只画 1P/2P 按钮，没有任何底部提示文字。
	_hint_blinking = _stage == "投币"
	_apply_blink_phase()


## 原版闪烁是按 int(经过秒)%2 硬切：亮 1 秒、灭 1 秒，
## "请投币！"与顶部高分屏提示同相位。
func _blink_phase_visible() -> bool:
	return int(floor(float(Time.get_ticks_msec() - _blink_start_ms) / 1000.0)) % 2 == 0


func reset_blink_phase() -> void:
	_blink_start_ms = Time.get_ticks_msec()
	_apply_blink_phase()


func _apply_blink_phase() -> void:
	var shown := _hint_blinking and _blink_phase_visible()
	lbl_hint.visible = shown
	_top_hint.visible = shown


func _process(_delta: float) -> void:
	_apply_blink_phase()


func _pick(players: int) -> void:
	if _switching or _stage != "玩家选择":
		return
	_switching = true
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	GameState.start_match(players)
	var selected := btn_1p if players == 1 else btn_2p
	selected.pivot_offset = selected.size * 0.5
	var fade_color := selected.modulate
	fade_color.a = 0.0
	var tween := create_tween()
	tween.tween_property(selected, "scale", Vector2(0.9, 0.9), PICK_PRESS_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(selected, "scale", Vector2.ONE * PICK_END_SCALE,
		PICK_TOTAL_SEC - PICK_PRESS_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(selected, "modulate", fade_color,
		PICK_TOTAL_SEC - PICK_PRESS_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	SceneRouter.change_to("login")


func _unhandled_input(event: InputEvent) -> void:
	if _switching or _stage != "玩家选择":
		return
	if event.is_action_pressed("pedal_left"):
		_pedal_pick = 1
		UiKit.highlight(btn_1p, true)
		UiKit.highlight(btn_2p, false)
		AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	elif event.is_action_pressed("pedal_right"):
		_pedal_pick = 2
		UiKit.highlight(btn_2p, true)
		UiKit.highlight(btn_1p, false)
		AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))
	elif event.is_action_pressed("pedal_confirm") and _pedal_pick in [1, 2]:
		_pick(_pedal_pick)
