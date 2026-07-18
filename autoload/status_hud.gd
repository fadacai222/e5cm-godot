extends CanvasLayer
## 右下角实时状态条，对应原版 main.py 的 _构建右上状态条图层：
## 文本 "{fps:.1f} FPS | {渲染后端} | {宽}*{高}"，字号 18，色 (188,194,201)；
## 面板内边距 12×6，底色 rgba(6,8,12,126) 圆角 10，白描边 alpha 36 宽 1；
## 锚点 bottomright = (宽-14, 高-12)。所有场景常驻，随每帧刷新。

var _panel: PanelContainer
var _label: Label


func _ready() -> void:
	layer = 100
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(6 / 255.0, 8 / 255.0, 12 / 255.0, 126 / 255.0)
	style.set_corner_radius_all(10)
	style.border_color = Color(1, 1, 1, 36 / 255.0)
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", style)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(188 / 255.0, 194 / 255.0, 201 / 255.0))
	_panel.add_child(_label)
	add_child(_panel)


func _renderer_label() -> String:
	var driver := str(ProjectSettings.get_setting("rendering/rendering_device/driver", ""))
	if driver.is_empty():
		driver = str(RenderingServer.get_current_rendering_driver_name())
	return "GPU-%s" % driver.capitalize() if not driver.is_empty() else "GPU"


func _process(_delta: float) -> void:
	visible = SettingsStore.status_hud_enabled
	if not visible:
		return
	var fps := Engine.get_frames_per_second()
	var fps_text := "%.1f" % fps if fps > 0.1 else "--"
	var view_size := get_viewport().get_visible_rect().size
	_label.text = "%s FPS | %s | %d*%d" % [
		fps_text, _renderer_label(), int(view_size.x), int(view_size.y)
	]
	_panel.reset_size()
	_panel.position = Vector2(
		view_size.x - 14 - _panel.size.x,
		view_size.y - 12 - _panel.size.y
	)
