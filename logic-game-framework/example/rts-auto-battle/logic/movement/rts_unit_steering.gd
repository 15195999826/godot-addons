## RtsUnitSteering - 单位避障 steering (separation + deflection, 避障第 1+2 层) (P2.2)
##
## 在 nav 写 actor.velocity (waypoint 方向) 之后, integrate (position += velocity*dt) 之前调用,
## 修改 actor.velocity 让单位之间互相避让。配合 P1.2 的 grid + A* 寻路 (避静态建筑) 与
## P2.3 的 stuck detection (避动态围困) 构成完整避障管线。
##
## 避障层 1 (separation):
##   - 邻居 = 同层 RtsUnitActor (RtsBuildingActor 不进 steering — 寻路已绕开静态建筑)
##   - 跨 layer (GROUND / AIR) 不互相挤
##   - **应用于所有单位** (含静止 idle / 攻击中 attacker) — 静止单位不施 sep 会让 cluster 抵达
##     目标后永久重叠; 应用全单位需 sep_radius = r_a + r_b 严格 (无 buffer), 否则 atk_range
##     内的 attackers (dist=2r=atk_range) 会被推开破坏接战
##   - sep_radius = r_a + r_b (无 buffer); 仅 dist < sep_radius 时施力 (即真正 overlap 才推)
##   - sep 方向: 远离邻居; 强度: (sep_radius - dist) / sep_radius (0 at edge, ~1 at overlap)
##
## 避障层 2 (deflection):
##   - 检测"迎面对撞": self.velocity 与 neighbor.velocity 几乎反向 (dot < HEAD_ON_DOT_THRESHOLD)
##     且 self 朝 neighbor 飞 (velocity 与 to_neighbor 同向)
##   - 旋转最终 velocity ±DEFLECTION_ANGLE (~28°), 旋转方向由 actor_id parity 决定 (决定性,
##     不调 randf)
##   - deflection 仅作用于"正在移动" (velocity > 0) 的单位 — 静止单位无方向可旋转
##
## 决定性 (replay bit-equal 必备):
##   - 邻居列表来自 spatial_hash.query_radius (sort by id)
##   - 求和顺序稳定 (按 sorted id 迭代)
##   - 偏转方向: actor_id char-sum 奇偶性 (确定函数, 不依赖 RNG)
##
## 决策来源: phase-2-core-systems.md §P2.2
class_name RtsUnitSteering
extends RefCounted


# ========== 调参常量 ==========

## separation 强度系数 (相对 move_speed)。1.0 = 单帧最多抵消整个 desired velocity。
const SEPARATION_WEIGHT: float = 1.5

## sep_force 总强度上限 (相对 move_speed)。
##
## 不限制时, N 个邻居叠加的 sep 可能远超 move_speed (clamp 到 move_speed 后变成"全推"),
## 导致 cluster 后半部单位被推远离目标后赶不回来。0.7 = 后侧单位至少 0.3 * move_speed
## 朝目标前进, 不会被 sep 完全反向。
const MAX_SEP_FRACTION: float = 0.7

## sep_radius 在 (r_a + r_b) 之上的额外缓冲 (像素)。
##
## 0 = 严格"仅 overlap 时推": dist < r_a + r_b 才施力。这是保 atk_range 接战不被破坏的关键 —
## melee 单位 collision_radius=12, attack_range=24 = 2r, 即 attackers 在 atk_range 时 dist=2r,
## 此时 strength=0 不推。任何 buffer > 0 都会让 attackers 被推到 atk_range + buffer 之外。
const SEPARATION_BUFFER: float = 0.0

## 迎面相向 dot 阈值。velocity dir 与 neighbor velocity dir 的内积 < 此值视为反向。
## -0.85 ≈ 反向 ±30° 的锥; 太严格 (-0.95) 多数实战擦肩而过不算迎面。
const HEAD_ON_DOT_THRESHOLD: float = -0.85

## 自身 velocity 朝 neighbor 的 dot 阈值。> 此值视为"朝着邻居飞"。
const APPROACHING_DOT_THRESHOLD: float = 0.7

## deflection 偏转角度 (弧度); 0.5 ≈ 28.6°.
const DEFLECTION_ANGLE: float = 0.5


# ========== 入口 ==========

## 修改 actor.velocity (in-place) 加入 separation + deflection 力。
##
## actor 必须是 RtsUnitActor; 其他 type (RtsBuildingActor) 直接跳过。
## 死亡 / 静止 (velocity ≈ 0) actor 跳过 — sep 不施于不动的单位。
##
## @param actor 当前单位
## @param spatial_hash 已 update_all 过的 hash, 用于查邻居候选
## @param world Gameplay world; 通过 id 取邻居 actor
## @param _dt 暂未使用 (force 是瞬时增量, 与 dt 解耦); 保留为对称接口
static func apply(
	actor: RtsBattleActor,
	spatial_hash: RtsSpatialHash,
	world: RtsWorldGameplayInstance,
	_dt: float,
) -> void:
	if actor == null or actor.is_dead() or world == null or spatial_hash == null:
		return
	if not (actor is RtsUnitActor):
		return  # buildings / non-units don't steer

	var unit := actor as RtsUnitActor
	var move_speed: float = unit.attribute_set.move_speed
	if move_speed <= 0.0:
		return

	# 搜索半径 = 最大 sep_radius (worst case 2 大单位); +8 px 留余量给桶边界 actor
	var search_radius: float = unit.collision_radius * 2.0 + SEPARATION_BUFFER + 8.0
	var candidate_ids: Array[String] = spatial_hash.query_radius(unit.position_2d, search_radius)

	var sep_force: Vector2 = Vector2.ZERO
	var head_on_count: int = 0

	# 静止单位 vel_dir = 0; deflection 检测在 vel_len > 0 内才跑
	var vel_len_sq: float = unit.velocity.length_squared()
	var vel_dir: Vector2 = unit.velocity.normalized() if vel_len_sq > 0.0001 else Vector2.ZERO

	for nid in candidate_ids:
		if nid == unit.get_id():
			continue
		var neighbor := world.get_actor(nid) as RtsBattleActor
		if neighbor == null or neighbor.is_dead():
			continue
		if neighbor.movement_layer != unit.movement_layer:
			continue  # 跨 layer 不互相挤
		if not (neighbor is RtsUnitActor):
			continue  # 静态 building 不进 steering (寻路已绕开)

		var neighbor_unit := neighbor as RtsUnitActor
		var diff: Vector2 = unit.position_2d - neighbor_unit.position_2d
		var dist: float = diff.length()
		var sep_radius: float = unit.collision_radius + neighbor_unit.collision_radius + SEPARATION_BUFFER
		if dist <= 0.0001 or dist >= sep_radius:
			continue

		var push_dir: Vector2 = diff / dist
		var strength: float = (sep_radius - dist) / sep_radius  # 0..1
		sep_force += push_dir * strength * move_speed * SEPARATION_WEIGHT

		# 迎面对撞检测: self 朝 neighbor 飞 + neighbor 朝 self 飞
		# 仅 vel_dir != 0 时检测 — 静止单位无方向可"迎面"
		if vel_dir != Vector2.ZERO:
			var to_neighbor: Vector2 = -push_dir
			if vel_dir.dot(to_neighbor) > APPROACHING_DOT_THRESHOLD:
				var n_vel_len_sq: float = neighbor_unit.velocity.length_squared()
				if n_vel_len_sq > 0.0001:
					var n_vel_dir: Vector2 = neighbor_unit.velocity.normalized()
					if vel_dir.dot(n_vel_dir) < HEAD_ON_DOT_THRESHOLD:
						head_on_count += 1

	# Cap sep_force magnitude — 避免 N 邻居叠加 + clamp 让后侧单位被完全反向推
	var max_sep: float = move_speed * MAX_SEP_FRACTION
	if sep_force.length_squared() > max_sep * max_sep:
		sep_force = sep_force.normalized() * max_sep

	# Apply separation
	var combined: Vector2 = unit.velocity + sep_force

	# Apply deflection (head-on resolution)
	if head_on_count > 0 and combined.length_squared() > 0.0001:
		var sign_factor: float = 1.0 if (_actor_id_parity(unit.get_id()) == 0) else -1.0
		combined = combined.rotated(DEFLECTION_ANGLE * sign_factor)

	# Clamp magnitude to move_speed
	if combined.length_squared() > move_speed * move_speed:
		combined = combined.normalized() * move_speed

	unit.velocity = combined


# ========== 内部 ==========

## actor_id 字符 unicode 之和的奇偶性。0 → CCW (sign +1), 1 → CW (sign -1)。
## 决定性: 同 id 同结果, 不依赖 RNG / hash 实现细节。
static func _actor_id_parity(actor_id: String) -> int:
	var sum: int = 0
	for i in range(actor_id.length()):
		sum += actor_id.unicode_at(i)
	return sum % 2
