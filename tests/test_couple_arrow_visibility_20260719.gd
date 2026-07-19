extends SceneTree
## 情侣模式箭头可见性回归：1P 使用 larrow，2P 使用 rarrow；Tap/Hold/手键都必须拿到真实纹理。

const AUTOLOADS := [
	["SettingsStore", "res://autoload/settings_store.gd"],
	["AssetLoader", "res://autoload/asset_loader.gd"],
]

var _failures := 0
var _created: Array[Node] = []


func _check(ok: bool, label: String, detail := "") -> void:
	if ok:
		print("  PASS  %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s  %s" % [label, detail])


func _initialize() -> void:
	for spec in AUTOLOADS:
		if root.get_node_or_null(spec[0]) != null:
			continue
		var node = load(spec[1]).new()
		node.name = spec[0]
		root.add_child(node)
		_created.append(node)
	await process_frame

	var field = load("res://scenes/gameplay/note_field.gd").new()
	root.add_child(field)
	field.setup(10, 1.0, true)

	var judge_script = load("res://core/judge_system.gd")
	var p1_tap = judge_script.JudgeNote.new(0, "tap", 1.0, 1.0, [])
	var p2_tap = judge_script.JudgeNote.new(5, "tap", 1.0, 1.0, [])
	var p1_hold = judge_script.JudgeNote.new(1, "hold", 1.2, 2.0, [])
	var p2_hold = judge_script.JudgeNote.new(6, "hold", 1.2, 2.0, [])
	field.load_notes([p1_tap, p2_tap, p1_hold, p2_hold])
	field.load_hand_events([
		{"dir": "ll", "player": 1, "start_sec": 1.4, "end_sec": 2.2, "type": "hold"},
		{"dir": "rr", "player": 2, "start_sec": 1.4, "end_sec": 2.2, "type": "hold"},
	])
	field.update_field(0.0, 0.016)

	var atlas: Dictionary = root.get_node("AssetLoader").couple_arrow_atlas()
	var notes: Array = field.get("_render_notes")
	var p1_head := notes[0].get("head") as Sprite2D
	var p2_head := notes[1].get("head") as Sprite2D
	_check(p1_head != null and p1_head.texture != null \
		and p1_head.texture == atlas.get("larrow_body_lb"),
		"情侣模式 1P Tap 使用 larrow 专用箭头",
		str(p1_head.texture) if p1_head != null else "null head")
	_check(p2_head != null and p2_head.texture != null \
		and p2_head.texture == atlas.get("rarrow_body_lb"),
		"情侣模式 2P Tap 使用 rarrow 专用箭头",
		str(p2_head.texture) if p2_head != null else "null head")

	for index in [2, 3]:
		var item: Dictionary = notes[index]
		_check((item.get("head") as Sprite2D).texture != null \
			and (item.get("neck") as Sprite2D).texture != null \
			and (item.get("body") as Sprite2D).texture != null \
			and (item.get("tail") as Sprite2D).texture != null,
			"情侣模式 %dP Hold 头身尾均有纹理" % (index - 1))

	var hands: Array = field.get("_render_hand_notes")
	for index in hands.size():
		var item: Dictionary = hands[index]
		_check((item.get("head") as Sprite2D).texture != null \
			and (item.get("neck") as Sprite2D).texture != null \
			and (item.get("body") as Sprite2D).texture != null \
			and (item.get("tail") as Sprite2D).texture != null,
			"情侣模式 %dP 手键 Hold 头身尾均有纹理" % (index + 1))

	field.queue_free()
	await process_frame
	for node in _created:
		if is_instance_valid(node):
			node.queue_free()
	print("ALL COUPLE ARROW VISIBILITY TESTS PASSED" if _failures == 0 else
		"%d COUPLE ARROW VISIBILITY TEST(S) FAILED" % _failures)
	quit(_failures)
