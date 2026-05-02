## RtsMinimalPushOut - Phase 1 最简圆形 push-out (O(N²) 双重循环)
##
## 决策来源: phase-1-foundation.md P1.2 "为什么需要 push-out"
##
## 背景: P1.2 移除 NavigationAgent2D.avoidance_enabled 后, 4v4 单位短兵相接时会重叠
## (collision_radius 不被尊重) → 主 smoke 的 melee_max_dist 断言假阳。
##
## 算法(Phase 1 妥协, Phase 2 P2.2 用 spatial hash + 完整 steering 替换):
##   for each pair (a, b):
##       dist = a.position_2d.distance_to(b.position_2d)
##       min_dist = a.collision_radius + b.collision_radius
##       if dist < min_dist:
##           push_dir = (a.pos - b.pos) / dist
##           overlap = min_dist - dist
##           a.pos += push_dir * overlap * 0.5
##           b.pos -= push_dir * overlap * 0.5
##
## 不变量:
##   - 决定性: 迭代顺序 = world.get_alive_units() 顺序(GameWorld 保证插入顺序)
##   - 决定性: 不调 randf
##   - 跨 layer 不互推 (Phase 1 GROUND only; Phase 2 P2.8 加 AIR 时这里需扩展 layer check)
##   - 死亡单位不参与
##   - O(N²): 4v4 = 28 pair 完全可接受; 100+ 单位时必须切到 spatial hash
class_name RtsMinimalPushOut
extends RefCounted


## 浮点容差 — 距离 < 0.001 视为完全重合, 跳过(避免除零)。
const EPSILON: float = 0.001


## 解析一帧的 push-out。`units` 是 RtsUnitActor 列表(必须存活)。
## 直接修改每个 unit 的 position_2d; 不返回值。
##
## 调方约定: 在 procedure tick 末尾、actor.position_2d += velocity*dt 之后调用,
## 让 push-out 修正后的位置作为本 tick 的最终位置(下 tick AI / nav 拿到的就是修正后的)。
static func resolve(units: Array) -> void:
	var n: int = units.size()
	for i in range(n):
		var a := units[i] as RtsBattleActor
		if a == null or a.is_dead():
			continue
		for j in range(i + 1, n):
			var b := units[j] as RtsBattleActor
			if b == null or b.is_dead():
				continue
			# Phase 1 GROUND only; Phase 2 P2.8 时此处加 layer check (跨 layer 不挤)
			if a.movement_layer != b.movement_layer:
				continue

			var diff: Vector2 = a.position_2d - b.position_2d
			var dist_sq: float = diff.length_squared()
			var min_dist: float = a.collision_radius + b.collision_radius
			# 早出避免 sqrt: 不重叠 (≥ min) 或完全重合 (< EPSILON) 都跳过
			if dist_sq >= min_dist * min_dist or dist_sq < EPSILON * EPSILON:
				continue
			var dist: float = sqrt(dist_sq)
			var push_dir: Vector2 = diff / dist
			var overlap: float = min_dist - dist
			a.position_2d += push_dir * (overlap * 0.5)
			b.position_2d -= push_dir * (overlap * 0.5)
