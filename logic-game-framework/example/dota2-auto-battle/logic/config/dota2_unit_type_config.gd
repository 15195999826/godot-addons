## Dota2UnitTypeConfig - lane creep 兵种静态数值表
##
## actor-attributes.md「Static Config Vs Runtime Attributes」：type config 是静态共享数据，
## 定义某 actor 种类的初始值；AttributeSet 是 runtime 可变数据（buff/aura/item 改它）。
## 此处只放静态初值 + 不可被 modifier 改的常量（collision_radius / 几何）。
##
## M1 两种 lane creep：近战 melee、远程 ranged。数值 hardcode 在此（参照 rts
## RtsUnitClassConfig 风格）。Hero/Tower/Building 不在 M1，但加新 UnitType 不破家族形状。
class_name Dota2UnitTypeConfig
extends RefCounted


enum UnitType { LANE_MELEE, LANE_RANGED }


## 单兵种静态数值条目（每次 get_stats 返回新副本，调方改 hp/max_hp 不污染 const）。
class StatBlock:
	extends RefCounted
	var display_name: String = ""
	var max_hp: float = 0.0
	var hp: float = 0.0
	## 攻击伤害（M1 简化：直接掉血，无 armor 公式 —— 见 actor-attributes.md armor 待定）。
	var attack_damage: float = 0.0
	## 像素；与目标距离 <= attack_range 才允许基础攻击。
	var attack_range: float = 0.0
	## 基础攻击间隔（毫秒）= Ability 冷却时长；attack point 在间隔内由 Timeline 驱动。
	var attack_interval_ms: float = 0.0
	## 像素/秒；交给 movement adapter / sim-nav 消费。
	var move_speed: float = 0.0
	## 像素；aggro 扫描半径，决定 controller 何时从 march 切 attack。
	var aggro_range: float = 0.0
	## 圆形碰撞半径（像素）；交给 sim-nav 适配器作为 unit clearance（硬阻挡）。
	var collision_radius: float = 0.0


const _LANE_MELEE := {
	"display_name": "Lane Melee Creep",
	"max_hp": 220.0,
	"hp": 220.0,
	"attack_damage": 16.0,
	"attack_range": 44.0,
	"attack_interval_ms": 900.0,
	"move_speed": 95.0,
	"aggro_range": 340.0,
	"collision_radius": 13.0,
}

const _LANE_RANGED := {
	"display_name": "Lane Ranged Creep",
	"max_hp": 140.0,
	"hp": 140.0,
	"attack_damage": 20.0,
	"attack_range": 130.0,
	"attack_interval_ms": 1100.0,
	"move_speed": 90.0,
	"aggro_range": 360.0,
	"collision_radius": 11.0,
}


static func get_stats(unit_type: UnitType) -> StatBlock:
	var raw: Dictionary = {}
	match unit_type:
		UnitType.LANE_MELEE:
			raw = _LANE_MELEE
		UnitType.LANE_RANGED:
			raw = _LANE_RANGED
		_:
			Log.assert_crash(false, "Dota2UnitTypeConfig", "Unknown UnitType: %d" % unit_type)
	var block := StatBlock.new()
	block.display_name = raw["display_name"]
	block.max_hp = raw["max_hp"]
	block.hp = raw["hp"]
	block.attack_damage = raw["attack_damage"]
	block.attack_range = raw["attack_range"]
	block.attack_interval_ms = raw["attack_interval_ms"]
	block.move_speed = raw["move_speed"]
	block.aggro_range = raw["aggro_range"]
	block.collision_radius = raw["collision_radius"]
	return block


static func to_string_name(unit_type: UnitType) -> String:
	match unit_type:
		UnitType.LANE_MELEE:
			return "lane_melee"
		UnitType.LANE_RANGED:
			return "lane_ranged"
	return "unknown"
