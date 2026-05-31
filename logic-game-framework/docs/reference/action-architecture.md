# Action 架构契约

> 本文是 Action 体系的**长期参考契约**，提炼自基础设施设计文档。它只记录稳定的分层约定、边界与设计取舍（"为什么"），不含落码顺序、文件清单或阶段计划。新增技能 / 机制必须遵守这里的契约。

---

## 一、Action 四层分层合同

`Action` 体系按四层理解和约束。核心目的：把 "Ability 过程入口" 与 "底层副作用原语" 拆清楚，避免每个复杂技能都新增半公开业务 Action，也避免把机制藏进单个技能里。

| 层 | 是否继承 Action | 是否可进 timeline | 语义 | 例子 |
|---|---|---|---|---|
| **Util / Utils** | 否 | 否 | 最底层结算 / 副作用函数；不负责 target selector / timeline adapter | `HexBattleDamageUtils.apply_damage` |
| **Primitive Action** | 是 | 是 | 领域原语 adapter；薄封装 target selector / resolver / util；不知道具体技能 | `DamageAction`、`LaunchProjectileAction`、`ApplyBuffAction`、`LooseTagAction`、未来 `SpawnActorAction` |
| **FlowAction** | 是 | 是 | 流程组合器；只组织 child actions，不承载业务语义 | `FlowAction.if_` |
| **SkillLocalAction** | 是 | 是 | 技能私有过程函数；只服务一个 Ability，可组织 Primitive/Flow 或直接调用 Util | `_DemonFormTickAction`、`_ShadowStepTeleportAction` |

### 基类选择

`Action.BaseAction` 是 framework internal abstract substrate，**不再作为应用层直接继承入口**。新增业务 Action 必须选择更具体的语义基类：

| 基类 | 用途 | 额外约束 |
|---|---|---|
| `Action.PrimitiveAction` | public 领域原语 adapter | 必须登记 public primitive allowlist / index |
| `Action.FlowActionBase` | 流程组合器 | 必须声明 child actions，业务逻辑不得放在这里 |
| `Action.SkillLocalAction` | 技能私有过程函数 | 必须绑定 owner `config_id`，运行时 assert 当前 ability 匹配 |

### 层与层之间的硬边界

- **应用层禁止新增 `extends Action.BaseAction`**。core 内部基类与既有历史类暂时走 allowlist，后续 cleanup 分批迁移到 `PrimitiveAction` / `FlowActionBase` / `SkillLocalAction`。
- **Util / Utils 层**：只做结算 / 副作用，不负责 target selector / timeline adapter。真正底层结算沉到这里；Action 不重复实现跨来源管线（例如伤害仍走 `HexBattleDamageUtils`）。
- **Primitive Action 层**：薄封装，不知道具体技能。简单技能可以直接在 timeline 上组合 Primitive Action，不强制包一层 local action。
- **FlowAction 层**：只能表达流程，不放技能业务逻辑。当前只批准 `FlowAction.if_`，不先扩 `sequence` / DSL / VM。
- **SkillLocalAction 层**：只服务一个 Ability。复杂技能用 SkillLocalAction 表达自身过程，不为了单个技能新增 public Primitive Action。若 SkillLocalAction 引入基类，必须声明 `owner_config_id` 并在 `execute()` 时 assert 当前 `ctx.ability_ref.config_id` 匹配；owner mismatch 用 `Log.assert_crash`，不 silent fail。
- **跨时间响应**（Projectile / summon / delayed hit）继续走 event-driven，不用 Action callback 平行系统。

### Child action 执行不变量（原子性 / freeze / verify）

- FlowAction / hook / composite 调用 child action 时**必须走统一 helper**：`Action.execute_child(parent_action, child_action, ctx)`（或同等命名）。helper 内部负责 `child.execute(ctx)` + `child._verify_unchanged()`。禁止各处手写漏 verify。
- 持有 child actions 的 Action 必须让 child 参与 `_freeze()`；优先由 `BaseAction.get_child_actions()` 统一处理，减少手写遗漏。
- 这一约束源于 Action 是**共享无状态对象**：执行后必须 verify 未被改写，child 必须随父一起 freeze，否则状态会泄漏到下一次执行。

### 命名约定不足以约束 AI 生成 —— validator 兜底

仅靠命名约定无法约束 AI 生成代码，因此分层合同由一个轻量 validator 作为新增技能 / 新机制的门禁，硬化以下边界（file-grep + light parse 即可，不要求完整 GDScript AST）：

- `core/actions` / `stdlib/actions` / `example/*/logic/actions` 下新增 `class_name .*Action` 视为 public Primitive Action，必须进入 allowlist 或登记表 —— 避免 AI 把技能专用 Action 放进 public action 目录。
- `example/**` / `stdlib/**` 新增 Action 不允许直接 `extends Action.BaseAction`；必须继承 `PrimitiveAction` / `FlowActionBase` / `SkillLocalAction`。
- skill / buff 文件内允许内嵌 `_XxxAction` 作为 SkillLocalAction；这类 local action **不允许使用 `class_name`**。
- child action 必须经统一 execute-helper 调用（保证 freeze / verify）。
- legacy `TagAction` 的新用法告警。
- `execution_state` key 必须带 namespace（`<namespace>.<field>`）。
- allowlist 每条必须写明原因与 `migrate_by` 备注。

---

## 二、各机制的设计契约与边界

### Tag 语义拆分：`LooseTagAction` + `TagComponentConfig`

**契约**：`TagContainer` 有三种 tag 来源，API 命名与文档必须反映这个语义，不能混名。

| 来源 | 写入方式 | 生命周期 | 适用场景 |
|---|---|---|---|
| loose tag | `LooseTagAction.Apply/Remove` 或 `AbilitySet.add_loose_tag/remove_loose_tag` | 手动添加 / 移除 | Stance 这种可切换、可由 action 修改的运行时状态 |
| auto-duration tag | `add_auto_duration_tag` | 计时自动清理 | 短时、按 tag 层独立过期的状态 |
| component tag | `TagComponentConfig` → `TagComponent` | 随 Ability 实例 grant/remove 自动添加 / 清理 | `status_action_lock` 这种 "Ability 存在期间天然拥有" 的标签 |

**为什么拆**：旧 `TagAction` 名字过宽 —— `ApplyTagAction` / `RemoveTagAction` 实际只修改 loose tag，`HasTagCondition` 又读取聚合 tag，三种语义混在一起。收敛方向：

- `LooseTagAction` 只承载 loose tag mutation（`Apply` / `Remove`）。
- 聚合 tag 查询**不放进** `LooseTagAction`。主动技能条件用 `Condition.HasTagCondition` / `NoTagCondition`；action flow 内需要判断时用 `FlowAction.if_(predicate, ...)`。
- component tag 配置统一用 core 层 `TagComponentConfig`（创建 `TagComponent`），不在 example 写局部 `StatusTagConfig`。
- 旧 `TagAction` 降级为 legacy / `@deprecated` 兼容 facade；新代码不再用旧名。

**边界**：
- `TagComponentConfig` 不用于 Stance 切换；它写的是 component tag，随 Ability 实例生命周期清理。
- `LooseTagAction` 不用于 `status_action_lock` 的 `cant_act` —— 否则多个 action lock 实例重叠时，remove loose tag 容易误删其它来源。
- `NoInstanceConfig.on_apply_actions/on_remove_actions` 可以执行 `LooseTagAction`，但这表达的是 "Ability 生命周期触发 loose tag mutation"，不是 component tag。
- 需要 component tag 时一律用 core `TagComponentConfig`，避免 `StatusTag` / `LooseTag` / 聚合查询三种语义继续混名。

---

### `FlowAction.if_`

**契约**：通用 Action flow 组合器，支持 hook 后条件分支。它**不改** `Action.BaseAction.execute()` 合同，不加 `should_execute`，也不新增专用 `XxxConditionalAction`。

签名形态：

```gdscript
FlowAction.if_(predicate, then_actions, else_actions := [])
```

- `predicate` 语义是 `func(ctx: ExecutionContext) -> bool`。实现可保持 `Callable` 形态，但返回值必须是 `bool`；返回 `null` / `int` / 其它类型时用 `Log.assert_crash`，不把 `nil` 静默当 false。
- `then_actions` / `else_actions` 允许为空数组，语义是 selected branch no-op（用于占位 hook 或 "条件不满足不做事"），不需要额外空 Action。
- 只执行被选中的 branch，按数组顺序执行 child actions。
- child action 必须经 `Action.execute_child(parent_action, child_action, ctx)` 执行。若 child 返回 failure，`IfAction` 停止当前 branch 后续 action 并返回 failure，已产生的 event_dicts 保留在 failure result 中；**不做 best-effort 全跑**。
- `ActionResult.data` 只合并 `FlowAction` 自己的元信息（例如 branch），**不把 child data 自动提升为公共合同**；技能需要跨 tag 状态时用 execution-local state（见下）。

---

### Character logic-facing V0

**契约**：新增 `CharacterActor.facing_direction`，但**不放进** `RawAttributeSet`，也**不放进** `HexBattleActor` 基类。`EnvironmentActor` 默认没有 facing；未来只有炮塔、传送带、喷火陷阱这类确实有方向语义的环境物才单独 opt-in。

V0 只做**瞬时逻辑朝向**，不引入 turn speed / turn duration / facing lock：

| 时机 | 规则 |
|---|---|
| 初始站位 | A 队默认朝东，B 队默认朝西 |
| 主动移动 | face toward destination |
| 主动攻击 / 施法 | face toward target |
| forced displacement（push/knockback/pull） | 不改变 facing |
| 被攻击 | 不自动转向 |
| Shadow Step | caster 落地后 face target；target facing 不变 |

事件合同：

```gdscript
ActorFacingChangedEvent(
	actor_id,
	old_direction,
	new_direction,
	reason
)
```

- 前端只消费事件做 visual-facing 平滑转向；logic-facing 已在事件产生时瞬时生效。
- `HexFacing.face_actor_toward` 是唯一推荐 setter：先更新 `CharacterActor.facing_direction`（source of truth），再 push `ActorFacingChangedEvent`。逻辑读到的 facing 永远是最新值，事件只作为 audit / presentation。
- 主动技能 / 攻击的 facing 更新集中在 active-use execution 创建入口（从 current target 取 hex position 调 `HexFacing.face_actor_toward`），避免每个技能手写。单个技能只在特殊语义时自己调用（如 Shadow Step 落地后 face target）。

位移类 action 按 displacement kind 分流：

| kind / 来源 | 是否改 facing |
|---|---|
| player/AI move、`StartMoveAction` / `ApplyMoveAction` 主动移动 | 是，face toward destination |
| push / knockback / pull 等 forced displacement | 否，displacement action 只发 `ActorDisplacedEvent` |
| teleport | 默认否；由调用方决定（Shadow Step 成功落地后自己 face target） |

**边界**：`EnvironmentActor` V0 不加 facing 字段。未来炮塔 / 喷火陷阱需要方向时，优先引入 `IFaceable` / `DirectionalEnvironmentActor` 这类 opt-in 形态，**不要把 `facing_direction` 回填进 `HexBattleActor` 基类**。

---

### Ability execution-local state

**契约**：每个 `AbilityExecutionInstance` 持有一份 execution-local state 字典。state 的 **owner 是 `AbilityExecutionInstance`**；`ExecutionContext` 不拥有这份状态，只在执行同一次 execution 的 action 时携带同一份字典引用作为访问入口。它表达 "同一次施法前段结果影响后段" 的短生命周期状态，**不用于跨施法 / 永久状态**。

**为什么需要**：例如 Shadow Step 在 `CAST` tag 完成瞬移后写 `shadow_step.teleport_success=true`，`HIT` tag 再由 `FlowAction.if_` 读该值决定是否造成伤害。

- 不能把这个状态放在 `Action` 自身 —— Action 是共享无状态对象。
- 也不能只放 `ActionResult` metadata —— 后续 tag 看不到前一个 tag 的返回值。

机制形态：
- 同一次 execution 的 `CAST` / `HIT` / `END` 每次创建新的 `ExecutionContext`，但共享同一份 `execution_state` 字典。
- `ExecutionContext.create_callback_context(...)` 也要携带同一份 `execution_state`，避免 action hook 里丢失本次 execution 状态；它可以继续不继承 `execution_info`（hook 里需要保留的是 event chain / ability_ref / execution_state）。
- 每次技能释放创建新的 `AbilityExecutionInstance`，因此不同施法之间天然隔离。
- **不保存完整 `ActionResult` 历史**。`ActionResult.event_dicts` 已进入 `EventCollector` 供 replay/presentation 消费；`ActionResult.data` 语义不稳定，跨 tag 复用会把 action 局部返回值升级成框架级状态，属于过度设计。

**使用约束**：
- key 必须带技能 / 机制命名空间（如 `shadow_step.teleport_success`）。优先用 `ctx.set_execution_state(...)` / `ctx.get_execution_state(...)` helper，并 assert key 包含 `.`。
- value 只放可序列化的轻量数据；坐标用 `HexCoord.to_dict()`，**不直接塞 Actor / Resource 引用**。
- **replay 合同采用 "重 execute 推导" 路径**：execution_state 是 transient scratchpad，事件流不记录它；replay 通过同 seed、同事件输入、deterministic action 再次执行自然重建。只有需要 presentation/debug 可观察的字段，才额外写进 event `customData` 或新增显式 event。
- 因此写 execution_state 的 action 必须 **deterministic** —— 不能读当前帧 wall-clock、随机数或外部 mutable singleton。若未来需要 mid-timeline snapshot/replay 恢复，`AbilityExecutionInstance.serialize()` 需包含这份字典，或新增 `ExecutionStateSetEvent` 类事件切到事件驱动恢复。
- 长期状态仍放 `AbilitySet.tag_container` / actor state，**不放 execution-local state**。

---

### `DamageAction` dead / invalid target no-op

**契约**：`HexBattleDamageAction.execute()` 的 per-target 循环入口有一道通用 guard —— 目标不存在或已死亡时 no-op：不产生 damage event、不扣负 HP、不触发 post damage、也不触发 on-hit / on-kill callback。

```gdscript
for target_id in targets:
	var target_actor := battle.get_actor(target_id)
	if target_actor == null or target_actor.is_dead():
		continue
	# 之后再进入 PreDamageEvent / apply_damage / callbacks / post damage
```

**为什么是通用合同而非 Shadow Step 特判**：死亡 actor 当前会留在 world 里用于前端死亡动画 / buff 对账。若继续允许 DamageAction 打死者，短期不会重复 `DeathEvent`，但会产生尸体 damage event、继续扣负 HP，并可能误触发未来 lifesteal / damage counter / hit proc 等 post 逻辑。

- 这道 guard 放在 `DamageAction` 层，**不放在每个 skill 的 `FlowAction.if_` predicate 里**。skill predicate 只表达技能自己的 gating（例如 Shadow Step 的 `teleport_success`）。

**callback 边界**：
- `on_hit` 只在本次 DamageAction 对一个 alive target 实际完成伤害结算后触发。
- `on_kill` 只在本次 DamageAction 把 alive target 从 `hp > 0` 打到 `hp <= 0` 时触发；对已死亡 target 的 no-op 不触发 on-kill。
- guard 使用 hex damageable actor 的统一 alive/dead 谓词，优先复用 `HexBattleActor.is_dead()`。若后续 `EnvironmentActor` 出现 destroy/dead 分叉，再补 `is_alive()` / `is_destroyed_or_dead()` 统一接口，**不让 DamageAction 分散判断具体子类**。
- V1 silently skip，不新增 `SkillTargetSkippedEvent`；未来需要命中遥测或 UI 提示再补显式 skip event。

---

### `NoInstanceConfig` lifecycle actions

**契约**：`NoInstanceConfig` / `NoInstanceComponent` 支持 Ability lifecycle 上的 action 组合：

```gdscript
NoInstanceConfig.builder()
	.on_apply_actions([...])
	.on_remove_actions([...])
	.build()
```

**为什么需要**：这不是 Stance 专用机制，而是补齐框架里 "Ability grant/remove 时执行一组无 timeline action" 的通用表达能力，避免每个技能为了初始化 / 清理 loose tag、标记或轻量状态都新增业务 component。

**合同**：
- 现有 event trigger 语义不变：`trigger(...) + actions(...)` 仍表示 "事件匹配后立即执行 actions，不创建 timeline instance"。
- 新增 lifecycle actions 不要求 trigger；`build()` 允许 lifecycle-only config。
- 但若配置了普通 `actions(...)`，仍必须配置至少一个 trigger，避免无触发事件的 action 静默无效。
- lifecycle actions 构造一个仅用于执行的 `ExecutionContext`：带 `ability_ref`、`event_collector`、空 / 内部 lifecycle event dict；`game_state_provider` 可为 `null`。
- lifecycle actions 适合 `LooseTagAction` 这类只依赖 owner / ability / tag_container 的轻量 action；**不应**用来发 projectile、移动 actor 或做需要 battle provider 的行为。运行时若 lifecycle action 读取缺失的 `game_state_provider`，应 `Log.assert_crash` 给出明确错误。
- 不新增 `GameEvent`，不把 lifecycle action 本身写入 replay；若 action 修改 tag，既有 `RecordingUtils.record_tag_changes()` 会记录 tag 变化。
- 同一个 `NoInstanceConfig` 内 action 数组按声明顺序执行；同一 Ability 的多个 component config 按 `AbilityConfig` 声明顺序构建 / 执行 lifecycle hook。

**触发表**：

| 场景 | 是否触发 `on_remove_actions` | 说明 |
|---|---|---|
| duration / expire 导致 Ability remove-effects | 是 | 走 Ability remove/effects 清理链 |
| `AbilitySet.revoke_ability` / 显式 remove | 是 | Stance remove 清理 Wrath/Calm 依赖这个路径 |
| actor death | 当前不自动触发 | hex 死亡 actor 会留在 world/recording 中用于死亡动画和对账；除非未来 death cleanup 显式 revoke abilities，否则不要假设 death 会清 loose tag |

---

### Validator 的定位

**契约**：分层合同与上述各机制的边界**不能只靠命名约定或文档**约束，由一个轻量 validator 作为新增技能 / 新机制的门禁。

- 工程上按 light parse / grep 实现，**不等完整 GDScript AST**。
- 它是**新增代码门禁**，不强制一次性迁移旧 `PoisonTickAction` / `SurgeTickAction` 等历史类 —— 这些走 allowlist 临时豁免，标为后续 cleanup 项。
- 第一版目标是硬化 AI 生成代码的边界：public Action 归类、禁止 app/example 直接继承 `BaseAction`、child action 必须 freeze / execute-helper、legacy `TagAction` 新用法告警、`execution_state` key namespace 检查。
- allowlist 每条必须写明原因与 `migrate_by` 备注，避免豁免无限期沉淀。
