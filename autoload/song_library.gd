extends Node
## 曲库（autoload: SongLibrary）
## 扫描 songs/<大模式>/<子模式>/<歌曲文件夹#星级>/，只读 sm 头部标签，
## 按 (大模式,子模式) 惰性扫描 + user:// 磁盘缓存（键=目录名列表哈希，目录变化自动重扫）。

const CACHE_DIR := "user://cache"
const CACHE_VERSION := 14
const SEARCH_INDEX_VERSION := 3
const SPEED_FILTER_ALL := "all"
const SPEED_FILTER_VARIABLE := "variable"
const SPEED_FILTER_EXTREME := "extreme"
const SPEED_MIN_ABSOLUTE_DELTA := 4.0
const SPEED_MIN_RELATIVE_DELTA := 0.08
const RUNTIME_ROOT := "res://assets/e5cm_runtime"
const PROJECT_SONGS_ROOT := "res://songs"
const LEGACY_PROJECT_SONGS_ROOT := RUNTIME_ROOT + "/songs"
const STATIC_INDEX_PATH := RUNTIME_ROOT + "/song_index.json"
const RELEASE_INDEX_NAME := "release-song-index.json"
const METADATA_CACHE_PATH := "user://cache/song_metadata_encoding_v1.json"
const METADATA_DECODER_PATH := "res://assets/runtime_support/decode_song_metadata.ps1"

const STYLE_ORDER := ["疯狂", "表演", "混音", "双踏板", "情侣"]
const COMPOUND_STYLE_BY_KEY := {
	"hard": "疯狂",
	"single": "表演",
	"remix": "混音",
	"double": "双踏板",
	"lover": "情侣",
}

signal scan_progress(mode: String, submode: String, current: int, total: int, status: String)
signal search_progress(current: int, total: int, status: String)

var songs_root := PROJECT_SONGS_ROOT
var use_static_index := true

## 大模式 -> songs 子目录（与旧版一致，DIY 目录小写）
const MODE_DIRS := {"花式": "花式", "竞速": "竞速", "DIY": "diy"}

var _cache := {}   # "mode/submode" -> Array[Dictionary]
var _cache_source_stamps := {}  # key -> 子模式目录时间/目录名指纹
var _static_index_loaded := false
var _static_songs := {}
var _static_submodes := {}
var _normalized_static_keys := {}
var _metadata_cache_loaded := false
var _metadata_cache := {}
var _utf8_file_cache := {}
var _metadata_decoder_native := ""
var _search_blob_cache := {}
var _search_index_payloads := {}  # library key -> {fingerprint, payload}
var _scan_song_dir_calls_for_test := 0
var _song_folder_signature_calls_for_test := 0
var _static_index_native_path := ""
var _static_index_is_release_sample := false
var _challenge_index_summary := {}
var _challenge_index_source_path := ""
var _challenge_index_source_modified := 0
var _force_standalone_for_test := false
var _warned_missing_release_index := false
var _static_index_thread := Thread.new()
var _static_index_thread_path := ""


func _ready() -> void:
	var loader := _asset_loader_node()
	if loader != null and loader.has_method("songs_root"):
		songs_root = str(loader.call("songs_root"))
	else:
		songs_root = _resolve_runtime_path("songs")
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	if DisplayServer.get_name().to_lower() != "headless":
		call_deferred("_start_static_index_prewarm")


func _process(_delta: float) -> void:
	_finish_static_index_prewarm(false)


func _exit_tree() -> void:
	_finish_static_index_prewarm(true)


func _start_static_index_prewarm() -> void:
	if _static_index_loaded or not use_static_index or _static_index_thread.is_started():
		return
	var index_path := _preferred_static_index_path()
	if index_path.is_empty():
		return
	_static_index_thread_path = index_path
	var err := _static_index_thread.start(_parse_static_index_worker.bind(index_path))
	if err != OK:
		_static_index_thread_path = ""


func _parse_static_index_worker(index_path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(index_path))


func _finish_static_index_prewarm(wait_for_completion: bool) -> bool:
	if not _static_index_thread.is_started():
		return false
	if not wait_for_completion and _static_index_thread.is_alive():
		return false
	var parsed = _static_index_thread.wait_to_finish()
	var index_path := _static_index_thread_path
	_static_index_thread_path = ""
	_apply_static_index(parsed, index_path)
	return true


func has_cached_songs(mode: String, submode: String) -> bool:
	var key := mode + "/" + submode
	var dir_name := str(MODE_DIRS.get(mode, ""))
	var base := songs_root.path_join(dir_name).path_join(submode)
	return _memory_cache_is_fresh(key, base)


func get_cached_songs(mode: String, submode: String) -> Array:
	var key := mode + "/" + submode
	var dir_name := str(MODE_DIRS.get(mode, ""))
	var base := songs_root.path_join(dir_name).path_join(submode)
	return _cache[key] if _memory_cache_is_fresh(key, base) else []


func _asset_loader_node() -> Node:
	# 纯单元测试会直接 new() SongLibrary 而不把它挂入 SceneTree；
	# 此时调用 get_tree() 本身就会产生日志错误，必须先做无副作用判断。
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null("AssetLoader")


func _resolve_runtime_path(path: String) -> String:
	var loader := _asset_loader_node()
	if loader != null and loader.has_method("abs_path"):
		return str(loader.call("abs_path", path))
	var normalized := path.replace("\\", "/")
	var project_songs_native := ProjectSettings.globalize_path(PROJECT_SONGS_ROOT).replace("\\", "/").trim_suffix("/")
	var selected_songs_root := songs_root.replace("\\", "/").trim_suffix("/")
	if selected_songs_root.is_empty() or selected_songs_root in [PROJECT_SONGS_ROOT, LEGACY_PROJECT_SONGS_ROOT, "songs"]:
		selected_songs_root = project_songs_native
	if normalized == "songs" or normalized == PROJECT_SONGS_ROOT \
			or normalized == LEGACY_PROJECT_SONGS_ROOT:
		return selected_songs_root
	if normalized.begins_with("songs/"):
		return selected_songs_root.path_join(normalized.substr("songs/".length()))
	if normalized.begins_with(PROJECT_SONGS_ROOT + "/"):
		return selected_songs_root.path_join(normalized.substr(PROJECT_SONGS_ROOT.length() + 1))
	if normalized.begins_with(LEGACY_PROJECT_SONGS_ROOT + "/"):
		return selected_songs_root.path_join(
			normalized.substr(LEGACY_PROJECT_SONGS_ROOT.length() + 1))
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return normalized
	if normalized.length() > 1 and normalized[1] == ":":
		return normalized
	return RUNTIME_ROOT.path_join(normalized)


## 大模式下的子模式目录列表（DIY = 曲包目录）
func list_submodes(mode: String) -> Array:
	var dir_name := str(MODE_DIRS.get(mode, ""))
	if dir_name.is_empty():
		return []
	# 子模式页只需要一层目录名。真实 songs 存在时直接枚举几个子目录，
	# 禁止为此解析开发版数千首歌曲的完整 JSON 索引。
	var live_submodes := _list_dirs(songs_root.path_join(dir_name))
	if not live_submodes.is_empty():
		return live_submodes
	_ensure_static_index()
	if use_static_index and mode != "DIY" and _static_submodes.has(mode):
		var indexed_submodes: Array = (_static_submodes[mode] as Array).duplicate()
		var index_is_clean := true
		for indexed_name in indexed_submodes:
			if _looks_mojibake(str(indexed_name)):
				index_is_clean = false
				break
		if index_is_clean:
			# 正式版允许玩家在 songs 下新增整个子模式目录，不能被发行侧车固定列表遮住。
			if _static_index_is_release_sample or _is_standalone_runtime():
				var live_dir_name := str(MODE_DIRS.get(mode, ""))
				for raw_live_submode in _list_dirs(songs_root.path_join(live_dir_name)):
					var live_submode := str(raw_live_submode)
					if not indexed_submodes.has(live_submode):
						indexed_submodes.append(live_submode)
				indexed_submodes.sort()
			return indexed_submodes
		# 老索引中的目录名已经被错误转成 U+FFFD 时，必须回到真实文件系统枚举。
		# 否则不仅标题乱码，整个 DIY 子模式键也无法与当前目录对应。
	var path := songs_root.path_join(dir_name)
	var result := []
	var da := DirAccess.open(path)
	if da == null:
		return []
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if da.current_is_dir() and not entry.begins_with("."):
			result.append(entry)
		entry = da.get_next()
	da.list_dir_end()
	result.sort()
	return result


## 每日/周常挑战只需要“有哪些模式、星级与未玩状态”，不应为此触发完整索引的路径规范化，
## 更不能逐目录扫描上万首曲库。这里从索引原文生成一次轻量摘要并缓存。
func challenge_capabilities_snapshot(records: Dictionary = {}) -> Dictionary:
	var summary := _challenge_capability_index_summary()
	var capabilities := {
		"modes": (summary.get("modes", {}) as Dictionary).duplicate(true),
		"has_unplayed": false,
		"has_breakable_record": false,
		"has_random_source": false,
		"two_player": false,
	}
	for raw_chart_key in summary.get("chart_keys", []):
		var chart_key := str(raw_chart_key)
		var record: Dictionary = records.get(chart_key, {})
		var plays := int(record.get("游玩次数", 0))
		if plays <= 0:
			capabilities["has_unplayed"] = true
		elif int(record.get("最高分", 0)) < 1350000:
			capabilities["has_breakable_record"] = true
		if bool(capabilities["has_unplayed"]) and bool(capabilities["has_breakable_record"]):
			break
	return capabilities


func _challenge_capability_index_summary() -> Dictionary:
	var index_path := _preferred_static_index_path()
	if index_path.is_empty():
		return {}
	var modified := int(FileAccess.get_modified_time(index_path))
	if not _challenge_index_summary.is_empty() \
			and _challenge_index_source_path == index_path \
			and _challenge_index_source_modified == modified:
		return _challenge_index_summary
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(index_path)) != OK or not parser.data is Dictionary:
		return {}
	var parsed: Dictionary = parser.data
	var songs_by_key = parsed.get("songsByKey", {})
	if not songs_by_key is Dictionary:
		return {}
	var modes := {}
	var chart_keys: Array[String] = []
	var seen := {}
	for raw_key in songs_by_key.keys():
		var key := str(raw_key)
		var separator := key.find("/")
		if separator <= 0:
			continue
		var mode := key.substr(0, separator)
		if mode.to_upper() == "DIY":
			mode = "DIY"
		if mode not in ["花式", "竞速", "DIY"]:
			continue
		var mode_info: Dictionary = modes.get(mode, {"count": 0, "stars": []})
		var star_set := {}
		for raw_star in mode_info.get("stars", []):
			star_set[int(raw_star)] = true
		var songs = (songs_by_key as Dictionary).get(raw_key, [])
		if not songs is Array:
			continue
		for raw_song in songs:
			if not raw_song is Dictionary:
				continue
			var song: Dictionary = raw_song
			var chart_key := str(song.get("sm_key", song.get("sm", "")))
			if chart_key.is_empty() or seen.has(chart_key):
				continue
			seen[chart_key] = true
			chart_keys.append(chart_key)
			mode_info["count"] = int(mode_info.get("count", 0)) + 1
			star_set[int(song.get("star", 0))] = true
		var stars: Array = star_set.keys()
		stars.sort()
		mode_info["stars"] = stars
		modes[mode] = mode_info
	_challenge_index_summary = {"modes": modes, "chart_keys": chart_keys}
	_challenge_index_source_path = index_path
	_challenge_index_source_modified = modified
	return _challenge_index_summary


func _scan_cache_path(key: String) -> String:
	return CACHE_DIR.path_join("scan_%s.json" % str(abs(hash(key))))


func _scan_cache_base_modified(base: String) -> int:
	return int(FileAccess.get_modified_time(base)) if DirAccess.open(base) != null else 0


func _is_standalone_runtime() -> bool:
	# Godot 导出模板不会稳定提供 standalone feature；发行预设显式注入 e5cm_release。
	return OS.has_feature("e5cm_release") or _force_standalone_for_test


func _preferred_static_index_path() -> String:
	var sidecar_path := _release_sidecar_index_path()
	if not sidecar_path.is_empty() and FileAccess.file_exists(sidecar_path):
		return sidecar_path
	# 正式 EXE 绝不能回退到 PCK 内的开发机完整索引。侧车丢失时宁可扫描真实 songs，
	# 否则会把开发机上万条歌曲当成已安装内容，形成无封面、不可播放的幽灵曲库。
	if _is_standalone_runtime():
		if not sidecar_path.is_empty() and not _warned_missing_release_index:
			_warned_missing_release_index = true
			push_warning("SongLibrary: 发行侧车索引缺失，改为扫描真实 songs：%s" % sidecar_path)
		return ""
	var runtime_index := _resolve_runtime_path("song_index.json")
	if FileAccess.file_exists(runtime_index):
		return runtime_index
	return STATIC_INDEX_PATH if FileAccess.file_exists(STATIC_INDEX_PATH) else ""


func _cache_source_stamp(base: String) -> String:
	var modified := _scan_cache_base_modified(base)
	# 正式版通常每个模式只有少量歌曲，可额外比较目录名，避免 Windows 秒级时间戳
	# 在“同一秒拖入歌曲”或“同数量替换歌曲”时漏判。开发全量曲库只检查目录时间，
	# 避免每次进入选歌都重新枚举数千个目录。
	if _is_standalone_runtime() or _static_index_is_release_sample:
		var names := PackedStringArray()
		for raw_name in _list_dirs(base):
			names.append(str(raw_name))
		return "%d|%s" % [modified, str(hash("|".join(names)))]
	return str(modified)


func _remember_cache_source(key: String, base: String) -> void:
	_cache_source_stamps[key] = _cache_source_stamp(base)


func _memory_cache_is_fresh(key: String, base: String) -> bool:
	if not _cache.has(key):
		return false
	var current_stamp := _cache_source_stamp(base)
	if not _cache_source_stamps.has(key):
		_cache_source_stamps[key] = current_stamp
		return true
	if str(_cache_source_stamps[key]) == current_stamp:
		return true
	_cache.erase(key)
	_search_index_payloads.erase(key)
	_cache_source_stamps.erase(key)
	return false


func _load_scan_cache_raw(key: String) -> Dictionary:
	var path := _scan_cache_path(key)
	if not FileAccess.file_exists(path):
		return {}
	var cached = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not cached is Dictionary \
			or int(cached.get("version", 0)) != CACHE_VERSION \
			or str(cached.get("songs_root", "")) != songs_root:
		return {}
	return cached


func _load_scan_cache_fast(key: String, base: String) -> Dictionary:
	var cached := _load_scan_cache_raw(key)
	if cached.is_empty() \
			or int(cached.get("base_modified", -1)) != _scan_cache_base_modified(base):
		return {}
	var cached_folders: Dictionary = cached.get("folders", {})
	var current_folders := _list_dirs(base)
	if current_folders.size() != cached_folders.size():
		return {}
	for raw_folder in current_folders:
		var folder := str(raw_folder)
		var previous: Dictionary = cached_folders.get(folder, {})
		if previous.is_empty() \
				or str(previous.get("signature", "")) != _song_folder_signature(base.path_join(folder)):
			return {}
	return cached


## 启动阶段只用子模式目录修改时间判断缓存是否可直接恢复。
## 旧实现每次启动都会重新打开数千个歌曲目录并枚举谱面/音频文件，
## 4123 首社区曲库即使完全没变化也要白扫一遍，等于把“缓存”又验证成了全量扫描。
## 新增/删除/重命名歌曲文件夹会改变 base 修改时间并触发增量扫描；
## 原地修改已有谱面仍可通过同步 get_songs() 的严格校验或 invalidate_cache() 刷新。
func _load_scan_cache_startup(key: String, base: String) -> Dictionary:
	var cached := _load_scan_cache_raw(key)
	if cached.is_empty() \
			or int(cached.get("base_modified", -1)) != _scan_cache_base_modified(base):
		return {}
	if not cached.get("songs", []) is Array or not cached.get("folders", {}) is Dictionary:
		return {}
	return cached


func _save_scan_cache(key: String, base: String, fingerprint: String, songs: Array,
		folder_entries: Dictionary = {}) -> void:
	var output := FileAccess.open(_scan_cache_path(key), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({
			"version": CACHE_VERSION,
			"songs_root": songs_root,
			"base_modified": _scan_cache_base_modified(base),
			"fingerprint": fingerprint,
			"songs": songs,
			"folders": folder_entries,
		}))
		output.close()


func _song_folder_signature(song_dir: String) -> String:
	_song_folder_signature_calls_for_test += 1
	var parts := PackedStringArray([str(int(FileAccess.get_modified_time(song_dir)))])
	var directory := DirAccess.open(song_dir)
	if directory == null:
		return "missing"
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if not directory.current_is_dir():
			var lower := entry.to_lower()
			if lower.ends_with(".sm") or lower.ends_with(".ssc") \
					or lower.ends_with(".json") or lower.ends_with(".mp3") \
					or lower.ends_with(".ogg") or lower.ends_with(".wav") \
					or lower.ends_with(".jpg") or lower.ends_with(".jpeg") \
					or lower.ends_with(".png") or lower.ends_with(".webp") \
					or lower.ends_with(".mp4") or lower.ends_with(".ogv"):
				var path := song_dir.path_join(entry)
				parts.append("%s:%d" % [entry, int(FileAccess.get_modified_time(path))])
		entry = directory.get_next()
	directory.list_dir_end()
	parts.sort()
	return str(hash("|".join(parts)))


func _scan_song_variants(song_dir: String, folder: String, mode: String,
		submode: String) -> Array:
	var song := _scan_song_dir(song_dir, folder, mode, submode)
	if song.is_empty():
		return []
	var sm_path := str(song["sm"])
	if sm_path.to_lower().ends_with(".json"):
		return [song]
	var sm_text := SmParser.read_text(sm_path) if _file_is_utf8(sm_path) else ""
	var candidates := SmParser.collect_candidates(sm_text) if not sm_text.is_empty() else []
	if not sm_text.is_empty():
		var global_profile := build_speed_profile(SmParser.parse_bpms(sm_text))
		song["speed_profile"] = global_profile
		var rows_per_beat := SmParser.parse_rows_per_beat(sm_text)
		for raw_candidate in candidates:
			if not raw_candidate is Dictionary:
				continue
			var candidate: Dictionary = raw_candidate
			var local_bpms := str(candidate.get("local_bpms", "")).strip_edges()
			candidate["speed_profile"] = build_speed_profile(
				SmParser.parse_bpms_raw(local_bpms, rows_per_beat)) \
				if not local_bpms.is_empty() else global_profile.duplicate(true)
	return build_song_variants(song, candidates)


func invalidate_cache(mode: String, submode: String) -> void:
	var key := mode + "/" + submode
	_cache.erase(key)
	_search_index_payloads.erase(key)
	_cache_source_stamps.erase(key)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_scan_cache_path(key)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_search_cache_path(key)))


## 取歌曲列表（带缓存）。每项：
## {folder, name, star, sm, mp3, cover, bpm, mode, submode, sm_key}
func get_songs(mode: String, submode: String) -> Array:
	var key := mode + "/" + submode
	var dir_name := str(MODE_DIRS.get(mode, ""))
	var base := songs_root.path_join(dir_name).path_join(submode)
	if _memory_cache_is_fresh(key, base):
		return _cache[key]
	_ensure_static_index()
	# DIY 是用户可热更新目录，静态索引不能作为真值，否则新增 JSON 谱面永远不可见。
	var static_songs_for_key := _static_songs_for_key(key)
	if use_static_index and mode != "DIY" and not static_songs_for_key.is_empty() \
			and _static_index_matches_installed_folders(mode, submode, static_songs_for_key):
		var indexed_songs: Array = static_songs_for_key.duplicate(true)
		# 先尝试搜索侧车缓存。命中时会连标题/歌手一起恢复，禁止再逐首读取谱面。
		_ensure_search_index_sync(key, indexed_songs,
			_static_search_fingerprint(key, indexed_songs))
		_cache[key] = indexed_songs
		_remember_cache_source(key, base)
		return _cache[key]
	# 外置 DIY/社区曲包优先用“根路径 + 子模式目录修改时间”快速命中。
	# 缓存有效时不再枚举全部歌曲目录，更不会逐个打开谱面/音频。
	var fast_cache := _load_scan_cache_fast(key, base)
	if not fast_cache.is_empty():
		var cached_songs: Array = fast_cache.get("songs", [])
		var cached_fingerprint := str(fast_cache.get("fingerprint", ""))
		_cache[key] = cached_songs
		_remember_cache_source(key, base)
		_ensure_search_index_sync(key, cached_songs, cached_fingerprint)
		return _cache[key]
	var previous_cache := _load_scan_cache_raw(key)
	var previous_folders: Dictionary = previous_cache.get("folders", {})
	var folders := _list_dirs(base)
	var folder_entries := {}
	var signature_parts := PackedStringArray([str(folders.size())])
	var songs := []
	for raw_folder in folders:
		var folder := str(raw_folder)
		var song_dir := base.path_join(folder)
		var signature := _song_folder_signature(song_dir)
		var previous: Dictionary = previous_folders.get(folder, {})
		var variants: Array
		if str(previous.get("signature", "")) == signature \
				and previous.get("songs", []) is Array:
			variants = (previous.get("songs", []) as Array).duplicate(true)
		else:
			variants = _scan_song_variants(song_dir, folder, mode, submode)
		folder_entries[folder] = {"signature": signature, "songs": variants}
		signature_parts.append("%s:%s" % [folder, signature])
		songs.append_array(variants)
	var fingerprint := str(hash("|".join(signature_parts)))
	_repair_song_names(songs)
	songs.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))

	_cache[key] = songs
	_remember_cache_source(key, base)
	_save_scan_cache(key, base, fingerprint, songs, folder_entries)
	_ensure_search_index_sync(key, songs, fingerprint)
	return songs


## 渐进读取歌曲列表。DIY / 社区曲包会把目录指纹和谱面解析拆到多个帧，
## 选歌场景可通过 scan_progress 显示真实进度，避免 Windows 把窗口判定为未响应。
func get_songs_async(mode: String, submode: String) -> Array:
	var key := mode + "/" + submode
	var dir_name := str(MODE_DIRS.get(mode, ""))
	var base := songs_root.path_join(dir_name).path_join(submode)
	if _memory_cache_is_fresh(key, base):
		_emit_scan_progress(mode, submode, 1, 1, "已从内存缓存载入")
		return _cache[key]
	_ensure_static_index()
	var static_songs_for_key := _static_songs_for_key(key)
	if use_static_index and mode != "DIY" and not static_songs_for_key.is_empty() \
			and _static_index_matches_installed_folders(mode, submode, static_songs_for_key):
		_emit_scan_progress(mode, submode, 0, 1, "正在读取曲库索引")
		if is_inside_tree():
			await get_tree().process_frame
		var indexed_songs: Array = static_songs_for_key.duplicate(true)
		# 侧车命中时不再修复/扫描整批谱面；只有首次缺少侧车时才建立一次。
		await _ensure_search_index_async(key, indexed_songs,
			_static_search_fingerprint(key, indexed_songs), mode, submode)
		_cache[key] = indexed_songs
		_remember_cache_source(key, base)
		_emit_scan_progress(mode, submode, 1, 1, "曲库与搜索索引载入完成")
		return _cache[key]
	# 启动时优先信任持久化快照：不再递归打开数千个歌曲文件夹做重复校验。
	# 只要子模式目录本身未发生增删/重命名，就直接恢复歌曲与搜索索引。
	var startup_cache := _load_scan_cache_startup(key, base)
	if not startup_cache.is_empty():
		_emit_scan_progress(mode, submode, 0, 1, "正在恢复曲库缓存")
		var cached_songs: Array = startup_cache.get("songs", [])
		var cached_fingerprint := str(startup_cache.get("fingerprint", ""))
		_cache[key] = cached_songs
		_remember_cache_source(key, base)
		await _ensure_search_index_async(key, cached_songs, cached_fingerprint, mode, submode)
		_emit_scan_progress(mode, submode, 1, 1, "曲库与搜索索引已从缓存恢复")
		return _cache[key]
	var previous_cache := _load_scan_cache_raw(key)
	var previous_folders: Dictionary = previous_cache.get("folders", {})
	var folders := _list_dirs(base)
	var total := maxi(1, folders.size() * 2 + 2)
	_emit_scan_progress(mode, submode, 0, total, "正在检查曲包目录")
	if is_inside_tree():
		await get_tree().process_frame

	var signatures := {}
	for folder_index in folders.size():
		var folder := str(folders[folder_index])
		signatures[folder] = _song_folder_signature(base.path_join(folder))
		_emit_scan_progress(mode, submode, folder_index + 1, total,
			"正在检查曲包 %d / %d" % [folder_index + 1, folders.size()])
		if is_inside_tree() and (folder_index % 8 == 7 or folder_index == folders.size() - 1):
			await get_tree().process_frame

	var songs := []
	var folder_entries := {}
	var signature_parts := PackedStringArray([str(folders.size())])
	for folder_index in folders.size():
		var folder := str(folders[folder_index])
		var signature := str(signatures.get(folder, ""))
		var previous: Dictionary = previous_folders.get(folder, {})
		var variants: Array
		var reused := str(previous.get("signature", "")) == signature \
			and previous.get("songs", []) is Array
		if reused:
			variants = (previous.get("songs", []) as Array).duplicate(true)
		else:
			variants = _scan_song_variants(base.path_join(folder), folder, mode, submode)
		folder_entries[folder] = {"signature": signature, "songs": variants}
		signature_parts.append("%s:%s" % [folder, signature])
		songs.append_array(variants)
		_emit_scan_progress(mode, submode, folders.size() + folder_index + 1, total,
			("正在复用缓存歌曲" if reused else "正在解析变更歌曲") \
				+ " %d / %d" % [folder_index + 1, folders.size()])
		if is_inside_tree() and (folder_index % 8 == 7 or folder_index == folders.size() - 1):
			await get_tree().process_frame

	var fingerprint := str(hash("|".join(signature_parts)))
	_emit_scan_progress(mode, submode, total - 1, total, "正在整理歌曲元数据")
	if is_inside_tree():
		await get_tree().process_frame
	await _repair_song_names_async(songs)
	songs.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	_cache[key] = songs
	_remember_cache_source(key, base)
	_save_scan_cache(key, base, fingerprint, songs, folder_entries)
	await _ensure_search_index_async(key, songs, fingerprint, mode, submode)
	_emit_scan_progress(mode, submode, total, total, "歌曲缓存与搜索索引建立完成")
	return songs


func _emit_scan_progress(mode: String, submode: String, current: int, total: int,
		status: String) -> void:
	scan_progress.emit(mode, submode, clampi(current, 0, maxi(1, total)), maxi(1, total), status)


func _release_sidecar_index_path() -> String:
	var override_path := OS.get_environment("E5CM_RELEASE_INDEX_PATH").strip_edges()
	if not override_path.is_empty():
		return override_path.replace("\\", "/")
	if _is_standalone_runtime():
		return OS.get_executable_path().get_base_dir().path_join(RELEASE_INDEX_NAME).replace("\\", "/")
	return ""


func _ensure_static_index() -> void:
	if _static_index_loaded or not use_static_index:
		return
	if _static_index_thread.is_started():
		_finish_static_index_prewarm(true)
		return
	# 正式版只认 EXE 同目录的精选索引；侧车丢失时扫描实际 songs，禁止读取开发机完整索引。
	var static_index_path := _preferred_static_index_path()
	if static_index_path.is_empty():
		_static_index_loaded = true
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(static_index_path))
	_apply_static_index(parsed, static_index_path)


func _apply_static_index(parsed, static_index_path: String) -> void:
	_static_index_loaded = true
	_static_index_native_path = static_index_path
	if not parsed is Dictionary or int(parsed.get("schemaVersion", 0)) != 1:
		return
	_static_songs = parsed.get("songsByKey", {})
	_static_submodes = parsed.get("submodesByMode", {})
	_static_index_is_release_sample = not str(parsed.get("releaseVersion", "")).is_empty() \
			or parsed.has("releaseSeed")
	_normalized_static_keys.clear()


## 只在真正进入某个子模式时规范化该键的路径。
## list_submodes() 只需要目录名，不应同步处理完整索引中的数千首歌。
func _static_songs_for_key(key: String) -> Array:
	if not _static_songs is Dictionary or not _static_songs.has(key):
		return []
	if bool(_normalized_static_keys.get(key, false)):
		return _static_songs[key] as Array if _static_songs[key] is Array else []
	var raw_songs = _static_songs[key]
	if not raw_songs is Array:
		_normalized_static_keys[key] = true
		return []
	var normalized_songs: Array = []
	for raw_song in raw_songs:
		if not raw_song is Dictionary:
			continue
		var song: Dictionary = raw_song.duplicate(true)
		for field in ["sm", "mp3", "cover", "video"]:
			var path := str(song.get(field, ""))
			if not path.is_empty():
				song[field] = _resolve_runtime_path(path)
		normalized_songs.append(song)
	_static_songs[key] = normalized_songs
	_normalized_static_keys[key] = true
	return normalized_songs


func _looks_mojibake(text: String) -> bool:
	var value := text.strip_edges()
	return value.contains("�") or value.contains("锟斤拷") or value.contains("ï¿½")


func _native_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _load_metadata_cache() -> void:
	if _metadata_cache_loaded:
		return
	_metadata_cache_loaded = true
	_metadata_cache = {}
	if not FileAccess.file_exists(METADATA_CACHE_PATH):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(METADATA_CACHE_PATH))
	if parsed is Dictionary:
		_metadata_cache = parsed


func _save_metadata_cache() -> void:
	var output := FileAccess.open(METADATA_CACHE_PATH, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(_metadata_cache))
		output.close()


func _metadata_decoder_native_path() -> String:
	if not _metadata_decoder_native.is_empty() and FileAccess.file_exists(_metadata_decoder_native):
		return _metadata_decoder_native
	if not FileAccess.file_exists(METADATA_DECODER_PATH):
		return ""
	# 导出后脚本位于 PCK 内，不能直接交给 powershell.exe 执行；先释放到 user://。
	var source_text := FileAccess.get_file_as_string(METADATA_DECODER_PATH)
	if source_text.is_empty():
		return ""
	var target_path := CACHE_DIR.path_join("decode_song_metadata_v1.ps1")
	var existing := FileAccess.get_file_as_string(target_path) \
		if FileAccess.file_exists(target_path) else ""
	if existing != source_text:
		var target := FileAccess.open(target_path, FileAccess.WRITE)
		if target == null:
			return ""
		target.store_string(source_text)
		target.close()
	_metadata_decoder_native = ProjectSettings.globalize_path(target_path)
	return _metadata_decoder_native


func _run_metadata_decoder_job(requests: Array, decoder_native: String) -> Dictionary:
	var token := "%s_%s_%s" % [Time.get_ticks_msec(), OS.get_thread_caller_id(),
		abs(hash(str(requests)))]
	var request_path := CACHE_DIR.path_join("metadata_request_%s.json" % token)
	var output_path := CACHE_DIR.path_join("metadata_output_%s.json" % token)
	var request_file := FileAccess.open(request_path, FileAccess.WRITE)
	if request_file == null:
		return {"exit_code": FileAccess.get_open_error(), "decoded": [], "output": []}
	request_file.store_string(JSON.stringify(requests))
	request_file.close()
	var command_output: Array = []
	var args := PackedStringArray([
		"-NoProfile", "-ExecutionPolicy", "Bypass",
		"-File", decoder_native,
		"-InputPath", ProjectSettings.globalize_path(request_path),
		"-OutputPath", ProjectSettings.globalize_path(output_path),
	])
	var exit_code := OS.execute("powershell.exe", args, command_output, true, false)
	var decoded: Array = []
	if exit_code == 0 and FileAccess.file_exists(output_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(output_path))
		if parsed is Array:
			decoded = parsed
	DirAccess.remove_absolute(ProjectSettings.globalize_path(request_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output_path))
	return {"exit_code": exit_code, "decoded": decoded, "output": command_output}


func _metadata_decoder_result(job_result) -> Array:
	if not job_result is Dictionary:
		return []
	var result := job_result as Dictionary
	var exit_code := int(result.get("exit_code", FAILED))
	if exit_code != 0:
		var output: Array = result.get("output", [])
		push_warning("SongLibrary: 曲库元数据跨编码解码失败：%s" %
			"\n".join(PackedStringArray(output)))
		return []
	var decoded = result.get("decoded", [])
	return decoded if decoded is Array else []


func _decode_song_metadata_batch(requests: Array) -> Array:
	if requests.is_empty() or OS.get_name() != "Windows":
		return []
	var decoder_native := _metadata_decoder_native_path()
	if decoder_native.is_empty() or not FileAccess.file_exists(decoder_native):
		return []
	return _metadata_decoder_result(_run_metadata_decoder_job(requests, decoder_native))


func _decode_song_metadata_batch_async(requests: Array) -> Array:
	if requests.is_empty() or OS.get_name() != "Windows":
		return []
	var decoder_native := _metadata_decoder_native_path()
	if decoder_native.is_empty() or not FileAccess.file_exists(decoder_native):
		return []
	var worker := Thread.new()
	var start_error := worker.start(_run_metadata_decoder_job.bind(
		requests.duplicate(true), decoder_native))
	if start_error != OK:
		push_warning("SongLibrary: 元数据解码线程启动失败，回退同步兼容路径")
		return _decode_song_metadata_batch(requests)
	while worker.is_alive():
		if is_inside_tree():
			await get_tree().process_frame
		else:
			OS.delay_msec(1)
	return _metadata_decoder_result(worker.wait_to_finish())


func _prepare_song_name_repair(songs: Array) -> Dictionary:
	_load_metadata_cache()
	var requests: Array = []
	var request_context := {}
	for i in songs.size():
		if not songs[i] is Dictionary:
			continue
		var song: Dictionary = songs[i]
		var current_name := str(song.get("name", ""))
		var current_artist := str(song.get("artist", "")).strip_edges()
		var artist_missing := current_artist.is_empty() or _looks_mojibake(current_artist)
		# 搜索索引必须在曲库缓存阶段同时拿到歌手字段，不能等用户搜索时再逐首读谱面。
		if not _looks_mojibake(current_name) \
				and not bool(song.get("metadata_needs_decode", false)) \
				and not artist_missing:
			continue
		var sm_path := str(song.get("sm", ""))
		if sm_path.is_empty() or not FileAccess.file_exists(sm_path):
			continue
		var modified := int(FileAccess.get_modified_time(sm_path))
		var cached: Dictionary = _metadata_cache.get(sm_path, {})
		var cached_title := str(cached.get("title", ""))
		var cached_artist := str(cached.get("artist", ""))
		if int(cached.get("modified", -1)) == modified \
				and not cached_title.is_empty() and not _looks_mojibake(cached_title):
			song["name"] = cached_title
			if not cached_artist.is_empty() and not _looks_mojibake(cached_artist):
				song["artist"] = cached_artist
			song.erase("metadata_needs_decode")
			songs[i] = song
			continue
		var request_id := str(i)
		requests.append({"id": request_id, "path": _native_path(sm_path)})
		request_context[request_id] = {"index": i, "path": sm_path, "modified": modified}
	return {"requests": requests, "context": request_context}


func _apply_song_name_repair_results(songs: Array, request_context: Dictionary,
		decoded: Array) -> bool:
	var cache_changed := false
	for raw_result in decoded:
		if not raw_result is Dictionary:
			continue
		var result: Dictionary = raw_result
		var request_id := str(result.get("id", ""))
		if not request_context.has(request_id):
			continue
		var title := str(result.get("title", "")).strip_edges()
		var artist := str(result.get("artist", "")).strip_edges()
		if title.is_empty() or _looks_mojibake(title):
			continue
		var context: Dictionary = request_context[request_id]
		var index := int(context["index"])
		if index < 0 or index >= songs.size() or not songs[index] is Dictionary:
			continue
		var song: Dictionary = songs[index]
		song["name"] = title
		if not artist.is_empty() and not _looks_mojibake(artist):
			song["artist"] = artist
		song.erase("metadata_needs_decode")
		songs[index] = song
		_metadata_cache[str(context["path"])] = {
			"modified": int(context["modified"]),
			"title": title,
			"artist": artist,
			"encoding": str(result.get("encoding", "")),
		}
		cache_changed = true
	return cache_changed


func _repair_song_names(songs: Array) -> void:
	var plan := _prepare_song_name_repair(songs)
	var requests: Array = plan.get("requests", [])
	var request_context: Dictionary = plan.get("context", {})
	if _apply_song_name_repair_results(songs, request_context,
			_decode_song_metadata_batch(requests)):
		_save_metadata_cache()


func _repair_song_names_async(songs: Array) -> void:
	var plan := _prepare_song_name_repair(songs)
	var requests: Array = plan.get("requests", [])
	var request_context: Dictionary = plan.get("context", {})
	var decoded := await _decode_song_metadata_batch_async(requests)
	if _apply_song_name_repair_results(songs, request_context, decoded):
		_save_metadata_cache()


func decode_song_metadata_for_test(path: String) -> Dictionary:
	var decoded := _decode_song_metadata_batch([{"id": "0", "path": _native_path(path)}])
	return decoded[0] if not decoded.is_empty() and decoded[0] is Dictionary else {}


func decode_song_metadata_async_for_test(path: String) -> Dictionary:
	var decoded := await _decode_song_metadata_batch_async(
		[{"id": "0", "path": _native_path(path)}])
	return decoded[0] if not decoded.is_empty() and decoded[0] is Dictionary else {}


func repair_song_names_for_test(source: Array) -> Array:
	var songs := source.duplicate(true)
	_repair_song_names(songs)
	return songs


func repair_song_names_async_for_test(source: Array) -> Array:
	var songs := source.duplicate(true)
	await _repair_song_names_async(songs)
	return songs


## 一个 SM 可能同时包含疯狂/表演/混音/双踏板/情侣复合谱；按原版规则拆成可独立筛选的歌曲项。
static func build_song_variants(base_song: Dictionary, candidates: Array) -> Array:
	var compound_best := {}
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		var columns := _candidate_columns(candidate)
		var mode_key := _compound_mode_key(candidate, columns)
		if mode_key.is_empty():
			continue
		var star := _candidate_star(candidate, int(base_song.get("star", 0)), true)
		var existing: Dictionary = compound_best.get(mode_key, {})
		if existing.is_empty() or star > int(existing.get("star", 0)) \
				or (star == int(existing.get("star", 0)) \
				and columns > int(existing.get("columns", 0))):
			compound_best[mode_key] = {
				"charttype": str(candidate.get("charttype", "")).strip_edges().to_lower(),
				"star": star,
				"columns": columns,
				"speed_profile": (candidate.get("speed_profile", {}) as Dictionary).duplicate(true),
			}

	if not compound_best.is_empty():
		var variants := []
		for mode_key in ["hard", "single", "remix", "double", "lover"]:
			if not compound_best.has(mode_key):
				continue
			var info: Dictionary = compound_best[mode_key]
			var song := base_song.duplicate(true)
			var charttype := str(info["charttype"])
			song["style"] = str(COMPOUND_STYLE_BY_KEY[mode_key])
			song["charttype"] = charttype
			song["star"] = int(info["star"])
			if not (info.get("speed_profile", {}) as Dictionary).is_empty():
				song["speed_profile"] = (info.get("speed_profile", {}) as Dictionary).duplicate(true)
			song["is_compound"] = true
			song["sm_key"] = "%s::charttype=%s" % [str(base_song.get("sm_key", "")), charttype]
			variants.append(song)
		return variants

	var song := base_song.duplicate(true)
	var preferred := _preferred_candidate(candidates)
	if not preferred.is_empty():
		var charttype := str(preferred.get("charttype", "")).strip_edges().to_lower()
		song["charttype"] = charttype
		song["style"] = _style_for_candidate(preferred)
		if not (preferred.get("speed_profile", {}) as Dictionary).is_empty():
			song["speed_profile"] = (preferred.get("speed_profile", {}) as Dictionary).duplicate(true)
	else:
		song["charttype"] = ""
		song["style"] = ""
	if str(song["style"]).is_empty():
		song["style"] = _style_for_submode(str(base_song.get("submode", "")))
	song["is_compound"] = false
	return [song]


static func build_speed_profile(bpms: Array, playable_until_beat := INF) -> Dictionary:
	var collapsed: Array = []
	for raw_entry in bpms:
		if not raw_entry is Array or raw_entry.size() < 2:
			continue
		var beat := float(raw_entry[0])
		var bpm := float(raw_entry[1])
		if not is_finite(beat) or not is_finite(bpm) or bpm <= 0.0:
			continue
		if is_finite(float(playable_until_beat)) and beat > float(playable_until_beat) + 0.001:
			continue
		if collapsed.is_empty():
			collapsed.append([beat, bpm])
			continue
		var previous_bpm := float((collapsed[-1] as Array)[1])
		var duplicate_tolerance := maxf(0.01, minf(previous_bpm, bpm) * 0.001)
		if absf(bpm - previous_bpm) <= duplicate_tolerance:
			continue
		collapsed.append([beat, bpm])

	if collapsed.is_empty():
		return {
			"variable": false, "extreme": false, "change_count": 0,
			"segment_count": 0, "min_bpm": 0.0, "max_bpm": 0.0, "ratio": 1.0,
		}

	var min_bpm := float((collapsed[0] as Array)[1])
	var max_bpm := min_bpm
	var meaningful_changes := 0
	for i in collapsed.size():
		var bpm := float((collapsed[i] as Array)[1])
		min_bpm = minf(min_bpm, bpm)
		max_bpm = maxf(max_bpm, bpm)
		if i <= 0:
			continue
		var previous := float((collapsed[i - 1] as Array)[1])
		var absolute_delta := absf(bpm - previous)
		var relative_delta := absolute_delta / maxf(0.001, minf(previous, bpm))
		if absolute_delta >= SPEED_MIN_ABSOLUTE_DELTA \
				and relative_delta >= SPEED_MIN_RELATIVE_DELTA:
			meaningful_changes += 1
	var ratio := max_bpm / maxf(0.001, min_bpm)
	var variable := meaningful_changes > 0
	# 1/2×、2× BPM 是常见节奏写法，只归入普通变速；
	# 极端变速只标记 Nu ABO 一类超低速、超高速或跨度巨大的花活谱。
	var extreme := variable and (min_bpm <= 20.0 or max_bpm >= 400.0 or ratio >= 4.0)
	return {
		"variable": variable,
		"extreme": extreme,
		"change_count": meaningful_changes,
		"segment_count": collapsed.size(),
		"min_bpm": min_bpm,
		"max_bpm": max_bpm,
		"ratio": ratio,
	}


static func normalize_speed_filter(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	return normalized if normalized in [SPEED_FILTER_VARIABLE, SPEED_FILTER_EXTREME] \
		else SPEED_FILTER_ALL


static func speed_filter_label(value: String) -> String:
	match normalize_speed_filter(value):
		SPEED_FILTER_VARIABLE:
			return "变速谱"
		SPEED_FILTER_EXTREME:
			return "极端变速"
	return ""


static func song_matches_speed_filter(song: Dictionary, speed_filter: String) -> bool:
	var wanted := normalize_speed_filter(speed_filter)
	if wanted == SPEED_FILTER_ALL:
		return true
	var profile: Dictionary = song.get("speed_profile", {})
	return bool(profile.get("extreme", false)) if wanted == SPEED_FILTER_EXTREME \
		else bool(profile.get("variable", false))


static func filter_songs(source: Array, style: String, star: int,
		speed_filter := SPEED_FILTER_ALL) -> Array:
	var wanted_style := style.strip_edges()
	var wanted_star := clampi(star, 0, 20)
	var wanted_speed := normalize_speed_filter(str(speed_filter))
	return source.filter(func(song):
		return song is Dictionary \
			and (wanted_style.is_empty() or str(song.get("style", "")) == wanted_style) \
			and (wanted_star == 0 or int(song.get("star", 0)) == wanted_star) \
			and song_matches_speed_filter(song, wanted_speed))


func _search_cache_path(key: String) -> String:
	return CACHE_DIR.path_join("search_%s.json" % str(abs(hash(key))))


func _static_search_fingerprint(key: String, songs: Array) -> String:
	var modified := int(FileAccess.get_modified_time(_static_index_native_path)) \
		if not _static_index_native_path.is_empty() and FileAccess.file_exists(_static_index_native_path) else 0
	return "static:%s:%d:%d" % [key, modified, songs.size()]


func _song_search_id(song: Dictionary, fallback_index := -1) -> String:
	for field in ["sm_key", "sm", "folder"]:
		var value := str(song.get(field, "")).strip_edges()
		if not value.is_empty():
			return value
	return "song:%d:%s:%s" % [fallback_index, song.get("name", ""), song.get("artist", "")]


func _make_search_blob(song: Dictionary) -> String:
	return _search_normalized("%s %s %s %s" % [
		song.get("name", ""), song.get("artist", ""), song.get("folder", ""),
		song.get("subtitle", ""),
	])


static func classify_title_language(title: String) -> String:
	var has_hangul := false
	var has_kana := false
	var has_han := false
	var has_latin := false
	for i in title.length():
		var code := title.unicode_at(i)
		if (code >= 0xAC00 and code <= 0xD7AF) \
				or (code >= 0x1100 and code <= 0x11FF) \
				or (code >= 0x3130 and code <= 0x318F):
			has_hangul = true
		elif (code >= 0x3040 and code <= 0x30FF) \
				or (code >= 0x31F0 and code <= 0x31FF) \
				or (code >= 0xFF66 and code <= 0xFF9F):
			has_kana = true
		elif (code >= 0x3400 and code <= 0x4DBF) \
				or (code >= 0x4E00 and code <= 0x9FFF) \
				or (code >= 0xF900 and code <= 0xFAFF):
			has_han = true
		elif (code >= 0x41 and code <= 0x5A) or (code >= 0x61 and code <= 0x7A):
			has_latin = true
	if has_hangul:
		return "韩文"
	if has_kana:
		return "日文"
	if has_han:
		return "中文"
	if has_latin:
		return "英文"
	return "其他"


func filter_songs_by_title_language(source: Array, language: String) -> Array:
	var wanted := language.strip_edges()
	if wanted.is_empty() or wanted == "全部":
		return source.duplicate()
	return source.filter(func(raw_song):
		if not raw_song is Dictionary:
			return false
		var song := raw_song as Dictionary
		var detected := str(song.get("_title_language", ""))
		if detected.is_empty():
			detected = classify_title_language(str(song.get("name", "")))
		return detected == wanted
	)


func _search_bigrams(text: String) -> Array:
	var unique := {}
	if text.length() < 2:
		return []
	for i in text.length() - 1:
		unique[text.substr(i, 2)] = true
	return unique.keys()


func _attach_search_payload(source: Array, key: String, payload: Dictionary) -> bool:
	var ids: Array = payload.get("ids", [])
	var blobs: Array = payload.get("blobs", [])
	var names: Array = payload.get("names", [])
	var artists: Array = payload.get("artists", [])
	var subtitles: Array = payload.get("subtitles", [])
	var languages: Array = payload.get("languages", [])
	var grams = payload.get("grams", {})
	if ids.size() != source.size() or blobs.size() != source.size() \
			or names.size() != source.size() or artists.size() != source.size() \
			or subtitles.size() != source.size() or languages.size() != source.size() \
			or not grams is Dictionary:
		return false
	for i in source.size():
		if not source[i] is Dictionary:
			return false
		var song: Dictionary = source[i]
		if not str(names[i]).is_empty():
			song["name"] = str(names[i])
		song["artist"] = str(artists[i])
		song["subtitle"] = str(subtitles[i])
		song["_title_language"] = str(languages[i])
		song["_search_key"] = key
		song["_search_index_pos"] = i
		song["_search_id"] = str(ids[i])
		song["_search_blob"] = str(blobs[i])
		_search_blob_cache[str(ids[i])] = str(blobs[i])
		source[i] = song
	return true


func _build_search_index_payload(source: Array, key: String,
		allow_metadata_read := true) -> Dictionary:
	if allow_metadata_read:
		# 一次性批量补齐乱码标题与缺失歌手；搜索阶段禁止再做这件事。
		_repair_song_names(source)
	var ids: Array = []
	var blobs: Array = []
	var names: Array = []
	var artists: Array = []
	var subtitles: Array = []
	var languages: Array = []
	var grams := {}
	for i in source.size():
		if not source[i] is Dictionary:
			ids.append("invalid:%d" % i)
			blobs.append("")
			names.append("")
			artists.append("")
			subtitles.append("")
			languages.append("其他")
			continue
		var song: Dictionary = source[i]
		if allow_metadata_read and str(song.get("artist", "")).strip_edges().is_empty():
			_ensure_song_artist(song)
		var search_id := _song_search_id(song, i)
		var blob := _make_search_blob(song)
		ids.append(search_id)
		blobs.append(blob)
		names.append(str(song.get("name", "")))
		artists.append(str(song.get("artist", "")))
		subtitles.append(str(song.get("subtitle", "")))
		languages.append(classify_title_language(str(song.get("name", ""))))
		for gram in _search_bigrams(blob):
			if not grams.has(gram):
				grams[gram] = []
			(grams[gram] as Array).append(i)
	var payload := {
		"version": SEARCH_INDEX_VERSION,
		"ids": ids,
		"blobs": blobs,
		"names": names,
		"artists": artists,
		"subtitles": subtitles,
		"languages": languages,
		"grams": grams,
	}
	_attach_search_payload(source, key, payload)
	return payload


func _load_search_index_cache(key: String, fingerprint: String, source: Array) -> bool:
	var path := _search_cache_path(key)
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary \
			or int(parsed.get("version", 0)) != SEARCH_INDEX_VERSION \
			or str(parsed.get("fingerprint", "")) != fingerprint:
		return false
	var payload: Dictionary = parsed.get("payload", {})
	if not _attach_search_payload(source, key, payload):
		return false
	_search_index_payloads[key] = {"fingerprint": fingerprint, "payload": payload}
	return true


func _save_search_index_cache(key: String, fingerprint: String,
		payload: Dictionary) -> void:
	var output := FileAccess.open(_search_cache_path(key), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({
			"version": SEARCH_INDEX_VERSION,
			"fingerprint": fingerprint,
			"payload": payload,
		}))
		output.close()


func _ensure_search_index_sync(key: String, source: Array, fingerprint: String) -> void:
	var existing: Dictionary = _search_index_payloads.get(key, {})
	if str(existing.get("fingerprint", "")) == fingerprint \
			and _attach_search_payload(source, key, existing.get("payload", {})):
		return
	if _load_search_index_cache(key, fingerprint, source):
		return
	var payload := _build_search_index_payload(source, key, true)
	_search_index_payloads[key] = {"fingerprint": fingerprint, "payload": payload}
	_save_search_index_cache(key, fingerprint, payload)


func _ensure_search_index_async(key: String, source: Array, fingerprint: String,
		mode: String, submode: String) -> void:
	var existing: Dictionary = _search_index_payloads.get(key, {})
	if str(existing.get("fingerprint", "")) == fingerprint \
			and _attach_search_payload(source, key, existing.get("payload", {})):
		_emit_scan_progress(mode, submode, 1, 1, "歌曲搜索索引已在内存中就绪")
		return
	if _load_search_index_cache(key, fingerprint, source):
		_emit_scan_progress(mode, submode, 1, 1, "歌曲搜索索引已从缓存载入")
		return

	# 缓存建立阶段一次性补齐歌手并生成搜索文本；这里允许慢，正式搜索不再读谱面。
	_emit_scan_progress(mode, submode, 0, maxi(1, source.size()), "正在补齐歌曲搜索元数据")
	if is_inside_tree():
		await get_tree().process_frame
	await _repair_song_names_async(source)
	var ids: Array = []
	var blobs: Array = []
	var names: Array = []
	var artists: Array = []
	var subtitles: Array = []
	var languages: Array = []
	var grams := {}
	var total := maxi(1, source.size())
	for i in source.size():
		var song: Dictionary = source[i] if source[i] is Dictionary else {}
		if str(song.get("artist", "")).strip_edges().is_empty():
			_ensure_song_artist(song)
		var search_id := _song_search_id(song, i)
		var blob := _make_search_blob(song)
		ids.append(search_id)
		blobs.append(blob)
		names.append(str(song.get("name", "")))
		artists.append(str(song.get("artist", "")))
		subtitles.append(str(song.get("subtitle", "")))
		languages.append(classify_title_language(str(song.get("name", ""))))
		for gram in _search_bigrams(blob):
			if not grams.has(gram):
				grams[gram] = []
			(grams[gram] as Array).append(i)
		if (i + 1) % 32 == 0 or i == source.size() - 1:
			_emit_scan_progress(mode, submode, i + 1, total,
				"正在建立歌曲搜索索引 %d / %d" % [i + 1, source.size()])
			if is_inside_tree() and i < source.size() - 1:
				await get_tree().process_frame
	var payload := {
		"version": SEARCH_INDEX_VERSION,
		"ids": ids,
		"blobs": blobs,
		"names": names,
		"artists": artists,
		"subtitles": subtitles,
		"languages": languages,
		"grams": grams,
	}
	_attach_search_payload(source, key, payload)
	_search_index_payloads[key] = {"fingerprint": fingerprint, "payload": payload}
	_save_search_index_cache(key, fingerprint, payload)
	_emit_scan_progress(mode, submode, total, total, "歌曲缓存与搜索索引建立完成")


func _search_payload_for_source(source: Array) -> Dictionary:
	if source.is_empty() or not source[0] is Dictionary:
		return {}
	var key := str((source[0] as Dictionary).get("_search_key", ""))
	if key.is_empty():
		return {}
	for raw_song in source:
		if not raw_song is Dictionary or str(raw_song.get("_search_key", "")) != key:
			return {}
	var entry: Dictionary = _search_index_payloads.get(key, {})
	return entry.get("payload", {})


func _search_from_index(source: Array, needle: String) -> Array:
	var payload := _search_payload_for_source(source)
	if payload.is_empty():
		# 极端兼容分支：只生成内存搜索文本，不允许在用户点击搜索后读取谱面文件。
		var fallback_key := "runtime:%s" % abs(hash(str(source.size()) + needle))
		payload = _build_search_index_payload(source, fallback_key, false)
		_search_index_payloads[fallback_key] = {"fingerprint": "runtime", "payload": payload}
	var grams: Dictionary = payload.get("grams", {})
	var candidate_bucket: Array = []
	var has_candidate_bucket := false
	for gram in _search_bigrams(needle):
		var bucket: Array = grams.get(gram, [])
		if bucket.is_empty():
			return []
		if not has_candidate_bucket or bucket.size() < candidate_bucket.size():
			candidate_bucket = bucket
			has_candidate_bucket = true
	var candidate_set := {}
	if has_candidate_bucket:
		for index in candidate_bucket:
			candidate_set[int(index)] = true
	var result := []
	for raw_song in source:
		if not raw_song is Dictionary:
			continue
		var position := int(raw_song.get("_search_index_pos", -1))
		if has_candidate_bucket and not candidate_set.has(position):
			continue
		var blob := str(raw_song.get("_search_blob", ""))
		if blob.contains(needle):
			result.append(raw_song)
	return result


func _song_search_blob(song: Dictionary, allow_metadata_read := false) -> String:
	var prebuilt := str(song.get("_search_blob", ""))
	if not prebuilt.is_empty():
		return prebuilt
	var cache_key := _song_search_id(song)
	var artist_missing := str(song.get("artist", "")).strip_edges().is_empty()
	if _search_blob_cache.has(cache_key) and not (allow_metadata_read and artist_missing):
		return str(_search_blob_cache[cache_key])
	if allow_metadata_read:
		_ensure_song_artist(song)
	var blob := _make_search_blob(song)
	_search_blob_cache[cache_key] = blob
	return blob


func search_songs(source: Array, keyword: String) -> Array:
	var needle := _search_normalized(keyword)
	if needle.is_empty():
		return source.duplicate()
	return _search_from_index(source, needle)


func search_songs_async(source: Array, keyword: String, _batch_size := 12,
		should_cancel := Callable()) -> Array:
	var needle := _search_normalized(keyword)
	if needle.is_empty():
		search_progress.emit(1, 1, "已显示全部歌曲")
		return source.duplicate()
	search_progress.emit(0, 2, "正在查询歌曲搜索索引")
	if is_inside_tree():
		await get_tree().process_frame
	if should_cancel.is_valid() and bool(should_cancel.call()):
		search_progress.emit(0, 2, "搜索已取消")
		return []
	search_progress.emit(1, 2, "正在校验索引候选结果")
	var result := _search_from_index(source, needle)
	if is_inside_tree():
		await get_tree().process_frame
	if should_cancel.is_valid() and bool(should_cancel.call()):
		search_progress.emit(1, 2, "搜索已取消")
		return []
	search_progress.emit(2, 2, "索引查询完成，找到 %d 首" % result.size())
	return result


func build_search_index_for_test(source: Array) -> void:
	var key := "__test__:%s" % abs(hash(str(source.size()) + str(Time.get_ticks_usec())))
	var payload := _build_search_index_payload(source, key, false)
	_search_index_payloads[key] = {"fingerprint": "test", "payload": payload}


func search_index_ready_for_test(source: Array) -> bool:
	if source.is_empty():
		return true
	var payload := _search_payload_for_source(source)
	if payload.is_empty() or (payload.get("blobs", []) as Array).size() != source.size():
		return false
	for raw_song in source:
		if not raw_song is Dictionary or str(raw_song.get("_search_blob", "")).is_empty():
			return false
	return true


func search_index_payload_for_test(source: Array) -> Dictionary:
	return _search_payload_for_source(source).duplicate(true)


static func _search_normalized(text: String) -> String:
	var value := text.strip_edges().to_lower()
	var separator := RegEx.new()
	separator.compile("[\\s_\\-·•—–/\\\\]+")
	return separator.sub(value, "", true)


func _ensure_song_artist(song: Dictionary) -> void:
	if not str(song.get("artist", "")).strip_edges().is_empty():
		return
	var path := str(song.get("sm", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	if path.to_lower().ends_with(".json"):
		var metadata := _json_song_metadata(path)
		song["artist"] = str(metadata.get("artist", ""))
		if str(song.get("name", "")).strip_edges().is_empty():
			song["name"] = str(metadata.get("title", ""))
		return
	if _file_is_utf8(path):
		var head := _read_head(path, 8192)
		song["artist"] = SmParser.extract_tag(head, "ARTIST").strip_edges()


static func available_styles(source: Array) -> Array:
	var found := {}
	for song in source:
		var style := str(song.get("style", "")).strip_edges()
		if not style.is_empty():
			found[style] = true
	var result := []
	for style in STYLE_ORDER:
		if found.erase(style):
			result.append(style)
	var other: Array = found.keys()
	other.sort()
	result.append_array(other)
	return result


static func available_stars(source: Array, style: String = "") -> Array:
	var found := {}
	var wanted_style := style.strip_edges()
	for song in source:
		if not wanted_style.is_empty() and str(song.get("style", "")) != wanted_style:
			continue
		var star := clampi(int(song.get("star", 0)), 0, 20)
		if star > 0:
			found[star] = true
	var result: Array = found.keys()
	result.sort()
	return result


static func _candidate_columns(candidate: Dictionary) -> int:
	if candidate.has("columns"):
		return int(candidate["columns"])
	return SmParser.count_columns(str(candidate.get("notes", "")))


static func _normalized(text: String) -> String:
	var re := RegEx.new()
	re.compile("[\\s_\\-]+")
	return re.sub(text.strip_edges().to_lower(), "", true)


static func _compound_mode_key(candidate: Dictionary, columns: int) -> String:
	if columns not in [10, 20]:
		return ""
	var charttype := str(candidate.get("charttype", "")).strip_edges().to_lower()
	if charttype in ["hard", "single", "remix", "double"]:
		return charttype
	if charttype in ["lover", "lover1", "lover2"]:
		return "lover"
	var context := _normalized("%s %s %s" % [candidate.get("description", ""),
		candidate.get("difficulty", ""), candidate.get("context_tag", "")])
	if context.contains("lover") or context.contains("couple") or context.contains("情侣"):
		return "lover"
	return ""


static func _candidate_star(candidate: Dictionary, fallback: int, prefer_level: bool) -> int:
	if prefer_level:
		var level_re := RegEx.new()
		level_re.compile("(?i)\\blevel\\s*([0-9]+)\\b")
		for field in ["description", "difficulty"]:
			var match := level_re.search(str(candidate.get(field, "")))
			if match:
				return clampi(int(match.get_string(1)), 1, 20)
	var number_re := RegEx.new()
	number_re.compile("[0-9]+")
	var meter_match := number_re.search(str(candidate.get("meter", "")))
	if meter_match:
		return clampi(int(meter_match.get_string()), 1, 20)
	return clampi(fallback, 0, 20)


static func _style_for_candidate(candidate: Dictionary) -> String:
	var charttype := str(candidate.get("charttype", "")).strip_edges().to_lower()
	var text := _normalized("%s %s %s %s" % [charttype, candidate.get("description", ""),
		candidate.get("difficulty", ""), candidate.get("context_tag", "")])
	if text.contains("lover") or text.contains("couple") or text.contains("情侣"):
		return "情侣"
	if charttype == "hard":
		return "疯狂"
	if charttype == "remix":
		return "混音"
	if charttype.contains("double") or charttype.contains("routine"):
		return "双踏板"
	if charttype.contains("single"):
		return "表演"
	return ""


static func _style_for_submode(submode: String) -> String:
	var text := submode.strip_edges()
	var lower := text.to_lower()
	if lower.contains("club") or text.contains("双踏板"):
		return "双踏板"
	for style in ["疯狂", "表演", "混音", "情侣"]:
		if text.contains(style):
			return style
	return text


static func _preferred_candidate(candidates: Array) -> Dictionary:
	var best := {}
	var best_priority := -1
	for candidate in candidates:
		if not candidate is Dictionary:
			continue
		var charttype := str(candidate.get("charttype", "")).strip_edges().to_lower()
		var priority := 10
		if charttype.contains("pump-single"):
			priority = 50
		elif charttype.contains("dance-single"):
			priority = 45
		elif charttype == "hard":
			priority = 42
		elif charttype.contains("single"):
			priority = 40
		elif charttype == "remix":
			priority = 35
		elif charttype.contains("pump-double"):
			priority = 30
		elif charttype.contains("double"):
			priority = 20
		elif charttype in ["lover1", "lover2"]:
			priority = 18
		if priority > best_priority:
			best = candidate
			best_priority = priority
	return best


func _list_dirs(path: String) -> Array:
	var result := []
	var da := DirAccess.open(path)
	if da == null:
		return result
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if da.current_is_dir() and not entry.begins_with("."):
			result.append(entry)
		entry = da.get_next()
	da.list_dir_end()
	result.sort()
	return result


func _static_index_matches_installed_folders(mode: String, submode: String,
		raw_indexed_songs) -> bool:
	# 正式包索引只含每个模式最多 4 首。开发目录重新放回完整 songs 后，
	# 不能继续把这个发行抽样索引当成完整曲库，否则界面永远只显示 4 首。
	if not _static_index_is_release_sample:
		return true
	if not raw_indexed_songs is Array:
		return false
	var dir_name := str(MODE_DIRS.get(mode, ""))
	if dir_name.is_empty():
		return false
	var installed_folders := _list_dirs(songs_root.path_join(dir_name).path_join(submode))
	var indexed_folders := {}
	for raw_song in raw_indexed_songs as Array:
		if raw_song is Dictionary:
			var song: Dictionary = raw_song
			var folder := str(song.get("folder", "")).strip_edges()
			if not folder.is_empty():
				indexed_folders[folder] = true
			# 索引指向的谱面、音频或封面已丢失时不能继续展示幽灵条目。
			for field in ["sm", "mp3", "cover"]:
				var path := str(song.get(field, "")).strip_edges()
				if not path.is_empty() and not FileAccess.file_exists(path):
					return false
	if installed_folders.size() != indexed_folders.size():
		return false
	for raw_folder in installed_folders:
		if not indexed_folders.has(str(raw_folder)):
			return false
	# 只有真实目录集合与发行索引完全一致时才继续秒开。
	return true


func _json_song_metadata(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {"title": "", "artist": "", "bpm": 0.0, "style": "表演",
			"charttype": "json-single", "columns": 5, "couple": false,
			"speed_profile": build_speed_profile([])}
	var title := ""
	for key in ["title", "songName", "song_name", "name", "musicName", "歌曲名"]:
		title = str(parsed.get(key, "")).strip_edges()
		if not title.is_empty():
			break
	var artist := ""
	for key in ["artist", "singer", "author", "composer", "歌手", "作者"]:
		artist = str(parsed.get(key, "")).strip_edges()
		if not artist.is_empty():
			break
	var bpm := 0.0
	for raw_bpm in parsed.get("bpms", []):
		if raw_bpm is Dictionary:
			bpm = float(raw_bpm.get("bpmVal", raw_bpm.get("bpm", 0.0)))
			if bpm > 0.0:
				break
	if bpm <= 0.0:
		bpm = float(parsed.get("bpm", parsed.get("BPM", 0.0)))
	var mode_info := SmParser.json_mode_info_from_data(parsed)
	var bpm_metadata := SmParser.json_bpm_metadata_from_data(parsed)
	var normalized_bpms: Array = bpm_metadata.get("bpms", [])
	var last_playable_beat := float(bpm_metadata.get("last_playable_beat", INF))
	return {"title": title, "artist": artist, "bpm": bpm,
		"style": str(mode_info.get("style", "表演")),
		"charttype": str(mode_info.get("charttype", "json-single")),
		"columns": int(mode_info.get("columns", 5)),
		"couple": bool(mode_info.get("couple", false)),
		"speed_profile": build_speed_profile(normalized_bpms, last_playable_beat)}


func json_song_mode_for_test(path: String) -> Dictionary:
	var metadata := _json_song_metadata(path)
	return {"style": metadata.get("style", "表演"),
		"charttype": metadata.get("charttype", "json-single"),
		"columns": metadata.get("columns", 5), "couple": metadata.get("couple", false)}


func _json_song_bpm(path: String) -> float:
	return float(_json_song_metadata(path).get("bpm", 0.0))


func _scan_song_dir(song_dir: String, folder: String, mode: String, submode: String) -> Dictionary:
	_scan_song_dir_calls_for_test += 1
	var da := DirAccess.open(song_dir)
	if da == null:
		return {}
	var sm_file := ""
	var json_file := ""
	var mp3_file := ""
	var cover_file := ""
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not da.current_is_dir():
			var lower := entry.to_lower()
			if sm_file.is_empty() and (lower.ends_with(".sm") or lower.ends_with(".ssc")):
				sm_file = entry
			elif json_file.is_empty() and lower.ends_with(".json"):
				json_file = entry
			elif mp3_file.is_empty() and (lower.ends_with(".mp3") or lower.ends_with(".ogg")):
				mp3_file = entry
			elif lower == "bann.jpg" or (cover_file.is_empty() and (lower.ends_with(".jpg") or lower.ends_with(".png"))):
				cover_file = entry
		entry = da.get_next()
	da.list_dir_end()
	if sm_file.is_empty():
		sm_file = json_file
	if sm_file.is_empty():
		return {}

	# 星级：文件夹名末尾 #数字（1~20）
	var star := 0
	var star_re := RegEx.new()
	star_re.compile("#\\s*(\\d+)\\s*$")
	var m := star_re.search(folder)
	if m:
		star = clampi(int(m.get_string(1)), 1, 20)

	# 名称：UTF-8 谱面直接读 TITLE；GB18030/GBK 谱面交给后续批量解码器。
	var sm_abs := song_dir.path_join(sm_file)
	var is_json := sm_file.to_lower().ends_with(".json")
	var metadata_needs_decode := false if is_json else not _file_is_utf8(sm_abs)
	var name := ""
	var artist := ""
	var bpm := 0.0
	var style := ""
	var charttype := ""
	var columns := 5
	var couple := false
	var speed_profile := build_speed_profile([])
	if is_json:
		var json_metadata := _json_song_metadata(sm_abs)
		name = str(json_metadata.get("title", ""))
		artist = str(json_metadata.get("artist", ""))
		bpm = float(json_metadata.get("bpm", 0.0))
		style = str(json_metadata.get("style", "表演"))
		charttype = str(json_metadata.get("charttype", "json-single"))
		columns = int(json_metadata.get("columns", 5))
		couple = bool(json_metadata.get("couple", false))
		speed_profile = (json_metadata.get("speed_profile", {}) as Dictionary).duplicate(true)
	else:
		var head := _read_head(sm_abs, 8192)
		if not head.is_empty():
			name = SmParser.extract_tag(head, "TITLE")
			artist = SmParser.extract_tag(head, "ARTIST").strip_edges()
			bpm = SmParser.parse_display_bpm(head)
			speed_profile = build_speed_profile(SmParser.parse_bpms(head))
			if mp3_file.is_empty():
				var music := SmParser.extract_tag(head, "MUSIC")
				if not music.is_empty() and FileAccess.file_exists(song_dir.path_join(music)):
					mp3_file = music
	var tag_re := RegEx.new()
	tag_re.compile("\\s*\\[[^\\]]*\\]\\s*$")
	name = tag_re.sub(name, "").strip_edges()
	if name.is_empty():
		var base_name := folder
		if m:
			base_name = folder.substr(0, m.get_start()).strip_edges()
		var parts := base_name.split("#")
		name = str(parts[1]) if parts.size() >= 2 else base_name

	# sm_key：songs/ 相对路径（与旧版歌曲记录键一致）
	var sm_key := "songs/" + sm_abs.replace("\\", "/").split("/songs/", true, 1)[1] \
		if sm_abs.replace("\\", "/").contains("/songs/") else sm_abs

	return {
		"folder": folder,
		"name": name,
		"artist": artist,
		"star": star,
		"sm": sm_abs,
		"sm_key": sm_key,
		"mp3": song_dir.path_join(mp3_file) if not mp3_file.is_empty() else "",
		"cover": song_dir.path_join(cover_file) if not cover_file.is_empty() else "",
		"bpm": bpm,
		"mode": mode,
		"submode": submode,
		"metadata_needs_decode": metadata_needs_decode,
		"chart_format": "json" if is_json else sm_file.get_extension().to_lower(),
		"style": style,
		"charttype": charttype,
		"columns": columns,
		"couple": couple,
		"speed_profile": speed_profile,
	}


func reset_scan_song_dir_calls_for_test() -> void:
	_scan_song_dir_calls_for_test = 0


func scan_song_dir_calls_for_test() -> int:
	return _scan_song_dir_calls_for_test


func reset_song_folder_signature_calls_for_test() -> void:
	_song_folder_signature_calls_for_test = 0


func song_folder_signature_calls_for_test() -> int:
	return _song_folder_signature_calls_for_test


func clear_memory_cache_for_test() -> void:
	_cache.clear()
	_cache_source_stamps.clear()
	_search_index_payloads.clear()


func _is_valid_utf8(data: PackedByteArray) -> bool:
	var i := 0
	while i < data.size():
		var first := int(data[i])
		if first <= 0x7F:
			i += 1
			continue
		var needed := 0
		var second_min := 0x80
		var second_max := 0xBF
		if first >= 0xC2 and first <= 0xDF:
			needed = 1
		elif first == 0xE0:
			needed = 2
			second_min = 0xA0
		elif first >= 0xE1 and first <= 0xEC:
			needed = 2
		elif first == 0xED:
			needed = 2
			second_max = 0x9F
		elif first >= 0xEE and first <= 0xEF:
			needed = 2
		elif first == 0xF0:
			needed = 3
			second_min = 0x90
		elif first >= 0xF1 and first <= 0xF3:
			needed = 3
		elif first == 0xF4:
			needed = 3
			second_max = 0x8F
		else:
			return false
		if i + needed >= data.size():
			return false
		var second := int(data[i + 1])
		if second < second_min or second > second_max:
			return false
		for offset in range(2, needed + 1):
			var continuation := int(data[i + offset])
			if continuation < 0x80 or continuation > 0xBF:
				return false
		i += needed + 1
	return true


func _file_is_utf8(path: String) -> bool:
	if _utf8_file_cache.has(path):
		return bool(_utf8_file_cache[path])
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_utf8_file_cache[path] = false
		return false
	var result := _is_valid_utf8(file.get_buffer(file.get_length()))
	_utf8_file_cache[path] = result
	return result


func _read_head(path: String, bytes: int) -> String:
	if not _file_is_utf8(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var buf := f.get_buffer(mini(bytes, f.get_length()))
	if buf.size() >= 3 and buf[0] == 0xEF and buf[1] == 0xBB and buf[2] == 0xBF:
		buf = buf.slice(3)
	return buf.get_string_from_utf8()
