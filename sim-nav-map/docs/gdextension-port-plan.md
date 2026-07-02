# 刀⑤ GDExtension 铸模 — 移植方案（2026-07-02 用户批准；**2026-07-03 M0-M5 全部完成 ✅**）

> 完成实况：M0 工具链 / M1 双平台 hello-world（wasm 浏览器 CDP 实证）/ M2 格网+射线表
> 逐字节 / M3 长径全链逐字段 / M4 移动热路径 600 tick 逐位（trig double-then-narrow
> 精确修复，零 ε）/ M5 真后台规划（固定延迟 T+1 收割 + 飞行中冻结守卫）。
> 每里程碑 codex review findings 全修。实测数字进 capability-envelope.md native 节。
> 风险登记核销：wasm 链 ✅ 排雷通过；trig ULP ✅ 精确修复（预案 ε 判据未动用）；
> godot-cpp v10 master pin ✅ 稳定；Web 无线程 → 按预期回退同步同调度。

> **人话版**（给回头看的人）：
> - 三角函数精度：引擎和 C++ 库算 sin/cos 偶尔差最后一位精度，600 帧累积
>   会让两边模拟走偏；换算法（先按更高精度算再折算）后 20 万次测试零差异，
>   风险已排除。
> - 用法：这是代码开关不是场景按钮——`use_native`/`use_native_solver`
>   默认 false，高性能项目在代码里手动设 true。开 native 后一批寻路指令
>   会攒齐了下一帧一起到（原来陆续到），这个节奏差异你已批准。
> - native 测试组只在 Windows/Web 能跑，但这台机器全程 Windows 开发 +
>   二进制已 commit，所以 2026-07-03 起并入 `-Required` 常规必跑
>   （`simnav/native` + `dota2lab/native`，共 6 个 smoke）。

寻路核心 + 分离求解热路径铸成 C++ GDExtension。战略定位（用户原话）：最底层设施，
跨项目长期复用；解锁真后台线程规划（GDScript 线程两次验尸判死，死因语言层全局锁）。
**C++ 是可切换后端，GDScript 是永久默认实现与参照真值机** —— 高性能需求的项目才开。

## 用户拍板（2026-07-02，逐条问答确认）

| # | 问题 | 拍板 |
|---|---|---|
| 1 | M0 工具链清单（SCons / emsdk → D:\emsdk / 4.7 导出模板 / godot-cpp） | ✅ 批准按清单装（批准时 emsdk 写 4.0.11，M1 实测官方模板为 4.0.20 后已按下方 pin 表纠正） |
| 2 | lab 默认后端 | ✅ GDScript 默认；native 走专用 smoke/探针 + lab UI 运行时切换钮 |
| 3 | 编译产物（.dll/.wasm）入库 | ✅ commit 进 submodule，跨项目即拉即用 |
| 4 | M5 线程模式 plan 到达节奏 | ✅ 允许与 GDScript 时间切片不同（各自完全确定；切后端 = 允许 plan 延迟特性不同） |

前置对齐（任务简报，已口头复确认）：范围 = 寻路核心 + 分离求解热路径；GDScript 真值机
保留 A/B 逐位对拍；wasm 先排雷再正式移植；工具链安装先征同意。

## 架构

**双后端可切换**：扩展注册 `SimNavNative*` 类家族，切换点在项目 adapter 层
（lab：`Dota2LabPathfinderWrapper.use_native` + `Dota2LabMotionEngine.use_native_solver`）。
消费方类型签名不动 —— native 结果在 plan 粒度（每 tick 1-4 次）转回 GDScript DTO。

**边界军规**：整查询进出（一次 plan 一次跨界）；整 tick 进出（M4 移动热路径每 tick 一次
mega call，SoA packed arrays，单位真相仍在 GDScript `Dota2LabUnit`）；禁止每格/每单位回调穿边界。

**移植范围**：

| 进 C++ | 留 GDScript |
|---|---|
| SimNavMap 格网（三层 navcell 数据/terrain tile/registry/dirty/静态障碍存储+空间索引+栅格化/坐标） | SimNavVertexPathfinder（短径） |
| SimNavJumpPointCache（bake + 4 射线表 + 增量修复） | 动态单位障碍入图 API（fable 设计单位不进图） |
| SimNavLongPathfinder 全链（JPS+/astar-excluded/精修/diagnostics） | validate_movement_line / validate_unit_line DTO 版 |
| SimNavHierarchicalPathfinder（chunk 洪泛/edges/global regions/reachability/canonicalize） | 0ad lab 全部 |
| Facade 子集（recompute_dirty flush / query_reachability / compute_path_result / movement_line_clear / diagnostics） | 既有 GDScript 栈全部原样保留（真值机） |
| Motion 热路径（Phase A 转向/步进/接触转向 + Phase B 分离全套，brute/hashed 双路径 + 16 阈值语义） | Phase C 看门狗、order 生命周期、plan 换入、事件 |
| PathRequestQueue native（long-path，M5 真线程） | |

**目录与产物**：源码 `native/`（src + SConstruct + setup.ps1；godot-cpp 克隆 gitignored）；
产物 `bin/`（committed）+ `simnav_native.gdextension`。

## 里程碑（每步收尾：A/B → 56 smoke 全绿 → 性能数字 → codex review → 修 findings → submodule commit + 主仓 bump）

- **M0 工具链**：清单安装 + godot-cpp Windows 编译通过
- **M1 hello-world 排雷**：Windows .dll 编辑器/headless 加载 + Emscripten（版本见下方
  pin 表，4.0.20）编 wasm（nothreads）+ Extension Support web 导出 + headless Chrome 验证。
  **wasm 不通 = 方案否决级**
- **M2 格网 + 路牌表**：A/B baked grid + 4 射线表逐字节（含脏修复后）
- **M3 长径全链 + hierarchical + flush**：A/B 万级射线穷举 + 全查询矩阵 + 500 segment +
  connectivity 网格 + 地形改变复测；wrapper 接 use_native；性能数字第一批
- **M4 移动热路径**：同一组预计算路径喂两引擎，600 tick 轨迹逐位 + 离散结局全同；
  trig ULP 差异逐点记录征拍板，不悄悄放宽
- **M5 真后台规划（⑤ 完全体）**：C++ worker + 读写锁（flush 写锁/查询读锁）；
  **固定延迟收割**：tick T 入队恰好 T+1 可见，没算完阻塞等（复刻 core-019 教训，录像安全）；
  Web 无线程自动回退 C++ 速度时间切片
- **收尾**：capability-envelope 性能数字、task-queue 1d-⑤ ✅、native README、public-api native 节

## A/B 与 float 语义军规

- 整数核心（射线表/JPS/hierarchical/成本/启发式）：**逐位相等硬验收**
- float 路径：GDScript 标量=double、Vector2 分量=float32；C++ 标量一律 double、表达式逐句照抄
  （窄化点由 godot-cpp 算子签名自动对齐）
- trig（仅 M4 facing 数学）：先按逐位测；有 ULP 差则降级为 ε 有界轨迹 + 离散结局逐位，
  差异逐个记录征拍板
- 探针 = 临时 tscn 跑完删；native 常驻 smoke 单独建组，不动既有 56 个 GDScript 锚

## 工具链 pin 记录

| 组件 | 版本/落点 | 备注 |
|---|---|---|
| MSVC | VS2022 Community（已装） | SCons 自动发现 |
| SCons | 4.10.1（miniconda pip） | |
| Emscripten | **4.0.20** → D:\emsdk | = 官方 4.7 web 模板实际编译版本（boot banner "Build configuration" 实证；4.7 分支 CI yml 写 4.0.11 已过时，勿信） |
| Godot 导出模板 | 4.7.stable 官方 tpz | 含 web dlink 模板 |
| godot-cpp | **v10 master `ba0edfe`**（clone 到 native/godot-cpp，gitignored） | rc1 有 #1941（4.7 新增 UINT8_MAX 等全局常量与 stdint 宏冲突 → 生成头语法错误），修复 `67a0b191d3` 在 rc1 之后，故 pin master；API 用本机 `godot --dump-extension-api` |

## 风险登记

| 风险 | 等级 | 处置 |
|---|---|---|
| wasm 构建链不通 | 方案否决级 | M1 首位排雷，不通不进 M2 |
| Web 无线程（默认 nothreads 模板） | 已知限制 | M5 Web 回退时间切片；threads 变体待真需要 |
| godot-cpp v10 master pin | 低 | M1 实测；备选 godot-4.5-stable tag（官方向前兼容承诺覆盖 4.7） |
| trig ULP → M4 非逐位 | 中 | ε 判据 + 逐点记录征拍板 |
| 体量 ~5.7k 行 GDScript → ~7-8k C++ | 工程量 | 里程碑切块，每块 A/B 焊死再前进 |
