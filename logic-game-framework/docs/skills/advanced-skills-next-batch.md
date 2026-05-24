# Advanced Skills Next Batch - GeneralPassive + Cone AoE

> 本轮目标。Phase 2+ 的主动 `Lifesteal` 与 `Piercing Line` 已落地；本文现在记录下一轮要实现的角色内建规则与 AoE shape 机制。
> 目标是把“`HexBattleGeneralPassive` / 普攻吸血属性 / Cone AoE selector / skill-preview debug 区域 / facing 前端回归”收敛成可落码的 contract。

## Scope

本批次优先处理四个方向：

- `HexBattleGeneralPassive`：角色内建规则桥，只把角色属性转换成标准战斗效果，例如普攻吸血、生命恢复、未来法力恢复。
- 普攻吸血属性：`attack_lifesteal_pct` 由角色属性驱动，普攻命中后通过 `HexBattleGeneralPassive` 转换为标准 heal。
- Cone AoE：首次系统验证 AoE `TargetSelector`，对比“基于格子的扇形”和“基于真实锥形角度的范围”。
- skill-preview debug 区域 + facing 前端回归：补齐 AoE 检查区域可视化，以及之前 facing 机制缺失的渲染层回归。

装备系统接入与法球/攻击特效示例移入下一阶段文档：

- [equipment-attack-effects-next-stage.md](equipment-attack-effects-next-stage.md)

明确不做：

- 不实现无关 advanced skills。
- 不做纯 VFX polish。
- 不为对齐 `HexBattleDamageUtils` 提前抽取空壳 `HealUtils`。
- 不把 `basic_attack` / `move` 写进 LGF core 概念层。
- 不用 `config_id == "skill_strike"` 这类硬编码作为长期 contract。
- 不把 `HexBattleGeneralPassive` 当普通 `passive` 处理；它是角色内建规则桥，不应被 Break 禁用。
- 不在本轮实现装备系统接入 / 装备法球 / 攻击特效叠加策略。

## Current Baseline

已落地能力：

- 主动 `HexBattleLifesteal`：一个近战主动技能，命中后按 `DamageEvent.actual_life_damage * 0.5` 治疗 caster。
- `HexBattlePiercingLine`：沿 hex 方向命中线上的多个敌人。
- `Strike` / `Move` 目前仍是 `Ability`，并且由 `CharacterActor` 持有默认 ability id，用于 AI / UI / 玩家默认操作选择。
- `Silence` 当前不需要知道哪个 ability 是普攻或移动；它只提供 `cant_use_skill` 状态，具体 ability 是否受沉默影响由自己的 condition 决定。

## Implementation Phases

> 给 Claude Code 的执行拆分。每个 phase 尽量独立提交；跨 phase 共享 helper 可以在最早需要它的 phase 内落地。

### Phase A · Attack Event Foundation

目标：建立普攻命中事件边界，不实现吸血效果。

改动面：

- 新增 `AttackLandedEvent`。
- `Strike` 在标准 damage 结算后发出 `AttackLandedEvent`。
- `AttackLandedEvent` 至少包含：

```text
attacker_actor_id
target_actor_id
source_ability_id
source_ability_config_id
actual_life_damage
damage_event
```

验收：

- `Strike` 命中后出现 `AttackLandedEvent`。
- Fireball / Poison tick / reflected damage / Fire Tile / Totem passive damage 不产生 `AttackLandedEvent`。
- `actual_life_damage = 0` 时仍允许事件存在；consumer 自己 no-op。

建议测试：

```powershell
./tools/run_tests.ps1 hex/skills
```

### Phase B · GeneralPassive Attack Lifesteal

目标：实现 `attack_lifesteal_pct` 属性驱动的普攻吸血。

改动面：

- 新增 example-local attribute key：`attack_lifesteal_pct`，默认 `0`。
- 新增 `HexBattleGeneralPassive`，由 `CharacterActor.equip_abilities()` 自动 grant。
- `HexBattleGeneralPassive` 监听 `AttackLandedEvent`，读取 attacker 当前 `attack_lifesteal_pct`，调用 `HexBattleHealAction` 治疗 attacker。
- 新增最小属性来源示例，例如 `VampiricTraining` passive，只负责给 owner 增加 `attack_lifesteal_pct`。
- `Break` 不禁用 `HexBattleGeneralPassive`；但可以禁用提供属性的普通 passive。

验收：

- 默认 `attack_lifesteal_pct = 0` 时，普攻不回血。
- 增加 `attack_lifesteal_pct` 后，`Strike` 按 `actual_life_damage * pct` 回血。
- shield 全吸收 / `actual_life_damage = 0` 时不回血。
- active skill damage 不触发普攻吸血。
- Break 禁用提供属性的普通 passive 后，吸血停止；`HexBattleGeneralPassive` 本身仍存在。

建议测试：

```powershell
./tools/run_tests.ps1 hex/skills
```

### Phase C · GeneralPassive HP Regeneration

目标：实现 `hp_regen_per_sec` 自然恢复，不走 heal pipeline。

改动面：

- 新增 `hp_regen_per_sec` attribute，默认 `0`。
- 新增 `RegenerationEvent`。
- 新增 `HexBattleRegenerateAction`，只负责资源恢复结算与 replay event。
- `HexBattleGeneralPassive` 用 periodic timeline 读取 `hp_regen_per_sec` 并恢复 HP。
- 不实现 `mp_regen_per_sec`，只保留未来语义。

验收：

- `hp_regen_per_sec > 0` 时周期性恢复 HP。
- 恢复量 clamp 到 `max_hp`，记录 `actual_amount`。
- 不产生 `HealEvent`。
- 不触发 heal-related passive。
- Break 不禁用 `HexBattleGeneralPassive`，但可禁用提供 regen 属性的普通 passive 来源。

建议测试：

```powershell
./tools/run_tests.ps1 hex/skills hex/regression
```

### Phase D · Cone AoE Logic

目标：实现两个基于 `target_coord` 的 AoE selector，不做 frontend debug overlay。

改动面：

- 新增 `skill_grid_cone`。
- 新增 `skill_angle_cone`。
- 支持 active skill 使用 `target_coord` 释放。
- 如需要，补 example 层 `can_use_skill_at_coord()`；不要把 coord targeting 塞进 actor-only `can_use_skill_on()`。
- `GridConeSelector`：取 caster range 内所有格，按 `{cast_dir - 1, cast_dir, cast_dir + 1}` 三方向 sector 过滤。
- `AngleConeSelector`：`range=3`、`half_angle_deg=45`，用 `coord_to_world()` 真实角度判断。
- `target_coord == caster.hex_position` 是 caller contract 错误；实现应暴露 error / assertion，不做保护性 fail/no-op，不 fallback 到 facing。

验收：

- 两个 cone 都复用 `HexBattleDamageAction`，多目标产生多个标准 `DamageEvent`。
- 同一站位下，`skill_grid_cone` 与 `skill_angle_cone` 命中集合可区分。
- 至少证明一个目标在 grid cone 内但 angle cone 外。
- hit order deterministic。

建议测试：

```powershell
./tools/run_tests.ps1 hex/skills
```

### Phase E · Skill-Preview Debug Shape

目标：让 skill-preview / frontend 能看到本次 AoE 检查区域。

改动面：

- Cone skill 的 `StageCueAction.params` 写入 selector debug payload。
- payload 使用：

```text
shape
origin_coord
target_coord
checked_coords
range
cast_direction / direction_sector
half_angle_deg
```

- skill-preview / frontend 增加轻量 debug overlay，短暂绘制 `checked_coords`。
- frontend 只消费 payload 绘制，不反推 selector。

验收：

- `StageCue.params.checked_coords` 与 selector 计算区域一致。
- `targetActorIds` 仍只表示实际命中 actor。
- skill-preview 播放 cone 技能时能看到检查区域。

建议测试：

```powershell
./tools/run_tests.ps1 hex/skills hex/frontend
```

### Phase F · Facing Frontend Regression

目标：补齐既有 facing 机制的渲染层回归，不绑定 Cone 技能通过条件。

改动面：

- replay 初始化读取 actor snapshot 中的 `facing_direction`。
- `actor_facing_changed` 回放时更新 `FrontendActorRenderState.facing_direction`。
- `FrontendUnitView` 增加轻量朝向箭头 attached visual，只对 `CharacterActor` 显示。
- 不做 turn speed / facing lock / 复杂转身动画。

验收：

- 初始 A 队朝东、B 队朝西的箭头可见。
- 主动攻击/施法产生 facing change 后，箭头随 replay 更新。
- forced displacement 不改变 facing，箭头不转。

建议测试：

```powershell
./tools/run_tests.ps1 hex/frontend
```

### Phase G · Final Regression + Docs

目标：整体验收并清理文档状态。

验收：

- 本文 Open Questions 已处理或明确留作 follow-up。
- `equipment-attack-effects-next-stage.md` 仍保持下一阶段，不被本轮实现污染。
- 新增 scenario / frontend smoke 已纳入测试组。

建议测试：

```powershell
./tools/run_tests.ps1 core/unit hex/skills hex/regression hex/frontend
```

## Phase F · Lifesteal / 吸血

> 历史锚点保留。原 Phase F 主动吸血技能已完成；下一轮关注的是“普攻吸血属性”，不是再做一个主动吸血技能。

### 新目标：普攻吸血属性

期望形态：

```text
角色身上有 attack_lifesteal_pct 属性。
被动或 buff 可以修改该属性。
普攻造成实际生命伤害后，HexBattleGeneralPassive 按 actual_life_damage * attack_lifesteal_pct 治疗攻击者。
```

建议规则：

- 只由普攻触发，不由 Fireball / Poison tick / reflected damage / Fire Tile / Totem passive damage 触发。
- shield 全吸收时 `actual_life_damage = 0`，不回血。
- 部分 shield / 减伤 / 易伤 / 暴击后，按最终实际生命伤害回血。
- target 剩余 HP 小于伤害时，应只按实际扣掉的生命值回血；实现前需要确认 `actual_life_damage` 是否已经 clamp 到目标剩余 HP。
- overheal 继续走现有 heal clamp 规则，不新增 overheal 护盾。
- 普攻吸血是攻击者自己的属性驱动效果，不写入 `Strike` 的硬编码分支。

### Contract 决策

普攻 / Move 继续是 `Ability`，但特殊性分两层：

- `CharacterActor` 上的默认 ability id 字段用于 command selection：AI、UI、玩家输入可以直接找到默认普攻和移动。
- 技能/效果系统内部不通过 actor slot 回查“这是不是普攻”，而是消费普攻技能发出的 domain event。

推荐事件边界：

```text
Strike Ability
  -> DamageAction
  -> DamageEvent(actual_life_damage, ...)
  -> AttackLandedEvent(attacker, target, source_ability_id, actual_life_damage, damage_event payload)
```

下游消费者：

- `HexBattleGeneralPassive` 监听 `AttackLandedEvent`，读取 `attack_lifesteal_pct` 并调用 `HexBattleHealAction`。
- 普通技能伤害继续只依赖 `DamageEvent`。

未来消费者：

- 装备 on-hit、法球 / 攻击特效也会监听 `AttackLandedEvent`，但它们属于下一阶段，不纳入本轮交付。

本轮明确新增 `AttackLandedEvent`，不再把它作为 `DamageEvent` provenance 的可选替代。`AttackLandedEvent` 是普攻命中后的 domain event，后续装备 on-hit / 法球 / 攻击特效也复用这条边界。

### HexBattleGeneralPassive

`HexBattleGeneralPassive` 是每个 `CharacterActor` 自动拥有的角色内建规则桥：

```text
character attributes -> standard combat effects
```

它只处理角色属性，不承载命名机制：

- `attack_lifesteal_pct`：默认 `0`；普攻命中后按 `actual_life_damage * pct` 治疗攻击者。
- `hp_regen_per_sec`：按固定周期自然恢复 HP。
- `mp_regen_per_sec`：未来有 mana/mp 后按固定周期恢复。

它不处理：

- `Thorn` / `DemonForm` / `FrostOrb` 这类有独立名字、独立语义、独立来源的机制。
- kill trigger / counterattack / conditional proc。
- 需要独立 cooldown、叠层、互斥、优先级或 cleanse/break/revoke 管理的效果。

Break contract：

- `HexBattleGeneralPassive` 不打普通 `passive` tag，建议使用 `intrinsic` / `system` / `character_rules` 一类 tag。
- `Break` 不禁用 `HexBattleGeneralPassive`。
- `Break` 可以禁用提供属性的普通 passive 来源；属性归零后，`HexBattleGeneralPassive` 自然 no-op。
- 如果某个来源不应被 Break 禁用，应明确不把该来源建模成普通 `passive`，或后续单独定义 item/stat source policy。

### 实现建议

- 新增 example-local attribute key：`attack_lifesteal_pct`。
- 新增 `HexBattleGeneralPassive`，由 `CharacterActor.equip_abilities()` 自动 grant。
- `HexBattleGeneralPassive` 使用 `NoInstanceConfig` 监听 `AttackLandedEvent`，读取 attacker 当前 `attack_lifesteal_pct`，调用 `HexBattleHealAction` 治疗 attacker。
- `HexBattleGeneralPassive` 可用 `ActivateInstanceConfig + GRANTED_SELF + periodic timeline` 处理 `hp_regen_per_sec`，未来再接 `mp_regen_per_sec`。
- 新增被动示例：例如 `VampiricTraining`，只用 stat modifier 给 owner 增加 `attack_lifesteal_pct`，不再自己监听攻击命中。
- 当前主动 `HexBattleLifesteal` 可以保留为主动技能；它不是普攻吸血属性的实现。

### Regeneration 不是 Heal

`hp_regen_per_sec` 属于本轮目标；`mp_regen_per_sec` 等未来有 mana/mp 后再接。

`hp_regen_per_sec` / `mp_regen_per_sec` 属于资源自然恢复，不属于治疗效果。

V1 contract：

- HP regen 不走 `HexBattleHealAction`。
- HP regen 不产生 `HealEvent`。
- HP regen 不触发 on-heal / post-heal / heal amp / overheal 相关机制。
- HP regen 仍然需要 replay/frontend 可见，建议使用独立 `RegenerationEvent`。
- HP regen 应 clamp 到 `max_hp`，并记录 `actual_amount`。

建议事件：

```text
RegenerationEvent
  kind: "regeneration"
  target_actor_id
  resource: "hp"
  amount
  actual_amount
  source: "general_passive"
```

建议 action：

```text
HexBattleRegenerateAction
```

它只负责资源恢复结算与 replay 事件，不调用 `process_post_event(heal_event, ...)`。

## Heal Pipeline · 不抽取 HealUtils

当前结论：本批次不抽取 `HexBattleHealUtils`。

原因：

- 现有治疗来源可以自然走 `HexBattleHealAction`。
- 普攻吸血 passive 也可以作为 reaction action 调用 `HexBattleHealAction`。
- 目前没有多个无法复用 `HexBattleHealAction` 的治疗入口，不存在 `DamageUtils` 那种多伤害来源分叉问题。

V1 contract：

- 主动 `HolyHeal`、主动 `HexBattleLifesteal`、未来普攻吸血，默认都调用 `HexBattleHealAction`。
- 如果需要补 `actual_heal` / `overheal` / `source_ability_id` 等 replay 字段，先直接补 `HealEvent` / `HexBattleHealAction`。
- 不为了和 `HexBattleDamageUtils` 结构对称而提前抽工具类。

未来满足任一条件时，再重新讨论抽取 `HexBattleHealUtils`：

- 出现多个治疗 Action 内联重复实现 push event / clamp / set HP / post heal。
- 出现无法方便构造 `ExecutionContext` / `TargetSelector` / `FloatResolver`、但仍必须产生标准治疗事件的底层治疗来源。
- 治疗管线变复杂，例如 heal bonus、heal reduction、healing received modifier、overheal shield、healing crit。

## Phase G · Line / Cone AoE

> `Piercing Line` 已完成。下一轮 AoE 重点不是再扩 damage pipeline，而是验证两个 cone `TargetSelector` 语义，并让 skill-preview 能看到本次事件检查区域。

### 目标

做两个独立技能，方便 scenario 直接对比：

```text
skill_grid_cone
基于 hex 格子的扇形。以 caster 当前格为中心，取 range 内所有格，再按释放方向筛出前方扇区。

skill_angle_cone
基于真实世界坐标的锥形。用 coord_to_world() 得到 caster / target / candidate center，按半径与夹角选中。
```

共同规则：

- 只命中敌方 alive `CharacterActor`。
- 复用 `HexBattleDamageAction`，selector 返回多目标，damage action 对每个目标产生标准 `DamageEvent`。
- 多目标同一 hit keyframe 受伤，不新增 `AoEAction`。
- V1 不做 wall / EnvironmentActor 阻挡；阻挡语义留 follow-up。
- 命中顺序必须 deterministic，建议 `distance_to(caster)` -> angle offset -> coord/id。

### Grid Cone Selector

`GridConeSelector` 是战棋语义：

- 技能使用 `target_coord` 释放，不要求点选 actor。
- 方向来自 `HexFacing.direction_between(caster.hex_position, target_coord)`。
- `target_coord == caster.hex_position` 是 caller contract 错误，不在技能里做保护性 fail/no-op，也不 fallback 到 facing；实现应暴露 error / assertion，修 AI 或输入逻辑。
- 选区不是手写 `[1, 3, 5]` 这种逐层宽度。
- 选区语义是：以 caster 当前格为中心，取 `range` 内所有 candidate coord；把 `caster -> candidate` 量化到 6 个 hex direction；只保留 direction 属于 `{cast_dir - 1, cast_dir, cast_dir + 1}` 的前向扇区格子。
- 例如 range=3 时，检查区域就是“3 格半径内朝释放方向的前方格子集合”，实际多少格由 hex 几何自然决定。
- 结果不依赖真实像素角度，便于玩家预览与规则解释。
- 同一 selected target 附近的小偏移不会改变方向，除非跨过 6 向分界。
- DESKTK 旧项目里 `TargetSelectionType::Cone` 只有配置声明，未落地目标选择逻辑；本轮不照搬旧实现，直接采用上述 grid sector contract。

### Angle Cone Selector

`AngleConeSelector` 是几何语义：

- 技能使用 `target_coord` 释放，不要求点选 actor。
- forward vector = `coord_to_world(target_coord) - coord_to_world(caster)`。
- candidate center = `coord_to_world(candidate.hex_position)`。
- 命中条件：

```text
distance(candidate, caster) <= radius
angle(forward, candidate - caster) <= half_angle + epsilon
```

- selected target 不量化到 6 方向；只要 target 不在 caster 同格，就用真实 forward vector。
- V1 只看 actor / cell center，不做“格子面积与锥形相交”。
- `target_coord == caster.hex_position` / forward 近零是 caller contract 错误，不在技能里做保护性 fail/no-op，也不 fallback 到 facing；实现应暴露 error / assertion，修 AI 或输入逻辑。
- 默认 `range = 3`，`half_angle_deg = 45`。

### StageCue Debug Shape

这是 contract debug，不是纯 VFX polish。

技能释放时，`StageCueAction.params` 必须携带本次 selector 的检查区域，让 skill-preview / frontend 可以短暂绘制：

```text
{
  "shape": "grid_cone" | "angle_cone",
  "origin_coord": {"q": int, "r": int},
  "target_coord": {"q": int, "r": int},
  "checked_coords": [{"q": int, "r": int}, ...],
  "range": int,
  "cast_direction": int,           # grid_cone only, 0..5
  "direction_sector": [int, ...],  # grid_cone only, e.g. [dir-1, dir, dir+1]
  "half_angle_deg": float          # angle_cone only
}
```

边界：

- `targetActorIds` 表示实际命中的 actor。
- `checked_coords` 表示本次事件检查区域，用于 debug overlay，不等同于实际命中目标。
- frontend / skill-preview 只消费 payload 绘制，不反推 selector 逻辑。
- 如果 selector 后续加入 blocking，`checked_coords` 应反映 blocking 后的实际检查/有效区域。

### Scenario 覆盖

- 同一组站位分别释放 `skill_grid_cone` 和 `skill_angle_cone`，断言命中集合不同。
- 至少一个目标在 grid cone 内但 angle cone 外，证明格子扇形比真实 45 度锥形更宽。
- AOE 同帧多目标受伤，断言多个 enemy 都产生 `DamageEvent`。
- `stageCue.params.checked_coords` 与 selector 计算出的检查区域一致。
- 边界目标靠近 `half_angle` 时结果稳定，使用 epsilon 避免浮点抖动。

## Separate Regression · Facing Visualization

> 这不是 Cone 技能的测试项，而是之前新增 `facing` 机制留下的 frontend / regression 缺口。

已有逻辑层 baseline：

- `CharacterActor` 持有 `facing_direction`。
- `HexFacing.face_actor_toward()` 会更新 source of truth 并发出 `ActorFacingChangedEvent`。
- scenario 已能读取 `final_facing_directions`。

需要补的前端 contract：

- replay 初始化时读取 actor snapshot 中的 `facing_direction`。
- `actor_facing_changed` 事件回放时更新 `FrontendActorRenderState.facing_direction`。
- `FrontendUnitView` 增加轻量朝向箭头 attached visual，只对 `CharacterActor` 显示；`EnvironmentActor` 不显示。
- 箭头显示当前 6 向朝向，先不做 turn speed / facing lock / 复杂转身动画。

验收：

- 初始 A 队朝东、B 队朝西的箭头可见。
- 主动攻击/施法产生 facing change 后，箭头随 replay 更新。
- forced displacement 不改变 facing，箭头不转。
- 这组测试归入 facing frontend/regression，不作为 `skill_grid_cone` / `skill_angle_cone` 的通过条件。

## 验收建议

普攻吸血：

- `HexBattleGeneralPassive` 自动 grant 给 `CharacterActor`，且不被 Break 禁用。
- 被动/buff 给 `attack_lifesteal_pct` 后，`Strike` 命中会 heal。
- `actual_life_damage = 0` 时不 heal。
- active skill damage 不触发普攻吸血。
- reflected damage / periodic damage 不触发普攻吸血。
- Break 禁用提供 `attack_lifesteal_pct` 的普通 passive 来源时，吸血自然停止；但 `HexBattleGeneralPassive` 本身仍保留。
- heal event 进入 replay，source / target 字段可追踪。

治疗管线：

- 普攻吸血 heal 走 `HexBattleHealAction`，不直接改 HP。
- `HexBattleHealAction` 行为不回归。
- 如果补 `actual_heal` / `overheal` / source 字段，需要 scenario 覆盖。
- 不新增 `HexBattleHealUtils`，除非触发上面的 future extraction 条件。

自然恢复：

- `hp_regen_per_sec` 不走 `HexBattleHealAction`。
- `hp_regen_per_sec` 不产生 `HealEvent`，不触发 heal-related passive。
- `hp_regen_per_sec` 产生 `RegenerationEvent`，且 `actual_amount` clamp 到缺失 HP。
- `Break` 不禁用 `HexBattleGeneralPassive`，但可禁用提供 regen 属性的普通 passive 来源。

Cone AoE：

- `skill_grid_cone` 与 `skill_angle_cone` 使用同一 damage pipeline，但 selector 命中集合可区分。
- AoE 多目标同一 hit keyframe 受伤，多个 `DamageEvent` 目标稳定。
- `StageCue.params.checked_coords` 可被 skill-preview/frontend 用于绘制检查区域。
- frontend 不从 `targetActorIds` 反推 AoE shape。

Facing 回归：

- 朝向箭头显示初始 `facing_direction`。
- `actor_facing_changed` replay 后箭头更新。
- forced displacement 不改变箭头方向。
- 该项是既有 facing 机制补测，不属于 Cone 技能自身 contract。

## Open Questions

- `HealEvent` / `HexBattleHealAction` 是否补 `actual_heal` / `overheal` / source 字段？
- 多个吸血来源是 additive、multiplicative，还是以后交给 stacking policy？
- `AngleConeSelector` 的默认 `half_angle_deg = 45` 已定；是否允许技能 config 覆盖留到实现时决定。
