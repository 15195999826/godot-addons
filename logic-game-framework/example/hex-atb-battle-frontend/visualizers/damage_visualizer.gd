## DamageVisualizer - 伤害事件转换器
##
## 将 damage 事件翻译为飘字、受击闪白和血条更新动作
## 注意：攻击特效由 StageCueVisualizer 处理，不在此处
class_name FrontendDamageVisualizer
extends FrontendBaseVisualizer


func _init() -> void:
	visualizer_name = "DamageVisualizer"


## 检查是否为伤害事件
func can_handle(event: Dictionary) -> bool:
	return get_event_kind(event) == "damage"


## 翻译伤害事件为视觉动作
func translate(event: Dictionary, context: FrontendVisualizerContext) -> Array[FrontendVisualAction]:
	var config := context.get_animation_config()
	
	var e := BattleEvents.DamageEvent.from_dict(event)
	var target_id := e.target_actor_id
	var actual_life_damage := e.actual_life_damage
	var shield_absorbed := e.shield_absorbed
	var is_critical := e.is_critical
	var is_reflected := e.is_reflected

	var target_position := context.get_actor_position(target_id)
	var current_hp := context.get_actor_hp(target_id)

	var actions: Array[FrontendVisualAction] = []

	# 1. 伤害飘字（按 actual_life_damage 显示；shield_absorbed 单独飘字）
	if actual_life_damage > 0.0:
		var text := "-%d" % roundi(actual_life_damage)
		if is_reflected:
			text = "反伤 " + text
		var style := FrontendFloatingTextAction.FloatingTextStyle.CRITICAL if is_critical else FrontendFloatingTextAction.FloatingTextStyle.NORMAL
		var color := _get_damage_color(is_critical, is_reflected)
		var floating_text := FrontendFloatingTextAction.new(
			target_id,
			text,
			color,
			target_position,
			style,
			config.damage_floating_text_duration
		)
		actions.append(floating_text)

	if shield_absorbed > 0.0:
		var absorb_text := "护盾 -%d" % roundi(shield_absorbed)
		var absorb_floating := FrontendFloatingTextAction.new(
			target_id,
			absorb_text,
			Color(0.4, 0.8, 1.0),  # 浅蓝
			target_position,
			FrontendFloatingTextAction.FloatingTextStyle.NORMAL,
			config.damage_floating_text_duration
		)
		actions.append(absorb_floating)

	# 2. 受击闪白（仅当真打到肉，全吸收时不闪）
	if actual_life_damage > 0.0:
		var hit_flash := FrontendProceduralVFXAction.new(
			FrontendProceduralVFXAction.EffectType.HIT_FLASH,
			config.damage_hit_vfx_duration,
			target_id
		)
		actions.append(hit_flash)

	# 3. 血条更新（按 actual_life_damage 扣血；全吸收时血条不动）
	if actual_life_damage > 0.0:
		var new_hp := maxf(0.0, current_hp - actual_life_damage)
		var update_hp := FrontendUpdateHPAction.new(
			target_id,
			current_hp,
			new_hp,
			config.damage_hp_bar_duration,
			config.damage_hp_bar_delay
		)
		actions.append(update_hp)

	return actions


## 根据伤害类型获取颜色
func _get_damage_color(is_critical: bool, is_reflected: bool) -> Color:
	if is_critical:
		return Color(1.0, 0.8, 0.0)  # 金色
	if is_reflected:
		return Color(0.8, 0.4, 1.0)  # 紫色
	return Color.WHITE
