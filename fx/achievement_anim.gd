class_name AchievementAnim
extends Control
## 结算前成就动画（full_combo / full_perfect）—— 原版部件合成：
## board(旋转光盘) + ring_light + bar(底板斜入) + label(标签) + arrow(箭头流) + wind
## 节奏取自 config/animation/结算前成就动画_设置.json（总时长约 4.5s，简化为 3.2s）。

signal finished

var _t := 0.0
var _running := false
var _board: TextureRect
var _ring: TextureRect
var _bar: TextureRect
var _label: TextureRect
var _wind: TextureRect
var _dim: ColorRect

const T_BAR_IN := 0.67
const T_MAIN_IN := 0.3
const T_LABEL := 1.0
const T_STAY := 0.8
const T_OUT := 0.45


func play(kind: String) -> void:
	# kind: "full_combo" / "full_perfect"
	var base := "UI-img/游戏界面/" + kind
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)

	_bar = _mk(base + "/bar.png", Vector2(960, 540), 1500)
	_board = _mk(base + "/board.png", Vector2(960, 540), 760)
	_ring = _mk(base + "/ring_light.png", Vector2(960, 540), 900)
	_wind = _mk(base + "/wind.png", Vector2(960, 540), 1300)
	_label = _mk(base + "/label.png", Vector2(960, 540), 980)

	_t = 0.0
	_running = true


func _mk(rel: String, center: Vector2, width: float) -> TextureRect:
	var tex := AssetLoader.tex(rel)
	var tr := TextureRect.new()
	tr.texture = tex
	if tex != null:
		var h := width * float(tex.get_height()) / float(tex.get_width())
		tr.custom_minimum_size = Vector2(width, h)
		tr.size = tr.custom_minimum_size
		tr.position = center - tr.size * 0.5
		tr.pivot_offset = tr.size * 0.5
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tr.modulate.a = 0.0
	add_child(tr)
	return tr


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	var t := _t
	var total := T_BAR_IN + T_MAIN_IN + T_LABEL + T_STAY + T_OUT

	_dim.color.a = clampf(t / 0.4, 0.0, 0.55) if t < total - T_OUT \
		else clampf((total - t) / T_OUT, 0.0, 1.0) * 0.55

	# 阶段1：底板斜入
	var k1 := clampf(t / T_BAR_IN, 0.0, 1.0)
	_bar.modulate.a = k1
	_bar.position.x = 960.0 - _bar.size.x * 0.5 + (1.0 - _ease_out(k1)) * -1730.0 * 0.5
	_bar.rotation_degrees = 4.5 * (1.0 - k1)

	# 阶段2：主体（board 旋转 + ring）
	var k2 := clampf((t - T_BAR_IN) / T_MAIN_IN, 0.0, 1.0)
	_board.modulate.a = k2
	_board.rotation_degrees += 57.0 * delta
	_ring.modulate.a = k2 * (0.7 + 0.3 * sin(t * 6.0))
	_wind.modulate.a = k2 * 0.8
	_wind.scale = Vector2.ONE * (1.0 + 0.15 * sin(t * 3.0))

	# 阶段3：label
	var k3 := clampf((t - T_BAR_IN - T_MAIN_IN) / T_LABEL, 0.0, 1.0)
	_label.modulate.a = _ease_out(k3)
	var ls := 1.6 - 0.6 * _ease_out(k3)
	_label.scale = Vector2(ls, ls)
	_label.rotation_degrees = 5.0 * (1.0 - k3)

	# 收尾
	if t >= total - T_OUT:
		var ko := clampf((total - t) / T_OUT, 0.0, 1.0)
		for node in [_bar, _board, _ring, _wind, _label]:
			node.modulate.a = minf(node.modulate.a, ko)
	if t >= total:
		_running = false
		finished.emit()
		queue_free()


func _ease_out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)
