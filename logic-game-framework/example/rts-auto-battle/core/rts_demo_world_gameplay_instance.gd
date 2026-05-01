## RtsDemoWorldGameplayInstance - 4v4 demo / smoke 战斗的 world instance
##
## RtsWorldGameplayInstance 子类: 与 hex example 的 HexDemoWorldGameplayInstance 同构,
## 服务 demo / smoke entry, 留 hook 给 Phase 2 P2.5 接 production_system / building factories。
##
## Phase 1 此子类很薄: 仅修改 type 标识符与 id prefix, 让 GameWorld registry / 录像
## 区分"demo 战斗" vs"未来 player 命令驱动战斗"。
##
## 战斗工厂 _create_battle_procedure 继承自父类 RtsWorldGameplayInstance.start_rts_battle 已经
## 构造好的 RtsAutoBattleProcedure 走法, 子类无需 override。
class_name RtsDemoWorldGameplayInstance
extends RtsWorldGameplayInstance


func _init() -> void:
	super._init(IdGenerator.generate("rts_demo"))
	type = "rts_demo"
