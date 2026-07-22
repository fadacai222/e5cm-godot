class_name RewardCatalog
extends RefCounted
## 奖励与玩家表达统一目录 v5：称号、头像框、玩家卡全部由代码主题系统绘制。
## 视觉奖励全部数据驱动，场景不允许按 reward_id 写特判。

const CATALOG_VERSION := 5
const VALID_SLOTS := [
	"title", "avatar_frame", "profile_card", "settlement_signature",
	"coin_sfx", "menu_sfx", "combo_theme",
]
const VALID_TYPES := [
	"title", "avatar_frame", "profile_card", "settlement_signature",
	"sound", "combo_theme",
]
const VALID_RARITIES := ["common", "rare", "epic", "legendary"]
const RARITY_DISPLAY_NAMES := {
	"common": "普通",
	"rare": "稀有",
	"epic": "史诗",
	"legendary": "传说",
}
const SLOT_ALIASES := {"frame": "avatar_frame", "card": "profile_card"}
const VALID_SURFACES := ["song_select", "gameplay", "esc_profile", "profile", "settlement"]
const IDENTITY_SURFACES := ["song_select", "gameplay", "esc_profile", "profile", "settlement"]
const CARD_SURFACES := ["song_select", "esc_profile", "profile", "settlement"]
const ART_ATLASES := {}
const ART_INDEX_LIMITS := {"avatar_frame": 12, "profile_card": 8}


static func rarity_display_name(rarity: String) -> String:
	return str(RARITY_DISPLAY_NAMES.get(rarity.strip_edges().to_lower(), "普通"))


const DEFAULT_VISUALS := {
	"title": {
		"visible": false,
		"primary_color": "#8EEBFF",
		"secondary_color": "#29E9FF",
		"text_color": "#F4FBFF",
		"style": "none",
	},
	"avatar_frame": {
		"visible": false,
		"border_color": "#FFD84A",
		"accent_color": "#29E9FF",
		"glow_color": "#29E9FF55",
		"thickness": 3.0,
		"style": "default",
		"dynamic": false,
	},
	"profile_card": {
		"visible": true,
		"fill_color": "#02102AF2",
		"header_color": "#052E4DB8",
		"border_color": "#29E9FFEA",
		"secondary_color": "#FF3CCFE0",
		"inner_color": "#6AC7FF55",
		"scanline_color": "#47B3FF0D",
		"rank_color": "#FFD84A",
		"style": "stable_default",
		"art_index": 0,
		"art_opacity": 0.90,
		"dynamic": false,
	},
	"settlement_signature": {"visible": false},
	"coin_sfx": {"visible": false},
	"menu_sfx": {"visible": false},
	"combo_theme": {"visible": false},
}

const ITEMS := {
	"title_daily_rookie": {
		"slot": "title", "type": "title", "name": "今日新星",
		"description": "完成每日挑战后获得的清爽身份标签。",
		"unlock_hint": "完成指定每日挑战",
		"rarity": "common", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"primary_color": "#29E9FF", "secondary_color": "#8EEBFF",
			"text_color": "#F4FBFF", "style": "cyan_chip", "badge": "DAILY", "art_index": 0},
	},
	"title_rhythm_worker": {
		"slot": "title", "type": "title", "name": "节奏打卡员",
		"description": "坚持完成节奏目标的进阶称号。",
		"unlock_hint": "完成指定进阶挑战",
		"rarity": "rare", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"primary_color": "#FF3CCF", "secondary_color": "#29E9FF",
			"text_color": "#FFF5FD", "style": "dual_chip", "badge": "RHYTHM", "art_index": 2},
	},
	"title_weekly_runner": {
		"slot": "title", "type": "title", "name": "周常冲刺者",
		"description": "完成周常目标后解锁的金色身份标签。",
		"unlock_hint": "完成指定周常挑战",
		"rarity": "rare", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"primary_color": "#FFD84A", "secondary_color": "#FF3CCF",
			"text_color": "#FFF8D6", "style": "gold_chip", "badge": "WEEKLY", "art_index": 3},
	},
	"frame_neon_cyan": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "霓虹青头像框",
		"description": "青色双环与短刻度构成的轻量头像框。",
		"unlock_hint": "完成指定每日挑战",
		"rarity": "common", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"border_color": "#29E9FF", "accent_color": "#8EEBFF",
			"glow_color": "#29E9FF66", "thickness": 4.0, "style": "neon_ticks",
			"safe_inset_ratio": 0.08, "art_index": 0, "dynamic": false},
	},
	"frame_neon_magenta": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "霓虹粉头像框",
		"description": "洋红主环与青色定位光组成的稀有头像框。",
		"unlock_hint": "完成指定高难挑战",
		"rarity": "rare", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"border_color": "#FF3CCF", "accent_color": "#29E9FF",
			"glow_color": "#FF3CCF66", "thickness": 4.5, "style": "neon_ticks",
			"safe_inset_ratio": 0.08, "art_index": 1, "dynamic": false},
	},
	"card_grid_blue": {
		"slot": "profile_card", "type": "profile_card", "name": "蓝色网格玩家卡",
		"description": "深蓝网格与双主色结构线组成的玩家卡主题。",
		"unlock_hint": "完成指定周常挑战",
		"rarity": "common", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "esc_profile", "profile", "settlement"],
		"visual": {"fill_color": "#03172EF2", "header_color": "#073A5CC8",
			"border_color": "#29E9FF", "secondary_color": "#FF3CCF",
			"inner_color": "#8EEBFF55", "scanline_color": "#3D9CFF18",
			"rank_color": "#FFD84A", "style": "blue_grid", "art_index": 0, "art_opacity": 0.96, "dynamic": false},
	},
	"title_streak_3": {
		"slot": "title", "type": "title", "name": "三日连拍",
		"description": "连续活跃三天的纪念称号。", "unlock_hint": "连续活跃 3 天",
		"rarity": "common", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"primary_color": "#72F7B8", "secondary_color": "#29E9FF",
			"text_color": "#EEFFF7", "style": "mint_chip", "badge": "STREAK 3", "art_index": 1},
	},
	"frame_streak_7": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "七日极光头像框",
		"description": "连续活跃七天解锁的青金双色头像框。", "unlock_hint": "连续活跃 7 天",
		"rarity": "rare", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"border_color": "#72F7B8", "accent_color": "#FFD84A",
			"glow_color": "#72F7B866", "thickness": 4.5, "style": "aurora_ticks",
			"safe_inset_ratio": 0.08, "art_index": 5, "dynamic": false},
	},
	"card_streak_30": {
		"slot": "profile_card", "type": "profile_card", "name": "月度星轨玩家卡",
		"description": "连续活跃三十天的传奇玩家卡。", "unlock_hint": "连续活跃 30 天",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "esc_profile", "profile", "settlement"],
		"visual": {"fill_color": "#12082FF4", "header_color": "#3B176EC8",
			"border_color": "#FFD84A", "secondary_color": "#FF3CCF",
			"inner_color": "#B58CFF66", "scanline_color": "#C9A6FF18",
			"rank_color": "#FFF1A8", "style": "star_track", "art_index": 5, "art_opacity": 0.97, "dynamic": false},
	},
	"title_full_combo": {
		"slot": "title", "type": "title", "name": "全连猎手",
		"description": "首次完成正式全连时获得。", "unlock_hint": "首次正式 ALL COMBO",
		"rarity": "rare", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"primary_color": "#FFD84A", "secondary_color": "#29E9FF",
			"text_color": "#FFF8D6", "style": "combo_chip", "badge": "ALL COMBO", "art_index": 2},
	},
	"frame_all_perfect": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "完美光环头像框",
		"description": "首次正式 ALL PERFECT 的金白纪念框。", "unlock_hint": "首次正式 ALL PERFECT",
		"rarity": "epic", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"border_color": "#FFF4B0", "accent_color": "#FFD84A",
			"glow_color": "#FFF4B088", "thickness": 5.0, "style": "perfect_halo",
			"safe_inset_ratio": 0.09, "art_index": 6, "dynamic": false},
	},
	"title_training_focus": {
		"slot": "title", "type": "title", "name": "问题终结者",
		"description": "完成一次针对问题区间的训练。", "unlock_hint": "完成训练室问题区间",
		"rarity": "common", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"primary_color": "#8EEBFF", "secondary_color": "#B58CFF",
			"text_color": "#F4FBFF", "style": "training_chip", "badge": "PRACTICE", "art_index": 1},
	},
	"title_fancy_lv10": {
		"slot": "title", "type": "title", "name": "花式新锐",
		"description": "花式模式达到 10 级。", "unlock_hint": "花式等级达到 10",
		"rarity": "common", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"primary_color": "#FF3CCF", "secondary_color": "#8EEBFF",
			"text_color": "#FFF5FD", "style": "mode_chip", "badge": "FANCY", "art_index": 0},
	},
	"title_racing_lv10": {
		"slot": "title", "type": "title", "name": "竞速新锐",
		"description": "竞速模式达到 10 级。", "unlock_hint": "竞速等级达到 10",
		"rarity": "common", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"primary_color": "#29E9FF", "secondary_color": "#FFD84A",
			"text_color": "#F4FBFF", "style": "mode_chip", "badge": "RACING", "art_index": 1},
	},
	"title_diy_lv10": {
		"slot": "title", "type": "title", "name": "DIY 探索者",
		"description": "DIY 模式达到 10 级。", "unlock_hint": "DIY 等级达到 10",
		"rarity": "common", "fallback_id": "", "performance_variant": "",
		"surfaces": ["song_select", "gameplay", "esc_profile", "profile", "settlement"],
		"visual": {"primary_color": "#B58CFF", "secondary_color": "#29E9FF",
			"text_color": "#F8F1FF", "style": "mode_chip", "badge": "DIY", "art_index": 1},
	},

	# 称号扩展：由 RewardTitleBadge 纯代码主题系统驱动。
	"title_precision_master": {
		"slot": "title", "type": "title", "name": "精准大师",
		"description": "稳定保持高准确率的技术型称号。", "unlock_hint": "累计获得 10 个 S 评价",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#29E9FF", "secondary_color": "#8EEBFF", "text_color": "#F4FDFF", "style": "precision", "badge": "PRECISE", "art_index": 2},
	},
	"title_combo_king": {
		"slot": "title", "type": "title", "name": "连击达人",
		"description": "以长连击证明稳定性的进阶称号。", "unlock_hint": "单曲最大 Combo 达到 500",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#20E8FF", "secondary_color": "#4D8CFF", "text_color": "#EEFDFF", "style": "combo_wave", "badge": "COMBO KING", "art_index": 3},
	},
	"title_rhythm_master": {
		"slot": "title", "type": "title", "name": "节奏掌控者",
		"description": "跨模式保持高水平表现的节奏称号。", "unlock_hint": "任意模式达到 30 级",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FF4DDA", "secondary_color": "#8B5CFF", "text_color": "#FFF2FD", "style": "master_wings", "badge": "RHYTHM MASTER", "art_index": 4},
	},
	"title_monthly_active": {
		"slot": "title", "type": "title", "name": "月度活跃者",
		"description": "整月保持活跃的纪念称号。", "unlock_hint": "连续活跃 30 天",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#29E9FF", "secondary_color": "#B58CFF", "text_color": "#F5FBFF", "style": "monthly", "badge": "MONTHLY", "art_index": 3},
	},
	"title_star_conqueror": {
		"slot": "title", "type": "title", "name": "星轨征服者",
		"description": "完成大量不同谱面的收藏型称号。", "unlock_hint": "完成 100 张不同谱面",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#55CFFF", "secondary_color": "#8F7CFF", "text_color": "#F4FBFF", "style": "star_track", "badge": "STAR TRACK", "art_index": 2},
	},
	"title_night_walker": {
		"slot": "title", "type": "title", "name": "夜光行者",
		"description": "在深夜完成正式谱面的限定风格称号。", "unlock_hint": "22:00 至次日 05:59 完成正式谱面",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FF49D6", "secondary_color": "#7B5CFF", "text_color": "#FFF2FD", "style": "night_moon", "badge": "NIGHT", "art_index": 5},
	},
	"title_battle_hardened": {
		"slot": "title", "type": "title", "name": "百战不殆",
		"description": "经历大量正式对局后的荣誉称号。", "unlock_hint": "累计完成 300 首正式歌曲",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FF4BD8", "secondary_color": "#C782FF", "text_color": "#FFF0FC", "style": "battle", "badge": "VETERAN", "art_index": 4},
	},
	"title_aurora_navigator": {
		"slot": "title", "type": "title", "name": "极光领航员",
		"description": "集齐极光环头像框与极光夜城玩家卡。", "unlock_hint": "集齐 2 件极光系列奖励",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FF65E5", "secondary_color": "#45EFFF", "text_color": "#FFF1FD", "style": "aurora", "badge": "AURORA", "art_index": 5},
	},
	"title_galaxy_lord": {
		"slot": "title", "type": "title", "name": "银河领主",
		"description": "银河系列收藏完成后的传说称号。", "unlock_hint": "集齐 8 件史诗奖励",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FFD13F", "secondary_color": "#8F70FF", "text_color": "#FFF6BD", "style": "galaxy_lord", "badge": "GALAXY LORD", "art_index": 6},
	},
	"title_legend_performer": {
		"slot": "title", "type": "title", "name": "传奇演奏家",
		"description": "长期稳定游玩的传说级身份称号。", "unlock_hint": "累计游玩 1000 分钟",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FFD443", "secondary_color": "#FF9E28", "text_color": "#FFF5B0", "style": "legend_player", "badge": "LEGEND", "art_index": 7},
	},
	"title_beat_sovereign": {
		"slot": "title", "type": "title", "name": "音律主宰",
		"description": "三模式均达到高等级的顶级称号。", "unlock_hint": "花式、竞速、DIY 均达到 30 级",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FFD33E", "secondary_color": "#FF4BD8", "text_color": "#FFF7BD", "style": "beat_lord", "badge": "BEAT LORD", "art_index": 6},
	},
	"title_rhythm_god": {
		"slot": "title", "type": "title", "name": "巅峰节奏神",
		"description": "奖励生态中的最终荣誉称号。", "unlock_hint": "集齐除本称号外的全部传说奖励",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FFE463", "secondary_color": "#FF9B24", "tertiary_color": "#FFF4A3", "text_color": "#FFF8C8", "background_color": "#160D00F7", "theme": "gold", "style": "rhythm_god", "badge": "RHYTHM GOD", "animated": true},
	},

	# 代码称号主题套装：每套拥有独立轮廓细节、配色和动态表现。
	"title_cyber_ronin": {
		"slot": "title", "type": "title", "name": "赛博浪人",
		"description": "霓虹切角、故障扫描和双端数据节点组成的赛博称号。", "unlock_hint": "单曲最大 Combo 达到 300",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#22E8FF", "secondary_color": "#FF3CCF", "tertiary_color": "#A5FAFF", "text_color": "#F3FEFF", "background_color": "#020D1DF7", "theme": "cyber", "style": "cyber_ronin", "badge": "RONIN", "animated": true},
	},
	"title_frost_core": {
		"slot": "title", "type": "title", "name": "零度核心",
		"description": "冰晶碎片、冷光内框和霜雾呼吸构成的极寒称号。", "unlock_hint": "累计获得 40 个 S 评价",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#6EDCFF", "secondary_color": "#E7FBFF", "tertiary_color": "#A8F2FF", "text_color": "#F5FDFF", "background_color": "#031625F7", "theme": "ice", "style": "cryo_core", "badge": "CRYO CORE", "animated": true},
	},
	"title_ember_crown": {
		"slot": "title", "type": "title", "name": "焰冠征服者",
		"description": "熔火波峰、橙金高光和战斗刻痕构成的烈焰称号。", "unlock_hint": "累计完成 200 首歌曲",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FF6B1A", "secondary_color": "#FFD34B", "tertiary_color": "#FFF0A2", "text_color": "#FFF5D6", "background_color": "#1A0700F7", "theme": "flame", "style": "ember_crown", "badge": "EMBER", "animated": true},
	},
	"title_matrix_ghost": {
		"slot": "title", "type": "title", "name": "矩阵幽灵",
		"description": "数据雨、绿色扫描线和隐匿代码标记组成的矩阵称号。", "unlock_hint": "DIY 模式达到 30 级",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#4CFF8A", "secondary_color": "#16D9C7", "tertiary_color": "#B7FFD0", "text_color": "#EFFFF3", "background_color": "#00150BF7", "theme": "matrix", "style": "matrix_ghost", "badge": "MATRIX", "animated": true},
	},
	"title_sakura_dream": {
		"slot": "title", "type": "title", "name": "樱落幻奏",
		"description": "飘落花瓣、柔粉高光和细线和风结构组成的樱花称号。", "unlock_hint": "花式模式达到 25 级",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FF87BC", "secondary_color": "#FFD5E6", "tertiary_color": "#FFF4FA", "text_color": "#FFF7FB", "background_color": "#210916F7", "theme": "sakura", "style": "sakura_dream", "badge": "SAKURA", "animated": true},
	},
	"title_void_watcher": {
		"slot": "title", "type": "title", "name": "虚空观测者",
		"description": "深空星点、环形引力纹和紫蓝暗光组成的虚空称号。", "unlock_hint": "花式、竞速、DIY 均达到 40 级",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#8A63FF", "secondary_color": "#37DFFF", "tertiary_color": "#D8C9FF", "text_color": "#F7F2FF", "background_color": "#08031AF8", "theme": "void", "style": "void_watcher", "badge": "VOID", "animated": true},
	},
	"title_prism_oracle": {
		"slot": "title", "type": "title", "name": "棱镜先知",
		"description": "幻彩波纹、棱镜星点和三色辉光组成的神谕称号。", "unlock_hint": "累计获得 100 个 S 评价",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FF4DDB", "secondary_color": "#2DEBFF", "tertiary_color": "#FFE86C", "text_color": "#FFF8FF", "background_color": "#100526F8", "theme": "aurora", "style": "prism_oracle", "badge": "PRISM", "animated": true},
	},
	"title_midas_destiny": {
		"slot": "title", "type": "title", "name": "鎏金天命",
		"description": "纯金双框、王冠折线和周期扫光组成的最高阶黄金称号。", "unlock_hint": "累计游玩 2000 分钟",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"primary_color": "#FFD13D", "secondary_color": "#FF9F1C", "tertiary_color": "#FFF2A6", "text_color": "#FFF8C7", "background_color": "#150D00F8", "theme": "gold", "style": "midas_destiny", "badge": "MIDAS", "animated": true},
	},

	# 头像框扩展：style 驱动八类代码环形主题与流光。
	"frame_minimal_silver": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "极简银头像框",
		"description": "克制的银白双环头像框。", "unlock_hint": "完成首次正式歌曲",
		"rarity": "common", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#E8EDF4", "accent_color": "#8795A8", "glow_color": "#DDE7F044", "style": "minimal_silver", "art_index": 2, "dynamic": false},
	},
	"frame_pulse": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "电音脉冲头像框",
		"description": "围绕头像跳动的电音波形框。", "unlock_hint": "最大 Combo 达到 500",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#22E9FF", "accent_color": "#8EFBFF", "glow_color": "#22E9FF66", "style": "pulse", "art_index": 3, "dynamic": false},
	},
	"frame_data_grid": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "数据网格头像框",
		"description": "像素节点与网格刻度组成的技术框。", "unlock_hint": "DIY 模式达到 15 级",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#18E2FF", "accent_color": "#65F6FF", "glow_color": "#18E2FF66", "style": "data_grid", "art_index": 4, "dynamic": false},
	},
	"frame_aurora": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "极光环头像框",
		"description": "青紫渐变与星点构成的极光框。", "unlock_hint": "连续活跃 14 天",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#66F2FF", "accent_color": "#B45CFF", "glow_color": "#8B7CFF77", "style": "aurora", "art_index": 5, "dynamic": false},
	},
	"frame_starburst": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "星芒环头像框",
		"description": "四向星芒与紫色光环构成的史诗框。", "unlock_hint": "累计获得 25 个 S 评价",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#FF5DDF", "accent_color": "#C681FF", "glow_color": "#FF5DDF77", "style": "starburst", "art_index": 6, "dynamic": false},
	},
	"frame_prism": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "棱镜环头像框",
		"description": "多色棱镜切面组成的幻彩头像框。", "unlock_hint": "完成 3 张不同 17★以上谱面并获得 S",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#6BEFFF", "accent_color": "#FF54D9", "glow_color": "#B56AFF77", "style": "prism", "art_index": 7, "dynamic": false},
	},
	"frame_flame": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "炽焰环头像框",
		"description": "橙金火焰与尖锐节点组成的战斗框。", "unlock_hint": "连续完成 10 张不同 15★以上谱面",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#FF8B25", "accent_color": "#FFD443", "glow_color": "#FF8B2577", "style": "flame", "art_index": 8, "dynamic": false},
	},
	"frame_ice": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "冰晶环头像框",
		"description": "冰蓝雪晶结构组成的冷色史诗框。", "unlock_hint": "完成 5 张不同 15★以上谱面且每首 MISS≤2",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#8BE8FF", "accent_color": "#E4FAFF", "glow_color": "#8BE8FF77", "style": "ice", "art_index": 9, "dynamic": false},
	},
	"frame_legend_wings": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "传说羽冠头像框",
		"description": "金白羽翼与冠饰组成的传说框。", "unlock_hint": "任意模式达到 50 级",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#FFD33E", "accent_color": "#FFF2A6", "glow_color": "#FFD33E88", "style": "legend_wings", "art_index": 10, "dynamic": false},
	},
	"frame_vip_crown": {
		"slot": "avatar_frame", "type": "avatar_frame", "name": "VIP 王冠头像框",
		"description": "黑金王冠与宝石节点组成的顶级框。", "unlock_hint": "拥有 5 件传说奖励",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": IDENTITY_SURFACES,
		"visual": {"border_color": "#FFD23D", "accent_color": "#FF4DDC", "glow_color": "#FFD23D99", "style": "vip_crown", "art_index": 11, "dynamic": false},
	},

	# 玩家卡扩展：style 驱动横向代码卡面与双流光。
	"card_neon_wave": {
		"slot": "profile_card", "type": "profile_card", "name": "霓虹波纹玩家卡",
		"description": "洋红波纹与频谱组成的夜店主题卡。", "unlock_hint": "花式模式达到 15 级",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": CARD_SURFACES,
		"visual": {"fill_color": "#16042BF2", "header_color": "#4A0B53CC", "border_color": "#FF4BD9", "secondary_color": "#7B5CFF", "inner_color": "#FF72E355", "scanline_color": "#FF4BD914", "rank_color": "#FF89E8", "style": "neon_wave", "art_index": 1, "art_opacity": 0.96, "dynamic": false},
	},
	"card_speed_lightning": {
		"slot": "profile_card", "type": "profile_card", "name": "竞速闪电玩家卡",
		"description": "蓝色闪电和速度线构成的竞速卡。", "unlock_hint": "竞速模式达到 20 级",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": CARD_SURFACES,
		"visual": {"fill_color": "#03172DF2", "header_color": "#073B5FCC", "border_color": "#20DFFF", "secondary_color": "#5CF3FF", "inner_color": "#48CFFF55", "scanline_color": "#20DFFF14", "rank_color": "#FFD84A", "style": "speed_lightning", "art_index": 2, "art_opacity": 0.96, "dynamic": false},
	},
	"card_fancy_stage": {
		"slot": "profile_card", "type": "profile_card", "name": "花式舞台玩家卡",
		"description": "聚光灯与观众光点组成的花式舞台卡。", "unlock_hint": "花式模式达到 20 级",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": CARD_SURFACES,
		"visual": {"fill_color": "#25052EF2", "header_color": "#5E0F66CC", "border_color": "#FF4BD9", "secondary_color": "#C077FF", "inner_color": "#FF77E055", "scanline_color": "#FF4BD914", "rank_color": "#FFD84A", "style": "fancy_stage", "art_index": 3, "art_opacity": 0.96, "dynamic": false},
	},
	"card_diy_blueprint": {
		"slot": "profile_card", "type": "profile_card", "name": "DIY 蓝图玩家卡",
		"description": "网格、尺寸线与模块结构组成的蓝图卡。", "unlock_hint": "DIY 模式达到 20 级",
		"rarity": "rare", "fallback_id": "", "performance_variant": "", "surfaces": CARD_SURFACES,
		"visual": {"fill_color": "#021B36F2", "header_color": "#063B5FCC", "border_color": "#1AE8FF", "secondary_color": "#55F4FF", "inner_color": "#1AE8FF44", "scanline_color": "#1AE8FF14", "rank_color": "#FFD84A", "style": "diy_blueprint", "art_index": 4, "art_opacity": 0.96, "dynamic": false},
	},
	"card_aurora_city": {
		"slot": "profile_card", "type": "profile_card", "name": "极光夜城玩家卡",
		"description": "极光渐变与未来城市剪影组成的主题卡。", "unlock_hint": "连续活跃 14 天",
		"rarity": "epic", "fallback_id": "", "performance_variant": "", "surfaces": CARD_SURFACES,
		"visual": {"fill_color": "#05243CF2", "header_color": "#0B5269CC", "border_color": "#23ECFF", "secondary_color": "#A95EFF", "inner_color": "#51FFCF44", "scanline_color": "#23ECFF14", "rank_color": "#FFE04A", "style": "aurora_city", "art_index": 5, "art_opacity": 0.97, "dynamic": false},
	},
	"card_black_gold_vip": {
		"slot": "profile_card", "type": "profile_card", "name": "黑金 VIP 玩家卡",
		"description": "黑金边框、王冠与频谱构成的传说卡。", "unlock_hint": "累计获得 50 个 S 评价",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": CARD_SURFACES,
		"visual": {"fill_color": "#130D01F5", "header_color": "#3A2600D8", "border_color": "#FFD13E", "secondary_color": "#FF9A22", "inner_color": "#FFD13E44", "scanline_color": "#FFD13E12", "rank_color": "#FFF2A0", "style": "black_gold_vip", "art_index": 6, "art_opacity": 0.98, "dynamic": false},
	},
	"card_prism_myth": {
		"slot": "profile_card", "type": "profile_card", "name": "棱镜神话玩家卡",
		"description": "棱镜切片与幻彩频谱构成的传说卡。", "unlock_hint": "集齐棱镜环头像框与棱镜先知称号",
		"rarity": "legendary", "fallback_id": "", "performance_variant": "", "surfaces": CARD_SURFACES,
		"visual": {"fill_color": "#110725F5", "header_color": "#341052D8", "border_color": "#FF4DDC", "secondary_color": "#28EFFF", "inner_color": "#B85CFF55", "scanline_color": "#FF4DDC12", "rank_color": "#FFE34B", "style": "prism_myth", "art_index": 7, "art_opacity": 0.98, "dynamic": false},
	},
}

func has(reward_id: String) -> bool:
	return ITEMS.has(reward_id)

func get_item(reward_id: String) -> Dictionary:
	return (ITEMS.get(reward_id, {}) as Dictionary).duplicate(true)

func display_name(reward_id: String) -> String:
	return str((ITEMS.get(reward_id, {}) as Dictionary).get("name", reward_id))

func ids() -> Array[String]:
	var result: Array[String] = []
	for raw_id in ITEMS.keys():
		result.append(str(raw_id))
	result.sort()
	return result

func canonical_slot(slot: String) -> String:
	return str(SLOT_ALIASES.get(slot, slot))

func get_default_visual(slot: String) -> Dictionary:
	return (DEFAULT_VISUALS.get(canonical_slot(slot), {}) as Dictionary).duplicate(true)

func validate_catalog() -> Array[String]:
	var errors := validate_items(ITEMS)
	for reward_type in ART_ATLASES:
		var path := str(ART_ATLASES[reward_type])
		if not ResourceLoader.exists(path):
			errors.append("%s 美术图集不存在: %s" % [reward_type, path])
	return errors

func validate_items(items: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	for raw_id in items.keys():
		var reward_id := str(raw_id)
		if seen.has(reward_id):
			errors.append("重复 reward_id: %s" % reward_id)
		seen[reward_id] = true
		if not items[raw_id] is Dictionary:
			errors.append("%s: 条目不是 Dictionary" % reward_id)
			continue
		_validate_item(reward_id, items[raw_id], items, errors)
	return errors

func _validate_item(reward_id: String, item: Dictionary, items: Dictionary,
		errors: Array[String]) -> void:
	var slot := canonical_slot(str(item.get("slot", "")))
	var reward_type := str(item.get("type", ""))
	if slot not in VALID_SLOTS:
		errors.append("%s: 未知槽位 %s" % [reward_id, slot])
	if reward_type not in VALID_TYPES:
		errors.append("%s: 未知类型 %s" % [reward_id, reward_type])
	if str(item.get("name", "")).strip_edges().is_empty():
		errors.append("%s: 缺少名称" % reward_id)
	if str(item.get("description", "")).strip_edges().is_empty():
		errors.append("%s: 缺少描述" % reward_id)
	if str(item.get("unlock_hint", "")).strip_edges().is_empty():
		errors.append("%s: 缺少获取条件" % reward_id)
	if str(item.get("rarity", "")) not in VALID_RARITIES:
		errors.append("%s: 非法稀有度" % reward_id)
	if not item.get("visual", {}) is Dictionary or (item.get("visual", {}) as Dictionary).is_empty():
		errors.append("%s: 缺少 visual" % reward_id)
	if not item.get("surfaces", []) is Array or (item.get("surfaces", []) as Array).is_empty():
		errors.append("%s: 未声明使用场景" % reward_id)
	else:
		for surface in item.get("surfaces", []):
			if str(surface) not in VALID_SURFACES:
				errors.append("%s: 未知使用场景 %s" % [reward_id, str(surface)])
	if reward_type == "title" and str(item.get("name", "")).length() > 16:
		errors.append("%s: 称号文案超过 16 字" % reward_id)
	var visual: Dictionary = item.get("visual", {}) if item.get("visual", {}) is Dictionary else {}
	_validate_visual(reward_id, visual, errors)
	if reward_type in ART_INDEX_LIMITS and visual.has("art_index"):
		var art_index := int(visual.get("art_index", -1))
		if art_index < 0 or art_index >= int(ART_INDEX_LIMITS[reward_type]):
			errors.append("%s: art_index 越界 %d" % [reward_id, art_index])
	var fallback_id := str(item.get("fallback_id", ""))
	if not fallback_id.is_empty() and not items.has(fallback_id):
		errors.append("%s: fallback_id 不存在 %s" % [reward_id, fallback_id])
	if _has_fallback_cycle(reward_id, items):
		errors.append("%s: fallback 循环引用" % reward_id)
	if bool((item.get("visual", {}) as Dictionary).get("dynamic", false)) \
			and str(item.get("performance_variant", "")).is_empty():
		errors.append("%s: 动态奖励缺少性能模式回退" % reward_id)

func _validate_visual(reward_id: String, visual: Dictionary, errors: Array[String]) -> void:
	for key in visual.keys():
		var key_text := str(key)
		var value = visual[key]
		if key_text.ends_with("_color") and not _valid_color(value):
			errors.append("%s: 非法颜色 %s=%s" % [reward_id, key_text, str(value)])
		if key_text.ends_with("_asset") and not str(value).is_empty() \
				and not ResourceLoader.exists(str(value)):
			errors.append("%s: 资源不存在 %s" % [reward_id, str(value)])

func _valid_color(value: Variant) -> bool:
	if value is Color:
		return true
	if not value is String:
		return false
	var text := str(value)
	if not text.begins_with("#") or text.length() not in [7, 9]:
		return false
	for i in range(1, text.length()):
		if text[i].to_upper() not in "0123456789ABCDEF":
			return false
	return true

func _has_fallback_cycle(start_id: String, items: Dictionary) -> bool:
	var visited := {}
	var current := start_id
	while not current.is_empty() and items.has(current):
		if visited.has(current):
			return true
		visited[current] = true
		current = str((items[current] as Dictionary).get("fallback_id", ""))
	return false
