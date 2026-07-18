extends RefCounted
## 将 Godot 内部字段映射到双端共享的稳定状态结构。


func export(scene_name: String, scene: Node, state_id: String) -> Dictionary:
	var canonical_name := scene_name
	var scene_state := {"name": canonical_name}
	match scene_name:
		"coin":
			scene_state.merge({
				"phase": str(scene.get("_stage")),
				"focusedPlayers": int(scene.get("_pedal_pick")),
				"selectionAnimating": bool(scene.get("_switching")),
				"backgroundTimeSeconds": scene.get_meta("parity_background_time", null),
			})
		"login":
			scene_state["phase"] = "login"
		"profile":
			scene_state["nickname"] = str(ProfileStore.profile.get("昵称", ""))
			var profile_stats: Dictionary = ProfileStore.profile.get("统计", {})
			var profile_progress: Dictionary = ProfileStore.profile.get("进度", {})
			var fancy: Dictionary = profile_progress.get("花式", {})
			var racing: Dictionary = profile_progress.get("竞速", {})
			scene_state.merge({
				"playMinutes": int(profile_stats.get("游玩时长分钟", 0)),
				"sCount": int(profile_stats.get("累计评价S数", 0)),
				"maxCombo": int(profile_stats.get("最大Combo", 0)),
				"maxComboSong": str(profile_stats.get("最大Combo曲目", "")),
				"bestScore": int(profile_stats.get("最高分", 0)),
				"bestScoreSong": str(profile_stats.get("最高分曲目", "")),
				"fancyLevel": int(fancy.get("等级", 1)),
				"fancyExperience": float(fancy.get("经验", 0.0)),
				"racingLevel": int(racing.get("等级", 1)),
				"racingExperience": float(racing.get("经验", 0.0)),
			})
		"mode_select":
			scene_state["selectedMode"] = str(GameState.big_mode)
		"submode_select":
			scene_state["selectedMode"] = str(GameState.sub_mode)
		"song_select":
			scene_state["phase"] = "detail" if bool(scene.detail.is_open()) else "list"
		"loading":
			scene_state["phase"] = "loading"
		"gameplay":
			if scene.esc_menu != null and scene.esc_menu.is_open():
				scene_state["phase"] = "paused"
			elif scene.ready_anim != null and scene.ready_anim.visible:
				scene_state["phase"] = "ready"
			else:
				scene_state["phase"] = "running"
			scene_state["timeSeconds"] = float(scene.conductor.get_chart_time_raw()) \
				if scene.conductor != null else 0.0
			if scene.hp != null:
				scene_state["health"] = float(scene.hp.visible_ratio())
				scene_state["totalHealth"] = int(scene.hp.hp)
				scene_state["visibleHealth"] = int(scene.hp.visible_hp())
				scene_state["overdrive"] = bool(scene.hp.is_overdrive())
			if scene.score != null:
				scene_state["score"] = int(scene.score.current_score)
				scene_state["combo"] = int(scene.score.current_combo)
			var nickname := scene.get_node_or_null("LegacyTopHud/Nickname") as Label
			var song_title := scene.get_node_or_null("LegacyTopHud/SongTitle") as Label
			var stars := scene.get_node_or_null("LegacyTopHud/Stars") as Label
			var countdown := scene.get_node_or_null("LegacyTopHud/Countdown") as Label
			var stage_board := scene.get_node_or_null("LegacyTopHud/StageBoard") as CanvasItem
			var stage_spectrum := scene.get_node_or_null("LegacyTopHud/StageSpectrum") as CanvasItem
			if nickname != null:
				scene_state["nickname"] = nickname.text
				scene_state["nicknameFontSize"] = nickname.get_theme_font_size("font_size")
			if song_title != null and stars != null and countdown != null \
					and stage_board != null and stage_spectrum != null:
				scene_state["rightHud"] = {
					"songTitle": song_title.text,
					"stars": stars.text,
					"countdown": countdown.text,
					"layers": {
						"spectrum": stage_spectrum.z_index,
						"board": stage_board.z_index,
						"songTitle": song_title.z_index,
						"stars": stars.z_index,
						"countdown": countdown.z_index,
					},
				}
			if scene.get("_hp_overdrive_material") != null:
				scene_state["overdrivePhasePixels"] = float(
					scene.get("_hp_overdrive_material").get_shader_parameter("phase_pixels"))
		"settlement":
			scene_state["grade"] = str(scene.payload.get("评级", ""))
	return {
		"stateId": state_id,
		"global": {
			"credit": GameState.credits,
			"players": GameState.player_count,
			"majorMode": GameState.big_mode,
			"subMode": GameState.sub_mode,
		},
		"scene": scene_state,
	}
