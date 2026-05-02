## RtsUnitClassConfig - RTS 兵种数值表
##
## M0 提供两个兵种: MELEE / RANGED, 数值 hardcode 在此, 按 task-plan README.md M0.3 段约定。
class_name RtsUnitClassConfig
extends RefCounted


## P2.8: FLYING_SCOUT 起开始接 AIR 层 (movement_layer = AIR + 自身 target_layer_mask = GROUND 攻地;
## 防空塔等单位 target_layer_mask = AIR 命中飞行)。
enum UnitClass { MELEE, RANGED, FLYING_SCOUT }


## 单兵种数值条目
class StatBlock:
	extends RefCounted
	var name: String = ""
	## 最大血量
	var max_hp: float = 0.0
	## 起手血量(默认 = max_hp)
	var hp: float = 0.0
	## 攻击力(走 LGF 减伤公式, 实际伤害 = max(1, atk - def))
	var atk: float = 0.0
	## 防御力
	var def: float = 0.0
	## 移动速度(像素/秒)
	var move_speed: float = 0.0
	## 攻击频率(次/秒), basic attack cooldown = 1 / attack_speed
	var attack_speed: float = 0.0
	## 攻击距离(像素), 平方比较
	var attack_range: float = 0.0
	## 圆形碰撞半径(像素), WC3 风连续 float (architecture-baseline.md §7 "小型 10-12")。
	## P1.2 最简 push-out 用此值; 必须 2r <= attack_range × RANGE_TOLERANCE 否则
	## melee 单位永远进不了 attack_range 内 (push-out 把它们推开过 atk_range)。
	var collision_radius: float = 0.0
	## P2.4 — 单位归类 tag (供敌方 target_priorities 匹配)。
	## 默认 melee→["melee","ground"], ranged→["ranged","ground"]; P2.8 飞行单位会有 ["flying","air"]。
	var unit_tags: Array[String] = []
	## P2.4 — 目标优先级表 [{tag: String, weight: float}, ...]; 高 weight 优先。
	## 默认 [] = 仅按距离选最近 (Phase 1 行为兼容); 特定单位类型可在 actor 上 override。
	var target_priorities: Array[Dictionary] = []
	## P2.8 — 移动层 (GROUND / AIR); 默认 GROUND, FLYING_* 类型覆盖为 AIR。
	## actor 走 nav 时 RtsPathfinding.find_path 会按此 layer 调 grid.is_passable_for_layer。
	var default_movement_layer: int = MovementLayer.Layer.GROUND
	## P2.8 — 攻击者武器命中的 layer mask (bit i = 1 表示能命中 layer i 的目标)。
	##   - melee 默认 MASK_GROUND (近战只打地面)
	##   - ranged 默认 MASK_BOTH (弓箭手兼顾防空)
	##   - flying_scout 默认 MASK_GROUND (空对地; 不互打飞行 — 简化, M1 仅 1 种 AIR 单位)
	## 0 = 不能攻击 (worker / non-combatant; M1 范围暂无)
	var target_layer_mask: int = MovementLayer.MASK_GROUND


const _MELEE_STATS := {
	"name": "Melee",
	"max_hp": 200.0,
	"hp": 200.0,
	"atk": 25.0,
	"def": 5.0,
	"move_speed": 80.0,
	"attack_speed": 1.0,
	"attack_range": 24.0,
	# 12px → 2r=24 = melee_attack_range (engagement at atk_range 时不被 push-out 推开)
	"collision_radius": 12.0,
	"unit_tags": ["melee", "ground"],
	"target_priorities": [],
	"default_movement_layer": MovementLayer.Layer.GROUND,
	# P2.8: melee 只能打地面 (近战不能跳起来打飞行)
	"target_layer_mask": MovementLayer.MASK_GROUND,
}

const _RANGED_STATS := {
	"name": "Ranged",
	"max_hp": 120.0,
	"hp": 120.0,
	"atk": 18.0,
	"def": 2.0,
	"move_speed": 70.0,
	"attack_speed": 0.8,
	"attack_range": 120.0,
	# 10px → 比 melee 更小, 更灵活; 远程不太可能因 push-out 引起 atk_range 边界问题。
	"collision_radius": 10.0,
	"unit_tags": ["ranged", "ground"],
	"target_priorities": [],
	"default_movement_layer": MovementLayer.Layer.GROUND,
	# P2.8: 弓箭手兼顾防空 (BOTH); P2.7 之前 RANGED 也是 BOTH 等价 (没 AIR 候选时 = GROUND only)
	"target_layer_mask": MovementLayer.MASK_BOTH,
}

## P2.8: 飞行侦察兵 — 走 AIR 层 (穿地面建筑 footprint), 攻地; 自己被防空塔 / RANGED 命中。
##
## 数值取舍:
##   - hp 中等 (90, 略低于 ranged 120) — 飞行机动性高, hp 不能太厚
##   - 移动速度 100 (高于 ranged 70) — 飞行优势
##   - 攻击距离 80 (中等; 比 ranged 短, 比 melee 长) — 给地面 anti-air 单位反击窗口
##   - target_layer_mask = MASK_GROUND (空对地, 不互打飞行 — 简化 M1)
##   - collision_radius 10 (与 ranged 同; AIR 层独立 steering, 与地面单位无 sep 干扰)
const _FLYING_SCOUT_STATS := {
	"name": "Flying Scout",
	"max_hp": 90.0,
	"hp": 90.0,
	"atk": 15.0,
	"def": 0.0,
	"move_speed": 100.0,
	"attack_speed": 0.8,
	"attack_range": 80.0,
	"collision_radius": 10.0,
	"unit_tags": ["flying", "air"],
	"target_priorities": [],
	"default_movement_layer": MovementLayer.Layer.AIR,
	"target_layer_mask": MovementLayer.MASK_GROUND,
}

## melee_attack_range 阈值, 用于 AC3 兵种行为断言:
##   - 所有 MELEE attack 距离 <= MELEE_RANGE_THRESHOLD * 1.05
##   - 所有 RANGED unit 至少 1 次 attack 距离 > MELEE_RANGE_THRESHOLD
const MELEE_RANGE_THRESHOLD: float = 24.0


## 取兵种数值。返回 StatBlock(每次新建副本, 调方可改 hp/max_hp 不影响 const)。
static func get_stats(unit_class: UnitClass) -> StatBlock:
	var raw: Dictionary = {}
	match unit_class:
		UnitClass.MELEE:
			raw = _MELEE_STATS
		UnitClass.RANGED:
			raw = _RANGED_STATS
		UnitClass.FLYING_SCOUT:
			raw = _FLYING_SCOUT_STATS
		_:
			Log.assert_crash(false, "RtsUnitClassConfig", "Unknown UnitClass: %d" % unit_class)
	var block := StatBlock.new()
	block.name = raw["name"]
	block.max_hp = raw["max_hp"]
	block.hp = raw["hp"]
	block.atk = raw["atk"]
	block.def = raw["def"]
	block.move_speed = raw["move_speed"]
	block.attack_speed = raw["attack_speed"]
	block.attack_range = raw["attack_range"]
	block.collision_radius = raw["collision_radius"]
	# P2.4: 把 raw dict 里的 Array 拷贝到 typed Array 字段, 避免 actor 之间共享同一可变引用。
	var raw_tags: Array = raw.get("unit_tags", []) as Array
	var tags: Array[String] = []
	for tag in raw_tags:
		tags.append(str(tag))
	block.unit_tags = tags
	var raw_prios: Array = raw.get("target_priorities", []) as Array
	var prios: Array[Dictionary] = []
	for entry in raw_prios:
		prios.append((entry as Dictionary).duplicate())
	block.target_priorities = prios
	# P2.8: layer / mask
	block.default_movement_layer = int(raw.get("default_movement_layer", MovementLayer.Layer.GROUND))
	block.target_layer_mask = int(raw.get("target_layer_mask", MovementLayer.MASK_GROUND))
	return block


static func to_string_name(unit_class: UnitClass) -> String:
	match unit_class:
		UnitClass.MELEE:
			return "melee"
		UnitClass.RANGED:
			return "ranged"
		UnitClass.FLYING_SCOUT:
			return "flying_scout"
	return "unknown"
