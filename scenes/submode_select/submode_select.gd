extends Control
## 子模式：快速逐个弹跳入场，第一次选择展开大图，第二次确认进入选歌。

const SUBMODE_BTNS := {
	"学习": "UI-img/玩法选择界面/按钮/学习模式按钮.png", "表演": "UI-img/玩法选择界面/按钮/表演模式按钮.png",
	"疯狂": "UI-img/玩法选择界面/按钮/疯狂模式按钮.png", "club": "UI-img/玩法选择界面/按钮/club模式按钮.png",
	"情侣": "UI-img/玩法选择界面/按钮/情侣模式按钮.png", "混音": "UI-img/玩法选择界面/按钮/混音模式按钮.png",
}
const SUBMODE_BIG := {
	"学习": "UI-img/玩法选择界面/学习模式.png", "表演": "UI-img/玩法选择界面/表演模式.png",
	"疯狂": "UI-img/玩法选择界面/疯狂模式.png", "club": "UI-img/玩法选择界面/双踏板模式.png",
	"情侣": "UI-img/玩法选择界面/情侣模式.png", "混音": "UI-img/玩法选择界面/混音模式.png",
}
const SUBMODE_ORDER := {
	"花式": ["学习", "表演", "疯狂", "club", "情侣", "混音"],
	"竞速": ["疯狂", "club", "情侣", "混音"],
}
const BTN_SIZE := Vector2(237, 237)
const BTN_GAP := 36.0
const BTN_Y := 452.0
const PAGE_COLUMNS := 6
const PAGE_ROWS := 3
const PAGE_SIZE := PAGE_COLUMNS * PAGE_ROWS
const GRID_ROW_GAP := 30.0
const GRID_Y := 195.0
const ENTRY_DURATION := 0.36
const ENTRY_DELAY := 0.035
const ENTRY_OFFSET := 190.0
const ENTRY_TRANSITION := Tween.TRANS_QUINT
const IDLE_AMPLITUDE := 6.0
const IDLE_PERIOD_MS := 1100.0
const IDLE_PHASE_STEP := 0.55

var _items: Array = []
var _page := 0
var _buttons: Array[TextureButton] = []
var _base_positions: Array[Vector2] = []
var _button_textures := {}
var _large_textures := {}
var _push_tweens := {}
@onready var _large_icon: TextureButton = $SubmodeLargeIcon
@onready var _page_label: Label = $PageIndicator
@onready var _prev_page: Button = $PreviousPage
@onready var _next_page: Button = $NextPage
@onready var _grid: Control = $SubmodeGrid
@onready var _credit_label: Label = $BottomCreditCenter/BottomCreditRow/CreditLabel
var _selected := -1
var _entry_finished := false


func _ready() -> void:
	SceneRouter.take_payload()
	# 从选歌预览返回时 AudioDirector 已被 stop_bgm()，子模式页必须自行恢复菜单音乐。
	AudioDirector.play_bgm(AssetLoader.sound("音乐_UI"))
	SharedVideoBackground.continue_sequence()
	_build_large_icon()
	_load_items()
	_update_credit_label(GameState.credits)
	GameState.credits_changed.connect(_update_credit_label)
	if _items.is_empty():
		UiKit.center_label(self, "该模式下没有找到曲目目录", 36, 480, Color(1, 0.6, 0.6))
		return
	_build_page_nav()
	_build_page()


func _load_items() -> void:
	if GameState.big_mode == "DIY":
		_items = SongLibrary.list_submodes("DIY")
	else:
		var existing := SongLibrary.list_submodes(GameState.big_mode)
		for item in SUBMODE_ORDER.get(GameState.big_mode, []):
			if existing.has(item):
				_items.append(item)
	_prewarm_item_textures()


func _prewarm_item_textures() -> void:
	_button_textures.clear()
	_large_textures.clear()
	for raw_item in _items:
		var mode_name := str(raw_item)
		var button_path := "UI-img/玩法选择界面/按钮/diy模式按钮.png" \
			if GameState.big_mode == "DIY" else str(SUBMODE_BTNS.get(mode_name, ""))
		var large_path := "UI-img/玩法选择界面/diy模式.png" \
			if GameState.big_mode == "DIY" else str(SUBMODE_BIG.get(mode_name, ""))
		if not _button_textures.has(mode_name):
			_button_textures[mode_name] = AssetLoader.tex(button_path)
		if not _large_textures.has(mode_name):
			_large_textures[mode_name] = AssetLoader.tex(large_path)


func texture_cache_ready_for_test(mode_name: String) -> bool:
	return _button_textures.get(mode_name) != null and _large_textures.get(mode_name) != null


func _build_large_icon() -> void:
	_large_icon.visible = false
	_large_icon.pressed.connect(_confirm_selected)


func _page_items() -> Array:
	return _items.slice(_page * PAGE_SIZE, mini((_page + 1) * PAGE_SIZE, _items.size()))


func _total_pages() -> int:
	return maxi(1, ceili(float(_items.size()) / float(PAGE_SIZE)))


func _caption_text(value: String) -> String:
	return value if value.length() <= 7 else value.substr(0, 7) + "…"


func _build_page_nav() -> void:
	_prev_page.pressed.connect(func(): _change_page(-1, true))
	_next_page.pressed.connect(func(): _change_page(1, true))
	_update_page_nav()


func _update_page_nav() -> void:
	if _page_label == null:
		return
	var pages := _total_pages()
	var show_nav := pages > 1
	_page_label.visible = show_nav
	_prev_page.visible = show_nav
	_next_page.visible = show_nav
	_page_label.text = "%d / %d" % [_page + 1, pages]
	_prev_page.disabled = _page <= 0
	_next_page.disabled = _page >= pages - 1


func _change_page(delta: int, select_edge := false) -> bool:
	var target := clampi(_page + delta, 0, _total_pages() - 1)
	if target == _page:
		return false
	_page = target
	_build_page()
	if select_edge and not _page_items().is_empty():
		_select(_page_items().size() - 1 if delta < 0 else 0)
	return true


func _build_page() -> void:
	_prewarm_item_textures()
	for button in _buttons:
		button.queue_free()
	_buttons.clear()
	_base_positions.clear()
	_selected = -1
	_large_icon.visible = false
	var items := _page_items()
	var multirow := items.size() > PAGE_COLUMNS
	var start_y := GRID_Y if multirow else BTN_Y
	var editor_slots: Array[Vector2] = []
	if not multirow and items.size() in [4, 6]:
		var slot_start := 1 if items.size() == 4 else 0
		for slot_index in items.size():
			editor_slots.append((_grid.get_node("Slot%d" % (slot_start + slot_index)) as Control).position)
	for i in items.size():
		var mode_name := str(items[i])
		var button := TextureButton.new()
		button.name = "SubmodeButton%d" % i
		button.texture_normal = _button_textures.get(mode_name)
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		var target: Vector2
		if not editor_slots.is_empty():
			target = editor_slots[i]
		else:
			var row := i / PAGE_COLUMNS
			var column := i % PAGE_COLUMNS
			var row_start := row * PAGE_COLUMNS
			var row_count := mini(PAGE_COLUMNS, items.size() - row_start)
			var row_width := row_count * BTN_SIZE.x + maxi(0, row_count - 1) * BTN_GAP
			var row_x := (1920.0 - row_width) * 0.5
			target = Vector2(row_x + column * (BTN_SIZE.x + BTN_GAP),
				start_y + row * (BTN_SIZE.y + GRID_ROW_GAP))
		button.position = target + Vector2(0, ENTRY_OFFSET)
		button.size = BTN_SIZE
		button.pivot_offset = BTN_SIZE * 0.5
		button.modulate.a = 0.0
		button.scale = Vector2(0.96, 0.96)
		button.pressed.connect(_activate.bind(i))
		_grid.add_child(button)
		_buttons.append(button)
		_base_positions.append(target)
		if GameState.big_mode == "DIY":
			var caption := Label.new()
			caption.text = _caption_text(mode_name)
			caption.position = Vector2(12, 150)
			caption.size = Vector2(BTN_SIZE.x - 24, 54)
			caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			caption.add_theme_font_size_override("font_size", 24)
			caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(caption)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(button, "position", target, ENTRY_DURATION).set_delay(i * ENTRY_DELAY) \
			.set_trans(ENTRY_TRANSITION).set_ease(Tween.EASE_OUT)
		tw.tween_property(button, "modulate:a", 1.0, 0.24).set_delay(i * ENTRY_DELAY) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(button, "scale", Vector2.ONE, 0.30).set_delay(i * ENTRY_DELAY) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entry_finished = false
	var finish_delay := ENTRY_DURATION + maxf(0.0, float(items.size() - 1) * ENTRY_DELAY)
	get_tree().create_timer(finish_delay).timeout.connect(func(): _entry_finished = true)
	_update_page_nav()


func _update_credit_label(credits: int) -> void:
	_credit_label.text = "CREDIT：%d/%d" % [maxi(0, credits), GameState.CREDITS_PER_GAME]


func _activate(index: int) -> void:
	if _selected == index:
		_confirm_selected()
	else:
		_select(index)


func _select(index: int) -> void:
	var items := _page_items()
	if index < 0 or index >= items.size() or _selected == index:
		return
	_selected = index
	var mode_name := str(items[index])
	_large_icon.texture_normal = _large_textures.get(mode_name)
	var target_width := BTN_SIZE.x * 1.2
	var tex := _large_icon.texture_normal
	var target_height := target_width
	if tex != null and tex.get_width() > 0:
		target_height = target_width * float(tex.get_height()) / float(tex.get_width())
	var center := _grid.position + _base_positions[index] + BTN_SIZE * 0.5
	_large_icon.size = Vector2(target_width, target_height)
	_large_icon.position = center - _large_icon.size * 0.5 - Vector2(0, BTN_SIZE.y * 0.5)
	_large_icon.pivot_offset = _large_icon.size * 0.5
	_large_icon.modulate.a = 0.0
	_large_icon.scale = Vector2(0.92, 0.92)
	_large_icon.visible = true
	_push_buttons(index)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_large_icon, "modulate:a", 1.0, 0.26)
	tw.tween_property(_large_icon, "scale", Vector2(1.06, 1.06), 0.156).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(_large_icon, "scale", Vector2.ONE, 0.104).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	AudioDirector.play_sfx(AssetLoader.sound("按钮音效"))


func _push_buttons(index: int) -> void:
	for i in _buttons.size():
		_buttons[i].visible = i != index
	if GameState.big_mode == "DIY" or index < 0 or index >= _buttons.size():
		return
	var targets := _push_target_xs(index)
	for i in _buttons.size():
		if i == index:
			continue
		var old_tween := _push_tweens.get(i) as Tween
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()
		var tween := create_tween()
		_push_tweens[i] = tween
		tween.tween_property(_buttons[i], "position:x", float(targets[i]), 0.32) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 与原版 core/工具.py::计算推开目标x列表一致：
## 以选中项为锚点重新排布整页按钮，再整体纠正越界；不是只推邻居或同一行。
func _push_target_xs(index: int) -> Array[float]:
	var count := _base_positions.size()
	var targets: Array[float] = []
	if count <= 0:
		return targets
	for position in _base_positions:
		targets.append((position as Vector2).x)
	var original_spacing := BTN_SIZE.x + 16.0
	if count >= 2:
		original_spacing = _base_positions[1].x - _base_positions[0].x
	if original_spacing <= 0.0:
		original_spacing = BTN_SIZE.x + 16.0
	var new_spacing := maxf(original_spacing, BTN_SIZE.x * 0.35)
	targets[index] = _base_positions[index].x
	for i in range(index - 1, -1, -1):
		targets[i] = targets[i + 1] - new_spacing
	for i in range(index + 1, count):
		targets[i] = targets[i - 1] + new_spacing
	var extra := BTN_SIZE.x * 0.35
	for i in count:
		if i < index:
			targets[i] -= extra
		elif i > index:
			targets[i] += extra
	var left_overflow := 24.0 - targets[0]
	var right_overflow := targets[-1] + BTN_SIZE.x - 1896.0
	var shift := 0.0
	if left_overflow > 0.0 and right_overflow > 0.0:
		shift = (left_overflow - right_overflow) * 0.5
	elif left_overflow > 0.0:
		shift = left_overflow
	elif right_overflow > 0.0:
		shift = -right_overflow
	for i in count:
		targets[i] = clampf(targets[i] + shift, 24.0, 1896.0 - BTN_SIZE.x)
	return targets


func _confirm(index := -1) -> void:
	if index >= 0 and index != _selected:
		_select(index)
		return
	_confirm_selected()


func _confirm_selected() -> void:
	if _selected < 0:
		_select(0)
		return
	var items := _page_items()
	GameState.sub_mode = str(items[_selected])
	GameState.song_select_restore = {}
	AudioDirector.play_bgm(_submode_bgm(GameState.sub_mode))
	SceneRouter.change_to_with_zoom("song_select", _large_icon)


func _submode_bgm(mode_name: String) -> String:
	if GameState.big_mode == "DIY" or mode_name.contains("表演"):
		return AssetLoader.sound("音乐_show")
	if mode_name.contains("疯狂"):
		return AssetLoader.sound("音乐_devil")
	if mode_name.contains("混音"):
		return AssetLoader.sound("音乐_remix")
	if mode_name.to_lower().contains("club"):
		return AssetLoader.sound("音乐_club")
	return AssetLoader.sound("音乐_UI")


func _process(_delta: float) -> void:
	if not _entry_finished or _selected >= 0:
		return
	var now := Time.get_ticks_msec() / IDLE_PERIOD_MS * TAU
	for i in _buttons.size():
		_buttons[i].position.y = _base_positions[i].y + sin(now + i * IDLE_PHASE_STEP) * IDLE_AMPLITUDE


func _unhandled_input(event: InputEvent) -> void:
	if _items.is_empty():
		if event.is_action_pressed("ui_cancel"):
			SceneRouter.change_to("mode_select")
		return
	var count := _page_items().size()
	if event.is_action_pressed("pedal_left"):
		if _selected == 0 and _page > 0:
			_change_page(-1, true)
		else:
			_select(count - 1 if _selected < 0 else (_selected - 1 + count) % count)
	elif event.is_action_pressed("pedal_right"):
		if _selected == count - 1 and _page < _total_pages() - 1:
			_change_page(1, true)
		else:
			_select(0 if _selected < 0 else (_selected + 1) % count)
	elif event.is_action_pressed("ui_page_up"):
		_change_page(-1, true)
	elif event.is_action_pressed("ui_page_down"):
		_change_page(1, true)
	elif event.is_action_pressed("pedal_confirm") or event.is_action_pressed("ui_accept"):
		_confirm_selected()
	elif event.is_action_pressed("ui_cancel"):
		SceneRouter.change_to("mode_select")
