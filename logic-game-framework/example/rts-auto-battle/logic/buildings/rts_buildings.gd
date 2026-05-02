## RtsBuildings - RTS 建筑工厂模块 (P2.5)
##
## 与 hex example 的 HexBattleStoneWall 同构 — building_kind: String 区分 + 工厂方法批量
## 创建已配好属性的 RtsBuildingActor 实例。决策 E 锁定不为 CrystalTower 单独建子类。
##
## 工厂方法都返回未 add_actor 的实例; 调方按以下顺序使用:
##
##   var barracks := RtsBuildings.create_barracks()
##   barracks.set_team_id(0)
##   barracks.position_2d = Vector2(100, 250)
##   world.add_actor(barracks)                # 触发 _on_id_assigned 同步 ability_set / attrs
##   world.rts_grid.place_building(barracks.get_id(), barracks.get_footprint_cells(world.rts_grid))
##
## 决策来源: phase-2-core-systems.md §P2.5 + architecture-baseline.md §4 (子类家族 — 工厂模式)
class_name RtsBuildings


# ========== 工厂方法 ==========

## 水晶塔: 高 hp, 不生产 (P2.6 胜负判定 — 任一阵营 crystal_tower 死即结束战斗)。
static func create_crystal_tower() -> RtsBuildingActor:
	return _create_from_kind(RtsBuildingConfig.KIND_CRYSTAL_TOWER)


## 兵营: 周期 spawn melee 单位, 默认 4 秒一个; 生产单位 stance=AGGRESSIVE。
static func create_barracks() -> RtsBuildingActor:
	return _create_from_kind(RtsBuildingConfig.KIND_BARRACKS)


## 防御塔: 中 hp, 不生产; P2.8 加防空能力时再扩字段 (target_layer_mask=AIR)。
static func create_archer_tower() -> RtsBuildingActor:
	return _create_from_kind(RtsBuildingConfig.KIND_ARCHER_TOWER)


# ========== 内部 ==========

## 通用工厂: 按 building_kind 查 RtsBuildingConfig, 实例化 RtsBuildingActor + 配齐属性。
static func _create_from_kind(building_kind: String) -> RtsBuildingActor:
	var stats := RtsBuildingConfig.get_stats(building_kind)

	var actor := RtsBuildingActor.new(building_kind)
	actor.set_display_name(stats.name)
	actor.footprint_size = stats.footprint_size
	actor.is_crystal_tower = stats.is_crystal_tower
	actor.production_period_ms = stats.production_period_ms
	actor.spawn_unit_kind = stats.spawn_unit_kind
	actor.spawn_unit_stance = stats.spawn_unit_stance

	# 建筑 collision_radius 用于"避免单位生成时与建筑物理重叠"的近邻判定;
	# footprint AABB 边长 / 2 是合理近似 (cell_size=32, 2×2 → 32 px 半径)。
	# 单位寻路通过 pathing map 绕开建筑 cells, 不需要严格 radius; 此处仅 spawn 距离参考。
	var cell_size: float = 32.0
	actor.collision_radius = max(stats.footprint_size.x, stats.footprint_size.y) * cell_size * 0.5

	# P2.8: 武器字段 (能攻击的塔) + tag / layer mask
	actor.atk_value = stats.atk
	actor.def_value = stats.def
	actor.attack_range_value = stats.attack_range
	actor.attack_speed_value = stats.attack_speed
	actor.target_layer_mask = stats.target_layer_mask
	actor.unit_tags = stats.unit_tags.duplicate()
	# 建筑永远在 GROUND 层 (M1 范围内不存在飞行建筑)
	actor.movement_layer = MovementLayer.Layer.GROUND

	# actor_id 留默认空串; _on_id_assigned 在 add_actor 后 sync 真 ID。
	actor.attribute_set = RtsBuildingAttributeSet.new()
	# max_hp 必须先于 hp: cross-attr clamp(hp <= max_hp) 在 set_hp_base 时按当前 max_hp 截。
	actor.attribute_set.set_max_hp_base(stats.max_hp)
	actor.attribute_set.set_hp_base(stats.hp)

	actor.ability_set = AbilitySet.new(actor.get_id(), actor.attribute_set)

	return actor
