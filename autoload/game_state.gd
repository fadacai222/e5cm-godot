extends Node
## 全局对局状态（autoload: GameState）
## 对应旧项目 main.py 的"状态"字典 + core/对局状态.py。
## 投币监听放在这里：任意场景按投币键都生效（对齐旧版，结算续币等待时也要能投币）。

signal credits_changed(credits: int)

const CREDITS_PER_GAME := 3
const CREDIT_STORE_PATH := "user://credits.cfg"

var credits := 0
var credit_store_path := CREDIT_STORE_PATH
var persist_credits := true
var player_count := 1
var big_mode := ""        # 花式 / 竞速 / DIY
var sub_mode := ""        # 疯狂 / club / 情侣 / 混音 / 学习 / 表演 / DIY曲包名
var flow := MatchFlow.new()

# 选歌状态恢复载荷（结算返回选歌时使用）
var song_select_restore := {}


func _ready() -> void:
	reload_credits()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("coin"):
		insert_coin()


func insert_coin(count: int = 1) -> bool:
	if count <= 0:
		return false
	var before := credits
	credits = maxi(0, credits + count)
	if credits <= before:
		return false
	_save_credits()
	credits_changed.emit(credits)
	AudioDirector.play_sfx(AssetLoader.sound("投币音效"), "global.coin_insert")
	return true


func has_enough_credits() -> bool:
	return credits >= CREDITS_PER_GAME


func consume_credits(count: int = CREDITS_PER_GAME) -> void:
	credits = maxi(0, credits - count)
	_save_credits()
	credits_changed.emit(credits)


func reload_credits() -> void:
	var config := ConfigFile.new()
	if config.load(credit_store_path) == OK:
		credits = maxi(0, int(config.get_value("credit", "balance", 0)))
	else:
		credits = 0
	credits_changed.emit(credits)


func _save_credits() -> void:
	if not persist_credits:
		return
	var config := ConfigFile.new()
	config.set_value("credit", "balance", maxi(0, credits))
	config.save(credit_store_path)


## 投币场景选择 1P/2P 后调用：扣费 + 初始化对局流程
func start_match(p_player_count: int) -> void:
	consume_credits(CREDITS_PER_GAME)
	player_count = clampi(p_player_count, 1, 2)
	flow.start_new_match()
	ProfileStore.clear_mode_progress_preview()


## 结算选"否"/超时回投币时调用
func reset_flow_state() -> void:
	flow.start_new_match()
	ProfileStore.clear_mode_progress_preview()
	big_mode = ""
	sub_mode = ""
	song_select_restore = {}
