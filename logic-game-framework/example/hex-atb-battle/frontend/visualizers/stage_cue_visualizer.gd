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
	"melee_slash",   # 横扫斩
	"melee_heavy",   # 毁灭重击
	"melee_combo",   # 疾风连刺
]

# ========== 需要播放治疗特效的 cue_id ==========

const HEAL_CUES := [
	"magic_heal",    # 圣光治愈
]


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
	
	var actions: Array[FrontendVisualAction] = []
	
	# 近战攻击类 cue → 攻击箭头特效
	if cue_id in MELEE_ATTACK_CUES:
		actions.append_array(_create_melee_attack_vfx(source_id, target_ids, cue_id, context))
	# 治疗类 cue → 治疗光束特效
	elif cue_id in HEAL_CUES:
		actions.append_array(_create_heal_vfx(source_id, target_ids, context))
	# 其他 cue_id（如 magic_fireball, ranged_arrow）不需要额外特效
	# 因为它们有投射物飞行动画
	
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
			_get_attack_vfx_color_by_team(source_team, false),  # 暴击信息在 damage 事件中，这里默认非暴击
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
		_:
			return FrontendAttackVFXAction.AttackVFXType.SLASH


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
