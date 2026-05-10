# 0 A.D. 源码本地参考副本 — 拉取与使用

> **不进仓**(被 `addons/sim-nav-map/.gitignore` 屏蔽 + 0 A.D. 是 GPL-2.0,我们当前许可证未对齐)。
> 每个开发者本地自己拉一份,仅供 `sim-nav-map` 开发期间对照参考用。

## 位置

`addons/sim-nav-map/docs/references/0ad-source/`。

## 拉取方法(Sparse + Partial Clone)

```bash
# 1. 启用 Windows 长路径(防 260 字符上限)
git config --global core.longpaths true

# 2. Partial clone(只拉 commit/tree 元数据,blob 按需)
git clone --depth=1 --filter=blob:none --sparse --no-checkout \
  https://gitea.wildfiregames.com/0ad/0ad.git \
  addons/sim-nav-map/docs/references/0ad-source

# 3. 配 sparse-checkout 只取 source/simulation2/ 子树
cd addons/sim-nav-map/docs/references/0ad-source
git sparse-checkout set --cone source/simulation2
git checkout
```

**结果**: ~9 MB 工作树 + ~1.3 MB .git。

## 关键文件位置

| Epic 文档引用 | 实际路径 |
|---|---|
| Pathfinding.h | `source/simulation2/helpers/Pathfinding.h` |
| Grid.h | `source/simulation2/helpers/Grid.h` |
| HierarchicalPathfinder.h/cpp | `source/simulation2/helpers/HierarchicalPathfinder.{h,cpp}` |
| LongPathfinder.h/cpp | `source/simulation2/helpers/LongPathfinder.{h,cpp}` |
| VertexPathfinder.cpp | `source/simulation2/helpers/VertexPathfinder.cpp` |
| PathGoal.h | `source/simulation2/helpers/PathGoal.h` |
| ICmpPathfinder.h | `source/simulation2/components/ICmpPathfinder.h` |
| ICmpObstructionManager.h | `source/simulation2/components/ICmpObstructionManager.h` |
| CCmpObstruction.cpp | `source/simulation2/components/CCmpObstruction.cpp` |
| CCmpObstructionManager.cpp | `source/simulation2/components/CCmpObstructionManager.cpp` |
| **CCmpUnitMotion 实现** | `source/simulation2/components/CCmpUnitMotion.h` + `CCmpUnitMotion_System.cpp`(注意 0 A.D. **没有** `CCmpUnitMotion.cpp`,实现拆在 .h + System.cpp) |
| CCmpUnitMotionManager.h | `source/simulation2/components/CCmpUnitMotionManager.h` |
| ICmpFootprint.h | `source/simulation2/components/ICmpFootprint.h` |
| CCmpFootprint.cpp | `source/simulation2/components/CCmpFootprint.cpp` |

## 升级 / 重新拉取

```bash
cd addons/sim-nav-map/docs/references/0ad-source
git fetch --depth=1
git reset --hard origin/main
```

## 来源说明 & 行号对齐注意

**官方源**: https://gitea.wildfiregames.com/0ad/0ad(默认分支 `main`)。GitHub 上的 `0ad/0ad` 仓库自 2024 起已 archived,我们直接用 gitea 官方源。

**⚠️ 与 Epic 文档里 github.com URL 的行号差异**: 部分老 Epic 文档里源码引用走的是 `github.com/0ad/0ad/blob/master/...` + 精确行号。GitHub mirror 的 `master` 是 archive 时刻的快照,行号固定;gitea `main` 是活分支,会持续推进。**对照源码时以"文件 + 函数/类名"定位,不要硬信 Epic 文档里的具体行号** — 行号只在 GitHub archive 那个 commit 上准。如果非要 byte-exact 对齐,改用 `git checkout <archive 时期的 commit>`。

## 删除(不再需要时)

```bash
rm -rf addons/sim-nav-map/docs/references/0ad-source
```
