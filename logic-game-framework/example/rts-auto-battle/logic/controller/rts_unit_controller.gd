## RtsUnitController - 单位 runtime 状态持有 (S3 修复; P2.1 Activity 替代 string FSM)
##
## P1.5 (修 S3) 拆分: 与 hex AIStrategy 同构方向, 但 RTS 有"runtime state"(nav 引用 / 当前
## activity)需要每 actor 一份, 不能挂在 strategy 上(strategy 是无状态共享)。
##
## P2.1 重写: 替代 Phase 1 的 string FSM (_last_intent_action: String) — 现在
## current_activity: RtsActivity 表示意图, RtsActivity.advance 推进。
##
## 职责:
##   1. 持 actor + agent + strategy 引用 (controller 是 actor 的"AI 入口")
##   2. tick(dt, world): 调 strategy.decide → 与 current_activity 比较 → 复用/替换 →
##      RtsActivity.advance 推进 (内部驱动 nav agent / 写 actor.current_target_id)
##   3. 暴露 wants_to_attack(): 给 procedure 决定是否触发 basic attack
##   4. 暴露 get_intent_action(): 给 smoke / debug 用 ("idle" / "move" / "approach" / "attack")
##
## 决策来源:
##   - phase-1-foundation.md P1.5 (S3 修复, 无状态策略 + 有状态 controller)
##   - phase-2-core-systems.md P2.1 (Activity 替换 string FSM)
class_name RtsUnitController
extends RefCounted


# ========== 字段 ==========

## 关联的 actor (1:1 owner)
var actor: RtsUnitActor = null

## 关联的 nav agent (Phase 2 P2.7 接 BattleDirector 时可能调整)
var agent: RtsNavAgent = null

## 共享策略实例(无状态, 同 unit_class 多个 actor 共用一个)。
## 注意: 这里只是引用 — controller 不写 strategy 内字段。
var strategy: RtsAIStrategy = null

## 当前正在跑的 activity (P2.1 替代 _last_intent_action 字符串 FSM)。
##
## 由 strategy.decide 提议 + reconcile 决定; 也可由 set_activity_chain 显式 push (smoke /
## P2.6 玩家命令场景, 此时 strategy 提议会临时被 cancel/ 替换 — 等链跑完恢复 strategy 控制)。
##
## null 表示尚未决策; advance 全跑完也是 null, 下一 tick 由 strategy 重新决策。
var current_activity: RtsActivity = null

## P2.3 stuck recovery: 命令被 abandon 后 strategy.decide 暂停 — current_activity 保持 Idle,
## 不被 strategy 提议覆盖。P2.6 玩家命令系统接入后, 玩家给新命令时 clear_command_abandon() 解除。
var _command_abandoned: bool = false

## P2.6: 玩家显式命令的"override-strategy" 标志。set_activity_chain(chain, true) 时设为 true,
## tick 跳过 strategy.decide / reconcile, 仅推进 current_activity, 让玩家命令不被自动 AI 覆盖。
##
## 链跑完 (current_activity 变 null 或全 DONE) 自动清; 也可 clear_player_command_override() 显式解。
##
## 与 _command_abandoned 的关系: 两者互斥优先级 — abandoned 优先 (单位被困彻底放弃),
## 此 flag 在 set_activity_chain(override=true) 时如有 abandoned 状态会一并 clear。
var _player_command_active: bool = false


# ========== 初始化 ==========

func _init(p_actor: RtsUnitActor, p_agent: RtsNavAgent, p_strategy: RtsAIStrategy) -> void:
	actor = p_actor
	agent = p_agent
	strategy = p_strategy


# ========== Tick ==========

## procedure 主循环每帧调用; strategy.decide → reconcile → advance。
##
## reconcile 规则:
##   - current null / DONE → 直接接受 proposed
##   - 等价 (RtsActivity.is_equivalent_to) → 复用 current, 丢弃 proposed (避免 nav 抖动)
##   - 不等价 → cancel current, 立刻 flush 让 on_last_run 释放 nav, 接管 proposed
##
## P2.3: command_abandoned 时跳过 strategy.decide, 仅推进 current_activity (Idle)。
## P2.6: _player_command_active 时也跳过 strategy.decide, 让玩家显式命令直到链跑完不被覆盖。
func tick(dt: float, world: RtsWorldGameplayInstance) -> void:
	if actor == null or actor.is_dead() or world == null or strategy == null:
		return

	if _command_abandoned:
		# 不跑 strategy.decide, 不替换 current_activity (abandon_command 已设为 Idle)
		if current_activity != null:
			current_activity.bind_runtime(agent)
			current_activity = RtsActivity.advance(current_activity, actor, world, dt)
		return

	if _player_command_active:
		# P2.6: 玩家命令期间不让 strategy 覆盖。链跑完 (advance 返回 null) 自动清 flag,
		# 让 strategy 接管下一 tick。
		if current_activity != null:
			current_activity.bind_runtime(agent)
			current_activity = RtsActivity.advance(current_activity, actor, world, dt)
		if current_activity == null:
			_player_command_active = false
		return

	# 1. Strategy 决策 (无状态; 每 tick 给出"建议 activity")
	var proposed := strategy.decide(actor, world)

	# 2. Reconcile current_activity 与 proposed
	if current_activity == null or current_activity.is_done():
		current_activity = proposed
	elif current_activity.is_equivalent_to(proposed):
		# 复用 current; proposed 自然 GC
		pass
	else:
		current_activity.cancel()
		# 立刻 advance 一次, 让 cancel 转 DONE 调到 on_last_run (释放 nav 资源)
		var _flushed := RtsActivity.advance(current_activity, actor, world, dt)
		current_activity = proposed

	# 3. 绑 runtime + 推进
	if current_activity != null:
		current_activity.bind_runtime(agent)
		current_activity = RtsActivity.advance(current_activity, actor, world, dt)


# ========== 显式 push (smoke / 未来玩家命令) ==========

## 显式替换当前 activity (取消旧链)。
##
## smoke_activity_chain 用于注入测试链; P2.6 玩家命令也走此入口 (PlaceBuilding / AttackHere
## 等翻译为 Activity 链 push 进 controller)。
##
## P2.6 起 override_strategy=true 时设 _player_command_active flag — controller.tick 跳过
## strategy.decide, 让玩家命令链严格执行直到跑完 (或 clear_player_command_override 显式解)。
## 旧调用 (smoke_activity_chain / smoke_production 的 spawner) 不传 override_strategy → 默认
## false 与 Phase 1 行为兼容 (strategy 仍会 reconcile / 替换)。
##
## override=true 也会清 abandoned 状态 — 玩家显式命令应能"复活" stuck 单位 (设计 D1)。
func set_activity_chain(chain_head: RtsActivity, override_strategy: bool = false) -> void:
	if current_activity != null and not current_activity.is_done():
		current_activity.cancel()
		var _flushed := RtsActivity.advance(current_activity, actor, null, 0.0)
	current_activity = chain_head
	_player_command_active = override_strategy
	if override_strategy:
		# 玩家命令应能从 stuck/abandon 状态启动单位 — 否则 stuck 单位永远收不到玩家命令
		_command_abandoned = false


## P2.6: 显式清除"玩家命令 override" 标志, 让下一 tick strategy.decide 重新接管。
##
## 调方在: 玩家"取消命令" UI 按钮 / 玩家命令链跑完后想立刻让 AI 接管 / 等场景调用。
## 链跑完 (current_activity → null) 时 controller.tick 也会自动清 flag, 通常不需要手动调。
func clear_player_command_override() -> void:
	_player_command_active = false


## P2.6: 是否处于"玩家命令 override" 模式 — strategy.decide 当前被忽略。
func is_player_command_active() -> bool:
	return _player_command_active


# ========== 给 procedure / smoke 用的查询 ==========

## 是否本 tick 想发起 basic attack。委托给 current_activity。
##
## procedure 主循环里在 actor.can_attack() 时调用 — 同时 true 才触发 attack action。
func wants_to_attack() -> bool:
	if current_activity == null:
		return false
	return current_activity.wants_to_attack()


## 当前决策标签 ("idle" / "move" / "approach" / "attack" / "attack_move"); smoke / debug 用,
## 不在生产 path 上做 string 决策 (那是 Phase 1 string FSM 的反模式)。
func get_intent_action() -> String:
	if current_activity == null or current_activity.is_done():
		return "idle"
	return current_activity.get_intent_label()


# ========== P2.3 stuck recovery API ==========

## 是否处于"命令已 abandon"状态 (stuck detector 连续 N 次 repath 失败后调 abandon_command 标记)。
##
## abandon 状态下 controller.tick 跳过 strategy.decide, 保持 current_activity = Idle, 直到
## clear_command_abandon() 被调用 (P2.6 玩家命令接入后)。
func is_command_abandoned() -> bool:
	return _command_abandoned


## 取消当前 activity, 切到 IdleActivity, 标记 abandon。
##
## stuck detector 在连续 MAX_REPATH_FAILURES 次 local repath 失败后调用 — 单位被建筑 / 地形完全
## 包围, attack-move 命令不可能完成时, 降级为"原地不动" (即 IdleActivity)。
##
## P2.6 玩家命令系统会暴露"clear_command_abandon" 入口, 玩家给新命令时清掉 abandon flag。
## P2.5 之前 (M1 仅 AI 驱动) 没有 P2.6, abandon 后 unit 保持 idle 至战斗结束 — smoke 可观察。
func abandon_command() -> void:
	if current_activity != null and not current_activity.is_done():
		current_activity.cancel()
		# 立刻 flush 让 on_last_run 释放 nav (clear_target / 清 current_target_id)
		var _flushed := RtsActivity.advance(current_activity, actor, null, 0.0)
	current_activity = RtsIdleActivity.new()
	_command_abandoned = true


## 清除 abandon 标记, 让 strategy.decide 重新接管 (P2.6 玩家命令 / 周期性 retry 时调用)。
func clear_command_abandon() -> void:
	_command_abandoned = false
