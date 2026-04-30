## RtsWorldGameplayInstance - RTS 连续坐标战斗世界 Instance
##
## WorldGameplayInstance 子类: 不依赖 UGridMap / hex grid, 用连续 Vector2 描述位置。
## NavigationRegion2D 由 frontend / smoke 入口注入, 提供给 actor 寻路。
##
## 战斗推进由 RtsAutoBattleProcedure 承担。
class_name RtsWorldGameplayInstance
extends WorldGameplayInstance


# ========== 字段 ==========

## 地图边界(像素), 仅供 AI / 出生点采样使用; 物理边界由 NavigationRegion2D 决定。
var map_size: Vector2 = Vector2(500.0, 500.0)

## NavigationRegion2D 句柄, 由 frontend / smoke 入口注入。
## 为 null 时 actor 退化为直线接敌(M0.4 之前 / RTS 单测中允许)。
var navigation_region: NavigationRegion2D = null


# ========== 初始化 ==========

func _init(id_value: String = "") -> void:
	super._init(id_value if id_value != "" else IdGenerator.generate("rts_world"))
	type = "rts_world"


## 注入 NavigationRegion2D。frontend / smoke 在 _ready 中构造后调用。
func set_navigation_region(region: NavigationRegion2D) -> void:
	navigation_region = region


# ========== Actor registry ==========

## 仅返回存活的 actor id 集合, 服务 EventProcessor.process_post_event 广播。
## RtsBattleActor 子类暴露 is_dead(); 非 RtsBattleActor 视作非战斗对象, 不进集合。
func get_alive_actor_ids() -> Array[String]:
	var result: Array[String] = []
	for actor in get_actors():
		if actor is RtsBattleActor and not (actor as RtsBattleActor).is_dead():
			result.append(actor.get_id())
	return result


func get_alive_actors() -> Array[RtsBattleActor]:
	var result: Array[RtsBattleActor] = []
	for actor in get_actors():
		if actor is RtsBattleActor and not (actor as RtsBattleActor).is_dead():
			result.append(actor as RtsBattleActor)
	return result
