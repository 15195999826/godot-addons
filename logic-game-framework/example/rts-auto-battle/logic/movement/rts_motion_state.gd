## RtsMotionState - 单位 motion 整 turn transient 状态(0 A.D. CCmpUnitMotionManager.MotionState 复刻)
##
## Manager 把每个 motion-bearing actor 的"turn 内"动态状态存这里:initial_pos / pos / push /
## pushing_pressure / 各种 flag。PreMove 写 initial;Move 改 pos;Push 累 push;PushAdjust 把
## push 应用到 pos;PostMove 把 pos 写回 actor.position_2d。
##
## **生命周期**:跟 actor 1:1, 由 Manager 在 register / unregister 时持有。actor 死亡或离场时
## Manager unregister 释放 state。
##
## **不变量**(各阶段后):
##   - PreMove 末:initial_pos == pos == actor.position_2d, push = 0
##   - Move 末:pos = 走完 path 段后的位置, push = 0
##   - Push pass 末:push 累各对手贡献(可能 > 0 / < 0)
##   - PushAdjust 末:pos += push, push = 0
##   - PostMove 末:actor.position_2d = pos, obstr_mgr.move_shape 同步
##
## **Phase A 阶段**:此 class 已定义但 Manager move_units 走 legacy 路径(component.tick +
## push_pass × N)不消费 state — Phase B 起 PreMove/Move/PostMove 真实现时使用。
##
## **决策来源**:
##   - 0 A.D. CCmpUnitMotionManager::MotionState (CCmpUnitMotionManager.h:42-90)
##   - plan: async-herding-newt.md "数据结构" 段
class_name RtsMotionState
extends RefCounted


# ========== Identity ==========

## actor_id (= owner_actor.get_id()).
var entity_id: String = ""

## 同 obstr_shape.control_group;= str(team_id),Manager push pass 内 sameControlGroup 判定用。
var control_group: String = ""


# ========== Turn-local state ==========

## Turn 开头 snapshot;PreMove 写,Move/Push/PushAdjust 不改。
var initial_pos: Vector2 = Vector2.ZERO

## Turn 内 transient;Move 推进 pos,Push 累计 state.push,PushAdjust apply,PostMove 写回 actor。
var pos: Vector2 = Vector2.ZERO

## 整 turn pairwise push 累计,PushAdjust 阶段 apply 到 pos 后清零。
var push: Vector2 = Vector2.ZERO

## 0..MAX_PRESSURE=255;Push pass 每 pair 累加,Move 末 decay = pressure × 0.6。
##
## 高 pressure → push 力度被 dampen,单位"陷"在拥挤区(0 A.D. CCmpUnitMotion_System.cpp:600)。
var pushing_pressure: int = 0


# ========== Speed / angle ==========

## 当前 turn 速度(motion._current_speed mirror)— PreMove 从 motion 读,Move 内可能改。
var speed: float = 0.0

## Turn 开头 angle snapshot。
var initial_angle: float = 0.0

## 当前 turn angle。
var angle: float = 0.0


# ========== Flags ==========

## true = 此 unit 不参与 push(死者 / spawn 中 / 飞行单位 / block_movement off);Manager skip。
var ignore: bool = false

## true = 此 unit 本 turn 需要 Move/PostMove 处理;PreMove 写,false 时 Manager skip。
##
## 0 A.D. 决策:`needUpdate = is_in_world && (currentSpeed != 0 || lastTurnSpeed != 0 || moveRequest != NONE)`
## (CCmpUnitMotion.h:1044-1045)
var need_update: bool = false

## Move 内若走直线(TryGoingStraightToTarget)则 true,会跳过 turn 末的 PathingUpdateNeeded 重算。
var went_straight: bool = false

## Move / PushAdjust 内若被 obstacle 阻挡则 true;PostMove 内调 HandleObstructedMove 处理。
var was_obstructed: bool = false

## obstr_mgr FLAG_MOVING mirror;PreMove 写,obstr_mgr.set_unit_moving_flag 在切换时调。
var is_moving: bool = false


# ========== 初始化 ==========

func _init(p_entity_id: String = "", p_control_group: String = "") -> void:
	entity_id = p_entity_id
	control_group = p_control_group
