## Dota2WorldGameplayInstance - dota2-auto-battle 连续坐标战斗世界 Instance
##
## WorldGameplayInstance 子类：长期持 actor registry；战斗是临时 Dota2AutoBattleProcedure。
## 与 hex HexWorldGameplayInstance / rts RtsWorldGameplayInstance 同构。战斗推进由
## Dota2AutoBattleProcedure 内化（frontend logic clock / smoke 直接 drive tick_once，
## **不**走 WorldGI.tick 的 blocking 循环）。
class_name Dota2WorldGameplayInstance
extends WorldGameplayInstance


## 即将传给 procedure 的 opts（start_dota2_battle 写，_create_battle_procedure 读）。
var _pending_opts: Dictionary = {}


func _init(id_value: String = "") -> void:
	super._init(id_value if id_value != "" else IdGenerator.generate("dota2_world"))
	type = "dota2_world"


# ========== 战斗调度 ==========

## 启动一场 dota2 lane 战斗。返回 procedure，调方负责 tick_once / finish。
## opts 键：tick_interval_ms: float（默认 30Hz）。teams 由 WaveSpawner 在
## procedure.start() 内动态创建（spawner 不发 intent）。
func start_dota2_battle(opts: Dictionary = {}) -> Dota2AutoBattleProcedure:
	_pending_opts = opts
	var procedure := start_battle([] as Array[Actor]) as Dota2AutoBattleProcedure
	_pending_opts = {}
	return procedure


## 工厂钩子：WorldGameplayInstance.start_battle 调用此函数创建 procedure。
func _create_battle_procedure(_participants: Array[Actor]) -> BattleProcedure:
	return Dota2AutoBattleProcedure.new(self, _pending_opts)


# ========== Actor registry ==========

## 覆盖父类，返回类型收窄为 Dota2BattleActor（公共战斗管线平权处理 unit / 未来 tower）。
func get_actor(actor_id: String) -> Dota2BattleActor:
	return super.get_actor(actor_id) as Dota2BattleActor


## 存活 actor id 集合，服务 EventProcessor.process_post_event 广播。
## 过滤 ability_set == null 的纯 data actor（post_event 走 IAbilitySetOwner 后 assert 非 null）。
func get_alive_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor in get_actors():
		if not (actor is Dota2BattleActor):
			continue
		var ba := actor as Dota2BattleActor
		if ba.is_dead() or ba.ability_set == null:
			continue
		result.append(ba.get_id())
	return result


## 仅返回存活的 Dota2UnitActor（M1 全是 unit；未来 tower/building 不进此列表）。
func get_alive_units() -> Array[Dota2UnitActor]:
	var result: Array[Dota2UnitActor] = []
	for actor in get_actors():
		if actor is Dota2UnitActor and not (actor as Dota2UnitActor).is_dead():
			result.append(actor as Dota2UnitActor)
	return result
