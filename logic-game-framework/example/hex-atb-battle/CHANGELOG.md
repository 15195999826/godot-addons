# Changelog — Hex ATB Battle 示例

本文件记录 hex-atb-battle 示例的重要变更。格式参考 [Keep a Changelog](https://keepachangelog.com/)。

- **Added** — 新增能力
- **Changed** — 行为或 API 变化
- **Fixed** — Bug 修复
- **Removed** — 移除
- **Deprecated** — 即将废弃

框架级变更见 `addons/logic-game-framework/CHANGELOG.md`；本文件只记 hex 示例自身的玩法 / 技能 / 表演层变更。

---

## [Unreleased]

_（暂无）_

---

## [Baseline] — 2026-05-31

文档 baseline 重置。此前逐阶段变更（hex 技能各 Phase、表演层迁移、设计评审轮次）已归档为快照——完整轨迹见 git 历史与框架 CHANGELOG。以下为当前 hex 示例的能力快照。

### 战斗

- 6v6 ATB 战斗，9×9 hex grid，六职业（priest / warrior / archer / mage / berserker / assassin）随机站位 + 全体 inspire buff。
- `HexDemoWorldGameplayInstance`（demo 行为）/ `SkillPreviewWorldGI`（沙盒）/ `HexBattleProcedure`（ATB / AI / 胜负 / 投射物广播）。
- 死者留 world registry（清 grid 占用、保留 `hex_position`），不 `remove_actor`。

### 技能

- `logic/abilities/`：~33 active + ~11 buffs + ~14 passives；Timeline keyframe 驱动 Action；标准门控四件套 + `HexBattleCooldownSystem` helper；`HexBattleSkillHelpers.caster_atk_damage` resolver。
- 状态控制走 example 层 Gateway（`HexBattleGatewayPolicyProvider`）；cast eligibility 走 ability metadata `ALLOWED_TARGET_KINDS`。
- 装备攻击特效 Phase G V1：`PreBasicAttackEvent` / `BasicAttackLandedEvent`、Daedalus 暴击 passive、装备 grant/revoke。
- skill-preview 沙盒 + 主仓 `SkillValidator` 五级校验（Stage 5 advisory）。

### 表演层

- `FrontendWorldView`（响应式观察 world 结构）+ `FrontendBattleAnimator`（消费 event timeline）；事件 vs 状态边界见 README。
- 战后 View ↔ Logic 终态对账 oracle（debug-only）。

> 设计铁律 / 事件-状态边界 / 技能模式 / 未来规划见 `README.md`；活契约见 `docs/reference/`。
