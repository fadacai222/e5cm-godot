extends Node
## 运行时资源加载（autoload: AssetLoader）
## UI、音效和公共贴图留在项目内；51GB 歌曲库独立放在项目外，避免 Godot
## 把音频/封面再次导入到 .godot/imported。歌曲封面只做有上限的内存 LRU。

const RUNTIME_ROOT := "res://assets/e5cm_runtime"
const PROJECT_SONGS_ROOT := "res://songs"
const LEGACY_PROJECT_SONGS_ROOT := RUNTIME_ROOT + "/songs"
const RECOVERY_DIR_NAME := "e5cm_runtime.__long_task_hold__"
const EXTERNAL_CONTENT_DIR_NAME := "e5cm-content"
const SONGS_ROOT_CONFIG := "user://songs_root.txt"
const SONG_TEXTURE_CACHE_LIMIT := 24

var _runtime_root := RUNTIME_ROOT
var _songs_root := PROJECT_SONGS_ROOT
var _using_recovery_root := false
var _tex_cache := {}     # 核心 UI 资源常驻缓存
var _song_tex_cache := {} # 外置歌曲封面有界缓存
var _song_tex_lru: Array[String] = []
var _atlas_cache := {}   # dir_abs -> Dictionary[frame_name -> AtlasTexture]


func _ready() -> void:
	_select_runtime_root()
	_select_songs_root()


func runtime_root() -> String:
	return _runtime_root


func songs_root() -> String:
	return _songs_root


func using_recovery_root() -> bool:
	return _using_recovery_root


func _select_runtime_root() -> void:
	# 核心资源是否可用只检查小体积 UI/音效，不再用 51GB 曲库作为探针。
	_runtime_root = RUNTIME_ROOT
	_using_recovery_root = false
	# 正式发行包故意不再携带开发机完整 song_index.json；核心资源完整性只看 UI 目录。
	# 发行曲库索引由 EXE 同目录的 release-song-index.json 提供。
	if DirAccess.open(RUNTIME_ROOT.path_join("UI-img")) != null:
		return
	var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	var recovery_root := project_dir.get_base_dir().path_join(RECOVERY_DIR_NAME).replace("\\", "/")
	if DirAccess.open(recovery_root.path_join("UI-img")) != null:
		_runtime_root = recovery_root
		_using_recovery_root = true
		push_warning("AssetLoader: 项目内核心资源不完整，临时使用恢复目录：%s" % recovery_root)


func _select_songs_root() -> void:
	var candidates: Array[String] = []
	# 当前项目约定：完整曲库位于项目根目录 songs。
	# 使用原生绝对路径读取，避免 .gdignore 下的原文件被 ResourceLoader 误走旧 remap；
	# 同时保留 res://songs 作为静态索引兼容别名。
	var project_songs_native := ProjectSettings.globalize_path(PROJECT_SONGS_ROOT).replace("\\", "/").trim_suffix("/")
	# 项目根目录优先，避免旧 user://songs_root.txt 继续把代码指向已经搬走的外置目录。
	candidates.append(project_songs_native)
	var environment_root := OS.get_environment("E5CM_SONGS_ROOT").strip_edges()
	if not environment_root.is_empty():
		candidates.append(environment_root)
	if FileAccess.file_exists(SONGS_ROOT_CONFIG):
		var configured := FileAccess.get_file_as_string(SONGS_ROOT_CONFIG).strip_edges()
		if not configured.is_empty():
			candidates.append(configured)
	var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")
	var desktop_root := project_dir.get_base_dir()
	candidates.append(desktop_root.path_join(EXTERNAL_CONTENT_DIR_NAME).path_join("songs"))
	candidates.append(desktop_root.path_join(RECOVERY_DIR_NAME).path_join("songs"))
	candidates.append(LEGACY_PROJECT_SONGS_ROOT)
	for raw_candidate in candidates:
		var candidate := raw_candidate.replace("\\", "/").trim_suffix("/")
		if DirAccess.open(candidate) != null:
			_songs_root = candidate
			return
	_songs_root = project_songs_native


func set_songs_root_for_test(path: String) -> void:
	_songs_root = path.replace("\\", "/").trim_suffix("/")


func _path_in_runtime_root(path: String, root_path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized == RUNTIME_ROOT:
		return root_path
	if normalized.begins_with(RUNTIME_ROOT + "/"):
		return root_path.path_join(normalized.substr(RUNTIME_ROOT.length() + 1))
	return normalized


func _path_in_songs_root(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized == "songs" or normalized == PROJECT_SONGS_ROOT \
			or normalized == LEGACY_PROJECT_SONGS_ROOT:
		return _songs_root
	if normalized.begins_with("songs/"):
		return _songs_root.path_join(normalized.substr("songs/".length()))
	if normalized.begins_with(PROJECT_SONGS_ROOT + "/"):
		return _songs_root.path_join(normalized.substr(PROJECT_SONGS_ROOT.length() + 1))
	if normalized.begins_with(LEGACY_PROJECT_SONGS_ROOT + "/"):
		return _songs_root.path_join(normalized.substr(LEGACY_PROJECT_SONGS_ROOT.length() + 1))
	return normalized


func is_song_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	return normalized == _songs_root or normalized.begins_with(_songs_root + "/") \
		or normalized == PROJECT_SONGS_ROOT \
		or normalized.begins_with(PROJECT_SONGS_ROOT + "/") \
		or normalized == LEGACY_PROJECT_SONGS_ROOT \
		or normalized.begins_with(LEGACY_PROJECT_SONGS_ROOT + "/") \
		or normalized == "songs" or normalized.begins_with("songs/")


func resource_exists(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	# 导出包只保留 Godot 导入产物和 remap，原始 png/mp3 通常不在 PCK 中。
	# ResourceLoader.exists() 能识别 remap；FileAccess.file_exists() 只适合原始/外置文件。
	if normalized.begins_with("res://") and ResourceLoader.exists(normalized):
		return true
	return FileAccess.file_exists(normalized)


func _path_exists(path: String) -> bool:
	return resource_exists(path) or DirAccess.open(path) != null

## 旧项目资源相对路径表（节选自 core/常量与路径.py::默认资源路径）
const RES := {
	"背景_玩家": "冷资源/backimages/背景图/01.jpg",
	"视频_玩家": "res://assets/video/player_select/003.mp4",
	"背景_选歌": "冷资源/backimages/选歌界面.png",
	"背景_模式": "冷资源/backimages/背景图/07.jpg",
	"投币_logo": "res://assets/ui/player_select/logo.png",
	"投币_联网图标": "res://assets/ui/player_select/online.png",
	"1P按钮": "res://assets/ui/player_select/1p.png",
	"2P按钮": "res://assets/ui/player_select/2p.png",
	"top栏背景": "res://assets/ui/top_bar/background.png",
	"top标题_个人中心": "res://assets/ui/top_bar/profile.png",
	"top标题_模式选择": "res://assets/ui/top_bar/mode_select.png",
	"top标题_玩法选择": "res://assets/ui/top_bar/submode_select.png",
	"top标题_歌曲选择": "res://assets/ui/top_bar/song_select.png",
	"top标题_收藏夹": "res://assets/ui/top_bar/favorites.png",
	"登陆_场景1_游客": "res://assets/ui/login/scene1_guest.png",
	"登陆_场景1_vip": "res://assets/ui/login/scene1_vip.png",
	"登陆_场景2_游客": "res://assets/ui/login/scene2_guest.png",
	"登陆_请刷卡背景": "res://assets/ui/login/swipe_bg.png",
	"登陆_请刷卡内容": "res://assets/ui/login/swipe_hint.png",
	"登陆_请刷卡内容白色": "res://assets/ui/login/swipe_hint_white.png",
	"登陆_磁卡": "res://assets/ui/login/card.png",
	"登陆_贵宾装饰": "res://assets/ui/login/vip_decoration.png",
	"音乐_UI": "冷资源/backsound/back_music_ui.mp3",
	"音乐_开始": "冷资源/backsound/back_music_logo.mp3",
	"音乐_show": "冷资源/backsound/show.mp3",
	"音乐_devil": "冷资源/backsound/devil.mp3",
	"音乐_remix": "冷资源/backsound/remix.mp3",
	"音乐_club": "冷资源/backsound/club.mp3",
	"音乐_排行榜": "res://assets/audio/player_select/ranking.mp3",
	"按钮音效": "res://assets/audio/player_select/button.mp3",
	"投币音效": "res://assets/audio/player_select/coin.mp3",
	"刷卡音效": "冷资源/Buttonsound/刷卡+5.mp3",
	"满额音效": "res://assets/audio/player_select/full.wav",
	"开始游戏": "冷资源/backsound/开始游戏.mp3",
	"准备就绪音效": "冷资源/backsound/准备就绪音效.mp3",
	"结算前成就音效": "冷资源/Buttonsound/全连.mp3",
	"结算音效": "冷资源/backsound/结算音效.mp3",
	"gameover": "冷资源/backsound/gameover.mp3",
}

const ARROW_SKIN_BASE := "UI-img/游戏界面/箭头"
const COUPLE_SKIN_BASE := "UI-img/游戏界面/情侣箭头"
const GRADE_IMG_DIR := "UI-img/游戏界面/结算/评价"
# 02/03 的击中特效图像字节完全相同，但各自保留独立 JSON 帧表。
# 运行时只加载一份纹理，发行包也可安全排除 03 的重复 PNG。
const ATLAS_TEXTURE_ALIASES := {
	ARROW_SKIN_BASE + "/03/key_effect": ARROW_SKIN_BASE + "/02/key_effect",
}


func abs_path(rel: String) -> String:
	var normalized := rel.replace("\\", "/")
	if normalized == "songs" or normalized.begins_with("songs/") \
			or normalized == PROJECT_SONGS_ROOT \
			or normalized.begins_with(PROJECT_SONGS_ROOT + "/") \
			or normalized == LEGACY_PROJECT_SONGS_ROOT \
			or normalized.begins_with(LEGACY_PROJECT_SONGS_ROOT + "/"):
		return _path_in_songs_root(normalized)
	if normalized == RUNTIME_ROOT or normalized.begins_with(RUNTIME_ROOT + "/"):
		var recovered := _path_in_runtime_root(normalized, _runtime_root)
		return recovered if _path_exists(recovered) else normalized
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return normalized
	if normalized.length() > 1 and normalized[1] == ":":
		return normalized
	return _runtime_root.path_join(normalized)


func res_path(key: String) -> String:
	return abs_path(str(RES.get(key, "")))


## 按键名取音频路径（给 AudioDirector 用）
func sound(key: String) -> String:
	var p := res_path(key)
	return p if resource_exists(p) else ""


## 加载纹理。核心 UI 可常驻；歌曲封面只保留最近 24 张，翻页不会无限吃内存。
func tex(rel: String) -> Texture2D:
	var path := abs_path(rel)
	var song_texture := is_song_path(path)
	var cache: Dictionary = _song_tex_cache if song_texture else _tex_cache
	if cache.has(path):
		if song_texture:
			_touch_song_texture(path)
		return cache[path]
	var texture: Texture2D = null
	# 项目资源优先走 Godot 导入产物，确保测试路径与导出包一致，也避免原图直读警告。
	# 只有外置曲库，或导入缓存缺失/损坏时，才退回原图自救。
	if not song_texture and path.begins_with("res://") and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	if texture == null and FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			texture = ImageTexture.create_from_image(image)
	cache[path] = texture
	if song_texture:
		_touch_song_texture(path)
		_trim_song_texture_cache()
	return texture


func _touch_song_texture(path: String) -> void:
	_song_tex_lru.erase(path)
	_song_tex_lru.append(path)


func _trim_song_texture_cache(keep_paths: Array[String] = []) -> void:
	var keep := {}
	for raw_path in keep_paths:
		keep[abs_path(raw_path)] = true
	var guard := _song_tex_lru.size() + 1
	while _song_tex_cache.size() > SONG_TEXTURE_CACHE_LIMIT and guard > 0:
		guard -= 1
		if _song_tex_lru.is_empty():
			break
		var oldest: String = str(_song_tex_lru.pop_front())
		if keep.has(oldest):
			_song_tex_lru.append(oldest)
			continue
		_song_tex_cache.erase(oldest)


func trim_song_texture_cache(keep_paths: Array[String] = []) -> void:
	_trim_song_texture_cache(keep_paths)


func clear_song_texture_cache() -> void:
	_song_tex_cache.clear()
	_song_tex_lru.clear()


func song_texture_cache_limit_for_test() -> int:
	return SONG_TEXTURE_CACHE_LIMIT


func list_resources(rel_dir: String, extensions: Array[String] = []) -> Array[String]:
	var directory := abs_path(rel_dir)
	var names: Array[String] = []
	if directory.begins_with("res://"):
		for raw_name in ResourceLoader.list_directory(directory):
			var name := str(raw_name)
			if not name.ends_with("/") and _matches_extension(name, extensions):
				names.append(name)
	if names.is_empty():
		var access := DirAccess.open(directory)
		if access != null:
			access.list_dir_begin()
			var entry := access.get_next()
			while not entry.is_empty():
				if not access.current_is_dir() and _matches_extension(entry, extensions):
					names.append(entry)
				entry = access.get_next()
			access.list_dir_end()
	names.sort()
	return names


func list_directories(rel_dir: String) -> Array[String]:
	var directory := abs_path(rel_dir)
	var names: Array[String] = []
	if directory.begins_with("res://"):
		for raw_name in ResourceLoader.list_directory(directory):
			var name := str(raw_name)
			if name.ends_with("/"):
				names.append(name.trim_suffix("/"))
	if names.is_empty():
		var access := DirAccess.open(directory)
		if access != null:
			access.list_dir_begin()
			var entry := access.get_next()
			while not entry.is_empty():
				if access.current_is_dir() and not entry.begins_with("."):
					names.append(entry)
				entry = access.get_next()
			access.list_dir_end()
	names.sort()
	return names


func _matches_extension(file_name: String, extensions: Array[String]) -> bool:
	if extensions.is_empty():
		return true
	return extensions.has(file_name.get_extension().to_lower())


func tex_key(key: String) -> Texture2D:
	return tex(res_path(key))


## 加载 TexturePacker 风格图集（skin.png + skin.json）
## 返回 {"arrow_body_lb.png": AtlasTexture, ...}（键含扩展名，也注册去扩展名的别名）
func atlas(rel_dir: String) -> Dictionary:
	var dir := abs_path(rel_dir)
	if _atlas_cache.has(dir):
		return _atlas_cache[dir]
	var result := {}
	var json_path := dir.path_join("skin.json")
	var texture_rel_dir := str(ATLAS_TEXTURE_ALIASES.get(rel_dir, rel_dir))
	var png_path := abs_path(texture_rel_dir).path_join("skin.png")
	if FileAccess.file_exists(json_path) and resource_exists(png_path):
		var sheet := tex(png_path)
		var data = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if sheet != null and data is Dictionary and data.get("frames") is Array:
			for f in data["frames"]:
				var name := str(f.get("filename", ""))
				var rect: Dictionary = f.get("frame", {})
				var at := AtlasTexture.new()
				at.atlas = sheet
				at.region = Rect2(
					float(rect.get("x", 0)), float(rect.get("y", 0)),
					float(rect.get("w", 0)), float(rect.get("h", 0)))
				result[name] = at
				result[name.get_basename()] = at
	_atlas_cache[dir] = result
	return result


## 箭头皮肤（皮肤名默认取设置项；分包缺失回退原版默认）
func _skin_dir(part: String, skin := "") -> String:
	var name := skin if not skin.is_empty() else str(SettingsStore.arrow_skin)
	var dir := ARROW_SKIN_BASE + "/" + name + "/" + part
	if FileAccess.file_exists(abs_path(dir).path_join("skin.json")):
		return dir
	return ARROW_SKIN_BASE + "/原版默认/" + part


func arrow_atlas(skin := "") -> Dictionary:
	return atlas(_skin_dir("arrow", skin))


func key_atlas(skin := "") -> Dictionary:
	return atlas(_skin_dir("key", skin))


func _add_text_pf_aliases(source: Dictionary, canonical_prefix: String,
		values: Array[String]) -> Dictionary:
	# 历史皮肤使用 text_pf2/text_pf5/text_pf7/text_pf8 等不同编号。
	# 调用方只认语义键，加载层统一补成 judge_* / number_*，避免逐皮肤写白名单。
	var keys := source.keys()
	keys.sort()
	for value in values:
		var canonical := "%s_%s" % [canonical_prefix, value]
		if source.get(canonical) is Texture2D:
			continue
		var suffix := "_%s" % value
		for raw_key in keys:
			var base_name := str(raw_key).get_basename()
			if not base_name.begins_with("text_pf") or not base_name.ends_with(suffix):
				continue
			var texture := source.get(raw_key) as Texture2D
			if texture == null:
				continue
			source[canonical] = texture
			source[canonical + ".png"] = texture
			break
	return source


func judge_atlas(skin := "") -> Dictionary:
	return _add_text_pf_aliases(atlas(_skin_dir("judge", skin)), "judge",
		["combo", "cool", "good", "miss", "perfect"])


func number_atlas(skin := "") -> Dictionary:
	return _add_text_pf_aliases(atlas(_skin_dir("number", skin)), "number",
		["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "x"])


func key_effect_atlas(skin := "") -> Dictionary:
	return atlas(_skin_dir("key_effect", skin))


func couple_arrow_atlas() -> Dictionary:
	return atlas(COUPLE_SKIN_BASE + "/arrow")


func couple_judge_atlas() -> Dictionary:
	return atlas(COUPLE_SKIN_BASE + "/judge")


func couple_number_atlas() -> Dictionary:
	return atlas(COUPLE_SKIN_BASE + "/number")


func couple_key_atlas(player := 1) -> Dictionary:
	return atlas(COUPLE_SKIN_BASE + "/key/%dp" % clampi(int(player), 1, 2))


func couple_key_effect_atlas(player := 1) -> Dictionary:
	return atlas(COUPLE_SKIN_BASE + "/key_effect/%dp" % clampi(int(player), 1, 2))


## 血条皮肤（stage/数字/判定文字）
func blood_bar_atlas() -> Dictionary:
	return atlas("UI-img/游戏界面/血条/blood_bar")


func judge_text_atlas() -> Dictionary:
	return atlas("UI-img/游戏界面/血条/judge")


## 评级图（s/a/b/c/e/f.png、失败.png、全连.png、三把全连.png）
func grade_tex(grade: String) -> Texture2D:
	return tex(GRADE_IMG_DIR + "/" + grade.to_lower() + ".png")
