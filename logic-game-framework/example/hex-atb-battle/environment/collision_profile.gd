## CollisionProfile - 被推 / 被撞时的结算数据
##
## 描述任何"占用格子的实体" (HexBattleActor) 在被推 / 被撞时的物理表现。
## 不是物理引擎: 没有质量 / 力 / 动量, 只是一组结算字段。
## 不进 attribute_set: 这些字段不参与 buff/modifier 系统, 是结构化数据。
##
## 视角: 字段都从"被撞物"的视角描述。
##   - damage_taken_on_blocked_push:
##       当我作为"被撞物"时, 我自己受多少撞击伤害。
##       indestructible 物体设 0。
##   - damage_dealt_to_pusher:
##       当我作为"被撞物"时, 撞我的人 (即被推过来的 actor / 推方) 受多少撞击伤害。
##       软物 (草丛) 可设 0; 硬物 (石墙) 设较高。
##   - pushable:
##       是否可被推开。false = 被撞时我自己不动 (墙、巨石等)。
##       Knockback Punch V1 不消费此字段 (target 默认就停在 blocker 前一格);
##       未来"链式推" / "wind torrent" 等多 N 推会用它判断"是否带动 blocker"。
##   - blocks_path:
##       是否阻挡寻路。false = 单位可走过 (草丛挡视线但不挡路)。
class_name CollisionProfile
extends RefCounted


var damage_taken_on_blocked_push: float = 1.0
var damage_dealt_to_pusher: float = 1.0
var pushable: bool = false
var blocks_path: bool = true


## 角色默认 profile: 互撞双方各受 1 点; 角色阻挡格子。
## CharacterActor 在 _init 末尾自动应用此默认。
static func default_character() -> CollisionProfile:
	var p := CollisionProfile.new()
	p.damage_taken_on_blocked_push = 1.0
	p.damage_dealt_to_pusher = 1.0
	p.pushable = true
	p.blocks_path = true
	return p


## 地图边界默认 profile: 撞墙者受 1 点, 边界本身无 hp 概念。
## PushAction 撞 edge 时按此 profile 的 damage_dealt_to_pusher 给 target 结算。
static func default_wall() -> CollisionProfile:
	var p := CollisionProfile.new()
	p.damage_taken_on_blocked_push = 0.0
	p.damage_dealt_to_pusher = 1.0
	p.pushable = false
	p.blocks_path = true
	return p
