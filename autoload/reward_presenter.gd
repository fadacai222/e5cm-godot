extends CanvasLayer
## 全局奖励解锁提示。只在非玩法安全场景展示，避免覆盖全连/全 P/升级主演出。

const DISPLAY_SECONDS := 3.2
const MERGE_DELAY_SECONDS := 0.22
const MAX_BATCH := 3

var _queue: Array[Dictionary] = []
var _queued_at_msec := 0
var _popup: Control
var _dismiss_at_msec := 0

func _ready() -> void:
	layer = 190
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not RewardService.reward_unlocked.is_connected(_on_reward_unlocked):
		RewardService.reward_unlocked.connect(_on_reward_unlocked)

func _on_reward_unlocked(_reward_id: String, reward: Dictionary) -> void:
	_queue.append(reward.duplicate(true))
	if _queued_at_msec <= 0:
		_queued_at_msec = Time.get_ticks_msec()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if is_instance_valid(_popup):
		if now >= _dismiss_at_msec:
			_close_popup()
		return
	if _queue.is_empty() or now - _queued_at_msec < int(MERGE_DELAY_SECONDS * 1000.0):
		return
	if not _safe_to_present():
		return
	_show_next_batch()

func _safe_to_present() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var path := str(scene.scene_file_path)
	if path.contains("/gameplay/") or path.contains("/loading/") or path.contains("/settlement/") \
			or path.contains("/boot/") or path.contains("/coin/"):
		return false
	return true

func _show_next_batch() -> void:
	var batch: Array[Dictionary] = []
	while not _queue.is_empty() and batch.size() < MAX_BATCH:
		batch.append(_queue.pop_front())
	_queued_at_msec = Time.get_ticks_msec() if not _queue.is_empty() else 0

	_popup = Control.new()
	_popup.name = "RewardUnlockPopup"
	_popup.position = Vector2(1238, 686)
	_popup.size = Vector2(630, 330 if batch.size() > 1 else 250)
	_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_popup)
	var frame := UiKit.hud_frame(_popup, Rect2(Vector2.ZERO, _popup.size), "PopupFrame",
		E5OriginalTheme.GOLD, E5OriginalTheme.MAGENTA, 64.0, true, 18.0)
	frame.fill_color = Color(0.022, 0.028, 0.075, 0.98)
	frame.header_color = Color(0.14, 0.08, 0.18, 0.88)
	var title := UiKit.label(_popup, "奖励解锁 / REWARD UNLOCKED", 24,
		Vector2(24, 15), E5OriginalTheme.GOLD, 3)
	title.size = Vector2(520, 40)
	for i in batch.size():
		var reward := batch[i]
		var row := Control.new()
		row.name = "UnlockedReward%d" % i
		row.position = Vector2(24, 78 + i * 70)
		row.size = Vector2(582, 60)
		_popup.add_child(row)
		var rarity := RewardCatalog.rarity_display_name(str(reward.get("rarity", "common")))
		var label := UiKit.label(row, "◆  %s" % str(reward.get("name", "奖励")), 21,
			Vector2(0, 0), Color.WHITE, 2)
		label.size = Vector2(380, 32)
		var tag := UiKit.label(row, rarity, 15, Vector2(402, 2), E5OriginalTheme.GOLD, 2)
		tag.size = Vector2(160, 28)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var desc := UiKit.label(row, str(reward.get("description", "")), 14,
			Vector2(24, 32), E5OriginalTheme.MUTED, 1)
		desc.size = Vector2(540, 26)
		desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var close := Button.new()
	close.name = "SkipButton"
	close.text = "确认 / 跳过"
	close.position = Vector2(430, _popup.size.y - 52)
	close.size = Vector2(176, 38)
	close.pressed.connect(_close_popup)
	UiKit.skin_arcade_button(close, false, false, 16, E5OriginalTheme.MAGENTA)
	_popup.add_child(close)
	_popup.modulate.a = 0.0
	_popup.position.x += 28.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_popup, "modulate:a", 1.0, 0.18)
	tween.tween_property(_popup, "position:x", 1238.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_dismiss_at_msec = Time.get_ticks_msec() + int(DISPLAY_SECONDS * 1000.0)

func _close_popup() -> void:
	if is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null
	_dismiss_at_msec = 0

func pending_count_for_test() -> int:
	return _queue.size()

func force_safe_present_for_test() -> void:
	if not _queue.is_empty() and not is_instance_valid(_popup):
		_show_next_batch()

func reset_for_test() -> void:
	_queue.clear()
	_queued_at_msec = 0
	_close_popup()
