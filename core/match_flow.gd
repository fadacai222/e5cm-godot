class_name MatchFlow
extends RefCounted
## 对局流程（3+1 把）+ 正式局经验汇总 —— 移植自旧项目 core/对局状态.py 与 core/等级经验.py 的局级逻辑
## 规则：
##  - 一局 3 首正式歌；第 1~3 把评 S 累计 S 数（上限 3）
##  - 第 3 把结束时 S 数=3 且未赠送过 -> 赠送第四把
##  - 每首歌结束立即入账并持久化；局内缓存只用于连续 S 倍率与整局经验汇总
##  - 第 4 把（赠送歌）静默入账

var current_round := 1        # 对局_当前把数（1~9 夹取）
var s_count := 0              # 对局_S次数（0~3）
var bonus_fourth := false     # 对局_赠送第四把

# 正式局经验缓存
var _exp_cache := {"模式": "", "歌曲": [], "连续S数": 0}


func start_new_match() -> void:
	current_round = 1
	s_count = 0
	bonus_fourth = false
	clear_exp_cache()


func clear_exp_cache() -> void:
	_exp_cache = {"模式": "", "歌曲": [], "连续S数": 0}


## 曲末结算：更新 S 数与赠送标记，返回 {结算后S数, 三把S赠送, 本局后赠送第四把}
func settle_round(grade: String, failed: bool) -> Dictionary:
	var round_n := clampi(current_round, 1, 9)
	var got_s := (not failed) and grade.strip_edges().to_upper() == "S"
	var s_after := s_count
	if round_n <= 3 and got_s:
		s_after = mini(3, s_count + 1)
	var triple_s_gift := round_n == 3 and s_after >= 3 and not bonus_fourth
	var bonus_after := bonus_fourth or triple_s_gift

	s_count = s_after
	bonus_fourth = bonus_after
	return {
		"结算后S数": s_after,
		"三把S赠送": triple_s_gift,
		"是否赠送第四把": bonus_after,
	}


## 歌曲经验结算（对应旧版 处理歌曲经验结算）
## 返回字典含：结算类型（正式局缓存/正式局结算/赠送歌静默入账）、经验增加值、模式进度、显示奖励窗、显示升级动画
func settle_song_exp(mode_key: String, progress: Dictionary, round_n: int,
		grade: String, cool_n: int, good_n: int, miss_n: int) -> Dictionary:
	round_n = maxi(1, round_n)
	var normalized := ExpSystem.normalize_progress(progress)

	# 第 4 把及以后：赠送歌静默入账
	if round_n > ExpSystem.MATCH_SONG_COUNT:
		clear_exp_cache()
		var gift := ExpSystem.gift_song_result(grade)
		var gift_deposit := _deposit_song_exp(normalized, float(gift["最终经验"]))
		return {
			"结算类型": "赠送歌静默入账",
			"经验增加值": int(roundf(float(gift_deposit["实际增加经验"]))),
			"单首歌结果": gift,
			"经验结算": gift_deposit,
			"模式进度": gift_deposit["模式进度"],
			"显示奖励窗": false,
			"显示升级动画": false,
		}

	_ensure_cache(mode_key, round_n)
	var streak := int(_exp_cache.get("连续S数", 0))
	var result := ExpSystem.song_result(grade, cool_n, good_n, miss_n, streak)

	_cache_song_result(mode_key, round_n, result)
	var songs: Array = _exp_cache["歌曲"].duplicate(true)
	var total := 0
	for song in songs:
		total += int(song.get("最终经验", 0))

	# 每一把只追加本首经验。这样即使玩家中途退出、崩溃或重启，已经完成的歌曲也不会丢经验。
	var deposit := _deposit_song_exp(normalized, float(result["最终经验"]))
	var response := {
		"结算类型": "正式局单曲入账" if round_n < ExpSystem.MATCH_SONG_COUNT else "正式局结算",
		"经验增加值": int(roundf(float(deposit["实际增加经验"]))),
		"缓存经验值": int(result["最终经验"]),
		"缓存累计经验": total,
		"正式局总经验": total,
		"单首歌结果": result,
		"正式局歌曲": songs,
		"模式进度": deposit["模式进度"],
		"经验结算": deposit,
		"预览缓存": false,
		"缓存把数": round_n,
		"显示奖励窗": true,
		"显示升级动画": int(deposit["升级次数"]) > 0,
	}
	if round_n >= ExpSystem.MATCH_SONG_COUNT:
		clear_exp_cache()
	return response


func _deposit_song_exp(progress: Dictionary, add_exp: float) -> Dictionary:
	var deposit := ExpSystem.deposit_exp(progress, add_exp)
	var mode_progress: Dictionary = (deposit.get("模式进度", progress) as Dictionary).duplicate(true)
	mode_progress["累计歌曲"] = int(progress.get("累计歌曲", 0)) + 1
	mode_progress["累计首数"] = int(progress.get("累计首数", 0)) + 1
	deposit["模式进度"] = mode_progress
	return deposit


func _ensure_cache(mode_key: String, round_n: int) -> void:
	if round_n <= 1:
		clear_exp_cache()
	if str(_exp_cache.get("模式", "")) != mode_key:
		_exp_cache = {"模式": mode_key, "歌曲": [], "连续S数": 0}
	_exp_cache["模式"] = mode_key


func _cache_song_result(mode_key: String, round_n: int, result: Dictionary) -> void:
	var songs: Array = _exp_cache.get("歌曲", []).duplicate(true)
	round_n = clampi(round_n, 1, ExpSystem.MATCH_SONG_COUNT)
	if round_n <= 1:
		songs = []
	elif songs.size() >= round_n:
		songs = songs.slice(0, round_n - 1)
	songs.append(result.duplicate(true))
	_exp_cache["模式"] = mode_key
	_exp_cache["歌曲"] = songs.slice(0, ExpSystem.MATCH_SONG_COUNT)
	_exp_cache["连续S数"] = clampi(int(result.get("连续S计数", 0)), 0, ExpSystem.MATCH_SONG_COUNT)
