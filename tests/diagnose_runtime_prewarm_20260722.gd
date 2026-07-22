extends SceneTree
## 使用真实显示服务器验证后台菜单场景预热、曲库索引预解析和路由总耗时。

const ROUTE_CASES := ["login", "profile", "mode_select", "submode_select", "song_select"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await create_timer(2.5).timeout
	var router := root.get_node("SceneRouter")
	var library := root.get_node("SongLibrary")
	var game_state := root.get_node("GameState")
	game_state.big_mode = "花式"
	game_state.sub_mode = "club"
	game_state.player_count = 1
	var prewarmed: Dictionary = router.get("_prewarmed_scenes")
	var pending: Dictionary = router.get("_prewarm_pending")
	var queue: Array = router.get("_prewarm_queue")
	print("RUNTIME_PREWARM display=%s scenes=%d pending=%d queue=%d static_loaded=%s thread_alive=%s" % [
		DisplayServer.get_name(),
		prewarmed.size(),
		pending.size(),
		queue.size(),
		str(bool(library.get("_static_index_loaded"))),
		str((library.get("_static_index_thread") as Thread).is_alive()),
	])
	for key in ROUTE_CASES:
		var started := Time.get_ticks_usec()
		router.call("change_to", key, {}, true)
		await scene_changed
		var changed := Time.get_ticks_usec()
		while bool(router.call("is_transition_busy")):
			await process_frame
		var finished := Time.get_ticks_usec()
		print("RUNTIME_ROUTE %s scene_ms=%.3f total_ms=%.3f" % [
			key,
			float(changed - started) / 1000.0,
			float(finished - started) / 1000.0,
		])
	quit(0)
