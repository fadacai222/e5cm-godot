extends Node
## 选歌列表翻页按钮协调器。
## 详情/筛选弹层现在各自完整管理输入边界，本节点只负责翻页按钮资源、翻页与显隐。

const PAGE_TEXTURE := "UI-img/选歌界面资源/下一首-选歌.png"
const PAGE_SFX := "冷资源/Buttonsound/翻页.mp3"
const PAGE_ALPHA := 176.0 / 255.0

@onready var _host: Control = get_parent()
@onready var _previous: TextureButton = _host.get_node("PreviousPage")
@onready var _next: TextureButton = _host.get_node("NextPage")
var _detail: Control
var _filter: Control
var _esc_menu: CanvasLayer


func _ready() -> void:
	var texture := AssetLoader.tex(PAGE_TEXTURE)
	_previous.texture_normal = texture
	_next.texture_normal = texture
	_previous.flip_h = true
	_next.flip_h = false
	_previous.modulate.a = PAGE_ALPHA
	_next.modulate.a = PAGE_ALPHA
	_previous.pressed.connect(_turn_page.bind(-1))
	_next.pressed.connect(_turn_page.bind(1))
	_previous.mouse_entered.connect(_page_hover.bind(_previous, true))
	_previous.mouse_exited.connect(_page_hover.bind(_previous, false))
	_next.mouse_entered.connect(_page_hover.bind(_next, true))
	_next.mouse_exited.connect(_page_hover.bind(_next, false))
	set_process(false)
	call_deferred("_resolve_runtime_nodes")


func _resolve_runtime_nodes() -> void:
	_detail = _host.get("detail") as Control
	_filter = _host.get("filter_panel") as Control
	_esc_menu = _host.get("esc_menu") as CanvasLayer
	for overlay in [_detail, _filter, _esc_menu]:
		if is_instance_valid(overlay) and not overlay.visibility_changed.is_connected(refresh):
			overlay.visibility_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if _detail == null or _filter == null or _esc_menu == null:
		call_deferred("_resolve_runtime_nodes")
		return
	_refresh_page_buttons()


func _refresh_page_buttons() -> void:
	var pages := 1
	if _host.has_method("_page_count"):
		pages = int(_host.call("_page_count"))
	var overlay_open := (is_instance_valid(_detail) and _detail.visible) \
		or (is_instance_valid(_filter) and _filter.visible) \
		or (is_instance_valid(_esc_menu) and bool(_esc_menu.call("is_open")))
	var show := pages > 1 and not overlay_open
	_previous.visible = show
	_next.visible = show


func _turn_page(direction: int) -> void:
	if not _previous.visible or not _next.visible:
		return
	if _host.has_method("_flip_page"):
		_host.call("_flip_page", direction)
	AudioDirector.play_sfx(AssetLoader.abs_path(PAGE_SFX))


func _page_hover(button: TextureButton, hovered: bool) -> void:
	button.modulate.a = 1.0 if hovered else PAGE_ALPHA
