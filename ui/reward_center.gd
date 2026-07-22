class_name RewardCenter
extends Control
## 完整奖励中心：目录筛选、未读状态、获取条件、实时装配预览。

signal close_requested

const PlayerIdentityViewScript := preload("res://ui/player_identity_view.gd")
const RewardThumbnailScript := preload("res://ui/reward_thumbnail.gd")
const PAGE_SIZE := 8

var ownership_filter := "all" # all / owned / locked
var type_filter := "all" # all / title / avatar_frame / profile_card
var page := 0
var selected_reward_id := ""
var _all_items: Array = []
var _preview: PlayerIdentityView
var _detail_title: Label
var _detail_body: Label
var _detail_source: Label
var _action_button: Button
var _reset_slot_button: Button
var _page_label: Label
var _refresh_queued := false
var _filter_buttons: Array[Button] = []
var _rewards: Node
var _audio: Node
var _assets: Node
var _focus_buttons: Array[Button] = []
var _focus_index := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		_rewards = tree.root.get_node_or_null("RewardService")
		_audio = tree.root.get_node_or_null("AudioDirector")
		_assets = tree.root.get_node_or_null("AssetLoader")
	if size.x < 100.0 or size.y < 100.0:
		size = Vector2(1560, 900)
	_build_shell()
	if _rewards != null and not _rewards.inventory_changed.is_connected(_queue_refresh):
		_rewards.inventory_changed.connect(_queue_refresh)
	if _rewards != null and not _rewards.loadout_changed.is_connected(_on_loadout_changed):
		_rewards.loadout_changed.connect(_on_loadout_changed)
	_refresh()

func _build_shell() -> void:
	UiKit.hud_frame(self, Rect2(Vector2.ZERO, size), "Frame",
		E5OriginalTheme.CYAN, E5OriginalTheme.MAGENTA, 78.0, true, 24.0)
	var title := UiKit.label(self, "我的奖励 / REWARD COLLECTION", 34,
		Vector2(38, 19), Color(0.35, 0.95, 1.0), 3)
	title.size = Vector2(740, 46)
	var unread := UiKit.label(self, "", 17, Vector2(750, 29), E5OriginalTheme.GOLD, 2)
	unread.name = "UnreadSummary"
	unread.size = Vector2(250, 34)

	var close := Button.new()
	close.name = "CloseButton"
	close.text = "关闭  ESC"
	close.position = Vector2(size.x - 222, 18)
	close.size = Vector2(184, 48)
	close.pressed.connect(func(): close_requested.emit())
	UiKit.skin_arcade_button(close, false, false, 20, E5OriginalTheme.MAGENTA)
	add_child(close)

	_filter_buttons.clear()
	var ownership := [
		["全部", "all"], ["已拥有", "owned"], ["未解锁", "locked"],
	]
	for i in ownership.size():
		var button := _filter_button("Ownership%s" % ownership[i][1], str(ownership[i][0]),
			Vector2(38 + i * 132, 94), Vector2(122, 42))
		button.pressed.connect(_set_ownership_filter.bind(str(ownership[i][1])))
	var types := [
		["全部类型", "all"], ["称号", "title"], ["头像框", "avatar_frame"], ["玩家卡", "profile_card"],
	]
	for i in types.size():
		var button := _filter_button("Type%s" % types[i][1], str(types[i][0]),
			Vector2(450 + i * 132, 94), Vector2(122, 42))
		button.pressed.connect(_set_type_filter.bind(str(types[i][1])))

	var divider := ColorRect.new()
	divider.position = Vector2(38, 148)
	divider.size = Vector2(size.x - 76, 2)
	divider.color = Color(E5OriginalTheme.CYAN.r, E5OriginalTheme.CYAN.g, E5OriginalTheme.CYAN.b, 0.38)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(divider)

	_preview = PlayerIdentityViewScript.new()
	_preview.name = "RewardPreviewIdentity"
	_preview.position = Vector2(790, 178)
	_preview.scale = Vector2(0.86, 0.86)
	_preview.configure("full", {"show_progress": true, "show_status": false})
	add_child(_preview)

	_detail_title = UiKit.label(self, "选择奖励", 28, Vector2(806, 548), E5OriginalTheme.GOLD, 2)
	_detail_title.size = Vector2(690, 46)
	_detail_body = UiKit.label(self, "选择左侧奖励即可实时预览。", 18,
		Vector2(806, 602), Color(0.78, 0.86, 0.96), 1)
	_detail_body.size = Vector2(690, 92)
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_source = UiKit.label(self, "", 16, Vector2(806, 704), E5OriginalTheme.MUTED, 1)
	_detail_source.size = Vector2(690, 52)
	_detail_source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_action_button = Button.new()
	_action_button.name = "RewardActionButton"
	_action_button.text = "装备"
	_action_button.position = Vector2(806, 786)
	_action_button.size = Vector2(210, 56)
	_action_button.disabled = true
	_action_button.pressed.connect(_activate_selected)
	UiKit.skin_arcade_button(_action_button, false, false, 20, E5OriginalTheme.GOLD)
	add_child(_action_button)
	_reset_slot_button = Button.new()
	_reset_slot_button.name = "ResetSlotButton"
	_reset_slot_button.text = "取消当前槽位"
	_reset_slot_button.position = Vector2(1032, 786)
	_reset_slot_button.size = Vector2(210, 56)
	_reset_slot_button.disabled = true
	_reset_slot_button.pressed.connect(_reset_selected_slot)
	UiKit.skin_arcade_button(_reset_slot_button, false, false, 19, E5OriginalTheme.CYAN)
	add_child(_reset_slot_button)
	var reset_all := Button.new()
	reset_all.name = "ResetAllButton"
	reset_all.text = "恢复默认装配"
	reset_all.position = Vector2(1258, 786)
	reset_all.size = Vector2(210, 56)
	reset_all.pressed.connect(_reset_all)
	UiKit.skin_arcade_button(reset_all, false, false, 19, E5OriginalTheme.MAGENTA)
	add_child(reset_all)

	var prev := Button.new()
	prev.name = "PrevPage"
	prev.text = "◀ 上一页"
	prev.position = Vector2(38, 822)
	prev.size = Vector2(170, 46)
	prev.pressed.connect(_change_page.bind(-1))
	UiKit.skin_arcade_button(prev, false, false, 17, E5OriginalTheme.CYAN)
	add_child(prev)
	_page_label = UiKit.label(self, "1 / 1", 18, Vector2(218, 828), Color.WHITE, 1)
	_page_label.name = "PageLabel"
	_page_label.size = Vector2(170, 34)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var next := Button.new()
	next.name = "NextPage"
	next.text = "下一页 ▶"
	next.position = Vector2(398, 822)
	next.size = Vector2(170, 46)
	next.pressed.connect(_change_page.bind(1))
	UiKit.skin_arcade_button(next, false, false, 17, E5OriginalTheme.CYAN)
	add_child(next)

func _filter_button(node_name: String, text_value: String, pos: Vector2, button_size: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = pos
	button.size = button_size
	add_child(button)
	_filter_buttons.append(button)
	return button

func _set_ownership_filter(value: String) -> void:
	ownership_filter = value
	page = 0
	selected_reward_id = ""
	_refresh()

func _set_type_filter(value: String) -> void:
	type_filter = value
	page = 0
	selected_reward_id = ""
	_refresh()

func _change_page(direction: int) -> void:
	var count := _filtered_items().size()
	var pages := maxi(1, int(ceilf(float(count) / PAGE_SIZE)))
	page = posmod(page + direction, pages)
	selected_reward_id = ""
	_refresh()

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_refresh_deferred")

func _refresh_deferred() -> void:
	_refresh_queued = false
	if is_inside_tree():
		_refresh()

func _on_loadout_changed(_loadout: Dictionary) -> void:
	_preview.clear_loadout_preview()
	_queue_refresh()

func _refresh() -> void:
	_all_items = _rewards.all_rewards() if _rewards != null else []
	_all_items.sort_custom(_reward_sort_before)
	var unread := get_node_or_null("UnreadSummary") as Label
	if unread != null:
		var unseen := int(_rewards.unseen_count()) if _rewards != null else 0
		var shards := int(_rewards.duplicate_shards()) \
			if _rewards != null and _rewards.has_method("duplicate_shards") else 0
		var summaries: Array[String] = []
		if unseen > 0:
			summaries.append("NEW %d" % unseen)
		if shards > 0:
			summaries.append("奖励碎片 %d" % shards)
		unread.text = "  ·  ".join(summaries)
	_refresh_filter_styles()
	for child in get_children():
		if str(child.name).begins_with("RewardRow"):
			child.free()
	var filtered := _filtered_items()
	var pages := maxi(1, int(ceilf(float(filtered.size()) / PAGE_SIZE)))
	page = clampi(page, 0, pages - 1)
	_page_label.text = "%d / %d" % [page + 1, pages]
	var start := page * PAGE_SIZE
	for local_index in mini(PAGE_SIZE, maxi(0, filtered.size() - start)):
		var reward: Dictionary = filtered[start + local_index]
		_build_reward_row(reward, local_index)
	if selected_reward_id.is_empty() and not filtered.is_empty():
		_select_reward(str(filtered[start].get("id", "")), false)
	elif not selected_reward_id.is_empty():
		_select_reward(selected_reward_id, false)
	_rebuild_focus_buttons()

func _reward_sort_before(a: Variant, b: Variant) -> bool:
	if not a is Dictionary or not b is Dictionary:
		return str(a) < str(b)
	var left: Dictionary = a
	var right: Dictionary = b
	for key in ["equipped", "owned"]:
		var left_flag := bool(left.get(key, false))
		var right_flag := bool(right.get(key, false))
		if left_flag != right_flag:
			return left_flag
	var left_new := bool(left.get("owned", false)) and not bool(left.get("seen", true))
	var right_new := bool(right.get("owned", false)) and not bool(right.get("seen", true))
	if left_new != right_new:
		return left_new
	var rarity_rank := {"legendary": 3, "epic": 2, "rare": 1, "common": 0}
	var left_rarity := int(rarity_rank.get(str(left.get("rarity", "common")), 0))
	var right_rarity := int(rarity_rank.get(str(right.get("rarity", "common")), 0))
	if left_rarity != right_rarity:
		return left_rarity > right_rarity
	var type_rank := {"title": 0, "avatar_frame": 1, "profile_card": 2}
	var left_type := int(type_rank.get(str(left.get("type", "")), 9))
	var right_type := int(type_rank.get(str(right.get("type", "")), 9))
	if left_type != right_type:
		return left_type < right_type
	return str(left.get("name", "")) < str(right.get("name", ""))

func _refresh_filter_styles() -> void:
	for button in _filter_buttons:
		var selected := (button.name == "Ownership%s" % ownership_filter) \
			or (button.name == "Type%s" % type_filter)
		UiKit.skin_arcade_button(button, selected, false, 16,
			E5OriginalTheme.GOLD if selected else E5OriginalTheme.CYAN)

func _filtered_items() -> Array:
	var result: Array = []
	for raw in _all_items:
		if not raw is Dictionary:
			continue
		var item: Dictionary = raw
		var owned := bool(item.get("owned", false))
		if ownership_filter == "owned" and not owned:
			continue
		if ownership_filter == "locked" and owned:
			continue
		if type_filter != "all" and str(item.get("type", "")) != type_filter:
			continue
		result.append(item)
	return result

func _build_reward_row(reward: Dictionary, local_index: int) -> void:
	var row := Button.new()
	row.name = "RewardRow%d" % local_index
	row.position = Vector2(38 + (local_index % 2) * 362,
		174 + floori(float(local_index) / 2.0) * 146)
	row.size = Vector2(342, 126)
	row.text = ""
	var row_progress: Dictionary = _rewards.progress_for(str(reward.get("id", ""))) \
		if _rewards != null and _rewards.has_method("progress_for") else {}
	row.tooltip_text = str(reward.get("unlock_hint", ""))
	if not row_progress.is_empty():
		row.tooltip_text += "\n当前进度：%s" % str(row_progress.get("text", ""))
	row.pressed.connect(_select_reward.bind(str(reward.get("id", "")), true))
	add_child(row)

	var owned := bool(reward.get("owned", false))
	var hidden := bool(reward.get("hidden", false)) and not owned
	var reward_name := "？？？" if hidden else str(reward.get("name", "奖励"))
	var slot_name: String = str({"title": "称号", "avatar_frame": "头像框",
		"profile_card": "玩家卡"}.get(str(reward.get("slot", "")), "装饰"))
	var selected := str(reward.get("id", "")) == selected_reward_id
	_style_reward_row(row, reward, selected)

	var thumbnail: RewardThumbnail = RewardThumbnailScript.new()
	thumbnail.name = "Thumbnail"
	thumbnail.position = Vector2(14, 15)
	thumbnail.size = Vector2(96, 96)
	thumbnail.set_reward_data(reward, not owned)
	row.add_child(thumbnail)

	var name_label := UiKit.label(row, reward_name, 17, Vector2(124, 18),
		Color(0.92, 0.95, 0.98) if owned else Color(0.61, 0.64, 0.68), 1)
	name_label.name = "RewardName"
	name_label.size = Vector2(202, 26)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var meta := UiKit.label(row, "%s · %s" % [slot_name,
		RewardCatalog.rarity_display_name(str(reward.get("rarity", "common")))], 13, Vector2(124, 50),
		Color(0.69, 0.80, 0.88) if owned else Color(0.48, 0.51, 0.55), 0)
	meta.name = "RewardMeta"
	meta.size = Vector2(202, 22)
	var state_text := "● NEW" if owned and not bool(reward.get("seen", true)) else (
		"✓ 已装备" if bool(reward.get("equipped", false)) else (
			"已拥有" if owned else "LOCKED / 未解锁"))
	var state := UiKit.label(row, state_text, 13, Vector2(124, 82),
		E5OriginalTheme.GOLD if bool(reward.get("equipped", false)) else (
			E5OriginalTheme.CYAN_SOFT if owned else Color(0.66, 0.68, 0.72)), 1)
	state.name = "RewardState"
	state.size = Vector2(202, 24)

func _select_reward(reward_id: String, play_sound := true) -> void:
	var reward := _find_item(reward_id)
	if reward.is_empty():
		return
	selected_reward_id = reward_id
	var owned := bool(reward.get("owned", false))
	var hidden := bool(reward.get("hidden", false)) and not owned
	var display_name := "隐藏奖励" if hidden else str(reward.get("name", reward_id))
	_detail_title.text = "%s  /  %s" % [display_name,
		RewardCatalog.rarity_display_name(str(reward.get("rarity", "common")))]
	_detail_body.text = "隐藏条件" if hidden else str(reward.get("description", ""))
	var progress: Dictionary = _rewards.progress_for(reward_id) \
		if _rewards != null and _rewards.has_method("progress_for") else {}
	var progress_line := ""
	if not progress.is_empty():
		progress_line = "\n当前进度：%s" % str(progress.get("text", ""))
	_detail_source.text = "获取条件：%s%s\n来源：%s" % [
		"隐藏条件" if hidden else str(reward.get("unlock_hint", "")),
		progress_line,
		str(reward.get("source", "尚未获得")) if owned else "未解锁",
	]
	var slot := str(reward.get("slot", ""))
	var loadout: Dictionary = _rewards.current_loadout() if _rewards != null else {}
	if not hidden:
		loadout[slot] = reward_id
		_preview.set_loadout_preview(loadout)
	else:
		_preview.clear_loadout_preview()
	var shard_cost := int(_rewards.shard_cost_for(reward_id)) \
		if _rewards != null and _rewards.has_method("shard_cost_for") else 0
	if owned:
		_action_button.disabled = false
		_action_button.text = "取消装备" if _rewards.equipped(slot) == reward_id else "装备"
	elif shard_cost > 0:
		var balance := int(_rewards.duplicate_shards())
		_action_button.disabled = balance < shard_cost
		_action_button.text = "碎片兑换  %d" % shard_cost if balance >= shard_cost else \
			"碎片不足  %d / %d" % [balance, shard_cost]
	else:
		_action_button.disabled = true
		_action_button.text = "尚未解锁"
	_reset_slot_button.disabled = _rewards == null or str(_rewards.equipped(slot)).is_empty()
	if owned and not bool(reward.get("seen", true)) and _rewards != null:
		_rewards.mark_seen(reward_id)
	if play_sound:
		_play_button_sound()
	call_deferred("_refresh_selected_styles")

func _refresh_selected_styles() -> void:
	for child in get_children():
		if child is Button and str(child.name).begins_with("RewardRow"):
			var reward_id := _reward_id_from_row(child as Button)
			var reward := _find_item(reward_id)
			_style_reward_row(child as Button, reward, reward_id == selected_reward_id)


func _style_reward_row(row: Button, reward: Dictionary, selected: bool) -> void:
	var owned := bool(reward.get("owned", false))
	if owned:
		UiKit.skin_arcade_button(row, selected, false, 17,
			E5OriginalTheme.GOLD if bool(reward.get("equipped", false)) else E5OriginalTheme.CYAN)
		return
	var border := Color(0.54, 0.57, 0.62, 0.82) if selected else Color(0.39, 0.42, 0.47, 0.68)
	var fill := Color(0.115, 0.12, 0.135, 0.98) if selected else Color(0.07, 0.075, 0.09, 0.97)
	var normal := E5OriginalTheme.panel_style(fill, border, 2 if selected else 1)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.14, 0.145, 0.16, 0.98)
	hover.border_color = Color(0.64, 0.67, 0.72, 0.90)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.09, 0.095, 0.11, 1.0)
	row.add_theme_stylebox_override("normal", normal)
	row.add_theme_stylebox_override("hover", hover)
	row.add_theme_stylebox_override("pressed", pressed)
	row.add_theme_stylebox_override("focus", hover)
	row.add_theme_color_override("font_color", Color(0.62, 0.64, 0.68))

func _reward_id_from_row(row: Button) -> String:
	var index := int(str(row.name).trim_prefix("RewardRow"))
	var filtered := _filtered_items()
	var absolute := page * PAGE_SIZE + index
	return str(filtered[absolute].get("id", "")) if absolute >= 0 and absolute < filtered.size() else ""

func _find_item(reward_id: String) -> Dictionary:
	for raw in _all_items:
		if raw is Dictionary and str(raw.get("id", "")) == reward_id:
			return raw
	return {}

func _activate_selected() -> void:
	var reward := _find_item(selected_reward_id)
	if reward.is_empty() or _rewards == null:
		return
	if not bool(reward.get("owned", false)):
		if _rewards.has_method("can_redeem_with_shards") \
				and _rewards.can_redeem_with_shards(selected_reward_id):
			var redeemed: Dictionary = _rewards.redeem_with_shards(selected_reward_id)
			if bool(redeemed.get("ok", false)):
				_play_button_sound()
				_queue_refresh()
		return
	var slot := str(reward.get("slot", ""))
	if _rewards.equipped(slot) == selected_reward_id:
		_rewards.reset_slot(slot)
	else:
		_rewards.equip(slot, selected_reward_id)
	_play_button_sound()

func _reset_selected_slot() -> void:
	var reward := _find_item(selected_reward_id)
	if reward.is_empty():
		return
	if _rewards != null:
		_rewards.reset_slot(str(reward.get("slot", "")))
	_play_button_sound()

func _reset_all() -> void:
	if _rewards != null:
		for slot in ["title", "avatar_frame", "profile_card"]:
			_rewards.reset_slot(slot)
	_play_button_sound()

func _play_button_sound() -> void:
	if _audio != null and _assets != null:
		_audio.play_sfx(_assets.sound("按钮音效"))

func _rebuild_focus_buttons() -> void:
	_focus_buttons.clear()
	_collect_focus_buttons(self)
	_focus_buttons = _focus_buttons.filter(func(button: Button):
		return is_instance_valid(button) and button.visible and not button.disabled)
	if _focus_buttons.is_empty():
		_focus_index = 0
		return
	var owner := get_viewport().gui_get_focus_owner()
	var owner_index := _focus_buttons.find(owner)
	_focus_index = owner_index if owner_index >= 0 else clampi(_focus_index, 0, _focus_buttons.size() - 1)
	if owner_index < 0:
		_focus_buttons[_focus_index].grab_focus.call_deferred()

func _collect_focus_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is Button:
			_focus_buttons.append(child)
		_collect_focus_buttons(child)

func _step_focus(direction: int) -> void:
	if _focus_buttons.is_empty():
		return
	_focus_index = posmod(_focus_index + direction, _focus_buttons.size())
	_focus_buttons[_focus_index].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pedal_left") or event.is_action_pressed("ui_left") \
			or event.is_action_pressed("ui_up"):
		_step_focus(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pedal_right") or event.is_action_pressed("ui_right") \
			or event.is_action_pressed("ui_down"):
		_step_focus(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pedal_confirm") and not _focus_buttons.is_empty():
		_focus_buttons[_focus_index].pressed.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_PAGEUP, KEY_PAGEDOWN]:
		_change_page(-1 if event.keycode == KEY_PAGEUP else 1)
		get_viewport().set_input_as_handled()
