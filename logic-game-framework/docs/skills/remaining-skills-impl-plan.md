# 剩余 5 技能可执行级实施方案（align 门文档）

> 配套 [`skill-implementation-progress.md`](skill-implementation-progress.md) 与 [`.lomo-team/reference/inkmon-skill-design.md`](../../.lomo-team/reference/inkmon-skill-design.md)。
> 本文 = taxonomy 16 技能剩余 5 个的**可执行级 align 方案**，逐个评审通过后才落码。
> 创建：2026-05-18 · Opus 4.7

---

## 评审追踪表

| 顺序 | # | 技能 | 难度 | 真新机制 | 评审状态 |
|---|---|---|---|---|---|
| 1 | 9 | Chain Lightning | ★★☆☆☆ | projectile `customData` 透传 + `FlowAction.if_` | ✅ 已批准(先落基础设施) |
| 2 | 12 | Shadow Step | ★★★☆☆ | logic-facing V0 + execution-local state + DamageAction dead-target no-op + facing arrow | ✅ 已批准(先落基础设施) |
| 3 | 14 | Stance | ★★☆☆☆ | NoInstance lifecycle actions + `LooseTagAction` stance tags | ✅ 已批准 |
| 4 | 15 | Demon Form | ★★★☆☆ | 无 | ⬜ 待评审 |
| 5 | 16 | Summon Totem | ★★★★★ | 框架可行性(spike 查清) | ⬜ 待评审(spike 门) |

状态：⬜ 待评审 · 🟡 需改(见该节末「评审意见」) · ✅ 已批准可落码

---

## 收敛的全局决策（评审时若推翻在此改）

| 项 | 结论 | 依据 |
|---|---|---|
| 实施顺序 | 基础设施(action 分层合同 + validator + tag 语义拆分 + FlowAction + execution-local state + DamageAction no-op + facing + NoInstance lifecycle actions) → Chain → Shadow → Stance → Demon → Totem | Chain/Shadow/Stance/Demon 都依赖前置小机制；之后仍按难度递增 |
| schema 倾向 | 优先复用；Chain 允许补 projectile `customData` 透传 + `FlowAction.if_`；Shadow 引入 CharacterActor logic-facing + execution-local state；不扩 core Timeline | Chain=projectileHit 链式触发；Shadow=ActorDisplacedEvent + facing state + teleport_success；DamageAction 统一过滤 dead/invalid target |
| facing 归属 | `facing_direction` 是 CharacterActor 运行时状态，不进 `RawAttributeSet`，不放 `HexBattleActor` 基类 | AttributeSet 是 float/modifier/breakdown 数值管线；EnvironmentActor 暂无朝向语义 |
| Demon Form 实现 | 方案 A：每 tick `add_modifier` 一个独立 +2 ADD_BASE | `raw.add_modifier` 是现成公共 API；无 stacks/动态/组件 |
| Summon Totem | spike 先行验证框架原语 → 绿再 TDD 建技能 | 战斗中途 add/remove actor + recording 完整性未知 |
| crit 建模 | 「+X%」用 damage resolver ×系数，**不**强设 is_critical | DamageAction 无强制 crit 入口；resolver 系数是既有 pattern |

---

# 0 · 技能前置基础设施

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
| `core/actions/Action.gd` | 可选改：增加 child action 执行 helper / child declaration hook |
| `docs/skills/remaining-skills-impl-plan.md` | 本节：记录合同，后续技能必须遵守 |

validator V1 检查：
- `core/actions` / `stdlib/actions` / `example/*/logic/actions` 下新增 `class_name .*Action` 视为 public Primitive Action，必须进入 allowlist 或登记表；避免 AI 把技能专用 Action 放进 public action 目录。
- `example/**` / `stdlib/**` 新增 Action 不允许直接 `extends Action.BaseAction`；必须继承 `Action.PrimitiveAction`、`Action.FlowActionBase` 或 `Action.SkillLocalAction`。core 内部基类与既有历史类暂时 allowlist。
- skill / buff 文件内允许内嵌 `_XxxAction` 作为 SkillLocalAction；不允许这类 local action 使用 `class_name`。
- SkillLocalAction 若后续引入基类，必须声明 `owner_config_id` 并在 `execute()` 时 assert 当前 `ctx.ability_ref.config_id` 匹配。
- FlowAction / hook / composite 调用 child action 时必须走统一 helper，或至少满足 `child.execute(ctx)` 后紧跟 `child._verify_unchanged()`。
- 持有 child actions 的 Action 必须让 child 参与 `_freeze()`；后续优先由 `BaseAction.get_child_actions()` 统一处理，减少手写遗漏。

实施时机：
1. **基础设施落码第一批**：新增本节合同、`FlowAction.if_`、`LooseTagAction` / `TagComponentConfig` 时，同步补 validator V1。
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
- 保留旧 `TagAction` 作为兼容 facade 或迁移入口，新增代码不再使用旧名。
- 聚合 tag 查询不放进 `LooseTagAction`。主动技能条件继续用 `Condition.HasTagCondition` / `NoTagCondition`；action flow 内需要判断时使用 `FlowAction.if_(predicate, ...)`。
- 新增 `TagComponentConfig` 到 core 层，作为 `TagComponent` 的正式 `AbilityComponentConfig`，不再在 example 里写局部 `StatusTagConfig`。

| 文件 | 新建/改 |
|---|---|
| `core/actions/loose_tag_action.gd` | 新建：`LooseTagAction.Apply` / `LooseTagAction.Remove`，语义等价于旧 loose tag apply/remove |
| `core/actions/tag_action.gd` | 改：标记为 legacy / compatibility facade；内部可委托 `LooseTagAction`，避免一次性破坏旧技能 |
| `core/abilities/components/tag_component_config.gd` | 新建：`TagComponentConfig`，通过 `create_component()` 创建 `TagComponent` |
| `core/abilities/components/tag_component.gd` | 可选改：构造参数从裸 `Dictionary` 收敛到 `TagComponentConfig` 或保持兼容读取 |
| `example/hex-atb-battle/logic/buffs/action_lock_status.gd` | 改：删除内嵌 `StatusTagConfig`，改用 `TagComponentConfig` |
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

## 0.2 `FlowAction.if_`

**结论**：新增通用 Action flow 组合器，支持 hook 后条件分支。它不改 `Action.BaseAction.execute()` 合同，不加 `should_execute`，也不新增专用 `XxxConditionalAction`。

| 文件 | 新建/改 |
|---|---|
| `core/actions/flow_action.gd` | 新建：`FlowAction.if_(predicate, then_actions, else_actions := [])` |
| `tests/core/actions/flow_action_test.gd` | 新建：then / else / nested action freeze 验证 |
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
| `logic/hex_facing.gd` | 新建：方向常量 / `opposite(dir)` / `direction_between(from,to)` |
| `logic/character_actor.gd` | 改：`facing_direction`、getter/setter、serialize/snapshot |
| `example/hex-atb-battle/core/events/battle_events.gd` | 改：新增 `ActorFacingChangedEvent` |
| `logic/actions/start_move_action.gd` 或 `apply_move_action.gd` | 改：主动移动时更新 facing |
| 主动技能触发路径 | 改：主动攻击/施法时更新 caster facing（优先集中在 active-use 执行入口，避免每个技能手写） |
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

## 0.4 Ability execution-local state

**结论**：给每个 `AbilityExecutionInstance` 增加一份 execution-local state 字典。state 的 owner 是 `AbilityExecutionInstance`；`ExecutionContext` 不拥有这份状态，只是在执行同一次 execution 的 action 时携带同一份字典引用，作为访问入口。它用于表达“同一次施法前段结果影响后段”的短生命周期状态，不用于跨施法 / 永久状态。

Shadow Step 需要这个能力：`CAST` tag 完成瞬移后写入 `shadow_step.teleport_success=true`，`HIT` tag 再由 `FlowAction.if_` 读取该值决定是否造成伤害。不能把这个状态放在 `Action` 自身，因为 Action 是共享无状态对象；也不能只放 `ActionResult` metadata，因为后续 tag 看不到前一个 tag 的返回值。

当前 `AbilityExecutionInstance` 没有记录字段，也不保存每个 action 的 `ActionResult` 历史；只有 timeline/action 配置、trigger event、ability_ref、elapsed/state/triggered_tags 等调度状态。本机制是在 instance 上新增一份窄用途 scratchpad，而不是把 action result log 做成 execution 的一等状态。

| 文件 | 新建/改 |
|---|---|
| `core/actions/execution_context.gd` | 改：新增 `execution_state: Dictionary` 引用 |
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
- 若未来需要 mid-timeline snapshot/replay 恢复，`AbilityExecutionInstance.serialize()` 需包含这份字典。
- 长期状态仍放 `AbilitySet.tag_container` / actor state，不放 execution-local state。

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
- lifecycle actions 适合 `LooseTagAction` 这类只依赖 owner / ability / tag_container 的轻量 action；不应在 V1 用来发 projectile、移动 actor 或做需要 battle provider 的行为。
- 不新增 `GameEvent`，不把 lifecycle action 本身写入 replay；若 action 修改 tag，既有 `RecordingUtils.record_tag_changes()` 会记录 tag 变化。

---

# 1 · Chain Lightning #9

**设计卡**：首目标魔法伤害 → 跳最近未命中敌人，每跳 -20%，最多 3 跳。

## 1.1 评审结论 + 调研结论

**原方案否决**：把 3 跳都放进 `TimelineTags.HIT` 的 Action local loop，会让伤害事件按顺序产生，但逻辑时间仍是同一 tag / 同一帧，不满足“先弹 A 再弹 B 再弹 C”的过程感。

新方向：复用 Fireball 的 **`projectileHit` → static hit timeline** 模式，但心智模型按 **on-hit 链式发射** 理解：

```text
projectileHit
  → HexBattleDamageAction 结算本跳伤害
  → DamageAction.on_hit(FlowAction.if_(has_next_chain_target, [LaunchProjectileAction.new(...)]))
```

主技能 cast timeline 只发射第一段 lightning projectile；后续每段 projectile 自己携带链路数据（第几跳、当前伤害、已命中目标、chain_id）。命中后 `DamageAction.on_hit` 只负责进入 hook；是否继续弹跳由 `FlowAction.if_` 判断；真正发射下一段仍复用 `LaunchProjectileAction`。

| 既有原语 | 现状 | 够用 |
|---|---|---|
| `LaunchProjectileAction` + `ProjectileSystem` | fireball/precise_shot 已走 projectileHit 二段触发 | ✅ 复用链式发射 |
| `ActivateInstanceConfig.trigger(ProjectileEvents.PROJECTILE_HIT_EVENT, filter)` | fireball 命中后进入 hit timeline | ✅ 复用 |
| `HexBattleDamageAction.on_hit(...)` | apply_damage 之后、post damage 之前触发 | ✅ 用作“命中后发下一段” |
| `FlowAction.if_(predicate, actions)` | 现无通用 Action flow；聚合 tag 查询已有 `Condition.HasTagCondition`，但它不是 action 分支组合器 | ⚠️ 新增小型组合器 |
| `HexBattleDamageUtils.apply_damage` + `broadcast_post_damage` | poison_tick / DamageAction 验证 pre→apply→post | ✅ |
| `HexBattlePreEvents.PreDamageEvent` | expose/shield 拦截走同一路径 | ✅ |
| `BattleEvents.DamageType.MAGICAL` | fireball 用例 | ✅ 复用 |
| `battle.get_alive_actors()` + `HexCoord.distance_to` | HexWorldGI / HexCoord 已支持找最近活敌人 | ✅ |
| Projectile `customData` | `LaunchProjectileAction` 已写入 launch params，但 `ProjectileSystem._emit_hit_event` 目前未透传到 hit event | ⚠️ 小补丁 |

不扩展 core Timeline。动态跳数由“是否继续发下一段 projectile”决定；timeline 仍是静态声明。

## 1.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `core/actions/flow_action.gd` | 前置基础设施：通用 Action 条件组合器，提供 `FlowAction.if_` |
| `stdlib/systems/projectile_system.gd` | 改：`projectileHit` 透传 launch `customData` |
| `logic/skills/chain_lightning.gd` | 新建 |
| `logic/skills/all_skills.gd` | 改(+1 行注册，带 cast/hit 两条 timeline) |
| `tests/battle/skill_scenarios/chain_lightning_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改(回写) |

## 1.3 数值常量表

| 常量 | 值 | 理由 |
|---|---|---|
| CONFIG_ID | `skill_chain_lightning` | 对齐 `skill_*` |
| CAST_TIMELINE_ID | `skill_chain_lightning` | 施法/发射第一段 |
| HIT_TIMELINE_ID | `skill_chain_lightning_hit` | 每次 projectileHit 后结算一跳 |
| BASE_DAMAGE | `60.0` MAGICAL | 多目标，单跳 < fireball 80 |
| MAX_HITS | `3` | 沿用本文既定语义：总命中 3 段；若设计卡要“首目标+3跳”，评审时改 4 |
| FALLOFF | `0.2`（×0.8/跳） | 设计卡 -20% |
| COOLDOWN_MS | `5000.0` | 多目标 > fireball 4000 |
| RANGE meta | `5` | 同 fireball |
| Projectile visual | `lightning` | `projectile_visualizer.gd` 已有 lightning 分支 |
| Projectile speed | `200.0` | 先同 fireball，保证有 projectileHit 驱动过程 |
| Cast Timeline | total 600，CAST:200 LAUNCH:400 END:600 | 同 fireball cast 结构 |
| Hit Timeline | total 100，END:100，`on_timeline_start` 跑 `DamageAction.on_hit(FlowAction.if_(...))` | 命中事件已到，伤害立即结算；下一段 projectile 由 FlowAction 判定后交给 LaunchProjectileAction 发射 |
| 伤害序列 | 60 / 48 / 38.4 | 60×0.8ⁿ |

## 1.4 代码骨架

`projectile_system.gd` 小补丁（通用透传，不新增 event kind）：
```gdscript
func _emit_hit_event(projectile: ProjectileActor, target_actor_id: String, hit_position: Vector3) -> void:
	# ...
	var options := {
		"damage": projectile.config.get(ProjectileActor.CFG_DAMAGE),
		"damageType": projectile.config.get(ProjectileActor.CFG_DAMAGE_TYPE),
	}
	var custom_data: Variant = projectile.get_launch_params().get("customData", {})
	if custom_data is Dictionary and not (custom_data as Dictionary).is_empty():
		options["customData"] = (custom_data as Dictionary).duplicate(true)
	var event := ProjectileEvents.create_projectile_hit_event(
		projectile.id, source_actor_id, target_actor_id, hit_position,
		projectile.get_fly_time(), projectile.get_fly_distance(),
		projectile.get_ability_config_id(), options)
	# ...
```

`flow_action.gd`（通用 Action flow 组合器；不做业务逻辑）：
```gdscript
class_name FlowAction
extends RefCounted

static func if_(
	predicate: Callable,
	then_actions: Array[Action.BaseAction],
	else_actions: Array[Action.BaseAction] = []
) -> Action.BaseAction:
	return IfAction.new(predicate, then_actions, else_actions)

class IfAction:
	extends Action.FlowActionBase

	var _predicate: Callable
	var _then_actions: Array[Action.BaseAction] = []
	var _else_actions: Array[Action.BaseAction] = []

	func _init(
		predicate: Callable,
		then_actions: Array[Action.BaseAction],
		else_actions: Array[Action.BaseAction] = []
	) -> void:
		super._init(TargetSelector.new())
		type = "flow_if"
		_predicate = predicate
		_then_actions.assign(then_actions)
		_else_actions.assign(else_actions)

	func get_child_actions() -> Array[Action.BaseAction]:
		var children: Array[Action.BaseAction] = []
		children.append_array(_then_actions)
		children.append_array(_else_actions)
		return children

	func execute(ctx: ExecutionContext) -> ActionResult:
		var passed := bool(_predicate.call(ctx))
		var actions := _then_actions if passed else _else_actions
		var all_events: Array[Dictionary] = []
		for action in actions:
			var result := Action.execute_child(self, action, ctx)
			if result != null and result.event_dicts is Array:
				all_events.append_array(result.event_dicts)
		return ActionResult.create_success_result(all_events, { "branch": "then" if passed else "else" })
```

`chain_lightning.gd`（Fireball 同款触发；hit timeline 内用 `DamageAction.on_hit(FlowAction.if_(...))` 链式发下一段）：
```gdscript
class_name HexBattleChainLightning
const CONFIG_ID := "skill_chain_lightning"
const CAST_TIMELINE_ID := "skill_chain_lightning"
const HIT_TIMELINE_ID := "skill_chain_lightning_hit"
const BASE_DAMAGE := 60.0
const MAX_HITS := 3
const FALLOFF := 0.2
const COOLDOWN_MS := 5000.0

static var CHAIN_LIGHTNING_CAST_TIMELINE := TimelineData.new(CAST_TIMELINE_ID, 600.0, {
	TimelineTags.CAST: 200.0, TimelineTags.LAUNCH: 400.0, TimelineTags.END: 600.0,
})

static var CHAIN_LIGHTNING_HIT_TIMELINE := TimelineData.new(HIT_TIMELINE_ID, 100.0, {
	TimelineTags.END: 100.0,
})

static func _projectile_hit_filter(event: Dictionary, ctx: AbilityLifecycleContext) -> bool:
	var data: Dictionary = event.get("customData", {}) as Dictionary
	return ProjectileEvents.is_projectile_hit_event(event) \
		and event.get("ability_config_id", "") == CONFIG_ID \
		and ctx.ability != null \
		and event.get("source_actor_id", "") == ctx.owner_actor_id \
		and data.get("ability_instance_id", "") == ctx.ability.id

static func _chain_custom_data_resolver() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		return {
			"ability_instance_id": ctx.ability_ref.id if ctx.ability_ref != null else "",
			"chain_id": ctx.execution_info.id if ctx.execution_info != null else IdGenerator.generate("chain_lightning"),
			"hit_index": 0,
			"damage": BASE_DAMAGE,
			"visited_actor_ids": [],
		})

static func _chain_damage_resolver() -> FloatResolver:
	return Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
		var data: Dictionary = ctx.get_current_event().get("customData", {}) as Dictionary
		return float(data.get("damage", BASE_DAMAGE)))

class NextChainTarget extends TargetSelector:
	func select(ctx: ExecutionContext) -> Array[String]:
		var data := HexBattleChainLightning._next_chain_data(ctx)
		var target_id: String = data.get("target_actor_id", "")
		return [target_id] if target_id != "" else []

static func _next_chain_target_selector() -> TargetSelector:
	return NextChainTarget.new()

static func _has_next_chain_target(ctx: ExecutionContext) -> bool:
	return _next_chain_data(ctx).has("target_actor_id")

static func _next_chain_projectile_config_resolver() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		var data := _next_chain_data(ctx)
		var damage := float(data.get("damage", BASE_DAMAGE * (1.0 - FALLOFF)))
		return {
			ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
			ProjectileActor.CFG_VISUAL_TYPE: "lightning",
			ProjectileActor.CFG_SPEED: 200.0,
			ProjectileActor.CFG_MAX_LIFETIME: 5000.0,
			ProjectileActor.CFG_HIT_DISTANCE: 30.0,
			ProjectileActor.CFG_DAMAGE: damage,
			ProjectileActor.CFG_DAMAGE_TYPE: "magical",
		})

static func _next_chain_start_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var data := _next_chain_data(ctx)
		return _actor_world_pos(data.get("start_actor_id", ""), ctx.game_state_provider))

static func _next_chain_target_position_resolver() -> Vector3Resolver:
	return Resolvers.vec3_fn(func(ctx: ExecutionContext) -> Vector3:
		var data := _next_chain_data(ctx)
		return _actor_world_pos(data.get("target_actor_id", ""), ctx.game_state_provider))

static func _next_chain_custom_data_resolver() -> DictResolver:
	return Resolvers.dict_fn(func(ctx: ExecutionContext) -> Dictionary:
		var data := _next_chain_data(ctx)
		return {
			"ability_instance_id": ctx.ability_ref.id if ctx.ability_ref != null else "",
			"chain_id": data.get("chain_id", ""),
			"hit_index": int(data.get("hit_index", 0)),
			"damage": float(data.get("damage", BASE_DAMAGE)),
			"visited_actor_ids": (data.get("visited_actor_ids", []) as Array).duplicate(),
		})

static func _next_chain_data(ctx: ExecutionContext) -> Dictionary:
	var battle: HexWorldGameplayInstance = ctx.game_state_provider
	var hit_event := ctx.get_original_event()
	var damage_event := BattleEvents.DamageEvent.from_dict(ctx.get_current_event())
	if battle == null or not ProjectileEvents.is_projectile_hit_event(hit_event):
		return {}
	if ctx.ability_ref == null:
		return {}
	var chain: Dictionary = hit_event.get("customData", {}) as Dictionary
	if chain.get("ability_instance_id", "") != ctx.ability_ref.id:
		return {}
	var current_id := damage_event.target_actor_id
	var current_actor := battle.get_actor(current_id)
	var caster := battle.get_character_actor(ctx.ability_ref.owner_actor_id)
	if current_actor == null or caster == null:
		return {}
	var hit_index := int(chain.get("hit_index", 0))
	if hit_index + 1 >= MAX_HITS:
		return {}
	var visited: Array[String] = []
	visited.assign(chain.get("visited_actor_ids", []))
	if not current_id in visited:
		visited.append(current_id)
	var next_id := _nearest_unvisited_enemy(caster.get_team_id(), current_actor.hex_position, visited, battle)
	if next_id == "":
		return {}
	return {
		"start_actor_id": current_id,
		"target_actor_id": next_id,
		"chain_id": chain.get("chain_id", ""),
		"hit_index": hit_index + 1,
		"damage": float(chain.get("damage", BASE_DAMAGE)) * (1.0 - FALLOFF),
		"visited_actor_ids": visited,
	}

static func _nearest_unvisited_enemy(team: int, from_pos: HexCoord,
		visited: Array[String], battle: HexWorldGameplayInstance) -> String:
	var best := ""
	var best_d := 1 << 30
	for actor in battle.get_alive_actors():
		if actor.get_team_id() == team or actor.get_id() in visited:
			continue
		var d := from_pos.distance_to(actor.hex_position)
		if d < best_d:
			best_d = d
			best = actor.get_id()
	return best

static func _actor_world_pos(actor_id: String, battle: HexWorldGameplayInstance) -> Vector3:
	var actor := battle.get_actor(actor_id) if battle != null else null
	if actor == null or not actor.hex_position.is_valid():
		return Vector3.ZERO
	return Vector3(actor.hex_position.q, actor.hex_position.r, 0)

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("连锁闪电")
	.description("对目标造成魔法伤害，弹跳至最近的其他敌人，每跳衰减 20%，最多 3 跳")
	.ability_tags(["skill", "active", "ranged", "magic", "enemy", "projectile"])
	.meta(HexBattleSkillMetaKeys.RANGE, 5)
	.active_use(ActiveUseConfig.builder()
		.timeline_id(CAST_TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.str_val("magic_fireball"))])
		.on_tag(TimelineTags.LAUNCH, [LaunchProjectileAction.new(
			HexBattleTargetSelectors.current_target(),
			Resolvers.dict_val({
				ProjectileActor.CFG_PROJECTILE_TYPE: ProjectileActor.PROJECTILE_TYPE_MOBA,
				ProjectileActor.CFG_VISUAL_TYPE: "lightning",
				ProjectileActor.CFG_SPEED: 200.0,
				ProjectileActor.CFG_MAX_LIFETIME: 5000.0,
				ProjectileActor.CFG_HIT_DISTANCE: 30.0,
				ProjectileActor.CFG_DAMAGE: BASE_DAMAGE,
				ProjectileActor.CFG_DAMAGE_TYPE: "magical",
			}),
			HexBattleSkillHelpers.owner_position_resolver(),
			HexBattleSkillHelpers.target_position_resolver(),
			null,
			_chain_custom_data_resolver())])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.component_config(ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.new(
			ProjectileEvents.PROJECTILE_HIT_EVENT,
			_projectile_hit_filter))
		.timeline_id(HIT_TIMELINE_ID)
		.on_timeline_start([HexBattleDamageAction.new(
			HexBattleTargetSelectors.current_target(),
			_chain_damage_resolver(),
			BattleEvents.DamageType.MAGICAL
		).on_hit(FlowAction.if_(
			_has_next_chain_target,
			[LaunchProjectileAction.new(
				_next_chain_target_selector(),
				_next_chain_projectile_config_resolver(),
				_next_chain_start_position_resolver(),
				_next_chain_target_position_resolver(),
				null,
				_next_chain_custom_data_resolver())]
		))])
		.build())
	.build())
```
`all_skills.gd`：`arr.append(_Entry.new(HexBattleChainLightning.ABILITY, [HexBattleChainLightning.CHAIN_LIGHTNING_CAST_TIMELINE, HexBattleChainLightning.CHAIN_LIGHTNING_HIT_TIMELINE]))`

## 1.5 scenario

map 7×3，caster[0,0] + enemy_0[1,0] enemy_1[2,0] enemy_2[3,0] enemy_3[6,2]（链外）。default get_actions。max_ticks 80。

| 断言 | 期望 |
|---|---|
| enemy_0 | `assert_float_in(dmg,[60,90])` |
| enemy_1 | `[48,72]` |
| enemy_2 | `[38.4,57.6]` |
| enemy_3 | `filter_damage_events` size 0 |
| 主伤害事件数 | 3 |
| `projectileLaunched` | size 3，`visualType=="lightning"` |
| `projectileHit` | size 3，且每条带 `customData.ability_instance_id` / `chain_id` / `hit_index` 0/1/2 |
| 时序 | 3 个 damage event 所在 replay frame 严格递增（证明不是同一 HIT local loop） |

crit 双值兜底（damage_action `randf()<0.1`）。收工 **重跑 5 次**。

## 1.6 新机制清单

1. **Projectile hit `customData` 透传**：`LaunchProjectileAction` 已把 customData 存进 projectile launch params；补 `ProjectileSystem._emit_hit_event` 把该字典写入 `projectileHit` event。无新增 event kind，无 core Timeline 扩展。
2. **`FlowAction.if_`**：通用 Action flow 组合器，签名为 `FlowAction.if_(predicate, then_actions, else_actions := [])`；predicate 是 `func(ctx: ExecutionContext) -> bool` 的纯判断。它只负责分支与聚合 `ActionResult`，不做技能业务逻辑，不污染 `Action.BaseAction` 的 `execute()` 合同。
3. **Chain Lightning next-target helper**：链路状态来自 projectile `customData`（`ability_instance_id` / `chain_id` / `hit_index` / `damage` / `visited_actor_ids`）。是否继续弹跳由 `_has_next_chain_target(ctx)` 判断；下一段 projectile 仍由 `LaunchProjectileAction` 发射，不新增专用 projectile launcher。

**Ordering 合同（已接受）**：
- 下一段 projectile 在当前跳 `apply_damage` 完成后、`broadcast_post_damage` 前发射。
- 下一段 projectile 的伤害仍必须等后续 `projectileHit` 才结算；因此不会把下一跳伤害插到当前跳 post reactions 前。
- replay 事件顺序可能是 `damage(A) → projectileLaunched(A→B) → thorn/reflect(...)`；这是本技能 V1 接受的表演语义。
- 若当前跳 post reaction 把 caster 反死，已发射的下一段 projectile 可能仍有视觉事件，但后续 hit trigger 因 caster/ability 不再有效应不会继续结算伤害；scenario 需补这个边界回归。

明确不做：不新增 dynamic Timeline tag，不新增全局 tick 分支，不从 EventCollector 反查历史事件驱动逻辑。
同时不修改 `LaunchProjectileAction` 的空 `TargetSelector` 语义；Chain Lightning 的终止条件由外层 `FlowAction.if_` 表达，避免把 actor-target-only 语义写进通用 projectile launch primitive。

## 1.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | N/A |
| StageCue | 起手复用 `magic_fireball`（§7.3，无专属闪电资产不编新名） |
| default_registry | 不动 |
| projectile | 复用 `visualType="lightning"`；无需新 visualizer |

链锁折线特效由连续 `projectileLaunched/projectileHit` 事件自然驱动；scenario 只读逻辑事件，不要求专属闪电资产。

> **评审意见**：原 Action local loop 方案不通过；专用 `LaunchNextChainProjectileAction` 也撤回。当前方案收敛为 `projectileHit -> DamageAction.on_hit -> FlowAction.if_(has_next_chain_target, [LaunchProjectileAction])`。落码前需重点确认 `FlowAction.if_` 不改变既有 Action 执行合同，`customData` 透传只影响 projectile event payload，不改变既有 fireball/precise_shot 行为；并补 “post reaction 反死 caster 后不继续结算下一跳伤害” 回归。

---

# 2 · Shadow Step #12

**设计卡**：瞬移到目标"身后"，+50% 一击。

## 2.1 评审结论 + 调研结论

| 既有原语 | 现状 | 够用 |
|---|---|---|
| `battle.grid.move_occupant(from,to)` + `actor.hex_position=` | push_action:138 落地 | ✅ |
| `BattleEvents.ActorDisplacedEvent.create(...)` | push_action:141 落地 | ✅ 复用(kind=teleport) |
| `HexCoord.neighbor(direction)` / `direction_to_neighbor` | HexCoord 已有 0..5 方向体系 | ✅ |
| `CharacterActor.facing_direction` | 当前不存在 | ⚠️ 前置基础设施 |
| `ActorFacingChangedEvent` | 当前不存在 | ⚠️ 前置基础设施 |
| `HexBattleDamageAction` | strike/knockback | ✅(resolver ×1.5) |
| `ExecutionContext.execution_state` | 前置基础设施新增 | ✅ 记录本次 execution 的瞬移是否成功 |
| `FlowAction.if_` | 前置基础设施新增 | ✅ 根据 `teleport_success` 决定 HIT 是否结算 |
| `DamageAction` dead target no-op | 前置基础设施优化 | ✅ HIT 时目标已死则通用跳过 |

**已推翻旧方案**：不再用“target 六邻格里离 caster 最远的空格”近似身后。Shadow Step 作为 `logic-facing V0` 的第一个消费者，使用明确 facing：

```text
behind(target) = target.hex_position.neighbor(opposite(target.facing_direction))
```

边界：
- target 必须是 `CharacterActor`；EnvironmentActor 默认没有 facing，不作为 Shadow Step 合法目标。
- 落点选择不是“只认唯一背侧格”：先尝试背侧格，再尝试背侧左右，继续向两侧类推，最后才尝试正面格；目标周身 1 格内都被占用、被预订或出界时才 teleport 失败，caster 留在原地。
- HIT 阶段只检查 `shadow_step.teleport_success`，不再检查 HIT 当下 caster 是否仍在目标背后；目标后续转身 / 位移不会取消伤害。
- teleport 失败也消耗冷却：ActiveUse cost 在激活时支付，后续落点不可用属于技能 whiff，不做 refund。
- caster / target 死亡或失效不在 Shadow Step 本地 predicate 里重复处理；§0.5 会先补齐 `DamageAction` 通用 no-op 合同。
- caster 成功落地后 face target；target facing 不变。
- forced displacement 不改变 facing。

## 2.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `logic/skills/shadow_step.gd` | 新建：含 `_ShadowStepTeleportAction` SkillLocalAction |
| `logic/skills/all_skills.gd` | 改(+1) |
| `tests/battle/skill_scenarios/shadow_step_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改 |

依赖 §0.3 的 facing 基础设施和 §0.4 的 execution-local state；本技能不再单独引入 facing 字段 / facing event。

## 2.3 数值常量表

| 常量 | 值 | 理由 |
|---|---|---|
| CONFIG_ID | `skill_shadow_step` | |
| TIMELINE_ID | `skill_shadow_step` | |
| DAMAGE_MULT | `1.5`（caster.atk×1.5） | 设计卡 +50%；resolver 系数（非强制 crit） |
| COOLDOWN_MS | `6000.0` | gap closer + 高单发，长 CD |
| RANGE meta | `4` | gap closer 突进距离 |
| Timeline | total 500，CAST:150 HIT:300 END:500 | 先瞬移后斩；HIT 由 FlowAction 判断本次 execution 是否已成功瞬移 |

## 2.4 代码骨架

`shadow_step.gd` 内嵌 SkillLocalAction（只管瞬移；伤害交同 timeline 后续 DamageAction）：
```gdscript
class _ShadowStepTeleportAction:
	extends Action.SkillLocalAction

	func _init(target_selector: TargetSelector) -> void:
		super._init(target_selector, HexBattleShadowStep.CONFIG_ID)
		type = "shadow_step_teleport"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		var caster_id := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
		var targets := get_targets(ctx)
		ctx.execution_state["shadow_step.teleport_success"] = false
		if battle == null or caster_id == "" or targets.is_empty():
			return ActionResult.create_success_result([], { "skipped": true })
		var caster := battle.get_character_actor(caster_id)
		var target := battle.get_character_actor(targets[0])
		if caster == null or target == null or target.is_dead():
			return ActionResult.create_success_result([], { "skipped": true })

		var from_pos := caster.hex_position
		var land := _landing_slot(target, battle)
		if land == null:
			# 目标周身 1 格内无可用落点：caster 留在原地；HIT 阶段会因 teleport_success=false 跳过伤害。
			return ActionResult.create_success_result([], { "teleported": false })

		if not battle.grid.move_occupant(from_pos, land):
			return ActionResult.create_success_result([], { "teleported": false })
		caster.hex_position = land
		ctx.execution_state["shadow_step.teleport_success"] = true
		var dist := from_pos.distance_to(land)
		var events: Array[Dictionary] = []
		var displaced := BattleEvents.ActorDisplacedEvent.create(
			caster_id, from_pos.to_dict(), land.to_dict(),
			"teleport", caster_id, dist, 0.0, 0.0)        # 自位移：无 stagger
		events.append(ctx.event_collector.push(displaced.to_dict()))
		events.append_array(HexFacing.face_actor_toward(
			caster, target.hex_position, "shadow_step", ctx.event_collector))
		return ActionResult.create_success_result(events, { "teleported": true })

	# 目标周身 1 格内选择落点：背侧优先，再背侧左右，继续类推；无合法落点则 null。
	func _landing_slot(target: CharacterActor, battle: HexWorldGameplayInstance) -> HexCoord:
		var behind_dir := HexFacing.opposite(target.get_facing_direction())
		for dir in _landing_priority_dirs(behind_dir):
			var land := target.hex_position.neighbor(dir)
			if battle.grid.has_tile(land) and not battle.grid.is_occupied(land) and not battle.grid.is_reserved(land):
				return land
		return null

	static func _landing_priority_dirs(behind_dir: int) -> Array[int]:
		return [
			posmod(behind_dir, 6),      # 正背侧
			posmod(behind_dir - 1, 6),  # 背侧左
			posmod(behind_dir + 1, 6),  # 背侧右
			posmod(behind_dir - 2, 6),  # 侧后左
			posmod(behind_dir + 2, 6),  # 侧后右
			posmod(behind_dir + 3, 6),  # 正面，最后 fallback
		]
```

`shadow_step.gd`：
```gdscript
class_name HexBattleShadowStep
const CONFIG_ID := "skill_shadow_step"
const TIMELINE_ID := "skill_shadow_step"
const DAMAGE_MULT := 1.5
const COOLDOWN_MS := 6000.0

static var _ATK_X15: FloatResolver = Resolvers.float_fn(func(ctx: ExecutionContext) -> float:
	var oid := ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else ""
	var a := GameWorld.get_actor(oid)
	if a == null or not (a is CharacterActor):
		return 0.0
	return (a as CharacterActor).attribute_set.atk * DAMAGE_MULT)

static func _shadow_step_teleport_succeeded(ctx: ExecutionContext) -> bool:
	return bool(ctx.execution_state.get("shadow_step.teleport_success", false))

static var SHADOW_STEP_TIMELINE := TimelineData.new(TIMELINE_ID, 500.0, {
	TimelineTags.CAST: 150.0, TimelineTags.HIT: 300.0, TimelineTags.END: 500.0,
})

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("影袭")
	.description("瞬移到目标背侧并造成 150% 攻击力的一击")
	.ability_tags(["skill", "active", "melee", "enemy"])
	.meta(HexBattleSkillMetaKeys.RANGE, 4)
	.meta(HexBattleSkillMetaKeys.ALLOWED_TARGET_KINDS, ["Character"])
	.active_use(ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_tag(TimelineTags.CAST, [_ShadowStepTeleportAction.new(
			HexBattleTargetSelectors.current_target())])
		.on_tag(TimelineTags.HIT, [FlowAction.if_(
			_shadow_step_teleport_succeeded,
			[HexBattleDamageAction.new(
				HexBattleTargetSelectors.current_target(),
				_ATK_X15, BattleEvents.DamageType.PHYSICAL)]
		)])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.build())
```
> 不新增 `TimelineTags.TELEPORT`。`CAST` tag 表示逻辑瞬移点；`HIT` tag 表示动画间隔后的伤害点。

## 2.5 scenario

map 7×3，caster[0,0] enemy_0[4,0]（B 队默认 facing=WEST，背侧为 [5,0] 且为空）。default get_actions。max_ticks 60。

| 断言 | 期望 |
|---|---|
| `ActorDisplacedEvent` 出现且 `displacement_kind=="teleport"` source=caster | size≥1 |
| caster 落点 | `[5,0]`（target facing 反方向一格） |
| caster 终态相邻 enemy_0 | `final` 位置 distance==1 |
| caster final facing | WEST（落地后 face target） |
| target final facing | WEST（Shadow Step 不改变 target facing） |
| enemy_0 受击 = atk×1.5 | `assert_float_in([atk*1.5, atk*1.5*1.5])` |

补三个边界 case：
- fallback-side：enemy_0 背侧 [5,0] 放 wall / ally / reservation，但背侧左 / 右存在空格；caster 落到优先级最高的可用邻格，`shadow_step.teleport_success=true`，后续 HIT 正常造成 Shadow Step damage。
- blocked-all-around：enemy_0 周身 6 邻格都被占、被预订或出界时不产生 teleport，caster 留在原地，`shadow_step.teleport_success=false`，因此不产生 Shadow Step damage。
- post-teleport change：如果瞬移成功后、HIT 前目标 facing 或位置被其它效果改变，Shadow Step 仍然在 HIT 尝试造成伤害；伤害条件是“传送成功”，不是“HIT 当下仍在背后”。若目标已死亡/失效，由 §0.5 的通用 DamageAction no-op 保护跳过。

## 2.6 新机制清单

**技能自身无新机制**：依赖 §0 的 `FlowAction.if_` + execution-local state + DamageAction dead-target no-op + Character logic-facing V0；位移仍复用 `ActorDisplacedEvent`。不新增 `TimelineTags.TELEPORT`，瞬移动作放在 `TimelineTags.CAST`。

## 2.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | N/A |
| StageCue | 可选复用 `melee_combo`（瞬斩感）；或不接（瞬移本身无 cue 也不红） |
| facing arrow | 由 §0.3 基础设施提供；本技能只触发 caster facing 变化 |
| default_registry / projectile | 不动 / N/A |

前端瞬移动画走既有 ActorDisplaced 订阅（push 已铺）；伤害事件在后续 HIT tag 出现，给传送动画留出短间隔。朝向箭头由 `ActorFacingChangedEvent` 驱动 visual-facing lerp/tween。若目标周身 1 格内无可用落点，不产生 displacement / damage，技能表现为本次释放 whiff。

> **评审意见**：已批准。旧的“离 caster 最远格”近似方案撤回。当前方案要求先落 §0.3 logic-facing + §0.4 execution-local state + §0.5 DamageAction no-op：Shadow Step 以 `target.facing_direction` 反方向为优先落点，在目标周身 1 格内按 `[背侧, 背左, 背右, 侧后左, 侧后右, 正面]` 查找可用格；EnvironmentActor 默认没有 facing，不是合法目标；周身 6 邻格都不可用、被占用或被预订时失败留原地且仍吃冷却；HIT 阶段通过 `FlowAction.if_(_shadow_step_teleport_succeeded, [DamageAction])` 阻止无条件伤害。

---

# 3 · Stance: Wrath/Calm #14

**设计卡**：两姿态主动切换。Wrath 造伤+50%/受伤+50%；Calm 造伤-25%/受伤-25%。

## 3.1 调研结论 + 范式

**方案更新**：Stance 不再拆成 `skill_stance + buff_stance_wrath + buff_stance_calm` 三个 Ability。姿态是 `skill_stance` 自身拥有的运行时状态，用 owner 的 `AbilitySet.tag_container` loose tag 记录：

| tag | 语义 |
|---|---|
| `stance:skill_stance:wrath` | Wrath 当前激活 |
| `stance:skill_stance:calm` | Calm 当前激活 |

`skill_stance` 是一个主动 Ability，同时组合三类现有/基础设施 component：
- grant 后默认进入 Wrath。
- 主动释放时切换 loose tag：Wrath → Calm；Calm → Wrath。
- outgoing / incoming 伤害修正由 `skill_stance` 自己挂的 `PreEventConfig` 根据当前 stance tag 决定。

这避免了两个 buff Ability 互斥，也避免把 Wrath / Calm 塞进 buff UI 的 positive / negative 分类。replay 仍能看到 tag change，因为 `RecordingUtils.record_tag_changes()` 已订阅 `AbilitySet.tag_container`。

无 outgoing_damage_amp 属性。两侧都走 **PreDamageEvent 修改通路**，注册入口是 `skill_stance` 自己挂的 `PreEventConfig`：
- 受伤 ±%：incoming `PreEventConfig` 过滤 `target_actor_id==owner` → 读 stance tag → `Modification.multiply("damage", k)`
- 造伤 ±%：outgoing `PreEventConfig` 过滤 `source_actor_id==owner` → 读 stance tag → `Modification.multiply("damage", k)`

**生命周期合同**：stance tags 是 loose tag，必须由 `skill_stance` 自己负责生命周期清理。通过 §0.6 的 `NoInstanceConfig.on_apply_actions/on_remove_actions` 表达：grant 时加默认 Wrath，remove 时清 Wrath / Calm。切换逻辑仍由 `LooseTagAction` + `FlowAction.if_` 组合表达。

**唯一性合同(V1 文档约束)**：当前测试 / 装备路径由我们控制，同一 actor 不会拥有多个 `skill_stance` 实例。V1 不扩 `AbilityConfig` instance policy；未来若开放 loadout / 多来源 grant，需要补 `unique_by_config` 合同或 `grant_unique_ability` helper。

## 3.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `logic/skills/stance.gd` | 新建：含 `skill_stance` 配置、tag lifecycle actions、PreDamage handlers、tag 切换组合 |
| `logic/skills/all_skills.gd` | 改(+1：只注册 `skill_stance`) |
| `tests/battle/skill_scenarios/stance_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改 |

## 3.3 数值常量表

| 常量 | 值 |
|---|---|
| 技能 CONFIG_ID | `skill_stance` |
| WRATH_TAG | `stance:skill_stance:wrath` |
| CALM_TAG | `stance:skill_stance:calm` |
| Wrath 造伤/受伤 mult | `1.5` / `1.5` |
| Calm 造伤/受伤 mult | `0.75` / `0.75` |
| 姿态 duration | 永久 loose tag（随 `skill_stance` grant/remove 生命周期初始化与清理） |
| 技能 COOLDOWN_MS | `2000.0`（防抖） |
| 技能 Timeline | total 300，HIT:150 END:300 |
| 初始姿态 | grant 后默认 Wrath；首次主动释放 → Calm，再 → Wrath，循环 |

## 3.4 代码骨架

`stance.gd`（单 Ability；无技能专用 Action / component）：
```gdscript
class_name HexBattleStance

const CONFIG_ID := "skill_stance"
const TIMELINE_ID := "skill_stance"
const WRATH_TAG := "stance:skill_stance:wrath"
const CALM_TAG := "stance:skill_stance:calm"
const WRATH_MULT := 1.5
const CALM_MULT := 0.75
const COOLDOWN_MS := 2000.0

static var STANCE_TIMELINE := TimelineData.new(TIMELINE_ID, 300.0, {
	TimelineTags.HIT: 150.0, TimelineTags.END: 300.0,
})

static func _has_wrath(ctx: ExecutionContext) -> bool:
	var actor := GameWorld.get_actor(ctx.ability_ref.owner_actor_id if ctx.ability_ref != null else "")
	var aset := IAbilitySetOwner.get_ability_set(actor)
	return aset != null and aset.has_tag(WRATH_TAG)

static func _stance_mult(ctx: AbilityLifecycleContext) -> float:
	if ctx.ability_set == null:
		return 1.0
	if ctx.ability_set.has_tag(WRATH_TAG):
		return WRATH_MULT
	if ctx.ability_set.has_tag(CALM_TAG):
		return CALM_MULT
	return 1.0

static func _incoming() -> PreEventConfig:
	return PreEventConfig.new(
		HexBattlePreEvents.PRE_DAMAGE_EVENT,
		func(_m: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			var mult := _stance_mult(ctx)
			if is_equal_approx(mult, 1.0):
				return EventPhase.pass_intent()
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", mult, ctx.ability.config_id, "姿态受伤")
			]),
		func(e: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return e.get("target_actor_id", "") == ctx.owner_actor_id,
		"Stance incoming damage")

static func _outgoing() -> PreEventConfig:
	return PreEventConfig.new(
		HexBattlePreEvents.PRE_DAMAGE_EVENT,
		func(_m: MutableEvent, ctx: AbilityLifecycleContext) -> Intent:
			var mult := _stance_mult(ctx)
			if is_equal_approx(mult, 1.0):
				return EventPhase.pass_intent()
			return EventPhase.modify_intent(ctx.ability.id, [
				Modification.multiply("damage", mult, ctx.ability.config_id, "姿态造伤")
			]),
		func(e: Dictionary, ctx: AbilityLifecycleContext) -> bool:
			return e.get("source_actor_id", "") == ctx.owner_actor_id,
		"Stance outgoing damage")

static var ABILITY := (AbilityConfig.builder()
	.config_id(CONFIG_ID)
	.display_name("姿态切换")
	.description("在 Wrath 与 Calm 两种姿态间切换")
	.ability_tags(["skill", "active", "self", "stance"])
	.component_config(NoInstanceConfig.builder()
		.on_apply_actions([
			LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
			LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
			LooseTagAction.Apply.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
		])
		.on_remove_actions([
			LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
			LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
		])
		.build())
	.component_config(_incoming())
	.component_config(_outgoing())
	.active_use(ActiveUseConfig.builder()
		.timeline_id(TIMELINE_ID)
		.on_timeline_start([StageCueAction.new(
			HexBattleTargetSelectors.ability_owner(),
			Resolvers.str_val("melee_slash"))])
		.on_tag(TimelineTags.HIT, [FlowAction.if_(
			_has_wrath,
			[
				LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
				LooseTagAction.Apply.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
			],
			[
				LooseTagAction.Remove.new(HexBattleTargetSelectors.ability_owner(), CALM_TAG),
				LooseTagAction.Apply.new(HexBattleTargetSelectors.ability_owner(), WRATH_TAG),
			]
		)])
		.condition(Condition.NoTagCondition.new(HexBattleActionLockStatus.TAG_CANT_ACT))
		.condition(HexBattleCooldownSystem.CooldownCondition.new())
		.cost(HexBattleCooldownSystem.TimedCooldownCost.new(COOLDOWN_MS))
		.build())
	.build())
```

不新增 `SwitchStanceAction`：切换姿态只是 “if has tag A then remove A + add B else remove B + add A”，用 `LooseTagAction` 和 §0 的 `FlowAction.if_` 表达即可。

## 3.5 scenario

caster[0,0] + 1 enemy。`get_actions` 多步：
1. 初始 grant 后断言 caster 有 `WRATH_TAG`、无 `CALM_TAG`。
2. caster Strike enemy，断 outgoing ×1.5。
3. enemy Strike caster，断 incoming ×1.5。
4. caster 施 stance，断 `WRATH_TAG` 移除、`CALM_TAG` 存在。
5. caster Strike enemy，断 outgoing ×0.75。
6. enemy Strike caster，断 incoming ×0.75。
7. caster 再施 stance，断回到 Wrath。

断言用 `assert_float_in` 兜 crit。额外补一个 lifecycle case：revoke / expire `skill_stance` 后，`WRATH_TAG` 和 `CALM_TAG` 都被清理。

## 3.6 新机制清单

1. **依赖 §0.6 NoInstance lifecycle actions**：`skill_stance` 用 `NoInstanceConfig.on_apply_actions/on_remove_actions` 表达默认 Wrath 与 remove 清理，不新增技能专用 component。
2. **未来规划：AbilityConfig instance policy**：V1 只文档约束 `skill_stance` 在同一 actor 上不多实例。未来若开放 loadout / 多来源 grant，需要补 `unique_by_config` / `grant_unique_ability` / reject-or-replace 策略，避免多个同 config 主动技能共享 loose tag 造成状态污染。

复用项：伤害修正仍走 `PreEventConfig` + `Modification.multiply` 通路；切换复用 `LooseTagAction.Apply` / `Remove` + `FlowAction.if_`；不新增事件/schema，不新增业务 `SwitchStanceAction`。

## 3.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | N/A：Wrath/Calm 是 stance tag，不是 buff ability |
| StageCue | 复用 `melee_slash`（自我姿态切换的挥手提示） |
| default_registry / projectile | 不动 / N/A |

若后续希望 UI 展示当前 stance，应新增 stance/tag visualizer，而不是走 BuffVisualizer。

> **评审意见**：已批准。Stance 从“三个 Ability（技能 + Wrath buff + Calm buff）”改为“单 Ability + loose stance tags”。主动释放用 `FlowAction.if_ + LooseTagAction` 切换 tag，不新增业务 Action；默认 Wrath 与 remove 清理由 §0.6 的 `NoInstanceConfig` lifecycle actions 表达；outgoing/incoming damage multiplier 由 `skill_stance` 自己挂的 `PreEventConfig` 读取当前 stance tag 决定。V1 文档约束同 actor 不出现多个 `skill_stance` 实例，未来再补 config-level `unique_by_config` 合同。

---

# 4 · Demon Form #15

**设计卡**：passive，每 3s 永久 +2 atk，无上限。

## 4.1 调研结论（关键澄清）

设计卡 §9「方案 B：Resolver 读 stacks」是**过时伪码**。本质 =「每 3s 给 atk 加一个 +2 的 ADD_BASE modifier」。`raw_attribute_set.add_modifier()`（:216）是现成公共 API。**无需用 stacks 做动态伤害/属性 resolver，也无需新组件 / 新 API**。periodic 驱动照 poison_buff（GRANTED_SELF + `TimelineData.periodic`）。stacks 只作为 tick 次数 / UI 显示 / modifier id 确定性计数。

按 §0.0 Action 分层合同，Demon Form 不新增 public `DemonFormTickAction`。tick 过程是 `buff_demon_form` 私有 routine，写成 `demon_form_buff.gd` 内嵌 `_DemonFormTickAction extends Action.SkillLocalAction`。

## 4.2 文件清单

| 文件 | 新建/改 |
|---|---|
| `logic/buffs/demon_form_buff.gd` | 新建：含 `_DemonFormTickAction` SkillLocalAction |
| `logic/skills/all_skills.gd` | 改(+1 buff，带 tick timeline) |
| `tests/battle/skill_scenarios/demon_form_scenario.gd` | 新建 |
| `docs/skills/skill-implementation-progress.md` | 改 |

## 4.3 数值常量表

| 常量 | 值 |
|---|---|
| CONFIG_ID | `buff_demon_form` |
| TICK_TIMELINE_ID | `buff_demon_form_tick` |
| TICK_INTERVAL_MS | `3000.0` |
| ATK_PER_TICK | `2.0`（ADD_BASE atk） |
| 上限 | 无 |
| 挂载方式 | passive（scenario 用 `get_passives()`；demo 可绑某职业，评审定） |

## 4.4 代码骨架

`demon_form_buff.gd` 内嵌 SkillLocalAction（用 ability.stacks 仅作确定性计数器，保证 modifier id 唯一可重放）：
```gdscript
class_name HexBattleDemonFormBuff
const CONFIG_ID := "buff_demon_form"
const TICK_TIMELINE_ID := "buff_demon_form_tick"
const TICK_INTERVAL_MS := 3000.0
const ATK_PER_TICK := 2.0

class _DemonFormTickAction:
	extends Action.SkillLocalAction

	func _init() -> void:
		super._init(HexBattleTargetSelectors.ability_owner(), CONFIG_ID)
		type = "demon_form_tick"

	func _execute_local(ctx: ExecutionContext) -> ActionResult:
		var ability := ctx.ability_ref.resolve() if ctx.ability_ref != null else null
		if ability == null or ability.is_expired():
			return ActionResult.create_success_result([], {})
		var battle: HexWorldGameplayInstance = ctx.game_state_provider
		var actor := battle.get_character_actor(ability.owner_actor_id) if battle != null else null
		if actor == null:
			return ActionResult.create_success_result([], {})

		var stacks_before := ability.get_stacks()
		ability.add_stacks(1)
		var n := ability.get_stacks()
		var raw := actor.attribute_set.get_raw()
		raw.add_modifier(AttributeModifier.create_add_base(
			"%s_%d" % [ability.config_id, n], "atk", ATK_PER_TICK, ability.id))
		ctx.event_collector.push(GameEvent.AbilityStacksChanged.create(
			ability.owner_actor_id, ability.id, ability.config_id, stacks_before, n).to_dict())
		return ActionResult.create_success_result([], { "demon_atk_bonus": n * ATK_PER_TICK })

static var DEMON_FORM_TICK_TIMELINE := TimelineData.periodic(TICK_TIMELINE_ID, TICK_INTERVAL_MS)

static var DEMON_FORM_BUFF := (AbilityConfig.builder()
	.config_id(CONFIG_ID).display_name("恶魔形态")
	.description("每 3 秒永久 +2 攻击力，无上限")
	.ability_tags(["buff", "positive"])
	.stacks(0, 999999, Ability.OVERFLOW_CAP)
	.component_config(ActivateInstanceConfig.builder()
		.trigger(TriggerConfig.GRANTED_SELF)
		.timeline_id(TICK_TIMELINE_ID)
		.on_timeline_end([_DemonFormTickAction.new()])
		.build())
	.build())
```
`all_skills.gd`：`arr.append(_Entry.new(HexBattleDemonFormBuff.DEMON_FORM_BUFF, [HexBattleDemonFormBuff.DEMON_FORM_TICK_TIMELINE]))`

## 4.5 scenario

caster 挂 DemonFormBuff（`get_passives`），无敌人或弱敌防早死，跑足 ~10s（max_ticks 调够）。断言：caster `atk` 终值 = 初始 atk + floor(经过 ms / 3000) × 2。可用 `final_actor` 属性快照或对 enemy 的伤害递增间接验证（scenario 无属性断言则打木桩看伤害台阶）。
> ⚠️ scenario 断言 atk 需确认：ScenarioAssertContext 有无属性读取。无 → 用「打不死的木桩，看连续 Strike 伤害随时间升 2/3s」间接断。评审定断言策略。

## 4.6 新机制清单

**技能自身无新机制。** 依赖 §0.0 的 SkillLocalAction 合同；`add_modifier` 是现成公共 API；periodic 照 poison_buff；`_DemonFormTickAction` 无状态（计数走 ability.stacks）；0 新事件/schema/组件/API。唯一开放点：长跑 N 个 modifier 的序列化体积——V1 接受（几十个），如需 compact 是后续优化非 V1。

## 4.7 表演层

| 接入点 | 处理 |
|---|---|
| BUFF_REGISTRY | **必接 +1**：`buff_demon_form` short "D" 暗红 `Color(0.6,0.1,0.1)`，PrimarySource.STACKS（显示叠层数=已 tick 次数） |
| StageCue / default_registry / projectile | 不接 / 不动 / N/A |

> **评审意见**：（待填）

---

# 5 · Summon Totem #16（spike 门，非直接 impl）

**设计卡**：召唤图腾 actor，低 HP、不移动、每 3s 攻击最近敌人、TTL 15s 或被打死。

## 5.1 为什么是 spike 门

3 个框架级未知，未查清不能写 impl 方案：

1. **战斗中途 add_actor 能否被 ATB/AI 驱动**：procedure 只 iter `get_alive_characters()`（CharacterActor）+ `ai_strategy.decide()`。图腾若非 CharacterActor 不会自动行动。
2. **中途新 actor 的 recording 完整性**：`setup_recording` 在 actor 何时挂？战斗中途加入的 actor 录像是否完整、replay 是否 bit-identical。
3. **TTL → remove_actor 通路**：`TimeDurationConfig` 只让 ability expire，不 remove actor 本体。需要「ability expire → battle.remove_actor」的通路，目前无落地参考。

## 5.2 Spike 计划（throwaway，断言框架原语而非图腾行为）

**spike scene**：`tests/battle/smoke_summon_spike.tscn`（spike 完可删/转正）

| spike 断言 | 验证点 |
|---|---|
| 战斗第 N tick 用 `battle.add_actor(EnvironmentActor.new(...))` + `grid.place_occupant` | 中途 add 不崩、grid 占位生效 |
| 一个 CharacterActor 中途 add + `set_team_id` + `equip_abilities` + 进 alive_actors | 是否自动进 ATB/AI 循环并行动 |
| 该 actor 的 grant/damage 事件出现在 replay | recording 是否覆盖中途 actor |
| `battle.remove_actor(id)` 后 grid 释放、无悬挂引用、replay 收尾正常 | TTL 自毁可行性 |
| 同 seed 跑 2 次 replay bit-identical | 中途增删 actor 不破确定性 |

**spike 产出 = 一份结论**写入本节「Spike 结论」，据此二选一：
- **路线 A**：图腾 = 低 HP CharacterActor（新「图腾」职业配置 + 简化 ai_strategy）→ 复用整套 ATB/AI/技能链
- **路线 B**：图腾 = 新 SummonActor 子类，自带 periodic auto-attack timeline（绕开 ATB），procedure 加最小驱动钩子

spike 绿后再出**正式 impl align 方案**（补本节），走 TDD（`lomo-kits:tdd` / `lomo-kits:smoke-test`）。

## 5.3 预判新机制清单（spike 后确认/收敛）

- 图腾 Actor 载体（新职业配置 或 新 SummonActor 子类）
- TTL → remove_actor 通路（若抽 `RemoveActorAction`，必须作为 Primitive Action 登记；图腾 TTL 自毁过程是 SkillLocalAction / ability lifecycle 逻辑）
- `ActorSummonedEvent`（新 event type，若 demo/replay 需要区分召唤）
- `SpawnActorAction`（Primitive Action，若 spike 证明中途 add_actor 可行）；图腾自身 summon 过程不新增 public `SummonTotemAction`，写成 SkillLocalAction
- 图腾 auto-attack ability（优先复用 Strike / DamageAction；若需要特殊 AI 行为，放图腾 controller / SkillLocalAction，不新增半公开业务 Action）

## 5.4 表演层（spike 后定）

新 unit visualizer（图腾形态）可能需进 `default_registry`；`ActorSummonedEvent` 视觉。spike 不接表演层（纯框架探针）。

> **评审意见**：（待填）

---

## 落码前总检查（每个技能批准后逐条过）

- [ ] 该节「评审状态」= ✅
- [ ] submodule 内实现 → commit；外层 bump 指针（分阶段即提）
- [ ] `smoke_skill_scenarios` 全绿；PreEvent/damage 类 **重跑 5 次**稳定
- [ ] 表演层 §7.1 逐项勾完或显式声明跳过
- [ ] 回写 `skill-implementation-progress.md`（状态/落地名/文件/scenario/Pattern 速查/偏离记录/日期/下一个建议）
- [ ] `enforcing-lgf` Validation Checklist 过
