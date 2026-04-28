## StoneWall - 石墙 (M1 唯一地形, 验证 EnvironmentActor 子系统)
##
## 物理特征:
##   - 不可破坏 (hp = INF, damage_taken=0): 受伤事件能正常 push, 但 hp 永远不会到 0
##   - 不可推动 (pushable = false)
##   - 阻挡寻路 (blocks_path = true)
##   - 撞墙者受 1 点物理伤害
##
## 用法 (scenario / battle setup):
##   var wall := HexBattleStoneWall.create()
##   battle.add_actor(wall)
##   wall.hex_position = HexCoord.new(2, 0)
##   battle.grid.place_occupant(wall.hex_position, wall)
##
## indestructible 用数据表达 (hp=INF + damage_taken=0), 不在 code path 里加早退分支。
class_name HexBattleStoneWall


const KIND := "stone_wall"


## 工厂函数: 创建一个完整配置好的石墙实例 (未放置到 grid)
static func create() -> EnvironmentActor:
	var profile := CollisionProfile.new()
	profile.damage_taken_on_blocked_push = 0.0
	profile.damage_dealt_to_pusher = 1.0
	profile.pushable = false
	profile.blocks_path = true

	var wall := EnvironmentActor.new(KIND, profile)
	# hp = INF: 即使 push damage 命中也不会死亡; 数据驱动 indestructible
	wall.attribute_set.set_max_hp_base(INF)
	wall.attribute_set.set_hp_base(INF)
	wall.set_display_name("石墙")
	return wall
