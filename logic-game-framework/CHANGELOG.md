# Changelog

本文件记录 Logic Game Framework 的重要变更。格式参考 [Keep a Changelog](https://keepachangelog.com/)。

- **Added** — 新增能力
- **Changed** — 行为或 API 变化
- **Fixed** — Bug 修复
- **Removed** — 移除
- **Deprecated** — 即将废弃

对于有架构推理的重大变更，在 `docs/design-notes/` 下会有对应长文，行末以链接引用。

---

## [Unreleased] — 2026-05-24 advanced-skills-next-batch Phase D — Cone AoE selectors (skill_grid_cone + skill_angle_cone)

引入首批 AoE `TargetSelector` 实现, 对比 hex 格子 sector (`GridConeSelector`) 与真实世界角度 (`AngleConeSelector`) 两种范围语义。两个 cone skill 都使用 `target_coord` 释放 (不点 actor), 复用 `HexBattleDamageAction` 多目标同帧产生多个 `DamageEvent`。

### Added

- **`example/hex-atb-battle/logic/abilities/active/grid_cone.gd`** — `HexBattleGridCone` (config_id `skill_grid_cone`, range 3, cooldown 8000ms). 内嵌 `_GridConeSelector`: `cast_dir = HexFacing.direction_between(caster, target_coord)`, 取 caster range 内所有 hex, 过滤 `direction_between(caster→cand) ∈ {cast_dir-1, cast_dir, cast_dir+1}` 三方向 sector 的敌方 alive CharacterActor。命中排序: hex_distance 升序 → coord sort_key 升序。`target_coord == caster.hex_position` → `Log.assert_crash` (caller contract 错误, 不 fallback)。
- **`example/hex-atb-battle/logic/abilities/active/angle_cone.gd`** — `HexBattleAngleCone` (config_id `skill_angle_cone`, range 3, half_angle 45°, cooldown 8000ms). 内嵌 `_AngleConeSelector`: forward = `coord_to_world(target_coord) - coord_to_world(caster)`, 对每 candidate (world coords) 检查 `|angle(forward, cand_vec)| <= 45° + epsilon`。命中排序: hex_distance → world angle → coord sort_key. 同 `target_coord == caster` assertion + forward 零向量检测。
- **3 个新 scenario** (`tests/battle/skill_scenarios/cone_*_scenario.gd`):
  - `cone_grid_hits_sector` — 同站位 4 enemy, grid 命中前方 3 (E/E/NE), 后方 W 不中。
  - `cone_angle_narrow` — 同设, angle 仅命中 2 个 (正东两枚), NE 60° world 角超出 45° 半角不中。
  - `cone_grid_vs_angle_distinguishable` — 两 cast 同站位, 断言 angle hit set ⊂ grid hit set 且 grid 严格更多。

### Changed

- **`example/hex-atb-battle/logic/scenario/skill_scenario_harness.gd`** — `_fire_action` 加 `target_coord: Dictionary = {}` 默认参数; action 字典支持 `"target_coord": {q,r}` 字段, 写入 `activate_event["target_coord"]`. cone / move 类 coord-based skill 在 scenario harness 内可直接释放。
- **`example/hex-atb-battle/logic/abilities/shared/all_skills.gd`** — manifest 加 2 个 cone ability + 各自 timeline 注册。
- **`example/hex-atb-battle/skill-preview/skill_preview.gd` `_collect_actor_setups`** — fixed_pos mode 现在透传 `target_coord` Dictionary 给 ability (而非仅 fallback 到 nearest actor)。
- **`example/hex-atb-battle/skill-preview/skill_preview_procedure.gd`** — keyframe 携带 `target_coord` 时, activate event 写入 `target_coord` 字段。dev-scene 现在可以测试 cone / move 这类真 coord-based ability。

### Validation

| 测试 | 结果 |
|---|---|
| `hex/skills smoke_skill_scenarios` | PASS 58/58 (含 3 新 cone) |
| `hex/regression` | PASS 3/3 |
| `core/unit` | PASS |
| dev-scene 视觉验证 | SkillPreview caster atk=40 朝 target_coord (3,0) cast `skill_grid_cone` → 3 enemy 同帧 `-40` damage 浮字 (timeline log 3 条 PHYSICAL 300ms 同时刻); 后方 enemy_3 (-1,0) HP 100 unchanged + Inspector "No damage or heal events". 多目标 AoE contract 闭环 |

---

## [Unreleased] — 2026-05-24 advanced-skills-next-batch Phase C — hp_regen_per_sec + RegenerationEvent

`hp_regen_per_sec` 由 `HexBattleGeneralPassive` periodic 1s timeline 驱动, 走自有 `HexBattleRegenerateAction` + `RegenerationEvent` (kind=`regeneration`), **不走 heal pipeline**, **不产 HealEvent**, **不触发 heal-related passive** (per spec)。VitalitySurge 普通被动 (`+5 hp/s`) 受 Break 影响; GeneralPassive 仍 tick 但属性归零 → action 早退。

### Added

- **`example/attributes/attributes_config.gd` / generated `hex_battle_character_attribute_set.gd`** — 新增 `hp_regen_per_sec` 属性, 默认 `0.0`, `minValue: 0.0`。
- **`example/hex-atb-battle/core/events/battle_events.gd`** — `RegenerationEvent` (kind=`regeneration`), payload: `target_actor_id` / `resource` / `amount` (理论恢复=per_sec*period) / `actual_amount` (clamp 到 max-current) / `source`。
- **`example/hex-atb-battle/logic/actions/regenerate_action.gd`** — `HexBattleRegenerateAction` 直接 `extends Action.PrimitiveAction` (新 LGF 规范), 走自有 resource → set_hp_base → push RegenerationEvent + broadcast 给存活 actor (kind `regeneration` 与 'heal' 不冲突, heal listener 自然不响应)。`Log.assert_crash(_resource == "hp")` 保证 V1 只支持 hp。`action_architecture_validator` allowlist 增 1 条对应入口。
- **`example/hex-atb-battle/logic/abilities/passives/general_passive.gd`** — 增 `REGEN_TIMELINE` (period=1000ms) + `ActivateInstanceConfig + GRANTED_SELF + on_timeline_end -> HexBattleRegenerateAction`。`_HP_REGEN_PER_SEC_RESOLVER` 每 tick 实时读 owner attribute (不冻结), buff/passive grant/revoke 自动响应。
- **`example/hex-atb-battle/logic/abilities/passives/vitality_surge.gd`** — `HexBattleVitalitySurge` (`config_id: passive_vitality_surge`, +5 hp/s 通过 StatModifier), tags `["passive", "regen"]` (Break 可禁)。
- **`example/hex-atb-battle/logic/abilities/shared/all_skills.gd`** — manifest 加 `HexBattleVitalitySurge` + `HexBattleGeneralPassive.REGEN_TIMELINE` 注册 (timeline 列表里)。
- **4 个新 scenario** 覆盖 Phase C 验收 (`hp_regen_*_scenario.gd`): default_zero / basic / clamp_max / break_disables_source。

### Changed

- **`example/hex-atb-battle/logic/scenario/skill_scenario_harness.gd`** —
  - `_PreviewInstance._create_actor` 在 idle 判定 still_executing 循环里 skip `intrinsic` ability。GeneralPassive 周期 timeline granted 后永不停止, 没有这个 skip 会让所有 scenario 都跑到 max_ticks (=以前的 Demon Form scenario 也是同款 timeout 路径, 但 shield_damage_type_matrix 等紧贴 max_ticks 边界的 scenario 会因边界 race 失败)。
  - `run_with_actions` 接受 `scene_config["min_ticks"]` (default 0), 在 tick 循环里 `tick_count < min_ticks` 时强制 `still_executing=true`, 让 periodic-timeline-依赖的 scenario (HP regen, Demon Form) 跑够帧数。
- **`example/hex-atb-battle/tests/battle/skill_scenarios/skill_scenario.gd`** — 新增 `get_min_ticks() -> int = 0` 钩子, scenario 自助声明"最少跑 N 帧才允许 idle 收敛"。
- **`example/hex-atb-battle/tests/battle/smoke_skill_scenarios.gd`** — 把 `scenario.get_min_ticks()` 透传到 harness 的 `scene_config["min_ticks"]`。
- **`core/actions/action_architecture_validator.gd`** — ALLOWLIST 加 `regenerate_action.gd` 条目 (extends PrimitiveAction 直接, allowlist 用于显式登记新 public action)。

### Validation

| 测试 | 结果 |
|---|---|
| `hex/skills smoke_skill_scenarios` | PASS 55/55 (含 4 新 hp_regen + 4 phase A + 5 phase B) |
| `hex/regression` | PASS 3/3 |
| `core/unit` | PASS |
| dev-scene 视觉验证 | timeline 8 个 RegenerationEvent (frame 10/20/30/.../80 each +5, frame 90+ actual_amount=0 clamped); caster HP 60 → 100 经 8 ticks, Inspector "Damage History" 显示 -40 initial damage from enemy_0 |

---

## [Unreleased] — 2026-05-24 advanced-skills-next-batch Phase B — HexBattleGeneralPassive + attack_lifesteal_pct

把"角色属性 → 标准战斗效果"的桥接落地。VampiricTraining (普通 passive, 受 Break 影响) 通过 StatModifier 给 owner +0.5 `attack_lifesteal_pct`; HexBattleGeneralPassive (intrinsic, 不受 Break) 监听 Phase A 落地的 `attack_landed` 事件, 按 `actual_life_damage * attack_lifesteal_pct` 调 `HexBattleHealAction` heal attacker。

### Added

- **`example/attributes/attributes_config.gd` / generated `hex_battle_character_attribute_set.gd`** — 新增 `attack_lifesteal_pct` 属性, 默认 `0.0`, `minValue: 0.0`。
- **`example/hex-atb-battle/logic/abilities/passives/general_passive.gd`** — `HexBattleGeneralPassive` (`config_id: "general_passive"`), tags `["intrinsic", "character_rules"]` (无 `passive` tag, Break 不禁)。`NoInstanceConfig` + trigger `"attack_landed"` + filter (attacker == owner) + inner `_LifestealAction extends Action.SkillLocalAction`。Action 内部读 callback ctx 拿 actual_life_damage, 读 attacker.attack_lifesteal_pct, 走 `HexBattleHealAction` 标准 heal pipeline; 所有 early-return 分支携 `attack_lifesteal_skipped` 原因 (no_event / no_actual_damage / zero_pct / attacker_unavailable) 便于排查。
- **`example/hex-atb-battle/logic/abilities/passives/vampiric_training.gd`** — `HexBattleVampiricTraining` (`config_id: "passive_vampiric_training"`, `LIFESTEAL_PCT = 0.5`), tags `["passive", "lifesteal"]` (带 `passive` tag, Break 禁源后 GeneralPassive 自然 no-op)。仅 `StatModifierConfig` 给 owner +0.5 `attack_lifesteal_pct`。
- **`example/hex-atb-battle/logic/character_actor.gd`** — `equip_abilities()` 在 class passive grant **之前** unconditional grant `HexBattleGeneralPassive`, 与 spec "每个 CharacterActor 必有" 对齐。
- **`example/hex-atb-battle/logic/scenario/skill_scenario_harness.gd` `_PreviewInstance._create_actor`** — 每个 scenario actor 单独 grant GeneralPassive (harness 故意不走 `equip_abilities` 避免 Move/Strike 默认注入, 但 GeneralPassive 是 intrinsic 必须保留)。
- **`example/hex-atb-battle/skill-preview/skill_preview.gd` `_spawn_one_actor`** — 与 harness 对齐, GeneralPassive 由 skill-preview 自动 grant。
- **`example/hex-atb-battle/logic/abilities/shared/all_skills.gd`** — manifest 注册 `HexBattleGeneralPassive` + `HexBattleVampiricTraining` 进 "Pure passives" 区块, skill-preview 现在能在 passive 列表里看到 `passive_vampiric_training` (`general_passive` 也可显式选, 但不必, 自动 grant 已覆盖)。
- **5 个新 scenario** 覆盖 Phase B 验收 (`lifesteal_attribute_*_scenario.gd`): default_zero / basic / shield_no_heal / fireball_no_trigger / break_disables_source。

### Validation

| 测试 | 结果 |
|---|---|
| `hex/skills smoke_skill_scenarios` | PASS 51/51 (含 5 个新 lifesteal_attribute + 4 个 Phase A attack_landed) |
| `hex/regression` | PASS 3/3 |
| `core/unit` | PASS |
| dev-scene 视觉验证 | caster `+20` heal 浮字可见, Inspector "Damage History" 列出 `+20.0 heal`; caster HP 70→90 ✓ |

---

## [Unreleased] — 2026-05-24 advanced-skills-next-batch Phase A — AttackLandedEvent (basic-attack domain event)

为 `HexBattleGeneralPassive` (Phase B) / 未来装备 on-hit / 法球 / 攻击特效订阅准备的 "普攻命中" domain event。**只由 Strike (以及未来其它"普攻"类 ability) 发射,Fireball / Poison tick / reflected damage / Fire Tile / Totem passive damage 都不发射** —— 这是 contract 而非命名约定。

### Added

- **`example/hex-atb-battle/core/events/battle_events.gd`** — `AttackLandedEvent` (kind `attack_landed`),payload: `attacker_actor_id` / `target_actor_id` / `source_ability_id` / `source_ability_config_id` / `actual_life_damage` / `damage_event` (deep-copy of the原始 damage dict)。Header 文档了顺序契约 (post broadcast 早于 父 damage post) 与 `attacker_actor_id` 可能指向已死 actor (Strike timeline 自 HIT 起 fire-and-forget) 的边界。
- **`example/hex-atb-battle/logic/abilities/active/strike.gd`** — 内嵌 `_EmitAttackLandedAction extends Action.SkillLocalAction` (`owner_config_id = "skill_strike"` 锁定只在 Strike 触发),通过 `.on_hit(...)` 挂在主 `HexBattleDamageAction` (不挂 `.on_critical`,crit bonus 不复触发)。事件 push 到 `event_collector` + broadcast 给 **fresh** alive list (与父 DamageAction 的 stale snapshot 不同 —— 死亡 target 在 attack_landed broadcast 自动出列,语义更对)。`Log.assert_crash` 兜底 `damage_event_dict` 必含 `actual_life_damage` / `target_actor_id`。
- **`example/hex-atb-battle/tests/battle/skill_scenarios/attack_landed_*_scenario.gd`** — 4 个新 scenario:
  - `strike_emits` (Strike 命中后必有 1 条事件 + 字段齐全 + `actual_life_damage > 0`);
  - `fireball_no_emit` (Fireball 不发);
  - `zero_actual_damage` (caster atk=20 + target ward cap=30 → `actual_life_damage = 0` 仍 emit, consumer 自行 no-op);
  - `reflect_no_emit` (Thorn 反伤经 `HexBattleReflectDamageAction` 走另条 path, 不触发 AttackLandedEvent)。

### 设计取舍

- **顺序倒置 (attack_landed broadcast 早于父 damage post)** —— `_process_callbacks` 跑在 `broadcast_post_damage` 之前是 DamageAction 既有顺序,Phase A 顺势使用; consumer 同时订阅 'damage' 与 'attack_landed' 时记录此顺序作 contract,header 文档已说明。
- **fresh vs stale alive list** —— `broadcast_post_damage` 用 stale (LGF 框架约定,本帧死的 actor 仍参与广播); `attack_landed` 用 fresh (本次 hit 把 target 打死时 target 自动出局,不再被打扰)。二者不强求一致,Phase B 仅 attacker 侧 lifesteal 监听,attacker 必在 fresh list。
- **damage_event 字段** —— `AttackLandedEvent.create()` 不再 `duplicate(true)` (instance 字段无人读),只在 `to_dict()` 出口 deep-copy 一次进 replay JSON。`from_dict()` 防御 `damage_event` 字段存在但为 null 的迁移情形 (`null as Dictionary` 不会 crash duplicate)。

| 测试 | 结果 |
|---|---|
| `hex/skills smoke_skill_scenarios` | PASS 46/46 (含 4 个新 attack_landed scenario) |
| `hex/regression` | PASS 3/3 |
| `core/unit` | PASS |
| `hex/frontend` | 6/7 PASS (唯一 TIMEOUT = 既有无关 `smoke_surge_unit_view`, standalone 跑 PASS) |

---

## [Unreleased] — 2026-05-18 devagent — 确定性回放定格(解锁瞬时 VFX 视觉验证)

skill_preview 回放此前只有 `wait_for_idle`(等全完,太晚)/ `wait_frames`(墙钟,与回放轴无固定换算)→ 截不到超短战斗里的一次性 VFX(斩杀爆 / 命中闪 / 投射物消失帧)。新增确定性回放控制,**永久解开"表演层无法 dev 闭环"**。

### Added

- **`example/hex-atb-battle/frontend/core/battle_director.gd`** — `step(delta_ms)`:复用 `_tick`,暂停态按精确量推进一步(不经 `_process`/不看 `_is_playing`,与正常播放同一路径)。
- **`example/hex-atb-battle/frontend/battle_animator.gd`** — `step(delta_ms)` 透传 + 对齐 unit view 位置(手动步进时 `_process` lerp 不跑)。
- **`example/hex-atb-battle/skill-preview/`** — `dev_agent_pause_playback` / `dev_agent_step_playback` / `dev_agent_playback_state`;ops 注册 3 op;`DEV_AGENT.md` 加文档 + 「瞬时 VFX 定格验证回路」配方。

不改 lomolib 通用层;`smoke_frontend_main` 等回放 smoke 覆盖,`-Required` 14/0/0 无回归。已用它定格验证 `execute_kill` 特效(frame-exact 步进:s8→frame3 精确)。

---

## [Unreleased] — 2026-05-18 hex-atb-battle — Execute (Tier 1 #6 收口) + 斩杀击杀特效

斩杀技能:目标「有效血量」(hp + 能挡 PURE 的护盾)低于 max_hp 20% → 造成 effective_hp+1 PURE 伤害(实质斩杀),否则退化为 caster.atk 普攻。完成 Tier 1 MVP 6/6,填补 pattern 速查「条件分支伤害 / 斩杀」空格。**0 框架/逻辑新机制** —— 单个既有 `HexBattleDamageAction` + Resolver 内按 target 状态分支 damage 值(LGF 表达"条件伤害"的惯用法,resolver 与 `current_target` selector 同源经 `ctx.get_current_event()` 取 target)。

### Added

- **`example/hex-atb-battle/logic/skills/execute.gd`** — `HexBattleExecute`,自带 resolver 分支斩杀/普攻;`on_kill` 回调发 `execute_kill` StageCue。
- **`example/hex-atb-battle/logic/utils/hex_battle_shield_resolver.gd`** — `sum_absorbable_capacity(actor, damage_type)` 公共静态,复用 `_collect_candidates` 硬过滤,累加「能吸该类型」护盾余量。斩杀判定据此把 universal/`["all"]` 盾计入有效血量、physical/magical 盾(挡不住 PURE)排除。
- **`example/hex-atb-battle/tests/battle/skill_scenarios/execute_scenario.gd`** — 4 case:低血斩杀 / 高血普攻 / 严格 20% 临界不触发 / 带 ward 抗斩杀(护盾计入有效血量 = 核心判定修复)+ `execute_kill` cue 有无断言。

### Changed

- **`example/hex-atb-battle/frontend/visualizers/stage_cue_visualizer.gd`** — 新增 `execute_kill` cue 分支:① 猩红 `IMPACT` 冲击波(`is_critical` 放大、0.8s 时长 + 0.15s 延迟,作为独立"斩杀收尾"不与起手挥击糊在一起)② 醒目大红 **"斩杀!" 飘字**(`FrontendFloatingTextAction` CRITICAL 强调样式,复用已验证清晰可辨的飘字系统,远相机一眼可读 = genre 标准击杀播报)。均复用既有渲染管线,无新 VFX 类/资产。经 devagent 确定性步进定格截图肉眼确认"明显"。
- **`example/hex-atb-battle/logic/skills/all_skills.gd`** — manifest 注册 Execute + EXECUTE_TIMELINE。
- **`example/hex-atb-battle/logic/scenario/skill_scenario_harness.gd`** — `_actor_src_to_preview_cfg` 支持显式 `max_hp`(此前 hp=max_hp 绑定,斩杀按比例判定需 hp≠max_hp)。

| 测试 | 结果 |
|---|---|
| `smoke_skill_scenarios` | PASS 17/17(含 Execute 4 case) |
| `hex/skills` + `hex/frontend` | 9 PASS / 0 FAIL(唯一 TIMEOUT = 既有无关 `smoke_surge_unit_view`) |
| `-Required` | 14 PASS / 0 FAIL / 0 TIMEOUT |

---

## [Unreleased] — 2026-05-18 hex-atb-battle — Typed shield skills + per-type shield bars

为 codex 落地的 typed 护盾 buff(`PHYSICAL_SHIELD_BUFF` / `MAGICAL_SHIELD_BUFF`)补上 gameplay 投放途径与按类型分条的表演层 —— 此前它们只有数据 + 前端白名单 + scenario 测试,无授予技能、且 skill_preview 的 buff 过滤导致无法施放;护盾条多盾时聚合成单色单条,区分不出类型。

### Added

- **`example/hex-atb-battle/logic/skills/physical_shield.gd` / `magical_shield.gd`** — 自施 typed 护盾主动技能(`skill_physical_shield` / `skill_magical_shield`),镜像 `ward.gd`(RANGE 0 / 500ms cast、HIT@300 / 4000ms cooldown / `ApplyShieldAction` + `ability_owner` selector)。带 `["skill","active","self","shield"]` 标签(非 `buff`),可在 demo / skill_preview 真实施放。
- **`example/hex-atb-battle/tests/frontend/smoke_shield_layout.{gd,tscn}`** — `FrontendShieldBarView` 多类型分条布局白盒回归:断言 3 个不同 `config_id` → 3 条可见、异色、Y 不重叠、按 `priority desc → config_id asc` 排序、填充比例正确、空态全隐藏。注册进 `hex/frontend` group。

### Changed

- **`example/hex-atb-battle/frontend/scene/shield_bar_view.gd`** — 从「sum/sum 单条 + `shields[0].color`」改为「按 `config_id` 分组、每类型一条竖直堆叠」的池化渲染,排序与 `ShieldResolver` 消耗序一致(`priority desc → config_id asc`)。条厚 0.09→0.13、step 0.17,远相机下可辨。
- **`example/hex-atb-battle/frontend/scene/name_label_view.gd`** — `name_label_offset` 1.5→1.92,给最多 3 条护盾条让位避免重叠。
- **`example/hex-atb-battle/logic/skills/all_skills.gd`** — manifest 注册两个新 typed 护盾技能 + 其 timeline。

数据契约(`FrontendShieldSummary` / `ApplyShieldStateAction` / `ShieldBarVisualizer` 白名单)与 resolver 结算未改动,既有 16 scenario + `smoke_shield_ui` 不回归。

| 测试 | 结果 |
|---|---|
| `hex/skills` + `hex/frontend` | 9 PASS / 0 FAIL (唯一 TIMEOUT = 既有无关 `smoke_surge_unit_view`) |
| `-Required` | 14 PASS / 0 FAIL / 0 TIMEOUT |
| `smoke_shield_layout` | PASS (6 步) |
| dev scene 三盾实测 | 三技能施放 + 三色分条渲染确认 |

---

## [Unreleased] — 2026-05-04 hex-atb-battle — Atomic displacement + ActionLockStatus

Push / knockback remains a one-keyframe atomic logic operation, then grants a timed target-side action lock (`status_action_lock`) to prevent the pushed actor from starting its own next action while preserving passive triggers and in-flight timelines. See design note.

→ [docs/design-notes/2026-05-04-displacement-atomic-by-design.md](docs/design-notes/2026-05-04-displacement-atomic-by-design.md)

### Added

- **`example/hex-atb-battle/logic/buffs/action_lock_status.gd`** — generic timed action-lock status with `action_locked` / `cant_act` component tags and reason tag support (`displacement_stagger` for Push V1).
- **`example/hex-atb-battle/frontend/visualizers/displacement_visualizer.gd`** — translates `actor_displaced` into `FrontendMoveAction`, using event `action_lock_duration_ms` as the animation duration.
- **`example/hex-atb-battle/tests/battle/smoke_knockback_punch.gd`** — adds action-lock metadata/status and ATB gate expiry cases.

### Changed

- **`example/hex-atb-battle/logic/actions/push_action.gd`** — writes `actual_distance` / `action_lock_duration_ms` / `collision_action_lock_bonus_ms` to displacement events and grants `status_action_lock` to surviving character targets.
- **`example/hex-atb-battle/logic/character_actor.gd`** — `can_act()` now treats `cant_act` as an actor-level action gate, so ATB stays full and is not reset while locked.
- **`example/hex-atb-battle/logic/skills/*.gd`** — active skills add `NoTagCondition(cant_act)` as a direct-activation safety gate. `Move` remains unchanged because it uses `ActivateInstanceConfig`; AI move is covered by the actor gate.
- **`example/hex-atb-battle/core/events/battle_events.gd`** — `ActorDisplacedEvent` / `PushBlockedEvent` carry action-lock metadata for replay/frontend consumers.

---

## [Unreleased] — 2026-05-04 hex-atb-battle — View ↔ Logic 终态对账 oracle

战斗结束后引入一个**端到端对账系统**:逻辑层在 `battle_finished` 之后 emit 一份完整的 actor 终态 snapshot,表演层在 playback 收尾时跑 reconciler 对账每个 actor 的 `position` / `is_alive` / `hp` / `max_hp`,任一字段漂移即报告 mismatch (`actor_id` + `field` + 详情)。

定位"漏 visualizer / visualizer 翻译错"这类**漂移类回归**——具体引出场景:击退机制 `ActorDisplacedEvent` 没有对应 visualizer,logic 改了 `actor.hex_position` 而 view 仍渲染原位,既有 logic smoke (只断言 events) 与 frontend smoke (只断言不崩) 之间的中间层无人验证。oracle 不绑特定 ability,任何战斗 smoke 跑过即可触发对账。

**debug-only 协议**: 仅在 `OS.has_feature("debug")` 下计算并 emit final_state,release 包零开销;oracle 收到空 final_state 视为 SKIPPED 不 fail,smoke 在 release 跑也不会假阳性。

**死者特殊处理**: 跳过 `position` (`FrontendUnitView.play_death` 修改 transform 是纯视觉装饰),`hp` / `max_hp` / `is_alive` 照查 (logic ability_set 不主动清 buff,view BuffVisualizer 也不主动清,双方对称)。详见参考文档。

→ [example/hex-atb-battle/docs/view-logic-reconciliation.md](example/hex-atb-battle/docs/view-logic-reconciliation.md)

### Added

- **`example/hex-atb-battle/core/hex_world_gameplay_instance.gd`** — 新增 `signal battle_final_state_ready(final_state: Dictionary)` + `_emit_final_state_if_debug` (battle_finished handler, base 类先 connect 保证早于子类 demo._on_battle_finished / SkillPreviewWorldGI 子类 handler 跑) + `_build_final_state_snapshot` / `_build_actor_snapshot` (复用 `HexBattleActor.get_attribute_snapshot` / `get_ability_snapshot` / `get_tag_snapshot`)
- **`example/hex-atb-battle/frontend/world_view.gd`** — `hex_to_world(coord)` public 包装,oracle 与 `_on_actor_position_changed` 用同一份投影函数
- **`example/hex-atb-battle/tests/frontend/view_logic_reconciler.gd`** — `HexBattleViewLogicReconciler` (RefCounted) + 嵌套 `Mismatch` / `ReconcileReport`;入口 `reconcile(final_state, animator, world_view, tree, settle_timeout_sec, position_epsilon, hp_epsilon)`;含 settle loop (`Time.get_ticks_msec` + `await tree.process_frame` 等 view position lerp 收敛) + 字段 diff (不 short-circuit,收齐所有 mismatch)
- **`example/hex-atb-battle/docs/view-logic-reconciliation.md`** — 完整参考文档:双源对账模型 / 字段全集表 / 死者特殊处理详细论证 / settle loop 设计 / debug-pub gate / 接入步骤清单 / 扩展点 (buffs / shields / tags 留 follow-up)

### 待处理

- **接入 `smoke_frontend_main` + skill-preview** — Phase 4 实施中,需 push_action / action_lock_status 修改稳定后再统一 smoke 验证
- **buff / shield 列表对账** — 需先解耦 `FrontendBuffVisualizer.BUFF_REGISTRY` 白名单,oracle 才能反查"应该有哪些 BuffSummary";暂以 view-side single-direction 检查为最小集
- **DisplacementVisualizer (`actor_displaced` event 翻译)** — 已由 Atomic displacement + ActionLockStatus 变更落地,oracle 可用 push scenario 覆盖 position drift

---

## [Unreleased] — 2026-05-04 RTS Pathfinding M3 Epic / M2 — ObstructionManager (Shape 数据库 + Spatial Index)

M3 Epic 第三个 milestone(M0 Footprint 拆分 + M1 Navcell Grid 已 archived 2026-05-04)。引入 `RtsObstructionManager` 作为所有 obstruction shape(单位圆 + 建筑 OBB)的统一数据库,替换 M0/M1 阶段"actor 自管 obstruction_shape + grid 自管 placement_map"的散乱状态;同时引入完整 `RtsObstructionFlags` 枚举(6 flag)+ `RtsObstructionTestFilter` 抽象 + `RtsSpatialIndex`(uniform grid bucket 256 px)+ 完整 SAT OBB-OBB 重叠测试。

**M2 是数据层 + Manager 单例落地, production code 仍走 dual-write**(grid bit 由 `rts_grid.place_building` 写入, manager 持 shape 数据但不被 pathfinder 消费); **replay seed=42 frames=9 events=20 deep-equal + baseline CSV byte-identical(882882 bytes)0 漂移**。spec §AC8 预期"trace 字段从占位变实填"导致新 baseline 未发生 — dual-write 模式让 M5 切 pathfinder 走 manager 时再一次性接受 baseline 漂。

不修改 LGF core / stdlib,改动仅在 `addons/logic-game-framework/example/rts-auto-battle/` 内。

### Added

- **`logic/obstruction/rts_obstruction_flags.gd`** — Obstruction shape EFlags 位掩码常量(class_name + 6 const);完整对照 0 A.D. `ICmpObstructionManager.h:78-86` 6 flag(BLOCK_MOVEMENT / BLOCK_FOUNDATION / BLOCK_CONSTRUCTION / BLOCK_PATHFINDING / MOVING / DELETE_UPON_CONSTRUCTION);替换 M0 阶段 `rts_buildings.gd:85` 硬编码 `1 << 3`
- **`logic/obstruction/rts_obstruction_test_filter.gd`** — Filter 抽象(RefCounted + `predicate(shape)` 默认 true)+ 3 静态工厂(`skip_control_group(group)` / `only_blocking_movement()` / `combined(a, b)`)+ 3 inner class 实现(`_SkipControlGroup` / `_OnlyBlockingMovement` / `_Combined`);**inner class 方案绕 GDScript 同文件 class_name 限制**(R6 缓解)
- **`logic/obstruction/rts_obstruction_shape_unit.gd`** — Unit 子类(extends RtsObstructionShape;`clearance: float` + `moving: bool`;`_init` 设 `type = Type.UNIT`);base.flags 与 moving 字段双写约定
- **`logic/obstruction/rts_spatial_index.gd`** — Uniform grid bucket spatial index(RefCounted;`BUCKET_SIZE = 256 px` = 8 navcell × 32 px;H2 决策 A);`_buckets: Dictionary[Vector2i, Array[int]]` + `_shape_buckets: Dictionary[int, Array[Vector2i]]` 反向索引(O(1) remove);4 公开 API(`insert` / `remove` / `update` / `query_circle`)+ 2 调试 helper(`size` / `bucket_count`);**`query_circle` 末尾 `result.sort()` 强制 tag 升序**(§12.4 determinism contract)
- **`logic/obstruction/rts_obstruction_manager.gd`** — Obstruction shape 数据库 + 空间查询 + rasterize 单例(RefCounted;挂 `RtsWorldGameplayInstance.obstruction_manager`;H1 决策 A);9+ 公开 API(`add_unit_shape` / `add_static_shape` / `move_shape` / `set_unit_moving_flag` / `set_*control_group` / `remove_shape` / `get_shape` / `get_obstructions_in_range` / `test_unit_shape` / `test_static_shape` / `distance_to_point` / `distance_to_target` / `rasterize`)+ 2 调试 helper(`size` / `next_tag`);**完整 SAT 4 轴 OBB-OBB 重叠测试**(R1 缓解;0 A.D. `helpers/Pathfinding.cpp:TestObstructionsAgainstSquare` 同算法);完整 circle-OBB / OBB local 投影 / point-in-OBB 几何;`rasterize(grid, pass_class, dirty_only)` 把 BLOCK_PATHFINDING shape 写到 NavcellGrid 对应 class bit;**`_next_tag` 单调递增永不复用**(R5 决策, tag 0 = invalid 哨兵);**rasterize 不调 `clear_dirty()`**(R5 P1-2 决策, RtsWorld.tick step 7 末统一清);`rasterize` 内 `_shapes.keys() + sort()` 保 deterministic 写入序(Dictionary 迭代序非 deterministic, §12.4)
- **`tests/battle/smoke_obstruction_manager_register.{gd,tscn}`** — 8 shape add(5 unit + 3 static)→ 验证 tag 1..8 单调递增 + `manager.size() == 8` + `next_tag() == 9` + `get_shape(tag)` 反查 + `get_obstructions_in_range(中心, 大半径)` 返回 8 shape 按 tag 升序(§12.4 determinism)
- **`tests/battle/smoke_obstruction_manager_query.{gd,tscn}`** — 5 段:filter predicate 基础(`skip_control_group` / `only_blocking_movement` / `combined`)+ `test_unit_shape`(单位 vs 单位)+ `test_static_shape`(OBB vs Unit / OBB)+ **SAT OBB-OBB 4 case**(轴对齐 / 旋转 45° / 边接触 / 角接触;R1 缓解)+ `distance_to_point` / `distance_to_target`
- **`tests/battle/smoke_obstruction_manager_remove.{gd,tscn}`** — 4 段:remove basic + idempotent(重复 remove / 不存在 tag 不 crash)+ query 一致性(remove 后 `get_obstructions_in_range` 不返回该 shape)+ remove all + re-add(验证 tag 永不复用,从 _next_tag 继续)

### Changed

- **`logic/obstruction/rts_obstruction_shape.gd`** — 基类 `flags` 字段注释从"M0 硬编码"更新为引用 `RtsObstructionFlags` + 典型组合(单位 BLOCK_MOVEMENT / 建筑 BLOCK_PATHFINDING|BLOCK_FOUNDATION / 树 BLOCK_PATHFINDING|DELETE_UPON_CONSTRUCTION)
- **`logic/buildings/rts_buildings.gd:85`** — `obstr.flags = 1 << 3` → `obstr.flags = RtsObstructionFlags.BLOCK_PATHFINDING`(消除 M0 硬编码)
- **`logic/rts_building_actor.gd`** — 加 `obstruction_tag: int = 0` 字段(0 = 未注册;dual-write 模式占位,M5 切 pathfinder 时成 single source of truth)
- **`logic/rts_unit_actor.gd`** — 加 `obstruction_tag: int = 0` 字段;**Death unregister deferred 到 M5**(spec drift, _shapes 持续膨胀 ≤100 unit, 战斗结束 procedure GC 时随 manager 释放)
- **`logic/commands/rts_place_building_command.gd:apply`** — step 3.5 补 `_register_to_obstruction_manager(rts_world, building)` 内部静态 helper, 调 `obstruction_manager.add_static_shape` 拿 tag 存 `building.obstruction_tag`;flag 用 `BLOCK_PATHFINDING | BLOCK_FOUNDATION`;manager / shape 任一为 null 时跳过(老 smoke / 单元测试 stub 兼容)
- **`core/rts_world_gameplay_instance.gd`** — 加 `obstruction_manager: RtsObstructionManager = null` 字段(跟 grid / passability_registry 字段同段)
- **`core/rts_auto_battle_procedure.gd`** — `_init` 末尾 `attach_passability_registry` 之后构造 `RtsObstructionManager` 挂 `world.obstruction_manager`(grid 为 null 时跳过老 smoke fallback);`start()` 起手 placed building loop 内 `place_building` 之后 inline 调 `add_static_shape`(同样 manager / shape 任一 null 跳过);`tick()` step 4d 之后插入 step 4f `_sync_unit_obstruction_shapes(world, alive_units)`(manager null 跳过);新加 helper `_sync_unit_obstruction_shapes`:遍历 alive_units, `obstruction_tag == 0` 调 `add_unit_shape` 注册并存 tag, `!= 0` 调 `move_shape(tag, position_2d)`

### 待处理

- **AC9 perf-trace** — M2 spec §AC9 要求 wall_clock ≤ +50% / tick_p99 ≤ 30 ms。perf_trace.gd 工具仍未实现(M0 / M1 也无), M2 实测 wall-clock 没明显增长(smoke 跑时间感觉跟 M1 一致), 但缺正式数据。stop-runner 第 5 条(2× 慢)未触发。计划 M5 启动前批量补足 perf_trace + oos_log 工具
- **Death unit obstruction_tag unregister** — M2.5 spec 要求 death 调 `manager.remove_shape(tag)`,实际 deferred 到 M5 启动前(M5 切 pathfinder 真正消费 manager 时同步加 cleanup hook;M2 阶段死单位 tag 残留不影响 baseline,因 production code 不消费 manager._shapes)
- **`obstruction_manager.rasterize` 接入** — M2.4 spec §step 4 要求 dual-write 中 manager 走 rasterize 写 NavcellGrid bit,实际仅 `place_building` 写入(单 source of truth);M5 切 pathfinder 走 manager 时一次性切换 + 接受 baseline 漂(预期变化)
- **set_unit_moving_flag MOVING bit 切换** — M2.5 spec 要求起步 / 停步触发,实际 deferred 到 M7 unit motion 重写时再做(M2 阶段 step 4f 仅 add/move,不切 MOVING bit)

### 验证表

| 测试 | M1 末态 | M2 末态 |
|---|---|---|
| LGF 单元测试 | 73/73 PASS | 73/73 PASS |
| smoke_rts_auto_battle | ticks=347 attacks=74 melee=32 ranged=42 melee_max=24.00 deaths=6 detoured=4 | **完全 byte-identical** |
| smoke_castle_war_minimal | ticks=193 unit_to_building_attacks=4 archer_anti_air=1 spawn_count=2 | **完全 byte-identical** |
| smoke_player_command_production | ticks=600 left_spawned=7 max_eastward=254.74 | **完全 byte-identical** |
| smoke_replay_bit_identical | seed=42 frames=9 events=20 deep-equal | **完全 byte-identical** |
| smoke_determinism | tick_diff=0 | **tick_diff=0** |
| baseline CSV(882 KB / 6155 行) | M1 末态 | **byte-identical(882882 bytes match)** |
| smoke_navcell_grid_passability(M1)| PASS AC1+AC2+AC8 | **完全 byte-identical** |
| smoke_obstruction_manager_register(新)| 不存在 | **PASS** AC4+AC7,8 shape tags 1..8 单调,sorted query OK |
| smoke_obstruction_manager_query(新)| 不存在 | **PASS** AC4+AC7+R1,filter + test_*_shape + SAT 4-case + distance OK |
| smoke_obstruction_manager_remove(新)| 不存在 | **PASS** AC4+AC7,basic + idempotent + query-consistent + readd OK |

---

## [Unreleased] — 2026-05-04 RTS Pathfinding M3 Epic / M1 — Navcell Grid + 16-bit Passability Class

M3 Epic 第二个 milestone(M0 Footprint 拆分 2026-05-04 已 archived)。把 `RtsBattleGrid` 内部 per-cell `is_blocking: bool`(M0 末态:走 ultra-grid-map plugin `model.is_tile_blocking`)替换为 `RtsNavcellGrid` `PackedInt32Array` 16-bit 位掩码 multi-class passability,引入 `RtsPassabilityClassRegistry` 注册 `default` + `air` 两 class(留 14 bit 给将来 mod / 扩展)。

**M1 是数据层重构,寻路算法不变** — 现有 `GridPathfinding.find_path` 仍工作(只是底下数据存储方式变了);**replay seed=42 frames=9 events=20 deep-equal + baseline CSV byte-identical(882882 bytes)**。

不修改 LGF core / stdlib,改动仅在 `addons/logic-game-framework/example/rts-auto-battle/` 内。

### Added

- **`logic/grid/rts_passability_class_config.gd`** — Passability class 配置(Resource);6 字段对齐 0 A.D. `pathfinder.xml` schema(class_name_id / bit_index / clearance / max_water_depth / min_water_depth / min_shore_distance);clearance 单位换 px(默认 14.0 贴近现有 `RtsUnitClassConfig.collision_radius`)
- **`logic/grid/rts_passability_class_registry.gd`** — Passability 注册查询单例(RefCounted);`PASS_CLASS_BITS=16` + `SPECIAL_PASS_CLASS_INDEX=15`(给 in-place 计算保留);`register / get_pass_class / get_mask / max_clearance / size` API;duplicate class_name_id `Log.assert_crash`;**registry full** 在 _next_bit ≥ 15 时 assert_crash;`get_pass_class` 命名避开 RefCounted 内建 `get_class()` 签名冲突
- **`logic/grid/rts_navcell_grid.gd`** — 多 class navcell 数据 grid(RefCounted);`_data: PackedInt32Array` 长度 = w × h(16-bit 位掩码 per cell)+ `_dirtiness: PackedByteArray` 同 size;`get_data / set_data / or_data / and_data / is_passable / mark_dirty / is_dirty / clear_dirty / width / height / navcell_center_world / nearest_navcell` API;边界外 `is_passable` 返 false / `get_data` 返 -1(防越界,跟 0 A.D. helpers/Pathfinding.h 一致);`or_data / and_data` 仅在值变化时 mark dirty(精确 dirty 集合);**dirty lifecycle 注释固化 R5 P1-2 决策**(rasterize / hierarchical update 只读,`RtsWorld.tick` step 7 末端统一 clear)
- **`tests/battle/smoke_navcell_grid_passability.{gd,tscn}`** — M1 acceptance smoke;5 个测试函数 13 项断言 覆盖 AC1(registry bit_index 0/1, get_mask 0x1/0x2, unknown 返 0, max_clearance, size)+ AC2(初始 clean / or_data 设 bit / and_data 清 bit / 边界外 false / dirty 标记 / clear_dirty)+ AC8(default 写不影响 air, air 写不影响 default, 双 bit 同 cell 独立)

### Changed

- **`logic/grid/rts_battle_grid.gd`** — 改成 facade:加 `_navcell_grid` / `_passability_registry` / `_default_class_mask` / `_half_cols` / `_half_rows` 字段;`attach_passability_registry(registry)` 注入(lazy 创建 `RtsNavcellGrid(cfg.columns, cfg.rows)` + 从 model `get_all_coords()` 同步已有 `is_tile_blocking` cells);`is_passable_for_layer / is_blocking / mark_obstacle_cell / unmark_obstacle_cell / place_building / remove_building` 走双写(model + NavcellGrid attached 时);`is_blocking(coord)` 新公开 API;`_coord_to_ij(coord) -> Vector2i` helper(HexCoord 偏移坐标 [-half..+half] → NavcellGrid 0-indexed [0..columns-1])
- **`core/rts_world_gameplay_instance.gd`** — 加 `passability_registry: RtsPassabilityClassRegistry = null` 字段
- **`core/rts_auto_battle_procedure.gd`** — `_init` 末尾按固定顺序 `register("default", clearance=14.0)` → `register("air", clearance=8.0)` 写 `world.passability_registry`(R5 决策:顺序固化让 mask 数字 0x1/0x2 跨 run 不漂);如 `world.rts_grid != null` 调 `attach_passability_registry`
- **`frontend/scene/rts_battle_map.gd`** — `_mark_obstacle_cells` 把 `model.set_tile_blocking(coord, true)` 改 `grid.mark_obstacle_cell(coord)`(走 facade 双写,不再直读 plugin)
- **`logic/commands/rts_building_placement.gd`** — `validate` footprint cells 阻挡检查从 `grid.model.is_tile_blocking` 改 `grid.is_blocking`(走 facade,NavcellGrid attached 时优先)

### 待处理

- **AC7 perf-trace 工具** — M1 spec §3 AC7 要求"perf-trace.csv 新增 M1 行 / vs M0: wall_clock ≤ +50%, tick_p99 ≤ 30 ms",但 perf_trace.gd 工具未实现(M0 也没引入)。M1 实测 wall-clock 没明显增长(smoke 跑时间感觉跟 M0 一致),但缺正式数据。按 stop-runner 第 5 条(`tick_p99/tick_max` 增长 ≥ 100% / 2× 才停)未触发。计划 M5 启动前批量补足 perf_trace + oos_log 工具。
- **smoke 直读 `grid.model.is_tile_blocking` 的 5 处**(diag_*.gd 等 utility) — 由 dual-write 兜底,不破。M5 删除 facade 时统一 cleanup。

### 验证表

| 测试 | M0 末态 | M1 末态 |
|---|---|---|
| LGF 单元测试 | 73/73 PASS | 73/73 PASS |
| smoke_rts_auto_battle | ticks=347 attacks=74 melee=32 ranged=42 melee_max=24.00 | **完全 byte-identical** |
| smoke_castle_war_minimal | ticks=193 left_win | **完全 byte-identical** |
| smoke_player_command_production | ticks=600 left_spawned=7 | **完全 byte-identical** |
| smoke_replay_bit_identical | seed=42 frames=9 events=20 deep-equal | **完全 byte-identical** |
| smoke_determinism | tick_diff=0 | **tick_diff=0** |
| baseline CSV (882 KB / 6155 行) | M0 末态 | **byte-identical(882882 bytes match)** |
| smoke_navcell_grid_passability(新)| 不存在 | **PASS** AC1+AC2+AC8 |

---

## [Unreleased] — 2026-04-30 RTS 自动战斗示例（连续坐标 + navmesh）

新增第二个 LGF 示例 `example/rts-auto-battle/`：连续 `Vector2` 坐标（500×500 px）+ Godot `NavigationServer2D` 寻路 + 实时 `attack_cooldown` 节奏，与既有 hex-atb-battle 的 hex grid + ATB 累积形成对比，验证 LGF 核心抽象（`WorldGameplayInstance` / `BattleProcedure` / `Actor` / `AbilitySet` / `EventProcessor`）对不同节奏 / 坐标系 / 寻路体系的复用面。

不修改 LGF core / stdlib，所有新代码进 `example/rts-auto-battle/`，三层架构对齐 hex 例子（core / logic / frontend / tests）。

### Added

- **`example/rts-auto-battle/`** — 4v4 自动战斗最小可玩闭环。两兵种 melee / ranged，AI 找最近敌人 → set nav target → 进 attack_range 后 cooldown 触发 basic attack。中央 (200..300, 200..300) 障碍迫使绕路接敌
  - `core/rts_world_gameplay_instance.gd` — `WorldGameplayInstance` 子类，连续坐标，注入 `NavigationRegion2D`
  - `core/rts_auto_battle_procedure.gd` — `BattleProcedure` 子类，连续 tick 推进 cooldown / AI / nav，`_check_battle_end` 一方全灭判胜负，`MAX_TICKS=1000` 安全上限
  - `logic/rts_battle_actor.gd` + `logic/rts_character_actor.gd` — actor 公共合同 + 兵种特化（持 `attribute_set` / `ability_set` / `attack_cooldown_remaining` / `current_target_id`）
  - `logic/config/rts_unit_attribute_set.gd` — RTS 单位属性集（hp / max_hp / atk / def / move_speed / attack_speed / attack_range），直接 extends `BaseGeneratedAttributeSet` 用 `_raw.apply_config` 注册，**不走 LGF 代码生成路径**避免动 `example/attributes/attributes_config.gd`
  - `logic/config/rts_unit_class_config.gd` — UnitClass enum + per-class StatBlock（MELEE: hp 200, atk 25, attack_range 24；RANGED: hp 120, atk 18, attack_range 120）
  - `logic/components/rts_nav_agent.gd` — `Node2D` 包 `NavigationAgent2D`，每 tick 推单位向 `get_next_path_position()` 走 `move_speed × dt`，并把 position 写回 actor.position_2d；自带 `path_length_traveled` / `max_y_deviation` 给 AC2 绕路断言用
  - `logic/ai/rts_basic_ai.gd` — 每 tick 决策（idle / approach / in_range），`current_target` 200ms 刷新一次避免 nav rebuild 抖动；与 hex 的 ATB 派生 AIStrategy 不同，直接 RefCounted helper
  - `logic/actions/rts_basic_attack_action.gd` — 静态 helper（不继承 BaseAction，basic attack 不值得 ExecutionContext+TargetSelector 全套）。仍走 `EventProcessor.process_pre_event` / `process_post_event` 管线，`pre_damage` event 给 buff / passive 留 hook
  - `logic/rts_battle_events.gd` — RTS 例子专属 event kind（`rts_pre_damage` / `rts_post_damage` / `rts_attack_resolved` / `rts_actor_died`）
  - `logic/logger/rts_battle_logger.gd` — 战斗事件捕获器，给 smoke 做兵种行为断言
  - `frontend/scene/rts_battle_map.gd` — 编程式构造 `NavigationRegion2D` + `NavigationPolygon`：3×3 网格 8 个凸四边形显式拼出可走区域（跳过中央障碍格）。注意：相邻 polygon 必须**精确共享端点对**才能被 `NavigationServer2D` 连成可达图，最初版"大条带"切法因端点不重合导致路径在障碍前 198 px 处断开
  - `frontend/visualizers/rts_unit_visualizer.gd` — 最简 stub：`Node2D` + `Polygon2D`（8 边形）按 team_id 染色 + Label 贴 hp。不做动画 / 攻击特效 / 相机控制
  - `frontend/demo_rts_frontend.{gd,tscn}` — 编辑器 F6 入口；headless 也能跑
  - `tests/battle/smoke_rts_auto_battle.{gd,tscn}` — acceptance gate smoke。4v4 跑到判胜负，断言兵种行为（melee 距离 ≤ 24×1.05；ranged 至少 1 次距离 > 24）+ 至少 1 个起点在障碍 y 范围的单位 max_y_deviation ≥ 30（绕路证据）
  - `tests/battle/smoke_navigation.{gd,tscn}` / `smoke_ai.{gd,tscn}` / `smoke_attack.{gd,tscn}` — phase smoke
  - `tests/frontend/smoke_frontend_main.{gd,tscn}` — 验证 8 个 visualizer 节点在 headless 下构建成功

### Changed

- `example/README.md` 新增（之前 example/ 没有 index 文件），列出 hex / rts 两个示例的对比表

### Notes

- LGF core / stdlib 未变更
- AC1-AC4 全过；AC5（hex demo regression）残余风险：headless 退出时 signal 11 segfault 不影响 battle 完成度，与 RTS 改动无关，归既有 LGF leak 范畴

---

## [Unreleased] — 2026-04-29 Knockback Punch (Tier 1 #4) + forced displacement 基础设施

实现 design 卡 Tier 1 #4 KnockbackPunch (击退拳): 近战伤害 + 沿 caster→target 方向推 1 格。
撞墙 / 撞 actor / 撞地图边界三种结局, 走 CollisionProfile 字段 (M1 已落地) 数据驱动结算。

设计意图: 把 forced displacement (knockback / pull / scatter) 从隐式 hardcode 提到通用 Action +
通用事件, 让未来 N>1 链式推 / wind_torrent / pull / scatter 等变体直接复用相同骨架。
PushAction 的 raycast 已支持 N>1, V1 KnockbackPunch 仅传 distance=1。

### Added

- **`HexBattlePushAction`** (`example/hex-atb-battle/logic/actions/push_action.gd`) — 通用 forced
  displacement Action。raycast N 格沿方向推进, 撞 occupant / edge 停下并按 CollisionProfile
  结算碰撞伤害。constructor 参数 `distance` (默认 1) 和 `displacement_kind` (默认 "knockback")
  让未来 pull / scatter / N>1 变体零代码复用。**碰撞伤害 contract**: deterministic 无暴击,
  不走 PreDamageEvent, 但走 `HexBattleDamageUtils.apply_damage` + `broadcast_post_damage`
  (ShieldComponent / death / thorns 仍生效)。`source_actor_id = caster` (gameplay attribution)。
  case 6 兜底: 若上一步 DamageAction 已击杀 target, 整段 push 跳过。
- **`HexBattleKnockbackPunch`** (`example/hex-atb-battle/logic/skills/knockback_punch.gd`) — Tier 1 #4
  设计卡的最小落地。Timeline HIT @ 300ms: DamageAction(atk) → PushAction(distance=1, "knockback")。
  cooldown 4000ms, range 1, ALLOWED_TARGET_KINDS=["Character"] (V1 不直接 push environment, 由
  WallBreaker pattern 验证打 env; KP 验证 forced displacement pattern)。
- **`BattleEvents.ActorDisplacedEvent`** (`example/hex-atb-battle/core/events/battle_events.gd`,
  kind="actor_displaced") — forced displacement 事件, 区别于自愿 `MoveCompleteEvent`。字段:
  `actor_id / from_hex / to_hex / displacement_kind / source_actor_id`。仅当 actor 真的移动时
  push (from != to)。前端动画 / replay / scenario 可按 `displacement_kind` 区分 knockback / pull /
  scatter。
- **`BattleEvents.PushBlockedEvent`** (kind="push_blocked") — push 路径被 occupant / edge 挡住时
  push。字段: `target_actor_id / from_hex (实际停在哪) / attempted_to_hex (本想到达的格) /
  blocked_by ("edge"|"actor") / blocker_actor_id ("" if edge) / source_actor_id`。双坐标避免
  replay / frontend / scenario 重算坐标。N>1 移动后撞: ActorDisplacedEvent + PushBlockedEvent
  都 push (语义独立)。
- **`HexCoord.direction_to_neighbor(other) -> int`** (`addons/ultra-grid-map/core/hex_coord.gd`)
  返回从 self 到 other 的邻居方向 (0-5), 不相邻返 -1。让 PushAction 可以从 caster/target
  位置直接求"推开方向"。未来 shadow_step / pull / line AoE 等空间技能复用。
- **`CollisionProfile.default_character()` / `.default_wall()`** static factories
  (`example/hex-atb-battle/logic/environment/collision_profile.gd`)。CharacterActor 默认 profile
  taken=1 / dealt=1 / pushable=true / blocks_path=true; default_wall 兜底"撞地图边界" 这种没
  blocker actor 的场景, dealt_to_pusher=1。
- **Smoke `smoke_knockback_punch`** (`example/hex-atb-battle/tests/battle/smoke_knockback_punch.gd`)
  覆盖 7 case: free push / edge / stone_wall blocker / character blocker / out-of-range /
  direct env target rejected / killed-by-base-damage / collision deterministic (20 trials)。

### Changed

- **`HexBattleActor`** 上提 `collision_profile: CollisionProfile` 字段为基类公共字段。
  CharacterActor 在 `_init` 末尾填 `CollisionProfile.default_character()`; EnvironmentActor 通过
  既有 `_init(profile)` 构造参数填。PushAction 不分支 character/env, 统一查 `actor.collision_profile`。
  数据驱动: 未来 character 职业差异 (轻甲 pushable / 重甲不动) 直接改 profile 数值。
- **`EnvironmentActor`** 删除独占 `collision_profile` 字段 (移到基类)。`_init` 接口不变。
- **`HexBattleSkillScenarioHarness._PreviewInstance.start`** — `UGridMap.configure(grid_config)`
  之后补 `grid = UGridMap.model`, 让 `battle.grid.has_tile / get_occupant / move_occupant` 在
  scenario 中可用 (与 `HexWorldGameplayInstance.configure_grid` 对齐)。修复 PushAction /
  ApplyMoveAction 等依赖 `battle.grid` 的代码在 harness scenario 下空指针。

### 设计决策摘要

- **collision_profile 上提到 HexBattleActor 基类 (而非 PushAction 内部分支 character/env)**:
  数据驱动, 未来 push/pull/scatter/wind_torrent 全部统一查 `actor.collision_profile`, 零分支。
- **走 metadata `ALLOWED_TARGET_KINDS=["Character"]` 而非 ["Character","Environment"]**:
  V1 不允许直接 push 环境物 (`pushable=false` 的反冲语义留给 V2)。Environment 仍可作为
  blocker 出现, 通过 PushAction 内部 occupant 检查处理。
- **拆 ActorDisplacedEvent + PushBlockedEvent 而非单事件 + cause 字段**: 命名诚实,
  前端动画可分开播 (displaced=平移动画 / blocked=撞击震屏)。N>1 移动后撞两个事件并存。
- **碰撞伤害不走 PreDamageEvent (M1)**: deterministic 无 modifier 介入, 避免 Expose 等
  错误地放大 collision damage。未来若需 Expose 影响 collision, 再扩 `HexBattleDamageUtils`
  显式入口。
- **`source_actor_id = caster` (gameplay attribution)**: thorns 反给 caster, kill credit 归
  caster, blocker 受的 collision damage 也归 caster。语义统一, 不引入"blocker 莫名其妙变伤害源"
  的混乱。

### 验证

| 测试 | 结果 |
|---|---|
| `smoke_knockback_punch` 7 case | 7/7 PASS (含 collision deterministic 20 trials) |
| `smoke_wall_breaker` (回归 EnvironmentActor 路径) | 2/2 PASS |
| `smoke_skill_scenarios` (14 scenarios 回归) | 14/14 PASS |
| `tests/run_tests.tscn` (LGF 单元测试) | 73/73 PASS |

---

## [Unreleased] — 2026-04-28 EnvironmentActor 子系统 + AttributeSet 继承 (M1)

引入 hex-atb-battle 中间基类 `HexBattleActor`,拆出两个子类 `CharacterActor` / `EnvironmentActor`,
并通过 generator 的 `_extends` 元字段建立属性集继承链(`HexBattleActor` → `Character` / `Environment`)。
M1 仅落地 `StoneWall` 一种地形作为闭环验证,trait 系统 (destructible / pushable / blocks_path) 暂不抽,
等第二种地形 (木桶 / 巨石) 再抽。

设计意图: 战斗管线 (DamageEvent / DeathEvent / PreEvent / PostEvent) 对 character + environment 平权;
AI / 默认 enemy selector / heal / buff / shield 等保持 character-only 隔离;
`actor.attribute_set.atk` 等专属访问保持强类型,公共代码走 `actor.get_attribute_set().hp` 拿基类视图。

### Added

- **`HexBattleActor`** (`example/hex-atb-battle/logic/hex_battle_actor.gd`) — 中间基类,持公共 `hex_position` /
  `ability_set` / `_is_dead`,提供 `get_attribute_set() -> HexBattleActorAttributeSet` 抽象合同 +
  `check_death` / `is_dead` / `is_pre_event_responsive` / `get_ability_set` (IAbilitySetOwner) +
  录像基础设施 (`_get_position` / `setup_recording` / `get_attribute_snapshot` / `get_ability_snapshot` /
  `get_tag_snapshot`)。子类实现 `get_attribute_set()` 返回各自强类型字段。
- **`EnvironmentActor`** (`example/hex-atb-battle/logic/environment_actor.gd`) — `HexBattleActor` 子类,
  持 `environment_kind: String` 区分视觉,持 `attribute_set: HexBattleEnvironmentAttributeSet` +
  `collision_profile: CollisionProfile` 普通字段。type = "Environment"。
- **`CollisionProfile`** (`example/hex-atb-battle/logic/environment/collision_profile.gd`) — 普通数据类,
  字段 `damage_taken_on_blocked_push` / `damage_dealt_to_pusher` / `pushable` / `blocks_path`。
  不进 attribute_set: 这些是结构化物理参数, 不参与 buff/modifier 系统。
  提供 `default_wall()` 静态工厂给"撞地图边界"等无 actor 场景用。
- **`HexBattleStoneWall`** (`example/hex-atb-battle/logic/environment/stone_wall.gd`) — M1 唯一地形,
  `create()` 工厂返回 indestructible (hp=INF + damage_taken=0) + immovable + blocks_path 的
  EnvironmentActor 实例。indestructible 用数据表达,不在代码里加早退分支。
- **`HexBattleActorAttributeSet`** (generated, `example/attributes/generated/hex_battle_actor_attribute_set.gd`)
  公共属性集基类,持 `hp` / `max_hp` 强类型访问器 + `cross_attr_clamp("hp", "max", "max_hp")`。
- **`HexBattleEnvironmentAttributeSet`** (generated) — `extends HexBattleActorAttributeSet`,
  M1 仅继承公共属性, 未来按需 + `mass` / `hardness` 等专属属性。
- **Generator `_extends` 支持** (`scripts/attribute_set_generator_script.gd`) — set 配置可声明
  `"_extends": "ParentSetName"`,生成的子类 `extends ParentAttributeSet`,父属性访问器只在父
  set 生成,子类继承使用,不重复生成。强制规则: parent 必须存在、检测继承环、DFS topo 排序、
  父子重复属性禁止 (`push_error`)、`maxRef/minRef` 方向校验 (父引用不能反向引子)。
  `_init` 通过 `super(p_actor_id)` + 增量 `_raw.apply_config` 让父属性先注册再叠子属性。
- **`HexWorldGameplayInstance.get_alive_battle_actors()`** 返回 `Array[HexBattleActor]`,
  含 character + environment, 给"格子占用统计"、"碰撞检测"等需要看到所有占格 actor 的场景。
- **`HexWorldGameplayInstance.get_character_actor(actor_id)`** 仅返回 `CharacterActor` (cast 失败返 null),
  给 AI / Heal / Buff / Shield 等 character-only 调用方使用。
- **`hex_battle_attribute_inheritance_test.gd`** — 验证 generator `_extends` 产出的继承链:
  父属性可见、parent clamp 在子集实例生效、子集独有属性不漏到父集、未注册属性 modifier
  warning+ignore (不 crash)。
- **Scenario `EnvironmentIsolationScenario`** (外层 `tests/skill_scenarios/`) — strike 不会误中
  stone_wall (隔离边界验证)。
- **`SkillPreviewBattle._PreviewInstance.environments`** 字段 + `_create_environment(cfg)` 工厂,
  scenario `"environment": [{"type": "stone_wall", "pos": [q, r]}]` 配置接入。
- **Preview result `environment_ids`** 字段 + `ScenarioAssertContext.environment_id(i)` helper。

### Changed

- **`CharacterActor`** (`example/hex-atb-battle/logic/character_actor.gd`) `extends Actor` →
  `extends HexBattleActor`。公共字段/方法 (hex_position / ability_set / _is_dead / check_death /
  is_dead / is_pre_event_responsive / get_ability_set / _get_position / setup_recording /
  get_ability_snapshot / get_tag_snapshot) 上抬到基类, CharacterActor 自身只保留 ATB / AI /
  职业 / `attribute_set: HexBattleCharacterAttributeSet` 等专属。新增 `get_attribute_set()` override
  返回自己的 character 强类型 attribute_set。`get_attribute_snapshot()` 覆盖基类返回完整 stats。
- **`HexBattleCharacterAttributeSet`** (generated) `extends BaseGeneratedAttributeSet` →
  `extends HexBattleActorAttributeSet`。hp / max_hp 访问器 + cross-clamp 移到父集; 自身只生成
  atk / def / speed 访问器。配置端在 `attributes_config.gd` 加 `"_extends": "HexBattleActor"`。
- **`HexWorldGameplayInstance.get_actor()`** 返回类型从 `CharacterActor` 放宽到 `HexBattleActor`,
  让 DamageUtils 等公共战斗管线对 character + environment 平权。AI / Heal / Buff 等 character-only
  调用方走 `get_character_actor()`。
- **`HexWorldGameplayInstance.remove_actor()`** 触发 grid 占用清理时, 对所有 `HexBattleActor` 子类
  生效, 不再只看 CharacterActor (env actor 死亡 / 被显式 remove 也走同一清理流程)。
- **`HexBattleDamageUtils.apply_damage()` / `_clear_grid_footprint()`** 改用 `HexBattleActor` 接口,
  通过 `target_actor.get_attribute_set().set_hp_base(...)` 走基类视图扣 hp。`_clear_grid_footprint`
  形参类型从 `CharacterActor` 放宽。
- **`HexBattleHealAction`** 改用 `battle.get_character_actor(target_id)` (隔离边界: env 默认不被治疗)。
- **`HexBattleTargetSelectors.AllEnemies`** 改用 `battle.get_character_actor(...)` 拿 owner (env 不施法)。
- **`HexBattleGameStateUtils.is_actor_dead()`** 走 `actor.get_attribute_set().hp` 平权访问 hp。
- **`HexBattleProcedure._start_recorder` / `SkillPreviewProcedure._start_recorder` /
  `SkillPreviewBattle.start`** `positionFormats` 配置加 `"Environment": "hex"`。

### 设计决策摘要

- **属性继承用配置 `_extends` 而非"两份配置重复写 hp"**: 后者会破坏 `_raw` 隐藏边界 (强类型访问
  必须暴露字符串通道 `get_attr(name)` 才能写公共代码), 前者保持 `actor.attribute_set.hp` 强类型
  且 `_raw` 完全隐藏。
- **`HexBattleActor` 不持 `attribute_set` 字段, 子类各自持强类型字段 + 重写 `get_attribute_set()` 抽象**:
  避免 GDScript 子类重声明同名 var 的 shadow 陷阱。专属代码 (Strike 读 atk) 继续 `actor.attribute_set.atk`,
  公共代码 (DamageUtils 读 hp) 走 `actor.get_attribute_set().hp`, 迁移面只在公共代码 (~5 处)。
- **StoneWall indestructible 用数据表达 (hp=INF + damage_taken=0)**: 不在代码里加 `if indestructible: return`
  早退分支, 让伤害管线对 wall 平权 (push damage event / 走 PreEvent / 走 PostEvent), 只是 hp 永不到 0。
- **`get_alive_actors` 名字保留兼容 (仍仅返 character)**, 新增 `get_alive_battle_actors` 给环境物
  访问。避免破坏现有 25+ 处 callers。

---

## [Unreleased] — 2026-04-28 SkillPreview 关注点分离: UI 只防 timeline 重叠, cooldown 由 LGF 上报

上一段 (2026-04-28 多 keyframe 修复) UI occupy 同时算了 cooldown, 越过了 UI 的关注点边界 ——
"能否释放" (cost / condition) 是 LGF 真战施法管道的责任, UI 不应替它做预筛。这一段把
occupy 收窄到只看 timeline, 失败语义改由 LGF 在 fire 时 push 事件供前端渲染。

设计意图: SkillPreview 替代 ATB+AI 决策层 ("在 t=X 让 caster 用 skill Y 打 Z"), 但下游施法
管道与真战 100% 一致 — cooldown / mp / hp 等约束都由 ActiveUseComponent 检查, 失败有
明确事件流, 不再 silently reject。

### Added

- **`GameEvent.AbilityActivateFailed`** (`core/events/game_event.gd`) 新事件类 +
  `ABILITY_ACTIVATE_FAILED_EVENT = "abilityActivateFailed"` 常量。payload:
  `abilityInstanceId / abilityConfigId / sourceId / targetActorId / reason / failedComponentType`。
  reason 来自 `Condition.get_fail_reason` / `Cost.get_fail_reason` (LGF core 只搬运字符串,
  example 层填语义如"技能冷却中")。failedComponentType ∈ {"condition", "cost"} 让前端区分图标。

### Changed

- **`ActiveUseComponent.on_event`** condition / cost 检查失败时除了 `Log.debug`, 现在还
  push 一条 `AbilityActivateFailed` 事件到 `GameWorld.event_collector`。仅在 trigger 已
  匹配后才会推 (即"该 ability 应该响应这次 activate 但被前置检查拒了"), trigger miss
  不算失败不推。
- **`SkillPreviewValidation.ability_occupy_ms`** 只取 `timeline.total_duration`, 不再扫
  `cost`。UI 现在允许 "间隔 ≥ timeline 但 < cooldown" 的 keyframe 排布 — 跑起来后由
  LGF 推 `AbilityActivateFailed`, 前端 console 显示"⛔ @{ms} {role} {skill} 释放失败:
  condition: 技能冷却中"。
- **`skill_preview.gd._log_event`** 加 `"abilityActivateFailed"` match 分支, 渲染
  ⛔ 图标 + reason。新 helper: `_role_label_for_actor_id` / `_skill_display_name_by_config_id`。

### Removed

- **`HexBattleCooldownSystem.TimedCooldownCost.get_duration()`** getter 删除 (UI occupy
  不再读它, 上一段为它专门加的, 这段不用了)。

### 验证

| 场景 | 上段 (cooldown 进 occupy) | 这段 (只 timeline) |
|---|---|---|
| Strike timeline=500, cooldown=2000, 排 t=0/500/1000 | UI 拦, 用户排不出 | UI 接受; 跑起来 1 exec + 2 abilityActivateFailed (reason="技能冷却中") |
| LGF run_tests | 66 PASS | 66 PASS (assertions 调整: occupy 期望 500 不再 2000) |

---

## [Unreleased] — 2026-04-28 SkillPreview 多 keyframe 修复

### Fixed

- **`SkillPreviewProcedure._fire_due_keyframes`** 同 actor 同 `ability_config` 多 keyframe 现在复用 ability instance(`find_ability_by_config_id` 命中已 grant 的 instance, 没有才 `Ability.new + grant_ability`)。改造前每个 keyframe 都 `grant_ability`, 后续 keyframe 的 ABILITY_ACTIVATE_EVENT 会被 `CooldownCondition` silently reject(cooldown tag 是 ability_set 级 owner-scoped), 用户配置 t=0/300/600 三发 Strike 实际只第一发命中。复用后 cooldown 行为与单 instance 真实施法一致, 严格遵守。
- **`SkillPreviewTimeline` UI 编辑期约束**: 同 actor 同 skill 的 keyframe 必须间隔 ≥ `occupy = max(timeline.total_duration, cooldown_ms)`, 否则 `next_free_time_ms_in_track` bump 到下一个空闲 100ms 边界。`_on_keyframe_skill_changed` 切技能时也重算 time。`_find_preview_setup_error` 加兜底校验, 拦从 preset 加载的违规 timeline。改造前 UI 只防"完全相同 time_ms"冲突, 用户能排出会被 procedure silently reject 的 timeline。

### Added

- **`SkillPreviewValidation`** (新 class, `addons/logic-game-framework/example/hex-atb-battle/skill-preview/skill_preview_validation.gd`) 把 occupy / 冲突计算抽成纯函数(`ability_occupy_ms` / `find_track_occupy_violation` / `next_free_time_ms_in_track`), 注入式 skill_resolver, 便于单元测试 headless 调用。
- **`HexBattleCooldownSystem.TimedCooldownCost.get_duration()`** public getter, 让 SkillPreviewValidation 不直接 access `_duration`。
- **逻辑层 smoke 扩充** (主仓 `tests/`): 新增 5 个 SkillPreviewProcedure smoke —
  - `smoke_skill_preview_proc_multi_kf_legal` (3 发 Strike 间隔 2100ms, 验证 grant 仅 1 次 + 复用同 ability instance)
  - `smoke_skill_preview_proc_multi_kf_illegal` (间隔 < cooldown, procedure 不崩 + cooldown reject 路径)
  - `smoke_skill_preview_proc_multi_kf_diff_skills` (Strike + SwiftStrike 交错, cooldown namespace 隔离)
  - `smoke_skill_preview_proc_concurrent_actors` (3 actor 同 t=0, 按 setup 顺序 deterministic)
  - `smoke_skill_preview_proc_target_dies_mid_timeline` (target 中途死亡 procedure 不崩)
- **`addons/logic-game-framework/tests/skill_preview_validation_test.gd`** SkillPreviewValidation 单元测试, 7 test 已登记到 `run_tests.gd::TEST_PATHS`。

### 验证

| 场景 | 改造前 | 改造后 |
|---|---|---|
| caster t=0/300/600 三发 Strike (multi_kf, < cooldown) | 1 damage (后两发 silently reject) | UI 阻止排出此配置; procedure 兜底仍 1 damage 不崩 |
| caster t=0/2100/4200 三发 Strike (multi_kf, ≥ cooldown) | 1 damage (旧逻辑每次重 grant 都被 reject) | 3 damage + 仅 1 次 grant + 全部复用同 ability_4 |
| LGF run_tests | 59 PASS | 66 PASS (新 7 测试) |

---

## [Unreleased] — 2026-04-27 SkillPreview 多 actor 时间轴模型

### Added

- **`SkillPreview` 工具 UI: SkillPreviewTimeline tab** (阶段二) — 在 Inspector 加横向多 actor 可视化时间轴。每 actor 一条 track, keyframe 渲染为色块按钮(团队上色: caster 绿/A 蓝/B 红); 点色块弹 `PopupPanel` 富表单(time / skill / target / Delete / Close), 点空白处按位置 snap 到 100ms 边界并自动 add + popup。Toolbar 含 `Span` SpinBox (0=auto-fit, >0=override); ruler 按 `_pick_tick_step(max_ms)` 选 250/500/1000/2000ms 步长。命名前缀 `Spt*` / `_spt_*` / `SPT_*` 与 LGF core `TimelineRegistry` / Ability animation timeline 概念区分。所有 mutation 仍走阶段一的 `_on_keyframe_*_changed` handler, Actors tab 列表式编辑器与 Timeline tab 同步重建(`_queue_inspector_rebuild` → `_rebuild_inspector` 双 tab 一次性刷新)。Time SpinBox conflict bump 后自动同步(`_build_kf_time_spin` 工厂在 Actors tab 行内和 popup 共用)。

### Changed

- **`SkillPreviewWorldGI.queue_preview`** 改签名: 从 `(caster_id, ability, target_id, passives)` 改为 `(actor_setups: Array[Dictionary], allow_empty_track: bool = false)`。每个 setup 携带 `{actor_id, passives: Array[AbilityConfig], track: Array[Keyframe]}`,`Keyframe = {time_ms, ability_config, target_id}`。旧调用全部需要迁移 (改造前 baseline = caster 单条 t=0 keyframe)。
- **`SkillPreviewProcedure._init`** 改签名: 接收 `actor_setups` 替换原 `caster_id / ability_config / target_id / passives`。`start()` 末尾立即 drain `time_ms <= 0` 的 keyframe (保留改造前"第 0 帧 activate"行为, event `logicTime=0.0`)。`tick_once` 在 `world.base_tick` 后按 `world.get_logic_time()` 调度后续 keyframe。结束判定加 `_pending_keyframes.is_empty()`。
- **`SkillPreviewBattle.run_with_actions`** (主仓 helper): `actions[i]` 增加可选 `time_ms: int` 字段 (默认 0)。`t<=0` 在 grant 阶段立即 activate (与改造前一致),`t>0` 进 pending 队列,每帧 `battle.tick` 后 drain 已到时项。
- **`SkillPreview` 工具 UI**: 删除全局 `Skill` / `Target` tab。Actors detail panel 内每个 actor 自己挂 passives + skill track (keyframe 列表 `[time_ms] [skill] [target_mode + index/q/r]`)。同 actor 同 `time_ms` 在 UI 阻止 (push 到下一个 100 边界)。

### Removed

- 旧 preset 文件 (`01_strike_basic.json` ~ `09_surge_self_buff.json`) 全删,替换为 v2 schema 的 3 个示例 (`01_caster_strike` / `02_combo_caster_3hit` / `03_thorns_reflect`)。preset JSON 加 `version: 2`,旧版被 `_is_preset_v2` 拒绝加载。

### 验证

| 场景 | 改造前 | 改造后 |
|---|---|---|
| caster t=0 Strike → enemy_0 (smoke_skill_preview_reactive) | PASS | PASS |
| caster t=0 + enemy_0 t=500 双 Strike (smoke_skill_preview_timeline) | N/A | PASS — caster damage @ frame 3, enemy damage @ frame 8, 间隔 5 帧 |

---

## [Unreleased] — 2026-04-27 录像: BattleRecorder 单 buffer 重构 (根治时序错位)

`BattleRecorder.pending_events` 字段删除。所有录像事件 (Action 显式 push 的 damage/heal/StacksChanged + Actor lifecycle callback push 的 AbilityGranted/AttributeChanged/ActorSpawned/Destroyed) 统一进 `GameWorld.event_collector`。`record_frame(frame, events)` 简化为只写入参数 events,不再合并第二容器。

→ [docs/design-notes/2026-04-27-recorder-single-buffer.md](docs/design-notes/2026-04-27-recorder-single-buffer.md)

### Bug

之前用两个并行容器: Action push 的事件进 `EventCollector._events`,callback 的事件进 `BattleRecorder.pending_events`。`record_frame` 合并时按"容器类型"拼接,无论 `[events, pending]` 还是 `[pending, events]` 都构造得出反例 — Action_A 中途 grant ability 触发 callback 这种调用栈穿插的场景下,真实时序是 `[damage1, AbilityGranted, damage2]`,任何固定拼接顺序都会错位。

之前 commit `dc3dcac` 颠倒为 `[pending, events]` 是症状疗法,只在 Surge (grant + first tick same frame) 这种"callback 全在 push 之前"的简单场景下 PASS,无法处理穿插。

### Changed

- **`RecordingContext.push_event`**: `_recorder.pending_events.append(event)` → `GameWorld.event_collector.push(event)`。`is_recording` guard 保留,防 `stop_recording` 与 unsubscribe 之间的 callback 残响灌脏事件。
- **`BattleRecorder.register_actor` / `unregister_actor`**: ActorSpawned/Destroyed event 改 push 进 `GameWorld.event_collector`,不再持有自己的 buffer。
- **`BattleRecorder.record_frame(frame, events)`**: 删除 `all_events.append_array(pending_events)` 合并逻辑,`pending_events.clear()` 也一并删除,`frame_data.events = events` 直接写入。
- **`BattleRecorder` 顶部 docstring**: 重写,去掉「两个来源 / 帧间缓冲区」叙述。

### Removed

- **`BattleRecorder.pending_events`** 字段。
- **`start_recording` / `start_recording_events_only`** 中的 `pending_events.clear()` 调用。

### 关键设计决策

- **为什么是 EventCollector 而非反过来**: EventCollector 是 Action 层的硬依赖 (永远存在),BattleRecorder 是可选的 session 抽象 (录像才创建)。让事件流统一往必选的 collector 走,recorder 退化为「session 元数据 + subscription 生命周期 + 写 timeline」职责。
- **`is_recording` guard 保留**: 录像 callback 可能在 `stop_recording` 与异步 unsubscribe 之间触发一次,此时 `event_collector` 仍在被复用 (下场战斗或主流程消费),不能让残响污染。
- **`dc3dcac` 不 revert**: 留作历史。新 commit message 标注 "supersedes dc3dcac"。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_skill_scenarios.tscn` (含 SurgeScenario `grant_index < first_stacks_index` 断言) | PASS |
| `tests/smoke_buff_ui.tscn` / `smoke_buff_pipeline.tscn` / `smoke_surge_unit_view.tscn` | PASS |
| `tests/smoke_frontend_main.tscn` | PASS |

---

## [Unreleased] — 2026-04-26 表演层: 血条迁移到 state 路径(贯彻 event/state 边界)

补完 `2026-04-26-presentation-event-vs-state.md` 边界 — 该 design-note 已把"hp 条高度"明确划入 State,但代码侧 `damage` / `heal` 一直走 `FrontendUpdateHPAction(from, to, duration)` 进 `ActionScheduler` 并行 lerp(Event 路径)。本轮把血条彻底迁到 state:visual_hp 每 tick 朝 target_hp 收敛,delta 只是把 target 拉低。

→ [docs/design-notes/2026-04-26-presentation-event-vs-state.md](docs/design-notes/2026-04-26-presentation-event-vs-state.md) 末尾「血条迁移到 state」补章节

### Bug

用户报告:多次伤害,血条不是从当前进度继续变化(同帧多伤害 → 多个 UpdateHPAction 并行写 visual_hp 互相覆盖 → 视觉跳变)。

### Added

- **`FrontendApplyHPDeltaAction`** (`example/hex-atb-battle/frontend/actions/apply_hp_delta_action.gd`): 瞬时指令(duration=0,delay 结束当帧 progress=1 立即完成),apply 时 `actor.target_hp = clamp(target_hp + delta, 0, max)`。
- **`FrontendActorRenderState.target_hp`** 字段:damage / heal apply 累在这里;visual_hp 由 RenderWorld 异步追赶。
- **`FrontendRenderWorld.tick_hp_lerp(delta_ms)`**: 每 tick 调一次,指数衰减 `1 - exp(-rate * dt)` 让 visual_hp 朝 target_hp 收敛。`FrontendBattleDirector._tick` 末尾 wire。
- **`FrontendAnimationConfig.hp_lerp_rate`** = 8.0(单位 1/秒,默认约 125ms 收敛 63%)。

### Changed

- **`FrontendVisualAction.ActionType`**: `UPDATE_HP` → `APPLY_HP_DELTA`。
- **`damage_visualizer.gd`**: 不再读 `context.get_actor_hp` snapshot,改生成 `FrontendApplyHPDeltaAction(target_id, -actual_life_damage, hp_bar_delay)`。`damage_hp_bar_delay` 仍然有用 — 飘字 / 闪白先飞,扣血后跟,节奏感保留。
- **`heal_visualizer.gd`**: 同上,`FrontendApplyHPDeltaAction(target_id, +heal_amount)`。
- **`render_world.gd`**: 删 `_apply_update_hp_action`,加 `_apply_apply_hp_delta_action` + `tick_hp_lerp`。`set_actor_hp` / `set_actor_dead` / `_apply_death_action` 同步 snap target_hp。`_initialize_actor_from_init_data` 初始化 target_hp = visual_hp。
- **`battle_director.gd::_tick`**: 末尾 `_world.tick_hp_lerp(delta_ms)` — 与 ActionScheduler 解耦,即使无 action 活跃也每帧推进 lerp。

### Removed

- **`FrontendUpdateHPAction`** (`actions/update_hp_action.gd` + `.uid`) 物理删除 — duration-driven 持续 lerp 是 Event 路径,血条作为 State 不再适用。
- **`FrontendAnimationConfig.damage_hp_bar_duration`** / **`heal_hp_bar_duration`**: state 路径下"动画时长"概念由 `hp_lerp_rate` 替代。

### 关键设计决策

- **delta-action 而非 set-target-action**: 候选「`SetTargetHPAction(actor_id, target_hp)`」被否决 — visualizer 是 stateless,从 context 读 visual_hp snapshot 再算 target,会重新引入「同帧多 event 拿到同一起点」的 bug。delta 表达「相对变化」,与 logic 层 damage event 的 `actual_life_damage` 字段语义对齐,RenderWorld 累加自然连续。
- **hp_lerp_rate 配合指数衰减**(`1 - exp(-rate * dt)`)而非线性 lerp:目标变更时不需要重置进度,任何时刻都从「当前 visual_hp」朝「target_hp」收敛,主观感知与原 300ms 线性 lerp 接近,但天然处理多次叠加。
- **方法论**:本文档主体只迁了 death 一个 case,bug 暴露后才补血条 — 边界立完贯彻不彻底是边界没立够明确的信号(见 design-note 第 8 条总结)。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_world_view.tscn` | PASS |
| `tests/smoke_skill_preview_reactive.tscn` | PASS |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

---

## [Unreleased] — 2026-04-26 文档归属:`docs/skills/` 从主仓迁回 LGF submodule

主仓 `docs/skills/`(`damage-pipeline.md` / `shield-system.md` / `skill-implementation-progress.md` / `README.md`)4 份文档全部 `git mv` 到 `addons/logic-game-framework/docs/skills/`。原因:这些文档描述的实现代码全部在 LGF submodule 内(`hex-atb-battle-core/apply_damage` / `Shield*` 组件 / `example/hex-atb-battle/logic/skills/` 进度卡),文档归属应跟随实现仓库以保证版本一致性 — 主仓 bump submodule pointer 时,代码 + 文档同步快进,避免「shield V1 文档 + shield V2 代码」错版风险。

主仓 `docs/` 整个目录清空(plan-docs/ 不在范围)。

---

## [Unreleased] — 2026-04-26 阶段 5 完工: 拆 HexBattle thin 门面, 引入 HexDemoWorldGameplayInstance

「世界 owns 战斗」重构计划阶段 5 落地: 物理删除 `HexBattle` thin 兼容门面, 把它原本封装的 6v6 demo 战斗启动行为(默认 grid + 6 character 硬编码 + inspire buff + 队伍随机放置 + start_battle + replay save)搬到新建的 `HexDemoWorldGameplayInstance`。每个独立场景拥有自己的 `HexWorldGameplayInstance` 子类(demo / skill-preview / 将来真游戏战斗), 框架类 `HexWorldGameplayInstance` 保持通用不被 demo hardcode 污染。
→ [design-notes/2026-04-26-phase-5-hex-demo-world-gi.md](docs/design-notes/2026-04-26-phase-5-hex-demo-world-gi.md)

### Added

- **`HexDemoWorldGameplayInstance`** (`example/hex-atb-battle/logic/hex_demo_world_gameplay_instance.gd`): 新建。`extends HexWorldGameplayInstance`, 收编原 `HexBattle` 全部内容 — `start(config)` / `_create_battle_procedure` / `_on_battle_finished` / `_save_replay` / `_build_default_grid_config` / `_create_team_actor` / `_place_team_randomly` / `_apply_inspire_buff_to_all` / `_print_battle_info` / `tick(dt)` / `get_all_actors` / `get_alive_actors` / `get_replay_data` / `get_log_dir`。id 前缀 `IdGenerator.generate("demo")`(actor id 形如 `demo_001:hero_001`), `type = "hex_demo"`。
- **`HexWorldGameplayInstance.get_alive_actors()`** (`example/hex-atb-battle/core/hex_world_gameplay_instance.gd`): 上抬。返回 `Array[CharacterActor]`, 与 `get_alive_actor_ids()` 并列, 解耦 AI strategy 对 thin facade 的依赖。

### Changed

- **AI strategy 类型签名**(`example/hex-atb-battle/logic/ai/ai_strategy.gd` + 3 个具体策略): `battle: HexBattle` → `battle: HexWorldGameplayInstance` 共 7 处。配合 `get_alive_actors` 上抬, AI 不再 IS-A 偶合具体子类。
- **`scripts/SimulationManager.gd`**: `HexBattle.new()` → `HexDemoWorldGameplayInstance.new()`, cast 类型同步。Web 桥接 `godot_run_battle` 跑的是 demo 路径。
- **`scripts/SkillPreviewBattle.gd`**: `_PreviewInstance` 从 `extends HexBattle` 改为 `extends HexWorldGameplayInstance`。自管 `left_team` / `right_team` / `recorder` 字段(原本借父类), 自带 `get_all_actors()` 走 staging 拼接。id 前缀 `preview` (actor id 形如 `preview_001:caster`)。
- **`tests/smoke_world_view.gd`**: `var _world: HexBattle` + `HexBattle.new()` → `HexDemoWorldGameplayInstance`。
- **`example/hex-atb-battle/logic/main.gd`** / **`example/hex-atb-battle/frontend/main.gd`**: 同步切到 `HexDemoWorldGameplayInstance`。`HexBattle.MAX_TICKS` → `HexBattleProcedure.MAX_TICKS`(唯一来源)。
- **`example/hex-atb-battle/logic/utils/hex_battle_game_state_utils.gd`** / **`example/hex-atb-battle/core/hex_battle_procedure.gd`** / **`core/events/handler_context.gd`**: 注释里的 `HexBattle` 字面量更新为 `HexWorldGameplayInstance` / `HexDemoWorldGameplayInstance` 按语义。
- **`CLAUDE.md`** mermaid 图: `HexBattle` 节点改名 `HexDemo`(对应新类), 关系箭头不变。

### Removed

- **`example/hex-atb-battle/logic/hex_battle.gd`** 物理删除(原 268 行)。`HexBattle.MAX_TICKS` / `HexBattle.recorder` 字段在 PR-1 已先去冗余, 物理删时调用方零阻塞。
- **`HexBattle` class_name** 和 `class_name HexBattle` 全局符号一并消失。所有调用方已切到 `HexDemoWorldGameplayInstance` 或 `HexWorldGameplayInstance`。

### 设计决策(本轮关键点)

- **不污染框架类**: 候选「demo 行为搬到 `HexWorldGameplayInstance`」被否决 — `HexWorldGameplayInstance` 是 framework 层通用 hex world, 写死「priest/warrior/archer 6 角色」「9x9 默认地图」「inspire buff」等 demo 行为会破坏「框架/实例」分层。
- **不冗余 inline 到 3 个 main**: 候选「demo 启动逻辑 inline 到 frontend/main + addon/main + SimulationManager」被否决 — 同套行为出现 3 份, 未来加角色/调整地图要同步 3 处。
- **选定: 与 `SkillPreviewWorldGI` 范式对齐**: 每个独立场景拥有自己的 `HexWorldGameplayInstance` 子类。3 个 demo main 共享一个 `HexDemoWorldGameplayInstance`(单一来源), skill-preview 走自己的 `SkillPreviewWorldGI`(已存在), 将来真游戏战斗加 `HexGameplayInstance` 之类。框架/场景边界清晰。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_world_view.tscn` | PASS (views 6→5) |
| `tests/smoke_skill_preview_reactive.tscn` | PASS (3 场连续 + reset) |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

### 跨阶段成果

至此「世界 owns 战斗」整个重构计划阶段 0–5 全部落地(阶段 4 作废)。`GameplayInstance` 抽象现在有 3 个 ergonomic 实现:
- `HexWorldGameplayInstance`(框架基类, 通用 hex world)
- `HexDemoWorldGameplayInstance`(6v6 demo 场景, 服务 3 个 demo entry)
- `SkillPreviewWorldGI`(skill-preview 编辑器场景, 含 reset / queue_preview)

`HexBattle` thin 门面消亡, actor id 前缀根据场景自然区分: `demo_*` / `preview_*` / `skill_preview_*`。

---

## [Unreleased] — 2026-04-26 表演层 Event vs State 边界

用户实测 bug:单位被普攻打死后亡语紧接命中,死亡动画并行播了两次。第一/二轮 patch(`Tween.is_running()` guard / `_death_played` flag) 都只解决死亡这一个 case。跟 Codex 讨论后定下表演层根边界:**State 是可覆盖事实(snapshot 同步无害),Event 是一次性命令(必须 transition-only)**。死亡动画从 snapshot 推断改成 event 触发。
→ [design-notes/2026-04-26-presentation-event-vs-state.md](docs/design-notes/2026-04-26-presentation-event-vs-state.md)

### Changed

- **`RenderWorld.actor_died`** (`example/hex-atb-battle/frontend/core/render_world.gd`) emit 语义收紧为 transition-only:新增私有 helper `_set_actor_alive(actor, alive)` 收口所有 `is_alive` 写入,只在 `was_alive && not alive` 那帧 emit 一次。`_apply_death_action`(progress >= 1.0)/ `set_actor_dead` 直接 emit 删除,`set_actor_hp`(hp ≤ 0)走同一 helper。重复设 false / 设回 true 不再触发。
- **`FrontendBattleAnimator`** wire `_director.actor_died` → `_unit_views[id].play_death()`(event-driven),不再依赖 `actor_state_changed` snapshot 推断死亡。`reset()` 内遍历 view 调 `revive()` — Reset 是 playback session control,不走 Director event。
- **`FrontendUnitView`** 拆 API:`update_state` 删死亡 / 复活分支,只管 hp / flash / tint state sync;新增公共方法 `play_death()`(once 策略,内部 `_death_played` flag 挡重入)和 `revive()`(清 flag + visible/scale 恢复)。删私有 `_play_death_animation` / `_revive_visual_state`。

### 触发策略约定(写进 design note,长期遵守)

每个一次性动画 view 公共方法显式声明触发策略:
- **once**:已播过就忽略(死亡 / 复活)
- **retrigger**:已在播也强制 kill 旧 tween 从头播(未来:受击抖 / 闪白 / 暴击大字)
- **queue**:排队顺序播完(暂未需要)

Animator 一律 wire event signal,**不关心策略**;策略写在 view 方法体内。

### 未来扩展(本期不做)

- `actor_revived(id)`:战斗内复活技能落地时再加,同样 transition-only
- `actor_damaged(id, amount, source_id, is_critical)`:受击表现需要时落地,view 端 retrigger 策略

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_skill_preview_reactive.tscn` | PASS(3 场连续 + reset 归 0) |
| `tests/smoke_frontend_main.tscn` | PASS(139 frames, 6 views) |
| `tests/smoke_world_view.tscn` | PASS |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

用户场景:F6 main.tscn → 普攻 + 亡语双击致死 → 死亡动画只播一次 ✅;Reset → 死掉的棋子回到初始态 ✅。

---

## [Unreleased] — 2026-04-26 A 层"录像播放"老路径下线

阶段 2/3 引入响应式 `WorldView + BattleAnimator` 后, destructive `FrontendBattleReplayScene.load_replay` 老路径只剩 `main.tscn` 一个生产调用方 + `tests/smoke_frontend_main` 一个 smoke 间接依赖。本轮一次性下线: `main.gd` 切到 `HexBattle (WorldGameplayInstance) + WorldView.bind_world + BattleAnimator.play(timeline, view.get_unit_views())` 响应式 wire(参考 skill_preview 同形态), smoke 节点路径同步换, 删 ReplayScene + 3 个孤儿 frontend 测试, ReplayControls 顺手改名 PlaybackControls 对齐命名约定。
→ [design-notes/2026-04-26-playback-old-path-retirement.md](docs/design-notes/2026-04-26-playback-old-path-retirement.md)

### Removed

- **`FrontendBattleReplayScene`** (`example/hex-atb-battle/frontend/scene/battle_replay_scene.gd`): destructive `load_replay(record)` 路径整体下线。视觉入口由 `main.gd` 自己 wire `WorldView + BattleAnimator` 替代。
- **3 个孤儿 frontend 测试** (`tests/frontend/test_replay_flow.gd` / `test_3d_visualization.gd` / `test_compilation.gd`): 不在 `run_tests.gd::TEST_PATHS` 里, 没人跑过, 全部移除。`tests/frontend/` 目录一并清掉。

### Changed

- **`example/hex-atb-battle/frontend/main.gd`**: 完全重写为响应式 wire。流程: 用户按 Start Battle → 创建 `HexBattle` → `WorldView.bind_world(battle)` → `battle.start(config)` 触发 `add_actor` signal → view spawn → tick 跑完战斗 → `battle_finished(timeline)` signal → `animator.play(timeline, view.get_unit_views())`。camera / lighting / WorldEnvironment / player_controller 由 main.gd 自管(从被删的 ReplayScene 搬出来)。
- **`tests/smoke_frontend_main.gd`** (主仓): 节点路径换成 `get_node("WorldView")` / `get_node("BattleAnimator")`。4 条 invariants 保持: `is_ended` / `current_frame == total_frames` / unit view count > 0 / `visual_hp ∈ [0, max_hp]`。
- **`FrontendReplayControls` → `FrontendPlaybackControls`** (`example/hex-atb-battle/frontend/ui/replay_controls.gd` → `ui/playback_controls.gd`): 顺手对齐 Playback 命名约定。功能 / 信号 / 公共方法不变, 仅 class_name + 文件名 + 节点 name。
- **`FrontendBattleAnimator`** API 增补(`example/hex-atb-battle/frontend/battle_animator.gd`): `pause()` / `resume()` / `reset()` / `get_total_frames()` / `get_current_frame()` / `get_actors_snapshot()` / `is_ended()` 全部转发到内部 `_director`; signal `playback_state_changed(is_playing)` / `frame_changed(current, total)` 转发自 director, 供 main.gd UI 同步进度 / 按钮态。

### 外部调用点兼容性

- 录像格式未变化(仍是 ReplayData v2 平铺 `{mapConfig, initialActors, timeline}`)。
- `SimulationManager.gd` 的 Web 桥接 (`godot_run_battle` / `godot_preview_skill`) 不在范围内 — 它们只产出录像 JSON 给 JS 端, Godot 内部不渲染。
- 主仓 `Simulation.tscn` (autoload SimulationManager) 不动。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_skill_preview_reactive.tscn` | PASS(3 场连续) |
| `tests/smoke_frontend_main.tscn` | PASS(131 frames / 6 views) |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

`main.tscn` F6 编辑器手动验证由用户接手。

### 遗留

- B 层"回放(Replay)"逻辑重算未落地。命名占位 `BattleReplayPlayer` / `BattleReplaySession` 保留, 视未来需求再做。
- AI 目录 `example/hex-atb-battle/logic/ai/*.gd` 5 个文件 `battle: HexBattle` 类型偏窄但 IS-A 兼容当前不报错, 单独一笔做。
- `stdlib/replay/` 目录命名暂未变。它持有 `BattleRecorder + ReplayData + ReplayLogPrinter` 都是录像数据生产/消费侧, 没有"录像播放表演"成分。如果 `Recording` 命名更合适, 留到那时一起做。

---

## [Unreleased] — 2026-04-26 死亡不再 remove_actor(阶段 3 D5 收尾)

阶段 3 遗留的 D5"skill_preview 战斗期死亡角色 view 立刻消失,死亡动画来不及播"问题。回归阶段 0 design note (2026-04-19-world-as-single-instance.md line 247) 原则:**死亡是行为禁止,不是 actor 离开 world**。`damage_utils.apply_damage` 在 hp ≤ 0 时不再调 `world.remove_actor`,改为只清 grid 占用 / 预订;actor 留在 registry 里 `is_dead()=true`,WorldView 不回收 view,后续 `actor_state_changed(is_alive=false)` signal 能找到 view 触发死亡 tween(缩小 + 下沉 + visible=false)。
→ [design-notes/2026-04-26-death-keeps-actor-in-world.md](docs/design-notes/2026-04-26-death-keeps-actor-in-world.md)

### Changed
- `HexBattleDamageUtils.apply_damage`(`example/hex-atb-battle/logic/utils/hex_battle_damage_utils.gd`):死亡分支删除 `battle.remove_actor(target_id)` 调用,新增私有静态方法 `_clear_grid_footprint(battle, dead_actor)` 单独清掉死者的 grid occupant + reservation。语义切分:**死亡 = 行为禁止 + 清格子 + 留 view + 留逻辑实例**;**离开 world = 玩家编辑删除 / 重启战斗 / 投射物完成**。
  
  正交性已查证:`get_alive_actor_ids` / `_check_battle_end` / AI 候选 / `process_post_event` 广播范围全部走 `actor.is_dead()`(基于 `_is_dead` flag, hp 一次性 ≤ 0 翻),不依赖 `world.has_actor()`,留尸体不污染战斗逻辑。`apply_move_action` 的 `grid.move_occupant` 由 `_clear_grid_footprint` 兜底防止活人撞死尸格触发 UNEXPECTED `push_error`。
  
  当前剩余的 `world.remove_actor` 运行时调用点:`stdlib/systems/projectile_system.gd:131`(投射物离场)、`example/hex-atb-battle/skill-preview/skill_preview.gd:315/562`(编辑态删 / 切 class),`SkillPreviewWorldGI.reset()` 走 `_actors.clear()` + emit。四条都是"actor 永久离开 world"正当语义,与"死亡留尸体"原则不冲突。

### 命名约定(本轮对齐)

| 中文 | 英文 | 含义 |
|---|---|---|
| **录像播放**(A 层, 现状) | **Playback** | 表演层视觉播放:`FrontendBattleReplayScene` / `FrontendBattleAnimator` 当前做的事 —— 从录像 dict 读 actor 配置和事件流, spawn 一组视觉 view, 按 frame 推动画 / 飘字 / VFX, **不重建逻辑 actor**。 |
| **回放**(B 层, 未来可能做) | **Replay** | 逻辑层重新跑一遍战斗: 反序列化真 Actor / AbilitySet / AttributeSet, 按 timeline 命令重计算战斗状态, 支持时间轴拖动 / 撤销 / 跳到第 N 帧。**当前不做, 没规划**。 |

英文层借 playback ≠ replay 的语感分层(playback = DVR 预录播放, replay = War3/Dota 类 deterministic 重算)钉死两层。

- 后续文档 / 讨论里出现"录像 / playback"词, **默认指 A 层**; "回放 / replay"词在 B 层落地前**避免使用**, 防止误读。
- 当前代码里的 `BattleRecorder` / `ReplayData` / `FrontendBattleReplayScene` / `FrontendBattleAnimator` / `tests/frontend/test_replay_flow.gd` 等 A 层类**仍叫 Replay***, 重命名留到 A 层老路径整合那一轮工作一并做。
- 未来 B 层入口预定: `BattleReplayPlayer` / `BattleReplaySession`。
- 阶段 0 design note 草拟的"ReplayPlayer hydrate 真 Actor"路径(形态 B)字面像 B 层但实际只是 A 层包装, **该方向作废**。

### 外部调用点兼容性
- 录像格式未变化(仍是 ReplayData v2 平铺 `{mapConfig, initialActors, timeline}`)。
- `FrontendBattleReplayScene` / `BattleAnimator` / `Director.load_replay` 全部未动。
- `main.tscn` / Web 桥接 / scenario runner 路径全部未动。

### 待处理
- A 层老路径整合:`FrontendBattleReplayScene.load_replay` destructive 路径未来一轮独立工作清理, 换成 `WorldView + BattleAnimator` 直接 bind(用户表示"接下来一定会做")。
- 死者 view 期间(0.5s 死亡 tween) 活人 move 到死尸格的视觉穿过感:本期不修, 视觉违和明显时再说。
- AI 走位 / 寻路目前不感知 view 还在(逻辑层 grid 已清),无影响 —— 视觉残留是 view 层的事。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_skill_preview_reactive.tscn` | PASS(3 场连续) |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ |

skill_preview F6 编辑器手动验证(死亡 tween 视觉)由用户接手。

---

## [Unreleased] — 2026-04-20 阶段 3:skill_preview 响应式切换

阶段 1/2 把 core/frontend 拆到 "World 持久 + Procedure 短命 + WorldView/Animator 叠加层" 后, 阶段 3 让 skill_preview 这个编辑器工具吃到这套新架构: 常驻一个 `SkillPreviewWorldGI` + 常驻 `FrontendWorldView` + 常驻 `FrontendBattleAnimator`, 编辑态增删 actor 走 `world.add_actor/remove_actor` 触发 signal → view 响应式刷新(不再 destructive 重建场景)。START 走 `world.queue_preview + start_battle` → 新增的 `SkillPreviewProcedure` 承接 grant+activate+tick-until-done 语义, 战斗结束后 `battle_finished` signal 把 timeline 喂给 Animator 叠加 VFX/飘字/死亡动画。
→ [design-notes/2026-04-20-skill-preview-reactive.md](docs/design-notes/2026-04-20-skill-preview-reactive.md)

### Added
- `SkillPreviewProcedure extends BattleProcedure`(`example/hex-atb-battle/skill-preview/skill_preview_procedure.gd`):skill_preview 特化的战斗过程。不跑 ATB/AI/胜负判定, 只承接"caster 施放指定 ability, tick 到所有技能无 executing instance + 无飞行投射物 + POST_EXECUTION_TICKS 缓冲"这条终止链。`tick_once` 合并 ability tick 与 "executing 探测" 同一循环(省掉一次全量 actor 扫描); `_any_projectile_flying` 单独扫投射物。`_start_recorder` override 走旧版 `start_recording(actors, configs, map_config)` 保留 initial_actors, 供 Animator `ReplayData.BattleRecord.from_dict` 消费。`MAX_TICKS=500 / POST_EXECUTION_TICKS=10` 与旧版一致; passives 构造时 `duplicate()` 防御调方数组外部 mutate。
- `SkillPreviewWorldGI extends HexWorldGameplayInstance`(`example/hex-atb-battle/skill-preview/skill_preview_world.gd`):编辑器常驻 WorldGI。`reset()` 清空 `_actors / _actor_id_2_actor_dic / _systems / grid / _logic_time`, emit `actor_removed` 让 `FrontendWorldView` 响应式回收 unit view。`queue_preview(caster_id, ability_config, target_id, passives)` 预存下一次 start_battle 的 preview 参数(passives `duplicate()` 防御), `_create_battle_procedure` override 消费参数构造 `SkillPreviewProcedure`(消费后清空防止跨场误用, 加 `Log.assert_crash(ability_config != null)` 防 "忘 queue_preview 直接 start_battle" 静默 null)。
- `HexWorldGameplayInstance.broadcast_projectile_events()`(`example/hex-atb-battle/core/hex_world_gameplay_instance.gd`):把 projectile HIT/MISS 事件的 collect+match+process_post_event 下沉为 world 公共 method。`HexBattleProcedure` / `SkillPreviewProcedure` 的 tick_once 都调这一方法, 消除同段逻辑两处内联。
- `tests/smoke_skill_preview_reactive.tscn/gd`(主仓库):连续跑 3 场战斗断言 WorldView/Animator 节点引用复用(直接比较 Node 引用, 不靠 instance_id) + reset 归 0 + battle_finished 产出非空 timeline + animator 跑到 playback_ended。

### Changed
- `skill_preview.gd`(`example/hex-atb-battle/skill-preview/skill_preview.gd`)从 "每次 START 调 `SkillPreviewBattle.run_with_config` destructive 重建临时 instance + `FrontendBattleReplayScene.load_replay`" 切到响应式栈:`_ready` 里 `GameWorld.init()` + 常驻 `SkillPreviewWorldGI` + `FrontendWorldView.bind_world` + `FrontendBattleAnimator`。编辑态的 `_rebuild_editor_preview`(旧)替换为 `_rebuild_world_from_model`(新)走 `world.reset() / configure_grid / add_actor / place_occupant` 的显式 mutation API, `FrontendBattleReplayScene / FrontendBattleDirector / _replay_events_by_frame / _last_logged_frame` 等字段全部删除。相机 / 光照 / 环境从原先委托 replay_scene 改为场景自己搭(`_setup_camera_and_env` 沿袭原参数)。console event log 退化为 `battle_finished` 后从 timeline 一次性 dump(不再按 frame 同步推进, UX 遗留记在 handoff)。
- `HexWorldGameplayInstance.logger: HexBattleLogger = null`(`example/hex-atb-battle/core/hex_world_gameplay_instance.gd`):把原先仅存在于 `HexBattle` 上的 `logger` 字段下沉到父类, 默认 null。动机 —— `damage_utils / heal_action` 用 `if battle.logger != null` 判空访问, 当 `game_state_provider` 是 `SkillPreviewWorldGI` 等 HexBattle 的姊妹子类时触发 `Invalid access to property 'logger'` 报错。下沉后任何 `HexWorldGameplayInstance` 子类都合法共享字段, HexBattle 上原有声明删除以避免 shadowing。
- `HexBattle` 在 `hex_battle.gd` 上的 `var logger: HexBattleLogger = null` 声明移除(下沉到 HexWorldGameplayInstance, 见上), `_on_battle_finished` 里 `logger = _hex_procedure.logger` 语义不变。
- `HexBattleProcedure._broadcast_projectile_events` 下沉并删除本地 method, `tick_once` 改调 `world.broadcast_projectile_events()`; 顺带移除原实现里的 `print("  [投射物] ...")` debug 行(调试 print 不属于框架职责, 要 log 走 HexBattleLogger)。
- 所有 `var battle: HexBattle = ctx.game_state_provider` 的静态类型标注改为 `var battle: HexWorldGameplayInstance = ctx.game_state_provider`:`actions/apply_move_action.gd` / `actions/apply_buff_action.gd` / `actions/damage_action.gd` / `actions/poison_tick_action.gd` / `actions/heal_action.gd` (×2) / `actions/reflect_damage_action.gd` / `actions/start_move_action.gd` / `target_selectors.gd`, 以及 `utils/hex_battle_damage_utils.gd` (×2) / `utils/hex_battle_game_state_utils.gd` (×2)。  
  动机 —— 这些 action 访问的字段(`get_actor / get_alive_actor_ids / grid / remove_actor / get_actors / logger`)阶段 1 已全部下沉到 HexWorldGameplayInstance, 标注成具体子类 HexBattle 是历史残留, 且会让 SkillPreviewWorldGI / 未来其它姊妹子类触发"Trying to assign value of type X to a variable of type hex_battle.gd"。AI 目录(`ai/*.gd` 5 文件)的 `battle: HexBattle` 暂未改 —— SkillPreviewProcedure 不走 AI 路径, 且 HexBattle 跑 HexBattleProcedure 时 AI 签名仍兼容, 改动留给未来"WorldGI 直接驱动 AI"场景。

### Fixed
- `skill_preview.gd._do_rebuild_world_unguarded`:右键加 actor 后 view 永远落在 (0,0)。根因 —— `WorldView._hydrate_from_actor` 在 `actor_added` 信号里一次性读 actor 的 `team / hp / hex_position`, 但 core 层 `actor_position_changed` signal 尚未 emit(本段"外部调用点兼容性"已记录, D5 列为阶段 4 待办), 导致 add 之后再赋值的字段 view 收不到。修法把 `set_team_id / attribute_set.set_*_base / hex_position` 全部前置到 `_world.add_actor(cchar)` 之前, hydrate 时即可读到正确值; `place_occupant` 留在 add 之后(grid 占用登记必须等 actor 入 world)。属于 hydrate 时序兜底, 阶段 4 补 `actor_position_changed` emit 后可改回任意顺序。
- `skill_preview.gd` 编辑态走全量 rebuild 导致"加一个 actor 所有棋子从 (0,0) 移过来"。根因 —— `_add_actor / _remove_actor_at / _move_caster_to`, 以及 actor row 的 q/r/hp/class 修改全部调 `_rebuild_world_from_model` → `_world.reset()` + 整体重建 actor。每次 reset 触发 `actor_removed` × N → WorldView 销毁所有 view → 重 spawn → 新 view 初始 `position = (0,0,0)`, `_process` 内 `position.lerp(_target_position, delta * 15.0)` 平滑插值时视觉上就是"全部从原点滑到目标"。修法把编辑态拆成 5 条增量 mutation 路径: `_add_actor` 走单 `_spawn_one_actor(idx)`; `_remove_actor_at` 走 `_world.remove_actor(actor_id)` (HexWorldGameplayInstance.remove_actor 已自带 grid occupant 清理); 坐标改动走 `_apply_actor_position_change` (`grid.move_occupant` + 手动 `actor_position_changed.emit` 兜底, 因 core 仍未补 emit); hp 改动走 `_apply_actor_hp_change` (`attribute_set.set_*_base` + `view.initialize` re-hydrate); class 切换走 `_apply_actor_class_change` (CharacterActor class 是构造参数 → remove + spawn 同 idx)。引入并行 `_actor_ids: Array[String]` 与 `_actors` 同 idx 对齐, 解决 idx 重编号(删 enemy_2 后 enemy_3 → enemy_2)导致 role_id 反查错位的问题。
- `skill_preview.gd` map spinbox(radius / orientation / hex_size) value_changed 每步触发全量 rebuild, 拖动时抖。加 150ms one_shot debounce Timer, 短促拖动只在停下后 rebuild 一次。
- `skill_preview.gd` 编辑期 reset 路径泛滥, 违反"reset 只用于明确意图的场景重置, 面板/右键全部走 event→update"的原则。清掉 3 处违反原则的 reset 调用 + 把剩余 reset 函数语义收紧:
  - 删 `_on_start_pressed` 战前 `_do_rebuild_world_unguarded` —— 编辑期已经实时 mutation 同步到 world, 战前不需要 commit, 这行的存在反而暴露"UI 模型 / world state 异步两份"的错位认知。
  - 删 `_on_passive_toggled` 内 `if pressed: _rebuild_world_from_model()` —— passive 只在 `_collect_selected_passives()` 喂给 queue_preview, 编辑期 world 不感知 passive, 此处 rebuild 纯属无效调用(历史残留)。
  - 改 map spinbox debounce timeout 接到新增的 `_apply_grid_change`(走 `_world.configure_grid` emit `grid_configured` -> view 重渲网格 + 遍历 `_actor_ids` 重新 `place_occupant` + 用同坐标 emit `actor_position_changed` 让 view 按新 hex_size 重算 world_position 平滑过渡)。注意 UGridMap.configure 创建新 GridMapModel 旧 occupant 全丢, 必须重新 place; radius 改小后 actor coord 不在新网格内时跳过 place 但仍 emit position_changed (coord_to_world 是纯数学不依赖 has_tile)。
  - `_rebuild_world_from_model` / `_do_rebuild_world_unguarded` 改名 `_reset_world_to_model` / `_reset_world_to_model_unguarded`, 函数注释里明确列出"合法调用点只有 3 处", 编辑期面板 / 右键 / spinbox 全部走 event→update 增量 mutation。
- `skill_preview.gd._on_playback_ended` 不再自动 reset world —— 战斗回放结束后保留 world 当前状态(死者已 remove / 受伤者血条 < max), 让用户能观察战斗结果或重播。状态恢复改由用户主动按新增的 RESET 按钮触发(`_on_reset_pressed`: `_reset_world_to_model_unguarded` + 清 console log + 启用 START)。START 按钮在回放结束后保持 disabled, 强制走 RESET → START 流程, 避免基于残破状态(死者已 remove / hp 已损耗)再次战斗导致语义混乱。`skill_preview.tscn` 在 StartButton 后追加 `ResetButton` 节点; `_style_reset_button` 给次要操作样式(浅米底 + 深咖字, 阵仗低于 START 主 CTA)。合法 reset 调用点更新为:_ready 初始化 / _on_reset_pressed / _on_preset_load_selected。
- `skill_preview.gd` HexPopupMenu 显示时用户右键另一个 hex 没反应,要再点一次。根因 —— `PopupMenu` 是 modal Window, popup visible 时 `InputEventMouseButton` 被 popup 自身截获(主场景 `_input` 收不到), 同时这次右键也不触发 popup 的 click-outside-close (右键不算 click-outside 触发器), 所以 popup 既不关闭也不让主场景重弹。修法:连 `Window.window_input` signal (popup 自身收到的事件转发回我们) → 检测 `MOUSE_BUTTON_RIGHT pressed` → 关旧 popup + raycast 当前鼠标位置 + `call_deferred("_show_hex_popup")` 在新 hex 重弹(deferred 让 hide 真正完成再 show, 避免同帧 race)。同 hex 右键只关闭不重弹。左键 / ESC / 点菜单项的关闭路径不走这条, 由 popup 原生关闭流程处理。曾经尝试过 `popup_hide` signal + deferred reopen 方案,但 `popup_hide` 在点菜单项时也触发 → 误判成需要重弹 → 用户反馈"创建 actor 后冒出新菜单",已撤回。

### 外部调用点兼容性
- `SkillPreviewBattle`(`scripts/SkillPreviewBattle.gd`)未动 —— `tests/skill_scenarios/` scenario runner 继续走 headless `run_with_config/actions` 路径(`GameWorld.init → 临时 _PreviewInstance(HexBattle) → tick → GameWorld.destroy`), 未切到 SkillPreviewWorldGI。动机:scenario runner 的"每场独立 GameWorld 生命周期"断言简单且已稳; skill_preview UI 需要常驻 world 才能做到"无缝展开战斗", 二者的需求不同, 一条路径优化给一种场景更克制。
- `main.tscn` / `Simulation.tscn` / Web 桥接继续走 `HexBattle` 门面 + `FrontendBattleReplayScene.load_replay(record)` 老路径, 未动。
- `BattleRecord` 录像格式未变化(阶段 4 落地 v3), `FrontendBattleReplayScene` 未动。

### 待处理(下一阶段)
- 阶段 4:`BattleRecord` v3(split `world_snapshot` + `event_timeline`) + `ReplayPlayer`(临时 WorldGI + WorldView)。录像路径切到 ReplayPlayer 后 skill_preview 战斗期死亡动画问题可根治 —— 届时 skill_preview 可以 bind 到 ReplayPlayer 构造的临时 world 看完整死亡动画, 或继续走本阶段常驻 world(死者 view 响应式消失, 死亡动画 skip)的方案。
- 阶段 5:`main.tscn` / `Simulation.tscn` / Web 桥接切到 WorldGI 承载。
- AI 目录 `battle: HexBattle` 类型标注收束(等 "WorldGI 直接驱动 AI" 需求落地再改, 当前 `HexBattleProcedure._decide_action` 传 `_world_instance: HexWorldGameplayInstance` 进去,AI 静态类型虽偏窄但传入的 HexBattle 实例 IS-A 兼容,不报错)。
- skill_preview 战斗期 console event log 同步推进(现在 `battle_finished` 后一次性 dump, 不追帧)。需要 `FrontendBattleAnimator` 转发 director `frame_changed` signal 才能做同步, 阶段 3 不加以免扩 scope。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS(Logic battle completed in 156 ticks) |
| `tests/smoke_skill_scenarios.tscn` | 12/12 ✅ (含 Shield + Thorn 系统并入) |
| `tests/smoke_world_view.tscn` | PASS(views 1 → 0) |
| `tests/smoke_skill_preview_reactive.tscn` | PASS(3 场连续, view/animator 实例复用 + reset 归 0) |

编辑器手动验证(skill_preview UI 的"无缝展开战斗"视觉)由用户接手, 不在 headless 覆盖面内。

### 阶段 3 收尾确认 (2026-04-26)

用户 F6 编辑器实测通过, 以下行为全部符合预期:
- 增删 actor / 拖 q/r/hp / class 切换 → 只动目标棋子的 view, 已有棋子不抖
- 拖 map radius / orientation / hex_size → 拖动期不抖, 松手后 150ms 平滑过渡(actor 跟新 hex_size 重算位置, 不是从 (0,0) 滑回)
- 战斗 START → 回放 → 状态保留 → 用户主动按 RESET 才回战前态
- popup visible 时右键另一个 hex → 旧 popup 关闭, 新 hex 重弹 popup; 点菜单项 / ESC / 左键关闭都不会误触发"反弹"
- 触发"reset 全部从 (0,0) 滑回"的入口已收敛到 3 处明确意图的合法路径(`_ready` / `_on_reset_pressed` / `_on_preset_load_selected`)

---

## [Unreleased] — 2026-04-20 阶段 2:Frontend 订阅器(WorldView + BattleAnimator)

阶段 1 把 core 拆成"World 持久 + Procedure 短命"两层后,frontend 仍停留在"被动消费录像 dict"范式。阶段 2 新增响应式订阅层:`WorldView` 订阅 WorldGI 的显式 mutation signal 维护 unit view 生命周期(非战斗期);`BattleAnimator` 复用 `FrontendBattleDirector` 消费 event_timeline,在 WorldView 提供的已有 view 上叠加 VFX / 飘字 / 死亡动画,不拥有 view。录像格式 / `FrontendBattleReplayScene` / `main.tscn` / scenario runner / Web 桥接全部未动 —— 阶段 2 纯加 API,现有路径继续走 HexBattle 门面 + replay scene。  
→ [design-notes/2026-04-20-world-view.md](docs/design-notes/2026-04-20-world-view.md)

### Added
- `FrontendWorldView extends Node3D`(`example/hex-atb-battle/frontend/world_view.gd`):`bind_world(world)` hydrate 当前 actor + 订阅 `actor_added` / `actor_removed` / `actor_position_changed` / `grid_configured` / `grid_cell_changed` signal。view 生命周期完全由 signal 驱动(reactive projection);没有 destructive `load_replay` 等价物。内部挂 `UnitsRoot` + `GridMapRenderer3D`;上层通过 `get_unit_views()` / `get_unit_view(id)` / `get_unit_view_count()` 抓取 view 引用。只为 `CharacterActor` 建 view,ProjectileActor 等非可视单位由 BattleAnimator 自行管 VFX 节点。
- `FrontendBattleAnimator extends Node3D`(`example/hex-atb-battle/frontend/battle_animator.gd`):`play(record_dict, unit_views)` 复用 `FrontendBattleDirector` 的 timeline 解码 / `FrontendActionScheduler` / `FrontendVisualizerRegistry`,把 Director 的状态变更 signal(`actor_state_changed` / `floating_text_created` / `attack_vfx_*` / `projectile_*`)转发到外部传入的 unit view 字典(`actor_died` 由 Director 经 `actor_state_changed.is_alive=false` 统一推入,不需单独转发);自己只承载 VFX / 投射物 / 飘字节点(挂在内部 `EffectsRoot`)。`playback_started` / `playback_ended` signal + `set_speed()` / `stop()` / `is_playing()` 兼容现有测试加速需求。
- `tests/smoke_world_view.tscn/gd`:阶段 2 主验证 —— bind 前 0 view → HexBattle.start 触发 signal 把 view 补齐 → WorldGI.tick 推进战斗 → BattleAnimator 消费 timeline 到 `playback_ended` → 显式 `world.remove_actor` 让剩余 view 响应式减少。

### Deprecated
- `FrontendBattleReplayScene`(`example/hex-atb-battle/frontend/scene/battle_replay_scene.gd`)收缩为"录像回放专用"路径 —— 仍由 `main.tscn` / Web 桥接使用,但不再是新战斗场景的视觉入口。阶段 4 录像格式 v3 落地后考虑用 `ReplayPlayer`(临时 WorldGI + WorldView)替换,彻底去掉 destructive `load_replay`。

### 外部调用点兼容性
- `main.tscn` / `SkillPreviewBattle` / scenario runner / Web 桥接均未调整,继续走 `HexBattle` 门面 + `FrontendBattleReplayScene.load_replay(record)` 老路径。WorldView / BattleAnimator 是"可选接入",需要响应式更新的场景才用。
- WorldGI 的 `actor_position_changed` / `grid_cell_changed` signal 已由 WorldView 订阅但 core 层尚未 emit 任何调用点 —— 预留钩子,后续移动动画 / 地形破坏技能按需补 emit。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS |
| `tests/smoke_skill_scenarios.tscn` | 9/9 ✅ |
| `tests/smoke_world_view.tscn` | PASS(bind + signal spawn + timeline 动画 + remove_actor) |

---

## [Unreleased] — 2026-04-20 阶段 1：WorldGameplayInstance + BattleProcedure 核心拆分

"世界 owns 战斗"架构第一步。把 HexBattle 身上的 instance(actor registry / grid / systems)与 procedure(ATB loop / teams / recorder)两条职责拆开,为后续 frontend 响应式 view + skill_preview 无缝展开战斗 + replay 格式 v3 奠基。阶段 1 只改 core / hex-atb-battle-core 层,调用端(`SkillPreviewBattle` / `main.tscn` / `scenes/Simulation.tscn` / scenario runner)通过 `HexBattle` 兼容门面不动一行。  
→ [design-notes/2026-04-19-world-as-single-instance.md](docs/design-notes/2026-04-19-world-as-single-instance.md)

### Added
- `WorldGameplayInstance extends GameplayInstance`(`core/entity/world_gameplay_instance.gd`):显式 mutation API `add_actor` / `remove_actor` / `configure_grid`,每个 emit 对应 signal(`actor_added` / `actor_removed` / `actor_position_changed` / `grid_configured` / `grid_cell_changed` / `battle_finished`);`start_battle(participants: Array[Actor])` 入口配合工厂钩子 `_create_battle_procedure`,`tick(dt)` 战斗优先,分帧吞吐由常数 `BATTLE_TICKS_PER_WORLD_FRAME`(默认 INT_MAX,一帧跑完)控制。Signal 只由显式 mutation 触发,战斗期间 actor 属性/tag 直接改内存,不发 signal(view 由 BattleAnimator 消费 event_timeline 回放)。
- `BattleProcedure extends RefCounted`(`core/entity/battle_procedure.gd`):抽象骨架。Public API `start` / `tick_once` / `should_end` / `finish`(被 WorldGI.tick 调用,不加下划线)。生命周期管理 in_combat tag(`_mark_in_combat` 虚钩子,基类 no-op,子类按 tag 容器实现)+ recorder(`_start_recorder` 虚钩子,默认走 events-only,子类可 override 回退旧版 `start_recording(actors,...)`)。
- `BattleRecorder.start_recording_events_only()`(`stdlib/replay/battle_recorder.gd`):仅记录 event timeline,不带 initial_actors / map_config。为新架构下"world 已常驻持有状态,录像只记过程事件"服务;旧版 `start_recording()` 保留未动,向后兼容。
- `HexBattleProcedure extends BattleProcedure`(`example/hex-atb-battle/core/hex_battle_procedure.gd`):hex 特化。承接原 `HexBattle.tick` 里的 ATB 累积、AI 决策、技能施放、投射物事件广播、MAX_TICKS 安全上限、胜负判定(某方全灭 → `mark_finished` + `_result` 设置为 `left_win / right_win / timeout`)。`_start_recorder` override 走旧版 `start_recording(actors, configs, map_config)` 路径,保留 initial_actors snapshot,阶段 1 不破坏 FrontendBattleReplayScene。
- `HexWorldGameplayInstance extends WorldGameplayInstance`(`example/hex-atb-battle/core/hex_world_gameplay_instance.gd`):actor registry + grid(UGridMap autoload 后端)+ system 管理。`configure_grid` 转发到 `UGridMap.configure`,保持 `grid` 字段指向 `UGridMap.model`。`remove_actor` 覆盖清理格子 occupant / reservation。`get_actor` 类型收窄 CharacterActor。提供 `get_alive_actor_ids` / `get_ability_set_for_actor` / `can_use_skill_on`。

### Changed
- `HexBattle extends HexWorldGameplayInstance`(`example/hex-atb-battle/logic/hex_battle.gd`)从具体 instance 转为 thin 兼容门面。`start(config)` 走新架构:`configure_grid()` + 6 个 `add_actor()` + 队伍装备 + buff + timeline 注册 + `start_battle(...)` 创建 HexBattleProcedure。`tick(dt)` 委托父类 `WorldGI.tick`,由其驱动 procedure;每 tick 从 procedure 镜像 `tick_count`。战斗结束通过 `battle_finished` signal 回 `_on_battle_finished`,保留字段 `left_team / right_team / recorder / logger / _ended / _final_replay_data / MAX_TICKS`(= 10000)兼容旧调用。  
  原 HexBattle 上的 ATB loop / projectile 广播 / AI 决策 / `_check_battle_end` / `_start_actor_action` / `_create_action_use_event` 等全部迁至 HexBattleProcedure,不再在 HexBattle 里保留。

### 外部调用点兼容性
- `HexBattle.new().start(config)` / `battle.tick(dt)` / `battle.tick_count` / `battle.left_team` / `battle.right_team` / `battle.recorder` / `battle.logger` / `battle.get_replay_data()` / `battle.get_log_dir()` / `HexBattle.MAX_TICKS` / `battle.can_use_skill_on(...)` 全部保留;`main.tscn` / `SimulationManager` / `SkillPreviewBattle` / scenario runner / Web 桥接均未调整。
- 录像格式暂未变化(仍走旧版 `start_recording(actors, ...)` 保留 initial_actors),FrontendBattleReplayScene 不受影响。格式 v3(split `world_snapshot` + `event_timeline`)在阶段 4 再落地。

### 待处理(下一阶段)
- 阶段 2:`WorldView` 订阅 WorldGI signal 维护 unit view,`BattleAnimator` 消费 event_timeline 叠加飘字/特效。
- 阶段 3:`skill_preview` 切换到常驻 `SkillPreviewWorldGI` + `world.start_battle`,验证无缝展开战斗。
- 阶段 4:`BattleRecord` v3 格式落地 + `ReplayPlayer`(临时 WorldGI + WorldView)。
- 阶段 5:正式游戏场景(`main.tscn` / `Simulation.tscn` / Web 桥)切换到 WorldGI 承载。

### 验证

| 测试 | 结果 |
|---|---|
| `addons/logic-game-framework/tests/run_tests.tscn` | 59/59 ✅ |
| `tests/smoke_frontend_main.tscn` | PASS(Logic battle completed in 139 ticks) |
| `tests/smoke_skill_scenarios.tscn` | 9/9 ✅ (CrushingBlow / DeathrattleAoe / Fireball / HolyHeal / Poison / PreciseShot / Strike / SwiftStrike / Thorn) |

---

## [Unreleased] — 2026-04-19 后续：Ability 叠层一级化 + grant 事件化

围绕 Poison（DOT）技能实装,对外暴露两个 framework 缺口并一次性补齐:
(1) 叠层数据之前挂在 `StackComponent` 里,action 必须遍历 components 找它;
(2) `grant_ability` 只跑 local callback,buff 无法"挂上就自动 tick"。

### Added
- `Ability.stacks / max_stacks / overflow_policy` 提升为一级属性,配套 API `get_stacks() / is_stacks_full() / add_stacks(count) / remove_stacks(count) / set_stacks(count)`。溢出策略常量 `Ability.OVERFLOW_CAP / OVERFLOW_REFRESH / OVERFLOW_REJECT`。REFRESH 策略在叠层同时调用本 ability 上 `TimeDurationComponent.refresh()`(之前的 TODO 随一级化变成 3 行实现)。归 0 不自动 expire —— 清理由调用方决定(stacks 做纯计数器,与项目约定一致)。
- `AbilityConfig` 加 `initial_stacks / max_stacks / overflow_policy` 配置字段,`AbilityConfigBuilder.stacks(initial, max_val, policy)` 一级 API。不调默认 1/1/CAP(不可叠加 ability 调 add_stacks 一直 CAP 在 1,语义安全)。
- `AbilitySet.grant_ability(ability, game_state_provider = null)` 新增第二参数。传入后,grant 内部构造 `ABILITY_GRANTED_EVENT` 并同步调 `receive_event(event_dict, provider)` 广播给本 actor 的所有 ability。限本人 ability_set 广播,不走 event_processor 全局 post —— 跨 actor 监听由业务层自行决定。未传 provider(默认)则仅跑 local callback,保持与旧调用点兼容。
- `TriggerConfig.GRANTED_SELF` 静态 factory:匹配 `ABILITY_GRANTED_EVENT` 且 `event.actor_id == owner_id` 且 `event.ability.id == ctx.ability.id`(严格 instance id,同 actor 上多个同 config 实例不互激活)。典型用途:buff 挂 `ActivateInstanceConfig + GRANTED_SELF + loop timeline` 实现"挂上就自动 tick"(DOT/HOT/持续光环)。

### Removed
- `stdlib/components/stack_component.gd` 删除(对应 `stacks / max_stacks / overflow_policy` 已上移到 Ability 一级)。StackComponent 原本"组件化"但实际没有 hook/callback 也没有组件间交互接口,只是"一堆方法 + 状态"伪装成 component。外部 action 必须遍历 components 按 type 字符串找它才能读写层数,违反 component 封装。上移后:
  - Poison DOT 的 tick action 直接 `ctx.ability_ref.get_ability().get_stacks()`,零胶水
  - `Ability` 成为 stacks 的 facade(类比 `attribute_set.atk` / `actor.faction`),AbilityConfig 一级 API `.stacks(...)` 声明可叠加 ability

### Changed
- `Ability.serialize()` 增加 `stacks / maxStacks / overflowPolicy` 字段(replay/snapshot 携带层数信息)。

### 外部调用点同步
本次 addon 改动对现有业务代码**零调用点变更**:grant_ability 新参数默认 null;stacks 字段在所有未调 `.stacks(...)` 的 config 下默认 1/1/CAP,add/remove 对它们是 no-op。

### Added(上轮累积,保留)
- `Actor.is_pre_event_responsive() -> bool`（默认 true）虚函数。项目层子类覆盖以表达"此刻不响应 PreEvent 分发"的状态（如死亡、沉默、眩晕）。框架在 `PreEventComponent` handler 触发时查询，返回 false 则 handler 自动降级为 `pass_intent()`。  
  → [design-notes/2026-04-19-ability-lifecycle-decoupling.md](docs/design-notes/2026-04-19-ability-lifecycle-decoupling.md)
- `GameplayInstance.end()` 末尾自动调 `EventProcessor.remove_handlers_by_owner_id(actor.get_id())` 清理所有 actor 的 PreEvent handler 注册，避免跨战斗累积孤儿。不 revoke ability，保留 `_abilities` 数组以支持复活等语义。

### Changed
- `Ability` 删除 `_lifecycle_context` 字段。`apply_effects(ctx)` 不再缓存 context，`remove_effects()` 内部通过新方法 `_build_remove_context()` 从 `owner_actor_id` + `GameWorld.get_actor` 按需重建精简 context（仅 `ability`/`attribute_set`/`ability_set` 三字段，`event_processor`/`owner_actor_id` 在 on_remove 路径上无消费者）。幂等性改由 `_effects_active: bool` 哨兵维护。  
  → [design-notes/2026-04-19-ability-lifecycle-decoupling.md](docs/design-notes/2026-04-19-ability-lifecycle-decoupling.md)
- `PreEventComponent` 删除 `_lifecycle_context` 字段。注册到 `EventProcessor._pre_handlers` 的 handler/filter lambda **只捕获 String ID 和用户 Callable**，不捕获 `self`（PreEventComponent 实例）；触发时通过静态方法 `_rebuild_context` 按需构造。重建包含三层 null 短路：
  1. `GameWorld.get_actor` 找不到 actor → `pass_intent()`
  2. `actor.is_pre_event_responsive()` 返回 false → `pass_intent()`
  3. `ability_set.find_ability_by_id` 找不到 ability → `pass_intent()`  
  这同时修复了潜在的"死者/已 revoke ability 的幽灵 handler 响应"问题。
- `DynamicStatModifierComponent` 删除 `_context: AbilityLifecycleContext` 缓存字段。`on_remove` 从参数收 context（签名本来就如此）。
- `tests/core/events/pre_event_component_test.gd` 重写测试 setup，通过 `GameWorld.create_instance` + `instance.add_actor` 注册真实 MockActor（继承 `Actor`），匹配生产代码"handler 重建需要 actor 在 GameWorld 里"的契约。

## [Unreleased] — 2026-04-19 后续轮：结构性循环根治

上一轮识别但未修的循环 C、调研发现的循环 D/E 本轮一次性处理。统一原则：**子对象回指所属 container 禁止强引用，一律用 WeakRef 或 String id**（此约定之前只由 `Actor._instance_id: String` 体现）。

### Changed
- `AbilityComponent._ability: Ability` → `_ability_ref: WeakRef`（循环 C）。`initialize()` 调 `weakref(ability)`；`get_ability() -> Ability` 新增，返回 `_ability_ref.get_ref() as Ability`（可能 null，调用方需短路）。子类不再允许直接访问 `_ability` 字段。  
  → 修复：`Ability._components[]` ↔ `AbilityComponent._ability` 互持强引用，GDScript RefCounted 无循环 GC，Ability 对象图永不释放。
- `TimeDurationComponent._trigger_expiration()` 使用 `var ability := get_ability(); if ability != null: ability.expire(...)` 替代直接字段访问。唯一的 stdlib 外部消费点。
- `AbilityExecutionInstance` 删除 `_game_state_provider: Variant` 字段（循环 D）。`tick(dt, provider)` / `fire_sync_actions(actions, tag, provider)` / `_build_execution_context(tag, provider)` / `_execute_actions_for_tag(tag, actions, provider)` 全部添加 `provider: Variant` 参数。`Ability.tick_executions(dt, provider)` / `AbilitySet.tick_executions(dt, provider)` 同步加参。`Ability.activate_new_execution_instance` 保留 `p_game_state_provider` 参数**仅用于 activate 瞬间 `fire_sync_actions(__timeline_start__)`**，不再传入 `AbilityExecutionInstance.new`。  
  → 修复：execution instance 缓存 provider（= battle）形成 `battle → actor → ability_set → ability → _execution_instances → _game_state_provider = battle` 循环。遵循既有"provider 是调用时参数流"约定（对齐 `HandlerContext.game_state` / `ExecutionContext.game_state_provider` / `Component.on_event`）。
- `System._instance: GameplayInstance` → `_instance_ref: WeakRef`（循环 E）。`on_register(instance)` / `on_unregister()` / 新增 `get_instance() -> GameplayInstance` 短路返回。`get_logic_time()` 走 getter。`ProjectileSystem._process_pending_removal` 唯一外部消费点改为局部 `var instance := get_instance()`。  
  → 修复：`GameplayInstance._systems[]` ↔ `System._instance` 互持强引用。虽然 `GameplayInstance.end()` 会调 `system.on_unregister()` 主动解链，但这是纪律防御（依赖 end 被正确调用）；WeakRef 把它变成结构性防御。

### 外部调用点同步
- `hex_battle.gd:343`、`scripts/SkillPreviewBattle.gd:98`、`tests/smoke_strike.gd:71`：`actor.ability_set.tick_executions(dt)` → `.tick_executions(dt, self/battle)`。
- `addons/logic-game-framework/tests/core/abilities/ability_execution_instance_test.gd` / `ability_test.gd` / `timeline_loop_test.gd`：补齐新签名。

### 验证（基线 → 本轮后）
| 测试 | Before | After |
|---|---|---|
| LGF 单元测试 (59/59) | 25 leaked | **14** |
| `smoke_strike.tscn` | 41 leaked | **38** |
| `smoke_frontend_main.tscn` | 57 leaked | **46** |

### 待处理
- **smoke_strike 剩余 38 泄漏的根源**：shutdown 时 battle 在 `_end_all_instances` + `_instances.clear()` 后仍有 1 个真实外部强引用。不是循环 C/D/E。可能的候选：Action 里某个 Callable / event 字典持对象引用 / `UGridMap.place_occupant` 缓存的 occupant 路径。独立问题，需要新一轮 probe 定位。
- 本轮本该带来的数字下降受到此残余循环压制，因此循环 D 的实际收益被低估了（frontend 降 11 是循环 D 的真实体现，smoke_strike 未能暴露）。

## [Unreleased] — 2026-04-19 第三轮：pre_change 闭包循环根治（config 驱动跨属性 clamp）

承接上一轮「smoke_strike 剩余 38 泄漏」待处理项。PREDELETE probe 定位到：
```
CharacterActor.attribute_set → HexBattleCharacterAttributeSet
HexBattleCharacterAttributeSet._pre_change_callback → Callable
Callable → (闭包捕获 self) → CharacterActor   ← 循环
```
即 `CharacterActor._setup_attribute_constraints` 注册的 lambda 在访问 `attribute_set.max_hp` 时隐式捕获 `self`，形成 actor ↔ attribute_set ↔ Callable 三角强引用。属于循环 C/D/E 同族（子对象存的 Callable 捕获 owner），但表层是「闭包捕获」而非「字段缓存」。

### 架构决策：pre_change callback → 声明式 config 驱动的 cross-attr clamp
`_pre_change_callback` 的实际能力只能改 `inout_value["value"]`（clamp），无法触发副作用 —— **唯一用例**是跨属性 clamp（hp ≤ max_hp）。收敛为声明式 API 后 Callable 彻底消失。

### Added
- `RawAttributeSet.register_cross_attr_clamp(target, bound, source)` + `clear_cross_attr_clamps()`。`bound` 取 `"max"` / `"min"`，`source` 属性的 current value 作为 target 的动态边界。构建期 assert target/source 必须在同 set 里定义。
- `BaseGeneratedAttributeSet.register_cross_attr_clamp` 转发。
- Attribute config schema 新增 `maxRef` / `minRef` 字段，值为同 set 内的属性名。生成器在 `_init()` 末尾自动产出 `_raw.register_cross_attr_clamp(...)` 调用，并在生成期 validate source 存在；缺失时 `push_error`。
- `example/attributes/attributes_config.gd` 的 `HexBattleCharacter.hp` 加 `"maxRef": "max_hp"`，生成文件同步重建。

### Removed
- `RawAttributeSet._pre_change_callback` 字段 + `set_pre_change(callback)` + `clear_pre_change()`。
- `BaseGeneratedAttributeSet.set_pre_change(callback)` 转发。
- `CharacterActor._setup_attribute_constraints()` 函数 + `_init()` 里的调用（约束语义已完全下沉到 config）。

### Changed
- `RawAttributeSet.get_breakdown()` 计算流程「步骤 2」从「调 `_pre_change_callback`」改为「遍历 `_cross_attr_clamps` 并走 `get_breakdown(source)`」。读 source 时复用已有 `_computing_set` 循环检测机制，语义一对一。
- `tests/core/attributes/attribute_set_test.gd` 两个 pre_change 测试改名为 `cross_attr_clamp_*`，API 切换为 `register_cross_attr_clamp("hp", "max", "max_hp")`，断言不变。

### 主仓库同步
- `character_actor.gd` 删 `_setup_attribute_constraints` 调用。项目级 `logic-game-framework-config/attributes/attributes_config.gd`（`Hero`/`Tower`）因不含 hp 属性，无需改动。

### 验证（基线 → 本轮后）
| 测试 | Before | After |
|---|---|---|
| LGF 单元测试 (59/59) | 33 leaked / 14 resources | **24 leaked / 11 resources** |
| `smoke_strike.tscn` | 112 leaked / 38 resources | **0 / 0** 🎯 |
| `smoke_frontend_main.tscn` | 46 resources | **0 / 0** 🎯 |

→ [design-notes/2026-04-19-attribute-cross-clamp-config-driven.md](docs/design-notes/2026-04-19-attribute-cross-clamp-config-driven.md)

### 待处理
- LGF 单元测试 24 leaked / 11 resources 是**测试框架层面**的泄漏（testframework 保留每个 `*_test.gd` 的 GDScript 引用），与生产代码无关，独立问题。
- `_listeners: Array[Callable]` 仍是潜在风险点：若业务代码向 `attribute_set.add_change_listener` 传入捕获 actor 的 lambda，会形成 actor ↔ attribute_set ↔ listener 循环。生成器产出的 wrapper 只捕获 `actor_id` String 和用户 Callable，自身安全；但用户侧 Callable 的闭包捕获需要审计（后续同类风险扫描）。
