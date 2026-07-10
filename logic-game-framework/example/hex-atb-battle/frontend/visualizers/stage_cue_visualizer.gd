## StageCueVisualizer - 舞台提示事件转换器
##
## 将 stageCue 事件翻译为视觉特效动作
## 根据 cue_id 决定播放什么特效：
## - melee_slash, melee_heavy, melee_combo → 播放攻击箭头特效
## - magic_fireball, ranged_arrow → 不播放（有投射物动画）
## - magic_heal → 治疗光束特效
class_name FrontendStageCueVisualizer
extends FrontendBaseVisualizer


# ========== 需要播放攻击特效的 cue_id ==========

const MELEE_ATTACK_CUES := [
	HexBattleCues.MELEE_SLASH,   # 横扫斩
	HexBattleCues.MELEE_HEAVY,   # 毁灭重击
	HexBattleCues.MELEE_COMBO,   # 疾风连刺
	HexBattleCues.TOTEM_ATTACK,  # 图腾自动攻击
]

# ========== 需要播放治疗特效的 cue_id ==========

const HEAL_CUES := [
	HexBattleCues.MAGIC_HEAL,    # 圣光治愈
]

# ========== 斩杀击杀醒目特效 cue_id ==========

const EXECUTE_KILL_CUE := HexBattleCues.EXECUTE_KILL  # Execute 命中击杀:猩红冲击波(放大)
## 比普通 attack_vfx 明显更长,确保"斩杀"收尾醒目、肉眼可辨(也便于回放定格验证)。
const EXECUTE_KILL_VFX_DURATION := 0.8
## 略延迟:让起手 melee_heavy 挥击先淡出,斩杀爆作为独立收尾炸出来,不糊在一起。
const EXECUTE_KILL_VFX_DELAY := 0.15

# ========== 控制状态 cue_id (Stun / Silence / Break 等共用 floating-text pattern) ==========

## stage cue → floating text 映射: cue_id → { text, color, style }
## 复用 FrontendFloatingTextAction (已存在的飘字系统), 不为单技能搭独立 VFX。
## 加新 control 飘字 = 多写一行配置即可。
const CONTROL_FLOATING_TEXTS := {
	HexBattleCues.CONTROL_STUNNED: {
		"text": "眩晕!",
		"color": Color(0.95, 0.85, 0.2),  # 金黄, 与 BuffVisualizer Stun entry 同色
		"style": FrontendFloatingTextAction.FloatingTextStyle.CRITICAL,
	},
	HexBattleCues.CONTROL_SILENCED: {
		"text": "沉默!",
		"color": Color(0.55, 0.35, 0.85),  # 紫色, 与 BuffVisualizer Silence entry 同色
		"style": FrontendFloatingTextAction.FloatingTextStyle.CRITICAL,
	},
	HexBattleCues.CONTROL_BROKEN: {
		"text": "破坏!",
		"color": Color(0.45, 0.45, 0.55),  # 暗紫灰, 与 BuffVisualizer Break entry 同色
		"style": FrontendFloatingTextAction.FloatingTextStyle.CRITICAL,
	},
	# Phase 2+ 进阶技能 floating text (Cleanse / Swap / Lifesteal / Piercing Line / Summon / Fire Tile)
	HexBattleCues.CONTROL_CLEANSED: {
		"text": "净化!",
		"color": Color(0.95, 0.95, 1.0),  # 白光, 净化的圣洁感
		"style": FrontendFloatingTextAction.FloatingTextStyle.HEAL,
	},
	HexBattleCues.SWAP_BLINK: {
		"text": "换位!",
		"color": Color(0.6, 0.85, 0.95),  # 浅青蓝, 瞬移感
		"style": FrontendFloatingTextAction.FloatingTextStyle.NORMAL,
	},
	HexBattleCues.SUMMON_TOTEM_CAST: {
		"text": "图腾!",
		"color": Color(0.75, 0.55, 0.3),  # 木褐, 图腾木质感
		"style": FrontendFloatingTextAction.FloatingTextStyle.NORMAL,
	},
	HexBattleCues.FIRE_TILE_CAST: {
		"text": "火地!",
		"color": Color(1.0, 0.45, 0.1),  # 橘红, 火焰即视感
		"style": FrontendFloatingTextAction.FloatingTextStyle.CRITICAL,
	},
	HexBattleCues.PIERCING_LINE_CAST: {
		"text": "穿透!",
		"color": Color(0.6, 0.85, 1.0),  # 锐青, 直线穿透感
		"style": FrontendFloatingTextAction.FloatingTextStyle.NORMAL,
	},
	HexBattleCues.LIFESTEAL_DRAIN: {
		"text": "汲血!",
		"color": Color(0.85, 0.15, 0.25),  # 暗红, 吸血的血色
		"style": FrontendFloatingTextAction.FloatingTextStyle.HEAL,
	},
}

# ========== Phase E: Cone debug overlay ==========

## Cone cast cue_id → 是否走 cone 检查区域 overlay path.
const CONE_DEBUG_CUES := [HexBattleCues.GRID_CONE_CAST, HexBattleCues.ANGLE_CONE_CAST]

const CONE_DEBUG_DURATION_MS := 1500.0
const CONE_DEBUG_FILL_Y := 0.06
const CONE_DEBUG_BOUNDARY_Y := 0.12
const CONE_DEBUG_FILL_COLOR_GRID := Color(0.18, 0.78, 1.0, 0.24)
const CONE_DEBUG_BOUNDARY_COLOR_GRID := Color(0.55, 0.95, 1.0, 0.95)
const CONE_DEBUG_FILL_COLOR_ANGLE := Color(1.0, 0.52, 0.08, 0.24)
const CONE_DEBUG_BOUNDARY_COLOR_ANGLE := Color(1.0, 0.78, 0.25, 0.95)


func _init() -> void:
	visualizer_name = "StageCueVisualizer"


## 检查是否为 stageCue 事件
func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == GameEvent.STAGE_CUE_EVENT


## 翻译 stageCue 事件为视觉动作
func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var e := GameEvent.StageCue.from_dict(event)
	var source_id := e.source_actor_id
	var target_ids := e.target_actor_ids
	var cue_id := e.cue_id
	var params: Dictionary = e.params if e.params != null else {}

	var actions: Array[FrontendVisualAction] = []

	# 近战攻击类 cue → 攻击箭头特效
	if cue_id in MELEE_ATTACK_CUES:
		actions.append_array(_create_melee_attack_vfx(source_id, target_ids, cue_id, context))
	# 治疗类 cue → 治疗光束特效
	elif cue_id in HEAL_CUES:
		actions.append_array(_create_heal_vfx(source_id, target_ids, context))
	# 斩杀击杀 → 猩红冲击波(放大)醒目特效,区别于普通近战挥击
	elif cue_id == EXECUTE_KILL_CUE:
		actions.append_array(_create_execute_kill_vfx(source_id, target_ids, context))
	# 控制状态 cue (Stun / Silence / Break) → 目标头顶飘字 (复用 floating-text pattern)
	elif cue_id in CONTROL_FLOATING_TEXTS:
		actions.append_array(_create_control_floating_text(target_ids, cue_id, context))
	# Phase E: cone debug overlay → checked cells fill + geometry boundary
	elif cue_id in CONE_DEBUG_CUES:
		actions.append_array(_create_cone_overlay(cue_id, params, context))
	# 其他 cue_id（如 magic_fireball, ranged_arrow）不需要额外特效
	# 因为它们有投射物飞行动画

	return actions


## Phase E: cone debug overlay —— 把 selector checked_coords 翻译成填充区和边界。
##
## 这是 contract debug overlay,不是 VFX polish: 让玩家 / 测试者看到本次 cone 检查的全部
## 格子 (包括没有 enemy 占位的). angle_cone 使用逻辑层给出的两条 edge_segments
## 画真实角度边界线; frontend 只消费 params, 不反推 selector 逻辑.
func _create_cone_overlay(
	cue_id: String,
	params: Dictionary,
	context: FrontendVisualizerContext,
) -> Array[FrontendVisualAction]:
	var actions: Array[FrontendVisualAction] = []
	var checked_coords: Array = params.get("checked_coords", []) as Array
	if checked_coords.is_empty():
		return actions
	var layout := context.get_layout()
	if layout == null:
		return actions

	var coords: Array[HexCoord] = []
	var coord_keys: Dictionary = {}
	for c_variant in checked_coords:
		if not (c_variant is Dictionary):
			continue
		var c := c_variant as Dictionary
		if not (c.has("q") and c.has("r")):
			continue
		var hex_coord := HexCoord.new(int(c.get("q", 0)), int(c.get("r", 0)))
		if not coord_keys.has(hex_coord.to_key()):
			coords.append(hex_coord)
			coord_keys[hex_coord.to_key()] = true
	if coords.is_empty():
		return actions

	var cell_polygons: Array[PackedVector3Array] = []
	var boundary_segments: Array[PackedVector3Array] = []
	for coord in coords:
		var corners_2d := layout.hex_corners(coord.to_axial())
		var fill_polygon := PackedVector3Array()
		for corner in corners_2d:
			fill_polygon.append(Vector3(corner.x, CONE_DEBUG_FILL_Y, corner.y))
		cell_polygons.append(fill_polygon)

		if cue_id != "angle_cone_cast":
			for side in range(6):
				var neighbor := coord.neighbor(side)
				if coord_keys.has(neighbor.to_key()):
					continue
				var segment := PackedVector3Array()
				var start_2d := corners_2d[side]
				var end_2d := corners_2d[(side + 1) % corners_2d.size()]
				segment.append(Vector3(start_2d.x, CONE_DEBUG_BOUNDARY_Y, start_2d.y))
				segment.append(Vector3(end_2d.x, CONE_DEBUG_BOUNDARY_Y, end_2d.y))
				boundary_segments.append(segment)

	var fill_color := CONE_DEBUG_FILL_COLOR_GRID
	var boundary_color := CONE_DEBUG_BOUNDARY_COLOR_GRID
	if cue_id == "angle_cone_cast":
		fill_color = CONE_DEBUG_FILL_COLOR_ANGLE
		boundary_color = CONE_DEBUG_BOUNDARY_COLOR_ANGLE
		boundary_segments.append_array(_parse_angle_edge_segments(params))
	actions.append(FrontendConeDebugOverlayAction.new(
		cue_id,
		cell_polygons,
		boundary_segments,
		fill_color,
		boundary_color,
		CONE_DEBUG_DURATION_MS
	))
	return actions


func _parse_angle_edge_segments(params: Dictionary) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	var edge_segments: Array = params.get("edge_segments", []) as Array
	for edge_variant in edge_segments:
		if not (edge_variant is Dictionary):
			continue
		var edge := edge_variant as Dictionary
		var start_variant: Variant = edge.get("start", {})
		var end_variant: Variant = edge.get("end", {})
		if not (start_variant is Dictionary) or not (end_variant is Dictionary):
			continue
		var start_dict := start_variant as Dictionary
		var end_dict := end_variant as Dictionary
		if start_dict.is_empty() or end_dict.is_empty():
			continue
		var start_pos := Vector3(
			float(start_dict.get("x", 0.0)),
			CONE_DEBUG_BOUNDARY_Y,
			float(start_dict.get("y", 0.0))
		)
		var end_pos := Vector3(
			float(end_dict.get("x", 0.0)),
			CONE_DEBUG_BOUNDARY_Y,
			float(end_dict.get("y", 0.0))
		)
		if start_pos.distance_to(end_pos) < 0.001:
			continue
		var segment := PackedVector3Array()
		segment.append(start_pos)
		segment.append(end_pos)
		result.append(segment)
	return result


## 控制状态 floating text (Stun "眩晕!" / Silence "沉默!" / Break "破坏!" 共用 pattern)
func _create_control_floating_text(
	target_ids: Array[String],
	cue_id: String,
	context: FrontendVisualizerContext
) -> Array[FrontendVisualAction]:
	var actions: Array[FrontendVisualAction] = []
	var cfg: Dictionary = CONTROL_FLOATING_TEXTS.get(cue_id, {})
	if cfg.is_empty() or target_ids.is_empty():
		return actions

	var anim_cfg := context.get_animation_config()
	for target_id in target_ids:
		var pos := context.get_actor_position(target_id)
		actions.append(FrontendFloatingTextAction.new(
			target_id,
			cfg.get("text", "") as String,
			cfg.get("color", Color.WHITE) as Color,
			pos,
			cfg.get("style", FrontendFloatingTextAction.FloatingTextStyle.NORMAL) as int,
			anim_cfg.damage_floating_text_duration
		))
	return actions


## 创建近战攻击特效
func _create_melee_attack_vfx(
	source_id: String,
	target_ids: Array[String],
	cue_id: String,
	context: FrontendVisualizerContext
) -> Array[FrontendVisualAction]:
	var config := context.get_animation_config()
	var actions: Array[FrontendVisualAction] = []
	
	if source_id.is_empty() or target_ids.is_empty():
		return actions
	
	var source_position := context.get_actor_position(source_id)
	var source_team := context.get_actor_team(source_id)
	
	# 为每个目标创建攻击特效
	for target_id in target_ids:
		var target_position := context.get_actor_position(target_id)
		
		var attack_vfx := FrontendAttackVFXAction.new(
			source_id,
			target_id,
			source_position,
			target_position,
			config.attack_vfx_duration,
			_get_vfx_type_for_cue(cue_id),
			_get_attack_vfx_color(cue_id, source_team, false),  # 暴击信息在 damage 事件中，这里默认非暴击
			false  # is_critical
		)
		actions.append(attack_vfx)
	
	return actions


## 根据 cue_id 获取特效类型
func _get_vfx_type_for_cue(cue_id: String) -> FrontendAttackVFXAction.AttackVFXType:
	match cue_id:
		"melee_slash":
			return FrontendAttackVFXAction.AttackVFXType.SLASH
		"melee_heavy":
			return FrontendAttackVFXAction.AttackVFXType.IMPACT
		"melee_combo":
			return FrontendAttackVFXAction.AttackVFXType.THRUST
		"totem_attack":
			return FrontendAttackVFXAction.AttackVFXType.IMPACT
		_:
			return FrontendAttackVFXAction.AttackVFXType.SLASH


func _get_attack_vfx_color(cue_id: String, team: int, is_critical: bool) -> Color:
	if cue_id == "totem_attack":
		return Color(0.95, 0.62, 0.24) if team == 0 else Color(1.0, 0.36, 0.16)
	return _get_attack_vfx_color_by_team(team, is_critical)


## 根据队伍获取攻击特效颜色
func _get_attack_vfx_color_by_team(team: int, is_critical: bool) -> Color:
	# 队伍 0（玩家方）：蓝色系
	# 队伍 1（敌方）：红色系
	if team == 0:
		if is_critical:
			return Color(0.3, 0.8, 1.0)  # 亮蓝色（暴击）
		return Color(0.2, 0.5, 1.0)  # 蓝色
	else:
		if is_critical:
			return Color(1.0, 0.6, 0.0)  # 橙色（暴击）
		return Color(1.0, 0.3, 0.2)  # 红色


## 创建治疗特效（从施法者飞向目标的绿色/金色光束）
func _create_heal_vfx(
	source_id: String,
	target_ids: Array[String],
	context: FrontendVisualizerContext
) -> Array[FrontendVisualAction]:
	var config := context.get_animation_config()
	var actions: Array[FrontendVisualAction] = []
	
	if source_id.is_empty() or target_ids.is_empty():
		return actions
	
	var source_position := context.get_actor_position(source_id)
	
	# 为每个目标创建治疗特效
	for target_id in target_ids:
		var target_position := context.get_actor_position(target_id)
		
		# 使用 SLASH 类型但用绿色/金色表示治疗
		var heal_vfx := FrontendAttackVFXAction.new(
			source_id,
			target_id,
			source_position,
			target_position,
			config.attack_vfx_duration,
			FrontendAttackVFXAction.AttackVFXType.SLASH,
			Color(0.3, 1.0, 0.4),  # 翠绿色
			false
		)
		actions.append(heal_vfx)

	return actions


## 创建斩杀击杀特效(猩红冲击波 + is_critical 放大 → 明显区别于普通近战挥击)
func _create_execute_kill_vfx(
	source_id: String,
	target_ids: Array[String],
	context: FrontendVisualizerContext
) -> Array[FrontendVisualAction]:
	var actions: Array[FrontendVisualAction] = []

	if source_id.is_empty() or target_ids.is_empty():
		return actions

	var source_position := context.get_actor_position(source_id)

	for target_id in target_ids:
		var target_position := context.get_actor_position(target_id)

		var kill_vfx := FrontendAttackVFXAction.new(
			source_id,
			target_id,
			source_position,
			target_position,
			EXECUTE_KILL_VFX_DURATION,
			FrontendAttackVFXAction.AttackVFXType.IMPACT,
			Color(1.0, 0.12, 0.08),  # 猩红
			true,  # is_critical → 放大
			EXECUTE_KILL_VFX_DELAY  # 独立"斩杀"收尾,不与起手挥击糊在一起
		)
		actions.append(kill_vfx)

		# 醒目"斩杀!"飘字 —— 复用已验证清晰可辨的飘字系统(CRITICAL 强调样式 +
		# 大红),远相机下也一眼可读,IMPACT 当命中闪,文字当不可错认的击杀播报。
		var callout := FrontendFloatingTextAction.new(
			target_id,
			"斩杀!",
			Color(1.0, 0.15, 0.1),
			target_position,
			FrontendFloatingTextAction.FloatingTextStyle.CRITICAL,
			context.get_animation_config().damage_floating_text_duration,
			EXECUTE_KILL_VFX_DELAY
		)
		actions.append(callout)

	return actions
