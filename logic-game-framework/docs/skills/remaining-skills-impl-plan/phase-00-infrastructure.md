# 0 · 技能前置基础设施

> 开发入口：[`../remaining-skills-impl-plan.md`](../remaining-skills-impl-plan.md)
> 下一阶段：[phase-01-chain-lightning.md](phase-01-chain-lightning.md)


> 这部分先于 Chain / Shadow 真正落码。目标是补小型通用能力，不把机制藏进单个技能里。

## 0.0 Action 分层合同 + validator

**结论**：先把 “Ability 过程入口” 和 “底层副作用原语” 拆清楚，避免后续每个复杂技能都新增半公开业务 Action。`Action` 体系按四层理解和约束：

| 层 | 是否继承 Action | 是否可进 timeline | 语义 | 例子 |
|---|---|---|---|---|
| Util / Utils | 否 | 否 | 最底层结算 / 副作用函数；不负责 target selector / timeline adapter | `HexBattleDamageUtils.apply_damage` |
| Primitive Action | 是 | 是 | 领域原语 adapter；薄封装 target selector / resolver / util；不知道具体技能 | `DamageAction`、`LaunchProjectileAction`、`ApplyBuffAction`、`LooseTagAction`、未来 `SpawnActorAction` |
| FlowAction | 是 | 是 | 流程组合器；只组织 child actions，不承载业务语义 | `FlowAction.if_` |
| SkillLocalAction | 是 | 是 | 技能私有过程函数；只服务一个 Ability，可组织 Primitive/Flow 或直接调用 Util | `_DemonFormTickAction`、`_ShadowStepTeleportAction` |

`Action.BaseAction` 是 framework internal abstract substrate，不再作为应用层直接继承入口。新增业务 Action 必须选择更具体的语义基类：

| 基类 | 用途 | 额外约束 |
|---|---|---|
| `Action.PrimitiveAction` | public 领域原语 adapter | 必须登记 public primitive allowlist / index |
| `Action.FlowActionBase` | 流程组合器 | 必须声明 child actions，业务逻辑不得放在这里 |
| `Action.SkillLocalAction` | 技能私有过程函数 | 必须绑定 owner `config_id`，运行时 assert 当前 ability 匹配 |

落地规则：
- 简单技能可以直接在 timeline 上组合 Primitive Action，不强制包一层 local action。
- 复杂技能用 SkillLocalAction 表达自身过程，不为了单个技能新增 public Primitive Action。
- 真正底层结算沉到 Util / Utils；Action 不重复实现跨来源管线，例如伤害仍走 `HexBattleDamageUtils`。
- FlowAction 只能表达流程，不放技能业务逻辑；当前只批准 `FlowAction.if_`，不先扩 `sequence` / DSL / VM。
- Projectile / summon / delayed hit 这类跨时间响应继续走 event-driven，不用 Action callback 平行系统。
- 应用层禁止新增 `extends Action.BaseAction`。旧代码先走 allowlist，后续 cleanup 分批迁移到 `PrimitiveAction` / `FlowActionBase` / `SkillLocalAction`。

**AI 生成约束**不能只靠命名约定，基础设施落码第一批加入轻量 validator。它先作为新增技能 / 新机制门禁，不在本轮强制迁移旧 `PoisonTickAction` / `SurgeTickAction`。

| 文件 | 新建/改 |
|---|---|
| `core/actions/action_validator.gd` 或测试侧 validator | 新建：扫描 Action 分层合同 |
| `tests/core/actions/action_architecture_validator_test.gd` | 新建：作为测试入口跑 validator |
| `core/actions/Action.gd` | 改：增加 child action 执行 helper / child declaration hook |
| `docs/skills/remaining-skills-impl-plan.md` | 本节：记录合同，后续技能必须遵守 |

validator V1 检查：
- `core/actions` / `stdlib/actions` / `example/*/logic/actions` 下新增 `class_name .*Action` 视为 public Primitive Action，必须进入 allowlist 或登记表；避免 AI 把技能专用 Action 放进 public action 目录。
- `example/**` / `stdlib/**` 新增 Action 不允许直接 `extends Action.BaseAction`；必须继承 `Action.PrimitiveAction`、`Action.FlowActionBase` 或 `Action.SkillLocalAction`。core 内部基类与既有历史类暂时 allowlist。
- skill / buff 文件内允许内嵌 `_XxxAction` 作为 SkillLocalAction；不允许这类 local action 使用 `class_name`。
- SkillLocalAction 若后续引入基类，必须声明 `owner_config_id` 并在 `execute()` 时 assert 当前 `ctx.ability_ref.config_id` 匹配；owner mismatch 用 `Log.assert_crash`，不 silent fail。
- FlowAction / hook / composite 调用 child action 时必须走统一 helper：`Action.execute_child(parent_action, child_action, ctx)`（或同等命名），helper 内部负责 `child.execute(ctx)` + `child._verify_unchanged()`；禁止各处手写漏 verify。
- 持有 child actions 的 Action 必须让 child 参与 `_freeze()`；后续优先由 `BaseAction.get_child_actions()` 统一处理，减少手写遗漏。
- V1 validator 用 file-grep + light parse 足够，不要求完整 GDScript AST。allowlist 每条必须写明原因与 `migrate_by` 备注；`PoisonTickAction` / `SurgeTickAction` 可作为临时豁免，但需标为后续收回 buff 文件的 cleanup 项。

实施时机：
1. **基础设施落码第一批**：新增本节合同、child action helper、`FlowAction.if_`、`LooseTagAction` / `TagComponentConfig` 时，同步补 validator V1。
2. **Demon Form 落码**：使用 SkillLocalAction，不新增 public `DemonFormTickAction`。
3. **Totem spike 后**：若需要 `SpawnActorAction` / `RemoveActorAction`，作为 Primitive Action 登记；图腾自身过程仍是 SkillLocalAction。
4. **后续 cleanup**：再评估是否把既有 `PoisonTickAction` / `SurgeTickAction` 收回对应 buff 文件；不作为当前 review 阻塞。

---

## 0.1 Tag 语义拆分：`LooseTagAction` + `TagComponentConfig`

**结论**：先把 tag mutation 与 component tag 配置拆清楚，再实现后续技能。`TagContainer` 已经有三种 tag 来源，文档和 API 命名必须反映这个语义：

| 来源 | 写入方式 | 生命周期 | 适用场景 |
|---|---|---|---|
| loose tag | `LooseTagAction.Apply/Remove` 或 `AbilitySet.add_loose_tag/remove_loose_tag` | 手动添加/移除 | Stance 这种可切换、可由 action 修改的运行时状态 |
| auto-duration tag | `add_auto_duration_tag` | 计时自动清理 | 短时、按 tag 层独立过期的状态 |
| component tag | `TagComponentConfig` → `TagComponent` | 随 Ability 实例 grant/remove 自动添加/清理 | `status_action_lock` 这种“Ability 存在期间天然拥有”的标签 |

`TagAction` 当前名字过宽：`ApplyTagAction` / `RemoveTagAction` 实际只修改 loose tag；`HasTagAction` 又读取聚合 tag，语义混在一起。V1 收敛为：

- 新增 `LooseTagAction`，只承载 loose tag mutation：`LooseTagAction.Apply.new(...)` / `LooseTagAction.Remove.new(...)`。
- 保留旧 `TagAction` 作为兼容 facade 或迁移入口，文件/类注释标为 legacy / `@deprecated`；新增代码不再使用旧名，validator 对新增 `TagAction.` 调用给 warning 或 fail（allowlist 内历史代码除外）。
- 聚合 tag 查询不放进 `LooseTagAction`。主动技能条件继续用 `Condition.HasTagCondition` / `NoTagCondition`；action flow 内需要判断时使用 `FlowAction.if_(predicate, ...)`。
- 新增 `TagComponentConfig` 到 core 层，作为 `TagComponent` 的正式 `AbilityComponentConfig`，不再在 example 里写局部 `StatusTagConfig`。

| 文件 | 新建/改 |
|---|---|
| `core/actions/loose_tag_action.gd` | 新建：`LooseTagAction.Apply` / `LooseTagAction.Remove`，语义等价于旧 loose tag apply/remove |
| `core/actions/tag_action.gd` | 改：标记为 legacy / compatibility facade；内部可委托 `LooseTagAction`，避免一次性破坏旧技能 |
| `core/abilities/components/tag_component_config.gd` | 新建：`TagComponentConfig`，通过 `create_component()` 创建 `TagComponent` |
| `core/abilities/components/tag_component.gd` | 可选改：构造参数从裸 `Dictionary` 收敛到 `TagComponentConfig` 或保持兼容读取 |
| `example/hex-atb-battle/logic/buffs/action_lock_status.gd` | 改：删除内嵌 `StatusTagConfig`，改用 `TagComponentConfig` |
| `example/**` | grep 并迁移其它局部 `StatusTagConfig` / component-tag config；`TagComponentConfig` 落地后禁止再写 example-local 版本 |
| `tests/core/actions/loose_tag_action_test.gd` | 新建：验证 apply/remove 只影响 loose tags |
| `tests/core/abilities/tag_component_config_test.gd` | 新建：验证 component tags 随 ability grant/remove 自动清理 |

`ActionLockStatus` 改写目标：

```gdscript
.component_config(TagComponentConfig.builder()
	.tag(TAG_ACTION_LOCKED)
	.tag(TAG_CANT_ACT)
	.optional_tag(reason_tag)
	.build())
```

边界：
- `TagComponentConfig` 不用于 Stance 切换；它写的是 component tag，随 Ability 实例生命周期清理。
- `LooseTagAction` 不用于 `status_action_lock` 的 `cant_act`；否则多个 action lock 实例重叠时，remove loose tag 容易误删其它来源。
- `NoInstanceConfig.on_apply_actions/on_remove_actions` 可以执行 `LooseTagAction`，但这表达的是“Ability 生命周期触发 loose tag mutation”，不是 component tag。
- `StatusTagConfig` 这类 example-local 命名需要随本节移除。后续需要 component tag 时一律使用 core `TagComponentConfig`，避免 `StatusTag` / `LooseTag` / 聚合查询三种语义继续混名。

## 0.2 `FlowAction.if_`

**结论**：新增通用 Action flow 组合器，支持 hook 后条件分支。它不改 `Action.BaseAction.execute()` 合同，不加 `should_execute`，也不新增专用 `XxxConditionalAction`。

| 文件 | 新建/改 |
|---|---|
| `core/actions/flow_action.gd` | 新建：`FlowAction.if_(predicate, then_actions, else_actions := [])` |
| `tests/core/actions/flow_action_test.gd` | 新建：then / else / empty branch / predicate type assert / child failure / nested action freeze 验证 |
| `tests/run_tests.gd` | 改：注册 flow action 单测 |

使用形态：

```gdscript
DamageAction.on_hit(
	FlowAction.if_(
		_has_next_chain_target,
		[LaunchProjectileAction.new(...)]
	)
)
```

合同：
- `predicate` 语义是 `func(ctx: ExecutionContext) -> bool`。实现可以保持 `Callable` 形态，但返回值必须是 `bool`；返回 `null` / `int` / 其它类型时用 `Log.assert_crash`，不要把 `nil` 静默当 false。
- `then_actions` / `else_actions` 允许为空数组，语义是 selected branch no-op；这用于占位 hook 或“条件不满足不做事”的流程，不需要额外空 Action。
- 只执行被选中的 branch，按数组顺序执行 child actions。
- child action 必须经 `Action.execute_child(parent_action, child_action, ctx)` 执行。若 child 返回 failure，`IfAction` 停止当前 branch 后续 action，并返回 failure，已产生的 event_dicts 保留在 failure result 中；不做 best-effort 全跑。
- `ActionResult.data` 只合并 `FlowAction` 自己的元信息（例如 branch），不把 child data 自动提升为公共合同；技能需要跨 tag 状态时用 §0.4 execution-local state。

## 0.3 Character logic-facing V0

**结论**：新增 `CharacterActor.facing_direction`，但不放进 `RawAttributeSet`，也不放进 `HexBattleActor`。EnvironmentActor 默认没有 facing；未来只有炮塔、传送带、喷火陷阱这类确实有方向语义的环境物才单独 opt-in。

V0 语义只做瞬时逻辑朝向：

| 时机 | 规则 |
|---|---|
| 初始站位 | A 队默认朝东，B 队默认朝西 |
| 主动移动 | face toward destination |
| 主动攻击 / 施法 | face toward target |
| forced displacement(push/knockback/pull) | 不改变 facing |
| 被攻击 | 不自动转向 |
| Shadow Step | caster 落地后 face target；target facing 不变 |

| 文件 | 新建/改 |
|---|---|
| `logic/hex_facing.gd` | 新建：方向常量 / `opposite(dir)` / `direction_between(from,to)` / `face_actor_toward(actor, target_hex, reason, event_collector)` |
| `logic/character_actor.gd` | 改：`facing_direction`、getter/setter、serialize/snapshot |
| `example/hex-atb-battle/core/events/battle_events.gd` | 改：新增 `ActorFacingChangedEvent` |
| `logic/actions/start_move_action.gd` 或 `apply_move_action.gd` | 改：主动移动时更新 facing |
| `core/abilities/core/ability_execution_instance.gd` 或 hex active-use adapter | 改：主动攻击/施法时集中更新 caster facing（创建 active execution 时按 current target face target，避免每个技能手写） |
| `frontend/world_view.gd` / `frontend/scene/unit_view.gd` | 改：只给 CharacterActor 渲染 facing arrow，收到 facing event 后视觉 lerp/tween |
| `tests/battle/skill_scenarios/facing_basics_scenario.gd` | 新建：移动/施法/forced displacement 三类时机 |

**事件合同**：

```gdscript
ActorFacingChangedEvent(
	actor_id,
	old_direction,
	new_direction,
	reason
)
```

前端只消费事件做 visual-facing 平滑转向；logic-facing 已经在事件产生时瞬时生效。不引入 turn speed / turn duration / facing lock。

集中入口：
- 主动技能/攻击的 facing 更新优先放在 active-use execution 创建入口：从 current target 取 hex position，调用 `HexFacing.face_actor_toward(caster, target_pos, "active_use", event_collector)`。单个技能只有特殊语义时才自己调用，例如 Shadow Step 落地后 face target。
- `HexFacing.face_actor_toward` 是唯一推荐 setter：先更新 `CharacterActor.facing_direction` source of truth，再 push `ActorFacingChangedEvent`。这样逻辑读到的 facing 永远是最新值，事件只作为 audit/presentation。
- 位移类 action 按 displacement kind 分流：

| kind / 来源 | 是否改 facing | 位置 |
|---|---|---|
| player/AI move、`StartMoveAction` / `ApplyMoveAction` 主动移动 | 是，face toward destination | move action 内调用 `HexFacing.face_actor_toward` |
| push / knockback / pull 等 forced displacement | 否 | displacement action 只发 `ActorDisplacedEvent` |
| teleport | 默认否；由调用方决定 | Shadow Step 成功落地后自己 face target |

EnvironmentActor V0 不加 facing 字段。未来如果炮塔/喷火陷阱需要方向，优先引入 `IFaceable`/`DirectionalEnvironmentActor` 这类 opt-in 形态；不要把 `facing_direction` 回填进 `HexBattleActor` 基类。

## 0.4 Ability execution-local state

**结论**：给每个 `AbilityExecutionInstance` 增加一份 execution-local state 字典。state 的 owner 是 `AbilityExecutionInstance`；`ExecutionContext` 不拥有这份状态，只是在执行同一次 execution 的 action 时携带同一份字典引用，作为访问入口。它用于表达“同一次施法前段结果影响后段”的短生命周期状态，不用于跨施法 / 永久状态。

Shadow Step 需要这个能力：`CAST` tag 完成瞬移后写入 `shadow_step.teleport_success=true`，`HIT` tag 再由 `FlowAction.if_` 读取该值决定是否造成伤害。不能把这个状态放在 `Action` 自身，因为 Action 是共享无状态对象；也不能只放 `ActionResult` metadata，因为后续 tag 看不到前一个 tag 的返回值。

当前 `AbilityExecutionInstance` 没有记录字段，也不保存每个 action 的 `ActionResult` 历史；只有 timeline/action 配置、trigger event、ability_ref、elapsed/state/triggered_tags 等调度状态。本机制是在 instance 上新增一份窄用途 scratchpad，而不是把 action result log 做成 execution 的一等状态。

| 文件 | 新建/改 |
|---|---|
| `core/actions/execution_context.gd` | 改：新增 `execution_state: Dictionary` 引用与 `set_execution_state/get_execution_state` namespace assert helper |
| `core/abilities/core/ability_execution_instance.gd` | 改：持有 `_execution_state`，构造每个 tag 的 `ExecutionContext` 时传同一份引用 |
| `tests/core/abilities/ability_execution_instance_test.gd` | 改：验证同一 execution 跨 tag 可见、不同 execution 互相隔离 |

实现形态：
- `AbilityExecutionInstance` 初始化 `var _execution_state: Dictionary = {}`。
- `_build_execution_context(...)` 把 `_execution_state` 引用放进 `ExecutionContext`；source of truth 仍是 `AbilityExecutionInstance`。
- 同一次 execution 的 `CAST` / `HIT` / `END` 虽然每次都会创建新的 `ExecutionContext`，但它们共享同一份 `execution_state` 字典。
- `ExecutionContext.create_callback_context(...)` 也要继续携带同一份 `execution_state`，避免 action hook 里丢失本次 execution 状态。
- `ExecutionContext.create_callback_context(...)` 可以继续不继承 `execution_info`；hook 里需要保留的是 event chain / ability_ref / execution_state。
- 每次技能释放都会创建新的 `AbilityExecutionInstance`，因此不同施法之间天然隔离。
- 不保存完整 `ActionResult` 历史。`ActionResult.event_dicts` 已进入 `EventCollector` 供 replay/presentation 消费；`ActionResult.data` 语义不稳定，若直接跨 tag 复用会把 action 的局部返回值升级成框架级状态，当前属于过度设计。

使用约束：
- key 必须带技能/机制命名空间，例如 `shadow_step.teleport_success`。
- value 只放可序列化的轻量数据；坐标用 `HexCoord.to_dict()`，不直接塞 Actor / Resource 引用。
- replay 合同采用“重 execute 推导”路径：execution_state 是 transient scratchpad，事件流不记录它；replay 通过同 seed、同事件输入、deterministic action 再次执行自然重建。只有需要 presentation/debug 可观察的字段，才额外写进 event `customData` 或新增显式 event。
- 因此写 execution_state 的 action 必须 deterministic，不能读当前帧 wall-clock、随机数或外部 mutable singleton。若未来需要 mid-timeline snapshot/replay 恢复，`AbilityExecutionInstance.serialize()` 需包含这份字典，或新增 `ExecutionStateSetEvent` 类事件再切到事件驱动恢复。
- 长期状态仍放 `AbilitySet.tag_container` / actor state，不放 execution-local state。
- namespace 约束要硬化：优先提供 `ctx.set_execution_state("shadow_step.teleport_success", value)` / `ctx.get_execution_state(...)` helper，并 assert key 包含 `.`；validator V1 可 light-scan `execution_state["literal"]`，要求 `<namespace>.<field>`。

## 0.5 `DamageAction` dead / invalid target no-op

**结论**：在 `HexBattleDamageAction.execute()` 的 per-target 循环入口补通用 guard：目标不存在或已死亡时 no-op，不产生 damage event，不扣负 HP，不触发 post damage，也不触发 on-hit/on-kill callback。

这不是 Shadow Step 特判，而是伤害管线的通用合同。死亡 actor 当前会留在 world 里用于前端死亡动画 / buff 对账；如果继续允许 DamageAction 打死者，短期不会重复 DeathEvent，但会产生尸体 damage event、继续扣负 HP，并可能误触发未来 lifesteal / damage counter / hit proc 等 post 逻辑。

| 文件 | 新建/改 |
|---|---|
| `example/hex-atb-battle/logic/actions/damage_action.gd` | 改：per-target 开始处跳过 null / dead target |
| `example/hex-atb-battle/tests/battle/skill_scenarios/damage_dead_target_noop_scenario.gd` | 新建：dead target 不产生 damage / death / post side effect |

伪码：

```gdscript
for target_id in targets:
	var target_actor := battle.get_actor(target_id)
	if target_actor == null or target_actor.is_dead():
		continue
	# 之后再进入 PreDamageEvent / apply_damage / callbacks / post damage
```

注意：这个 guard 放在 `DamageAction` 层，而不是每个 skill 的 `FlowAction.if_` predicate 里。skill predicate 只表达技能自己的 gating，例如 Shadow Step 的 `teleport_success`。

callback 边界：
- `on_hit` 只在本次 DamageAction 对一个 alive target 实际完成伤害结算后触发。
- `on_kill` 只在本次 DamageAction 把 alive target 从 `hp > 0` 打到 `hp <= 0` 时触发；对已死亡 target 的 no-op 不触发 on-kill。
- guard 使用 hex damageable actor 的统一 alive/dead 谓词。当前优先复用 `HexBattleActor.is_dead()`；若后续 EnvironmentActor 出现 destroy/dead 分叉，再补 `is_alive()` / `is_destroyed_or_dead()` 统一接口，不让 DamageAction 分散判断具体子类。
- V1 silently skip，不新增 `SkillTargetSkippedEvent`。未来如果需要命中遥测或 UI 提示，再补显式 skip event。

## 0.6 `NoInstanceConfig` lifecycle actions

**结论**：扩展现有 `NoInstanceConfig` / `NoInstanceComponent`，支持 Ability lifecycle 上的 action 组合：

```gdscript
NoInstanceConfig.builder()
	.on_apply_actions([...])
	.on_remove_actions([...])
	.build()
```

这不是 Stance 专用机制。它补齐的是框架里“Ability grant/remove 时执行一组无 timeline action”的通用表达能力，避免每个技能为了初始化/清理 loose tag、标记或轻量状态都新增业务 component。

| 文件 | 新建/改 |
|---|---|
| `core/abilities/components/no_instance_config.gd` | 改：新增 `on_apply_actions` / `on_remove_actions` 字段与 builder 方法 |
| `core/abilities/components/no_instance_component.gd` | 改：实现 `on_apply(context)` / `on_remove(context)` 执行 lifecycle actions |
| `tests/core/abilities/no_instance_component_test.gd` 或现有组件测试 | 改/新增：验证 apply/remove lifecycle actions 执行、trigger actions 旧行为不变 |

合同：
- 现有 event trigger 语义保持不变：`trigger(...) + actions(...)` 仍表示“事件匹配后立即执行 actions，不创建 timeline instance”。
- 新增 lifecycle actions 不要求 trigger；`build()` 允许 lifecycle-only config。
- 如果配置了普通 `actions(...)`，仍必须配置至少一个 trigger，避免无触发事件的 action 静默无效。
- lifecycle actions 构造一个仅用于执行的 `ExecutionContext`：带 `ability_ref`、`event_collector`、空/内部 lifecycle event dict；`game_state_provider` 可为 `null`。
- lifecycle actions 适合 `LooseTagAction` 这类只依赖 owner / ability / tag_container 的轻量 action；不应在 V1 用来发 projectile、移动 actor 或做需要 battle provider 的行为。运行时如果 lifecycle action 读取缺失的 `game_state_provider`，应 `Log.assert_crash` 给出明确错误；validator V1 可先用 action allowlist 限制 lifecycle action 类型。
- 不新增 `GameEvent`，不把 lifecycle action 本身写入 replay；若 action 修改 tag，既有 `RecordingUtils.record_tag_changes()` 会记录 tag 变化。
- 同一个 `NoInstanceConfig` 内 action 数组按声明顺序执行；同一个 Ability 的多个 component config 按 AbilityConfig 声明顺序构建/执行 lifecycle hook。

触发表：

| 场景 | 是否触发 `on_remove_actions` | 说明 |
|---|---|---|
| duration / expire 导致 Ability remove-effects | 是 | 走 Ability remove/effects 清理链 |
| `AbilitySet.revoke_ability` / 显式 remove | 是 | Stance remove 清理 Wrath/Calm 依赖这个路径 |
| actor death | 当前不自动触发 | hex 死亡 actor 会留在 world/recording 中用于死亡动画和对账；除非未来 death cleanup 显式 revoke abilities，否则不要假设 death 会清 loose tag |

---

## 0.7 基础设施落码顺序（建议）

§0 内部建议按依赖从低到高落：

1. §0.0 Action 分层合同 + `Action.execute_child` helper + validator shell / allowlist。
2. §0.1 `LooseTagAction` + `TagComponentConfig`，顺手迁移 `ActionLockStatus` 和其它 example-local tag component config。
3. §0.2 `FlowAction.if_`。
4. §0.6 `NoInstanceConfig` lifecycle actions。
5. §0.5 `DamageAction` dead/invalid no-op。
6. stack-scaled StatModifier + scenario attribute snapshot（Demon Form 前置）。
7. §0.3 Character logic-facing V0。
8. §0.4 execution-local state。

validator V1 工程上按 light parse / grep 先做，不等完整 AST。第一版目标是把 AI 生成代码的边界硬化：新增 public Action 归类、禁止 app/example 直接继承 `BaseAction`、child action 必须 freeze/execute-helper、legacy `TagAction` 新用法告警、execution_state key namespace 检查。
