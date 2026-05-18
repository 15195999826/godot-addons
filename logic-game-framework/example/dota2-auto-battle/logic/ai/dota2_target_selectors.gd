## Dota2TargetSelectors - Action 目标选择器（项目层）
##
## 基础攻击的权威目标来自 controller 的 AttackTargetIntent —— procedure 把它放进
## ABILITY_ACTIVATE_EVENT.target_actor_id 再喂给 ability_set.receive_event。Action 链里
## 的 on_tag DamageAction 通过本 selector 从事件链取回该目标（与 hex
## HexBattleTargetSelectors.CurrentTarget 同构）。execution 读"激活事件携带的 intent
## 目标"，不另立 actor-owned 真相。
class_name Dota2TargetSelectors
extends RefCounted


## 从当前事件链取 target_actor_id（基础攻击激活事件携带 controller 的 intent 目标）。
class CurrentTarget extends TargetSelector:
	func select(ctx: ExecutionContext) -> Array[String]:
		var event := ctx.get_current_event()
		if event.is_empty():
			return []
		var tid: Variant = event.get("target_actor_id", "")
		if tid is String and tid != "":
			return [tid]
		return []


static func current_target() -> CurrentTarget:
	return CurrentTarget.new()
