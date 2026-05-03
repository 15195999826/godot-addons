## RtsPassabilityClassRegistry - Passability class 注册查询单例
##
## 一个 RtsWorldGameplayInstance 持有一个 registry; procedure 启动时按固定顺序注册
## (default 先 → air 后), bit_index 从 0 开始自动递增。
##
## 0 A.D. 对照: ICmpPathfinder.h 的 GetPassabilityClass / GetPassabilityClasses /
## GetMaximumClearance.
##
## Determinism: register 顺序固化是 replay bit-identical 的关键 (R5 决策); 从 mask
## 数字 (0x1 / 0x2 / ...) 推算 NavcellGrid 布局, 顺序换会让所有 mask 数字漂。
##
## SPECIAL_PASS_CLASS_INDEX (15) 是给 in-place 计算保留的 bit, 普通 class 注册不
## 占用这一位; PASS_CLASS_BITS - 1 = 15 上限保证 _next_bit < 15 不撞 special。
class_name RtsPassabilityClassRegistry
extends RefCounted


# ========== 常量 ==========

const PASS_CLASS_BITS: int = 16
const SPECIAL_PASS_CLASS_INDEX: int = 15


# ========== 字段 ==========

var _classes: Array[RtsPassabilityClassConfig] = []
var _by_name: Dictionary = {}
var _next_bit: int = 0


# ========== 注册 / 查询 ==========

## 注册一个 class; bit_index 自动分配; 重复 class_name_id 时 assert_crash。
##
## 注册顺序固化是 replay determinism 关键 — procedure 内永远 default 先 air 后。
func register(cfg: RtsPassabilityClassConfig) -> void:
	Log.assert_crash(_next_bit < PASS_CLASS_BITS - 1, "RtsPassabilityClassRegistry", "registry full (next_bit=%d)" % _next_bit)
	Log.assert_crash(not _by_name.has(cfg.class_name_id), "RtsPassabilityClassRegistry", "duplicate class %s" % cfg.class_name_id)
	cfg.bit_index = _next_bit
	_next_bit += 1
	_classes.append(cfg)
	_by_name[cfg.class_name_id] = cfg


## 按 name 查 config; 未注册返 null。
##
## 注: RefCounted / Object 已有内建 get_class() 返回 String 类名, 此处用 get_pass_class()
## 命名避开签名冲突。
func get_pass_class(name_id: String) -> RtsPassabilityClassConfig:
	return _by_name.get(name_id, null)


## 按 name 查位掩码 (1 << bit_index); 未注册返 0。
func get_mask(name_id: String) -> int:
	var cfg: RtsPassabilityClassConfig = _by_name.get(name_id, null)
	return 1 << cfg.bit_index if cfg != null else 0


## 所有 class 中最大 clearance, 给 short pathfinder buffer 用。
func max_clearance() -> float:
	var m: float = 0.0
	for c in _classes:
		m = maxf(m, c.clearance)
	return m


## 已注册 class 数量。
func size() -> int:
	return _classes.size()


## 全部已注册 class (按注册序; 给 ObstructionManager.rasterize_if_dirty 遍历用)。
##
## 返 reference (调方不应修改); 注册顺序固化是 replay determinism 关键 (R5 决策)。
func get_classes() -> Array[RtsPassabilityClassConfig]:
	return _classes


## 按 mask (1 << bit_index) 反查 class; 未匹配返 null (M3 spec §M3.1 步骤 2 要求)。
func get_class_by_mask(mask: int) -> RtsPassabilityClassConfig:
	for c in _classes:
		if (1 << c.bit_index) == mask:
			return c
	return null
