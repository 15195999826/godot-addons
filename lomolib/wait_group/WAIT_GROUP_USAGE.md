# WaitGroup 使用文档

## 概述

WaitGroup 是一个多任务同步工具，类似 Go 语言的 `sync.WaitGroup`，用于等待多个异步任务完成。

## 核心特性

- ✅ 简单的计数器机制（Add/Done）
- ✅ 支持 `await` 协程等待
- ✅ 支持链式回调 `next()`
- ✅ 自动生命周期管理
- ✅ 调试日志支持
- ⚠️ **非线程安全**（仅主线程使用）

## 快速开始

### 基本用法（await 方式）

```gdscript
func load_multiple_resources() -> void:
    # 创建 WaitGroup
    var result = WaitGroupManager.create_wait_group(&"LoadResources")
    var wg: LomoWaitGroup = result[1]

    # 添加 3 个任务
    wg.add(3)

    # 异步加载资源
    load_texture_async(wg)
    load_audio_async(wg)
    load_scene_async(wg)

    # 等待所有任务完成
    await wg.wait()

    print("所有资源加载完成！")


func load_texture_async(wg: LomoWaitGroup) -> void:
    await get_tree().create_timer(1.0).timeout
    # 加载纹理...
    wg.done(&"LoadTexture")


func load_audio_async(wg: LomoWaitGroup) -> void:
    await get_tree().create_timer(0.5).timeout
    # 加载音频...
    wg.done(&"LoadAudio")


func load_scene_async(wg: LomoWaitGroup) -> void:
    await get_tree().create_timer(2.0).timeout
    # 加载场景...
    wg.done(&"LoadScene")
```

### 链式回调（next 方式）

```gdscript
func process_batch_data() -> void:
    var result = WaitGroupManager.create_wait_group(&"ProcessBatch")
    var wg: LomoWaitGroup = result[1]

    wg.add(5)

    # 处理 5 个数据块
    for i in range(5):
        process_data_chunk(i, wg)

    # 所有任务完成后执行回调
    wg.next(func():
        print("批量处理完成！")
        save_results()
    )


func process_data_chunk(index: int, wg: LomoWaitGroup) -> void:
    await get_tree().create_timer(randf_range(0.5, 2.0)).timeout
    print("数据块 %d 处理完成" % index)
    wg.done(&"Chunk_%d" % index)
```

### 动态添加任务

```gdscript
func download_files(file_urls: Array) -> void:
    var result = WaitGroupManager.create_wait_group(&"DownloadFiles")
    var wg: LomoWaitGroup = result[1]

    # 动态设置任务数量
    wg.add(file_urls.size())

    for url in file_urls:
        download_file(url, wg)

    await wg.wait()
    print("所有文件下载完成！")


func download_file(url: String, wg: LomoWaitGroup) -> void:
    # 模拟下载
    await get_tree().create_timer(1.0).timeout
    print("下载完成: %s" % url)
    wg.done(&"Download_%s" % url)
```

## API 参考

### WaitGroupManager（AutoLoad 单例）

| 方法 | 说明 |
|------|------|
| `create_wait_group(name: StringName) -> Array` | 创建 WaitGroup，返回 `[id, wg]` |
| `find_wait_group(id: int) -> LomoWaitGroup` | 根据 ID 查找 WaitGroup |
| `cleanup_all_wait_groups()` | 清理所有活跃的 WaitGroup |

### LomoWaitGroup

| 方法 | 说明 |
|------|------|
| `add(delta: int = 1)` | 增加等待计数 |
| `done(task_name: StringName, enable_log: bool)` | 完成一个任务 |
| `wait()` | 等待所有任务完成（协程） |
| `next(callback: Callable)` | 完成后执行回调 |
| `set_cancelled()` | 取消执行（不触发回调） |
| `get_counter() -> int` | 获取当前计数 |
| `is_completed() -> bool` | 是否已完成 |

| 信号 | 说明 |
|------|------|
| `completed(wg_id: int)` | 所有任务完成时触发 |

## 常见场景

### 1. 游戏初始化（加载多个系统）

```gdscript
func initialize_game() -> void:
    var result = WaitGroupManager.create_wait_group(&"GameInit")
    var wg: LomoWaitGroup = result[1]

    wg.add(4)

    init_audio_system(wg)
    init_save_system(wg)
    init_network(wg)
    init_ui_system(wg)

    await wg.wait()

    print("游戏初始化完成，开始游戏！")
    start_game()
```

### 2. 关卡加载（地形 + 敌人 + 道具）

```gdscript
func load_level(level_id: int) -> void:
    var result = WaitGroupManager.create_wait_group(&"LoadLevel_%d" % level_id)
    var wg: LomoWaitGroup = result[1]

    wg.add(3)

    spawn_terrain(level_id, wg)
    spawn_enemies(level_id, wg)
    spawn_items(level_id, wg)

    await wg.wait()

    start_level()
```

### 3. 保存多个玩家数据

```gdscript
func save_all_players(players: Array) -> void:
    var result = WaitGroupManager.create_wait_group(&"SavePlayers")
    var wg: LomoWaitGroup = result[1]

    wg.add(players.size())

    for player in players:
        save_player_data(player, wg)

    wg.next(func():
        show_notification("所有玩家数据已保存")
    )
```

## 注意事项

### ⚠️ 非线程安全
```gdscript
# ❌ 错误：不要在子线程调用 done()
func worker_thread(wg: LomoWaitGroup) -> void:
    # ... 子线程工作 ...
    wg.done()  # 线程不安全！

# ✅ 正确：在主线程调用 done()
func worker_thread(wg: LomoWaitGroup) -> void:
    # ... 子线程工作 ...
    call_deferred("_on_thread_done", wg)

func _on_thread_done(wg: LomoWaitGroup) -> void:
    wg.done()  # 主线程调用
```

### ⚠️ 避免计数器失衡
```gdscript
# ❌ 错误：Add 和 Done 数量不匹配
var wg = WaitGroupManager.create_wait_group(&"Test")[1]
wg.add(2)
wg.done()  # 只调用 1 次，永远不会完成！

# ✅ 正确：确保 Add 和 Done 数量一致
var wg = WaitGroupManager.create_wait_group(&"Test")[1]
wg.add(2)
wg.done()
wg.done()  # 完成！
```

### ⚠️ 不要重复使用 WaitGroup
```gdscript
# ❌ 错误：完成后再次使用
var wg = WaitGroupManager.create_wait_group(&"Test")[1]
wg.add(1)
wg.done()
# ... 稍后 ...
wg.add(1)  # 计数器从 -1 变成 0，行为未定义！

# ✅ 正确：每次创建新的 WaitGroup
func process_twice() -> void:
    await process_once()
    await process_once()

func process_once() -> void:
    var wg = WaitGroupManager.create_wait_group(&"Process")[1]
    wg.add(1)
    # ... 处理 ...
    wg.done()
    await wg.wait()
```

## 对比 C++ 实现

| 特性 | C++ 版本 | GDScript 版本 |
|------|---------|--------------|
| 计数器 | `int32 Counter` | `int _counter` |
| 异步等待 | `TPromise<void> + Future` | Godot `Signal + await` |
| 完成回调 | `TFunction<void()>` | `Callable` |
| 调试日志 | `UE_LOG` | `Log.debug()` |
| 线程安全 | ⚠️ 注释提示非线程安全 | ⚠️ 明确标注非线程安全 |

## 性能建议

- 小任务（< 10 个）：直接使用 WaitGroup
- 中等任务（10-100 个）：考虑分批处理
- 大量任务（> 100 个）：使用线程池 + 分批 WaitGroup

## 完整示例

参考 `addons/lomolib/examples/wait_group_demo.gd`（待创建）
