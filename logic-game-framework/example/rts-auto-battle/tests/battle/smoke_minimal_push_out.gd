## RTS minimal push-out smoke (P1.2)
##
## 验证 RtsMinimalPushOut.resolve():
##   1. 4 个 melee 单位都被设到接近同一点 (collision_radius=12, 2r=24);
##   2. 跑 60 个 push-out tick 后, 任意两单位的 distance ≥ collision_radius * 2 - 0.5;
##   3. 没有单位的 position 漂得离起点不合理远(>50 px).
##
## 算法是 O(N²) 一帧解析多次直到稳定; 这里跑 60 帧足以让 4 单位散开。
##
## Phase 2 P2.2 用 spatial hash + 完整 steering 替换时, 此 smoke 改 import 新的实现即可继续工作。
extends Node


const Config := preload("res://addons/logic-game-framework/example/rts-auto-battle/logic/config/rts_unit_class_config.gd")

## 每帧推一次 push-out, 60 帧应足以让单位互相散开
const FRAMES_TO_RUN: int = 60

## 容差 (px)
const TOLERANCE: float = 0.5


func _ready() -> void:
	GameWorld.init()

	# 4 个 melee, 都从 (250, 250) ± 微小偏移开始, 完全重合
	var units: Array[RtsUnitActor] = []
	var offsets: Array[Vector2] = [
		Vector2(0.1, 0.0),
		Vector2(-0.1, 0.0),
		Vector2(0.0, 0.1),
		Vector2(0.0, -0.1),
	]
	for i in range(4):
		var actor := RtsUnitActor.new(Config.UnitClass.MELEE)
		actor.set_team_id(0)
		actor.set_id("u%d" % i)
		actor.position_2d = Vector2(250.0, 250.0) + offsets[i]
		units.append(actor)

	# 验证默认 collision_radius
	if units[0].collision_radius != 12.0:
		_fail("expected MELEE collision_radius=12.0, got %f" % units[0].collision_radius)
		return

	# 跑 push-out 60 帧
	for f in range(FRAMES_TO_RUN):
		RtsMinimalPushOut.resolve(units)

	# 主断言: 任意两单位距离 ≥ 2r - tolerance
	var min_required: float = units[0].collision_radius * 2.0 - TOLERANCE  # = 23.5
	for i in range(units.size()):
		for j in range(i + 1, units.size()):
			var dist := units[i].position_2d.distance_to(units[j].position_2d)
			if dist < min_required:
				_fail("units[%d] and units[%d] too close: dist=%.4f < %.4f (2r=%.1f)" % [
					i, j, dist, min_required, units[0].collision_radius * 2.0,
				])
				return

	# 辅助断言: 没单位漂得太远 (push-out 不应失控)
	var origin := Vector2(250.0, 250.0)
	for i in range(units.size()):
		var d := units[i].position_2d.distance_to(origin)
		if d > 50.0:
			_fail("units[%d] drifted too far: dist=%.2f" % [i, d])
			return

	print("push-out smoke: 4 units separated, positions=%s" % str([
		units[0].position_2d, units[1].position_2d, units[2].position_2d, units[3].position_2d,
	]))

	GameWorld.destroy()
	print("SMOKE_TEST_RESULT: PASS - O(N²) push-out separates 4 overlapping units")
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("SMOKE_TEST_RESULT: FAIL - %s" % reason)
	get_tree().quit(1)
