extends Node
## 全局对局状态（autoload: GameState）
## 对应旧项目 main.py 的"状态"字典 + core/对局状态.py。
## 投币监听放在这里：任意场景按投币键都生效（对齐旧版，结算续币等待时也要能投币）。

signal credits_changed(credits: int)

const CREDITS_PER_GAME := 3
const CREDIT_STORE_PATH := "user://credits.cfg"
const COIN_HOLD_DELAY_SEC := 0.30
const COIN_HOLD_REPEAT_SEC := 0.06
const COIN_HOLD_MAX_REPEATS_PER_FRAME := 16

var credits := 0
var credit_store_path := CREDIT_STORE_PATH
var persist_credits := true
var player_count := 1
var big_mode := ""        # 花式 / 竞速 / DIY
var sub_mode := ""        # 疯狂 / club / 情侣 / 混音 / 学习 / 表演 / DIY曲包名
var flow := MatchFlow.new()

# 选歌状态恢复载荷（结算返回选歌时使用）
var song_select_restore := {}

var _coin_hold_active := false
var _coin_repeat_countdown := COIN_HOLD_DELAY_SEC


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload_credits()


func _process(delta: float) -> void:
	if not _coin_hold_active:
		return
	# 某些场景会消费按键松开事件；每帧核对物理状态，避免切场景后幽灵投币。
	if not Input.is_action_pressed("coin"):
		_end_coin_hold()
		return
	_tick_coin_hold(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("coin"):
		_begin_coin_hold()
	elif event.is_action_released("coin"):
		_end_coin_hold()


func _begin_coin_hold() -> bool:
	if _coin_hold_active:
		return false
	_coin_hold_active = true
	_coin_repeat_countdown = COIN_HOLD_DELAY_SEC
	return insert_coin()


func _end_coin_hold() -> void:
	_coin_hold_active = false
	_coin_repeat_countdown = COIN_HOLD_DELAY_SEC


func _tick_coin_hold(delta: float) -> int:
	if not _coin_hold_active or delta <= 0.0:
		return 0
	var remaining := delta
	var repeated := 0
	while remaining + 1e-6 >= _coin_repeat_countdown \
			and repeated < COIN_HOLD_MAX_REPEATS_PER_FRAME:
		remaining -= _coin_repeat_countdown
		_coin_repeat_countdown = COIN_HOLD_REPEAT_SEC
		if insert_coin():
			repeated += 1
		else:
			break
	_coin_repeat_countdown = maxf(0.0, _coin_repeat_countdown - remaining)
	return repeated


## 测试入口：复用正式长按状态机，不依赖真实键盘设备。
func coin_hold_begin_for_test() -> bool:
	return _begin_coin_hold()


func coin_hold_tick_for_test(delta: float) -> int:
	return _tick_coin_hold(delta)


func coin_hold_end_for_test() -> void:
	_end_coin_hold()


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
