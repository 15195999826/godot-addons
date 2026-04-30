## RtsBattleActor - RTS 连续坐标战斗 Actor 基类
##
## RTS 例子的 Actor 公共合同: 连续坐标 position、team_id、is_dead 标志。
## 具体兵种(RtsCharacterActor)在 logic/rts_character_actor.gd 进一步特化。
##
## M0.2 仅提供最小公共合同 (position / is_dead / team) 让 WorldGI / Procedure 编译过;
## M0.3 在子类 RtsCharacterActor 中追加 attribute_set / ability_set / 兵种字段。
class_name RtsBattleActor
extends Actor


# ========== 公共字段 ==========

## 当前位置(像素, 连续坐标), 替代 hex_position
var position_2d: Vector2 = Vector2.ZERO

## 当前帧速度(像素/秒); navmesh 推路径时由 RtsNavAgent 写入, 仅信息性。
var velocity: Vector2 = Vector2.ZERO

## 队伍 ID(0=left, 1=right)
var team_id: int = -1

## 死亡标志(由 hp <= 0 时 procedure / action 设置)
var _is_dead: bool = false


# ========== 队伍 ==========

func set_team_id(p_team_id: int) -> void:
	team_id = p_team_id
	_team = str(p_team_id)


func get_team_id() -> int:
	return team_id


# ========== 死亡 ==========

func is_dead() -> bool:
	return _is_dead


## 标记为死亡(由 attack action / hp watcher 调用)。
func mark_dead() -> void:
	_is_dead = true


## 死亡 actor 不再响应 PreEvent handler, 与 hex 例子一致。
func is_pre_event_responsive() -> bool:
	return not _is_dead


# ========== 录像支持 ==========

## 用 Vector2 (x, y) 当 Vector3 (x, y, 0) 暴露给 BattleRecorder。
## configs.positionFormats["Character"] = "rts2d" 让渲染层正确解释。
func _get_position() -> Vector3:
	return Vector3(position_2d.x, position_2d.y, 0.0)


func _get_team_int() -> int:
	return team_id
