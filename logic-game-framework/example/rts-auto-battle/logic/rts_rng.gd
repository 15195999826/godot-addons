## RtsRng - RTS 全局确定性随机源(autoload)
##
## 决策来源:
##   - D3-A (Sim = 30Hz fixed-tick + 全局 RNG with seed)
##   - phase-1-foundation.md P1.7 (Fixed tick + light determinism)
##   - architecture-baseline.md §6 (RtsRecording.world_snapshot.rng_seed)
##
## 职责:
##   - 持单一 RandomNumberGenerator 实例
##   - 暴露 randf / randi / randf_range / randi_range 给 RTS 例子用
##   - set_seed 在 procedure 起始重置, 让同 seed 同序列 RNG 调用 → 同结果
##
## **使用约定**:
##   - RTS 例子代码内**不要直接调** `randf()` / `randi()` / `RandomNumberGenerator.new()`,
##     否则会脱离 seed 控制, 破坏 light determinism。
##   - LGF core / stdlib 内部的 randf 不在此约束内(由 LGF 自己保证 deterministic)。
##   - GD script `randf()` (全局) 的 seed 不可控, 不要混用。
##
## Phase 1 light determinism 验收: 同 seed → 同 winner + 同 total_ticks ± 1
## Phase 2 P2.6+P2.7 完整流式 replay 后, 验证 bit-identical event_timeline。
extends Node


# ========== 字段 ==========

var _rng: RandomNumberGenerator = null

## 当前种子(只读, 给 procedure 在 world_snapshot 写录像时回读)
var _current_seed: int = 0


# ========== 生命周期 ==========

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	# 默认 seed = 0(让人可观察的起手状态); 调方在 procedure 起始通过 set_seed 重置。
	set_seed(0)


# ========== Seed 控制 ==========

## 设置种子并立即重置内部 RNG 状态(让同 seed 后续调用产出同序列)。
func set_seed(seed_value: int) -> void:
	_current_seed = seed_value
	if _rng == null:
		_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	_rng.state = 0


## 当前 seed(给 procedure 写 world_snapshot 用)
func get_current_seed() -> int:
	return _current_seed


# ========== 随机 API (与 GDScript 全局 randf/randi 同签名) ==========

func randf() -> float:
	if _rng == null:
		set_seed(0)
	return _rng.randf()


func randi() -> int:
	if _rng == null:
		set_seed(0)
	return _rng.randi()


func randf_range(min_v: float, max_v: float) -> float:
	if _rng == null:
		set_seed(0)
	return _rng.randf_range(min_v, max_v)


func randi_range(min_v: int, max_v: int) -> int:
	if _rng == null:
		set_seed(0)
	return _rng.randi_range(min_v, max_v)
