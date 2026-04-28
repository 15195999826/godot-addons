## CollisionProfile - 环境物碰撞物理参数
##
## 描述一个 EnvironmentActor 在被推 / 被撞时的物理表现。
## 不进 attribute_set: 这些字段不参与 buff/modifier 系统, 是结构化数据。
##
## 字段:
##   - damage_taken_on_blocked_push:
##       当我作为"被撞物" (推动者撞到我后停下) 时, 我自己受多少碰撞伤害。
##       indestructible 物体设 0。
##   - damage_dealt_to_pusher:
##       当我作为"被撞物"时, 撞我的人受多少碰撞伤害。
##       软物 (草丛) 可设 0; 硬物 (石墙) 设较高。
##   - pushable:
##       是否可被推开。false = 被撞时我自己不动 (墙、巨石等)。
##   - blocks_path:
##       是否阻挡寻路。false = 单位可走过 (草丛挡视线但不挡路)。
class_name CollisionProfile
extends RefCounted


var damage_taken_on_blocked_push: float = 1.0
var damage_dealt_to_pusher: float = 1.0
var pushable: bool = false
var blocks_path: bool = true
