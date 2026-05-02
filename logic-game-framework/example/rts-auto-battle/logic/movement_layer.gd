## MovementLayer - 单位移动层枚举
##
## D3-D 锁定决策: layer-based 多层(GROUND / AIR), 武器 target_layer_mask 决定能否打到。
## Phase 1 仅 GROUND 单位; AIR 接口预留, 完整功能在 Phase 2 P2.8。
##
## 加新 layer (WATER / UNDERGROUND) 时直接扩枚举 + bitmask, 不动 RtsBattleActor 字段结构
## (见 architecture-baseline.md §12.2)。
class_name MovementLayer
extends RefCounted


enum Layer {
	GROUND = 0,
	AIR = 1,
}


## 默认 layer
const DEFAULT: int = Layer.GROUND


# ========== P2.8: target_layer_mask bitmask ==========

## 武器/攻击者用 target_layer_mask 描述能命中哪些 layer。
## 与 Layer enum 平行: bit i = 1 表示能命中 Layer i (1 << Layer.GROUND = 1, 1 << Layer.AIR = 2)。
##
## 例:
##   - 普通近战 = MASK_GROUND (=1) — 只能打地面
##   - 普通弓兵 = MASK_BOTH (=3) — 地面 + 防空
##   - 防空塔   = MASK_AIR (=2) — 只能打飞行
##   - 不能攻击的建筑 (兵营 / 水晶塔) = MASK_NONE (=0)
const MASK_NONE: int = 0
const MASK_GROUND: int = 1   # 1 << Layer.GROUND
const MASK_AIR: int = 2      # 1 << Layer.AIR
const MASK_BOTH: int = 3     # MASK_GROUND | MASK_AIR


## 把 layer 转成 bitmask (1 << layer)。
static func mask_for_layer(layer: int) -> int:
	return 1 << layer


## mask 是否包含给定 layer (mover.target_layer_mask 是否能命中 candidate.movement_layer)。
static func mask_matches(mask: int, layer: int) -> bool:
	return (mask & (1 << layer)) != 0
