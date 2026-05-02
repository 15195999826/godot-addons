## RtsWeaponConfig - 武器层 mask 常量与查询 (P2.8)
##
## 武器 = (atk, def, attack_range, attack_speed, target_layer_mask) 五元组的统称。
## P2.8 范围内不为武器单独建实例 — 武器属性直接挂在 attacker actor 上 (RtsUnitActor /
## RtsBuildingActor 的 atk/attack_range/attack_speed/target_layer_mask 字段, 由 unit_class /
## building_kind 配置注入)。本文件提供:
##   - target_layer_mask 的 bitmask 常量 (与 MovementLayer.MASK_* 同源)
##   - 命中校验 helper (matches / build_from_layers)
##
## RtsAutoTargetSystem / RtsBasicAttackAction 通过此类做 attacker → candidate 的 layer 命中过滤。
##
## 决策来源: phase-2-core-systems.md §P2.8 (target_layer_mask)
class_name RtsWeaponConfig
extends RefCounted


# ========== Mask 常量 (与 MovementLayer 同源, 方便外部不绕路 import) ==========

const MASK_NONE: int = MovementLayer.MASK_NONE
const MASK_GROUND: int = MovementLayer.MASK_GROUND
const MASK_AIR: int = MovementLayer.MASK_AIR
const MASK_BOTH: int = MovementLayer.MASK_BOTH


# ========== 查询 ==========

## attacker.target_layer_mask 是否覆盖 candidate.movement_layer。
##
## 例: mask=MASK_AIR (2), candidate.movement_layer=Layer.AIR (1) → matches=true
##     mask=MASK_GROUND (1), candidate.movement_layer=Layer.AIR → matches=false
static func matches(mask: int, candidate_layer: int) -> bool:
	return MovementLayer.mask_matches(mask, candidate_layer)


## 给定 attacker 是否能命中 target (按 layer mask 过滤)。
##
## attacker.target_layer_mask == 0 (不能攻击) → 永远 false。
## target == null / dead → false。
static func can_hit(attacker: RtsBattleActor, target: RtsBattleActor) -> bool:
	if attacker == null or target == null:
		return false
	if target.is_dead():
		return false
	if attacker.target_layer_mask == MASK_NONE:
		return false
	return matches(attacker.target_layer_mask, target.movement_layer)


## 多 layer 列表 → bitmask (Array[int] 形式)。
##
## 例: build_mask([MovementLayer.Layer.GROUND, MovementLayer.Layer.AIR]) = 3
static func build_mask(layers: Array) -> int:
	var mask: int = 0
	for l in layers:
		mask |= (1 << int(l))
	return mask
