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
