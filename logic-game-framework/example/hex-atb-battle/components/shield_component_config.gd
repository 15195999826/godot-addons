## ShieldComponent 配置
##
## 定义护盾的容量、可吸收伤害类型、消耗优先级、叠加策略，
## 以及破裂 / 到期时的回调。Ability._resolve_components() 据此创建
## HexBattleShieldComponent 实例（每个 Ability 独立一份，状态隔离）。
##
## V1 仅实现 stacking_policy = "independent"：每次 ApplyShieldAction
## 都产生一个独立的护盾 ability 实例，由 ShieldResolver 统一排序消耗。
##
## 回调签名（V2 落地 Aphotic / Rune 时再实际使用）：
##   on_break:  func(record: Dictionary, ctx: ExecutionContext, battle: HexWorldGameplayInstance) -> Array[Dictionary]
##              record 字段见 HexBattleShieldComponent.get_state_snapshot()，附加 absorbed / broken / damage_type。
##              返回的事件已 push 到 event_collector，由调用方收集。
##   on_expire: func(record: Dictionary, ctx_or_null: AbilityLifecycleContext) -> void
##              到期路径独立于伤害流程，由 ability lifecycle 在 on_remove 钩子里触发（仅当 reason == time_duration）。
class_name HexBattleShieldComponentConfig
extends AbilityComponentConfig


## 护盾容量
var capacity: float = 0.0

## 可吸收的伤害类型字符串列表（"physical" / "magical" / "pure"）；
## 含 "all" 或为空则吸收任意类型。
var damage_types: Array[String] = ["all"]

## 消耗优先级（高优先级先消耗）
var priority: int = 0

## 叠加策略（V1 占位字段，仅支持 "independent"）
var stacking_policy: String = "independent"

## 破裂回调（V1 可为空）
var on_break: Callable = Callable()

## 到期回调（V1 可为空）
var on_expire: Callable = Callable()


func _init(
	p_capacity: float = 0.0,
	p_damage_types: Array[String] = ["all"],
	p_priority: int = 0,
	p_stacking_policy: String = "independent",
	p_on_break: Callable = Callable(),
	p_on_expire: Callable = Callable()
) -> void:
	capacity = p_capacity
	damage_types = p_damage_types
	priority = p_priority
	stacking_policy = p_stacking_policy
	on_break = p_on_break
	on_expire = p_on_expire


func create_component() -> AbilityComponent:
	return HexBattleShieldComponent.new(self)
