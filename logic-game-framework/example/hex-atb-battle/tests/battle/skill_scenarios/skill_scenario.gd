## SkillScenario - 单技能逻辑断言场景基类
##
## 子类放在 `addons/logic-game-framework/example/hex-atb-battle/tests/battle/skill_scenarios/*.gd`，
## 自动被 runner 扫描执行。
##
## 一个 scenario 负责:
##   1. 声明场景(caster/allies/enemies/地图/目标)
##   2. 声明要装备的 ActiveUse 技能(+ 可选被动)
##   3. 在 assert_replay 里对产出的 replay 断言
##
## scenario 只做**逻辑验证**（伤害数值、事件序列、buff 生命周期）。
## 表演/视觉验证不在这一层，属于 SkillPreview 工具。
class_name SkillScenario
extends RefCounted


## 显示名（日志输出用）
func get_name() -> String:
	return get_script().resource_path.get_file().get_basename()


## 返回场景配置，格式见 HexBattleSkillScenarioHarness.run_with_config 约定。
##
## 最小示例:
## [codeblock]
## return {
##     "map": {"rows": 3, "cols": 3},
##     "caster":  {"class": "WARRIOR", "pos": [0, 0]},
##     "enemies": [{"class": "WARRIOR", "pos": [1, 0], "hp": 1000}],
##     "target":  {"mode": "auto"},
## }
## [/codeblock]
func get_scene_config() -> Dictionary:
	return {}


## 返回 caster 要施放的 ActiveUse 技能 config。
## 若 scenario override 了 get_actions()，本方法可以不实现（返回 null）。
func get_active_skill() -> AbilityConfig:
	return null


## 返回 action 序列，描述"谁施放什么技能打谁"。
##
## 默认实现:基于 get_active_skill() 派生单步 action(caster 自动施法最近敌人)。
## Override 用于:
##   - 被动技能测试(让 enemy 先打 caster 触发反伤/尸爆)
##   - 多步协同(ally 先 buff,然后 caster 攻击)
##   - 跨队施法(诡异场景)
##
## action 格式见 HexBattleSkillScenarioHarness.run_with_actions 约定。
func get_actions() -> Array[Dictionary]:
	var active := get_active_skill()
	if active == null:
		return []
	return [{"caster": "caster", "skill": active, "target": "auto"}]


## 返回给 caster 额外挂的被动技能（可空）
func get_passives() -> Array[AbilityConfig]:
	return []


## §Phase G — 进 tick 循环前的可选 setup hook (装备 scenarios 等需要在 actor 创建后
## 进行的 ItemSystem 操作: 注册 player bag / actor equipment container, 装备 item 触发
## grant_ability 等)。
##
## 调用时机: harness 已创建 caster/ally/enemy 并 grant get_passives(), 但还未开始 tick。
## 因此 setup_battle 内 grant 的 ability 在第 1 帧就能 fire,与 caster_passives 等价。
##
## 默认 no-op; 装备 scenarios override 并返回 false 表示 setup 失败 (test fail)。
## 返回 true 表示 setup 成功, harness 继续 tick 循环。
##
## scenario_assert_context 在 assert_replay 时可以读 result 内嵌的 setup_errors。
func setup_battle(
	_battle: Object,
	_caster: Object,
	_ally_actors: Array,
	_enemy_actors: Array,
	_setup_errors: Array,
) -> bool:
	return true


## 最大 tick 数（防死循环）。超时计 FAIL。
func get_max_ticks() -> int:
	return 500


## 最小 tick 数。idle 判定在 tick_count >= min_ticks 之前禁止收敛, 强制 battle 至少跑 N 帧。
## 用途: Phase C HP regen / Demon Form / 其他依赖周期 timeline 的 scenario, 让 intrinsic
## periodic tick 有时间累积观察。普通 scenario 不需要 override (默认 0 = 让 harness 自然判定 idle).
func get_min_ticks() -> int:
	return 0


## 断言 replay 与场景状态。用 ctx 提供的工具做断言，任一失败 ctx.fail(...)
func assert_replay(_ctx: ScenarioAssertContext) -> void:
	push_error("[SkillScenario] assert_replay not implemented in %s" % get_name())
