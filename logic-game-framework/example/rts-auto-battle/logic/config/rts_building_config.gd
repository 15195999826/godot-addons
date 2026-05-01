## RtsBuildingConfig - RTS 建筑数值表 (P2.5)
##
## 与 RtsUnitClassConfig 同构: 提供 BuildingKind 字符串 → StatBlock (hp / footprint /
## production_period / spawn_unit_kind) 的查表方法。
##
## P2.5 落地 3 种建筑:
##   - crystal_tower : 水晶塔 (高 hp, 不生产; P2.6 落地胜负判定时用)
##   - barracks      : 兵营 (生产 melee, production_period_ms=4000)
##   - archer_tower  : 防御塔 (中 hp, 不生产; P2.8 加防空能力时再扩字段)
##
## 决策来源:
##   - architecture-baseline.md §4 (子类家族 — building_kind: String)
##   - phase-2-core-systems.md §P2.5 (建筑数值表)
class_name RtsBuildingConfig
extends RefCounted


# ========== 建筑 kind 常量 ==========

const KIND_CRYSTAL_TOWER: String = "crystal_tower"
const KIND_BARRACKS: String = "barracks"
const KIND_ARCHER_TOWER: String = "archer_tower"


## 单建筑数值条目
class StatBlock:
	extends RefCounted
	var name: String = ""
	## 最大血量
	var max_hp: float = 0.0
	## 起手血量 (默认 = max_hp)
	var hp: float = 0.0
	## footprint cell 尺寸 (cells × cells, AABB; (1,1) = 单 cell, (2,2) = 2×2 = 4 cells)
	var footprint_size: Vector2i = Vector2i(1, 1)
	## 是否水晶塔 (P2.6 胜负判定 — 任一阵营 crystal_tower hp=0 → 战斗结束)
	var is_crystal_tower: bool = false
	## 生产周期 (ms); <= 0 表示不生产 (crystal_tower / archer_tower)
	var production_period_ms: float = 0.0
	## 生产的单位兵种 (RtsUnitClassConfig.UnitClass; production_period_ms <= 0 时未使用)
	var spawn_unit_kind: int = -1
	## 生产单位的初始 stance (默认 AGGRESSIVE; P2.6 玩家命令可 override)
	var spawn_unit_stance: int = -1
	## P2.6 — 建造资源消耗 (PlaceBuildingCommand 扣减; team 资源不够 → 命令失败)。
	## crystal_tower 默认 0 (玩家不应该能花钱建主基地; smoke 起手布置 / 调方手动放); 兵营 100;
	## 防御塔 50。这些数字仅 M1 占位, P3 经济系统会重做。
	var cost: int = 0


const _CRYSTAL_TOWER_STATS := {
	"name": "Crystal Tower",
	"max_hp": 2000.0,
	"hp": 2000.0,
	"footprint_size": Vector2i(2, 2),
	"is_crystal_tower": true,
	"production_period_ms": 0.0,
	"spawn_unit_kind": -1,
	"cost": 0,
}

const _BARRACKS_STATS := {
	"name": "Barracks",
	"max_hp": 800.0,
	"hp": 800.0,
	"footprint_size": Vector2i(2, 2),
	"is_crystal_tower": false,
	# 4 秒一个 melee — smoke 30s 期望 ≥ 5 个 (理论 7-8, 留 buffer)
	"production_period_ms": 4000.0,
	# RtsUnitClassConfig.UnitClass.MELEE = 0
	"spawn_unit_kind": 0,
	"cost": 100,
}

const _ARCHER_TOWER_STATS := {
	"name": "Archer Tower",
	"max_hp": 600.0,
	"hp": 600.0,
	"footprint_size": Vector2i(1, 1),
	"is_crystal_tower": false,
	"production_period_ms": 0.0,
	"spawn_unit_kind": -1,
	"cost": 50,
}


## 取建筑数值。返回 StatBlock (每次新建副本)。
## 未知 kind → Log.assert_crash, 与 RtsUnitClassConfig.get_stats 一致。
static func get_stats(building_kind: String) -> StatBlock:
	var raw: Dictionary = {}
	match building_kind:
		KIND_CRYSTAL_TOWER:
			raw = _CRYSTAL_TOWER_STATS
		KIND_BARRACKS:
			raw = _BARRACKS_STATS
		KIND_ARCHER_TOWER:
			raw = _ARCHER_TOWER_STATS
		_:
			Log.assert_crash(false, "RtsBuildingConfig", "Unknown building_kind: %s" % building_kind)
	var block := StatBlock.new()
	block.name = raw["name"]
	block.max_hp = raw["max_hp"]
	block.hp = raw["hp"]
	block.footprint_size = raw["footprint_size"]
	block.is_crystal_tower = raw["is_crystal_tower"]
	block.production_period_ms = raw["production_period_ms"]
	block.spawn_unit_kind = raw["spawn_unit_kind"]
	block.cost = int(raw.get("cost", 0))
	# 默认 AGGRESSIVE stance (RtsUnitActor.Stance.AGGRESSIVE = 2);
	# 不直接引用枚举常量避开 cyclic dep, 数值形式传出, smoke / 调方按 RtsUnitActor.Stance 对照。
	block.spawn_unit_stance = 2
	return block
