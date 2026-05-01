## RtsProductionSystem - 建筑周期生产单位系统 (P2.5)
##
## procedure 主循环每 tick 调一次. 走 world 全部 alive RtsBuildingActor, 按
## production_period_ms 累积 _production_progress_ms, 满周期触发 spawn。
##
## 设计为纯 RefCounted (不挂 LGF System / 不持场景树), 所有"创建 actor + nav agent +
## controller + 加入 procedure team" 的副作用通过 spawner: Callable 回调外部完成 — smoke 与
## procedure 之间通过 unit_spawner opts 注入 (与 event_sink / unit_runtimes 同模式)。
##
## spawner 签名:
##   func(building: RtsBuildingActor) -> RtsUnitActor
## 返回 null 表示 spawn 失败 (spawn 位被占 / 玩家 cap 已满 etc), 系统当作未生产, 周期不重置 —
## 下次 tick 再试。返回非 null → progress 减一周期 (溢出量保留)。
##
## 决定性 (replay bit-equal 友好):
##   - world.get_actors() 按 insertion order 迭代 (Godot 4 dict 语义)
##   - 进度累积 dt × production_speed_multiplier 是浮点确定性 (同 seed → 同 dt 序列)
##   - spawner 内部不应调 randf (smoke / 调方负责; production_system 自己零 randf)
##
## 决策来源: phase-2-core-systems.md §P2.5
class_name RtsProductionSystem
extends RefCounted


# ========== Tick ==========

## 推进所有 alive 生产建筑一帧。
##
## @param dt_ms     本帧 tick 时长 (ms; 与 procedure._tick_interval 一致)
## @param world     RtsWorldGameplayInstance, 用于 get_actors() 拿全部建筑
## @param spawner   Callable(building: RtsBuildingActor) -> RtsUnitActor; 实际创建/注册单位
##
## @return 本帧成功 spawn 的单位数 (spawner 返回非 null 计 1)
func tick(dt_ms: float, world: RtsWorldGameplayInstance, spawner: Callable) -> int:
	if world == null or not spawner.is_valid():
		return 0
	if dt_ms <= 0.0:
		return 0

	var spawn_count: int = 0
	for actor in world.get_actors():
		if not (actor is RtsBuildingActor):
			continue
		var building := actor as RtsBuildingActor
		if building.is_dead():
			continue
		if building.production_period_ms <= 0.0:
			continue
		if building.spawn_unit_kind < 0:
			continue

		# 累积 progress; production_speed_multiplier 来自 attribute_set (默认 1.0)
		var multiplier: float = 1.0
		if building.attribute_set != null:
			multiplier = building.attribute_set.production_speed_multiplier
		building._production_progress_ms += dt_ms * multiplier

		# 满周期 → 触发 spawn (一 tick 多周期溢出仅触发 1 次, 简化 — 高产出建筑遇极慢 tick
		# 时损失少量产能, 但 4s 周期 vs 50ms tick 差距 80×, 实战不会触发)。
		if building._production_progress_ms >= building.production_period_ms:
			var spawned: RtsUnitActor = spawner.call(building) as RtsUnitActor
			if spawned != null:
				building._production_progress_ms -= building.production_period_ms
				spawn_count += 1
			# spawner 返回 null → 下次 tick 重试; progress 不重置 (可能溢出累积, 由调方负责检验)

	return spawn_count
