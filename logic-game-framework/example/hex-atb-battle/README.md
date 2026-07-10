# Hex ATB Battle 示例

Logic Game Framework 的**回合制 / ATB + hex grid** 战斗示例，也是框架的首要参考实现。一局 6v6（priest / warrior / archer / mage / berserker / assassin 六职业）在 9×9 六边形格子上以 ATB 节奏自动交战；技能用 Timeline keyframe 驱动 Action，前端响应式观察 world 播放表演。除完整 demo 外，还含 **skill-preview 沙盒**（单技能演示 + AI 生成技能验证）。

定位：**技能机制展示 + AI 技能沙盒**，不是可平衡的竞技对战。设计取舍按"范式一致 / 可预测 / 可 introspect"而非"数值公平"衡量。

## 架构

三层单向依赖（详见框架 [`docs/README.md`](../../docs/README.md) 的"逻辑表演分离架构"与"World owns Battle + 响应式前端"两节）：

| 层 | 目录 | 职责 | 说明 |
|---|---|---|---|
| **core**（共享） | `core/` | 强类型事件定义 | `events/battle_events.gd`。见 [`core/README.md`](core/README.md) |
| **logic**（逻辑） | `logic/` | WorldGI / procedure / 战斗规则 / 技能 / actor | `HexWorldGameplayInstance`（hex world 基类）、`HexDemoWorldGameplayInstance`（demo 行为）、`HexBattleProcedure`（ATB / AI / 胜负）、`abilities/`、`hex_battle_actor.gd` |
| **frontend**（表演） | `frontend/` | 响应式 view + 事件动画 | `FrontendWorldView`（观察 world 结构）、`FrontendBattleAnimator`（消费 event timeline）。见 [`frontend/README.md`](frontend/README.md) |

- **World owns Battle**：`HexWorldGameplayInstance` 持有 actor / grid / systems；战斗是短命的 `HexBattleProcedure`。每个场景（demo / skill-preview）有自己的 `HexWorldGameplayInstance` 子类（`HexDemoWorldGameplayInstance` / `SkillPreviewWorldGI`），框架基类保持通用。
- **逻辑→表演数据流**见 [`logic/docs/logic-to-presentation-guide.md`](logic/docs/logic-to-presentation-guide.md)（StageCue 事件、Timeline 配置）。

## 设计铁律

hex 演进中固化的不可违反约束：

- **死亡 ≠ 离开 world**：hp ≤ 0 时只清 grid footprint（`_clear_grid_footprint` in `hex_battle_damage_utils.gd`），**绝不**调 `world.remove_actor` —— actor 留在 registry（`is_dead()=true`、behavior 禁用、`hex_position` 保留），给复活 / 救起 / 亡语 / 尸爆留路。逻辑实例 / grid 占用 / view 三维度独立配置，不绑成"清=全清"。
- **每个场景拥有自己的 `HexWorldGameplayInstance` 子类**：demo 战斗行为（grid 配置 / 六职业 / 随机放置 / inspire buff / 战报 / 录像）封装在 `HexDemoWorldGameplayInstance`，框架基类保持通用 —— 不许把 demo 内容写进基类（污染分层）或 inline 复制到多个 entry（同步地狱）。新场景沿用"子类化"范式。
- **表演层 Event vs State 是根边界**：可每帧重复且幂等的（HP 条 / 闪白 / 染色 / 位置）走 State snapshot；重复执行会建节点 / 起 tween / 播音效 / 发粒子的（死亡动画 / 受击 / 暴击大字）走 transition-only Event —— 混用会导致一次性动画重复播放（详见下「事件 vs 状态边界」）。
- **Cast eligibility 走 declarative metadata，不进 Condition**："能不能对环境物 / 阵营 / 范围释放"用 ability metadata（`HexBattleSkillMetaKeys.ALLOWED_TARGET_KINDS`，默认 `["Character"]`），由 `can_use_skill_on()` 事前查询 —— AI / UI / tooltip / 玩家 cast 都需要事前过滤候选；Condition 是事件到达时的 reactive 判断，承载 cast 配置会变双源真相。**施法输入协议也是 cast 配置**：`TARGETING` metadata（`actor` / `coord` / `self`）声明 activate 事件带 `target_actor_id` 还是 `target_coord`，AI / UI 按它分派（不嗅探 "cone" 描述 tag）；ACTOR/SELF 合法性走 `can_use_skill_on`，COORD 走 `can_use_skill_at`。
- **目标选择三层分工（geometry 层强制共用）**：①合法性 = declarative metadata（上一条）；②**形状几何 = static 纯函数**——coord 型区域技能必须提供 `compute_checked_coords()`（grid_cone / angle_cone 范式），执行 selector 与前端预览 / overlay **只能调它**，不许各算各的（预览=实际覆盖区的单一真相源）；③执行期命中 = TargetSelector 专属（ATB 出手延迟决定占格 / 存活 / 阵营过滤必须在结算帧重解析）。UE/GAS 式"预览与执行公用 TargetActor"在此架构映射为只共用②层。
- **强制位移是原子逻辑操作**：`PushAction` 在单个 HIT keyframe 内完成 raycast / 碰撞 / `grid.move_occupant` / `hex_position` / 位移事件，发过去式单事件 `actor_displaced`，**不**向 timeline scheduler 暴露中间"被推中"态；"推完不能立即行动"靠目标侧 `HexBattleActionLockStatus`（`cant_act` tag）而非 scheduler 延迟。事件元数据（`actual_distance` 等）逻辑层算一次写入，前端 visualizer 直接消费不重算。
- **Gateway 是入口资格规则，不是效果执行**：Stun / Silence / Break 状态控制走 `ActiveGateway` —— 它在 active 入口处消费 component-owned 的 functional gate tag：`cant_act`（`action_lock_status.gd`，挡 Move / Strike / 所有 active skill）、`cant_use_skill`（`silence_buff.gd`）、`cant_use_passive`（`break_buff.gd`，仅查询用）。语义 tag（`stun` / `silence`）放 buff `ability_tags`、功能 gate tag 放 component tag，二者分离。Gateway 只挡入口、**不**自动 cancel in-flight execution（Stun 打断须显式组合 `CancelActiveExecutionsAction`）。target eligibility 仍走 ability metadata（`can_use_skill_on`），不进 gateway condition。
- **hex = 技能展示 + AI 沙盒，非可平衡对战**：balance 类"设计债"按"范式一致 / 可预测 / 可 introspect"验收而非"数值公平"，多数经评审撤销 / 降级（scaling vs flat 由技能自定、expose 指数叠加是有意设计、未播种 shuffle 不破坏契约因 hex replay = 事件流回放非 seed 重模拟）。真正的债是"约定一致性靠逐文件手抄、无共享 helper 固化标准技能骨架"（见下「未来规划」）。

<a id="event-vs-state"></a>
### 事件 vs 状态边界

表演层更新分两条互斥路径，混用会让一次性动画重复播放（实测：单位被普攻打死后 0.3s 亡语再命中，死亡动画并行播两次）。判断标准：**能每帧重复执行且结果幂等的走 State；重复执行会创建节点 / 启动 tween / 播音效 / 发粒子的走 Event。**

- **State —— 响应式 snapshot 观察（持续态）**：HP 条高度、闪白进度、染色、位置由 `RenderWorld` 发 `actor_state_changed(id, state)`，`FrontendBattleAnimator._on_actor_state_changed` 转发到 `UnitView.update_state(state)`，每帧赋值天然幂等。HP 条尤其走 state：`FrontendActorRenderState` 持 `visual_hp`（显示值）+ `target_hp`（伤害 / 治疗即时累加），伤害事件生成瞬时 `FrontendApplyHPDeltaAction`（duration=0），`RenderWorld.tick_hp_lerp` 每帧指数衰减追赶。
- **Event —— timeline transition 消费（一次性）**：死亡动画 / 复活 / 受击 / 暴击大字由 `RenderWorld` 发 transition-only event（如 `actor_died(id)`，只在 `was_alive && now_dead` 那帧 emit 一次，统一走 `_set_actor_alive` helper）。`FrontendBattleAnimator._on_actor_died` wire 到 `UnitView.play_death()`。
- **关键约定**：transition-only 是 **emit 端契约**（prev-state 对比保证只 emit 一次），下游 wire 无需做幂等；触发策略（once / retrigger / queue）是 **view 方法本地决定**（`play_death` 用 `_death_played` flag 挡重入）。Reset / Replay 复活属 session control，走 `FrontendBattleAnimator.reset()` 遍历 `view.revive()`，不污染 event bus。

> 战后还有一道 **View ↔ Logic 终态对账 oracle** 抓"漏 visualizer / 翻译错"漂移，详见 [`docs/reference/view-logic-reconciliation.md`](docs/reference/view-logic-reconciliation.md)。

## 技能模式速览

技能 / 被动全部落在 `logic/abilities/` 下，按生命周期分三类：

- **`active/`（~33 个主动技能）** —— 由 `ABILITY_ACTIVATE_EVENT` 驱动、走 Timeline 的可施放技能。代表：近战普攻 `strike`、追踪投射物 `fireball` / `precise_shot` / `chain_lightning`、瞬移 `shadow_step`、位移控制 `knockback_punch` / `swap`、形态切换 `stance`、召唤 `summon_totem`、锥形 AOE `angle_cone` / `grid_cone`、直线穿透 `piercing_line` / `wall_breaker`，以及 `poison` / `stun` / `silence` / `expose` / `holy_heal` / `lifesteal` / `execute` / `cleanse` / 护盾类 `physical_shield` / `magical_shield` 等。
- **`buffs/`（~11 个）** —— DOT / 增益 / 控制状态的自治 Ability：`poison_buff` / `stun_buff` / `silence_buff` / `expose_buff` / `inspire_buff` / `surge_buff` / `ward_buff` / `shield_buffs` / `action_lock_status` 等。层数语义来自 Ability 一级 `stacks`，tick 由 `ActivateInstanceConfig` + `GRANTED_SELF` periodic timeline 自驱。
- **`passives/`（~14 个）** —— 常驻 / 触发型被动：`demon_form`（每 3s 永久 +atk，tick timeline）、`vampiric_training`、`thorn`、`vigor` / `vitality`、`deathrattle_aoe`、`general_passive`、totem / fire-tile 系列，以及装备 grant 的 `daedalus_critical_strike`（监听 `PreBasicAttackEvent` 决定本次普攻暴击）。
- **`shared/`** —— 跨技能复用的 `cooldown_system.gd` / `skill_helpers.gd` / `buff_tags.gd`。

**通用技能结构**：每个主动技能 = 一段 **Timeline** + 挂在 keyframe tag（`CAST` / `HIT` / `LAUNCH` / `END`）上的 **Action**。`strike` 在 `HIT` 跑 `HexBattleDamageAction`；`fireball` 在 `LAUNCH` 发射弹体、再由独立 `*_HIT` timeline 结算伤害（弹体本身 0 HP 伤害）。

**标准主动门控四件套**：`NoTagCondition(cant_act)` + `NoTagCondition(cant_use_skill)` + `CooldownCondition` + `TimedCooldownCost(cd_ms)`。`shared/cooldown_system.gd` 提供 `HexBattleCooldownSystem.apply_standard_active_gating(builder, cd_ms)`（新技能统一入口）与 `apply_basic_attack_gating(...)`（普攻豁免 silence，ARPG/MOBA 惯例）。当前多数技能仍逐文件手抄这 4 行 —— 迁移到 helper 见下「未来规划」。

**伤害用 Resolver** 在 `execute()` 时按 ctx 解析：`HexBattleSkillHelpers.caster_atk_damage(mult)` 读 `caster.atk × mult`（让 buff / 装备对 atk 的修改自动生效），固定值伤害用 `Resolvers.float_val(x)`。

**Action 分层**（详见框架 [`docs/reference/action-architecture.md`](../../docs/reference/action-architecture.md)）：底层 Primitive（`HexBattleDamageAction` / `ApplyBuffAction` / `LaunchProjectileAction`）→ 流程控制 `FlowAction.if_(predicate, [...])`（如 `shadow_step` 仅瞬移成功时造伤）→ 技能私有 `SkillLocalAction` 子类（`_ShadowStepTeleportAction` / `_DemonFormTickAction` 等，不进 public action 注册表、不用 `class_name`）。

**skill-preview 沙盒 + SkillValidator**：技能可在独立战斗 world 里预览。AI 生成的技能脚本由主仓 `scripts/SkillValidator.gd` 做五级校验：Stage 1 编译 → Stage 2 接口 → Stage 3 运行 → Stage 4 结构 → Stage 5 进阶建议（warn-only，永不改 success；扫 determinism / cooldown / 缺失门控 / 缺失 range meta）。

## 未来规划

### 装备攻击特效

> Phase G V1（装备 grant passive、`PreBasicAttackEvent` / `BasicAttackLandedEvent` 边界、`attack_lifesteal_pct`、Daedalus 暴击 passive、`HexActorEquipmentContainer` grant/revoke）已落地；以下为尚未实现的前瞻点。

- **后置 on-hit 特效样例**：新增监听 `BasicAttackLandedEvent` 的装备 passive，验证「命中后上 buff / 追加伤害 / stage cue」路径（Daedalus 走 `PreBasicAttackEvent` 改本次普攻，覆盖不到后置链路）。
- **多攻击特效策略**：当一个 actor 同时持多个暴击 / on-hit 来源时再设计叠加规则（候选 `AttackEffectPolicy`：只允许一个 / 按 priority / 按最高倍率）；`PreBasicAttackEvent` 也仅在真实需求时再补 `damage_type` / `can_crit` / `guaranteed_crit` 字段。当前 V1 只保证单一 equipment-granted passive。
- **长期演化**：能力稳定且多 example 都需要这套「普攻前事件 + 命中事件 + 攻击特效策略」时，再上提到 LGF 框架层；仅当装备自身有 HP / cooldown / 可被战斗事件命中时，才把装备从「item + granted passive」升级为 Actor。

### 标准技能门控迁移

~28 个技能仍逐文件手抄门控四件套，应迁移到 `apply_standard_active_gating` helper（防漂移，非修 bug）—— 见框架 [`docs/README.md`](../../docs/README.md) 的"已知债务"。

## 文档索引

| 文档 | 内容 |
|---|---|
| [`docs/reference/damage-pipeline.md`](docs/reference/damage-pipeline.md) | 伤害结算 9 步流程 + damage event schema 各字段「该读哪个」对照 |
| [`docs/reference/shield-system.md`](docs/reference/shield-system.md) | 护盾 / on-damage-taken 反伤契约 |
| [`docs/reference/view-logic-reconciliation.md`](docs/reference/view-logic-reconciliation.md) | 战后 View ↔ Logic 终态对账 oracle 契约 |
| [`core/README.md`](core/README.md) / [`frontend/README.md`](frontend/README.md) | 分层架构说明 |
| [`logic/docs/logic-to-presentation-guide.md`](logic/docs/logic-to-presentation-guide.md) | StageCue 事件、Timeline 配置、数据流 |
