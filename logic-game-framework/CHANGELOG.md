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
