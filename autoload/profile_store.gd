extends Node
## 玩家档案（autoload: ProfileStore）

signal profile_changed
signal progress_changed(mode_key: String, progress: Dictionary, preview: bool)
## 对应旧项目 userdata/profile/个人资料.json（结构保持一致，便于旧存档直接迁移）
## + 歌曲记录（旧 sqlite 歌曲记录作用域 -> user://records.json）
## + 收藏夹（旧 sqlite 收藏夹作用域 -> user://favorites.json）

const PROFILE_PATH := "user://profile.json"
const RECORDS_PATH := "user://records.json"
const FAVORITES_PATH := "user://favorites.json"

var profile_path := PROFILE_PATH
var persist_enabled := true
var profile := {}
var records := {}     # "songs/竞速/club/xxx/yyy.sm" -> {最高分, 游玩次数, 歌名, sm路径}
var favorites := []   # Array[String] sm相对路径
var _mode_progress_previews := {} # 仅内存：前两把缓存经验的即时显示，不提前写入正式等级


func _ready() -> void:
	_mode_progress_previews.clear()
	profile = _load_json(profile_path, _default_profile())
	refresh_rank_cache()
	records = _load_json(RECORDS_PATH, {})
	var fav = _load_json(FAVORITES_PATH, [])
	favorites = fav if fav is Array else []


func _default_profile() -> Dictionary:
	return {
		"昵称": "玩家",
		"头像文件": "",
		"统计": {
			"游玩时长分钟": 0,
			"累计评价S数": 0,
			"最大Combo": 0,
			"最大Combo曲目": "",
			"最高分": 0,
			"最高分曲目": "",
		},
		"进度": {
			"最大等级": ExpSystem.MAX_LEVEL,
			"经验版本": ExpSystem.EXP_DATA_VERSION,
			"段位": "",
			"花式": ExpSystem.default_progress(),
			"竞速": ExpSystem.default_progress(),
			"diy": ExpSystem.default_progress(),
		},
	}


## 模式键：花式/竞速/diy（DIY 大模式统一小写 diy，与旧版一致）
func _progress_key(mode_key: String) -> String:
	return mode_key.to_lower() if mode_key.to_upper() == "DIY" else mode_key


func get_mode_progress(mode_key: String) -> Dictionary:
	var key := _progress_key(mode_key)
	var progress = profile.get("进度", {}).get(key, null)
	if progress == null:
		progress = ExpSystem.default_progress()
	return ExpSystem.normalize_progress(progress, int(profile.get("进度", {}).get("经验版本", 1)))


func get_mode_progress_for_display(mode_key: String) -> Dictionary:
	var key := _progress_key(mode_key)
	if _mode_progress_previews.has(key):
		return (_mode_progress_previews[key] as Dictionary).duplicate(true)
	return get_mode_progress(key)


func set_mode_progress_preview(mode_key: String, progress: Dictionary) -> void:
	var key := _progress_key(mode_key)
	var normalized := ExpSystem.normalize_progress(progress)
	_mode_progress_previews[key] = normalized
	progress_changed.emit(key, normalized.duplicate(true), true)
	profile_changed.emit()


func clear_mode_progress_preview(mode_key := "") -> void:
	if mode_key.is_empty():
		var keys := _mode_progress_previews.keys().duplicate()
		_mode_progress_previews.clear()
		for raw_key in keys:
			var key := str(raw_key)
			progress_changed.emit(key, get_mode_progress(key), false)
		if not keys.is_empty():
			profile_changed.emit()
		return
	var key := _progress_key(mode_key)
	if not _mode_progress_previews.erase(key):
		return
	progress_changed.emit(key, get_mode_progress(key), false)
	profile_changed.emit()


func set_mode_progress(mode_key: String, progress: Dictionary) -> void:
	var key := _progress_key(mode_key)
	if not profile.has("进度"):
		profile["进度"] = {}
	var normalized := ExpSystem.normalize_progress(progress)
	profile["进度"][key] = normalized
	profile["进度"]["经验版本"] = ExpSystem.EXP_DATA_VERSION
	_mode_progress_previews.erase(key)
	profile["进度"]["段位"] = str(get_rank_index())
	save_profile()
	progress_changed.emit(key, normalized.duplicate(true), false)
	profile_changed.emit()


func get_highest_competitive_level() -> int:
	return maxi(int(get_mode_progress("花式").get("等级", 1)),
		int(get_mode_progress("竞速").get("等级", 1)))


func get_highest_competitive_level_for_display() -> int:
	return maxi(int(get_mode_progress_for_display("花式").get("等级", 1)),
		int(get_mode_progress_for_display("竞速").get("等级", 1)))


## 玩家总段位取花式、竞速、DIY 三个大模式中的最高等级。
## 保留 competitive 接口给旧 UI/统计使用，但段位不再排除 DIY 玩家。
func get_highest_mode_level() -> int:
	return maxi(get_highest_competitive_level(),
		int(get_mode_progress("DIY").get("等级", 1)))


func get_highest_mode_level_for_display() -> int:
	return maxi(get_highest_competitive_level_for_display(),
		int(get_mode_progress_for_display("DIY").get("等级", 1)))


func get_rank_index() -> int:
	return ExpSystem.rank_index_for_level(get_highest_mode_level())


func get_rank_index_for_display() -> int:
	return ExpSystem.rank_index_for_level(get_highest_mode_level_for_display())


func get_rank_asset_path() -> String:
	return ExpSystem.rank_asset_path(get_rank_index())


func get_rank_asset_path_for_display() -> String:
	return ExpSystem.rank_asset_path(get_rank_index_for_display())


func get_rank_label() -> String:
	return "%d段" % get_rank_index()


func get_rank_label_for_display() -> String:
	return "%d段" % get_rank_index_for_display()


## 修复旧存档只按花式/竞速写入的段位缓存。UI 不依赖这个字段，
## 但保持存档内部一致，避免后续工具或旧兼容代码继续读到一段。
func refresh_rank_cache(save_if_changed := true) -> bool:
	if not profile.has("进度") or not profile["进度"] is Dictionary:
		profile["进度"] = {}
	var expected := str(get_rank_index())
	if str(profile["进度"].get("段位", "")) == expected:
		return false
	profile["进度"]["段位"] = expected
	if save_if_changed:
		save_profile()
	return true


## 更新歌曲最高分（对应旧 core/歌曲记录.py::更新歌曲最高分）
## 返回 {是否新纪录, 最高分, 旧最高分, 游玩次数}
func update_song_record(sm_key: String, song_name: String, score: int) -> Dictionary:
	var item = records.get(sm_key, {"最高分": 0, "游玩次数": 0, "歌名": song_name, "sm路径": sm_key})
	var old_best := int(item.get("最高分", 0))
	var new_record := score > old_best
	item["游玩次数"] = int(item.get("游玩次数", 0)) + 1
	item["歌名"] = song_name if song_name != "" else str(item.get("歌名", ""))
	item["sm路径"] = sm_key
	if new_record:
		item["最高分"] = score
	records[sm_key] = item
	_save_json(RECORDS_PATH, records)
	return {
		"是否新纪录": new_record,
		"最高分": maxi(old_best, score),
		"旧最高分": old_best,
		"游玩次数": int(item["游玩次数"]),
	}


func get_song_record(sm_key: String) -> Dictionary:
	return records.get(sm_key, {"最高分": 0, "游玩次数": 0, "歌名": "", "sm路径": sm_key})


func toggle_favorite(sm_key: String) -> bool:
	if favorites.has(sm_key):
		favorites.erase(sm_key)
	else:
		favorites.append(sm_key)
	_save_json(FAVORITES_PATH, favorites)
	return favorites.has(sm_key)


func save_profile() -> void:
	_save_json(profile_path, profile)


func set_nickname(value: String) -> bool:
	var control_chars := RegEx.new()
	control_chars.compile("[\\x00-\\x1F\\x7F]")
	var nickname := control_chars.sub(value, "", true).strip_edges()
	if nickname.is_empty():
		return false
	profile["昵称"] = nickname.substr(0, 16)
	save_profile()
	profile_changed.emit()
	return true


func set_avatar_file(path: String) -> bool:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.is_empty() or not FileAccess.file_exists(normalized):
		return false
	if not normalized.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp"]:
		return false
	var image := Image.new()
	if image.load(normalized) != OK:
		return false
	profile["头像文件"] = normalized
	save_profile()
	profile_changed.emit()
	return true


func _load_json(path: String, default_value: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return default_value
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed != null else default_value


func _save_json(path: String, data: Variant) -> void:
	if not persist_enabled:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  ", false))
