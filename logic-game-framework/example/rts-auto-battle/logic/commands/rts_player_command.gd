## RtsPlayerCommand - 玩家命令基类 (P2.6)
##
## 表示玩家在某 tick 发起的一次离散指令 (放建筑 / 升级 / 卖建筑 / 单位下命令)。
## procedure 在每 tick step 2 调 RtsPlayerCommandQueue.apply_due 把所有 tick_stamp
## ≤ current_tick 的命令应用; apply 返回 result dict, 失败 (合法性 / 资源不足) 时
## 不静默丢弃 — 命令进 _failed_commands 给 replay / UI 反馈。
##
## 不变量:
##   - 命令一旦构造, tick_stamp / team_id / 主参数不变 (每次 enqueue 是新对象)
##   - apply 是幂等的 (调方应用一次后将命令出队, 不重复 apply)
##   - apply 不依赖外部全局状态; 仅读 procedure / world 参数
##
## 决策来源: phase-2-core-systems.md §P2.6 (子类 PlaceBuildingCommand /
## UpgradeBuildingCommand / SellBuildingCommand)
class_name RtsPlayerCommand
extends RefCounted


# ========== 字段 ==========

## 命令应用的 tick (procedure._current_tick); 调方在 enqueue 时填。
## tick 0 = 战斗起手; tick stamp 小于 current_tick 视为"过期"也被 apply (无 backlog 丢弃)。
var tick_stamp: int = 0

## 发起方阵营 (0/1)。procedure 用此校验"这个 team 是否在该战斗中"。
var team_id: int = -1


# ========== 钩子 (子类 override) ==========

## 应用此命令。返回 dict:
##   { "success": bool, "reason": String, "details": Dictionary (可选) }
##
## reason 在 success=false 时填合法性失败原因 ("not_enough_resources" /
## "out_of_build_zone" / "cells_occupied" 等枚举字符串)。
##
## 子类可在 details 里返回创建出的 actor id (PlaceBuildingCommand 返回新建筑 id),
## 给 smoke / replay 引用。
func apply(_procedure, _world) -> Dictionary:
	return { "success": false, "reason": "not_implemented" }


## 命令类型字符串 (录像 / 调试用; 与 class_name 对齐避免反射开销)。
func command_type() -> String:
	return "rts_player_command"


## 序列化为 dict (用于 replay 录像 player_commands 字段)。
##
## 子类 override + 调 super.serialize() 拿基础字段; 加自己的特化字段。
func serialize() -> Dictionary:
	return {
		"type": command_type(),
		"tick_stamp": tick_stamp,
		"team_id": team_id,
	}
