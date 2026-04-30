## RtsUnitClassConfig - RTS 兵种数值表
##
## M0 提供两个兵种: MELEE / RANGED, 数值 hardcode 在此, 按 task-plan README.md M0.3 段约定。
class_name RtsUnitClassConfig
extends RefCounted


enum UnitClass { MELEE, RANGED }


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


const _MELEE_STATS := {
	"name": "Melee",
	"max_hp": 200.0,
	"hp": 200.0,
	"atk": 25.0,
	"def": 5.0,
	"move_speed": 80.0,
	"attack_speed": 1.0,
	"attack_range": 24.0,
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
	return block


static func to_string_name(unit_class: UnitClass) -> String:
	match unit_class:
		UnitClass.MELEE:
			return "melee"
		UnitClass.RANGED:
			return "ranged"
	return "unknown"
