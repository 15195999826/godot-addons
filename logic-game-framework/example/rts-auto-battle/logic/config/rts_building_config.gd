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


# ========== 内部常量 ==========

## Cell size (px), 跟 RtsBattleGrid.DEFAULT_CELL_SIZE 对齐 — M0.3 fallback 用.
## 当 raw config 没显式 obstruction_size 时, 从旧 footprint_size: Vector2i × 此常量 派生.
## 不直接引 RtsBattleGrid.DEFAULT_CELL_SIZE 避免 config → grid 反向依赖; 数值已在 §RtsBattleGrid 钉死,
## 双源漂移风险低 (RTS 例子从未改过 cell_size).
const _CELL_SIZE_FALLBACK: float = 32.0


## 单建筑数值条目
class StatBlock:
	extends RefCounted
	var name: String = ""
	## 最大血量
	var max_hp: float = 0.0
	## 起手血量 (默认 = max_hp)
	var hp: float = 0.0
	## footprint cell 尺寸 (cells × cells, AABB; (1,1) = 单 cell, (2,2) = 2×2 = 4 cells)。
	##
	## **M0.3 注**: 此字段保留 (向后兼容现有 RtsBuildingActor.get_footprint_cells 算法 + 全部 smoke 数字);
	## M2 引入 ObstructionManager 后由 obstruction_size (Vector2 px) 替换并删除。
	## 新引入的 obstruction_size 默认从此字段 × cell_size 派生 (M0.3 fallback)。
	var footprint_size: Vector2i = Vector2i(1, 1)
	## M0.3 — Obstruction shape OBB 全宽全高 (px). 用于 RtsObstructionShapeStatic.{width, height}.
	##
	## 默认 ZERO; raw config 没显式时 fallback = `Vector2(footprint_size) × _CELL_SIZE_FALLBACK`.
	## 三个建筑 (crystal_tower / barracks / archer_tower) 当前均走 fallback (M0.3 不配置, 保持 0 漂移).
	var obstruction_size: Vector2 = Vector2.ZERO
	## M0.3 — Obstruction shape 几何中心相对 actor.position_2d 的偏移 (px). 默认 ZERO.
	##
	## ZERO = sprite 锚点 = 寻路占地中心 (M0 默认行为, F1 决策 A); 非零让 sprite 视觉中心和寻路占地中心错位
	## (M0.7 步骤 1 新 smoke 故意把 obstruction_offset 设非零验证 cells 跟着 obstruction.center 走).
	var obstruction_offset: Vector2 = Vector2.ZERO
	## M0.3 — Footprint UI 形状类型 (对照 RtsFootprintShape.Type: 0=CIRCLE, 1=SQUARE). 默认 0 = CIRCLE.
	var footprint_shape_type: int = 0
	## M0.3 — UI selection footprint 尺寸 (px). 注意**新名**: 不叫 footprint_size (跟旧 Vector2i 字段冲突).
	##
	## 语义 (跟 RtsFootprintShape.size 对应):
	##   - CIRCLE: x = 半径; y 不用
	##   - SQUARE: x = 半宽; y = 半高
	##
	## 默认 ZERO; raw config 没显式时 fallback = obstruction 外接圆半径 = `max(w, h) * 0.5`.
	var selection_footprint_size: Vector2 = Vector2.ZERO
	## 是否水晶塔 (P2.6 胜负判定 — 任一阵营 crystal_tower hp=0 → 战斗结束)
	var is_crystal_tower: bool = false
	## M2.1 Phase C — 是否 worker drop-off 点 (RtsReturnAndDropActivity 找己方最近 is_drop_off 建筑)。
	## crystal_tower 起手 true (双方起手就有 ct → 经济闭环不需要新加 building_kind);
	## Phase D 若加 town_hall / supply_depot 也设 true。
	var is_drop_off: bool = false
	## 生产周期 (ms); <= 0 表示不生产 (crystal_tower / archer_tower)
	var production_period_ms: float = 0.0
	## 生产的单位兵种 (RtsUnitClassConfig.UnitClass; production_period_ms <= 0 时未使用)
	var spawn_unit_kind: int = -1
	## 生产单位的初始 stance (默认 AGGRESSIVE; P2.6 玩家命令可 override)
	var spawn_unit_stance: int = -1
	## M2.1 Phase A — 建造资源消耗 (PlaceBuildingCommand 扣减; team 任一资源不够 → 命令失败)。
	## key = 资源种类 ("gold" / "wood" — RtsTeamConfig 同口径); value = 需求量。
	## 缺 key / value=0 视为不消耗该资源。crystal_tower 起手 {} (不可建造来源 = smoke / 调方);
	## Phase D finalized: barracks {"gold": 80, "wood": 50} (gold-rich 偏 melee 推 ct);
	## archer_tower {"gold": 60, "wood": 100} (wood-rich 偏防空)。
	var cost: Dictionary[String, int] = {}

	# ========== P2.8: 武器字段 (供能攻击的塔) ==========
	## 攻击力 (0 = 不攻击; 兵营 / 水晶塔 都 0; archer_tower = 防空 atk)
	var atk: float = 0.0
	## 防御力 (减伤公式中用; M1 范围内塔受击不走 def 减伤但保留字段对齐)
	var def: float = 0.0
	## 攻击距离 (像素)
	var attack_range: float = 0.0
	## 攻击频率 (次/秒)
	var attack_speed: float = 0.0
	## P2.8 — 武器命中 layer mask (bit i = 1 表示能命中 layer i 的目标)。
	##   - barracks / crystal_tower: MASK_NONE (0) 不参战
	##   - archer_tower: MASK_AIR (2) anti-air 防空塔
	## 工厂从此字段写入 actor.target_layer_mask。
	var target_layer_mask: int = MovementLayer.MASK_NONE
	## P2.8 — 建筑归类 tag (供敌方 target_priorities 匹配 / debug)。
	##   - barracks: ["building", "barracks"]
	##   - archer_tower: ["building", "tower", "anti_air"]
	##   - crystal_tower: ["building", "crystal_tower", "priority_target"]
	var unit_tags: Array[String] = []


const _CRYSTAL_TOWER_STATS := {
	"name": "Crystal Tower",
	"max_hp": 2000.0,
	"hp": 2000.0,
	"footprint_size": Vector2i(2, 2),
	"is_crystal_tower": true,
	# M2.1 Phase C: ct 兼任 worker drop-off (双方起手就有 ct → harvest 闭环不需要新加 building_kind)
	"is_drop_off": true,
	"production_period_ms": 0.0,
	"spawn_unit_kind": -1,
	# 不可建造来源 — 起手 / 调方手动放, PlaceBuildingCommand 走 cost 校验本字段会被遍历
	"cost": {},
	# P2.8: 不参战 — 玩家保护对象, 没武器
	"atk": 0.0,
	"def": 0.0,
	"attack_range": 0.0,
	"attack_speed": 0.0,
	"target_layer_mask": MovementLayer.MASK_NONE,
	"unit_tags": ["building", "crystal_tower", "priority_target"],
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
	# Phase D finalized: gold-rich 偏 barracks 推 melee 直 ct
	"cost": {"gold": 80, "wood": 50},
	# P2.8: 兵营不参战 — 只生产, 不打人
	"atk": 0.0,
	"def": 0.0,
	"attack_range": 0.0,
	"attack_speed": 0.0,
	"target_layer_mask": MovementLayer.MASK_NONE,
	"unit_tags": ["building", "barracks"],
}

## P2.8: archer_tower 升级为防空塔 (target_layer_mask = MASK_AIR, 只打飞行)。
##   - atk 25 比 ranged unit (18) 高 — 塔单点输出强但不能移动
##   - attack_range 140 比 ranged (120) 略远 — 塔需要先发优势, 让飞行单位被迫绕飞
##   - attack_speed 0.7 略慢 — 塔单点强但开火节奏慢
##   - target_layer_mask = MASK_AIR — 只打飞行, 地面单位即使来攻也不还手
const _ARCHER_TOWER_STATS := {
	"name": "Archer Tower",
	"max_hp": 600.0,
	"hp": 600.0,
	"footprint_size": Vector2i(1, 1),
	"is_crystal_tower": false,
	"production_period_ms": 0.0,
	"spawn_unit_kind": -1,
	# Phase D finalized: wood-rich 偏防空 (anti-air)
	"cost": {"gold": 60, "wood": 100},
	"atk": 25.0,
	"def": 0.0,
	"attack_range": 140.0,
	"attack_speed": 0.7,
	"target_layer_mask": MovementLayer.MASK_AIR,
	"unit_tags": ["building", "tower", "anti_air"],
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
	block.is_drop_off = bool(raw.get("is_drop_off", false))
	block.production_period_ms = raw["production_period_ms"]
	block.spawn_unit_kind = raw["spawn_unit_kind"]
	block.cost = _copy_resource_dict(raw.get("cost", null))
	# P2.8: 武器 / mask / tags
	block.atk = float(raw.get("atk", 0.0))
	block.def = float(raw.get("def", 0.0))
	block.attack_range = float(raw.get("attack_range", 0.0))
	block.attack_speed = float(raw.get("attack_speed", 0.0))
	block.target_layer_mask = int(raw.get("target_layer_mask", MovementLayer.MASK_NONE))
	var raw_tags: Array = raw.get("unit_tags", []) as Array
	var tags: Array[String] = []
	for tag in raw_tags:
		tags.append(str(tag))
	block.unit_tags = tags
	# 默认 AGGRESSIVE stance (RtsUnitActor.Stance.AGGRESSIVE = 2);
	# 不直接引用枚举常量避开 cyclic dep, 数值形式传出, smoke / 调方按 RtsUnitActor.Stance 对照。
	block.spawn_unit_stance = 2
	# M0.3 — Obstruction / footprint shape 字段 (raw 未显式时 fallback 派生).
	# 当前 3 个建筑 raw 都不写新字段, 全走 fallback, 保 0 漂移 + 向后兼容现有 smoke.
	if raw.has("obstruction_size"):
		block.obstruction_size = raw["obstruction_size"]
	else:
		block.obstruction_size = Vector2(block.footprint_size) * _CELL_SIZE_FALLBACK
	if raw.has("obstruction_offset"):
		block.obstruction_offset = raw["obstruction_offset"]
	if raw.has("footprint_shape_type"):
		block.footprint_shape_type = int(raw["footprint_shape_type"])
	if raw.has("selection_footprint_size"):
		block.selection_footprint_size = raw["selection_footprint_size"]
	else:
		# default = obstruction 外接圆半径 (CIRCLE.size.x = 半径).
		var max_dim: float = maxf(block.obstruction_size.x, block.obstruction_size.y)
		block.selection_footprint_size = Vector2(max_dim * 0.5, 0.0)
	return block


## raw const dict 是普通 Dictionary, 转 Dictionary[String, int] typed 副本 (避免外层共享引用)。
## 缺 / null → 空 typed dict, 与 cost 默认 {} 同语义 (validate 遍历空就 always pass)。
static func _copy_resource_dict(raw_value: Variant) -> Dictionary[String, int]:
	var typed: Dictionary[String, int] = {}
	if raw_value == null:
		return typed
	var src: Dictionary = raw_value as Dictionary
	for key in src:
		typed[str(key)] = int(src[key])
	return typed
