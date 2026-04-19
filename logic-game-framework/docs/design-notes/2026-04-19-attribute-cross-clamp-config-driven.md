# pre_change 闭包循环根治：config 驱动的跨属性 clamp

**日期**：2026-04-19（同日第三轮）
**范围**：`core/attributes/raw_attribute_set.gd`、`core/attributes/base_generated_attribute_set.gd`、`scripts/attribute_set_generator_script.gd`、`example/attributes/attributes_config.gd`、`example/attributes/generated/hex_battle_character_attribute_set.gd`、`example/hex-atb-battle/character_actor.gd`、`tests/core/attributes/attribute_set_test.gd`
**前置**：`2026-04-19-structural-cycles-weakref.md`（循环 C/D/E）

---

## 背景

上一轮消除循环 C/D/E 后，`smoke_strike` 仍残留 38 resources / 112 leaked instance，battle 对象图无法完全释放。上轮 design note 末尾记录「未尽事项」：battle 在 `_instances.clear()` 后仍有 1 个真实外部强引用，候选包括 Action Callable / event 字典 / UGridMap occupant。

## 定位：PREDELETE probe + weakref 追踪

本轮 probe 策略分两步：

**Step 1 — battle 自身生命周期**：在 `GameplayInstance._init` / `_notification(NOTIFICATION_PREDELETE)` 打 id，`shutdown` 三个阶段（before_end / after_end / after_clear）打 refcount。

结果：battle 在 smoke_strike `_run_test` 返回后、`_ready` 末尾即 `GONE` ✅。说明 battle 本身没泄漏，但 LGF 对象图的其他部分仍拖着资源。

**Step 2 — actor 生命周期**：在 smoke_strike 里保留 `_battle_weakref` / `_caster_weakref` / `_target_weakref`，`_ready` 末尾检查：

```
PROBE post_run_test: battle GONE (good)
PROBE post_run_test: caster STILL ALIVE refcount=2
PROBE post_run_test: target STILL ALIVE refcount=2
```

🎯 **actor 独立泄漏**，battle 释放了但 actor 没。每个 actor refcount=2：一个来自 `probe.get_ref()` 的临时强引用，另一个来自某个未知持有者。

## 根因：`CharacterActor._setup_attribute_constraints` 的闭包循环

`character_actor.gd:68-73`：

```gdscript
func _setup_attribute_constraints() -> void:
    attribute_set.set_pre_change(func(attr_name: String, inout_value: Dictionary) -> void:
        if attr_name == "hp":
            var max_hp := attribute_set.max_hp   # ← self.attribute_set.max_hp
            if inout_value["value"] > max_hp:
                inout_value["value"] = max_hp
    )
```

GDScript lambda 里 `attribute_set` 标识符解析为 `self.attribute_set`，lambda **隐式捕获 self（CharacterActor）**。形成循环：

```
CharacterActor.attribute_set → HexBattleCharacterAttributeSet (extends RawAttributeSet)
HexBattleCharacterAttributeSet._raw._pre_change_callback → Callable
Callable → (闭包捕获 self) → CharacterActor
```

注释掉 `_setup_attribute_constraints` 的 lambda 后（保留函数签名），smoke_strike 从 `112 leaked / 38 resources` 一步到位 `0 / 0`。**此循环解释 smoke_strike 全部剩余泄漏。**

## 类别与上轮循环 C/D/E 的关系

| 循环 | 表层模式 | 本质 |
|---|---|---|
| C: `AbilityComponent._ability` | 字段缓存 | 子对象存 owner 强引用 |
| D: `AbilityExecutionInstance._game_state_provider` | 字段缓存 | 子对象存 container 强引用 |
| E: `System._instance` | 字段缓存 | 子对象存 container 强引用 |
| **本轮：`_pre_change_callback`** | **Callable 捕获** | **子对象存的 Callable 的闭包捕获了 owner** |

C/D/E 是「显式字段持有」，本轮是「Callable 闭包隐式持有」。统一原则仍成立：**子对象回指 owner 禁止强引用**，但变体扩展到闭包捕获层面，不再仅限字段。

## 关键架构选择：为什么不直接修 API（A 方案），也不用虚方法（E 方案）

讨论中考虑过：

**A. 改 `set_pre_change` callback 签名，由框架传 `self`**
```gdscript
_pre_change_callback.call(self, attr_name, inout_value)
# callback: func(attr_set, attr_name, inout_value)
```
否决：签名 `func(attr_set, ...)` 暗示"generic callback 可以处理任意 attr_set"，但框架契约是「只传 self」。语义与签名矛盾，code smell。

**E. 把 callback 改成虚方法，子类 override**
```gdscript
# RawAttributeSet
func _pre_change(attr_name, inout_value): pass  # 虚方法

# HexBattleCharacterAttributeSet
func _pre_change(attr_name, inout_value):
    if attr_name == "hp" and inout_value["value"] > max_hp:
        inout_value["value"] = max_hp
```
否决：`HexBattleCharacterAttributeSet` 是 **AttributeSetGeneratorScript 自动生成** 的文件，头部有「⚠️ AUTO-GENERATED FILE - DO NOT MODIFY」警告。要让子类 override 必须扩生成器 + 设计 config schema 描述 override 方法体（DSL 化 clamp 逻辑），成本非平凡。

**F. 运行时声明式 API（`register_cross_attr_clamp`，Actor 手写调用）**
可行但仍把"约束声明"漂在 Actor 里，与 config 已在描述 `baseValue`/`minValue`/`maxValue`/`derived` 的既有风格不符。

**G（本轮选择）. config 驱动 + 生成器自动注册**
把 clamp 声明和其它属性元数据一样归属 config，生成器产出 runtime 注册调用。零 Callable，零闭包，零外部注入。

## 实现

### 1. `RawAttributeSet`：删 callback API，加声明式 API

```gdscript
# 删
var _pre_change_callback: Callable = Callable()
func set_pre_change(callback: Callable): ...
func clear_pre_change(): ...

# 加
var _cross_attr_clamps: Array[Dictionary] = []   # 每项 {target, bound, source}

func register_cross_attr_clamp(target: String, bound: String, source: String) -> void:
    Log.assert_crash(bound == "max" or bound == "min", ...)
    Log.assert_crash(has_attribute(target), ...)
    Log.assert_crash(has_attribute(source), ...)
    _cross_attr_clamps.append({"target": target, "bound": bound, "source": source})
    _dirty_set[target] = true
    _cache.erase(target)

func clear_cross_attr_clamps() -> void: ...

func _apply_cross_attr_clamps(attr_name: String, value: float) -> float:
    var result := value
    for clamp_cfg in _cross_attr_clamps:
        if clamp_cfg["target"] != attr_name:
            continue
        var ref_value := get_breakdown(clamp_cfg["source"]).current_value
        if clamp_cfg["bound"] == "max" and result > ref_value:
            result = ref_value
        elif clamp_cfg["bound"] == "min" and result < ref_value:
            result = ref_value
    return result
```

`get_breakdown` 原「步骤 2 调 callback」替换为 `_apply_cross_attr_clamps`。读 source 走 `get_breakdown(source)` → 命中现有 `_computing_set` 循环检测，fallback 到 cache/base。

### 2. Config schema 扩展：`maxRef` / `minRef`

```gdscript
# example/attributes/attributes_config.gd
"HexBattleCharacter": {
    "hp": { "baseValue": 100.0, "minValue": 0.0, "maxRef": "max_hp" },
    "max_hp": { "baseValue": 100.0, "minValue": 1.0 },
    ...
}
```

命名与 `minValue`/`maxValue` 同族：静态常数版叫 `minValue`/`maxValue`，动态引用另一属性叫 `minRef`/`maxRef`。允许与静态 clamp 并存（先静态后动态，取更严）。

### 3. 生成器：识别 ref 字段，产出注册调用

```gdscript
# attribute_set_generator_script.gd::_generate_set 末尾
for attr_name in base_attr_names:
    var cfg: Dictionary = base_attrs[attr_name]
    for field_name in ["maxRef", "minRef"]:
        if not cfg.has(field_name) or cfg[field_name] == null:
            continue
        var source_attr := str(cfg[field_name])
        if not base_attrs.has(source_attr) and not derived_attrs.has(source_attr):
            push_error(...)  # 构建期 validate
            continue
        var bound := "max" if field_name == "maxRef" else "min"
        lines.append("\t_raw.register_cross_attr_clamp(\"%s\", \"%s\", \"%s\")" % [...])
```

生成的 `hex_battle_character_attribute_set.gd::_init` 末尾多一行：
```gdscript
_raw.register_cross_attr_clamp("hp", "max", "max_hp")
```

### 4. `CharacterActor` 去构造依赖

```gdscript
# 删
_setup_attribute_constraints()   # 调用
func _setup_attribute_constraints() -> void: ...  # 函数
```

约束完全下沉到 `HexBattleCharacterAttributeSet.new()` 里（生成器产出的 `_init` 调了 `register_cross_attr_clamp`）。CharacterActor 不再承载约束语义。

## 验证

| 测试 | 上轮基线 | 本轮基线 | 本轮后 |
|---|---|---|---|
| LGF 单元 59/59 | 25 resources | 33 leaked / 14 resources | **24 leaked / 11 resources** |
| `smoke_strike` | 38 resources | 112 leaked / 38 resources | **0 / 0** 🎯 |
| `smoke_frontend_main` | 46 resources | 46 resources | **0 / 0** 🎯 |

smoke 两项**彻底归零**。上轮 handoff 的「未尽事项」全部解决。

LGF 单元测试的 11 resources 泄漏全部是 `tests/core/**/*_test.gd` 这批 GDScript 文件被 test framework 保留，与生产代码无关，独立问题不在本轮范围。

## 为什么数字下降幅度大

上轮 design note 分析过「数字降幅受未知循环压制」—— 确实如此。本轮定位的闭包循环把 actor 对象图完全锁死，`RefCounted` 无循环 GC，整个 battle 的 actor + ability + component + attribute_set + tag_container 全部跟着泄漏。一旦断开：
- battle 对象图完全释放
- 12 个 `Resource still in use` (actor 相关) 全部解除
- 所有由 actor 间接持有的 RefCounted 实例释放

这也复盘了为什么上轮 smoke_strike 只降 3（41→38）：循环 D 把 `_game_state_provider` 字段删除释放了 battle，但 actor 仍被 pre_change lambda 锁死 —— battle 释放后 actor 依旧活，全链条还是泄漏。

## 方法论总结

1. **PREDELETE probe 要查到"哪些对象没死"，不只是"数字多少"。** 上轮统计 refcount 时只追 battle，以为外部强引用在拖 battle；本轮 weakref 三件套（battle/caster/target）直接揭露是 actor 单独泄漏，battle 已正常释放。
2. **Callable 闭包是 C/D/E 同类循环的变体**。子对象持 Callable 字段时，必须追问 Callable 的闭包捕获了什么。GDScript 里 lambda 对 `self.xxx` 字段的访问是**隐式 self 捕获**，形式上像"用外部变量"，实际是强引用。
3. **API 的"灵活性"要和"安全可用性"匹配**。`_pre_change_callback` 承诺 Callable 灵活，但 call 参数窄（只有 `attr_name`/`inout_value`），想做副作用只能从闭包捕外部 —— 而外部捕获就撞循环陷阱。签名灵活 ≠ 实际可灵活使用。
4. **声明式 API 是闭包陷阱的结构解**。把"注入 Callable"换成"注入 String 参数"，问题从 GDScript 内存管理层消失。config 驱动进一步把它从代码层移到数据层。
5. **约束语义归属 config**。属性元数据（base/min/max/derived/ref）集中在 config 是 single source of truth 的自然形态，生成器负责 runtime 装配。避免"一半声明式一半运行时补充"的分裂。

## 遗留

- `_listeners: Array[Callable]` 仍是闭包捕获潜在风险点。生成器自动产出的 wrapper 只捕获 `actor_id` String + 用户 Callable，自身安全；但用户侧 Callable 若捕获 actor 仍会循环。后续同类风险审计需要覆盖此 API。
- 项目内 85 个 lambda（`grep "func(" addons/logic-game-framework/ *.gd`）尚未全量审计，其中多数是 action/timeline 里短寿命闭包（参数即用即弃），但存到生命周期较长字段/数组的 Callable 都需要检查。
