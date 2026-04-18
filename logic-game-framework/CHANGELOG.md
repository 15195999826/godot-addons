# Changelog

本文件记录 Logic Game Framework 的重要变更。格式参考 [Keep a Changelog](https://keepachangelog.com/)。

- **Added** — 新增能力
- **Changed** — 行为或 API 变化
- **Fixed** — Bug 修复
- **Removed** — 移除
- **Deprecated** — 即将废弃

对于有架构推理的重大变更，在 `docs/design-notes/` 下会有对应长文，行末以链接引用。

---

## [Unreleased]

### Added
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

### 待处理
- Ability ↔ AbilityComponent 循环引用：`Ability._components[C]` 和 `C._ability` 形成结构性强引用循环，独立于 LifecycleContext 循环。本轮不修。smoke_strike 泄漏 44 → 41、smoke_frontend_main 60 → 57 下降幅度有限的主因是此循环仍在。后续用弱引用（`WeakRef`）或显式销毁方案解决。
