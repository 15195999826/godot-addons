## RtsIdleActivity - 空闲意图 (P2.1)
##
## 单位无敌可见 / 无命令时的 fallback。tick 永远返回 true, 等外部 cancel。
## actor.current_target_id 在 on_first_run 清空, 防止上一 AttackActivity 残留。
##
## 决策来源: phase-2-core-systems.md P2.1 (子 activity 列表)
class_name RtsIdleActivity
extends RtsActivity


func on_first_run(actor: RtsUnitActor, _world: RtsWorldGameplayInstance) -> void:
	if actor != null:
		actor.current_target_id = ""


func tick(_actor: RtsUnitActor, _world: RtsWorldGameplayInstance, _dt: float) -> bool:
	return true


func is_equivalent_to(other: RtsActivity) -> bool:
	return other is RtsIdleActivity


func get_intent_label() -> String:
	return "idle"
