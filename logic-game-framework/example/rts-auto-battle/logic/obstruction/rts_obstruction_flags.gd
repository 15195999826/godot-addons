## RtsObstructionFlags - Obstruction shape EFlags 位掩码常量 (M2 引入)
##
## 0 A.D. `ICmpObstructionManager.h:78-86` EFlags 枚举的 GDScript 复刻。表示一个 obstruction
## shape 的语义属性 — 它对寻路 / 建造 / 移动 / 状态切换分别有什么影响。
##
## **M0 阶段**: rts_buildings.gd 硬编码 `1 << 3` (= BLOCK_PATHFINDING) 临时占位。
## **M2 阶段** (本文件): 引入完整 6 个 flag, 替换硬编码; 后续 ObstructionManager / Filter / Pathfinder
##                       一律走这里的常量。
##
## **典型组合**:
##   - 单位 (unit shape): BLOCK_MOVEMENT (移动中其它单位避开它)
##   - 建筑 (static shape): BLOCK_PATHFINDING | BLOCK_FOUNDATION (盖建筑时挡 + 寻路时挡)
##   - 树 / 资源点: BLOCK_PATHFINDING | DELETE_UPON_CONSTRUCTION (挡寻路, 但建筑可盖在上面砍掉)
##
## **0 A.D. 对照**: `ICmpObstructionManager.h:78-86`
##   FLAG_BLOCK_MOVEMENT          = (1 << 0)
##   FLAG_BLOCK_FOUNDATION        = (1 << 1)
##   FLAG_BLOCK_CONSTRUCTION      = (1 << 2)
##   FLAG_BLOCK_PATHFINDING       = (1 << 3)
##   FLAG_MOVING                  = (1 << 4)
##   FLAG_DELETE_UPON_CONSTRUCTION= (1 << 5)
##
## **决策来源**:
##   - data-structures.md §2.2 (EFlags 枚举)
##   - milestones/M2-obstruction-manager.md §M2.1 步骤 1
class_name RtsObstructionFlags


## 阻止单位穿过 (动态 obstruction; unit motion 用)。
const BLOCK_MOVEMENT: int           = 1 << 0

## 阻止盖 foundation (新建筑放置预检; placement command 用)。
const BLOCK_FOUNDATION: int         = 1 << 1

## 阻止施工进度 (foundation → 完工 阶段; 单位走到上面会暂停施工)。
const BLOCK_CONSTRUCTION: int       = 1 << 2

## 阻止 A* 选这条路 (静态 obstruction; rasterize 进 NavcellGrid 用)。
const BLOCK_PATHFINDING: int        = 1 << 3

## 单位正在移动 (unit motion 状态切换; M2 阶段写入, M7 unit motion 重写时消费)。
const MOVING: int                   = 1 << 4

## 这个 entity 在 foundation 建到上面时删除 (例: 树 → 砍掉 → 建筑落地)。
const DELETE_UPON_CONSTRUCTION: int = 1 << 5
